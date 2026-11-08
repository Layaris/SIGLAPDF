import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/core/utils/pdf_coords.dart';
import 'package:sigla/features/documents/editor/editor_controller.dart';
import 'package:sigla/features/documents/editor/element_factory.dart';
import 'package:sigla/features/documents/models/placed_element.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';

EditorController _ctrl({bool form = false}) {
  final bytes = form ? buildFormPdf() : buildPlainPdf(pages: 3);
  return EditorController(fileName: 'prova.pdf', bytes: bytes, info: const PdfService().inspect(bytes));
}

void main() {
  test('aggiunge, seleziona, annulla e ripete', () {
    final c = _ctrl();
    expect(c.isDirty, isFalse);
    final e = c.add(type: ElementType.date, page: 1, rect: const NormRect(0.1, 0.1, 0.2, 0.03), text: '01/01/2026');
    expect(c.selectedId, e.id);
    expect(c.elementsOn(1), hasLength(1));
    expect(c.isDirty, isTrue);
    c.undo();
    expect(c.elements, isEmpty);
    expect(c.selectedId, isNull);
    c.redo();
    expect(c.elements.single.text, '01/01/2026');
  });

  test('un trascinamento crea un solo passo di cronologia', () {
    final c = _ctrl();
    final e = c.add(type: ElementType.check, page: 0, rect: const NormRect(0.1, 0.1, 0.05, 0.05));
    c.beginChange();
    for (var i = 1; i <= 10; i++) {
      c.updateElement(e.copyWith(rect: e.rect.translate(0.01 * i, 0)));
    }
    c.endChange();
    expect(c.elements.single.rect.x, closeTo(0.2, 1e-9));
    c.undo();
    expect(c.elements.single.rect.x, closeTo(0.1, 1e-9), reason: 'torna alla posizione prima del gesto');
    c.undo();
    expect(c.elements, isEmpty);
  });

  test('un gesto senza spostamenti non sporca la cronologia', () {
    final c = _ctrl();
    c.add(type: ElementType.check, page: 0, rect: const NormRect(0.1, 0.1, 0.05, 0.05));
    c.beginChange();
    c.endChange();
    c.undo();
    expect(c.elements, isEmpty);
  });

  test('gli elementi restano dentro la pagina', () {
    final c = _ctrl();
    final e = c.add(type: ElementType.cross, page: 0, rect: const NormRect(0.98, 0.98, 0.1, 0.1));
    expect(c.elements.single.rect.right, lessThanOrEqualTo(1.0));
    c.updateElement(e.copyWith(rect: const NormRect(-1, -1, 0.1, 0.1)));
    expect(c.elements.single.rect.x, 0);
  });

  test('replica su tutte le pagine senza duplicati, in un passo', () {
    final c = _ctrl();
    final e = c.add(type: ElementType.initials, page: 0, rect: const NormRect(0.8, 0.9, 0.1, 0.04));
    expect(c.replicateOnAllPages(e), 2);
    expect(c.elements, hasLength(3));
    expect(c.elements.map((x) => x.page).toSet(), {0, 1, 2});
    expect(c.replicateOnAllPages(e), 0, reason: 'già presenti');
    c.undo();
    expect(c.elements, hasLength(1));
  });

  test('elimina e valori dei campi con cronologia', () {
    final c = _ctrl(form: true);
    expect(c.formValues['citta'], 'Milano');
    c.setFormValue('nome', 'Anna');
    c.setFormValues({'citta': 'Roma', 'privacy': 'true', 'sconosciuto': 'x'});
    expect(c.changedFormValues, {'nome': 'Anna', 'citta': 'Roma', 'privacy': 'true'});
    c.undo();
    expect(c.formValues['citta'], 'Milano');
    expect(c.formValues['nome'], 'Anna');
    final e = c.add(type: ElementType.text, page: 0, rect: const NormRect(0, 0, 0.1, 0.1), text: 'x');
    c.remove(e.id);
    expect(c.elements, isEmpty);
    c.undo();
    expect(c.elements, hasLength(1));
  });

  group('ElementFactory', () {
    const f = ElementFactory(Size(595, 842));

    test('immagine con proporzioni rispettate in punti', () {
      final r = f.imageRect(4, widthPts: 160);
      final pts = r.toRect(const Size(595, 842));
      expect(pts.width, closeTo(160, 0.01));
      expect(pts.width / pts.height, closeTo(4, 0.01));
      expect(r.x + r.w / 2, closeTo(0.5, 1e-9));
    });

    test('testo: altezza dal corpo, larghezza dalla lunghezza', () {
      final r = f.textRect('Mario Rossi', fontPts: 12);
      expect(r.h * 842, closeTo(12 / textBoxFontRatio, 0.01));
      expect(f.textRect('Mario Rossi Bianchi Verdi').w, greaterThan(r.w));
    });

    test('quadrato in punti e sigla in basso a destra', () {
      final s = f.squareRect(sidePts: 16).toRect(const Size(595, 842));
      expect(s.width, closeTo(s.height, 0.01));
      final i = f.initialsCornerRect(2);
      expect(i.right, closeTo(0.92, 1e-9));
      expect(i.bottom, closeTo(0.95, 1e-9));
    });

    test('data odierna in formato italiano', () => expect(todayText(DateTime(2026, 3, 5)), '05/03/2026'));
  });

  test('dopo l\'esportazione non chiede più conferma, finché non cambi qualcosa', () {
    final c = _ctrl();
    c.add(type: ElementType.check, page: 0, rect: const NormRect(0.1, 0.1, 0.05, 0.05));
    expect(c.isDirty, isTrue);
    c.markExported();
    expect(c.isDirty, isFalse);
    c.add(type: ElementType.cross, page: 0, rect: const NormRect(0.2, 0.1, 0.05, 0.05));
    expect(c.isDirty, isTrue);
  });
}
