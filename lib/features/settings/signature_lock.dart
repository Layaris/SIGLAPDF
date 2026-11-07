import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/app_services.dart';
import 'settings_repository.dart';

/// Autenticazione del dispositivo (impronta, volto o PIN), sostituibile nei test.
abstract class Authenticator {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class DeviceAuthenticator implements Authenticator {
  DeviceAuthenticator([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    if (kIsWeb) return true;
    try {
      // biometricOnly: false → se la biometria non c'è si può usare il PIN del dispositivo.
      return await _auth.authenticate(localizedReason: reason, biometricOnly: false, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }
}

/// Blocco delle firme: se attivo, serve l'autenticazione per vederle o usarle.
/// Si richiude quando l'app va in background. Sul web è sempre disattivato.
class SignatureLock extends ChangeNotifier {
  SignatureLock(this._settings, this._auth, {this.isWeb = kIsWeb});

  final SettingsRepository _settings;
  final Authenticator _auth;
  final bool isWeb;
  bool _unlocked = false;
  Future<bool>? _pending;

  bool get enabled => !isWeb && _settings.value.biometricLock;
  bool get isLocked => enabled && !_unlocked;

  Future<bool> isAvailable() => isWeb ? Future.value(false) : _auth.isAvailable();

  Future<bool> unlock() {
    if (!isLocked) return Future.value(true);
    return _pending ??= _auth.authenticate('Sblocca le tue firme').then((ok) {
      _pending = null;
      if (ok) {
        _unlocked = true;
        notifyListeners();
      }
      return ok;
    });
  }

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }

  /// Attiva o disattiva il blocco: in entrambi i casi chiede l'autenticazione.
  Future<bool> setEnabled(bool value) async {
    if (isWeb) return false;
    if (value && !await _auth.isAvailable()) return false;
    final ok = await _auth.authenticate(value ? 'Attiva il blocco delle firme' : 'Disattiva il blocco delle firme');
    if (!ok) return false;
    await _settings.update((s) => s.copyWith(biometricLock: value));
    _unlocked = true;
    notifyListeners();
    return true;
  }
}

/// Verifica che le firme siano sbloccate prima di usarle.
Future<bool> ensureSignaturesUnlocked(BuildContext context) => AppScope.of(context).lock.unlock();
