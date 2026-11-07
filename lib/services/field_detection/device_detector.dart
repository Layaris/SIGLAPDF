import 'dart:typed_data';
import 'dart:ui';

import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../pdf_service.dart';
import 'field_detector.dart';
import 'local_text_detector.dart';
import 'ocr.dart';

/// Pixel RGBA di una pagina renderizzata.
class RgbaPage {
  const RgbaPage(this.pixels, this.width, this.height);
  final Uint8List pixels;
  final int width;
  final int height;
}

/// Render RGBA di una pagina (sostituibile nei test).
typedef RgbaRasterizer = Future<RgbaPage?> Function(Uint8List pdf, int page, double dpi);

Future<RgbaPage?> printingRgbaRasterizer(Uint8List pdf, int page, double dpi) async {
  await for (final r in Printing.raster(pdf, pages: [page], dpi: dpi)) {
    return RgbaPage(r.pixels, r.width, r.height);
  }
  return null;
}

/// Riconoscimento "sul dispositivo": per le pagine con testo usa il testo del PDF; per le pagine
/// scansionate (senza testo) legge l'immagine con l'OCR del telefono, se disponibile.
/// In entrambi i casi poi applica lo stesso dizionario delle etichette. Niente rete.
class DeviceFieldDetector implements FieldDetector {
  DeviceFieldDetector({this.ocr, RgbaRasterizer? rasterizer, this.ocrDpi = 200, this.minWords = 3})
      : _raster = rasterizer ?? printingRgbaRasterizer;

  final OcrEngine? ocr;
  final RgbaRasterizer _raster;
  final double ocrDpi;

  /// Sotto questo numero di parole una pagina è considerata scansionata.
  final int minWords;

  bool get hasOcr => ocr != null;

  @override
  String get name => 'locale';

  @override
  Future<List<DetectedField>> detect(DetectionInput input) async {
    final scanned = <int>[];
    final out = <DetectedField>[];
    final doc = openPdf(input.pdf);
    try {
      final extractor = PdfTextExtractor(doc);
      for (final p in input.targetPages) {
        if (p < 0 || p >= input.pages.length) continue;
        List<List<WordBox>> lines;
        try {
          lines = pdfTextLines(extractor, p, input.pages[p].coords);
        } catch (_) {
          lines = const [];
        }
        final words = lines.fold<int>(0, (n, l) => n + l.length);
        if (words < minWords) {
          scanned.add(p);
        } else {
          out.addAll(detectFieldsInLines(lines, input.pages[p], p, source: name));
        }
      }
    } finally {
      doc.dispose();
    }
    final engine = ocr;
    if (engine != null) {
      for (final p in scanned) {
        out.addAll(await _ocrPage(engine, input, p));
      }
    }
    return out.where((f) => !input.avoid.any((a) => a.$1 == f.page && _overlaps(a.$2.toRect(const Size(1, 1)), f.rect.toRect(const Size(1, 1))))).toList();
  }

  Future<List<DetectedField>> _ocrPage(OcrEngine engine, DetectionInput input, int p) async {
    final img = await _raster(input.pdf, p, ocrDpi);
    if (img == null || img.width == 0) return const [];
    final lines = await engine.recognize(img.pixels, img.width, img.height);
    // Pixel → punti della pagina visiva.
    final info = input.pages[p];
    final sx = info.visual.width / img.width;
    final sy = info.visual.height / img.height;
    final boxes = [
      for (final l in lines)
        [
          for (final w in l)
            if (w.text.trim().isNotEmpty)
              WordBox(w.text, Rect.fromLTRB(w.rect.left * sx, w.rect.top * sy, w.rect.right * sx, w.rect.bottom * sy)),
        ],
    ]..sort((a, b) => (a.isEmpty ? 0 : a.first.rect.top).compareTo(b.isEmpty ? 0 : b.first.rect.top));
    return detectFieldsInLines(boxes.where((l) => l.isNotEmpty).toList(), info, p, source: 'OCR');
  }

  static bool _overlaps(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return false;
    final small = (a.width * a.height) < (b.width * b.height) ? a.width * a.height : b.width * b.height;
    return small > 0 && i.width * i.height / small > 0.3;
  }
}
