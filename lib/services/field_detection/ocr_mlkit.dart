import 'dart:async';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr.dart';

/// OCR con Google ML Kit (script latino). Il modello è nell'APK: niente rete.
/// Il riconoscitore si riusa tra le pagine di una stessa ricerca e si chiude dopo un po' di inattività
/// (ricrearlo per ogni pagina ricaricherebbe il modello ogni volta).
class MlKitOcrEngine implements OcrEngine {
  TextRecognizer? _recognizer;
  Timer? _idle;

  @override
  Future<List<List<OcrWord>>> recognize(Uint8List rgba, int width, int height) async {
    _idle?.cancel();
    final recognizer = _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
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
      _idle = Timer(const Duration(seconds: 30), () {
        final r = _recognizer;
        _recognizer = null;
        unawaited(r?.close());
      });
    }
  }
}
