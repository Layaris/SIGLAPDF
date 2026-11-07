import 'package:flutter/widgets.dart';

import '../features/profile/profile_repository.dart';
import '../features/settings/settings_repository.dart';
import '../features/settings/signature_lock.dart';
import '../features/signatures/signature_repository.dart';
import '../services/field_detection/ocr.dart';
import 'storage/key_value_store.dart';
import 'utils/file_access.dart';

/// Contenitore dei repository e servizi dell'app.
/// Passato all'albero con [AppScope]; nei test si costruisce con store in memoria.
class AppServices {
  AppServices({
    required this.settings,
    required this.signatures,
    required this.profile,
    required this.lock,
    this.files = const SystemFileAccess(),
    this.ocr,
  });

  final SettingsRepository settings;
  final SignatureRepository signatures;
  final ProfileRepository profile;
  final SignatureLock lock;
  final FileAccess files;

  /// OCR sul dispositivo per i PDF scansionati (Android), null dove non c'è.
  final OcrEngine? ocr;

  /// Servizi con archivio in memoria (test e anteprime).
  factory AppServices.inMemory({
    FileAccess files = const SystemFileAccess(),
    Authenticator? auth,
    bool isWeb = false,
    OcrEngine? ocr,
  }) {
    final settings = SettingsRepository(MemoryKeyValueStore());
    return AppServices(
      settings: settings,
      signatures: SignatureRepository(MemoryKeyValueStore()),
      profile: ProfileRepository(MemoryKeyValueStore()),
      lock: SignatureLock(settings, auth ?? _AlwaysYes(), isWeb: isWeb),
      files: files,
      ocr: ocr,
    );
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope mancante sopra a questo widget');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}

class _AlwaysYes implements Authenticator {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> authenticate(String reason) async => true;
}
