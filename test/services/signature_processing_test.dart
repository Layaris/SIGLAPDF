import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sigla/services/signature_processing.dart';

/// Foto sintetica: carta grigio chiaro con rumore, firma scura in un rettangolo noto.
Uint8List _photo({int w = 400, int h = 200, int ink = 40, int paper = 225}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final noise = ((x * 7 + y * 13) % 11) - 5;
      final v = paper + noise;
      im.setPixelRgb(x, y, v, v, v + 3);
    }
  }
  // "Firma": linea spessa obliqua da (100,80) a (300,120) + un ricciolo.
  for (var x = 100; x <= 300; x++) {
    final yc = 80 + ((x - 100) * 40 ~/ 200);
    for (var d = -3; d <= 3; d++) {
      im.setPixelRgb(x, yc + d, ink, ink, ink + 60);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  group('Otsu', () {
    test('trova la soglia tra due picchi', () {
      final h = List<int>.filled(256, 0);
      h[40] = 1000; // inchiostro
      h[220] = 9000; // carta
      final t = otsuThreshold(h);
      expect(t, inInclusiveRange(40, 219));
    });

    test('istogramma vuoto → 127', () => expect(otsuThreshold(List<int>.filled(256, 0)), 127));

    test('istogramma con valori sparsi', () {
      final grays = [for (var i = 0; i < 500; i++) 30 + i % 20, for (var i = 0; i < 4500; i++) 200 + i % 30];
      final t = otsuThreshold(histogram(grays));
      expect(t, greaterThanOrEqualTo(49));
      expect(t, lessThan(200));
    });
  });

  test('inkAlpha: pieno fino alla soglia, poi sfuma verso la carta', () {
    expect(inkAlpha(10, 128, 20), 255);
    expect(inkAlpha(128, 128, 20), 255);
    expect(inkAlpha(250, 128, 20), 0);
    expect(inkAlpha(168, 128, 20), 0);
    expect(inkAlpha(148, 128, 20), inInclusiveRange(120, 135));
    expect(inkAlpha(135, 128, 20), greaterThan(inkAlpha(160, 128, 20)));
    expect(inkAlpha(128, 128, 0), 255);
    expect(inkAlpha(129, 128, 0), 0);
  });

  group('cutoutSignature', () {
    test('PNG a 16 bit: stessa firma trovata', () {
      final eight = img.decodeImage(_photo())!;
      final sixteen = eight.convert(format: img.Format.uint16);
      final r = cutoutSignature(CutoutRequest(Uint8List.fromList(img.encodePng(sixteen))));
      final out = img.decodePng(r.png)!;
      expect(out.width, inInclusiveRange(200, 220), reason: 'a 16 bit prima risultava tutto bianco');
    });

    test('sfondo trasparente, ritaglio sul contenuto e soglia automatica', () {
      final r = cutoutSignature(CutoutRequest(_photo()));
      final out = img.decodePng(r.png)!;
      expect(out.numChannels, 4);
      // Ritagliato: circa 200×47 + margini, non 400×200.
      expect(out.width, inInclusiveRange(200, 220));
      expect(out.height, inInclusiveRange(45, 62));
      // Tra il grigio dell'inchiostro (~47) e quello della carta (~225).
      expect(r.threshold, inInclusiveRange(48, 200));
      // Angoli trasparenti (sfondo rimosso).
      expect(out.getPixel(0, out.height - 1).a, 0);
      expect(out.getPixel(out.width - 1, 0).a, 0);
      // Inchiostro opaco al centro della linea.
      final cx = out.width ~/ 2;
      final opaque = [for (var y = 0; y < out.height; y++) out.getPixel(cx, y).a].reduce((a, b) => a > b ? a : b);
      expect(opaque, greaterThan(230));
    });

    test('ricolora in blu', () {
      final r = cutoutSignature(CutoutRequest(_photo(), recolor: InkRecolor.blue));
      final out = img.decodePng(r.png)!;
      final cx = out.width ~/ 2;
      img.Pixel? ink;
      for (var y = 0; y < out.height; y++) {
        final p = out.getPixel(cx, y);
        if (p.a > 240) ink = p;
      }
      expect(ink, isNotNull);
      expect(ink!.r, 0x1D);
      expect(ink.g, 0x3F);
      expect(ink.b, 0xBF);
    });

    test('soglia manuale bassissima → nessuna firma trovata', () {
      expect(
        () => cutoutSignature(CutoutRequest(_photo(), threshold: 5, softness: 0)),
        throwsA(isA<SignatureProcessingException>()),
      );
    });

    test('immagine non valida → messaggio chiaro', () {
      expect(
        () => cutoutSignature(CutoutRequest(Uint8List.fromList([1, 2, 3]))),
        throwsA(isA<SignatureProcessingException>()),
      );
    });

    test('foto grande viene ridotta al lato massimo', () {
      final r = cutoutSignature(CutoutRequest(_photo(w: 1600, h: 800), maxSide: 800));
      expect(r.width, lessThanOrEqualTo(800));
    });

    test('PNG con trasparenza: i pixel trasparenti contano come carta', () {
      final im = img.Image(width: 60, height: 30, numChannels: 4);
      for (var x = 10; x < 50; x++) {
        im.setPixelRgba(x, 15, 0, 0, 0, 255);
      }
      final r = cutoutSignature(CutoutRequest(Uint8List.fromList(img.encodePng(im)), threshold: 128));
      expect(r.width, inInclusiveRange(40, 54));
    });
  });

  test('cropPngToContent ritaglia mantenendo un margine', () {
    final im = img.Image(width: 100, height: 100, numChannels: 4);
    img.fillRect(im, x1: 40, y1: 45, x2: 59, y2: 54, color: img.ColorRgba8(0, 0, 255, 255));
    final r = cropPngToContent(Uint8List.fromList(img.encodePng(im)), padding: 2);
    expect(r.width, 24);
    expect(r.height, 14);
  });
}
