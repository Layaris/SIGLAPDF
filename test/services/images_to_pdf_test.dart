import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sigla/services/images_to_pdf.dart';
import 'package:sigla/services/pdf_service.dart';

Uint8List _png(int w, int h) => Uint8List.fromList(img.encodePng(img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 200, 200))));

void main() {
  test('una pagina A4 per immagine, orientamento dall\'immagine', () async {
    final pdf = await imagesToPdf([_png(300, 400), _png(800, 400), Uint8List.fromList([1, 2, 3])]);
    final info = const PdfService().inspect(pdf);
    expect(info.pages, hasLength(2), reason: 'l\'immagine non valida viene saltata');
    expect(info.pages[0].visual.width, closeTo(595, 1));
    expect(info.pages[0].visual.height, closeTo(842, 1));
    expect(info.pages[1].visual.width, closeTo(842, 1), reason: 'immagine orizzontale → pagina orizzontale');
  });

  test('nessuna immagine valida → errore', () async {
    await expectLater(imagesToPdf([Uint8List.fromList([0])]), throwsArgumentError);
    await expectLater(imagesToPdf(const []), throwsArgumentError);
  });
}
