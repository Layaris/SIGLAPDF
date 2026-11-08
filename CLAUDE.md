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
    field_detection/        FieldDetector + motore locale (testo + OCR ML Kit) + motore AI
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
- **Lingue**: ogni testo visibile passa da `tr('testo italiano', [arg0, arg1])` (`core/l10n/l10n.dart`),
  con segnaposto `{0}`, `{1}`. La traduzione inglese va aggiunta in `core/l10n/strings_en.dart`
  (chiave = testo italiano come scritto nel sorgente). `test/l10n_test.dart` fallisce se manca.
  Non usare `tr()` in valori `const`/`static final`/liste globali (verrebbero calcolati una volta
  sola): usare getter. Le etichette degli enum si traducono con `String get label => tr(_it)`.
  Lingua: impostazione `language` ('it' predefinita, 'en', 'system'); cambiarla ricostruisce
  l'app (chiave sul `MaterialApp`) e `HomeShell` ricorda la scheda aperta.
- Logica pura in `services/` e nei modelli, senza dipendenze dalla UI, coperta da test.
- Niente `dart:io` diretto nel codice condiviso: usare `XFile` (cross_file) e guardie `kIsWeb`.
- Coordinate degli elementi **normalizzate 0–1** rispetto alla pagina come la vede l'utente
  (già ruotata); convertite in punti PDF solo all'esportazione (`core/utils/pdf_coords.dart`).
- Prima di ogni commit: `flutter analyze` e `flutter test` senza errori.
- Commit piccoli, messaggi in italiano al presente ("Aggiunge…", "Corregge…").
- Prima di usare un'API di un pacchetto, verificarla in `~/.pub-cache/hosted/pub.dev/<pkg>`.

## Novità e DMReleases (obbligatorio per ogni funzione visibile)

Le pagine pubbliche di Sigla stanno in **Layaris/DMReleases** e devono restare allineate all'app.
Quando aggiungi o cambi qualcosa che l'utente vede:

1. Scrivi una riga in parole semplici in `NOVITA.md`, sezione "Prossima versione". Alla pubblicazione
   (*Pubblica*) lo script `.github/scripts/update_dmreleases.py` la mette nelle note della release e nel
   `sigla/CHANGELOG.md` di DMReleases, e qui la sposta sotto "build-N" (il workflow fa il commit).
2. Per le funzioni importanti aggiorna anche, in DMReleases (branch `claude/determined-keller-5b8xki`,
   poi PR verso `main`):
   - `sigla/README.md` (sezione "Cosa fa") e `sigla/GUIDA.md` (come si usa);
   - `docs/sigla/index.html` (schede "Cosa fa") e la scheda di Sigla in `docs/index.html`;
   - `sigla/PRIVACY.md` e `docs/sigla/privacy.html` se cambia cosa va in rete;
   - `README.md` principale (blocco `<!-- app:sigla -->`) se cambia la descrizione breve.
