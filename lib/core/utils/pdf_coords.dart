import 'dart:ui';

import 'package:flutter/foundation.dart';
import '../l10n/l10n.dart';

/// Rettangolo normalizzato (0–1) rispetto alla pagina come la vede l'utente,
/// origine in alto a sinistra.
@immutable
class NormRect {
  const NormRect(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get bottom => y + h;

  /// Riporta il rettangolo dentro la pagina, con dimensioni minime.
  NormRect clamped({double minSize = 0.01}) {
    final cw = w.clamp(minSize, 1.0);
    final ch = h.clamp(minSize, 1.0);
    return NormRect(x.clamp(0.0, 1.0 - cw), y.clamp(0.0, 1.0 - ch), cw, ch);
  }

  NormRect translate(double dx, double dy) => NormRect(x + dx, y + dy, w, h);

  NormRect copyWith({double? x, double? y, double? w, double? h}) => NormRect(x ?? this.x, y ?? this.y, w ?? this.w, h ?? this.h);

  /// In pixel per un riquadro di pagina di [size].
  Rect toRect(Size size) => Rect.fromLTWH(x * size.width, y * size.height, w * size.width, h * size.height);

  static NormRect fromRect(Rect r, Size size) =>
      NormRect(r.left / size.width, r.top / size.height, r.width / size.width, r.height / size.height);

  Map<String, double> toMap() => {'x': x, 'y': y, 'w': w, 'h': h};

  factory NormRect.fromMap(Map<String, dynamic> m) => NormRect(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['w'] as num).toDouble(),
        (m['h'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) => other is NormRect && other.x == x && other.y == y && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'NormRect(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${w.toStringAsFixed(3)}, ${h.toStringAsFixed(3)})';
}

/// Conversioni tra coordinate normalizzate e punti PDF.
///
/// Una pagina ha dimensioni "non ruotate" [unrotated] (MediaBox/CropBox) e una rotazione
/// /Rotate di 0, 90, 180 o 270 gradi in senso orario. L'utente vede la pagina ruotata.
class PdfCoords {
  PdfCoords(this.unrotated, this.rotation) : assert(const {0, 90, 180, 270}.contains(rotation));

  final Size unrotated;
  final int rotation;

  bool get swapped => rotation == 90 || rotation == 270;

  /// Dimensioni della pagina come la vede l'utente, in punti.
  Size get visual => swapped ? Size(unrotated.height, unrotated.width) : unrotated;

  /// Rettangolo in punti nello spazio visivo (quello usato con la trasformazione
  /// di [visualTransform] applicata alla grafica della pagina).
  Rect toVisualPoints(NormRect r) => r.toRect(visual);

  NormRect fromVisualPoints(Rect r) => NormRect.fromRect(r, visual);

  /// Converte un punto dallo spazio visivo a quello non ruotato (origine in alto a sinistra).
  Offset visualToUnrotated(Offset v) {
    final w = unrotated.width, h = unrotated.height;
    return switch (rotation) {
      90 => Offset(v.dy, h - v.dx),
      180 => Offset(w - v.dx, h - v.dy),
      270 => Offset(w - v.dy, v.dx),
      _ => v,
    };
  }

  /// Inverso di [visualToUnrotated].
  Offset unrotatedToVisual(Offset u) {
    final w = unrotated.width, h = unrotated.height;
    return switch (rotation) {
      90 => Offset(h - u.dy, u.dx),
      180 => Offset(w - u.dx, h - u.dy),
      270 => Offset(u.dy, w - u.dx),
      _ => u,
    };
  }

  /// Rettangolo in punti non ruotati → rettangolo in punti visivi.
  Rect unrotatedRectToVisual(Rect r) => Rect.fromPoints(unrotatedToVisual(r.topLeft), unrotatedToVisual(r.bottomRight));

  /// Rettangolo normalizzato → rettangolo in punti nello spazio non ruotato della pagina.
  Rect toUnrotatedPoints(NormRect r) {
    final v = toVisualPoints(r);
    final a = visualToUnrotated(v.topLeft);
    final b = visualToUnrotated(v.bottomRight);
    return Rect.fromPoints(a, b);
  }

  /// Traslazione e rotazione (gradi, convenzione syncfusion) da applicare alla grafica
  /// della pagina perché il disegno in coordinate visive finisca al posto giusto.
  ({double dx, double dy, double angle}) get visualTransform => switch (rotation) {
        90 => (dx: 0, dy: unrotated.height, angle: -90),
        180 => (dx: unrotated.width, dy: unrotated.height, angle: -180),
        270 => (dx: unrotated.width, dy: 0, angle: -270),
        _ => (dx: 0, dy: 0, angle: 0),
      };
}
