import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/key_value_store.dart';

/// PDF esportato di recente, salvato solo sul dispositivo.
@immutable
class RecentDocument {
  const RecentDocument({
    required this.id,
    required this.name,
    required this.savedAt,
    required this.pageCount,
    required this.pdf,
    this.thumbnail,
  });

  final String id;
  final String name;
  final DateTime savedAt;
  final int pageCount;
  final Uint8List pdf;

  /// PNG piccolo della prima pagina.
  final Uint8List? thumbnail;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'savedAt': savedAt.toIso8601String(),
        'pageCount': pageCount,
        'pdf': pdf,
        if (thumbnail != null) 'thumbnail': thumbnail,
      };

  static RecentDocument? fromMap(Map<String, dynamic> m) {
    final pdf = m['pdf'];
    if (pdf is! Uint8List || m['id'] is! String) return null;
    final thumb = m['thumbnail'];
    return RecentDocument(
      id: m['id'] as String,
      name: m['name'] as String? ?? 'documento.pdf',
      savedAt: DateTime.tryParse(m['savedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      pageCount: (m['pageCount'] as num?)?.toInt() ?? 0,
      pdf: pdf,
      thumbnail: thumb is Uint8List ? thumb : null,
    );
  }
}

/// Ultimi PDF esportati (al massimo [maxItems], ognuno al massimo [maxBytes]).
/// Non vanno nel backup: restano solo su questo dispositivo.
class RecentsRepository extends ChangeNotifier {
  RecentsRepository(this._store, {this.maxItems = 12, this.maxBytes = 25 * 1024 * 1024, this.maxTotalBytes = 80 * 1024 * 1024}) {
    for (final k in _store.keys) {
      final d = RecentDocument.fromMap(asStringMap(_store.get(k)));
      if (d != null) _items[d.id] = d;
    }
  }

  final KeyValueStore _store;
  final int maxItems;
  final int maxBytes;
  final int maxTotalBytes;
  final Map<String, RecentDocument> _items = {};
  static const _uuid = Uuid();

  /// Dal più recente.
  List<RecentDocument> get all => _items.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));

  bool get isEmpty => _items.isEmpty;

  /// Aggiunge un PDF esportato. Se c'è già un documento con lo stesso nome lo sostituisce.
  /// Restituisce null se il file è troppo grande.
  Future<RecentDocument?> add({
    required String name,
    required Uint8List pdf,
    required int pageCount,
    Uint8List? thumbnail,
    DateTime? now,
  }) async {
    if (pdf.length > maxBytes) return null;
    final replaced = _items.values.where((d) => d.name == name).toList();
    final d = RecentDocument(
      id: _uuid.v4(),
      name: name,
      savedAt: now ?? DateTime.now(),
      pageCount: pageCount,
      pdf: pdf,
      thumbnail: thumbnail,
    );
    // Prima il nuovo, poi si tolgono il vecchio con lo stesso nome e quelli in eccesso.
    await _store.put(d.id, d.toMap());
    _items[d.id] = d;
    for (final old in replaced) {
      _items.remove(old.id);
      await _store.delete(old.id);
    }
    // Oltre al numero, un tetto allo spazio totale: i recenti stanno tutti in memoria.
    var total = 0;
    final keep = <String>{};
    for (final r in all) {
      if (keep.length >= maxItems || (keep.isNotEmpty && total + r.pdf.length > maxTotalBytes)) continue;
      keep.add(r.id);
      total += r.pdf.length;
    }
    for (final extra in all.where((r) => !keep.contains(r.id)).toList()) {
      _items.remove(extra.id);
      await _store.delete(extra.id);
    }
    notifyListeners();
    return d;
  }

  Future<void> remove(String id) async {
    if (_items.remove(id) == null) return;
    await _store.delete(id);
    notifyListeners();
  }

  Future<void> clear() async {
    _items.clear();
    await _store.clear();
    notifyListeners();
  }
}
