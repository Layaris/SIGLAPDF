import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/l10n/l10n.dart';
import 'core/storage/key_value_store.dart';
import 'features/documents/editor/editor_page.dart';
import 'features/documents/recents/recents_repository.dart';
import 'features/documents/templates/templates_repository.dart';
import 'features/profile/profile_repository.dart';
import 'features/settings/settings_repository.dart';
import 'features/settings/signature_lock.dart';
import 'features/signatures/signature_repository.dart';
import 'services/document_sources.dart';
import 'services/field_detection/ocr.dart';
import 'services/update_checker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  await initializeDateFormatting('en_US');
  // Archivio: se qualcosa non si apre (memoria piena, navigazione privata, file illeggibile) l'app parte
  // lo stesso con un archivio in memoria e un avviso, invece di restare una pagina bianca.
  // Niente cancellazioni automatiche: i dati sul disco restano per la prossima apertura.
  var storageUnavailable = false;
  var hiveReady = true;
  try {
    await Hive.initFlutter('sigla');
  } catch (_) {
    hiveReady = false;
  }
  Future<KeyValueStore> open(String name) async {
    if (hiveReady) {
      try {
        return await HiveKeyValueStore.open(name);
      } catch (_) {}
    }
    storageUnavailable = true;
    return MemoryKeyValueStore();
  }

  final settingsStore = await open('settings');
  final signatureStore = await open('signatures');
  final profileStore = await open('profile');
  final recentsStore = await open('recents');
  final templatesStore = await open('templates');
  final updatesStore = await open('updates');
  final settings = SettingsRepository(settingsStore);
  final services = AppServices(
    settings: settings,
    lock: SignatureLock(settings, DeviceAuthenticator()),
    signatures: SignatureRepository(signatureStore),
    profile: ProfileRepository(profileStore),
    recents: RecentsRepository(recentsStore),
    templates: TemplatesRepository(templatesStore),
    updates: UpdateService(updatesStore, enabledOnPlatform: !kIsWeb && defaultTargetPlatform == TargetPlatform.android),
    ocr: createDeviceOcr(),
    storageUnavailable: storageUnavailable,
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(SiglaApp(services: services, navigatorKey: navigatorKey));
  // Avviso di nuova versione (Android, al massimo una volta al giorno, si spegne nelle impostazioni).
  if (settings.value.checkUpdates) unawaited(services.updates.check());
  // "Apri con" / "Condividi" un PDF (Android).
  // All'avvio la UI potrebbe non essere ancora pronta: si aspetta il navigatore (max 5 s).
  Future<BuildContext?> ready() async {
    for (var i = 0; i < 50 && navigatorKey.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final ctx = navigatorKey.currentContext;
    return ctx != null && ctx.mounted ? ctx : null;
  }

  await ShareIntentSource().start(
    (pdf) async {
      final ctx = await ready();
      if (ctx != null && ctx.mounted) await openPdfEditor(ctx, name: pdf.name, bytes: pdf.bytes);
    },
    onTooLarge: (name) async {
      final ctx = await ready();
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(tr('PDF troppo grande da aprire (massimo 100 MB).'))));
      }
    },
  );
}
