# Architettura di Sigla

## Panoramica

```
UI (features/*)  ──ascolta──▶  Repository / Controller (ChangeNotifier)
      │                               │
      └──chiama──▶ services/ (logica pura, testabile)
                                      │
                         core/storage (KeyValueStore → Hive)
```

- **UI**: widget per funzione in `lib/features/`. Si aggiornano con `ListenableBuilder`.
- **Repository** (`SignatureRepository`, `ProfileRepository`, `SettingsRepository`):
  `ChangeNotifier` che leggono/scrivono su un `KeyValueStore`.
- **Controller dell'editor** (`EditorController`): stato del documento aperto, elementi
  posizionati, selezione, cronologia per undo/redo.
- **Servizi**: logica senza UI (PDF, elaborazione immagini, rilevamento campi, backup).
- **AppServices**: contenitore dei repository e servizi, passato con un `InheritedWidget`
  (`AppScope`) per evitare dipendenze globali e poter iniettare fake nei test.

## Archivio locale

`KeyValueStore` ha due implementazioni: `HiveKeyValueStore` (app) e `MemoryKeyValueStore` (test).
Box Hive:

| Box          | Chiave         | Valore                                   |
|--------------|----------------|------------------------------------------|
| `signatures` | id (uuid)      | mappa della firma (PNG in `Uint8List`)   |
| `profile`    | `profile`      | mappa del profilo                        |
| `settings`   | `settings`     | mappa delle impostazioni                 |

Sul web Hive salva in IndexedDB.

## Coordinate

Gli elementi sul PDF hanno un rettangolo **normalizzato** `(x, y, w, h)` in `[0, 1]` rispetto
alla pagina **come viene mostrata** (rotazione già applicata), origine in alto a sinistra.
All'esportazione `PdfCoords` converte in punti PDF nello spazio di disegno della pagina
(syncfusion: origine in alto a sinistra, unità punti), tenendo conto della rotazione
(0/90/180/270) della pagina.

## Flusso dell'editor

1. Il PDF viene caricato in byte (`file_picker`, "Apri con", scanner).
2. `PdfService.inspect` legge numero pagine, dimensioni, rotazione, campi AcroForm.
3. Le pagine vengono renderizzate al bisogno con `Printing.raster` (pdfium su mobile, pdf.js sul
   web) da `PageRenderer`: massimo due render insieme, cache LRU di 10 pagine; ogni widget riceve
   una copia (`ui.Image.clone`) che libera quando non serve più.
4. L'utente aggiunge elementi; ogni modifica conclusa crea uno snapshot nella cronologia.
5. `PdfService.export` riapre il PDF originale, compila i campi AcroForm, disegna gli elementi
   nel contenuto della pagina, appiattisce i campi (flatten) e salva i byte.
6. Il file si salva (`FilePicker.saveFile`) o si condivide (`Printing.sharePdf`).

## Blocco delle firme

`SignatureLock` (con `Authenticator`, finto nei test) protegge libreria e inserimento delle firme.
`AppLifecycleListener` chiama `onHidden`/`onShown`: il blocco si richiude solo se l'app è rimasta
in background più di 30 secondi (scegliere un file o scattare una foto non lo richiude).

## Ingressi dei documenti

- `FileAccess.pickPdf` (file picker), `DocumentScanner` (cunning_document_scanner, mobile),
  `imagesToPdf` (immagini → PDF, una pagina A4 per immagine), `ShareIntentSource` ("Apri con" /
  "Condividi" su Android, avviato da `main.dart` con un `navigatorKey`).

## Rilevamento campi

Interfaccia `FieldDetector` → `Future<List<DetectedField>> detect(DetectionInput)`.

- `LocalTextFieldDetector`: estrae le righe con coordinate (`PdfTextExtractor`), cerca le
  etichette con un dizionario italiano/inglese e trova lo spazio da compilare
  (sequenze `___` o `....`, spazio dopo `:` fino a fine riga, spazio sotto l'etichetta).
- `DeviceFieldDetector` (quello usato dall'app): per le pagine con testo usa la stessa logica del
  motore locale; per le pagine scansionate, su Android, renderizza la pagina e la legge con l'OCR
  di Google ML Kit sul telefono, poi applica il dizionario alle parole lette. Niente rete.
- `AnthropicFieldDetector`: render della pagina in PNG e richiesta all'API Messages; la
  risposta deve essere solo JSON con etichetta, tipo e riquadro normalizzato.

I risultati passano sempre da un'anteprima in cui l'utente conferma, corregge o scarta.

## Formato del backup `.sigla`

File JSON in UTF-8 (l'envelope è in chiaro, il contenuto è cifrato):

```json
{
  "format": "sigla-backup",
  "version": 2,
  "createdAt": "2026-11-07T10:00:00.000Z",
  "kdf": { "name": "pbkdf2-hmac-sha256", "iterations": 310000, "salt": "<base64, 16 byte>" },
  "cipher": { "name": "aes-256-gcm", "nonce": "<base64, 12 byte>", "mac": "<base64, 16 byte>" },
  "ciphertext": "<base64>"
}
```

- Chiave: 256 bit derivati dalla password con PBKDF2-HMAC-SHA256, salt casuale di 16 byte.
- Cifratura: AES-256-GCM, nonce casuale di 12 byte, tag di 16 byte. L'header (format, version,
  kdf, cipher name) è usato come dato autenticato aggiuntivo (AAD) per evitare manomissioni.
- Contenuto in chiaro (dopo la decifratura), JSON (schema 3):

```json
{
  "schema": 3,
  "signatures": [
    { "id": "…", "name": "Firma", "kind": "signature|initials", "source": "drawn|image|typed",
      "png": "<base64>", "isDefault": true, "createdAt": "…" }
  ],
  "profiles": [
    { "id": "…", "label": "Io", "data": { "firstName": "…", "gender": "M|F", "…": "…",
      "custom": [ { "key": "…", "value": "…" } ] } }
  ],
  "activeProfile": "…",
  "templates": [
    { "id": "…", "name": "…", "pageCount": 2, "fingerprint": "p2-…", "createdAt": "…",
      "elements": [ { "type": "signature|date|text|ink|…", "page": 0,
                      "rect": { "x": 0.1, "y": 0.8, "w": 0.3, "h": 0.06 }, "text": "…", "color": 4280149951 } ] }
  ],
  "settings": { "themeMode": "system", "inkColor": "blue", "…": "…" }
}
```

- La chiave API Anthropic **non** è inclusa.
- **Versioni**: `version` è la versione dell'envelope, `schema` quella del contenuto.
  `BackupMigrations` porta un contenuto vecchio allo schema corrente prima dell'import.
  - Schema 1 (formato preliminare): firme con campo `type` (`draw|image|text`) e senza `kind`;
    profilo con i campi personalizzati come mappa `extra`. La migrazione a 2 converte
    `type` in `source`, imposta `kind: signature` e trasforma `extra` in lista `custom`.
  - Schema 2: un solo `profile`. La migrazione a 3 lo mette in `profiles` con id `principale`
    e nome "Io", imposta `activeProfile` e aggiunge `templates` vuoto.
- I documenti recenti **non** sono nel backup (possono essere grandi e personali).
- **Import**: "Unisci" aggiunge le firme e i modelli mancanti (per id); per i profili, stesso id o
  stesso nome → completa solo i campi vuoti, altrimenti aggiunge il profilo. "Sostituisci" cancella
  i dati locali e usa quelli del backup (la chiave API resta).
- Password sbagliata o file alterato → errore di autenticazione GCM → messaggio
  "Password errata o file danneggiato".
