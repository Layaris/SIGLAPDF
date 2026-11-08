import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/pdf_coords.dart';

/// Tipi di elemento posizionabile sopra la pagina.
enum ElementType {
  signature('Firma'),
  initials('Sigla'),
  signedDate('Firma con data'),
  text('Testo'),
  date('Data'),
  check('Spunta'),
  cross('Croce'),
  ink('Tratto a mano'),
  highlight('Evidenziatore');

  const ElementType(this._it);
  final String _it;

  /// Etichetta nella lingua dell'interfaccia.
  String get label => tr(_it);

  bool get isImage => this == signature || this == initials || this == signedDate;
  bool get isText => this == text || this == date;
  bool get isMark => this == check || this == cross;

  /// Si può cambiare colore (blu/nero).
  bool get hasInkColor => isText || isMark || this == ink;

  static ElementType? parse(Object? v) => ElementType.values.where((t) => t.name == v).firstOrNull;
}

/// Colore dell'evidenziatore (giallo) e sua opacità nel PDF.
const highlightColor = 0xFFFFD84D;
const highlightOpacity = 0.38;

/// Elemento posizionato su una pagina, con rettangolo normalizzato.
@immutable
class PlacedElement {
  const PlacedElement({
    required this.id,
    required this.type,
    required this.page,
    required this.rect,
    this.text = '',
    this.image,
    this.color = 0xFF1D3FBF,
    this.strokes = const [],
    this.inkWidth = 0.004,
  });

  final String id;
  final ElementType type;
  final int page;
  final NormRect rect;

  /// Testo per [ElementType.text], [ElementType.date] e la data di [ElementType.signedDate].
  final String text;

  /// PNG per firma, sigla e firma con data.
  final Uint8List? image;

  /// Colore ARGB di testo, segni e tratti.
  final int color;

  /// Tratti di [ElementType.ink]: punti normalizzati (0–1) dentro [rect].
  final List<List<Offset>> strokes;

  /// Spessore dei tratti come frazione della larghezza della pagina.
  final double inkWidth;

  /// Firme, sigle, segni e tratti mantengono le proporzioni quando si ridimensionano.
  bool get keepsAspect => type.isImage || type.isMark || type == ElementType.ink;

  PlacedElement copyWith({String? id, int? page, NormRect? rect, String? text, int? color, Uint8List? image}) => PlacedElement(
        id: id ?? this.id,
        type: type,
        page: page ?? this.page,
        rect: rect ?? this.rect,
        text: text ?? this.text,
        image: image ?? this.image,
        color: color ?? this.color,
        strokes: strokes,
        inkWidth: inkWidth,
      );

  /// Mappa per i modelli (senza l'immagine: firma e sigla si prendono da quelle predefinite).
  Map<String, dynamic> toTemplateMap() => {
        'type': type.name,
        'page': page,
        'rect': rect.toMap(),
        'text': text,
        'color': color,
        if (strokes.isNotEmpty) 'strokes': [for (final s in strokes) [for (final p in s) [p.dx, p.dy]]],
        'inkWidth': inkWidth,
      };

  static PlacedElement? fromTemplateMap(Map<String, dynamic> m) {
    final type = ElementType.parse(m['type']);
    final rect = m['rect'];
    if (type == null || rect is! Map) return null;
    final rawStrokes = m['strokes'];
    return PlacedElement(
      id: '',
      type: type,
      page: (m['page'] as num?)?.toInt() ?? 0,
      rect: NormRect.fromMap(rect.cast<String, dynamic>()),
      text: m['text'] as String? ?? '',
      color: (m['color'] as num?)?.toInt() ?? 0xFF1D3FBF,
      inkWidth: (m['inkWidth'] as num?)?.toDouble() ?? 0.004,
      strokes: rawStrokes is List
          ? [
              for (final s in rawStrokes.whereType<List<dynamic>>())
                [
                  for (final p in s.whereType<List<dynamic>>())
                    if (p.length == 2) Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()),
                ],
            ]
          : const [],
    );
  }
}

/// Rapporto tra altezza del riquadro e corpo del testo, uguale a schermo e nel PDF.
const textBoxFontRatio = 0.72;

/// Nella firma con data la firma occupa la parte alta, la data la fascia in basso.
const signedDateSplit = 0.74;

/// Converte un tratto (punti in coordinate della pagina, normalizzate) in un elemento
/// [ElementType.ink] con i punti relativi al suo riquadro.
PlacedElement? inkElementFromStroke(
  List<Offset> pagePoints, {
  required int page,
  required int color,
  required double inkWidth,
  required double pageAspect,
}) {
  if (pagePoints.length < 2) return null;
  var minX = pagePoints.first.dx, maxX = minX, minY = pagePoints.first.dy, maxY = minY;
  for (final p in pagePoints) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  // Margine pari a metà spessore, così il tratto non viene tagliato.
  final padX = inkWidth / 2 + 0.002, padY = inkWidth * pageAspect / 2 + 0.002;
  minX -= padX;
  maxX += padX;
  minY -= padY;
  maxY += padY;
  final w = (maxX - minX).clamp(0.005, 1.0), h = (maxY - minY).clamp(0.005, 1.0);
  return PlacedElement(
    id: '',
    type: ElementType.ink,
    page: page,
    rect: NormRect(minX, minY, w, h),
    color: color,
    inkWidth: inkWidth,
    strokes: [
      [for (final p in pagePoints) Offset((p.dx - minX) / w, (p.dy - minY) / h)],
    ],
  );
}
