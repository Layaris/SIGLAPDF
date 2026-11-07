import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

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
    return PickedBytes(f.name, await f.readAsBytes());
  }

  @override
  Future<PickedBytes?> pickPdf() => _one(FileType.custom, ext: const ['pdf']);

  @override
  Future<PickedBytes?> pickImage() => _one(FileType.image);

  @override
  Future<List<PickedBytes>> pickImages() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    return [for (final f in files) PickedBytes(f.name, await f.readAsBytes())];
  }

  @override
  Future<PickedBytes?> pickAny({List<String>? extensions}) =>
      extensions == null ? _one(FileType.any) : _one(FileType.custom, ext: extensions);

  @override
  Future<bool> save({required String fileName, required Uint8List bytes, required String mimeType}) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    return uri != null;
  }
}
