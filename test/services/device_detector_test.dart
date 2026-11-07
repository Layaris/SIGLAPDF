import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sigla/services/field_detection/device_detector.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/field_detection/ocr.dart';
import 'package:sigla/services/images_to_pdf.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';

/// OCR finto: restituisce righe fisse in pixel di un'immagine 1000×1414.
class FakeOcr implements OcrEngine {
  int calls = 0;
  @override
  Future<List<List<OcrWord>>> recognize(Uint8List rgba, int width, int height) async {
    calls++;
    expect(rgba.length, width * height * 4);
    return [
      [const OcrWord('Cognome:', Rect.fromLTRB(100, 200, 260, 230))],
      [const OcrWord('Nome', Rect.fromLTRB(100, 300, 180, 330)), const OcrWord('________', Rect.fromLTRB(200, 300, 600, 330))],
      [const OcrWord('Codice', Rect.fromLTRB(100, 400, 200, 430)), const OcrWord('fiscale', Rect.fromLTRB(210, 400, 320, 430))],
    ];
  }
}

Future<RgbaPage?> _raster(Uint8List pdf, int page, double dpi) async => RgbaPage(Uint8List(1000 * 1414 * 4), 1000, 1414);

Future<Uint8List> _scannedPdf() {
  // Pagina fatta solo di un'immagine (come una scansione): nessun testo estraibile.
  final im = img.Image(width: 600, height: 848)..clear(img.ColorRgb8(255, 255, 255));
  return imagesToPdf([Uint8List.fromList(img.encodePng(im))]);
}

void main() {
  test('scansione: usa l\'OCR e trova i campi con le coordinate giuste', () async {
    final pdf = await _scannedPdf();
    final info = const PdfService().inspect(pdf);
    final ocr = FakeOcr();
    final fields = await DeviceFieldDetector(ocr: ocr, rasterizer: _raster).detect(DetectionInput(pdf: pdf, pages: info.pages));
    expect(ocr.calls, 1);
    expect(fields.every((f) => f.source == 'OCR'), isTrue);
    final kinds = fields.map((f) => f.kind).toSet();
    expect(kinds, containsAll([FieldKind.lastName, FieldKind.firstName, FieldKind.taxCode]));
    final nome = fields.firstWhere((f) => f.kind == FieldKind.firstName);
    expect(nome.rect.x, closeTo(0.2, 0.01), reason: 'la linea ____ inizia a 200 px su 1000');
    expect(nome.rect.right, closeTo(0.6, 0.01));
    final cognome = fields.firstWhere((f) => f.kind == FieldKind.lastName);
    expect(cognome.rect.x, greaterThan(0.26), reason: 'dopo i due punti');
  });

  test('PDF con testo: niente OCR', () async {
    final pdf = buildUnmarkedFormPdf();
    final info = const PdfService().inspect(pdf);
    final ocr = FakeOcr();
    final fields = await DeviceFieldDetector(ocr: ocr, rasterizer: _raster).detect(DetectionInput(pdf: pdf, pages: info.pages));
    expect(ocr.calls, 0);
    expect(fields, isNotEmpty);
    expect(fields.every((f) => f.source == 'locale'), isTrue);
  });

  test('scansione senza OCR (web): nessun campo, nessun errore', () async {
    final pdf = await _scannedPdf();
    final info = const PdfService().inspect(pdf);
    final d = DeviceFieldDetector(rasterizer: _raster);
    expect(d.hasOcr, isFalse);
    expect(await d.detect(DetectionInput(pdf: pdf, pages: info.pages)), isEmpty);
  });

  test('createDeviceOcr: fuori da Android non c\'è', () => expect(createDeviceOcr(), isNull));
}
