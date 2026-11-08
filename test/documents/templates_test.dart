import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/storage/key_value_store.dart';
import 'package:sigla/core/utils/pdf_coords.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/editor_page.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/features/documents/templates/templates_repository.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';
import '../widgets/editor_page_test.dart' show fakeRaster;

/// Riferimento con BigInt: la versione dell'app deve dare lo stesso risultato (anche sul web).
String _reference(String norm, int pages) {
  final mask = BigInt.from(0xffffffff), prime = BigInt.from(0x01000193);
  var h1 = BigInt.from(0x811c9dc5), h2 = BigInt.from(0x050c5d1f);
  for (final c in norm.codeUnits) {
    h1 = ((h1 ^ BigInt.from(c)) * prime) & mask;
    h2 = ((h2 ^ BigInt.from(c + 31)) * prime) & mask;
  }
  String hex(BigInt v) => v.toRadixString(16).padLeft(8, '0');
  return 'p$pages-${hex(h1)}${hex(h2)}';
}

void main() {
  test('impronta: stabile, sensibile al testo e alle pagine, null senza testo', () {
    const text = 'Dichiarazione sostitutiva di certificazione. Il sottoscritto nato a il codice fiscale';
    final a = documentFingerprint(text, 2);
    expect(a, documentFingerprint('  ${text.toUpperCase()}  ', 2), reason: 'spazi e maiuscole non contano');
    expect(a, isNot(documentFingerprint('$text residente', 2)));
    expect(a, isNot(documentFingerprint(text, 3)));
    expect(documentFingerprint('poco', 1), isNull);
    final norm = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    expect(a, _reference(norm, 2), reason: 'stesso valore del calcolo esatto con BigInt');
  });

  test('inspect calcola l\'impronta dei moduli con testo', () {
    final info = const PdfService().inspect(buildUnmarkedFormPdf());
    expect(info.fingerprint, startsWith('p1-'));
    expect(const PdfService().inspect(buildUnmarkedFormPdf()).fingerprint, info.fingerprint);
  });

  test('repository: salva, riconosce, sostituisce lo stesso modulo, importa', () async {
    final store = MemoryKeyValueStore();
    final r = TemplatesRepository(store);
    const e = PlacedElement(id: 'x', type: ElementType.date, page: 0, rect: NormRect(0.1, 0.1, 0.2, 0.03), text: '01/01/2020');
    final t1 = await r.save(name: 'Modulo A', elements: const [e], pageCount: 1, fingerprint: 'fp1');
    expect(r.matching('fp1')!.id, t1.id);
    expect(r.matching('altro'), isNull);
    await r.save(name: 'Modulo A v2', elements: const [e, e], pageCount: 1, fingerprint: 'fp1');
    expect(r.all, hasLength(1));
    expect(r.all.single.elements, hasLength(2));
    expect(TemplatesRepository(store).all.single.name, 'Modulo A v2');
    final other = TemplatesRepository(MemoryKeyValueStore());
    expect(await other.importAll(r.all, replace: false), 1);
  });

  test('applicare: date di oggi, firma attuale, pagine mancanti saltate', () {
    final t = FormTemplate(
      id: 't',
      name: 'M',
      pageCount: 3,
      createdAt: DateTime(2026),
      elements: const [
        PlacedElement(id: '', type: ElementType.date, page: 0, rect: NormRect(0, 0, 0.1, 0.1), text: '01/01/2020'),
        PlacedElement(id: '', type: ElementType.signature, page: 0, rect: NormRect(0, 0.5, 0.2, 0.1)),
        PlacedElement(id: '', type: ElementType.text, page: 2, rect: NormRect(0, 0, 0.1, 0.1), text: 'pag 3'),
      ],
    );
    final noSig = elementsFromTemplate(t, pageCount: 2, today: '08/11/2026');
    expect(noSig.map((e) => e.type), [ElementType.date], reason: 'niente firma salvata e pagina 3 assente');
    expect(noSig.single.text, '08/11/2026');
    final withSig = elementsFromTemplate(t, pageCount: 3, today: '08/11/2026', signaturePng: tinyPng());
    expect(withSig, hasLength(3));
    expect(withSig[1].image, isNotNull);
    // Firma attuale con proporzioni diverse: stessa larghezza e stesso fondo, altezza ricalcolata.
    final fitted = elementsFromTemplate(t, pageCount: 3, today: '', signaturePng: tinyPng(), signatureAspect: 4, pageAspects: const [0.5, 0.5, 0.5]);
    final r = fitted[1].rect;
    expect(r.w, closeTo(0.2, 1e-9));
    expect(r.h, closeTo(0.2 * 0.5 / 4, 1e-9), reason: 'larghezza in pixel / altezza in pixel = 4');
    expect(r.y + r.h, closeTo(0.6, 1e-9), reason: 'resta sulla stessa riga');
  });

  testWidgets('editor: salva il modello e lo propone riaprendo lo stesso modulo', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    final s = AppServices.inMemory();
    await s.signatures.add(name: 'F', kind: SignatureKind.signature, source: SignatureSource.drawn, png: tinyPng(), width: 4, height: 2);
    final bytes = buildUnmarkedFormPdf();
    EditorPage editor() => EditorPage(
          controller: EditorController(fileName: 'dichiarazione.pdf', bytes: bytes, info: const PdfService().inspect(bytes)),
          rasterizer: fakeRaster,
        );
    await tester.pumpWidget(wrapWithServices(s, editor()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Firma'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Altro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salva come modello'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'dichiarazione'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Salva'));
    await tester.pumpAndSettle();
    expect(s.templates.all.single.name, 'dichiarazione');

    // Riapertura: proposta in alto.
    await tester.pumpWidget(const SizedBox());
    final second = editor();
    await tester.pumpWidget(wrapWithServices(s, second));
    await tester.pumpAndSettle();
    expect(find.textContaining('Modulo già compilato'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Applica'));
    await tester.pumpAndSettle();
    expect(second.controller.elements.single.type, ElementType.signature);
    expect(find.textContaining('Modulo già compilato'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
}
