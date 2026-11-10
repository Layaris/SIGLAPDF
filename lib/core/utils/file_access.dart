import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// File scelto dall'utente: nome e byte.
class PickedBytes {
  const PickedBytes(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Accesso ai file del dispositivo, astratto per poterlo sostituire nei test.
abstract class FileAccess {
  Future<PickedBytes?> pickPdf();
  Future<PickedBytes?> pickImage();
  Future<List<PickedBytes>> pickImages();
  Future<PickedBytes?> pickAny({List<String>? extensions});

  /// Salva i byte con il dialogo di sistema (sul web: download). True se salvato.
  Future<bool> save({required String fileName, required Uint8List bytes, required String mimeType});
}

class SystemFileAccess implements FileAccess {
  const SystemFileAccess();

  Future<PickedBytes?> _one(FileType type, {List<String>? ext}) async {
    final f = await FilePicker.pickFile(type: type, allowedExtensions: ext);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    await _clearCache();
    return PickedBytes(f.name, bytes);
  }

  /// Su Android il file scelto viene copiato nella cache dell'app: letti i byte, la copia si toglie.
  static Future<void> _clearCache() async {
    if (kIsWeb) return;
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
  }

  @override
  Future<PickedBytes?> pickPdf() => _one(FileType.custom, ext: const ['pdf']);

  @override
  Future<PickedBytes?> pickImage() => _one(FileType.image);

  @override
  Future<List<PickedBytes>> pickImages() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final out = [for (final f in files) PickedBytes(f.name, await f.readAsBytes())];
    await _clearCache();
    return out;
  }

  @override
  Future<PickedBytes?> pickAny({List<String>? extensions}) =>
      extensions == null ? _one(FileType.any) : _one(FileType.custom, ext: extensions);

  @override
  Future<bool> save({required String fileName, required Uint8List bytes, required String mimeType}) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    // Sul web il file viene scaricato ma la libreria restituisce sempre null: il salvataggio è riuscito.
    return kIsWeb || uri != null;
  }
}
