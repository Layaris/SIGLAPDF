import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/storage/key_value_store.dart';
import 'features/profile/profile_repository.dart';
import 'features/settings/settings_repository.dart';
import 'features/signatures/signature_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  await Hive.initFlutter('sigla');
  final settingsStore = await HiveKeyValueStore.open('settings');
  final signatureStore = await HiveKeyValueStore.open('signatures');
  final profileStore = await HiveKeyValueStore.open('profile');
  final services = AppServices(
    settings: SettingsRepository(settingsStore),
    signatures: SignatureRepository(signatureStore),
    profile: ProfileRepository(profileStore),
  );
  runApp(SiglaApp(services: services));
}
