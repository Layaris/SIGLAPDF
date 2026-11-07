import 'package:flutter/foundation.dart';

import '../../core/storage/key_value_store.dart';
import 'profile_model.dart';

class ProfileRepository extends ChangeNotifier {
  ProfileRepository(this._store) : _profile = Profile.fromMap(asStringMap(_store.get(_key)));

  static const _key = 'profile';
  final KeyValueStore _store;
  Profile _profile;

  Profile get value => _profile;

  Future<void> save(Profile p) async {
    _profile = p;
    notifyListeners();
    await _store.put(_key, p.toMap());
  }

  Future<void> importProfile(Profile p, {required bool replace}) => save(replace ? p : _profile.mergedWith(p));
}
