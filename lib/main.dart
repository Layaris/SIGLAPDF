import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_services.dart';
import 'core/storage/key_value_store.dart';
import 'features/settings/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');
  await Hive.initFlutter('sigla');
  final settingsStore = await HiveKeyValueStore.open('settings');
  final services = AppServices(settings: SettingsRepository(settingsStore));
  runApp(SiglaApp(services: services));
}
