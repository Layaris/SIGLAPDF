import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/features/signatures/drawing/draw_signature_page.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/features/signatures/signatures_page.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('stato vuoto invita a creare una firma e apre il disegno', (tester) async {
    final services = AppServices.inMemory();
    await tester.pumpWidget(wrapWithServices(services, const SignaturesPage()));
    expect(find.text('Crea la tua firma'), findsOneWidget);
    await tester.tap(find.text('Nuova firma'));
    await tester.pumpAndSettle();
    expect(find.text('Disegna'), findsOneWidget);
    await tester.tap(find.text('Disegna'));
    await tester.pumpAndSettle();
    expect(find.byType(DrawSignaturePage), findsOneWidget);
    expect(find.text('Firma qui'), findsNothing, reason: 'il suggerimento è disegnato nel canvas');
  });

  testWidgets('mostra le firme salvate con la predefinita e le sezioni', (tester) async {
    final services = AppServices.inMemory();
    await services.signatures.add(
      name: 'Mario',
      kind: SignatureKind.signature,
      source: SignatureSource.drawn,
      png: tinyPng(),
      width: 4,
      height: 2,
    );
    await tester.pumpWidget(wrapWithServices(services, const SignaturesPage()));
    await tester.pump();
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Predefinita'), findsOneWidget);
    expect(find.text('Sigle'), findsOneWidget);
    expect(find.textContaining('Nessuna sigla'), findsOneWidget);
    expect(find.bySemanticsLabel('Firma: Mario'), findsOneWidget);
  });

  testWidgets('disegna e salva una firma', (tester) async {
    final services = AppServices.inMemory();
    await tester.pumpWidget(wrapWithServices(services, const DrawSignaturePage()));
    final area = find.bySemanticsLabel('Area di disegno della firma');
    final box = tester.getRect(area);
    final gesture = await tester.startGesture(box.center - const Offset(80, 0));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(16, 3));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Dai un nome'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Salva').last);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(services.signatures.all, hasLength(1));
    expect(services.signatures.all.single.png, isNot(Uint8List(0)));
  });
}
