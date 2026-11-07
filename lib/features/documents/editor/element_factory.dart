import 'dart:ui';

import 'package:intl/intl.dart';

import '../../../core/utils/pdf_coords.dart';
import '../models/placed_element.dart';

/// Calcolo delle dimensioni iniziali degli elementi, in coordinate normalizzate.
class ElementFactory {
  const ElementFactory(this.pageVisual);

  /// Dimensioni della pagina visiva in punti.
  final Size pageVisual;

  double get _ratio => pageVisual.width / pageVisual.height;

  /// Rettangolo per un'immagine con proporzioni [aspect] (larghezza/altezza),
  /// larga [widthPts] punti e centrata in [center] (normalizzato).
  NormRect imageRect(double aspect, {double widthPts = 160, Offset center = const Offset(0.5, 0.5)}) {
    final w = (widthPts / pageVisual.width).clamp(0.05, 0.9);
    final h = w * _ratio / (aspect <= 0 ? 3 : aspect);
    return NormRect(center.dx - w / 2, center.dy - h / 2, w, h).clamped();
  }

  /// Riquadro per un testo di [chars] caratteri con corpo [fontPts].
  NormRect textRect(String text, {double fontPts = 12, Offset center = const Offset(0.5, 0.5)}) {
    final boxH = fontPts / textBoxFontRatio;
    final estW = (text.length.clamp(2, 200)) * fontPts * 0.56 + fontPts;
    final w = (estW / pageVisual.width).clamp(0.04, 0.95);
    final h = boxH / pageVisual.height;
    return NormRect(center.dx - w / 2, center.dy - h / 2, w, h).clamped();
  }

  /// Quadrato di [sidePts] punti per spunta e croce.
  NormRect squareRect({double sidePts = 16, Offset center = const Offset(0.5, 0.5)}) {
    final w = sidePts / pageVisual.width;
    final h = sidePts / pageVisual.height;
    return NormRect(center.dx - w / 2, center.dy - h / 2, w, h).clamped(minSize: 0.005);
  }

  /// Posizione classica della sigla: in basso a destra.
  NormRect initialsCornerRect(double aspect) {
    final r = imageRect(aspect, widthPts: 70);
    return NormRect(0.92 - r.w, 0.95 - r.h, r.w, r.h).clamped();
  }
}

/// Data odierna nel formato italiano gg/mm/aaaa.
String todayText([DateTime? now]) => DateFormat('dd/MM/yyyy').format(now ?? DateTime.now());
