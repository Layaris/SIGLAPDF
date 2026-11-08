import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/utils/pdf_coords.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';

void main() {
  const service = PdfService();

  test('inspect legge pagine, rotazione e campi AcroForm', () {
    final info = service.inspect(buildFormPdf());
    expect(info.pages, hasLength(2));
    expect(info.pages[0].unrotated.width, closeTo(595, 0.5));
    expect(info.pages[1].rotation, 90);
    expect(info.pages[1].visual.width, closeTo(842, 0.5));
    final names = info.fields.map((f) => f.name).toList();
    expect(names, containsAll(['nome', 'citta', 'privacy', 'provincia']));
    final citta = info.fields.firstWhere((f) => f.name == 'citta');
    expect(citta.kind, FormFieldKind.text);
    expect(citta.value, 'Milano');
    expect(citta.page, 0);
    expect(citta.rect!.x, closeTo(50 / 595, 0.01));
    expect(info.fields.firstWhere((f) => f.name == 'privacy').kind, FormFieldKind.checkbox);
    final prov = info.fields.firstWhere((f) => f.name == 'provincia');
    expect(prov.options, ['MI', 'RM']);
  });

  test('file non PDF o danneggiato → messaggio chiaro', () {
    expect(() => service.inspect(utf8.encode('ciao')), throwsA(isA<PdfOpenException>()));
    expect(
      () => service.inspect(utf8.encode('%PDF-1.4 rotto')),
      throwsA(isA<PdfOpenException>()),
    );
  });

  test('esporta con firma, testo, data e segni; il risultato si rilegge', () async {
    final src = buildPlainPdf(pages: 2);
    final out = await service.export(src, elements: [
      PlacedElement(id: 'a', type: ElementType.signature, page: 0, rect: const NormRect(0.5, 0.8, 0.3, 0.08), image: tinyPng()),
      const PlacedElement(id: 'b', type: ElementType.text, page: 0, rect: NormRect(0.1, 0.3, 0.5, 0.03), text: 'Mario Rossi è qui'),
      const PlacedElement(id: 'c', type: ElementType.date, page: 1, rect: NormRect(0.1, 0.5, 0.3, 0.03), text: '07/11/2026'),
      const PlacedElement(id: 'd', type: ElementType.check, page: 1, rect: NormRect(0.1, 0.6, 0.03, 0.03)),
      const PlacedElement(id: 'e', type: ElementType.cross, page: 1, rect: NormRect(0.2, 0.6, 0.03, 0.03)),
      const PlacedElement(id: 'z', type: ElementType.text, page: 9, rect: NormRect(0, 0, 0.1, 0.1), text: 'fuori'),
    ]);
    final doc = PdfDocument(inputBytes: out);
    expect(doc.pages.count, 2);
    final p1 = PdfTextExtractor(doc).extractText(startPageIndex: 0, endPageIndex: 0);
    final p2 = PdfTextExtractor(doc).extractText(startPageIndex: 1, endPageIndex: 1);
    expect(p1, contains('Mario Rossi è qui'));
    expect(p2, contains('07/11/2026'));
    expect(p1 + p2, isNot(contains('fuori')));
    // Il testo sta dove è stato posizionato (y ≈ 0.3 × 842 ≈ 253).
    final line = PdfTextExtractor(doc)
        .extractTextLines(startPageIndex: 0, endPageIndex: 0)
        .firstWhere((l) => l.text.contains('Mario'));
    expect(line.bounds.left, closeTo(59.5, 3));
    expect(line.bounds.center.dy, closeTo(0.315 * 842, 6));
    doc.dispose();
    // L'immagine della firma è nel file.
    expect(latin1.decode(out, allowInvalid: true), contains('/Image'));
  });

  test('pagina ruotata: il testo finisce nella posizione visiva giusta', () async {
    final src = buildFormPdf();
    final out = await service.export(src, elements: [
      // In alto a sinistra della pagina come la vede l'utente (orizzontale).
      const PlacedElement(id: 't', type: ElementType.text, page: 1, rect: NormRect(0.05, 0.05, 0.3, 0.04), text: 'RUOTATO'),
    ]);
    final doc = PdfDocument(inputBytes: out);
    final lines = PdfTextExtractor(doc).extractTextLines(startPageIndex: 1, endPageIndex: 1);
    final line = lines.firstWhere((l) => l.text.contains('RUOTATO'));
    // Visivo: x 42…295, y 30…54 (pagina orizzontale 842×595).
    // Non ruotato (x = vy, y = H − vx): x 30…54, y 547…800. Senza la trasformazione
    // il testo finirebbe invece in alto (y ≈ 30).
    final expected = PdfCoords(doc.pages[1].size, 90).visualToUnrotated(const Offset(42.1, 29.75));
    expect(expected.dx, closeTo(29.75, 0.1));
    expect(expected.dy, closeTo(799.9, 0.1));
    final b = line.bounds;
    expect(b.left, inInclusiveRange(25, 70), reason: 'bounds $b');
    expect(b.top, inInclusiveRange(540, 810), reason: 'bounds $b');
    doc.dispose();
  });

  test('compila AcroForm e appiattisce: campi spariti, valori nel contenuto', () async {
    final out = await service.export(buildFormPdf(), formValues: {
      'nome': 'Giulia Bianchi',
      'privacy': 'true',
      'provincia': 'RM',
      'inesistente': 'x',
    });
    final doc = PdfDocument(inputBytes: out);
    expect(doc.form.fields.count, 0, reason: 'flatten rimuove i campi');
    final text = PdfTextExtractor(doc).extractText();
    expect(text, contains('Giulia Bianchi'));
    expect(text, contains('Milano'), reason: 'il valore già presente resta');
    expect(text, contains('RM'));
    doc.dispose();
  });

  test('senza flatten i campi restano compilati e modificabili', () async {
    final out = await service.export(buildFormPdf(), formValues: {'nome': 'Anna'}, flatten: false);
    final info = service.inspect(out);
    expect(info.fields.firstWhere((f) => f.name == 'nome').value, 'Anna');
  });

  test('la stessa immagine su molte pagine viene incorporata una volta sola', () async {
    final png = tinyPng();
    final src = buildPlainPdf(pages: 30);
    PlacedElement on(int page, List<int> bytes) => PlacedElement(
        id: 'p$page', type: ElementType.initials, page: page, rect: const NormRect(0.8, 0.9, 0.1, 0.05), image: Uint8List.fromList(bytes));
    final shared = await const PdfService().export(src, elements: [for (var i = 0; i < 30; i++) PlacedElement(
        id: 's$i', type: ElementType.initials, page: i, rect: const NormRect(0.8, 0.9, 0.1, 0.05), image: png)]);
    final copies = await const PdfService().export(src, elements: [for (var i = 0; i < 30; i++) on(i, png)]);
    expect(shared.length, lessThan(copies.length), reason: 'una sola immagine invece di 30');
  });

  test('firma sopra un campo AcroForm appiattito: il modulo si esporta senza campi', () async {
    // L'ordine (prima il flatten, poi le firme) è verificato a mano con pdftoppm: un campo con sfondo
    // grigio copriva la firma. Qui si controlla che il doppio passaggio non perda niente.
    final out = await const PdfService().export(buildFormPdf(), formValues: const {'nome': 'Mario'}, elements: [
      PlacedElement(id: 'f', type: ElementType.signature, page: 0, rect: const NormRect(0.1, 0.12, 0.3, 0.05), image: tinyPng()),
    ]);
    final doc = PdfDocument(inputBytes: out);
    expect(doc.form.fields.count, 0);
    expect(doc.pages.count, 2);
    expect(PdfTextExtractor(doc).extractText(startPageIndex: 0, endPageIndex: 0), contains('Mario'));
    doc.dispose();
  });

  test('sanitizeForStandardFont', () {
    expect(sanitizeForStandardFont('Città € “ok” ✓ 你'), 'Città € "ok" v ?');
  });
}
