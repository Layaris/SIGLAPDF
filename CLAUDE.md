# CLAUDE.md — Sigla

Guida per riprendere il lavoro su **Sigla** (nome provvisorio, cambiabile).

## Scopo

App Flutter (Android, iOS, Web) per **compilare e firmare PDF**. Gratuita per uso personale,
interfaccia in italiano, grafica minimalista "inchiostro e carta". Tutto in locale e offline:
nessun cloud, nessun account, nessun tracciamento. L'unica chiamata di rete opzionale è il
riconoscimento campi con l'API Anthropic, con chiave inserita dall'utente.

## Stack

- Flutter stable 3.47.x (Dart 3.13). Un solo codice per Android, iOS e Web.
- `org: it.sigla`, project name `sigla`.
- PDF: `syncfusion_flutter_pdf` (lettura/scrittura, AcroForm, estrazione testo, flatten).
- Render pagine e condivisione: `printing` (`Printing.raster`, `Printing.sharePdf`).
  Sul web `printing` usa pdf.js (vedi "Decisioni").
- File: `file_picker` v13 (API nuova: `pickFile()` → `PlatformFile?`, `readAsBytes()`,
  `saveFile(fileName:, bytes:, mimeType:)`).
- Immagini: `image` (puro Dart, anche web).
- Archivio: `hive_ce` + `hive_ce_flutter` (IndexedDB sul web).
- Cifratura backup: `cryptography` (AES-256-GCM + PBKDF2-HMAC-SHA256).
- Biometria: `local_auth` v3 (`authenticate(localizedReason:, biometricOnly:, persistAcrossBackgrounding:)`).
- Altro: `image_picker`, `cunning_document_scanner` (solo mobile), `receive_sharing_intent`
  (solo Android), `share_plus` v13 (`SharePlus.instance.share(ShareParams(...))`), `http`, `uuid`, `intl`.
- Stato: `ChangeNotifier` + `ListenableBuilder`. Niente framework di stato.

## Struttura

```
lib/
  main.dart                 avvio: storage, servizi, runApp
  app.dart                  SiglaApp (MaterialApp, temi, scope dei servizi)
  core/
    storage/                KeyValueStore (Hive e in memoria per i test)
    theme/                  colori e temi chiaro/scuro
    utils/                  coordinate, date, file, piattaforma
    widgets/                componenti riusabili (stato vuoto, sezioni…)
  features/
    home/                   shell di navigazione adattiva (Documenti, Firme, Profilo, Impostazioni)
    documents/              apertura PDF, editor, elementi posizionabili, campi
    signatures/             libreria firme, disegno, import immagine, firma scritta
    profile/                profilo dati per autocompilazione
    settings/               impostazioni, blocco biometrico, AI, nota legale
    backup/                 esporta/importa backup .sigla
  services/
    pdf_service.dart        render, esportazione con flatten, AcroForm
    signature_processing.dart   scontorno (Otsu), ritaglio, ricolorazione, tratti
    field_detection/        FieldDetector + motore locale + motore AI
    crypto_backup.dart      formato .sigla cifrato, versioni e migrazioni
test/                       unit test per i servizi, widget test per le schermate
docs/                       ROADMAP.md, ARCHITECTURE.md
.github/workflows/          build e pubblicazione manuale su Layaris/DMReleases
```

## Comandi

```bash
export PATH=/opt/flutter/bin:$PATH   # nel container cloud Flutter è in /opt/flutter
flutter pub get
flutter analyze
flutter test
flutter run -d chrome                # web
flutter build web --release
flutter build apk --release          # NON lanciarlo nel container: si builda su GitHub
```

## Convenzioni

- Testi UI in italiano, brevi, verbi d'azione ("Firma", "Esporta PDF").
- Logica pura in `services/` e nei modelli, senza dipendenze dalla UI, coperta da test.
- Niente `dart:io` diretto nel codice condiviso: usare `XFile` (cross_file) e guardie `kIsWeb`.
- Coordinate degli elementi **normalizzate 0–1** rispetto alla pagina come la vede l'utente
  (già ruotata); convertite in punti PDF solo all'esportazione (`core/utils/pdf_coords.dart`).
- Prima di ogni commit: `flutter analyze` e `flutter test` senza errori.
- Commit piccoli, messaggi in italiano al presente ("Aggiunge…", "Corregge…").
- Prima di usare un'API di un pacchetto, verificarla in `~/.pub-cache/hosted/pub.dev/<pkg>`.

## Decisioni prese (e perché)

- **printing invece di pdfrx**: niente NDK su Android, render affidabile su tutte le piattaforme.
- **Hive con mappe JSON-like** (nessun TypeAdapter): schema semplice, facile da migrare e da
  mettere nel backup.
- **KeyValueStore astratto**: i repository si testano con uno store in memoria.
- **PBKDF2-HMAC-SHA256 (310 000 iterazioni) invece di Argon2id**: su web usa WebCrypto (veloce),
  Argon2id in puro Dart sarebbe troppo lento nel browser. Iterazioni salvate nell'header,
  quindi aumentabili in futuro senza rompere i vecchi backup.
- **La chiave API non va nel backup**: è un segreto locale del dispositivo.
- **Spunta e croce disegnate come vettori** all'esportazione (Helvetica non ha ✓/✗).
- **Firme sempre come PNG trasparente** ritagliato: disegno, import e firma scritta producono
  lo stesso formato, quindi editor ed esportazione hanno un solo percorso.
- **Blocco biometrico solo sulle firme** (libreria e inserimento nell'editor), si richiude quando
  l'app va in background. Disattivato sul web.
- **Rilevamento campi dietro `FieldDetector`**: motore locale (testo + dizionario) predefinito,
  motore AI opzionale. Mai inserimenti silenziosi: sempre anteprima con conferma.
- **Build solo su GitHub Actions, manuale** (`workflow_dispatch`), per non consumare minuti.

## Stato attuale

Vedi `docs/ROADMAP.md` per il dettaglio. Fase corrente: **1 — setup, tema, navigazione**.

## Prossimi passi

1. Archivio locale, libreria firme, disegno firma.
