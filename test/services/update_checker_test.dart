import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/storage/key_value_store.dart';
import 'package:sigla/features/documents/documents_page.dart';
import 'package:sigla/services/update_checker.dart';

import '../test_helpers.dart';

String _latest(int build) => jsonEncode({
      'app': 'sigla',
      'version': '1.1.0',
      'build': build,
      'apk': 'https://github.com/Layaris/DMReleases/releases/download/sigla-build-$build/Sigla-build-$build.apk',
    });

void main() {
  test('parseLatest: solo build più nuove, solo link GitHub', () {
    expect(UpdateService.parseLatest(_latest(12), 10)!.build, 12);
    expect(UpdateService.parseLatest(_latest(10), 10), isNull);
    expect(UpdateService.parseLatest('{"app":"sigla","build":20,"apk":"https://evil.example/x.apk"}', 1), isNull);
    expect(UpdateService.parseLatest('{"app":"altra","build":20}', 1), isNull);
    expect(UpdateService.parseLatest('{"app":"sigla","build":20,"apk":"https://github.com/altro/repo/releases/download/x/y.apk"}', 1), isNull,
        reason: 'solo le release di Layaris/DMReleases');
    expect(UpdateService.parseLatest('non json', 1), isNull);
  });

  test('controlla al massimo una volta al giorno; "Non ora" non ripropone la stessa build', () async {
    var calls = 0;
    var now = DateTime(2026, 11, 8, 10);
    final client = MockClient((req) async {
      calls++;
      expect(req.url, UpdateService.latestUrl);
      return http.Response(_latest(12), 200);
    });
    final store = MemoryKeyValueStore();
    final s = UpdateService(store, client: client, currentBuild: 10, enabledOnPlatform: true, clock: () => now);
    expect((await s.check())!.build, 12);
    await s.check();
    expect(calls, 1, reason: 'stesso giorno: niente nuova richiesta');
    await s.dismiss();
    expect(s.available, isNull);
    now = now.add(const Duration(days: 1));
    expect(await s.check(), isNull, reason: 'build già rifiutata');
    expect(calls, 2);
    expect((await s.check(force: true))!.build, 12, reason: '"Controlla ora" la mostra comunque');
  });

  test('web, build di sviluppo o rete assente: nessun avviso', () async {
    final web = UpdateService(MemoryKeyValueStore(), currentBuild: 10);
    expect(web.supported, isFalse);
    expect(await web.check(), isNull);
    final dev = UpdateService(MemoryKeyValueStore(), currentBuild: null, enabledOnPlatform: true);
    expect(dev.supported, isFalse);
    final offline = UpdateService(MemoryKeyValueStore(),
        client: MockClient((_) async => throw http.ClientException('offline')), currentBuild: 1, enabledOnPlatform: true);
    expect(await offline.check(), isNull);
    expect(offline.lastCheckFailed, isTrue, reason: '"Controlla ora" deve dire che il controllo non è riuscito');
    expect(await offline.check(), isNull, reason: 'offline non segna l\'ora: riprova subito');
  });

  testWidgets('documenti: banner con Scarica e Non ora', (tester) async {
    final updates = UpdateService(MemoryKeyValueStore(),
        client: MockClient((_) async => http.Response(_latest(12), 200)), currentBuild: 10, enabledOnPlatform: true);
    final s = AppServices.inMemory(updates: updates);
    await tester.runAsync(() => updates.check());
    await tester.pumpWidget(wrapWithServices(s, const DocumentsPage()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('Nuova versione di Sigla 1.1.0 (build 12)'), findsOneWidget);
    expect(find.text('Scarica'), findsOneWidget);
    await tester.tap(find.text('Non ora'));
    await tester.pump();
    expect(find.textContaining('Nuova versione'), findsNothing);
  });
}
