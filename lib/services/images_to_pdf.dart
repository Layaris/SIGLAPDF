import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../core/l10n/l10n.dart';

/// Crea un PDF con una pagina A4 per ogni immagine (orientamento in base all'immagine).
/// Le immagini vengono raddrizzate (EXIF), ridotte a [maxSide] px e ricodificate in JPEG.
Future<Uint8List> imagesToPdf(List<Uint8List> images, {int maxSide = 2200, int quality = 85}) async {
  if (images.isEmpty) throw ArgumentError(tr('Nessuna immagine'));
  final doc = PdfDocument();
  try {
    doc.pageSettings.margins.all = 0;
    var added = 0;
    for (final bytes in images) {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      var im = img.bakeOrientation(decoded);
      final side = math.max(im.width, im.height);
      if (side > maxSide) {
        final k = maxSide / side;
        im = img.copyResize(im, width: (im.width * k).round(), height: (im.height * k).round(), interpolation: img.Interpolation.average);
      }
      final jpg = Uint8List.fromList(img.encodeJpg(im, quality: quality));
      final landscape = im.width > im.height;
      const a4 = Size(595, 842);
      final pageSize = landscape ? Size(a4.height, a4.width) : a4;
      final section = doc.sections!.add();
      // syncfusion normalizza la dimensione: l'orizzontale si imposta con l'orientamento.
      section.pageSettings.size = a4;
      section.pageSettings.orientation = landscape ? PdfPageOrientation.landscape : PdfPageOrientation.portrait;
      section.pageSettings.margins.all = 0;
      final page = section.pages.add();
      // Immagine centrata, adattata con un margine di 18 pt.
      const margin = 18.0;
      final availW = pageSize.width - margin * 2, availH = pageSize.height - margin * 2;
      final k = math.min(availW / im.width, availH / im.height);
      final w = im.width * k, h = im.height * k;
      page.graphics.drawImage(
        PdfBitmap(jpg),
        Rect.fromLTWH((pageSize.width - w) / 2, (pageSize.height - h) / 2, w, h),
      );
      added++;
    }
    if (added == 0) throw ArgumentError(tr('Nessuna immagine valida'));
    return Uint8List.fromList(await doc.save());
  } finally {
    doc.dispose();
  }
}
