import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

/// Archivio chiave/valore minimale. I valori sono tipi semplici
/// (String, num, bool, Uint8List, List, Map) così restano portabili nel backup.
abstract class KeyValueStore {
  Object? get(String key);
  Future<void> put(String key, Object? value);
  Future<void> delete(String key);
  Future<void> clear();
  Iterable<String> get keys;
}

/// Implementazione in memoria, usata nei test.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object?> _data = {};

  @override
  Object? get(String key) => _data[key];

  @override
  Future<void> put(String key, Object? value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Iterable<String> get keys => List.unmodifiable(_data.keys);
}

/// Implementazione su un box Hive (IndexedDB sul web).
class HiveKeyValueStore implements KeyValueStore {
  HiveKeyValueStore(this._box);

  final Box<dynamic> _box;

  static Future<HiveKeyValueStore> open(String name) async =>
      HiveKeyValueStore(await Hive.openBox<dynamic>(name));

  @override
  Object? get(String key) => _box.get(key);

  @override
  Future<void> put(String key, Object? value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);

  @override
  Future<void> clear() async {
    await _box.clear();
  }

  @override
  Iterable<String> get keys => _box.keys.map((k) => k.toString());
}

/// Converte ricorsivamente le mappe lette da Hive (`Map<dynamic, dynamic>`)
/// in `Map<String, dynamic>`.
Map<String, dynamic> asStringMap(Object? value) {
  if (value is! Map) return <String, dynamic>{};
  return value.map((k, v) => MapEntry(k.toString(), _normalize(v)));
}

Object? _normalize(Object? v) {
  if (v is Map) return asStringMap(v);
  if (v is TypedData) return v; // Uint8List resta tale (PNG delle firme).
  if (v is List) return v.map(_normalize).toList();
  return v;
}
