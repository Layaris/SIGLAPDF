import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/storage/key_value_store.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/features/signatures/signature_repository.dart';

final _png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);

Future<Signature> _add(SignatureRepository r, String name, {SignatureKind kind = SignatureKind.signature}) =>
    r.add(name: name, kind: kind, source: SignatureSource.drawn, png: _png, width: 30, height: 10);

void main() {
  test('la prima firma di ogni tipo diventa predefinita', () async {
    final r = SignatureRepository(MemoryKeyValueStore());
    final a = await _add(r, 'A');
    final b = await _add(r, 'B');
    final s = await _add(r, 'S', kind: SignatureKind.initials);
    expect(r.byId(a.id)!.isDefault, isTrue);
    expect(r.byId(b.id)!.isDefault, isFalse);
    expect(r.byId(s.id)!.isDefault, isTrue);
    expect(r.defaultOf(SignatureKind.signature)!.id, a.id);
  });

  test('imposta predefinita, rinomina ed elimina', () async {
    final r = SignatureRepository(MemoryKeyValueStore());
    final a = await _add(r, 'A');
    final b = await _add(r, 'B');
    await r.setDefault(b.id);
    expect(r.byId(a.id)!.isDefault, isFalse);
    expect(r.all.first.id, b.id, reason: 'la predefinita è in cima');
    await r.rename(a.id, '  Firma lunga ');
    expect(r.byId(a.id)!.name, 'Firma lunga');
    await r.rename(a.id, '   ');
    expect(r.byId(a.id)!.name, 'Firma lunga', reason: 'nome vuoto ignorato');
    await r.remove(b.id);
    expect(r.byId(a.id)!.isDefault, isTrue, reason: 'la predefinita passa alla rimasta');
  });

  test('persiste e rilegge dallo store', () async {
    final store = MemoryKeyValueStore();
    final r = SignatureRepository(store);
    final a = await _add(r, 'A');
    final reloaded = SignatureRepository(store);
    expect(reloaded.byId(a.id)!.name, 'A');
    expect(reloaded.byId(a.id)!.png, _png);
  });

  test('import in unione non duplica e non ruba la predefinita', () async {
    final r = SignatureRepository(MemoryKeyValueStore());
    final a = await _add(r, 'A');
    final incoming = [
      a.copyWith(name: 'A dal backup'),
      Signature(
        id: 'x',
        name: 'X',
        kind: SignatureKind.signature,
        source: SignatureSource.image,
        png: _png,
        width: 1,
        height: 1,
        createdAt: DateTime(2026),
        isDefault: true,
      ),
    ];
    final added = await r.importAll(incoming, replace: false);
    expect(added, 1);
    expect(r.byId(a.id)!.name, 'A');
    expect(r.byId(a.id)!.isDefault, isTrue);
    expect(r.byId('x')!.isDefault, isFalse);
  });

  test('import con sostituzione cancella le firme locali', () async {
    final r = SignatureRepository(MemoryKeyValueStore());
    await _add(r, 'A');
    final x = Signature(
      id: 'x',
      name: 'X',
      kind: SignatureKind.initials,
      source: SignatureSource.typed,
      png: _png,
      width: 1,
      height: 1,
      createdAt: DateTime(2026),
    );
    await r.importAll([x], replace: true);
    expect(r.all.map((s) => s.id), ['x']);
    expect(r.byId('x')!.isDefault, isTrue, reason: 'garantita una predefinita per tipo');
  });

  test('toJson/fromMap conserva i dati (PNG in base64)', () {
    final s = Signature(
      id: 'i',
      name: 'N',
      kind: SignatureKind.initials,
      source: SignatureSource.typed,
      png: _png,
      width: 3,
      height: 2,
      createdAt: DateTime.utc(2026, 1, 2),
      isDefault: true,
    );
    final back = Signature.fromMap(s.toJson());
    expect(back.png, _png);
    expect(back.kind, SignatureKind.initials);
    expect(back.source, SignatureSource.typed);
    expect(back.createdAt, DateTime.utc(2026, 1, 2));
    expect(back.isDefault, isTrue);
  });
}
