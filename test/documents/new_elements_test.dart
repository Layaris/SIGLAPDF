import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/utils/pdf_coords.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/editor_page.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/services/pdf_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';
import '../widgets/editor_page_test.dart' show fakeRaster;

void main() {
  test('tratto a mano: riquadro attorno ai punti e punti relativi al riquadro', () {
    final e = inkElementFromStroke(
      const [Offset(0.2, 0.3), Offset(0.4, 0.35), Offset(0.6, 0.3)],
      page: 1,
      color: 0xFF111111,
      inkWidth: 0.004,
      pageAspect: 0.707,
    )!;
    expect(e.type, ElementType.ink);
    expect(e.rect.x, lessThan(0.2));
    expect(e.rect.right, greaterThan(0.6));
    final pts = e.strokes.single;
    expect(pts.first.dx, greaterThan(0));
    expect(pts.last.dx, lessThan(1));
    // Ricostruzione: riquadro + punto relativo = punto originale.
    final back = Offset(e.rect.x + pts[1].dx * e.rect.w, e.rect.y + pts[1].dy * e.rect.h);
    expect((back - const Offset(0.4, 0.35)).distance, lessThan(1e-9));
    expect(inkElementFromStroke(const [Offset(0.1, 0.1)], page: 0, color: 0, inkWidth: 0.004, pageAspect: 1), isNull);
  });

  test('serializzazione per i modelli (senza immagine)', () {
    final e = PlacedElement(
      id: 'x',
      type: ElementType.ink,
      page: 2,
      rect: const NormRect(0.1, 0.2, 0.3, 0.1),
      color: 0xFF111111,
      strokes: const [
        [Offset(0, 0), Offset(1, 1)],
      ],
      image: tinyPng(),
    );
    final m = jsonDecode(jsonEncode(e.toTemplateMap())) as Map<String, dynamic>;
    expect(m.containsKey('image'), isFalse);
    final back = PlacedElement.fromTemplateMap(m)!;
    expect(back.type, ElementType.ink);
    expect(back.page, 2);
    expect(back.strokes.single.last, const Offset(1, 1));
    expect(PlacedElement.fromTemplateMap({'type': 'boh', 'rect': {}}), isNull);
  });

  test('esporta firma con data, tratto a mano ed evidenziatore', () async {
    final src = buildPlainPdf(pages: 1);
    final out = await const PdfService().export(src, elements: [
      PlacedElement(id: 'a', type: ElementType.signedDate, page: 0, rect: const NormRect(0.5, 0.7, 0.3, 0.1), image: tinyPng(), text: '08/11/2026'),
      const PlacedElement(
        id: 'b',
        type: ElementType.ink,
        page: 0,
        rect: NormRect(0.1, 0.5, 0.3, 0.05),
        strokes: [
          [Offset(0, 0.5), Offset(0.5, 0), Offset(1, 0.5)],
        ],
      ),
      const PlacedElement(id: 'c', type: ElementType.highlight, page: 0, rect: NormRect(0.05, 0.04, 0.5, 0.03), color: highlightColor),
    ]);
    final doc = PdfDocument(inputBytes: out);
    final text = PdfTextExtractor(doc).extractText();
    expect(text, contains('08/11/2026'));
    expect(text, contains('Pagina 1'), reason: 'il testo sotto l\'evidenziatore resta');
    doc.dispose();
    final raw = latin1.decode(out, allowInvalid: true);
    expect(raw, contains('/Image'));
    expect(raw, contains('/Multiply'), reason: 'evidenziatore in modalità moltiplica');
  });

  Future<EditorPage> pump(WidgetTester tester, AppServices s) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    final bytes = buildPlainPdf(pages: 3);
    final page = EditorPage(
      controller: EditorController(fileName: 'a.pdf', bytes: bytes, info: const PdfService().inspect(bytes)),
      rasterizer: fakeRaster,
    );
    await tester.pumpWidget(wrapWithServices(s, page));
    await tester.pumpAndSettle();
    return page;
  }

  Future<void> scrollToolbar(WidgetTester tester) async {
    await tester.drag(find.text('Firma'), const Offset(-600, 0));
    await tester.pumpAndSettle();
  }

  testWidgets('penna: disegna un tratto e diventa un elemento', (tester) async {
    final s = AppServices.inMemory();
    final page = await pump(tester, s);
    await scrollToolbar(tester);
    await tester.tap(find.text('Penna'));
    await tester.pumpAndSettle();
    expect(find.text('Spessa'), findsOneWidget);
    final pageRect = tester.getRect(find.bySemanticsLabel('Pagina 1 di 3'));
    final g = await tester.startGesture(pageRect.topLeft + const Offset(100, 100));
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(20, 6));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    final ink = page.controller.elements.where((e) => e.type == ElementType.ink).toList();
    expect(ink, hasLength(1));
    expect(ink.single.strokes.single.length, greaterThan(3));
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();
    expect(find.text('Spessa'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('firma e data, evidenziatore, miniature', (tester) async {
    final s = AppServices.inMemory();
    await s.signatures.add(name: 'F', kind: SignatureKind.signature, source: SignatureSource.drawn, png: tinyPng(), width: 4, height: 2);
    final page = await pump(tester, s);
    await tester.tap(find.text('Firma e data'));
    await tester.pumpAndSettle();
    final sd = page.controller.elements.single;
    expect(sd.type, ElementType.signedDate);
    expect(sd.text, matches(RegExp(r'^\d\d/\d\d/\d{4}$')));
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();
    await scrollToolbar(tester);
    await tester.tap(find.text('Evidenzia'));
    await tester.pumpAndSettle();
    expect(page.controller.elements.last.type, ElementType.highlight);
    // Miniature: pulsante Pagine (schermo stretto) e foglio con le pagine.
    await tester.tap(find.byTooltip('Pagine'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsWidgets);
    await tester.binding.setSurfaceSize(null);
  });
}
