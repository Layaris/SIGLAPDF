import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/editor_page.dart';
import 'package:sigla/features/settings/settings_page.dart';
import 'package:sigla/features/settings/signature_lock.dart';
import 'package:sigla/features/signatures/signatures_page.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';
import 'editor_page_test.dart' show fakeRaster;

class FakeAuth implements Authenticator {
  FakeAuth({this.available = true, this.answer = true});
  bool available;
  bool answer;
  int calls = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return answer;
  }
}

void main() {
  test('blocco firme: attiva, si richiude, sblocca solo con autenticazione', () async {
    final auth = FakeAuth();
    final s = AppServices.inMemory(auth: auth);
    final lock = s.lock;
    expect(lock.isLocked, isFalse);
    expect(await lock.setEnabled(true), isTrue);
    expect(s.settings.value.biometricLock, isTrue);
    expect(lock.isLocked, isFalse, reason: 'appena attivato resta sbloccato');
    lock.lock();
    expect(lock.isLocked, isTrue);
    auth.answer = false;
    expect(await lock.unlock(), isFalse);
    expect(lock.isLocked, isTrue);
    auth.answer = true;
    expect(await lock.unlock(), isTrue);
    expect(lock.isLocked, isFalse);
    // Senza biometria disponibile non si attiva.
    final s2 = AppServices.inMemory(auth: FakeAuth(available: false));
    expect(await s2.lock.setEnabled(true), isFalse);
    // Sul web è sempre disattivato.
    final web = AppServices.inMemory(isWeb: true);
    await web.settings.update((x) => x.copyWith(biometricLock: true));
    expect(web.lock.isLocked, isFalse);
    expect(await web.lock.setEnabled(true), isFalse);
  });

  testWidgets('firme bloccate: schermata di sblocco', (tester) async {
    final auth = FakeAuth();
    final s = AppServices.inMemory(auth: auth);
    await s.lock.setEnabled(true);
    s.lock.lock();
    await tester.pumpWidget(wrapWithServices(s, const SignaturesPage()));
    expect(find.text('Firme protette'), findsOneWidget);
    await tester.tap(find.text('Sblocca'));
    await tester.pumpAndSettle();
    expect(find.text('Crea la tua firma'), findsOneWidget);
  });

  testWidgets('impostazioni: tema, inchiostro, AI con avviso, nota legale', (tester) async {
    final s = AppServices.inMemory();
    await tester.pumpWidget(wrapWithServices(s, const SettingsPage()));
    await tester.tap(find.text('Scuro'));
    await tester.pump();
    expect(s.settings.value.themeMode, ThemeMode.dark);
    await tester.tap(find.text('Nero'));
    await tester.pump();
    expect(s.settings.value.inkColor, 'black');

    await tester.tap(find.text('Usa il riconoscimento AI'));
    await tester.pumpAndSettle();
    expect(s.settings.value.aiEnabled, isTrue);
    await tester.scrollUntilVisible(find.widgetWithText(TextField, 'Modello'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining("inviate come immagini all'API di Anthropic"), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Chiave API Anthropic'), ' sk-ant-123 ');
    expect(s.settings.value.aiApiKey, 'sk-ant-123');
    expect(s.settings.value.aiModel, 'claude-haiku-5-5');

    await tester.scrollUntilVisible(find.textContaining('firma elettronica semplice'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('eIDAS'), findsOneWidget);
    expect(find.text('Esporta backup'), findsOneWidget);
  });

  testWidgets('editor: con AI attiva chiede il motore e serve la chiave', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    final s = AppServices.inMemory();
    await s.settings.update((x) => x.copyWith(aiEnabled: true));
    final bytes = buildUnmarkedFormPdf();
    await tester.pumpWidget(wrapWithServices(
      s,
      EditorPage(
        controller: EditorController(fileName: 'm.pdf', bytes: bytes, info: const PdfService().inspect(bytes)),
        rasterizer: fakeRaster,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compila'));
    await tester.pumpAndSettle();
    expect(find.text('Come cercare i campi?'), findsOneWidget);
    await tester.tap(find.text('AI avanzata'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Inserisci la chiave API'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}
