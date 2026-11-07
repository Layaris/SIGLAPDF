# Preparare la prima pubblicazione (da fare una volta sola)

Queste istruzioni sono pensate per essere eseguite sul tuo computer (anche da un agente).
Servono a dare a GitHub i "secret" che il workflow **Pubblica** usa per creare l'APK firmato
e pubblicarlo su Layaris/DMReleases. L'IPA per iPhone per ora non si fa.

## Cosa serve sul computer

1. **GitHub CLI** (`gh`): https://cli.github.com
   - Windows: `winget install --id GitHub.cli`
   - Mac: `brew install gh`
2. **Java** (serve solo il comando `keytool`), versione 17 o più recente:
   - Windows: `winget install --id EclipseAdoptium.Temurin.17.JDK`
   - Mac: `brew install --cask temurin@17`
   - Controllo: `keytool -help` deve rispondere senza errori (se no, riaprire il terminale).

## Passo 1 · Accedere a GitHub

```bash
gh auth login
```

Rispondere: **GitHub.com** › **HTTPS** › **Yes** (autentica git) › **Login with a web browser**,
poi incollare nel browser il codice mostrato e accedere con l'account **Layaris**.

Controllo: `gh auth status` deve mostrare l'account Layaris.

## Passo 2 · Token per pubblicare su DMReleases

```bash
gh auth token | gh secret set DMRELEASES_TOKEN --repo Layaris/SIGLAPDF
```

## Passo 3 · Creare la chiave di firma Android (keystore)

Scegliere una password lunga (almeno 12 caratteri, senza spazi) e usarla al posto di `PASSWORD`
in tutti i comandi qui sotto. In una cartella sicura (es. `Documenti/sigla-firma`):

```bash
keytool -genkeypair -v -keystore sigla-release.jks -alias sigla -keyalg RSA -keysize 2048 -validity 10000 -storepass PASSWORD -keypass PASSWORD -dname "CN=Sigla, O=DM Releases, C=IT"
```

> **Molto importante:** fare subito una copia di `sigla-release.jks` e della password
> (per esempio su una chiavetta e in un gestore di password). Se si perdono, gli aggiornamenti
> futuri non si potranno più installare sopra l'app esistente.

## Passo 4 · Caricare la chiave nei secret

Dalla cartella che contiene `sigla-release.jks`.

**Windows (PowerShell):**

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\sigla-release.jks")) | gh secret set ANDROID_KEYSTORE_BASE64 --repo Layaris/SIGLAPDF
```

**Mac / Linux:**

```bash
base64 < sigla-release.jks | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64 --repo Layaris/SIGLAPDF
```

Poi (tutti i sistemi), sostituendo `PASSWORD`:

```bash
gh secret set ANDROID_KEYSTORE_PASSWORD --repo Layaris/SIGLAPDF --body "PASSWORD"
```

```bash
gh secret set ANDROID_KEY_PASSWORD --repo Layaris/SIGLAPDF --body "PASSWORD"
```

```bash
gh secret set ANDROID_KEY_ALIAS --repo Layaris/SIGLAPDF --body "sigla"
```

## Passo 5 · Controllo

```bash
gh secret list --repo Layaris/SIGLAPDF
```

Devono comparire 5 nomi: `DMRELEASES_TOKEN`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`.

## Passo 6 · Avviare la pubblicazione

Dire a Claude "secret fatti": avvia lui il workflow e lo segue. In alternativa:

```bash
gh workflow run Pubblica --repo Layaris/SIGLAPDF -f android=true -f ios=false -f publish=true
```

Dura circa 10–15 minuti. Alla fine l'APK è in https://github.com/Layaris/DMReleases/releases
con il nome **Sigla · build N**.
