import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/utils/pdf_coords.dart';
import '../models/placed_element.dart';

/// Modello di un modulo ricorrente: dove vanno firma, testi, data…
@immutable
class FormTemplate {
  const FormTemplate({
    required this.id,
    required this.name,
    required this.pageCount,
    required this.createdAt,
    required this.elements,
    this.fingerprint,
  });

  final String id;
  final String name;
  final int pageCount;
  final DateTime createdAt;

  /// Impronta del modulo di origine (null se era una scansione senza testo).
  final String? fingerprint;
  final List<PlacedElement> elements;

  FormTemplate copyWith({String? name}) => FormTemplate(
        id: id,
        name: name ?? this.name,
        pageCount: pageCount,
        createdAt: createdAt,
        elements: elements,
        fingerprint: fingerprint,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'pageCount': pageCount,
        'createdAt': createdAt.toIso8601String(),
        'fingerprint': fingerprint,
        'elements': [for (final e in elements) e.toTemplateMap()],
      };

  static FormTemplate? fromMap(Map<String, dynamic> m) {
    if (m['id'] is! String) return null;
    final raw = m['elements'];
    return FormTemplate(
      id: m['id'] as String,
      name: (m['name'] as String?)?.trim().isNotEmpty == true ? (m['name'] as String).trim() : tr('Modello'),
      pageCount: (m['pageCount'] as num?)?.toInt() ?? 1,
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      fingerprint: m['fingerprint'] as String?,
      elements: raw is List
          ? raw.whereType<Map<dynamic, dynamic>>().map((e) => PlacedElement.fromTemplateMap(e.cast<String, dynamic>())).whereType<PlacedElement>().toList()
          : const [],
    );
  }
}

class TemplatesRepository extends ChangeNotifier {
  TemplatesRepository(this._store) {
    for (final k in _store.keys) {
      try {
        final t = FormTemplate.fromMap(asStringMap(_store.get(k)));
        if (t != null) _items[t.id] = t;
      } catch (_) {
        // Voce rovinata: si salta, l'app deve partire comunque.
      }
    }
  }

  final KeyValueStore _store;
  final Map<String, FormTemplate> _items = {};
  static const _uuid = Uuid();

  List<FormTemplate> get all => _items.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  bool get isEmpty => _items.isEmpty;

  /// Modello salvato per lo stesso modulo (stessa impronta), se c'è.
  FormTemplate? matching(String? fingerprint) =>
      fingerprint == null ? null : all.where((t) => t.fingerprint == fingerprint).firstOrNull;

  /// Salva un modello. Se ne esiste già uno per lo stesso modulo lo sostituisce.
  Future<FormTemplate> save({
    required String name,
    required List<PlacedElement> elements,
    required int pageCount,
    String? fingerprint,
  }) async {
    final old = matching(fingerprint);
    final t = FormTemplate(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? tr('Modello') : name.trim(),
      pageCount: pageCount,
      createdAt: DateTime.now(),
      fingerprint: fingerprint,
      elements: [for (final e in elements) PlacedElement.fromTemplateMap(e.toTemplateMap())!],
    );
    // Prima si salva il nuovo, poi si toglie il vecchio: se il salvataggio fallisce il vecchio resta.
    await _store.put(t.id, t.toMap());
    _items[t.id] = t;
    if (old != null) {
      _items.remove(old.id);
      await _store.delete(old.id);
    }
    notifyListeners();
    return t;
  }

  Future<void> rename(String id, String name) async {
    final t = _items[id];
    if (t == null || name.trim().isEmpty) return;
    _items[id] = t.copyWith(name: name.trim());
    await _store.put(id, _items[id]!.toMap());
    notifyListeners();
  }

  Future<void> remove(String id) async {
    if (_items.remove(id) == null) return;
    await _store.delete(id);
    notifyListeners();
  }

  /// Import da backup: [replace] cancella prima tutto, altrimenti aggiunge gli id mancanti.
  Future<int> importAll(List<FormTemplate> items, {required bool replace}) async {
    if (replace) {
      _items.clear();
      await _store.clear();
    }
    var added = 0;
    for (final t in items) {
      if (_items.containsKey(t.id)) continue;
      _items[t.id] = t;
      await _store.put(t.id, t.toMap());
      added++;
    }
    notifyListeners();
    return added;
  }
}

/// Elementi pronti da inserire da un modello. Firma e sigla prendono le immagini attuali;
/// le date diventano quella di oggi; gli elementi oltre le pagine del documento si saltano.
List<PlacedElement> elementsFromTemplate(
  FormTemplate t, {
  required int pageCount,
  required String today,
  Uint8List? signaturePng,
  Uint8List? initialsPng,
  double? signatureAspect,
  double? initialsAspect,
  List<double>? pageAspects,
}) {
  // La firma di oggi può avere proporzioni diverse da quella usata per il modello: si tiene la larghezza
  // e la riga di base (il fondo del riquadro) e si ricalcola l'altezza, così non si deforma.
  NormRect fit(PlacedElement e, double? aspect, {double share = 1}) {
    final pa = pageAspects != null && e.page < pageAspects.length ? pageAspects[e.page] : null;
    if (aspect == null || aspect <= 0 || pa == null || pa <= 0) return e.rect;
    final r = e.rect;
    final h = (r.w * pa / aspect) / share; // pa = larghezza/altezza della pagina
    return NormRect(r.x, r.y + r.h - h, r.w, h).clamped();
  }

  final out = <PlacedElement>[];
  for (final e in t.elements) {
    if (e.page >= pageCount) continue;
    switch (e.type) {
      case ElementType.signature:
      case ElementType.signedDate:
        if (signaturePng == null) continue;
        final dated = e.type == ElementType.signedDate;
        out.add(e.copyWith(
          image: signaturePng,
          text: dated ? today : e.text,
          rect: dated ? e.rect : fit(e, signatureAspect),
        ));
      case ElementType.initials:
        if (initialsPng == null) continue;
        out.add(e.copyWith(image: initialsPng, rect: fit(e, initialsAspect)));
      case ElementType.date:
        out.add(e.copyWith(text: today));
      default:
        out.add(e);
    }
  }
  return out;
}
