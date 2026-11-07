import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/features/profile/profile_model.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/field_detection/label_dictionary.dart';
import 'package:sigla/services/field_detection/local_text_detector.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';

List<FieldKind> _kinds(String s) => findLabels(normalizeForMatching(s)).map((m) => m.kind).toList();

void main() {
  group('dizionario etichette', () {
    test('italiano', () {
      expect(_kinds('Nome e cognome:'), [FieldKind.fullName]);
      expect(_kinds('Cognome ____ Nome ____'), [FieldKind.lastName, FieldKind.firstName]);
      expect(_kinds('nato/a a ______ il ______'), [FieldKind.birthPlace, FieldKind.birthDate]);
      expect(_kinds('Data di nascita'), [FieldKind.birthDate]);
      expect(_kinds('C.F.'), [FieldKind.taxCode]);
      expect(_kinds('Codice Fiscale'), [FieldKind.taxCode]);
      expect(_kinds('residente in ____ via ____ CAP ____ Prov. ___'),
          [FieldKind.city, FieldKind.address, FieldKind.zip, FieldKind.province]);
      expect(_kinds('Città'), [FieldKind.city]);
      expect(_kinds('Tel.'), [FieldKind.phone]);
      expect(_kinds('E-mail'), [FieldKind.email]);
      expect(_kinds('Luogo e data'), [FieldKind.placeAndDate]);
      expect(_kinds('Data ____ Firma ____'), [FieldKind.date, FieldKind.signature]);
    });

    test('inglese', () {
      expect(_kinds('First name'), [FieldKind.firstName]);
      expect(_kinds('Last name'), [FieldKind.lastName]);
      expect(_kinds('Date of birth'), [FieldKind.birthDate]);
      expect(_kinds('Signature'), [FieldKind.signature]);
      expect(_kinds('Zip code'), [FieldKind.zip]);
    });

    test('"il" vale come data di nascita solo dopo "nato a"', () {
      expect(_kinds('il presente modulo'), isEmpty);
      expect(_kinds('nata a Roma il'), [FieldKind.birthPlace, FieldKind.birthDate]);
    });

    test('nessun falso positivo dentro altre parole', () {
      expect(_kinds('cognome'), [FieldKind.lastName]);
      expect(_kinds('vialetto'), isEmpty);
      expect(_kinds('telefonata'), isEmpty);
      expect(_kinds('Dichiara di aver letto'), isEmpty);
    });

    test('normalizzazione: stessa lunghezza, minuscole, senza accenti', () {
      const s = 'CITTÀ È';
      expect(normalizeForMatching(s), 'citta e');
      expect(normalizeForMatching(s).length, s.length);
    });

    test('nomi dei campi AcroForm', () {
      expect(kindForFieldName('codiceFiscale'), FieldKind.taxCode);
      expect(kindForFieldName('CF'), FieldKind.taxCode);
      expect(kindForFieldName('data_nascita'), FieldKind.birthDate);
      expect(kindForFieldName('luogoNascita'), FieldKind.birthPlace);
      expect(kindForFieldName('Cognome'), FieldKind.lastName);
      expect(kindForFieldName('txtEmail1'), FieldKind.email);
      expect(kindForFieldName('campo42'), isNull);
    });
  });

  test('valori proposti dal profilo', () {
    const p = Profile(values: {
      ProfileField.firstName: 'Mario',
      ProfileField.lastName: 'Rossi',
      ProfileField.city: 'Roma',
      ProfileField.taxCode: 'rssmra80a01h501u',
    });
    expect(FieldKind.fullName.proposedValue(p, today: '01/01/2026'), 'Mario Rossi');
    expect(FieldKind.taxCode.proposedValue(p, today: ''), 'RSSMRA80A01H501U');
    expect(FieldKind.placeAndDate.proposedValue(p, today: '01/01/2026'), 'Roma, 01/01/2026');
    expect(FieldKind.date.proposedValue(p, today: '01/01/2026'), '01/01/2026');
    expect(FieldKind.parse('taxCode'), FieldKind.taxCode);
    expect(FieldKind.parse('tax_code'), FieldKind.taxCode);
    expect(FieldKind.parse('boh'), isNull);
  });

  group('LocalTextFieldDetector su un modulo generato', () {
    late List<DetectedField> fields;
    late PdfDocumentInfo info;

    setUpAll(() async {
      final pdf = buildUnmarkedFormPdf();
      info = const PdfService().inspect(pdf);
      fields = await const LocalTextFieldDetector().detect(DetectionInput(pdf: pdf, pages: info.pages));
    });

    DetectedField one(FieldKind k) => fields.firstWhere((f) => f.kind == k, orElse: () => throw TestFailure('manca $k in ${fields.map((f) => '${f.kind}:${f.label}').toList()}'));

    test('trova tutti i campi attesi', () {
      final kinds = fields.map((f) => f.kind).toSet();
      expect(
        kinds,
        containsAll([
          FieldKind.fullName,
          FieldKind.birthPlace,
          FieldKind.birthDate,
          FieldKind.taxCode,
          FieldKind.city,
          FieldKind.address,
          FieldKind.zip,
          FieldKind.phone,
          FieldKind.email,
          FieldKind.placeAndDate,
          FieldKind.signature,
        ]),
      );
      expect(fields.every((f) => f.source == 'locale' && f.page == 0), isTrue);
    });

    test('la riga senza etichette non produce campi', () {
      // "Dichiara di aver letto…" è a y=250 (≈ 0.297 della pagina).
      expect(fields.where((f) => (f.rect.y - 250 / 842).abs() < 0.01), isEmpty);
    });

    test('le linee "____" danno lo spazio giusto', () {
      final place = one(FieldKind.birthPlace);
      final date = one(FieldKind.birthDate);
      expect(place.rect.y, closeTo(120 / 842, 0.02));
      expect(date.rect.x, greaterThan(place.rect.right), reason: '"il" viene dopo il luogo');
      final name = one(FieldKind.fullName);
      expect(name.rect.w, greaterThan(0.3));
    });

    test('dopo i due punti: spazio fino a fine riga o alla prossima etichetta', () {
      final cf = one(FieldKind.taxCode);
      expect(cf.rect.x, greaterThan(50 / 595));
      expect(cf.rect.right, greaterThan(0.8), reason: 'fino al margine destro');
      final tel = one(FieldKind.phone);
      final email = one(FieldKind.email);
      expect(tel.rect.right, lessThanOrEqualTo(300 / 595), reason: 'si ferma prima di "Email"');
      expect(email.rect.x, greaterThan(300 / 595));
    });

    test('puntini e firma', () {
      final pd = one(FieldKind.placeAndDate);
      // 34 puntini in Helvetica 11 ≈ 104 pt ≈ 0,175 della larghezza: il campo copre i puntini.
      expect(pd.rect.w, closeTo(104 / 595, 0.03));
      expect(pd.rect.x, greaterThan(100 / 595), reason: 'dopo "Luogo e data"');
      final sign = one(FieldKind.signature);
      // Spazio libero a destra di "Firma" sulla stessa riga (sotto solo se a destra non c'è posto).
      expect(sign.rect.x, greaterThan(380 / 595));
      expect(sign.rect.y, closeTo(300 / 842, 0.02));
    });

    test('evita i riquadri già occupati', () async {
      final pdf = buildUnmarkedFormPdf();
      final cf = one(FieldKind.taxCode);
      final again = await const LocalTextFieldDetector().detect(DetectionInput(pdf: pdf, pages: info.pages, avoid: [(0, cf.rect)]));
      expect(again.where((f) => f.kind == FieldKind.taxCode), isEmpty);
    });
  });
}
