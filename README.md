# Sigla

**Compila e firma PDF dal telefono, dal tablet o dal browser.** Gratuita per uso personale.
Tutto resta sul dispositivo: nessun account, nessun cloud, nessun tracciamento.

> "Sigla" è un nome provvisorio.

## Cosa fa

- **Firme illimitate** con nome, e sigle (iniziali) come tipo separato.
  - Disegno a mano con tratto liscio e supporto alla pressione (Apple Pencil, stilo).
  - Import da foto o file con scontorno automatico dello sfondo.
  - Firma "scritta" con un font corsivo.
- **PDF**: apri da file, da "Apri con" (Android) o con lo scanner (mobile); aggiungi firma, sigla,
  testo, data, spunta e croce; "Sigla tutte le pagine"; esporta il PDF appiattito.
- **Moduli**: compila i campi AcroForm e riconosce anche i campi non segnalati
  ("Nome: ______") proponendo i dati del tuo profilo. Riconoscimento AI facoltativo.
- **Backup** cifrato con password in un unico file `.sigla`.
- **Blocco** delle firme con impronta o Face ID (mobile).

## Requisiti

- Flutter stable 3.47.x (Dart 3.13).
- Android: SDK con minSdk 24. Non serve l'NDK.
- iOS: Mac con Xcode (iOS 13+).

## Setup

```bash
flutter pub get
flutter analyze
flutter test
```

## Avvio

```bash
flutter run -d chrome     # web
flutter run               # dispositivo collegato
```

## Build

### Web

```bash
flutter build web --release
```

L'output è in `build/web/`, pubblicabile su qualsiasi hosting statico.
Nota: sul web il render delle pagine usa pdf.js, caricato dal pacchetto `printing`.

### Android

```bash
flutter build apk --release
```

Per ora l'APK è firmato con la chiave di debug. Per usare una chiave propria:

1. Crea il keystore (una volta sola, conservalo con cura):
   ```bash
   keytool -genkey -v -keystore sigla-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias sigla
   ```
2. Crea `android/key.properties` (non va nel repository):
   ```properties
   storePassword=...
   keyPassword=...
   keyAlias=sigla
   storeFile=/percorso/sigla-release.jks
   ```
3. `android/app/build.gradle.kts` usa automaticamente `key.properties` se esiste,
   altrimenti la chiave di debug.

Su GitHub Actions il keystore arriva dai secret (vedi "Pubblicazione").

### iOS

Serve un Mac con Xcode:

```bash
cd ios && pod install && cd ..
flutter build ipa --release            # con account sviluppatore
flutter build ios --release --no-codesign   # senza firma, per sideload
```

`Info.plist` contiene già i permessi per fotocamera, galleria e Face ID.
Senza Mac l'IPA non firmato si genera con il workflow GitHub (runner macOS) e si installa
con SideStore, AltStore o Sideloadly.

## Pubblicazione

Le build si fanno **solo a mano** su GitHub Actions (workflow *Pubblica*,
`.github/workflows/release.yml`) e vengono pubblicate nel repository
[Layaris/DMReleases](https://github.com/Layaris/DMReleases) come `sigla-build-N`.
Secret richiesti nel repository SIGLAPDF:

| Secret | A cosa serve |
|---|---|
| `DMRELEASES_TOKEN` | token GitHub con permesso *contents: write* su Layaris/DMReleases |
| `ANDROID_KEYSTORE_BASE64` | (facoltativo) keystore in base64 |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | (facoltativi) dati del keystore |

Senza keystore l'APK è firmato con la chiave di debug: in quel caso gli aggiornamenti
potrebbero non installarsi sopra la versione precedente.

## Licenze

- **Syncfusion**: `syncfusion_flutter_pdf` è un pacchetto commerciale con
  [licenza Community gratuita](https://www.syncfusion.com/products/communitylicense)
  per singoli sviluppatori e piccole aziende (meno di 1 milione di dollari di fatturato annuo,
  massimo 5 sviluppatori). Sigla è gratuita per uso personale e rientra in questa licenza.
- Font della firma scritta: vedi `assets/fonts/` (SIL Open Font License).

## Documentazione

- [CLAUDE.md](CLAUDE.md): guida per lo sviluppo
- [docs/ROADMAP.md](docs/ROADMAP.md): funzioni e stato
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): architettura e formato del backup

## Nota legale

La firma grafica apposta con Sigla è una **firma elettronica semplice** (Regolamento eIDAS),
non una firma digitale qualificata.
