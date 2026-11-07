import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/app.dart';
import 'package:sigla/core/app_services.dart';

void main() {
  testWidgets('mostra le quattro sezioni e cambia scheda', (tester) async {
    await tester.pumpWidget(SiglaApp(services: AppServices.inMemory()));
    await tester.pumpAndSettle();

    for (final label in ['Documenti', 'Firme', 'Profilo', 'Impostazioni']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Profilo'), findsOneWidget);
  });
}
