import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../../services/signature_processing.dart';

/// Famiglia del font corsivo incluso nell'app.
const cursiveFontFamily = 'GreatVibes';

/// Renderizza un testo con il font corsivo in un PNG trasparente ritagliato.
Future<CutoutResult?> renderTypedSignature(String text, {required Color color, double fontSize = 120}) async {
  final value = text.trim();
  if (value.isEmpty) return null;
  final tp = TextPainter(
    text: TextSpan(
      text: value,
      style: TextStyle(fontFamily: cursiveFontFamily, fontSize: fontSize, color: color, height: 1.4),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  // Margine generoso: gli svolazzi del corsivo escono dal riquadro del testo.
  final pad = fontSize * 0.6;
  final w = (tp.width + pad * 2).ceil();
  final h = (tp.height + pad * 2).ceil();
  final recorder = ui.PictureRecorder();
  tp.paint(Canvas(recorder), Offset(pad, pad));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  tp.dispose();
  if (data == null) return null;
  return cropPngToContent(data.buffer.asUint8List());
}
