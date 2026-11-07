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
3. Le pagine vengono renderizzate al bisogno con `Printing.raster` e messe in cache.
4. L'utente aggiunge elementi; ogni modifica conclusa crea uno snapshot nella cronologia.
5. `PdfService.export` riapre il PDF originale, compila i campi AcroForm, disegna gli elementi
   nel contenuto della pagina, appiattisce i campi (flatten) e salva i byte.
6. Il file si salva (`FilePicker.saveFile`) o si condivide (`Printing.sharePdf`).

## Rilevamento campi

Interfaccia `FieldDetector` → `Future<List<DetectedField>> detect(DetectionInput)`.

- `LocalTextFieldDetector`: estrae le righe con coordinate (`PdfTextExtractor`), cerca le
  etichette con un dizionario italiano/inglese e trova lo spazio da compilare
  (sequenze `___` o `....`, spazio dopo `:` fino a fine riga, spazio sotto l'etichetta).
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
- Contenuto in chiaro (dopo la decifratura), JSON:

```json
{
  "schema": 2,
  "signatures": [
    { "id": "…", "name": "Firma", "kind": "signature|initials", "source": "drawn|image|typed",
      "png": "<base64>", "isDefault": true, "createdAt": "…" }
  ],
  "profile": { "firstName": "…", "…": "…", "custom": [ { "key": "…", "value": "…" } ] },
  "settings": { "themeMode": "system", "inkColor": "blue", "…": "…" }
}
```

- La chiave API Anthropic **non** è inclusa.
- **Versioni**: `version` è la versione dell'envelope, `schema` quella del contenuto.
  `BackupMigrations` porta un contenuto vecchio allo schema corrente prima dell'import.
  - Schema 1 (formato preliminare): firme con campo `type` (`draw|image|text`) e senza `kind`;
    profilo con i campi personalizzati come mappa `extra`. La migrazione a 2 converte
    `type` in `source`, imposta `kind: signature` e trasforma `extra` in lista `custom`.
- **Import**: "Unisci" aggiunge le firme mancanti (per id) e completa il profilo solo nei campi
  vuoti; "Sostituisci" cancella i dati locali e usa quelli del backup.
- Password sbagliata o file alterato → errore di autenticazione GCM → messaggio
  "Password errata o file danneggiato".
