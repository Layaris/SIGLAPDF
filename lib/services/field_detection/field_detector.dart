import 'dart:typed_data';

import '../../core/utils/pdf_coords.dart';
import '../pdf_service.dart';
import 'field_kind.dart';

/// Opzione di un campo a scelta (es. "M", "Sì") con la casella da spuntare.
class ChoiceOption {
  const ChoiceOption(this.label, this.rect);
  final String label;

  /// Casella (o punto accanto all'opzione) normalizzata sulla pagina.
  final NormRect rect;
}

/// Campo trovato su una pagina, ancora da confermare.
class DetectedField {
  const DetectedField({
    required this.page,
    required this.kind,
    required this.label,
    required this.rect,
    required this.source,
    this.lineHeight,
    this.options = const [],
  });

  /// Opzioni dei campi a scelta ([FieldKind.isChoice]).
  final List<ChoiceOption> options;

  final int page;
  final FieldKind kind;

  /// Etichetta come appare nel documento.
  final String label;

  /// Spazio da compilare, normalizzato sulla pagina visiva.
  final NormRect rect;

  /// Motore che l'ha trovato ("locale", "AI").
  final String source;

  /// Altezza della riga di testo (normalizzata), utile per dimensionare il testo.
  final double? lineHeight;
}

/// Dati per il rilevamento.
class DetectionInput {
  const DetectionInput({required this.pdf, required this.pages, this.pageIndexes, this.avoid = const []});

  final Uint8List pdf;
  final List<PdfPageInfo> pages;

  /// Pagine da analizzare (null = tutte).
  final List<int>? pageIndexes;

  /// Riquadri da evitare (es. campi AcroForm già presenti), per pagina.
  final List<(int page, NormRect rect)> avoid;

  Iterable<int> get targetPages => pageIndexes ?? List.generate(pages.length, (i) => i);
}

/// Motore di riconoscimento dei campi. Nuovi motori implementano questa interfaccia.
abstract class FieldDetector {
  String get name;
  Future<List<DetectedField>> detect(DetectionInput input);
}
