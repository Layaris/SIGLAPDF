import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import '../core/l10n/l10n.dart';

/// Colore dell'inchiostro dopo lo scontorno: originale oppure ricolorato.
enum InkRecolor { original, blue, black }

/// Risultato dello scontorno: PNG trasparente ritagliato.
class CutoutResult {
  const CutoutResult({required this.png, required this.width, required this.height, required this.threshold});
  final Uint8List png;
  final int width;
  final int height;

  /// Soglia usata (0–255): i pixel più scuri diventano inchiostro.
  final int threshold;
}

/// Parametri dello scontorno, serializzabili per `compute`.
class CutoutRequest {
  const CutoutRequest(
    this.bytes, {
    this.threshold,
    this.recolor = InkRecolor.original,
    this.softness = 18,
    this.maxSide = 1600,
  });

  final Uint8List bytes;

  /// Null = soglia automatica di Otsu.
  final int? threshold;
  final InkRecolor recolor;

  /// Ampiezza (in livelli di grigio) della sfumatura dei bordi.
  final int softness;

  /// Lato massimo dell'immagine elaborata (le foto grandi vengono ridotte).
  final int maxSide;
}

/// Errore di elaborazione con messaggio per l'utente.
class SignatureProcessingException implements Exception {
  const SignatureProcessingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Luminanza percepita (0–255), ITU-R BT.601.
int luminance(num r, num g, num b) => ((r * 299 + g * 587 + b * 114) / 1000).round().clamp(0, 255);

/// Istogramma a 256 livelli dei valori di grigio.
List<int> histogram(Iterable<int> grays) {
  final h = List<int>.filled(256, 0);
  for (final g in grays) {
    h[g.clamp(0, 255)]++;
  }
  return h;
}

/// Soglia di Otsu: massimizza la varianza tra le due classi (inchiostro / carta).
/// Restituisce t tale che i pixel con grigio <= t sono inchiostro.
int otsuThreshold(List<int> hist) {
  assert(hist.length == 256);
  final total = hist.fold<int>(0, (a, b) => a + b);
  if (total == 0) return 127;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var sumB = 0.0;
  var wB = 0;
  var best = 0.0;
  var threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sumAll - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}

/// Opacità dell'inchiostro per un grigio. Fino alla soglia l'inchiostro è pieno;
/// sopra la soglia sfuma verso la carta in 2×[softness] livelli (bordi morbidi).
/// La sfumatura sta sopra la soglia perché Otsu, con poca firma e molta carta,
/// tende a mettere la soglia vicino all'inchiostro.
int inkAlpha(int gray, int threshold, int softness) {
  if (gray <= threshold) return 255;
  if (softness <= 0) return 0;
  final hi = threshold + softness * 2;
  if (gray >= hi) return 0;
  return ((hi - gray) / (hi - threshold) * 255).round();
}

/// Rettangolo dei pixel con alpha > [minAlpha]; null se l'immagine è vuota.
({int x, int y, int w, int h})? contentBounds(img.Image im, {int minAlpha = 24}) {
  var minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).a > minAlpha) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return null;
  return (x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1);
}

/// Ritaglia sul contenuto non trasparente, con un piccolo margine.
img.Image cropToContent(img.Image im, {int padding = 4, int minAlpha = 24}) {
  final b = contentBounds(im, minAlpha: minAlpha);
  if (b == null) return im;
  final x = math.max(0, b.x - padding);
  final y = math.max(0, b.y - padding);
  final w = math.min(im.width - x, b.w + padding * 2);
  final h = math.min(im.height - y, b.h + padding * 2);
  return img.copyCrop(im, x: x, y: y, width: w, height: h);
}

/// Decodifica, raddrizza (EXIF) e riduce un'immagine.
img.Image decodeForProcessing(Uint8List bytes, {int maxSide = 1600}) {
  final raw = img.decodeImage(bytes);
  if (raw == null) {
    throw SignatureProcessingException(tr('Formato immagine non supportato. Usa JPG o PNG.'));
  }
  // Immagini a 16 bit o in virgola mobile: i canali vanno oltre 255 e la soglia leggerebbe tutto bianco.
  final decoded = raw.format == img.Format.uint8 ? raw : raw.convert(format: img.Format.uint8);
  var im = img.bakeOrientation(decoded);
  final side = math.max(im.width, im.height);
  if (side > maxSide) {
    final scale = maxSide / side;
    im = img.copyResize(
      im,
      width: (im.width * scale).round(),
      height: (im.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
  return im;
}

/// Scontorno completo: scala di grigi → soglia (Otsu o manuale) → sfondo trasparente
/// con bordi morbidi → ricolorazione opzionale → ritaglio sul contenuto.
CutoutResult cutoutSignature(CutoutRequest req) {
  final src = decodeForProcessing(req.bytes, maxSide: req.maxSide);
  final w = src.width, h = src.height;

  // Grigi; i pixel già trasparenti (PNG) contano come carta.
  final grays = Uint8List(w * h);
  var i = 0;
  for (final p in src) {
    final a = p.aNormalized;
    final g = luminance(p.r, p.g, p.b);
    grays[i++] = (g * a + 255 * (1 - a)).round();
  }
  final t = (req.threshold ?? otsuThreshold(histogram(grays))).clamp(1, 254);

  final (int, int, int)? tint = switch (req.recolor) {
    InkRecolor.blue => (0x1D, 0x3F, 0xBF),
    InkRecolor.black => (0x11, 0x11, 0x11),
    InkRecolor.original => null,
  };

  final out = img.Image(width: w, height: h, numChannels: 4);
  i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++, i++) {
      final alpha = inkAlpha(grays[i], t, req.softness);
      if (alpha == 0) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
        continue;
      }
      if (tint != null) {
        out.setPixelRgba(x, y, tint.$1, tint.$2, tint.$3, alpha);
      } else {
        final p = src.getPixel(x, y);
        // Scurisce un po' il colore originale: la carta schiarisce i bordi.
        out.setPixelRgba(x, y, (p.r * 0.85).round(), (p.g * 0.85).round(), (p.b * 0.85).round(), alpha);
      }
    }
  }

  final cropped = cropToContent(out, padding: 6);
  if (contentBounds(cropped) == null) {
    throw SignatureProcessingException(tr('Nessuna firma trovata. Prova a regolare la soglia o usa una foto più contrastata.'));
  }
  return CutoutResult(
    png: Uint8List.fromList(img.encodePng(cropped, level: 6)),
    width: cropped.width,
    height: cropped.height,
    threshold: t,
  );
}

/// Ritaglia un PNG già trasparente (es. firma scritta) sul contenuto.
CutoutResult cropPngToContent(Uint8List png, {int padding = 6}) {
  final im = img.decodePng(png);
  if (im == null) throw SignatureProcessingException(tr('Immagine non valida.'));
  final rgba = im.numChannels == 4 ? im : im.convert(numChannels: 4);
  final cropped = cropToContent(rgba, padding: padding);
  return CutoutResult(
    png: Uint8List.fromList(img.encodePng(cropped, level: 6)),
    width: cropped.width,
    height: cropped.height,
    threshold: 0,
  );
}
