import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/features/documents/autofill/autofill_preview_page.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/editor_page.dart';
import 'package:sigla/features/documents/editor/element_factory.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/features/profile/profile_page.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';
import 'editor_page_test.dart' show fakeRaster;

void main() {
  testWidgets('profilo: salva da solo e aggiunge dati personalizzati', (tester) async {
    final services = AppServices.inMemory();
    await tester.pumpWidget(wrapWithServices(services, const ProfilePage()));
    await tester.enterText(find.widgetWithText(TextField, 'Nome'), 'Mario');
    await tester.enterText(find.widgetWithText(TextField, 'Codice fiscale'), 'rssmra');
    await tester.pump(const Duration(milliseconds: 600));
    expect(services.profile.value[ProfileField.firstName], 'Mario');
    expect(services.profile.value[ProfileField.taxCode], 'RSSMRA', reason: 'maiuscolo automatico');
    expect(find.text('Salvato'), findsOneWidget);
    expect(find.text('Il codice fiscale di solito ha 16 caratteri.'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Aggiungi un dato'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Aggiungi un dato'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Nome del dato'), 'Patente');
    await tester.enterText(find.widgetWithText(TextField, 'Valore'), 'U123');
    await tester.pump(const Duration(milliseconds: 600));
    expect(services.profile.value.custom.single, const CustomField('Patente', 'U123'));
  });

  Future<EditorPage> pumpEditor(WidgetTester tester, AppServices services, {bool form = false}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    final bytes = form ? buildFormPdf() : buildUnmarkedFormPdf();
    final page = EditorPage(
      controller: EditorController(fileName: 'modulo.pdf', bytes: bytes, info: const PdfService().inspect(bytes)),
      rasterizer: fakeRaster,
    );
    await tester.pumpWidget(wrapWithServices(services, page));
    await tester.pumpAndSettle();
    return page;
  }

  testWidgets('compila automaticamente: anteprima, conferma, inserimento', (tester) async {
    final services = AppServices.inMemory();
    await services.profile.save(const Profile(values: {
      ProfileField.firstName: 'Mario',
      ProfileField.lastName: 'Rossi',
      ProfileField.taxCode: 'RSSMRA80B01F839X',
    }));
    final page = await pumpEditor(tester, services);
    await tester.tap(find.text('Compila'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(find.byType(AutofillPreviewPage), findsOneWidget);
    expect(find.text('Campi trovati'), findsOneWidget);
    expect(find.text('Mario Rossi'), findsOneWidget);
    // Nome completo e codice fiscale dal profilo, più "Luogo e data" con la data di oggi.
    expect(find.text('"Il/La sottoscritto/a" · pagina 1'), findsOneWidget);
    expect(find.text('Inserisci 3 campi'), findsOneWidget);
    await tester.tap(find.text('Inserisci 3 campi'));
    await tester.pumpAndSettle();
    final texts = page.controller.elements.where((e) => e.type == ElementType.text).map((e) => e.text).toSet();
    expect(texts, {'Mario Rossi', 'RSSMRA80B01F839X', todayText()});
    expect(find.text('Inseriti 3 campi'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('campi AcroForm: pannello, autocompilazione dal profilo e annulla', (tester) async {
    final services = AppServices.inMemory();
    await services.profile.save(const Profile(values: {ProfileField.firstName: 'Anna', ProfileField.lastName: 'Verdi'}));
    final page = await pumpEditor(tester, services, form: true);
    expect(find.bySemanticsLabel('Campo nome'), findsOneWidget);
    await tester.tap(find.text('Campi'));
    await tester.pumpAndSettle();
    expect(find.text('Campi del modulo'), findsOneWidget);
    await tester.tap(find.text('Dal profilo'));
    await tester.pumpAndSettle();
    // Il campo "nome" è riconosciuto come nome di battesimo.
    expect(page.controller.formValues['nome'], 'Anna');
    expect(page.controller.formValues['citta'], 'Milano', reason: 'i campi già compilati restano');
    await tester.enterText(find.widgetWithText(TextField, 'nome · pag. 1'), 'Annalisa');
    await tester.pump();
    expect(page.controller.formValues['nome'], 'Annalisa');
    page.controller.undo();
    expect(page.controller.formValues['nome'], 'Anna', reason: 'la digitazione è un solo passo');
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('dati profilo: inserisce un valore come testo', (tester) async {
    final services = AppServices.inMemory();
    await services.profile.save(const Profile(values: {ProfileField.email: 'a@b.it'}));
    final page = await pumpEditor(tester, services);
    await tester.tap(find.text('Dati profilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('a@b.it'));
    await tester.pumpAndSettle();
    expect(page.controller.elements.single.text, 'a@b.it');
    await tester.binding.setSurfaceSize(null);
  });
}
