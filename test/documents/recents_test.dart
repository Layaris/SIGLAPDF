import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/storage/key_value_store.dart';
import 'package:sigla/features/documents/documents_page.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/editor_page.dart';
import 'package:sigla/features/documents/recents/recents_repository.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';
import '../widgets/editor_page_test.dart' show fakeRaster;

void main() {
  test('recenti: ordine, limite, stesso nome sostituito, file troppo grandi esclusi', () async {
    final store = MemoryKeyValueStore();
    final r = RecentsRepository(store, maxItems: 3, maxBytes: 100);
    final t0 = DateTime(2026, 1, 1);
    for (var i = 0; i < 4; i++) {
      await r.add(name: 'doc$i.pdf', pdf: Uint8List(10), pageCount: 1, now: t0.add(Duration(minutes: i)));
    }
    expect(r.all.map((d) => d.name), ['doc3.pdf', 'doc2.pdf', 'doc1.pdf']);
    await r.add(name: 'doc2.pdf', pdf: Uint8List(20), pageCount: 2, now: t0.add(const Duration(hours: 1)));
    expect(r.all.first.name, 'doc2.pdf');
    expect(r.all.where((d) => d.name == 'doc2.pdf'), hasLength(1));
    expect(await r.add(name: 'grande.pdf', pdf: Uint8List(101), pageCount: 1), isNull);
    // Persistenza.
    expect(RecentsRepository(store, maxItems: 3).all.first.pdf.length, 20);
    await r.clear();
    expect(r.isEmpty, isTrue);
  });

  testWidgets('documenti: i recenti compaiono e si riaprono', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    final s = AppServices.inMemory();
    await s.recents.add(name: 'contratto_firmato.pdf', pdf: buildPlainPdf(pages: 2), pageCount: 2);
    await tester.pumpWidget(wrapWithServices(s, const DocumentsPage()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Recenti'), findsOneWidget);
    expect(find.text('contratto_firmato.pdf'), findsOneWidget);
    expect(find.textContaining('2 pagine'), findsOneWidget);
    await tester.tap(find.text('contratto_firmato.pdf'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EditorPage), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('recenti disattivati: elenco nascosto', (tester) async {
    final s = AppServices.inMemory();
    await s.recents.add(name: 'x.pdf', pdf: buildPlainPdf(pages: 1), pageCount: 1);
    await s.settings.update((x) => x.copyWith(keepRecents: false));
    await tester.pumpWidget(wrapWithServices(s, const DocumentsPage()));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Recenti'), findsNothing);
  });

  testWidgets('esportare salva il PDF tra i recenti', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    final s = AppServices.inMemory();
    final bytes = buildPlainPdf(pages: 1);
    await tester.pumpWidget(wrapWithServices(
      s,
      EditorPage(
        controller: EditorController(fileName: 'modulo_firmato.pdf', bytes: bytes, info: const PdfService().inspect(bytes)),
        rasterizer: fakeRaster,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Esporta PDF'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('PDF pronto'), findsOneWidget);
    expect(s.recents.all.single.name, 'modulo_firmato.pdf', reason: 'niente _firmato_firmato');
    await tester.binding.setSurfaceSize(null);
  });
}
