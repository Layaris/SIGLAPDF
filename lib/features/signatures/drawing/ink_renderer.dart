import 'dart:typed_data';
import 'dart:ui' as ui;

import 'ink_model.dart';

/// Risultato del render di una firma: PNG trasparente e dimensioni in pixel.
class RenderedSignature {
  const RenderedSignature(this.png, this.width, this.height);
  final Uint8List png;
  final int width;
  final int height;
}

/// Renderizza i tratti in un PNG trasparente ritagliato sul contenuto.
/// [pixelRatio] aumenta la risoluzione (3 = nitido anche su PDF stampati).
Future<RenderedSignature?> renderStrokesToPng(List<InkStroke> strokes, {double pixelRatio = 3}) async {
  final bounds = strokesBounds(strokes);
  if (bounds == null || bounds.isEmpty) return null;
  final w = (bounds.width * pixelRatio).ceil().clamp(1, 4096);
  final h = (bounds.height * pixelRatio).ceil().clamp(1, 4096);
  final scale = w / bounds.width;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paintStrokes(canvas, strokes, scale: scale, shift: -bounds.topLeft);
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  if (data == null) return null;
  return RenderedSignature(data.buffer.asUint8List(), w, h);
}