3. Se cambia l'aspetto, rifai gli screenshot (dati di fantasia, modulo di esempio incluso):
   ```bash
   flutter build web --release --no-web-resources-cdn
   (cd build/web && python3 -m http.server 8766 &)
   NODE_PATH=$(npm root -g) node tool/screenshots/screenshots.js /tmp/shots
   python3 tool/screenshots/copy_to_dmreleases.py /tmp/shots ../DMReleases
   ```
   Lo script pilota la web app tramite l'albero di accessibilità di Flutter (`tool/screenshots/lib.js`):
   niente `scrollIntoView` (sposta solo l'albero, non la pagina), si scorre con la rotellina; i trascinamenti
   compensano la soglia del gesto; in modalità penna la pagina non è nell'albero. Le posizioni sul modulo
   vengono da `posizioni.json`, scritto da `make_sample_pdf.py`.

## Decisioni prese (e perché)

- **`asStringMap` non tocca i `TypedData`**: i PNG letti da Hive restano `Uint8List`.
- **Scontorno**: soglia di Otsu sui grigi; l'inchiostro è pieno fino alla soglia e sfuma
  sopra (Otsu con poca firma e molta carta mette la soglia vicino all'inchiostro). Le foto
  vengono raddrizzate (EXIF) e ridotte a 1400 px; su mobile l'elaborazione va in `compute`.
- **Font corsivo**: Great Vibes (OFL), unico font incluso.
- **`FileAccess` astratto** (`core/utils/file_access.dart`) per sostituire il file picker nei test.
- **Editor**: pagine in una `ListView` verticale, zoom con pulsanti (100–300%) e scorrimento
  orizzontale quando serve; niente pinch per non litigare con il trascinamento degli elementi.
  Nuovi elementi al centro della parte visibile della pagina corrente. Cronologia a snapshot
  immutabili (max 100); un gesto di trascinamento = un passo (`beginChange`/`endChange`).
- **Rotazione pagine**: syncfusion disegna le pagine caricate nello spazio non ruotato; prima di
  disegnare si applica `PdfCoords.visualTransform` (traslazione + rotazione) così le coordinate
  visive finiscono al posto giusto. Verificato da test con estrazione del testo.
- **Testo nel PDF**: Helvetica standard (WinAnsi). `sanitizeForStandardFont` sostituisce i
  caratteri non supportati. Corpo = altezza riquadro × 0,72, ridotto se non entra in larghezza.
- **Render pagine**: `PageRenderer` con cache e massimo due render in parallelo; dpi in base alla
  larghezza mostrata (tetto 220). Attenzione: in `whenComplete` non restituire il future stesso
  (deadlock trovato e corretto).
- **Riconoscimento campi**: etichette normalizzate a lunghezza invariata (indici → coordinate
  dei caratteri). Corrispondenza più lunga e non sovrapposta; "il" vale come data di nascita
  solo dopo "nato a". Spazio da compilare: linea `___`/`....` → dopo `:` fino alla prossima
  etichetta o al margine → riga di soli `___` sotto → spazio libero sotto. Le proposte senza
  valore nel profilo partono escluse; "Luogo e data" usa la data di oggi anche senza città.
- **AcroForm + profilo**: abbinamento per nome del campo (`kindForFieldName`, es. `codiceFiscale`,
  `data_nascita`, `CF`); si compilano solo i campi vuoti. La digitazione nello stesso campo è un
  solo passo di annulla.
- **AI (Anthropic)**: chiamata HTTP diretta (non esiste un SDK Dart ufficiale) a `/v1/messages`,
  `anthropic-version: 2026-10-21`, immagine PNG a 110 dpi, risposta vincolata con
  `output_config.format` (`json_schema`). Sul web header `anthropic-dangerous-direct-browser-access`.
  Massimo 10 pagine per richiesta. Prima di usarla l'editor chiede il motore e avvisa dell'invio.
- **Blocco firme**: `SignatureLock` + `Authenticator` (fake nei test). Si richiude con
  `AppLifecycleListener` (onHide/onPause). `biometricOnly: false` per permettere il PIN.
- **Impostazioni**: le sezioni non sono `const`, altrimenti non si ricostruiscono al cambio.
- **"Apri con"** solo Android (`receive_sharing_intent`, VIEW e SEND `application/pdf`). Su iOS
  niente `CFBundleDocumentTypes` finché non c'è la share extension, per non mostrare un'opzione
  che non funziona.
- **Immagini → PDF**: pagina A4 per immagine; l'orizzontale si imposta con `orientation`
  (syncfusion normalizza la `size`).
- **Web offline**: pdf.js in `web/pdfjs/` + `--no-web-resources-cdn`. `dartPdfJsBaseUrl` deve
  iniziare con `./` (bug trovato: con `pdfjs/` import() falliva e le pagine restavano vuote).
  Se l'anteprima fallisce compare "Anteprima non disponibile" (mai spinner infinito).
- **Memoria pagine**: cache LRU di 10 pagine con copie `ui.Image.clone` per widget.
- **Blocco firme con margine di 30 s** in background (`SignatureLock.grace`).
- **Android**: temi `Theme.AppCompat.DayNight.NoActionBar` + dipendenza appcompat (richiesto da
  local_auth su Android ≤ 8). Splash e sfondo color carta.
- **Barra strumenti dell'editor** trascinabile anche col mouse (`ScrollConfiguration` con tutti i
  `PointerDeviceKind`), altrimenti sul web desktop gli strumenti in fondo non si raggiungono.
- **Prove nel browser**: servire `build/web` (`python3 -m http.server`) e usare Playwright.
  Con Playwright registrare `page.on('filechooser')` subito: `waitForEvent` attiva
  l'intercettazione in modo asincrono e il primo clic può sfuggire (falso bug).
- **OCR sul dispositivo (Android)**: `DeviceFieldDetector` usa il testo del PDF; per le pagine con
  meno di 3 parole (scansioni) renderizza la pagina a 200 dpi in RGBA e la legge con Google ML Kit
  (`InputImage.fromBitmap`, modello latino incluso nell'APK, offline). Le parole OCR (pixel) diventano
  `WordBox` in punti e passano dallo stesso dizionario (`detectFieldsInLines`). ML Kit importa
  `dart:io`: è isolato con import condizionale (`ocr.dart` → `ocr_factory_io.dart` / `_stub.dart`),
  così la web app compila. Su iOS per ora disattivato (non provato; ML Kit può richiedere iOS 15.5+).
- **Recenti**: ultimi 12 PDF esportati in Hive (box `recents`), max 25 MB l'uno, con miniatura;
  non vanno nel backup; si spengono in Impostazioni (e si cancellano).
- **Modelli**: `FormTemplate` (box `templates`) con elementi serializzati senza immagini; impronta del
  modulo (`documentFingerprint`: lettere/cifre delle prime 2 pagine + numero pagine, due FNV-1a a 32
  bit scomposti per non superare 2^53 sul web). Proposta automatica in cima all'editor.
- **Profili multipli**: chiavi `profiles` (lista) e `active`; la vecchia chiave `profile` migra a "Io".
  Backup **schema 3** (profili + modelli), migrazione 2→3 in `BackupMigrations`.
- **Caselle di scelta**: `FieldKind.gender`/`yesNo` con `DetectedField.options`; caselle `[ ]`, `( )`,
  `☐`… (spazi multipli ammessi: l'estrazione separa i caratteri) o "Sesso M F"; spunta sulla casella.
- **Penna/evidenziatore**: tratti come `ElementType.ink` con punti normalizzati nel riquadro
  (`inkElementFromStroke`); evidenziatore esportato con trasparenza `multiply`.
- **Avviso di versione**: `UpdateService` legge `raw.githubusercontent.com/Layaris/DMReleases/main/sigla/latest.json`
  (max 1 volta/20 h, solo Android, build da `--dart-define=APP_BUILD`).
- **Web app**: workflow `web.yml` → Cloudflare Pages, progetto `dmsigla` (`https://dmsigla.pages.dev`,
  base href `/`), come le altre app di DMReleases. Parte da solo a ogni push che tocca
  `lib/ web/ assets/ pubspec.*` sul branch principale (e a mano). Usa `npx wrangler@4`; crea il progetto
  se manca. Secret `CLOUDFLARE_API_TOKEN` (Pages Edit) e `CLOUDFLARE_ACCOUNT_ID`; senza secret salta
  la pubblicazione senza fallire. Le chiavi dell'utente stanno sul suo PC (vedi `docs/PUBBLICAZIONE.md`).
- **Esportazione in due passaggi**: syncfusion appiattisce i campi al salvataggio disegnandoli *sopra* il
  contenuto. Con campi AcroForm: compila → appiattisce → salva → riapre → disegna firme e testi → salva
  (verificato con pdftoppm: un campo con sfondo grigio copriva la firma). Le immagini uguali (stesso
  `Uint8List`) diventano un solo `PdfBitmap`.
- **Import "Sostituisci"**: prima si leggono e validano tutte le voci, poi si cancella; un backup senza dati
  utili viene rifiutato. `biometricLock` e la chiave API restano quelli del dispositivo. Iterazioni PBKDF2
  lette dal file al massimo `maxIterations` (2 000 000). Export e "Sostituisci" chiedono lo sblocco firme.
- **Recenti**: oltre a 12 file, tetto totale di 80 MB (la box Hive è caricata tutta in memoria).
- **PageRenderer**: un render in corso si riusa solo se abbastanza nitido, altrimenti se ne accoda uno.
- **Pressione solo da stilo**: il dito su Android dà pressioni rumorose; senza stilo lo
  spessore varia con la velocità (più veloce = più sottile), filtrato passa-basso.

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
- **Build solo su GitHub Actions**: APK/IPA manuali (`workflow_dispatch`); la web app si ripubblica da sola
  a ogni push del codice (repository pubblico: minuti gratuiti).

## Stato attuale

Vedi `docs/ROADMAP.md`. **Fasi 1–9 completate** più le migliorie (recenti, modelli, firma con data,
penna/evidenziatore, zoom con due dita e miniature, più profili, caselle Sì/No e M/F, avviso di nuova
versione, web app su Cloudflare Pages, inglese). 154 test verdi, `flutter analyze` pulito,
build web verificata nel browser (Playwright: firma, profilo, apertura PDF, compilazione automatica,
esportazione, nessuna richiesta esterna). **APK pubblicato** (build 5 su DMReleases, dopo l'audit; firmato con la
chiave `CN=Sigla, O=DM Releases`, stesso certificato della build 4, ~100 MB universale); web app online su https://dmsigla.pages.dev.
Correzioni della prima build: `compileSdk = 37` (receive_sharing_intent) con
`android.suppressUnsupportedCompileSdk=37`, `proguard-rules.pro` con `-dontwarn` per i riconoscitori
ML Kit non inclusi. Non ancora provato su un telefono vero. L'IPA per ora non si fa.
In SIGLAPDF il branch `claude/determined-keller-5b8xki` è l'unico ed è quello predefinito.
In DMReleases la cartella `sigla/` è già su `main` (Layaris/DMReleases#1).

## Prossimi passi

1. Configurazione fatta: 7 secret su SIGLAPDF; chiavi dell'utente in
   `C:\Users\tyrig\Documents\progetti claude\CHIAVI PRIVATE\SIGLA` (keystore creato sul suo PC,
   token GitHub solo su DMReleases con Contents RW).
2. L'utente prova l'APK sul telefono: correggere quello che non va. Possibile miglioria: APK divisi per
   architettura (`--split-per-abi`) per ridurre i ~100 MB.
3. Idee future in `docs/ROADMAP.md`.
