import 'package:flutter/widgets.dart';

import '../features/settings/settings_repository.dart';
import '../features/signatures/signature_repository.dart';
import 'storage/key_value_store.dart';

/// Contenitore dei repository e servizi dell'app.
/// Passato all'albero con [AppScope]; nei test si costruisce con store in memoria.
class AppServices {
  AppServices({required this.settings, required this.signatures});

  final SettingsRepository settings;
  final SignatureRepository signatures;

  /// Servizi con archivio in memoria (test e anteprime).
  factory AppServices.inMemory() => AppServices(
        settings: SettingsRepository(MemoryKeyValueStore()),
        signatures: SignatureRepository(MemoryKeyValueStore()),
      );
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
