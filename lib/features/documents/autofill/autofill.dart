import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../../core/utils/pdf_coords.dart';
import '../../../services/field_detection/field_detector.dart';
import '../../../services/field_detection/field_kind.dart';
import '../../../services/field_detection/label_dictionary.dart';
import '../../../services/pdf_service.dart';
import '../../profile/profile_model.dart';
import '../models/placed_element.dart';

/// Proposta di compilazione mostrata nell'anteprima: l'utente la conferma, corregge o scarta.
class FillProposal {
  FillProposal({required this.field, required this.value, this.include = true});

  final DetectedField field;
  String value;
  bool include;

  bool get isSignature => field.kind == FieldKind.signature;
}

/// Crea le proposte dai campi trovati. I campi senza valore nel profilo partono esclusi.
List<FillProposal> buildProposals(List<DetectedField> fields, Profile profile, {required String today, bool hasSignature = false}) {
  final sorted = [...fields]..sort((a, b) {
      final p = a.page.compareTo(b.page);
      if (p != 0) return p;
      final y = a.rect.y.compareTo(b.rect.y);
      return y != 0 ? y : a.rect.x.compareTo(b.rect.x);
    });
  return [
    for (final f in sorted)
      () {
        final v = f.kind.proposedValue(profile, today: today);
        final include = f.kind == FieldKind.signature ? hasSignature : v.isNotEmpty;
        return FillProposal(field: f, value: v, include: include);
      }(),
  ];
}

/// Converte le proposte confermate in elementi da aggiungere all'editor.
List<PlacedElement> proposalsToElements(
  List<FillProposal> proposals, {
  required List<PdfPageInfo> pages,
  required int color,
  Uint8List? signaturePng,
  double signatureAspect = 3,
}) {
  final out = <PlacedElement>[];
  for (final p in proposals) {
    if (!p.include) continue;
    final f = p.field;
    if (f.page < 0 || f.page >= pages.length) continue;
    final size = pages[f.page].visual;
    final r = f.rect.toRect(size);
    if (p.isSignature) {
      if (signaturePng == null) continue;
      // Altezza comoda per una firma, larghezza dentro lo spazio trovato.
      var h = (r.height * 2.4).clamp(24.0, 56.0);
      var w = h * signatureAspect;
      if (w > r.width && r.width > 40) {
        w = r.width;
        h = w / signatureAspect;
      }
      final rect = Rect.fromLTWH(r.left, r.bottom - h * 0.8, w, h);
      out.add(PlacedElement(
        id: '',
        type: ElementType.signature,
        page: f.page,
        rect: NormRect.fromRect(rect, size).clamped(),
        image: signaturePng,
      ));
      continue;
    }
    final text = p.value.trim();
    if (text.isEmpty) continue;
    // Il testo sta sopra la linea: altezza pari alla riga (max 20 pt), con un piccolo rientro.
    final h = math.min(r.height, 20.0);
    final rect = Rect.fromLTWH(r.left + 2, r.bottom - h, math.max(r.width - 2, 10), h);
    out.add(PlacedElement(
      id: '',
      type: ElementType.text,
      page: f.page,
      rect: NormRect.fromRect(rect, size).clamped(),
      text: text,
      color: color,
    ));
  }
  return out;
}

/// Valori AcroForm proposti dal profilo per i campi ancora vuoti, in base al nome del campo.
Map<String, String> acroFormValuesFromProfile(List<FormFieldInfo> fields, Map<String, String> current, Profile profile, {required String today}) {
  final out = <String, String>{};
  for (final f in fields) {
    if (f.kind != FormFieldKind.text || !f.isFillable) continue;
    if ((current[f.name] ?? '').trim().isNotEmpty) continue;
    final kind = kindForFieldName(f.name);
    if (kind == null || kind == FieldKind.signature) continue;
    final v = kind.proposedValue(profile, today: today);
    if (v.isNotEmpty) out[f.name] = v;
  }
  return out;
}
