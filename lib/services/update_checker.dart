import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/app_info.dart';
import '../core/storage/key_value_store.dart';

/// Versione pubblicata su DMReleases più recente di quella installata.
@immutable
class UpdateInfo {
  const UpdateInfo({required this.build, required this.version, required this.url});
  final int build;
  final String version;
  final String url;
}

/// Controlla (al massimo una volta al giorno) se su DMReleases c'è un APK più recente.
/// Una sola richiesta anonima al file pubblico `sigla/latest.json`; nessun dato inviato.
class UpdateService extends ChangeNotifier {
  UpdateService(
    this._store, {
    http.Client? client,
    int? currentBuild,
    this.enabledOnPlatform = false,
    DateTime Function()? clock,
  })  : _client = client ?? http.Client(),
        currentBuild = currentBuild ?? int.tryParse(AppInfo.build),
        _clock = clock ?? DateTime.now;

  static final latestUrl = Uri.parse('https://raw.githubusercontent.com/Layaris/DMReleases/main/sigla/latest.json');
  static const _lastKey = 'lastCheck';
  static const _dismissedKey = 'dismissedBuild';

  final KeyValueStore _store;
  final http.Client _client;
  final DateTime Function() _clock;

  /// Build installata (null nelle build di sviluppo: niente controllo).
  final int? currentBuild;

  /// Solo l'app Android si aggiorna da DMReleases (la web app si aggiorna da sola).
  final bool enabledOnPlatform;

  UpdateInfo? _available;
  UpdateInfo? get available => _available;

  bool get supported => enabledOnPlatform && currentBuild != null;

  /// Controlla se è passato abbastanza tempo dall'ultima volta (o se [force]).
  Future<UpdateInfo?> check({bool force = false}) async {
    if (!supported) return null;
    final last = DateTime.tryParse(_store.get(_lastKey) as String? ?? '');
    if (!force && last != null && _clock().difference(last) < const Duration(hours: 20)) return _available;
    try {
      final res = await _client.get(latestUrl).timeout(const Duration(seconds: 15));
      await _store.put(_lastKey, _clock().toIso8601String());
      if (res.statusCode != 200) return null;
      final info = parseLatest(utf8.decode(res.bodyBytes), currentBuild!);
      final dismissed = (_store.get(_dismissedKey) as num?)?.toInt();
      _available = info != null && (force || info.build != dismissed) ? info : null;
      notifyListeners();
      return _available;
    } catch (_) {
      return null;
    }
  }

  /// "Non ora": non riproporre questa build.
  Future<void> dismiss() async {
    final a = _available;
    if (a == null) return;
    _available = null;
    notifyListeners();
    await _store.put(_dismissedKey, a.build);
  }

  /// Legge `latest.json`: restituisce l'APK se la build è più nuova di [current].
  static UpdateInfo? parseLatest(String json, int current) {
    try {
      final m = jsonDecode(json);
      if (m is! Map || m['app'] != 'sigla') return null;
      final build = (m['build'] as num?)?.toInt();
      final apk = m['apk'];
      if (build == null || apk is! String || !apk.startsWith('https://github.com/')) return null;
      if (build <= current) return null;
      return UpdateInfo(build: build, version: '${m['version'] ?? ''}', url: apk);
    } catch (_) {
      return null;
    }
  }
}
