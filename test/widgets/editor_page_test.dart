import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/app_services.dart';
import 'package:sigla/core/utils/file_access.dart';
import 'package:sigla/features/documents/documents_page.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/editor_page.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/features/signatures/signature_model.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';
import '../test_helpers.dart';

Future<ui.Image?> fakeRaster(Uint8List pdf, int page, double dpi) async {
  final r = ui.PictureRecorder();
  ui.Canvas(r).drawRect(const ui.Rect.fromLTWH(0, 0, 4, 6), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  return r.endRecording().toImageSync(4, 6);
}

class FakeFiles implements FileAccess {
  FakeFiles({this.pdf});
  final PickedBytes? pdf;
  Uint8List? saved;
  String? savedName;

  @override
  Future<PickedBytes?> pickPdf() async => pdf;
  @override
  Future<PickedBytes?> pickImage() async => null;
  @override
  Future<List<PickedBytes>> pickImages() async => const [];
  @override
  Future<PickedBytes?> pickAny({List<String>? extensions}) async => null;
  @override
  Future<bool> save({required String fileName, required Uint8List bytes, required String mimeType}) async {
    saved = bytes;
    savedName = fileName;
    return true;
  }
}

EditorPage _editor(Uint8List bytes) => EditorPage(
      controller: EditorController(fileName: 'contratto.pdf', bytes: bytes, info: const PdfService().inspect(bytes)),
      rasterizer: fakeRaster,
    );

void main() {
  setUp(() {});

  testWidgets('editor: mostra le pagine e aggiunge data, spunta e croce', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    final services = AppServices.inMemory();
    final page = _editor(buildPlainPdf(pages: 2));
    await tester.pumpWidget(wrapWithServices(services, page));
    await tester.pumpAndSettle();
    expect(find.text('contratto.pdf'), findsOneWidget);
    expect(find.bySemanticsLabel('Pagina 1 di 2'), findsOneWidget);

    await tester.tap(find.text('Data'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Data: \d\d/\d\d/\d{4}$')), findsOneWidget);
    // Elemento selezionato: compare la barra di selezione.
    expect(find.text('Modifica'), findsOneWidget);
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Spunta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fatto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Croce'));
    await tester.pumpAndSettle();
    expect(page.controller.elements.map((e) => e.type), [ElementType.date, ElementType.check, ElementType.cross]);
    // La croce selezionata ha la cornice con elimina e ridimensiona.
    expect(find.bySemanticsLabel('Ridimensiona'), findsOneWidget);

    await tester.tap(find.byTooltip('Annulla'));
    await tester.pumpAndSettle();
    expect(page.controller.elements.map((e) => e.type), [ElementType.date, ElementType.check]);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('editor: trascina un elemento e lo sposta', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    final services = AppServices.inMemory();
    final page = _editor(buildPlainPdf(pages: 1));
    await tester.pumpWidget(wrapWithServices(services, page));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spunta'));
    await tester.pumpAndSettle();
    final ctrl = page.controller;
    final before = ctrl.elements.single.rect;
    await tester.drag(find.bySemanticsLabel('Spunta'), const Offset(100, 50));
    await tester.pumpAndSettle();
    final after = ctrl.elements.single.rect;
    expect(after.x, greaterThan(before.x));
    expect(after.y, greaterThan(before.y));
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('editor: sigla tutte le pagine con la sigla predefinita', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    final services = AppServices.inMemory();
    await services.signatures.add(
      name: 'MR',
      kind: SignatureKind.initials,
      source: SignatureSource.drawn,
      png: tinyPng(),
      width: 4,
      height: 2,
    );
    final page = _editor(buildPlainPdf(pages: 3));
    await tester.pumpWidget(wrapWithServices(services, page));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sigla tutte'));
    await tester.pumpAndSettle();
    expect(page.controller.elements.where((e) => e.type == ElementType.initials), hasLength(3));
    expect(find.text('Sigla aggiunta su 3 pagine'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('documenti: apre un PDF scelto e mostra l\'editor', (tester) async {
    final files = FakeFiles(pdf: PickedBytes('modulo.pdf', buildPlainPdf(pages: 1)));
    final services = AppServices.inMemory(files: files);
    await tester.pumpWidget(wrapWithServices(services, const DocumentsPage()));
    expect(find.text('Firma o compila un PDF'), findsOneWidget);
    await tester.tap(find.text('Apri PDF'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EditorPage), findsOneWidget);
    expect(find.text('modulo.pdf'), findsOneWidget);
  });

  testWidgets('documenti: file non valido mostra un errore', (tester) async {
    final files = FakeFiles(pdf: PickedBytes('rotto.pdf', Uint8List.fromList([1, 2, 3, 4, 5, 6])));
    final services = AppServices.inMemory(files: files);
    await tester.pumpWidget(wrapWithServices(services, const DocumentsPage()));
    await tester.tap(find.text('Apri PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Il file non è un PDF valido.'), findsOneWidget);
  });
}
