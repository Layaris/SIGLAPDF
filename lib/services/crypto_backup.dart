import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import '../core/l10n/l10n.dart';

/// Errore del backup con messaggio per l'utente.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Formato del file .sigla (vedi docs/ARCHITECTURE.md).
///
/// - envelope JSON in chiaro con `format`, `version`, parametri KDF e cifratura;
/// - contenuto JSON cifrato con AES-256-GCM, chiave da PBKDF2-HMAC-SHA256;
/// - l'header è usato come dato autenticato (AAD).
class CryptoBackup {
  CryptoBackup({this.iterations = defaultIterations, Random? random}) : _random = random ?? Random.secure();

  static const format = 'sigla-backup';
  static const envelopeVersion = 2;
  static const currentSchema = 3;
  static const defaultIterations = 310000;
  static const minPasswordLength = 8;

  final int iterations;
  final Random _random;

  List<int> _bytes(int n) => List<int>.generate(n, (_) => _random.nextInt(256));

  static Future<SecretKey> _deriveKey(String password, List<int> salt, int iterations) =>
      Pbkdf2.hmacSha256(iterations: iterations, bits: 256).deriveKeyFromPassword(password: password, nonce: salt);

  /// Dati autenticati: i campi dell'header che non devono essere manomessi.
  static List<int> _aad(int version, int iterations, String salt) =>
      utf8.encode('$format|$version|pbkdf2-hmac-sha256|$iterations|$salt|aes-256-gcm');

  /// Cifra il contenuto [payload] (che deve contenere `schema`) e restituisce i byte del file.
  Future<Uint8List> encrypt(Map<String, dynamic> payload, String password, {DateTime? now}) async {
    if (password.length < minPasswordLength) {
      throw BackupException(tr('La password deve avere almeno {0} caratteri.', [minPasswordLength]));
    }
    final salt = _bytes(16);
    final nonce = _bytes(12);
    final saltB64 = base64Encode(salt);
    final key = await _deriveKey(password, salt, iterations);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: key,
      nonce: nonce,
      aad: _aad(envelopeVersion, iterations, saltB64),
    );
    final envelope = {
      'format': format,
      'version': envelopeVersion,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'kdf': {'name': 'pbkdf2-hmac-sha256', 'iterations': iterations, 'salt': saltB64},
      'cipher': {'name': 'aes-256-gcm', 'nonce': base64Encode(box.nonce), 'mac': base64Encode(box.mac.bytes)},
      'ciphertext': base64Encode(box.cipherText),
    };
    return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent(' ').convert(envelope)));
  }

  /// Decifra un file .sigla e restituisce il contenuto già migrato allo schema corrente.
  static Future<Map<String, dynamic>> decrypt(Uint8List bytes, String password) async {
    Map<String, dynamic> env;
    try {
      env = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw BackupException(tr('Il file non è un backup di Sigla.'));
    }
    if (env['format'] != format) throw BackupException(tr('Il file non è un backup di Sigla.'));
    final version = env['version'];
    if (version is! int || version < 1) throw BackupException(tr('Versione del backup non valida.'));
    if (version > envelopeVersion) {
      throw BackupException(tr('Backup creato con una versione più recente di Sigla. Aggiorna l\'app.'));
    }
    try {
      final kdf = (env['kdf'] as Map).cast<String, dynamic>();
      final cipher = (env['cipher'] as Map).cast<String, dynamic>();
      if (kdf['name'] != 'pbkdf2-hmac-sha256' || cipher['name'] != 'aes-256-gcm') {
        throw BackupException(tr('Formato di cifratura non supportato.'));
      }
      final iterations = kdf['iterations'] as int;
      if (iterations < 1000 || iterations > 10000000) throw BackupException(tr('Parametri del backup non validi.'));
      final saltB64 = kdf['salt'] as String;
      final key = await _deriveKey(password, base64Decode(saltB64), iterations);
      final box = SecretBox(
        base64Decode(env['ciphertext'] as String),
        nonce: base64Decode(cipher['nonce'] as String),
        mac: Mac(base64Decode(cipher['mac'] as String)),
      );
      // La versione 1 dell'envelope non usava dati autenticati.
      final aad = version >= 2 ? _aad(version, iterations, saltB64) : const <int>[];
      final clear = await AesGcm.with256bits().decrypt(box, secretKey: key, aad: aad);
      final payload = (jsonDecode(utf8.decode(clear)) as Map).cast<String, dynamic>();
      return BackupMigrations.migrate(payload);
    } on BackupException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw BackupException(tr('Password errata o file danneggiato.'));
    } catch (_) {
      throw BackupException(tr('Password errata o file danneggiato.'));
    }
  }
}

/// Migrazioni del contenuto del backup fino a [CryptoBackup.currentSchema].
class BackupMigrations {
  static Map<String, dynamic> migrate(Map<String, dynamic> payload) {
    var p = Map<String, dynamic>.of(payload);
    var schema = (p['schema'] as num?)?.toInt() ?? 1;
    if (schema > CryptoBackup.currentSchema) {
      throw BackupException(tr('Backup creato con una versione più recente di Sigla. Aggiorna l\'app.'));
    }
    while (schema < CryptoBackup.currentSchema) {
      p = switch (schema) {
        1 => _v1toV2(p),
        2 => _v2toV3(p),
        _ => throw BackupException(tr('Versione del backup non supportata.')),
      };
      schema = p['schema'] as int;
    }
    return p;
  }

  /// Schema 2 → 3: il profilo singolo diventa una lista di profili con nome; arrivano i modelli.
  static Map<String, dynamic> _v2toV3(Map<String, dynamic> p) {
    final profile = p['profile'];
    final out = Map<String, dynamic>.of(p)..remove('profile');
    out['profiles'] = [
      if (profile is Map) {'id': 'principale', 'label': 'Io', 'data': profile},
    ];
    out['activeProfile'] = 'principale';
    out['templates'] = out['templates'] ?? <Object>[];
    out['schema'] = 3;
    return out;
  }

  /// Schema 1 (formato preliminare): firme con `type` draw|image|text e senza `kind`;
  /// profilo con i campi personalizzati come mappa `extra`.
  static Map<String, dynamic> _v1toV2(Map<String, dynamic> p) {
    const sourceOf = {'draw': 'drawn', 'image': 'image', 'text': 'typed'};
    final sigs = (p['signatures'] as List? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map((m) {
          final s = m.cast<String, dynamic>();
          return {
            ...s,
            'source': sourceOf[s['type']] ?? s['source'] ?? 'drawn',
            'kind': s['kind'] ?? 'signature',
          }..remove('type');
        })
        .toList();
    final profile = Map<String, dynamic>.of((p['profile'] as Map? ?? const {}).cast<String, dynamic>());
    final extra = profile.remove('extra');
    if (extra is Map) {
      profile['custom'] = [
        for (final e in extra.entries) {'key': '${e.key}', 'value': '${e.value}'},
      ];
    }
    return {...p, 'schema': 2, 'signatures': sigs, 'profile': profile};
  }
}
