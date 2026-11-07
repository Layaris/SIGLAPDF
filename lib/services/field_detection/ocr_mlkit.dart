import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr.dart';

/// OCR con Google ML Kit (script latino). Il modello è nell'APK: niente rete.
class MlKitOcrEngine implements OcrEngine {
  @override
  Future<List<List<OcrWord>>> recognize(Uint8List rgba, int width, int height) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromBitmap(bitmap: rgba, width: width, height: height),
      );
      return [
        for (final block in result.blocks)
          for (final line in block.lines)
            [for (final e in line.elements) OcrWord(e.text, e.boundingBox)],
      ];
    } finally {
      await recognizer.close();
    }
  }
}
