import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/key_value_store.dart';
import 'profile_model.dart';

/// Profili per l'autocompilazione. Ce n'è sempre almeno uno; [value] è quello attivo.
class ProfileRepository extends ChangeNotifier {
  ProfileRepository(this._store) {
    final raw = _store.get(_listKey);
    if (raw is List) {
      for (final m in raw) {
        final p = NamedProfile.fromMap(asStringMap(m));
        if (p != null) _profiles.add(p);
      }
    }
    if (_profiles.isEmpty) {
      // Prima versione: un solo profilo sotto la chiave "profile".
      final legacy = Profile.fromMap(asStringMap(_store.get(_legacyKey)));
      _profiles.add(NamedProfile(id: _uuid.v4(), label: 'Io', profile: legacy));
    }
    final active = _store.get(_activeKey);
    _activeId = _profiles.any((p) => p.id == active) ? active! as String : _profiles.first.id;
  }

  static const _listKey = 'profiles';
  static const _activeKey = 'active';
  static const _legacyKey = 'profile';
  static const _uuid = Uuid();

  final KeyValueStore _store;
  final List<NamedProfile> _profiles = [];
  late String _activeId;

  List<NamedProfile> get profiles => List.unmodifiable(_profiles);
  String get activeId => _activeId;
  NamedProfile get active => _profiles.firstWhere((p) => p.id == _activeId);

  /// Profilo attivo.
  Profile get value => active.profile;

  NamedProfile? byId(String id) => _profiles.where((p) => p.id == id).firstOrNull;

  Future<void> _persist() async {
    await _store.put(_listKey, [for (final p in _profiles) p.toMap()]);
    await _store.put(_activeKey, _activeId);
    await _store.delete(_legacyKey);
  }

  /// Salva i dati del profilo attivo.
  Future<void> save(Profile p) async {
    final i = _profiles.indexWhere((x) => x.id == _activeId);
    _profiles[i] = _profiles[i].copyWith(profile: p);
    notifyListeners();
    await _persist();
  }

  Future<void> setActive(String id) async {
    if (id == _activeId || byId(id) == null) return;
    _activeId = id;
    notifyListeners();
    await _persist();
  }

  /// Crea un profilo vuoto e lo rende attivo.
  Future<NamedProfile> addProfile(String label) async {
    final p = NamedProfile(id: _uuid.v4(), label: label.trim().isEmpty ? 'Profilo ${_profiles.length + 1}' : label.trim(), profile: const Profile());
    _profiles.add(p);
    _activeId = p.id;
    notifyListeners();
    await _persist();
    return p;
  }

  Future<void> renameProfile(String id, String label) async {
    final i = _profiles.indexWhere((x) => x.id == id);
    if (i < 0 || label.trim().isEmpty) return;
    _profiles[i] = _profiles[i].copyWith(label: label.trim());
    notifyListeners();
    await _persist();
  }

  /// Elimina un profilo (non l'ultimo rimasto).
  Future<bool> removeProfile(String id) async {
    if (_profiles.length <= 1) return false;
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) _activeId = _profiles.first.id;
    notifyListeners();
    await _persist();
    return true;
  }

  /// Import da backup. [replace] usa solo i profili del backup; altrimenti unisce: stesso id o
  /// stesso nome → completa i campi vuoti, altrimenti aggiunge.
  Future<void> importProfiles(List<NamedProfile> incoming, {required bool replace, String? activeId}) async {
    if (incoming.isEmpty) return;
    if (replace) {
      _profiles
        ..clear()
        ..addAll(incoming);
      _activeId = incoming.any((p) => p.id == activeId) ? activeId! : incoming.first.id;
    } else {
      for (final p in incoming) {
        final i = _profiles.indexWhere((x) => x.id == p.id || x.label.toLowerCase() == p.label.toLowerCase());
        if (i >= 0) {
          _profiles[i] = _profiles[i].copyWith(profile: _profiles[i].profile.mergedWith(p.profile));
        } else {
          _profiles.add(p);
        }
      }
    }
    notifyListeners();
    await _persist();
  }

  /// Compatibilità: importa un singolo profilo nel profilo attivo.
  Future<void> importProfile(Profile p, {required bool replace}) => save(replace ? p : value.mergedWith(p));
}
