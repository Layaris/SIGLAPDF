import 'package:flutter/foundation.dart';

import '../../../core/utils/pdf_coords.dart';

/// Tipi di elemento posizionabile sopra la pagina.
enum ElementType {
  signature('Firma'),
  initials('Sigla'),
  text('Testo'),
  date('Data'),
  check('Spunta'),
  cross('Croce');

  const ElementType(this.label);
  final String label;

  bool get isImage => this == signature || this == initials;
  bool get isText => this == text || this == date;
  bool get isMark => this == check || this == cross;
}

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
  });

  final String id;
  final ElementType type;
  final int page;
  final NormRect rect;

  /// Testo per [ElementType.text] e [ElementType.date].
  final String text;

  /// PNG per firma e sigla.
  final Uint8List? image;

  /// Colore ARGB di testo e segni.
  final int color;

  /// Firme e sigle mantengono le proporzioni quando si ridimensionano.
  bool get keepsAspect => type.isImage || type.isMark;

  PlacedElement copyWith({String? id, int? page, NormRect? rect, String? text, int? color}) => PlacedElement(
        id: id ?? this.id,
        type: type,
        page: page ?? this.page,
        rect: rect ?? this.rect,
        text: text ?? this.text,
        image: image,
        color: color ?? this.color,
      );
}

/// Rapporto tra altezza del riquadro e corpo del testo, uguale a schermo e nel PDF.
const textBoxFontRatio = 0.72;
