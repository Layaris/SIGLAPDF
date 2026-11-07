import 'dart:typed_data';
import 'dart:ui';

import 'ocr_factory_stub.dart' if (dart.library.io) 'ocr_factory_io.dart' as impl;

/// Parola letta dall'OCR, con riquadro in pixel dell'immagine.
class OcrWord {
  const OcrWord(this.text, this.rect);
  final String text;
  final Rect rect;
}

/// Motore OCR sul dispositivo (nessun invio in rete).
abstract class OcrEngine {
  /// Legge il testo da un'immagine RGBA e restituisce le righe di parole.
  Future<List<List<OcrWord>>> recognize(Uint8List rgba, int width, int height);
}

/// OCR disponibile su questa piattaforma (Google ML Kit su Android), altrimenti null.
OcrEngine? createDeviceOcr() => impl.createDeviceOcr();
