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
class PageRenderer {
  PageRenderer(this.pdf, {PageRasterizer? rasterizer}) : _rasterize = rasterizer ?? printingRasterizer;

  final Uint8List pdf;
  final PageRasterizer _rasterize;
  final Map<int, ui.Image> _cache = {};
  final Map<int, double> _cachedDpi = {};
  final Map<int, Future<ui.Image?>> _inFlight = {};
  int _running = 0;
  final List<Completer<void>> _waiting = [];
  bool _disposed = false;

  ui.Image? cached(int page) => _cache[page];

  /// Immagine della pagina ad almeno [dpi]; riusa la cache se abbastanza nitida.
  Future<ui.Image?> render(int page, double dpi) {
    final have = _cachedDpi[page];
    if (have != null && have >= dpi * 0.85) return Future.value(_cache[page]);
    // Attenzione: la callback non deve restituire il future (whenComplete lo aspetterebbe).
    return _inFlight[page] ??= _run(page, dpi).whenComplete(() {
      _inFlight.remove(page);
    });
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
