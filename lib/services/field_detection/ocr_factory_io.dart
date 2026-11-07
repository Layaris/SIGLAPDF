import 'dart:io' show Platform;

import 'ocr.dart';
import 'ocr_mlkit.dart';

/// Android: Google ML Kit (modello incluso nell'app, funziona offline).
/// iOS per ora escluso: l'IPA non è ancora pubblicato e ML Kit lì non è stato provato.
OcrEngine? createDeviceOcr() => Platform.isAndroid ? MlKitOcrEngine() : null;
