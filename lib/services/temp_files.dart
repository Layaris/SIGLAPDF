import 'temp_files_stub.dart' if (dart.library.io) 'temp_files_io.dart' as impl;

/// Cancella un file temporaneo dopo averne letto i byte (pagine scansionate, PDF ricevuti con
/// "Apri con", foto scattate). Così i documenti non restano nella memoria dell'app.
/// Sul web non fa niente. Gli errori si ignorano: il file potrebbe essere già stato tolto.
Future<void> deleteTempFile(String? path) => impl.deleteTempFile(path);

/// Dimensione di un file in byte, o null se non si riesce a leggerla (sul web: sempre null).
Future<int?> fileLength(String path) => impl.fileLength(path);
