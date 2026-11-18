import 'package:flutter/material.dart';

import '../../services/field_detection/ai_detector.dart';

/// Impostazioni dell'app. Le chiavi API restano solo sul dispositivo e non vanno nel backup.
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
    this.aiMode = 'auto',
    this.geminiApiKey = '',
    this.geminiModel = '',
    this.nanoGptApiKey = '',
    this.nanoGptModel = '',
    this.keepRecents = true,
    this.checkUpdates = true,
    this.language = 'it',
  });

  static const defaultAiModel = 'claude-haiku-5-5';

  final ThemeMode themeMode;
  final String inkColor; // 'blue' | 'black'
  final double penWidth;
  final bool biometricLock;
  final bool aiEnabled;
  final String aiApiKey;
  final String aiModel;

  /// Servizio AI: 'auto' (prima Gemini, poi NanoGPT, poi Claude, fra quelli con la chiave) oppure il nome
  /// di un [AiProvider] per usare solo quello.
  final String aiMode;
  final String geminiApiKey;

  /// Modello Gemini; vuoto = predefinito ([AiProvider.defaultModel]).
  final String geminiModel;
  final String nanoGptApiKey;
  final String nanoGptModel;

  /// Chiave e modello di un servizio.
  AiAccess access(AiProvider p) => switch (p) {
        AiProvider.gemini => AiAccess(p, geminiApiKey, geminiModel),
        AiProvider.nanogpt => AiAccess(p, nanoGptApiKey, nanoGptModel),
        AiProvider.anthropic => AiAccess(p, aiApiKey, aiModel),
      };

  /// Servizi da provare, in ordine, fra quelli con la chiave.
  List<AiAccess> get aiChain {
    final only = AiProvider.parse(aiMode);
    return [
      for (final p in only == null ? AiProvider.values : [only])
        if (access(p).apiKey.trim().isNotEmpty) access(p),
    ];
  }

  /// Ricorda gli ultimi PDF esportati (solo sul dispositivo).
  final bool keepRecents;

  /// Avvisa quando su DMReleases c'è una versione nuova (solo app Android).
  final bool checkUpdates;

  /// Lingua dell'interfaccia: 'it', 'en' oppure 'system'.
  final String language;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? inkColor,
    double? penWidth,
    bool? biometricLock,
    bool? aiEnabled,
    String? aiApiKey,
    String? aiModel,
    String? aiMode,
    String? geminiApiKey,
    String? geminiModel,
    String? nanoGptApiKey,
    String? nanoGptModel,
    bool? keepRecents,
    bool? checkUpdates,
    String? language,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        inkColor: inkColor ?? this.inkColor,
        penWidth: penWidth ?? this.penWidth,
        biometricLock: biometricLock ?? this.biometricLock,
        aiEnabled: aiEnabled ?? this.aiEnabled,
        aiApiKey: aiApiKey ?? this.aiApiKey,
        aiModel: aiModel ?? this.aiModel,
        aiMode: aiMode ?? this.aiMode,
        geminiApiKey: geminiApiKey ?? this.geminiApiKey,
        geminiModel: geminiModel ?? this.geminiModel,
        nanoGptApiKey: nanoGptApiKey ?? this.nanoGptApiKey,
        nanoGptModel: nanoGptModel ?? this.nanoGptModel,
        keepRecents: keepRecents ?? this.keepRecents,
        checkUpdates: checkUpdates ?? this.checkUpdates,
        language: language ?? this.language,
      );

  /// Mappa completa (archivio locale).
  Map<String, dynamic> toMap() => {
        ...toBackupMap(),
        'aiApiKey': aiApiKey,
        'geminiApiKey': geminiApiKey,
        'nanoGptApiKey': nanoGptApiKey,
      };

  /// Mappa per il backup: senza le chiavi API.
  Map<String, dynamic> toBackupMap() => {
        'themeMode': themeMode.name,
        'inkColor': inkColor,
        'penWidth': penWidth,
        'biometricLock': biometricLock,
        'aiEnabled': aiEnabled,
        'aiModel': aiModel,
        'aiMode': aiMode,
        'geminiModel': geminiModel,
        'nanoGptModel': nanoGptModel,
        'keepRecents': keepRecents,
        'checkUpdates': checkUpdates,
        'language': language,
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
      aiMode: AiProvider.parse(m['aiMode'] as String?)?.name ?? 'auto',
      geminiApiKey: (m['geminiApiKey'] as String?) ?? '',
      geminiModel: ((m['geminiModel'] as String?) ?? '').trim(),
      nanoGptApiKey: (m['nanoGptApiKey'] as String?) ?? '',
      nanoGptModel: ((m['nanoGptModel'] as String?) ?? '').trim(),
      keepRecents: m['keepRecents'] != false,
      checkUpdates: m['checkUpdates'] != false,
      language: const {'it', 'en', 'system'}.contains(m['language']) ? m['language'] as String : 'it',
    );
  }
}
