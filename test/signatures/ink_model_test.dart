import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sigla/features/signatures/drawing/ink_model.dart';
import 'package:sigla/features/signatures/drawing/ink_renderer.dart';

const _blue = Color(0xFF1D3FBF);

InkStroke _line(double y, {double? pressure}) => InkStroke(
      [for (var i = 0; i <= 10; i++) InkPoint(10.0 + i * 10, y, pressure: pressure, t: i * 16)],
      width: 3,
      color: _blue,
    );

void main() {
  group('buildSegments', () {
    test('un punto produce un segmento-punto', () {
      final s = buildSegments(const InkStroke([InkPoint(5, 5)], width: 3, color: _blue));
      expect(s, hasLength(1));
      expect(s.first.start, s.first.end);
    });

    test('le curve sono continue: ogni segmento parte dove finisce il precedente', () {
      final segs = buildSegments(_line(20));
      expect(segs.length, greaterThan(3));
      for (var i = 1; i < segs.length; i++) {
        expect(segs[i].start, segs[i - 1].end);
      }
      expect(segs.first.start, const Offset(10, 20));
      expect(segs.last.end, const Offset(110, 20));
    });

    test('la pressione alta ingrossa il tratto', () {
      final light = buildSegments(_line(20, pressure: 0.05));
      final heavy = buildSegments(_line(20, pressure: 1.0));
      expect(heavy.last.width, greaterThan(light.last.width * 1.8));
    });

    test('i punti duplicati vengono scartati', () {
      final s = buildSegments(const InkStroke([InkPoint(1, 1), InkPoint(1, 1), InkPoint(1.1, 1)], width: 2, color: _blue));
      expect(s, hasLength(1));
    });
  });

  group('InkDrawing', () {
    test('annulla, ripeti e cancella', () {
      final d = InkDrawing();
      expect(d.isEmpty, isTrue);
      d.begin(const InkPoint(0, 0), width: 3, color: _blue);
      d.extend(const InkPoint(10, 10));
      d.end();
      d.begin(const InkPoint(20, 0), width: 3, color: _blue);
      d.end();
      expect(d.strokes, hasLength(2));
      d.undo();
      expect(d.strokes, hasLength(1));
      expect(d.canRedo, isTrue);
      d.redo();
      expect(d.strokes, hasLength(2));
      d.clear();
      expect(d.isEmpty, isTrue);
      // Cancella si può annullare con Ripeti.
      d.redo();
      d.redo();
      expect(d.strokes, hasLength(2));
      // Un nuovo tratto svuota Ripeti.
      d.undo();
      d.begin(const InkPoint(5, 5), width: 3, color: _blue);
      d.end();
      expect(d.canRedo, isFalse);
    });

    test('ricolora tutti i tratti', () {
      final d = InkDrawing()
        ..begin(const InkPoint(0, 0), width: 3, color: _blue)
        ..end()
        ..recolor(const Color(0xFF111111));
      expect(d.strokes.single.color, const Color(0xFF111111));
    });
  });

  test('strokesBounds include lo spessore', () {
    final r = strokesBounds([_line(50)])!;
    expect(r.left, lessThan(10));
    expect(r.right, greaterThan(110));
    expect(r.top, lessThan(50));
  });

  testWidgets('il render produce un PNG trasparente ritagliato sul tratto', (tester) async {
    final rendered = await tester.runAsync(() => renderStrokesToPng([_line(50)], pixelRatio: 2));
    expect(rendered, isNotNull);
    final decoded = img.decodePng(Uint8List.fromList(rendered!.png))!;
    expect(decoded.width, rendered.width);
    // Larghezza ≈ (100 + spessore) × 2, non l'intera area di disegno.
    expect(decoded.width, inInclusiveRange(200, 240));
    expect(decoded.height, lessThan(40));
    // Angolo trasparente, centro con inchiostro.
    expect(decoded.getPixel(0, 0).a, 0);
    final center = decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
    expect(center.a, greaterThan(200));
    expect(center.b, greaterThan(center.r));
  });
}
