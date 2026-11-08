import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/features/backup/backup_service.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/services/crypto_backup.dart';

import '../test_helpers.dart';

// Poche iterazioni nei test: il formato le salva nell'header.
final _crypto = CryptoBackup(iterations: 2000);

void main() {
  const payload = {
    'schema': 3,
    'signatures': <Object>[],
    'profiles': [
      {'id': 'a', 'label': 'Io', 'data': {'firstName': 'Mario'}},
    ],
    'activeProfile': 'a',
    'templates': <Object>[],
    'settings': {'inkColor': 'black'},
  };

  test('cifra e decifra con la password giusta', () async {
    final file = await _crypto.encrypt(payload, 'password-lunga');
    final env = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
    expect(env['format'], 'sigla-backup');
    expect(env['version'], 2);
    expect(env['kdf']['iterations'], 2000);
    expect(base64Decode(env['kdf']['salt'] as String), hasLength(16));
    expect(base64Decode(env['cipher']['nonce'] as String), hasLength(12));
    expect(utf8.decode(file), isNot(contains('Mario')), reason: 'contenuto cifrato');
    final back = await CryptoBackup.decrypt(file, 'password-lunga');
    expect((back['profiles'] as List).single['data'], {'firstName': 'Mario'});
  });

  test('password sbagliata → errore chiaro', () async {
    final file = await _crypto.encrypt(payload, 'password-lunga');
    await expectLater(
      CryptoBackup.decrypt(file, 'password-sbagliata'),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', 'Password errata o file danneggiato.')),
    );
  });

  test('sale e nonce casuali: due backup uguali sono diversi', () async {
    final a = await _crypto.encrypt(payload, 'password-lunga');
    final b = await _crypto.encrypt(payload, 'password-lunga');
    expect(a, isNot(equals(b)));
  });

  test('header manomesso (AAD) o testo cifrato alterato → rifiutato', () async {
    final file = await _crypto.encrypt(payload, 'password-lunga');
    final env = jsonDecode(utf8.decode(file)) as Map<String, dynamic>;
    // createdAt è informativo; format, version, kdf e cipher sono nell'AAD.
    final tampered = {...env, 'createdAt': '2000-01-01T00:00:00.000Z'};
    expect((await CryptoBackup.decrypt(Uint8List.fromList(utf8.encode(jsonEncode(tampered))), 'password-lunga'))['schema'], 3,
        reason: 'createdAt non è autenticato: è solo informativo');
    final ct = base64Decode(env['ciphertext'] as String)..[0] ^= 0xFF;
    final broken = {...env, 'ciphertext': base64Encode(ct)};
    await expectLater(
      CryptoBackup.decrypt(Uint8List.fromList(utf8.encode(jsonEncode(broken))), 'password-lunga'),
      throwsA(isA<BackupException>()),
    );
  });

  test('file non valido, formato sconosciuto, versione futura, password corta', () async {
    await expectLater(CryptoBackup.decrypt(Uint8List.fromList([1, 2, 3]), 'x'), throwsA(isA<BackupException>()));
    await expectLater(
      CryptoBackup.decrypt(Uint8List.fromList(utf8.encode('{"format":"altro"}')), 'x'),
      throwsA(isA<BackupException>()),
    );
    await expectLater(
      CryptoBackup.decrypt(Uint8List.fromList(utf8.encode('{"format":"sigla-backup","version":99}')), 'x'),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('più recente'))),
    );
    await expectLater(_crypto.encrypt(payload, 'corta'), throwsA(isA<BackupException>()));
  });

  test('migrazione dallo schema 1', () {
    final v1 = {
      'signatures': [
        {'id': 'a', 'name': 'A', 'type': 'draw', 'png': 'AAA='},
        {'id': 'b', 'name': 'B', 'type': 'text', 'png': 'AAA='},
      ],
      'profile': {
        'firstName': 'Mario',
        'extra': {'Patente': 'U1'},
      },
    };
    final v3 = BackupMigrations.migrate(v1);
    expect(v3['schema'], 3);
    final sigs = (v3['signatures'] as List).cast<Map<String, dynamic>>();
    expect(sigs[0]['source'], 'drawn');
    expect(sigs[1]['source'], 'typed');
    expect(sigs[0]['kind'], 'signature');
    expect(sigs[0].containsKey('type'), isFalse);
    final named = NamedProfile.fromMap(((v3['profiles'] as List).single as Map).cast<String, dynamic>())!;
    expect(named.label, 'Io');
    expect(named.profile.custom.single, const CustomField('Patente', 'U1'));
    expect(named.profile[ProfileField.firstName], 'Mario');
    expect(() => BackupMigrations.migrate({'schema': 4}), throwsA(isA<BackupException>()));
  });

  test('migrazione dallo schema 2: profilo singolo → lista di profili', () {
    final v3 = BackupMigrations.migrate({
      'schema': 2,
      'signatures': <Object>[],
      'profile': {'firstName': 'Anna'},
      'settings': <String, Object>{},
    });
    expect(v3['schema'], 3);
    expect(v3.containsKey('profile'), isFalse);
    expect(v3['activeProfile'], 'principale');
    expect((v3['profiles'] as List).single['data'], {'firstName': 'Anna'});
    expect(v3['templates'], isEmpty);
  });

  test('backup completo dell\'app: esporta, importa con unisci e sostituisci', () async {
    final source = AppServices.inMemory();
    await source.signatures.add(name: 'Firma', kind: SignatureKind.signature, source: SignatureSource.drawn, png: tinyPng(), width: 4, height: 2);
    await source.profile.save(const Profile(values: {ProfileField.firstName: 'Mario', ProfileField.city: 'Roma'}));
    await source.settings.update((s) => s.copyWith(inkColor: 'black', aiApiKey: 'sk-segreta'));
    final service = BackupService(source, crypto: _crypto);
    expect(service.buildPayload().toString(), isNot(contains('sk-segreta')), reason: 'la chiave API non va nel backup');
    await service.export('password-lunga');

    await source.profile.addProfile('Mamma');
    await source.profile.save(const Profile(values: {ProfileField.firstName: 'Lucia'}));
    await source.profile.setActive(source.profile.profiles.first.id);
    await source.templates.save(name: 'Modulo', elements: const [], pageCount: 1, fingerprint: 'fp');
    final file2 = await service.export('password-lunga');

    final target = AppServices.inMemory();
    await target.profile.save(const Profile(values: {ProfileField.firstName: 'Anna'}));
    final merged = await BackupService(target, crypto: _crypto).import(file2, 'password-lunga', replace: false);
    expect(merged.signatures, 1);
    expect(merged.templates, 1);
    expect(target.profile.value[ProfileField.firstName], 'Anna', reason: 'unisci non sovrascrive (stesso nome "Io")');
    expect(target.profile.value[ProfileField.city], 'Roma');
    expect(target.profile.profiles.map((p) => p.label), ['Io', 'Mamma']);
    expect(target.settings.value.inkColor, 'blue', reason: 'unisci non tocca le impostazioni');

    await target.settings.update((s) => s.copyWith(aiApiKey: 'sk-locale'));
    final replaced = await BackupService(target, crypto: _crypto).import(file2, 'password-lunga', replace: true);
    expect(replaced.settings, isTrue);
    expect(target.profile.value[ProfileField.firstName], 'Mario');
    expect(target.settings.value.inkColor, 'black');
    expect(target.settings.value.aiApiKey, 'sk-locale', reason: 'la chiave locale resta');
    expect(target.signatures.all, hasLength(1));
    expect(BackupService(target).fileName(DateTime(2026, 3, 4)), 'sigla-backup-20260304.sigla');
  });
}
