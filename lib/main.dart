import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/storage/key_value_store.dart';
import 'features/documents/editor/editor_page.dart';
import 'features/profile/profile_repository.dart';
import 'features/settings/settings_repository.dart';
import 'features/settings/signature_lock.dart';
import 'features/signatures/signature_repository.dart';
import 'services/document_sources.dart';
import 'services/field_detection/ocr.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  await Hive.initFlutter('sigla');
  final settingsStore = await HiveKeyValueStore.open('settings');
  final signatureStore = await HiveKeyValueStore.open('signatures');
  final profileStore = await HiveKeyValueStore.open('profile');
  final settings = SettingsRepository(settingsStore);
  final services = AppServices(
    settings: settings,
    lock: SignatureLock(settings, DeviceAuthenticator()),
    signatures: SignatureRepository(signatureStore),
    profile: ProfileRepository(profileStore),
    ocr: createDeviceOcr(),
  );
  final navigatorKey = GlobalKey<NavigatorState>();
  runApp(SiglaApp(services: services, navigatorKey: navigatorKey));
  // "Apri con" / "Condividi" un PDF (Android).
  await ShareIntentSource().start((pdf) async {
    // All'avvio la UI potrebbe non essere ancora pronta: si aspetta il navigatore (max 5 s).
    for (var i = 0; i < 50 && navigatorKey.currentContext == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final ctx = navigatorKey.currentContext;
    if (ctx != null && ctx.mounted) await openPdfEditor(ctx, name: pdf.name, bytes: pdf.bytes);
  });
}
