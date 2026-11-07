import 'package:flutter/material.dart';

/// Impostazioni dell'app. La chiave API resta solo sul dispositivo e non va nel backup.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.inkColor = 'blue',
    this.penWidth = 3.0,
    this.biometricLock = false,
    this.aiEnabled = false,
    this.aiApiKey = '',
    this.aiModel = defaultAiModel,
  });

  static const defaultAiModel = 'claude-haiku-5-5';

  final ThemeMode themeMode;
  final String inkColor; // 'blue' | 'black'
  final double penWidth;
  final bool biometricLock;
  final bool aiEnabled;
  final String aiApiKey;
  final String aiModel;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? inkColor,
    double? penWidth,
    bool? biometricLock,
    bool? aiEnabled,
    String? aiApiKey,
    String? aiModel,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        inkColor: inkColor ?? this.inkColor,
        penWidth: penWidth ?? this.penWidth,
        biometricLock: biometricLock ?? this.biometricLock,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiApiKey: aiApiKey ?? this.aiApiKey,
        aiModel: aiModel ?? this.aiModel,
      );

  /// Mappa completa (archivio locale).
  Map<String, dynamic> toMap() => {
        ...toBackupMap(),
        'aiApiKey': aiApiKey,
      };

  /// Mappa per il backup: senza la chiave API.
  Map<String, dynamic> toBackupMap() => {
        'themeMode': themeMode.name,
        'inkColor': inkColor,
        'penWidth': penWidth,
        'biometricLock': biometricLock,
        'aiEnabled': aiEnabled,
        'aiModel': aiModel,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) {
    final theme = ThemeMode.values.where((t) => t.name == m['themeMode']).firstOrNull ?? ThemeMode.system;
    final ink = m['inkColor'] == 'black' ? 'black' : 'blue';
    final width = (m['penWidth'] as num?)?.toDouble() ?? 3.0;
    final model = (m['aiModel'] as String?)?.trim();
    return AppSettings(
      themeMode: theme,
      inkColor: ink,
      penWidth: width.clamp(1.0, 8.0),
      biometricLock: m['biometricLock'] == true,
      aiEnabled: m['aiEnabled'] == true,
      aiApiKey: (m['aiApiKey'] as String?) ?? '',
      aiModel: (model == null || model.isEmpty) ? defaultAiModel : model,
    );
  }
}
