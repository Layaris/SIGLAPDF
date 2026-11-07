import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Scanner documenti con correzione della prospettiva (solo Android e iOS).
class DocumentScanner {
  const DocumentScanner();

  bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Immagini delle pagine scansionate; lista vuota se annullato.
  Future<List<Uint8List>> scan() async {
    final paths = await CunningDocumentScanner.getPictures(noOfPages: 30) ?? const <String>[];
    return [for (final p in paths) await XFile(p).readAsBytes()];
  }
}

/// PDF ricevuto da "Apri con" o "Condividi".
class IncomingPdf {
  const IncomingPdf(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// "Apri con" / "Condividi" verso Sigla (solo Android).
class ShareIntentSource {
  ShareIntentSource();

  StreamSubscription<List<SharedMediaFile>>? _sub;

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Ascolta i PDF in arrivo (all'avvio e con l'app aperta).
  Future<void> start(void Function(IncomingPdf pdf) onPdf) async {
    if (!isSupported) return;
    Future<void> handle(List<SharedMediaFile> files) async {
      for (final f in files) {
        final isPdf = (f.mimeType ?? '').contains('pdf') || f.path.toLowerCase().endsWith('.pdf');
        if (!isPdf) continue;
        try {
          final bytes = await XFile(f.path).readAsBytes();
          final name = f.path.split('/').last;
          onPdf(IncomingPdf(name.isEmpty ? 'documento.pdf' : name, bytes));
        } catch (_) {
          // File non leggibile: ignorato.
        }
      }
    }

    try {
      _sub = ReceiveSharingIntent.instance.getMediaStream().listen(handle, onError: (_) {});
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      await handle(initial);
      await ReceiveSharingIntent.instance.reset();
    } catch (_) {
      // Plugin non disponibile: niente "Apri con".
    }
  }

  void dispose() => _sub?.cancel();
}
