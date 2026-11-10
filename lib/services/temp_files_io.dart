import 'dart:io';

/// Si cancellano solo file nelle cartelle private di Sigla (cache, file dell'app): mai un file
/// dell'utente, anche se un'altra app ("Apri con" da un file manager) passasse il percorso originale.
bool isAppPrivatePath(String path, {String? tempDir}) {
  final p = path.replaceAll('\\', '/');
  final tmp = (tempDir ?? Directory.systemTemp.path).replaceAll('\\', '/');
  return p.contains('/it.sigla.sigla/') || (tmp.isNotEmpty && p.startsWith(tmp));
}

Future<void> deleteTempFile(String? path) async {
  if (path == null || path.isEmpty || !isAppPrivatePath(path)) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // Non cancellabile: si lascia.
  }
}

Future<int?> fileLength(String path) async {
  try {
    return await File(path).length();
  } catch (_) {
    return null;
  }
}
