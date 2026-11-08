import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:printing/printing.dart';

/// Funzione che renderizza una pagina in immagine (sostituibile nei test).
typedef PageRasterizer = Future<ui.Image?> Function(Uint8List pdf, int page, double dpi);

Future<ui.Image?> printingRasterizer(Uint8List pdf, int page, double dpi) async {
  await for (final raster in Printing.raster(pdf, pages: [page], dpi: dpi)) {
    return raster.toImage();
  }
  return null;
}

/// Render delle pagine con cache e una coda: al massimo due render insieme.
///
/// La cache tiene al massimo [maxCached] pagine (le meno usate di recente vengono liberate).
/// Chi riceve un'immagine ne riceve una copia ([ui.Image.clone]) e deve chiamarne `dispose`:
/// così la cache può liberare le sue senza rompere le pagine ancora mostrate.
class PageRenderer {
  PageRenderer(this.pdf, {PageRasterizer? rasterizer, this.maxCached = 10})
      : _rasterize = rasterizer ?? printingRasterizer;

  final Uint8List pdf;
  final int maxCached;
  final PageRasterizer _rasterize;
  final Map<int, ui.Image> _cache = {};
  final Map<int, double> _cachedDpi = {};
  final Map<int, Future<ui.Image?>> _inFlight = {};
  final Map<int, double> _inFlightDpi = {};
  int _running = 0;
  final List<Completer<void>> _waiting = [];
  bool _disposed = false;

  /// Copia dell'immagine in cache (da liberare con `dispose`), oppure null.
  ui.Image? cached(int page) {
    final img = _cache.remove(page);
    if (img == null) return null;
    _cache[page] = img; // in fondo: usata di recente
    return img.clone();
  }

  int get cachedCount => _cache.length;

  /// Immagine della pagina ad almeno [dpi]; riusa la cache se abbastanza nitida.
  /// Restituisce una copia da liberare con `dispose`.
  Future<ui.Image?> render(int page, double dpi) {
    final have = _cachedDpi[page];
    if (have != null && have >= dpi * 0.85 && _cache.containsKey(page)) return Future.value(cached(page));
    ui.Image? copy(ui.Image? img) => img == null || _disposed ? null : img.clone();
    final current = _inFlight[page];
    // Un render già in corso va bene solo se abbastanza nitido (es. la miniatura a 48 dpi non basta
    // per la pagina grande): altrimenti se ne accoda uno nuovo, che parte quando finisce l'altro.
    if (current != null && (_inFlightDpi[page] ?? 0) >= dpi * 0.85) return current.then(copy);
    final job = current == null ? _run(page, dpi) : current.then((_) => _run(page, dpi), onError: (Object _) => _run(page, dpi));
    late final Future<ui.Image?> shared;
    // Attenzione: la callback non deve restituire il future (whenComplete lo aspetterebbe).
    shared = job.whenComplete(() {
      if (identical(_inFlight[page], shared)) {
        _inFlight.remove(page);
        _inFlightDpi.remove(page);
      }
    });
    _inFlight[page] = shared;
    _inFlightDpi[page] = dpi;
    return shared.then(copy);
  }

  Future<ui.Image?> _run(int page, double dpi) async {
    while (_running >= 2) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      if (_disposed) return null;
      final img = await _rasterize(pdf, page, dpi);
      if (img == null || _disposed) {
        img?.dispose();
        return null;
      }
      _cache.remove(page)?.dispose();
      _cache[page] = img;
      _cachedDpi[page] = dpi;
      while (_cache.length > maxCached) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest)?.dispose();
        _cachedDpi.remove(oldest);
      }
      return img;
    } catch (_) {
      return null;
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  void dispose() {
    _disposed = true;
    for (final i in _cache.values) {
      i.dispose();
    }
    _cache.clear();
  }
}
