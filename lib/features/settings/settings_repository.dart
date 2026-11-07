import 'package:flutter/foundation.dart';

import '../../core/storage/key_value_store.dart';
import 'settings_model.dart';

class SettingsRepository extends ChangeNotifier {
  SettingsRepository(this._store) : _settings = AppSettings.fromMap(asStringMap(_store.get(_key)));

  static const _key = 'settings';
  final KeyValueStore _store;
  AppSettings _settings;

  AppSettings get value => _settings;

  Future<void> update(AppSettings Function(AppSettings s) change) async {
    _settings = change(_settings);
    notifyListeners();
    await _store.put(_key, _settings.toMap());
  }

  /// Sostituisce le impostazioni con quelle di un backup, mantenendo la chiave API locale.
  Future<void> restoreFromBackup(Map<String, dynamic> map) async {
    final restored = AppSettings.fromMap(map).copyWith(aiApiKey: _settings.aiApiKey);
    _settings = restored;
    notifyListeners();
    await _store.put(_key, _settings.toMap());
  }
}
