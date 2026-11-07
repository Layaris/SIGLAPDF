
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/key_value_store.dart';
import 'signature_model.dart';

/// Libreria delle firme. Una sola firma predefinita per tipo (firma / sigla).
class SignatureRepository extends ChangeNotifier {
  SignatureRepository(this._store) {
    for (final k in _store.keys) {
      try {
        final s = Signature.fromMap(asStringMap(_store.get(k)));
        if (s.png.isNotEmpty) _items[s.id] = s;
      } catch (_) {
        // Voce corrotta: ignorata.
      }
    }
  }

  final KeyValueStore _store;
  final Map<String, Signature> _items = {};
  static const _uuid = Uuid();

  /// Tutte le firme, prima le predefinite, poi le più recenti.
  List<Signature> get all {
    final list = _items.values.toList()
      ..sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  List<Signature> ofKind(SignatureKind kind) => all.where((s) => s.kind == kind).toList();

  Signature? byId(String id) => _items[id];

  /// Predefinita del tipo, oppure la più recente.
  Signature? defaultOf(SignatureKind kind) {
    final list = ofKind(kind);
    return list.where((s) => s.isDefault).firstOrNull ?? list.firstOrNull;
  }

  bool get isEmpty => _items.isEmpty;

  Future<Signature> add({
    required String name,
    required SignatureKind kind,
    required SignatureSource source,
    required Uint8List png,
    required int width,
    required int height,
  }) async {
    final makeDefault = ofKind(kind).isEmpty;
    final s = Signature(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? kind.label : name.trim(),
      kind: kind,
      source: source,
      png: png,
      width: width,
      height: height,
      createdAt: DateTime.now(),
      isDefault: makeDefault,
    );
    _items[s.id] = s;
    notifyListeners();
    await _store.put(s.id, s.toMap());
    return s;
  }

  Future<void> rename(String id, String name) async {
    final s = _items[id];
    if (s == null || name.trim().isEmpty) return;
    await _save(s.copyWith(name: name.trim()));
  }

  Future<void> setDefault(String id) async {
    final target = _items[id];
    if (target == null) return;
    for (final s in ofKind(target.kind).where((s) => s.isDefault && s.id != id)) {
      await _save(s.copyWith(isDefault: false), notify: false);
    }
    await _save(target.copyWith(isDefault: true));
  }

  Future<void> remove(String id) async {
    final removed = _items.remove(id);
    if (removed == null) return;
    await _store.delete(id);
    // Se era la predefinita, la più recente dello stesso tipo prende il suo posto.
    if (removed.isDefault) {
      final next = ofKind(removed.kind).firstOrNull;
      if (next != null) await _save(next.copyWith(isDefault: true), notify: false);
    }
    notifyListeners();
  }

  /// Import da backup. [replace] cancella prima tutto; altrimenti aggiunge solo gli id mancanti.
  Future<int> importAll(List<Signature> signatures, {required bool replace}) async {
    if (replace) {
      _items.clear();
      await _store.clear();
    }
    var added = 0;
    for (final s in signatures) {
      if (_items.containsKey(s.id) || s.png.isEmpty) continue;
      // In unione non si rubano le predefinite esistenti.
      final keepDefault = s.isDefault && (replace || defaultOf(s.kind) == null);
      final item = s.copyWith(isDefault: keepDefault);
      _items[item.id] = item;
      await _store.put(item.id, item.toMap());
      added++;
    }
    // Garantisce una predefinita per tipo.
    for (final kind in SignatureKind.values) {
      final list = ofKind(kind);
      if (list.isNotEmpty && !list.any((s) => s.isDefault)) {
        await _save(list.first.copyWith(isDefault: true), notify: false);
      }
    }
    notifyListeners();
    return added;
  }

  Future<void> _save(Signature s, {bool notify = true}) async {
    _items[s.id] = s;
    if (notify) notifyListeners();
    await _store.put(s.id, s.toMap());
  }
}
