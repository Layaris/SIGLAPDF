import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sigla/core/app_services.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/features/signatures/import/import_signature_page.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/features/signatures/typed/typed_renderer.dart';
import 'package:sigla/features/signatures/typed/typed_signature_page.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('firma scritta: propone il nome del profilo e salva un PNG', (tester) async {
    final services = AppServices.inMemory();
    await services.profile.save(const Profile(values: {ProfileField.firstName: 'Mario', ProfileField.lastName: 'Rossi'}));
    await tester.pumpWidget(wrapWithServices(services, const TypedSignaturePage()));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Mario Rossi'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Salva').last);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    final saved = services.signatures.all.single;
    expect(saved.source, SignatureSource.typed);
    expect(saved.name, 'Firma');
    expect(img.decodePng(saved.png)!.numChannels, 4);
  });

  testWidgets('renderTypedSignature con testo vuoto restituisce null', (tester) async {
    final r = await tester.runAsync(() => renderTypedSignature('  ', color: Colors.blue));
    expect(r, isNull);
  });

  testWidgets('import da immagine mostra anteprima, soglia e colore', (tester) async {
    final im = img.Image(width: 300, height: 120);
    img.fill(im, color: img.ColorRgb8(235, 235, 235));
    img.fillRect(im, x1: 50, y1: 50, x2: 250, y2: 60, color: img.ColorRgb8(20, 20, 60));
    final bytes = img.encodePng(im);
    final services = AppServices.inMemory();
    await tester.pumpWidget(wrapWithServices(
      services,
      ImportSignaturePage(kind: SignatureKind.signature, origin: ImageOrigin.file, initialBytes: bytes),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Anteprima della firma scontornata'), findsOneWidget);
    expect(find.text('Soglia'), findsOneWidget);
    expect(find.text('Blu'), findsOneWidget);
  });
}
