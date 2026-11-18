import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/features/documents/autofill/autofill.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/field_detection/label_dictionary.dart';
import 'package:sigla/services/field_detection/local_text_detector.dart';
import 'package:sigla/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF A4 con una riga di testo.
Uint8List _pdf(String line) {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = const Size(595, 842);
  doc.pages.add().graphics.drawString(line, PdfStandardFont(PdfFontFamily.helvetica, 11), bounds: const Rect.fromLTWH(40, 60, 520, 16));
  final b = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return b;
}

const _profile = Profile(
  values: {
    ProfileField.firstName: 'Giulia', ProfileField.lastName: 'Ferraresi', ProfileField.birthDate: '12/05/1988',
    ProfileField.birthPlace: 'Modena', ProfileField.birthProvince: 'MO', ProfileField.taxCode: 'FRRGLI88E52F257K',
    ProfileField.address: 'Via delle Rose 8', ProfileField.zip: '40121', ProfileField.city: 'Bologna', ProfileField.province: 'BO',
    ProfileField.phone: '3331234567', ProfileField.email: 'giulia@esempio.it', ProfileField.gender: 'F',
  },
  custom: [CustomField('Cittadinanza', 'italiana'), CustomField('N. patente', 'AB1234567')],
);

Future<List<FillProposal>> _proposals(String line) async {
  final b = _pdf(line);
  final info = const PdfService().inspect(b);
  final fields = await const LocalTextFieldDetector()
      .detect(DetectionInput(pdf: b, pages: info.pages, extraLabels: [for (final c in _profile.custom) c.key]));
  return buildProposals(fields, _profile, today: '08/11/2026');
}

/// "tipo=valore" delle proposte incluse.
Future<List<String>> _included(String line) async =>
    [for (final p in await _proposals(line)) if (p.include) '${p.field.kind.name}=${p.value}'];

void main() {
  test('nomi di altre persone e date diverse non ricevono i dati di chi compila', () async {
    expect(await _included('Nome del padre ______________________________'), isEmpty);
    expect(await _included("Cognome e nome dell'alunno/a ____________________"), isEmpty);
    expect(await _included('Data di scadenza ____________________________'), isEmpty);
    expect(await _included('Al Comune di ______________________'), isEmpty);
    expect(await _included('Luogo di lavoro _________________________'), isEmpty);
    // "del dichiarante" invece è chi compila.
    expect(await _included('Cognome e nome del dichiarante ____________________'), ['lastFirstName=Ferraresi Giulia']);
  });

  test('ordine "Cognome e nome", luogo e provincia di nascita', () async {
    expect(await _included('Cognome e nome ______________________________'), ['lastFirstName=Ferraresi Giulia']);
    expect(await _included('Nome e cognome ______________________________'), ['fullName=Giulia Ferraresi']);
    expect(await _included('Comune di nascita ____________________________'), ['birthPlace=Modena']);
    expect(await _included('Luogo e data di nascita: ______________________'), ['birthPlaceAndDate=Modena, 12/05/1988']);
    expect(
      await _included('nato/a a ____________ (prov. ___) il __________ residente a ____________ (prov. ___)'),
      ['birthPlace=Modena', 'birthProvince=MO', 'birthDate=12/05/1988', 'city=Bologna', 'province=BO'],
    );
    expect(await _included('nata il ______________________'), ['birthDate=12/05/1988']);
  });

  test('indirizzo, via senza ripetizioni, domicilio, abbreviazioni', () async {
    expect(await _included('Indirizzo di residenza: _______________________'), ['address=Via delle Rose 8']);
    expect(await _included('Via ____________________________ n. _____'), ['address=delle Rose 8']);
    expect(await _included('Viale ___________________________'), ['address=Via delle Rose 8'], reason: 'tipo diverso: valore intero');
    expect(await _included('Domiciliato/a in ______________________________'), ['city=Bologna']);
    expect(await _included('Cod. Fisc. ___________________________________'), ['taxCode=FRRGLI88E52F257K']);
    expect(await _included('Recapito telefonico ___________________________'), ['phone=3331234567']);
  });

  test('"Luogo, data" con città e data; data a gruppi in un solo riquadro largo', () async {
    expect(await _included('Luogo, data ___________________________'), ['placeAndDate=Bologna, 08/11/2026']);
    final p = await _proposals('Data ___/___/_____');
    expect(p.single.field.kind, FieldKind.date);
    expect(p.single.field.rect.w * 595, greaterThan(40), reason: 'prima il riquadro copriva solo i primi "___" (18 pt)');
  });

  test('consensi privacy e dati personalizzati del profilo', () async {
    final c = await _proposals('[ ] Acconsento     [ ] Non acconsento');
    expect(c.single.field.kind, FieldKind.yesNo);
    expect(c.single.field.options.map((o) => o.label), ['Sì', 'No']);
    expect((await _proposals('Acconsento [ ]     Non acconsento [ ]')).single.field.options.map((o) => o.label), ['Sì', 'No']);
    expect(await _included('Cittadinanza ______________________'), ['custom=italiana']);
    expect(await _included('N. patente ________________________'), ['custom=AB1234567']);
  });

  test('una frase che finisce con una parola chiave non è un campo', () async {
    expect(await _proposals("Per esercitare i diritti previsti scrivere all'indirizzo"), isEmpty);
    expect(await _included('Indirizzo:'), ['address=Via delle Rose 8'], reason: 'etichetta breve con ":" resta un campo');
  });

  test('moduli compilabili: nome del campo per priorità, non per lunghezza', () {
    expect(kindForFieldName('email_address'), FieldKind.email);
    expect(kindForFieldName('indirizzoEmail'), FieldKind.email);
    expect(kindForFieldName('cognome_nome'), FieldKind.lastFirstName);
    expect(kindForFieldName('nomeCognome'), FieldKind.fullName);
    expect(kindForFieldName('nome_padre'), isNull);
    expect(kindForFieldName('data_scadenza'), isNull);
    expect(kindForFieldName('codfisc'), FieldKind.taxCode);
    expect(kindForFieldName('codiceFiscale'), FieldKind.taxCode);
    expect(kindForFieldName('data_nascita'), FieldKind.birthDate);
    expect(kindForFieldName('indirizzo'), FieldKind.address);
    expect(kindForFieldName('CAP'), FieldKind.zip);
  });

  test('moduli compilabili: liste e pulsanti di scelta dal profilo, caselle mai spuntate da sole', () {
    FormFieldInfo f(String name, FormFieldKind kind, [List<String> options = const [], bool multiline = false]) =>
        FormFieldInfo(name: name, kind: kind, value: '', page: 0, rect: null, options: options, multiline: multiline);
    final v = acroFormValuesFromProfile([
      f('provincia', FormFieldKind.combo, ['Bologna (BO)', 'Modena (MO)']),
      f('sesso', FormFieldKind.radio, ['Maschio', 'Femmina']),
      f('privacy', FormFieldKind.checkbox),
      f('indirizzo', FormFieldKind.text, const [], true),
      f('provincia_nascita', FormFieldKind.combo, ['BO', 'MO']),
    ], const {}, _profile, today: '08/11/2026');
    expect(v['provincia'], 'Bologna (BO)');
    expect(v['sesso'], 'Femmina');
    expect(v.containsKey('privacy'), isFalse);
    expect(v['indirizzo'], 'Via delle Rose 8 40121 Bologna (BO)');
    expect(v['provincia_nascita'], 'MO');
  });
}
