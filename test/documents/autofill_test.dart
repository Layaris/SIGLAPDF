import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/utils/pdf_coords.dart';
import 'package:sigla/features/documents/autofill/autofill.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/field_detection/local_text_detector.dart';
import 'package:sigla/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';

const _profile = Profile(values: {
  ProfileField.firstName: 'Mario',
  ProfileField.lastName: 'Rossi',
  ProfileField.birthPlace: 'Napoli',
  ProfileField.birthDate: '01/02/1980',
  ProfileField.taxCode: 'RSSMRA80B01F839X',
  ProfileField.city: 'Roma',
  ProfileField.address: 'Via Roma 1',
  ProfileField.zip: '00100',
  ProfileField.email: 'mario@example.com',
});

DetectedField _f(FieldKind k, {double y = 0.1}) =>
    DetectedField(page: 0, kind: k, label: k.label, rect: NormRect(0.2, y, 0.4, 0.02), source: 'locale');

void main() {
  test('proposte: ordinate, valori dal profilo, vuote escluse', () {
    final props = buildProposals(
      [_f(FieldKind.email, y: 0.5), _f(FieldKind.fullName, y: 0.1), _f(FieldKind.phone, y: 0.3), _f(FieldKind.signature, y: 0.8)],
      _profile,
      today: '07/11/2026',
    );
    expect(props.map((p) => p.field.kind), [FieldKind.fullName, FieldKind.phone, FieldKind.email, FieldKind.signature]);
    expect(props[0].value, 'Mario Rossi');
    expect(props[0].include, isTrue);
    expect(props[1].include, isFalse, reason: 'telefono assente nel profilo');
    expect(props[3].include, isFalse, reason: 'nessuna firma salvata');
  });

  test('dalle proposte agli elementi: testi sopra la linea e firma proporzionata', () {
    final pdf = buildPlainPdf(pages: 1);
    final pages = const PdfService().inspect(pdf).pages;
    final props = buildProposals([_f(FieldKind.fullName), _f(FieldKind.signature, y: 0.8)], _profile, today: '', hasSignature: true);
    final els = proposalsToElements(props, pages: pages, color: 0xFF111111, signaturePng: tinyPng(), signatureAspect: 2);
    expect(els, hasLength(2));
    final text = els.firstWhere((e) => e.type == ElementType.text);
    expect(text.text, 'Mario Rossi');
    expect(text.rect.bottom, closeTo(0.12, 0.001), reason: 'allineato al fondo dello spazio');
    expect(text.rect.h, greaterThan(0.02), reason: 'un po\' più alto della riga trovata');
    final sign = els.firstWhere((e) => e.type == ElementType.signature);
    final px = sign.rect.toRect(pages[0].visual);
    expect(px.width / px.height, closeTo(2, 0.01));
    // Proposta esclusa → nessun elemento.
    props[0].include = false;
    expect(proposalsToElements(props, pages: pages, color: 0, signaturePng: null), isEmpty);
  });

  test('AcroForm: valori dal profilo solo per i campi vuoti riconosciuti', () {
    const fields = [
      FormFieldInfo(name: 'cognome', kind: FormFieldKind.text, value: '', page: 0, rect: null),
      FormFieldInfo(name: 'codice_fiscale', kind: FormFieldKind.text, value: '', page: 0, rect: null),
      FormFieldInfo(name: 'citta', kind: FormFieldKind.text, value: 'Milano', page: 0, rect: null),
      FormFieldInfo(name: 'campo7', kind: FormFieldKind.text, value: '', page: 0, rect: null),
      FormFieldInfo(name: 'email', kind: FormFieldKind.text, value: '', page: 0, rect: null, readOnly: true),
    ];
    final v = acroFormValuesFromProfile(fields, {'citta': 'Milano'}, _profile, today: '');
    expect(v, {'cognome': 'Rossi', 'codice_fiscale': 'RSSMRA80B01F839X'});
  });

  test('flusso completo: riconosce i campi, inserisce i valori, esporta e rilegge', () async {
    final pdf = buildUnmarkedFormPdf();
    final info = const PdfService().inspect(pdf);
    final found = await const LocalTextFieldDetector().detect(DetectionInput(pdf: pdf, pages: info.pages));
    final props = buildProposals(found, _profile, today: '07/11/2026');
    final ctrl = EditorController(fileName: 'm.pdf', bytes: pdf, info: info)
      ..addAll(proposalsToElements(props, pages: info.pages, color: 0xFF1D3FBF));
    final out = await const PdfService().export(pdf, elements: ctrl.elements);
    final doc = PdfDocument(inputBytes: out);
    final lines = PdfTextExtractor(doc).extractTextLines(startPageIndex: 0, endPageIndex: 0);
    final all = lines.map((l) => l.text).join('\n');
    for (final v in ['Mario Rossi', 'Napoli', '01/02/1980', 'RSSMRA80B01F839X', 'Roma, 07/11/2026', 'mario@example.com', '00100']) {
      expect(all, contains(v));
    }
    // Il nome sta sulla riga del "sottoscritto" (y ≈ 90–106).
    final nameLine = lines.firstWhere((l) => l.text.contains('Mario Rossi'));
    expect(nameLine.bounds.center.dy, inInclusiveRange(84, 110));
    doc.dispose();
  });
}
