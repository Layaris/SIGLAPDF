import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/app.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/l10n/l10n.dart';
import 'package:sigla/core/l10n/strings_en.dart';

/// Chiavi tr('...') e valori degli enum tradotti nel codice sorgente.
Set<String> _sourceKeys() {
  final lit = r"'((?:[^'\\\n]|\\.)*)'";
  final keys = <String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final s = f.readAsStringSync();
    for (final m in RegExp(r'\btr\(\s*' + lit).allMatches(s)) {
      keys.add(m.group(1)!);
    }
    if (s.contains('String get label => tr(_it)')) {
      for (final m in RegExp(r'^\s*\w+\(' + lit + r'\)[,;]', multiLine: true).allMatches(s)) {
        keys.add(m.group(1)!);
      }
    }
  }
  // Le chiavi nel sorgente hanno gli escape Dart (\' e \n): si confrontano decodificate.
  return keys.map((k) => k.replaceAll(r"\'", "'").replaceAll(r'\n', '\n')).toSet();
}

void main() {
  tearDown(() => L10n.lang = 'it');

  test('ogni testo dell\'interfaccia ha la traduzione inglese', () {
    final missing = _sourceKeys().where((k) => !stringsEn.containsKey(k)).toList();
    expect(missing, isEmpty, reason: 'aggiungere in lib/core/l10n/strings_en.dart');
  });

  test('segnaposto uguali nelle due lingue', () {
    for (final e in stringsEn.entries) {
      final a = RegExp(r'\{\d\}').allMatches(e.key).map((m) => m.group(0)).toList()..sort();
      final b = RegExp(r'\{\d\}').allMatches(e.value).map((m) => m.group(0)).toList()..sort();
      expect(b, a, reason: e.key);
    }
  });

  test('tr: segnaposto e lingua', () {
    expect(tr('Inserisci {0} campi', [3]), 'Inserisci 3 campi');
    L10n.lang = 'en';
    expect(tr('Inserisci {0} campi', [3]), 'Insert 3 fields');
    expect(tr('testo senza traduzione'), 'testo senza traduzione');
    expect(L10n.resolve('system', 'it'), 'it');
    expect(L10n.resolve('system', 'de'), 'en');
    expect(L10n.resolve('it', 'en'), 'it');
  });

  testWidgets('l\'app passa all\'inglese e resta sulla scheda aperta', (tester) async {
    final services = AppServices.inMemory();
    await tester.pumpWidget(SiglaApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Documenti'), findsWidgets);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets, reason: 'resta su Impostazioni');
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Documents'), findsWidgets);
    await tester.tap(find.byIcon(Icons.draw_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Create your signature'), findsOneWidget);
    await services.settings.update((s) => s.copyWith(language: 'it'));
    await tester.pumpAndSettle();
    expect(find.text('Crea la tua firma'), findsOneWidget);
  });
}
