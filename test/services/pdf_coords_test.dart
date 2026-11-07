import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/utils/pdf_coords.dart';

void main() {
  const a4 = Size(595, 842);
  const r = NormRect(0.1, 0.2, 0.3, 0.05);

  test('pagina non ruotata: normalizzato → punti e ritorno', () {
    final c = PdfCoords(a4, 0);
    final p = c.toVisualPoints(r);
    expect(p.left, closeTo(59.5, 1e-9));
    expect(p.top, closeTo(168.4, 1e-9));
    expect(p.width, closeTo(178.5, 1e-9));
    expect(p.height, closeTo(42.1, 1e-9));
    final back = c.fromVisualPoints(p);
    expect(back.x, closeTo(r.x, 1e-12));
    expect(back.h, closeTo(r.h, 1e-12));
    expect(c.toUnrotatedPoints(r), p);
  });

  test('rotazione 90: dimensioni scambiate e punti mappati', () {
    final c = PdfCoords(a4, 90);
    expect(c.visual, const Size(842, 595));
    // Angolo visivo in alto a sinistra → angolo non ruotato in basso a sinistra.
    expect(c.visualToUnrotated(Offset.zero), const Offset(0, 842));
    expect(c.visualToUnrotated(const Offset(842, 0)), Offset.zero);
    final u = c.toUnrotatedPoints(const NormRect(0, 0, 0.5, 0.5));
    expect(u, const Rect.fromLTWH(0, 421, 297.5, 421));
  });

  test('rotazione 180 e 270', () {
    final c180 = PdfCoords(a4, 180);
    expect(c180.visualToUnrotated(Offset.zero), const Offset(595, 842));
    final c270 = PdfCoords(a4, 270);
    expect(c270.visual, const Size(842, 595));
    expect(c270.visualToUnrotated(Offset.zero), const Offset(595, 0));
    expect(c270.visualToUnrotated(const Offset(0, 595)), Offset.zero);
  });

  test('la trasformazione grafica è coerente con visualToUnrotated', () {
    for (final rot in [0, 90, 180, 270]) {
      final c = PdfCoords(a4, rot);
      final t = c.visualTransform;
      const v = Offset(100, 50);
      // Rotazione syncfusion: angolo negativo = antiorario (asse y verso il basso).
      final rad = t.angle * 3.141592653589793 / 180;
      final cosA = _round(_cos(rad)), sinA = _round(_sin(rad));
      final rotated = Offset(v.dx * cosA - v.dy * sinA, v.dx * sinA + v.dy * cosA);
      final mapped = rotated + Offset(t.dx, t.dy);
      expect(mapped, c.visualToUnrotated(v), reason: 'rotazione $rot');
    }
  });

  test('clamped tiene il rettangolo nella pagina', () {
    final c = const NormRect(0.9, -0.2, 0.3, 0.2).clamped();
    expect(c.x, closeTo(0.7, 1e-12));
    expect(c.y, 0);
    expect(const NormRect(0.5, 0.5, 0, 0).clamped(minSize: 0.02).w, 0.02);
  });

  test('toMap/fromMap', () => expect(NormRect.fromMap(r.toMap()), r));
}

double _cos(double x) => _taylor(x, true);
double _sin(double x) => _taylor(x, false);
double _taylor(double x, bool cos) {
  // Evita dart:math per mostrare il calcolo; precisione sufficiente per multipli di 90°.
  var term = cos ? 1.0 : x, sum = term;
  for (var n = 1; n < 30; n++) {
    final k = cos ? 2 * n : 2 * n + 1;
    term *= -x * x / ((k - 1) * k);
    sum += term;
  }
  return sum;
}

double _round(double v) => (v * 1e9).roundToDouble() / 1e9;
