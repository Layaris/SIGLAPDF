import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/features/documents/autofill/autofill.dart';
import 'package:sigla/features/documents/autofill/autofill_preview_page.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/field_detection/local_text_detector.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';

Future<List<DetectedField>> _detect(Uint8List bytes) {
  final info = const PdfService().inspect(bytes);
  return const LocalTextFieldDetector().detect(DetectionInput(pdf: bytes, pages: info.pages));
}

void main() {
  test('caselle Sì/No e M/F con le loro opzioni', () async {
    final fields = await _detect(buildChoicesPdf());
    final yn = fields.firstWhere((f) => f.kind == FieldKind.yesNo);
    expect(yn.options.map((o) => o.label), ['Sì', 'No']);
    expect(yn.label, contains('Autorizza'));
    expect(yn.options.first.rect.x, lessThan(yn.options.last.rect.x));
    final g = fields.firstWhere((f) => f.kind == FieldKind.gender);
    expect(g.options.map((o) => o.label), ['M', 'F']);
    expect(fields.where((f) => f.kind == FieldKind.lastName), hasLength(1), reason: 'gli altri campi restano');
    expect(fields.where((f) => f.kind == FieldKind.gender), hasLength(1), reason: '"Sesso:" non crea anche un campo di testo');
  });

  test('caselle dopo l\'opzione: "Sì [ ] No [ ]" e "M [ ] F [ ]"', () async {
    final bytes = buildChoicesAfterPdf();
    final fields = await _detect(bytes);
    final yn = fields.firstWhere((f) => f.kind == FieldKind.yesNo);
    expect(yn.options.map((o) => o.label), ['Sì', 'No']);
    expect(yn.label, 'Desidero ricevere la newsletter', reason: 'l\'etichetta non contiene "Sì"');
    final g = fields.firstWhere((f) => f.kind == FieldKind.gender);
    expect(g.options.map((o) => o.label), ['M', 'F']);
    expect(g.label, 'Sesso');
    expect(g.options.first.rect.x, lessThan(g.options.last.rect.x));
  });

  test('"Sesso M F" senza caselle', () async {
    final fields = await _detect(buildGenderLettersPdf());
    final g = fields.firstWhere((f) => f.kind == FieldKind.gender);
    expect(g.options.map((o) => o.label), ['M', 'F']);
  });

  test('proposte: sesso dal profilo, Sì/No da scegliere; spunta sulla casella', () async {
    final fields = await _detect(buildChoicesPdf());
    const profile = Profile(values: {ProfileField.gender: 'F', ProfileField.lastName: 'Rossi'});
    final props = buildProposals(fields, profile, today: '');
    final g = props.firstWhere((p) => p.field.kind == FieldKind.gender);
    expect(g.value, 'F');
    expect(g.include, isTrue);
    final yn = props.firstWhere((p) => p.field.kind == FieldKind.yesNo);
    expect(yn.include, isFalse);
    yn
      ..value = 'Sì'
      ..include = true;
    final pages = const PdfService().inspect(buildChoicesPdf()).pages;
    final els = proposalsToElements(props, pages: pages, color: 0xFF111111);
    final checks = els.where((e) => e.type == ElementType.check).toList();
    expect(checks, hasLength(2));
    final fBox = g.field.options.firstWhere((o) => o.label == 'F').rect;
    // La spunta del sesso è sulla riga di "Sesso" (la prima è quella del Sì, una riga sopra).
    final c = checks.firstWhere((e) => (e.rect.y + e.rect.h / 2 - (fBox.y + fBox.h / 2)).abs() < 0.01).rect;
    expect((c.x + c.w / 2 - (fBox.x + fBox.w / 2)).abs(), lessThan(0.01), reason: 'spunta centrata sulla casella F');
  });

  testWidgets('anteprima: scelta Sì/No con i chip', (tester) async {
    final fields = await tester.runAsync(() => _detect(buildChoicesPdf()));
    final props = buildProposals(fields!.where((f) => f.kind == FieldKind.yesNo).toList(), const Profile(), today: '');
    List<FillProposal>? confirmed;
    await tester.pumpWidget(wrapWithServices(
      AppServices.inMemory(),
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => confirmed = await Navigator.of(context).push<List<FillProposal>>(
            MaterialPageRoute(builder: (_) => AutofillPreviewPage(proposals: props, hasSignature: false)),
          ),
          child: const Text('apri'),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Nessuna'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sì'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inserisci 1 campo'));
    await tester.pumpAndSettle();
    expect(confirmed!.single.value, 'Sì');
  });
}
