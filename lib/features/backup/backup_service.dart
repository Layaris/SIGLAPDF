import 'dart:typed_data';

import '../../core/app_services.dart';
import '../../core/l10n/l10n.dart';
import '../../services/crypto_backup.dart';
import '../documents/templates/templates_repository.dart';
import '../profile/profile_model.dart';
import '../signatures/signature_model.dart';

/// Riepilogo di un import.
class ImportSummary {
  const ImportSummary({required this.signatures, required this.profile, required this.settings, this.templates = 0});
  final int signatures;
  final bool profile;
  final bool settings;
  final int templates;
}

/// Collega il formato .sigla ai repository dell'app.
class BackupService {
  BackupService(this.services, {CryptoBackup? crypto}) : crypto = crypto ?? CryptoBackup();

  final AppServices services;
  final CryptoBackup crypto;

  /// Contenuto in chiaro del backup (schema corrente). La chiave API non è inclusa.
  Map<String, dynamic> buildPayload() => {
        'schema': CryptoBackup.currentSchema,
        'app': 'sigla',
        'signatures': [for (final s in services.signatures.all) s.toJson()],
        'profiles': [for (final p in services.profile.profiles) p.toMap()],
        'activeProfile': services.profile.activeId,
        'templates': [for (final t in services.templates.all) t.toMap()],
        'settings': services.settings.value.toBackupMap(),
      };

  Future<Uint8List> export(String password) => crypto.encrypt(buildPayload(), password);

  String fileName([DateTime? now]) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'sigla-backup-${d.year}${two(d.month)}${two(d.day)}.sigla';
  }

  /// Decifra e importa. [replace] = sostituisci, altrimenti unisci.
  Future<ImportSummary> import(Uint8List bytes, String password, {required bool replace}) async {
    final payload = await CryptoBackup.decrypt(bytes, password);
    // Prima si legge e si controlla tutto; solo dopo si toccano i dati del dispositivo, così un file
    // con una voce rovinata non lascia un import a metà (con "Sostituisci" le firme locali sparirebbero).
    List<T> parse<T extends Object>(Object? list, T? Function(Map<String, dynamic>) from) {
      final out = <T>[];
      for (final raw in (list is List ? list : const [])) {
        if (raw is! Map) continue;
        try {
          final v = from(raw.cast<String, dynamic>());
          if (v != null) out.add(v);
        } catch (_) {
          // Voce non valida: saltata.
        }
      }
      return out;
    }

    final sigs = parse(payload['signatures'], Signature.fromMap);
    final profiles = parse(payload['profiles'], NamedProfile.fromMap);
    final templates = parse(payload['templates'], FormTemplate.fromMap);
    final active = payload['activeProfile'];
    if (replace && sigs.isEmpty && profiles.isEmpty && templates.isEmpty) {
      throw BackupException(tr('Il backup non contiene dati: non ho cambiato niente.'));
    }
    final added = await services.signatures.importAll(sigs, replace: replace);
    await services.profile.importProfiles(profiles, replace: replace, activeId: active is String ? active : null);
    final profileDone = profiles.isNotEmpty;
    final templatesAdded = await services.templates.importAll(templates, replace: replace);
    final settingsMap = payload['settings'];
    var settingsDone = false;
    if (replace && settingsMap is Map) {
      await services.settings.restoreFromBackup(settingsMap.cast<String, dynamic>());
      settingsDone = true;
    }
    return ImportSummary(signatures: added, profile: profileDone, settings: settingsDone, templates: templatesAdded);
  }
}
