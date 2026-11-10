import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sigla/services/temp_files_io.dart';

void main() {
  test('si cancellano solo file nelle cartelle private di Sigla', () async {
    expect(isAppPrivatePath('/data/user/0/it.sigla.sigla/cache/doc.pdf', tempDir: '/data/user/0/it.sigla.sigla/cache'), isTrue);
    expect(isAppPrivatePath('/storage/emulated/0/Android/data/it.sigla.sigla/files/Pictures/scan1.jpg', tempDir: '/x'), isTrue);
    expect(isAppPrivatePath('/storage/emulated/0/Download/contratto.pdf', tempDir: '/data/user/0/it.sigla.sigla/cache'), isFalse,
        reason: 'un file dell\'utente non si tocca');
    // File temporaneo vero: viene cancellato.
    final f = File('${Directory.systemTemp.path}/sigla_test_${DateTime.now().microsecondsSinceEpoch}.pdf')..writeAsStringSync('x');
    expect(await fileLength(f.path), 1);
    await deleteTempFile(f.path);
    expect(f.existsSync(), isFalse);
    // Fuori dalle cartelle private: resta.
    final outside = Directory('${Directory.current.path}/build/sigla_test_keep')..createSync(recursive: true);
    final keep = File('${outside.path}/keep.pdf')..writeAsStringSync('x');
    await deleteTempFile(keep.path);
    expect(keep.existsSync(), isTrue);
    outside.deleteSync(recursive: true);
  });
}
