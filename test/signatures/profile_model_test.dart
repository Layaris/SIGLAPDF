import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/storage/key_value_store.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/features/profile/profile_repository.dart';

void main() {
  const p = Profile(values: {
    ProfileField.firstName: 'Mario',
    ProfileField.lastName: 'Rossi',
    ProfileField.address: 'Via Roma 1',
    ProfileField.zip: '00100',
    ProfileField.city: 'Roma',
    ProfileField.province: 'RM',
  }, custom: [CustomField('Patente', 'U1234567')]);

  test('nome completo, iniziali e indirizzo completo', () {
    expect(p.fullName, 'Mario Rossi');
    expect(p.initials, 'M.R.');
    expect(p.fullAddress, 'Via Roma 1, 00100 Roma (RM)');
    expect(p.filledEntries.map((e) => e.$1), containsAll(['Nome e cognome', 'Indirizzo completo', 'Patente']));
  });

  test('toMap/fromMap', () {
    final back = Profile.fromMap(p.toMap());
    expect(back[ProfileField.city], 'Roma');
    expect(back.custom, p.custom);
  });

  test('unione: completa solo i campi vuoti', () {
    const local = Profile(values: {ProfileField.firstName: 'Anna'}, custom: [CustomField('patente', 'X')]);
    final merged = local.mergedWith(p);
    expect(merged[ProfileField.firstName], 'Anna');
    expect(merged[ProfileField.lastName], 'Rossi');
    expect(merged.custom, hasLength(1), reason: 'stessa chiave, ignorata');
  });

  test('repository salva e rilegge', () async {
    final store = MemoryKeyValueStore();
    await ProfileRepository(store).save(p);
    expect(ProfileRepository(store).value.fullName, 'Mario Rossi');
  });

  test('più profili: migrazione, attivo, aggiungi, rinomina, elimina', () async {
    final store = MemoryKeyValueStore();
    // Vecchio formato con un solo profilo.
    await store.put('profile', p.toMap());
    final r = ProfileRepository(store);
    expect(r.profiles.single.label, 'Io');
    expect(r.value.fullName, 'Mario Rossi');
    final mamma = await r.addProfile('Mamma');
    expect(r.activeId, mamma.id);
    expect(r.value.isEmpty, isTrue);
    await r.save(const Profile(values: {ProfileField.firstName: 'Lucia'}));
    await r.renameProfile(mamma.id, 'Mamma Lucia');
    final reloaded = ProfileRepository(store);
    expect(reloaded.profiles.map((x) => x.label), ['Io', 'Mamma Lucia']);
    expect(reloaded.value[ProfileField.firstName], 'Lucia', reason: 'resta attivo dopo il riavvio');
    expect(store.get('profile'), isNull, reason: 'vecchia chiave rimossa');
    expect(await reloaded.removeProfile(mamma.id), isTrue);
    expect(await reloaded.removeProfile(reloaded.activeId), isFalse, reason: 'l\'ultimo non si elimina');
    expect(reloaded.value.fullName, 'Mario Rossi');
  });
}
