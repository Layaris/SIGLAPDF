import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/storage/key_value_store.dart';
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
      final t = FormTemplate.fromMap(asStringMap(_store.get(k)));
      if (t != null) _items[t.id] = t;
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
    if (old != null) {
      _items.remove(old.id);
      await _store.delete(old.id);
    }
    final t = FormTemplate(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? tr('Modello') : name.trim(),
      pageCount: pageCount,
      createdAt: DateTime.now(),
      fingerprint: fingerprint,
      elements: [for (final e in elements) PlacedElement.fromTemplateMap(e.toTemplateMap())!],
    );
    _items[t.id] = t;
    await _store.put(t.id, t.toMap());
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
}) {
  final out = <PlacedElement>[];
  for (final e in t.elements) {
    if (e.page >= pageCount) continue;
    switch (e.type) {
      case ElementType.signature:
      case ElementType.signedDate:
        if (signaturePng == null) continue;
        out.add(e.copyWith(image: signaturePng, text: e.type == ElementType.signedDate ? today : e.text));
      case ElementType.initials:
        if (initialsPng == null) continue;
        out.add(e.copyWith(image: initialsPng));
      case ElementType.date:
        out.add(e.copyWith(text: today));
      default:
        out.add(e);
    }
  }
  return out;
}
