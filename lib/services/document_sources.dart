import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'temp_files.dart';

/// Scanner documenti con correzione della prospettiva (solo Android e iOS).
class DocumentScanner {
  const DocumentScanner();

  bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// Immagini delle pagine scansionate; lista vuota se annullato.
  Future<List<Uint8List>> scan() async {
    final paths = await CunningDocumentScanner.getPictures(noOfPages: 30) ?? const <String>[];
    final out = <Uint8List>[];
    for (final p in paths) {
      out.add(await XFile(p).readAsBytes());
      // Lo scanner lascia le foto delle pagine nella cartella dell'app: lette, si cancellano.
      await deleteTempFile(p);
    }
    return out;
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

  /// PDF più grandi di così non si aprono (verrebbero caricati tutti in memoria).
  static const maxBytes = 100 * 1024 * 1024;

  /// Ascolta i PDF in arrivo (all'avvio e con l'app aperta). [onTooLarge] se il file supera [maxBytes].
  Future<void> start(void Function(IncomingPdf pdf) onPdf, {void Function(String name)? onTooLarge}) async {
    if (!isSupported) return;
    Future<void> handle(List<SharedMediaFile> files) async {
      for (final f in files) {
        final isPdf = (f.mimeType ?? '').contains('pdf') || f.path.toLowerCase().endsWith('.pdf');
        if (!isPdf) continue;
        final name = f.path.split('/').last;
        try {
          final size = await fileLength(f.path);
          if (size != null && size > maxBytes) {
            onTooLarge?.call(name);
            continue;
          }
          final bytes = await XFile(f.path).readAsBytes();
          onPdf(IncomingPdf(name.isEmpty ? 'documento.pdf' : name, bytes));
        } catch (_) {
          // File non leggibile (o già tolto: un "Apri con" vecchio riconsegnato all'avvio): ignorato.
        } finally {
          // Il plugin copia il PDF nella cache dell'app: letto, si cancella.
          await deleteTempFile(f.path);
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
