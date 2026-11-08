import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/features/documents/editor/page_renderer.dart';

void main() {
  test('cache limitata: le pagine meno recenti vengono liberate', () async {
    var calls = 0;
    Future<ui.Image?> raster(Uint8List pdf, int page, double dpi) async {
      calls++;
      final r = ui.PictureRecorder();
      ui.Canvas(r).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
      return r.endRecording().toImageSync(2, 2);
    }

    final renderer = PageRenderer(Uint8List(0), rasterizer: raster, maxCached: 3);
    final copies = <ui.Image>[];
    for (var p = 0; p < 5; p++) {
      copies.add((await renderer.render(p, 72))!);
    }
    expect(renderer.cachedCount, 3);
    expect(renderer.cached(0), isNull, reason: 'pagina 0 liberata');
    // Le copie restano valide anche se la cache ha liberato le sue.
    expect(copies.first.width, 2);
    // Pagina in cache: nessun nuovo render.
    final again = await renderer.render(4, 72);
    expect(calls, 5);
    expect(again, isNotNull);
    // Più nitida → nuovo render.
    await renderer.render(4, 200);
    expect(calls, 6);
    for (final c in [...copies, again!]) {
      c.dispose();
    }
    renderer.dispose();
    expect(await renderer.render(1, 72), isNull, reason: 'dopo dispose niente render');
  });

  test('richieste contemporanee della stessa pagina: un solo render', () async {
    var calls = 0;
    Future<ui.Image?> raster(Uint8List pdf, int page, double dpi) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final r = ui.PictureRecorder();
      ui.Canvas(r).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
      return r.endRecording().toImageSync(2, 2);
    }

    final renderer = PageRenderer(Uint8List(0), rasterizer: raster);
    final results = await Future.wait([renderer.render(0, 72), renderer.render(0, 72)]);
    expect(calls, 1);
    expect(results.every((i) => i != null), isTrue);
    expect(identical(results[0], results[1]), isFalse, reason: 'ognuno ha la sua copia');
  });

  test('render a bassa risoluzione in corso: una richiesta più nitida non riceve la miniatura', () async {
    final dpis = <double>[];
    Future<ui.Image?> raster(Uint8List pdf, int page, double dpi) async {
      dpis.add(dpi);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final side = dpi.round();
      final r = ui.PictureRecorder();
      ui.Canvas(r).drawRect(ui.Rect.fromLTWH(0, 0, side.toDouble(), 1), ui.Paint());
      return r.endRecording().toImageSync(side, 1);
    }

    final renderer = PageRenderer(Uint8List(0), rasterizer: raster);
    final thumb = renderer.render(0, 48);
    final page = renderer.render(0, 192);
    final small = (await thumb)!, big = (await page)!;
    expect(small.width, 48);
    expect(big.width, 192, reason: 'prima riceveva l\'immagine a 48 dpi e restava sfocata');
    expect(dpis, [48, 192]);
    // Una seconda richiesta a 48 dpi durante quella nitida si accoda a quella.
    small.dispose();
    big.dispose();
    renderer.dispose();
  });
}
