# Preparare la pubblicazione di Sigla (istruzioni per l'agente sul PC)

Da fare **una volta sola**, dal browser (account GitHub **Layaris**, account Cloudflare dell'utente)
e con **PowerShell** per salvare i file. Non serve installare niente (niente GitHub CLI, niente Java).

Alla fine:
- GitHub ha i secret per creare l'**APK firmato** e pubblicarlo su **Layaris/DMReleases**;
- la **web app** si pubblica da sola su **Cloudflare Pages** (https://dmsigla.pages.dev);
- tutte le chiavi sono salvate in `C:\Users\tyrig\Documents\progetti claude\CHIAVI PRIVATE\SIGLA`.

Regole: non incollare mai token o password in chat, in issue o in file del repository.
I file vanno **solo** nella cartella qui sopra.

---

## Passo 0 · Cartella delle chiavi

In PowerShell:

```powershell
$dir = "C:\Users\tyrig\Documents\progetti claude\CHIAVI PRIVATE\SIGLA"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
explorer $dir
```

(In ogni nuova finestra di PowerShell rieseguire la prima riga per avere `$dir`.)

## Passo 1 · Token GitHub (serve per pubblicare in DMReleases e salvare la chiave)

1. Aprire https://github.com/settings/personal-access-tokens/new (loggati come **Layaris**).
2. Compilare:
   - **Token name:** `Sigla pubblicazione`
   - **Expiration:** la durata più lunga disponibile (es. 366 giorni). Annotare la data di scadenza.
   - **Resource owner:** `Layaris`
   - **Repository access:** *Only select repositories* › **Layaris/SIGLAPDF** e **Layaris/DMReleases**
3. **Permissions › Repository permissions**:
   - **Contents:** *Read and write*
   - **Secrets:** *Read and write*
   - (Metadata diventa *Read-only* da solo: va bene)
4. **Generate token** › copiare il token (inizia con `github_pat_`; si vede una volta sola).
5. Salvarlo subito nel file, in PowerShell (il token è negli appunti):

```powershell
Get-Clipboard | Set-Content -Path "$dir\github-token-DMRELEASES.txt" -NoNewline -Encoding ascii
```

6. Aprire https://github.com/Layaris/SIGLAPDF/settings/secrets/actions/new
   - **Name:** `DMRELEASES_TOKEN`
   - **Secret:** incollare il token › **Add secret**

## Passo 2 · Password della chiave di firma Android

1. Generarla e salvarla in PowerShell (32 caratteri casuali, solo lettere e numeri):

```powershell
$b = New-Object byte[] 48
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
$pw = ([Convert]::ToBase64String($b) -replace '[^A-Za-z0-9]','').Substring(0,32)
Set-Content -Path "$dir\android-keystore-password.txt" -Value $pw -NoNewline -Encoding ascii
$pw | Set-Clipboard
Remove-Variable pw, b
```

2. Aprire https://github.com/Layaris/SIGLAPDF/settings/secrets/actions/new
   - **Name:** `ANDROID_KEYSTORE_PASSWORD`
   - **Secret:** incollare (è negli appunti) › **Add secret**

## Passo 3 · Creare la chiave di firma e salvarla

1. Aprire https://github.com/Layaris/SIGLAPDF/actions/workflows/keystore.yml
   › **Run workflow** › lasciare *Sostituisci* **spento** › **Run workflow**.
2. Aspettare circa 1 minuto e aprire l'esecuzione (deve avere la spunta verde).
   Se è rossa: aprire il passo fallito e riferire a Claude il messaggio di errore.
3. In fondo alla pagina, sezione **Artifacts**, scaricare **sigla-chiave-backup**
   (finisce in `Download` come `sigla-chiave-backup.zip`).
4. Estrarre la chiave nella cartella e togliere lo zip:

```powershell
Expand-Archive -Path "$env:USERPROFILE\Downloads\sigla-chiave-backup.zip" -DestinationPath $dir -Force
Remove-Item "$env:USERPROFILE\Downloads\sigla-chiave-backup.zip"
Get-ChildItem $dir
```

   Deve comparire `sigla-release.jks`.
5. Tornare nella pagina dell'esecuzione e **cancellare l'artifact** (icona del cestino accanto a
   *sigla-chiave-backup*): il repository è pubblico, così il file non resta online.

> **Molto importante:** `sigla-release.jks` + `android-keystore-password.txt` servono **per sempre**.
> Se si perdono, gli aggiornamenti dell'APK non si installano più sopra l'app già installata.
> Fare una copia della cartella `SIGLA` anche fuori dal PC (chiavetta o cloud personale).

## Passo 4 · Cloudflare (web app pubblicata in automatico)

Se nella cartella `CHIAVI PRIVATE` c'è già un token Cloudflare di un altro progetto (Multifolio,
PackSnap) con il permesso **Cloudflare Pages › Edit**, si può riusare: copiarlo anche in `SIGLA` e
saltare al punto 4.

1. Accedere a https://dash.cloudflare.com (stesso account delle altre app).
2. Aprire https://dash.cloudflare.com/profile/api-tokens › **Create Token** › in fondo
   **Custom token › Get started**:
   - **Token name:** `Sigla GitHub`
   - **Permissions:** `Account` · `Cloudflare Pages` · `Edit`
   - **Account Resources:** `Include` · il proprio account
   - **Continue to summary** › **Create Token** › copiare il token.
3. Salvarlo:

```powershell
Get-Clipboard | Set-Content -Path "$dir\cloudflare-api-token.txt" -NoNewline -Encoding ascii
```

4. **Account ID**: è il codice di 32 caratteri nell'indirizzo del browser dopo
   `dash.cloudflare.com/` (oppure in **Workers & Pages**, colonna a destra, *Account ID* › copia).
   Salvarlo:

```powershell
Get-Clipboard | Set-Content -Path "$dir\cloudflare-account-id.txt" -NoNewline -Encoding ascii
```

5. In https://github.com/Layaris/SIGLAPDF/settings/secrets/actions/new creare due secret:
   - `CLOUDFLARE_API_TOKEN` = il token
   - `CLOUDFLARE_ACCOUNT_ID` = l'account ID

Il progetto `dmsigla` su Cloudflare **non** va creato a mano: lo crea il workflow.

## Passo 5 · Promemoria nella cartella

```powershell
@"
SIGLA - chiavi private (NON condividere, NON mettere su GitHub)

android-keystore-password.txt  password della chiave di firma Android (per sempre)
sigla-release.jks              chiave di firma Android, alias "sigla" (per sempre)
github-token-DMRELEASES.txt    token GitHub "Sigla pubblicazione" (scade: ANNOTARE LA DATA)
cloudflare-api-token.txt       token Cloudflare "Sigla GitHub" (Pages Edit)
cloudflare-account-id.txt      ID account Cloudflare

Secret su github.com/Layaris/SIGLAPDF: DMRELEASES_TOKEN, ANDROID_KEYSTORE_PASSWORD,
ANDROID_KEYSTORE_BASE64, ANDROID_KEY_PASSWORD, ANDROID_KEY_ALIAS,
CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID
Quando il token GitHub scade: crearne uno nuovo (passo 1) e aggiornare il secret DMRELEASES_TOKEN.
"@ | Set-Content -Path "$dir\LEGGIMI.txt" -Encoding utf8
```

## Passo 6 · Controllo

In https://github.com/Layaris/SIGLAPDF/settings/secrets/actions devono esserci **7 secret**:
`DMRELEASES_TOKEN`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`.

Nella cartella `SIGLA` devono esserci 6 file: i 5 del promemoria più `LEGGIMI.txt`.

Poi scrivere a Claude **"fatto"**: Claude avvia la pubblicazione dell'APK e della web app e corregge
eventuali errori.

---

## Dopo: come si pubblica

- **APK su DMReleases** (a mano, quando si vuole una nuova versione):
  https://github.com/Layaris/SIGLAPDF/actions/workflows/release.yml › **Run workflow** › **APK**
  acceso, **IPA** spento › **Run workflow**. In 10–15 minuti l'APK è in
  https://github.com/Layaris/DMReleases/releases come **Sigla · build N**. Le app già installate
  mostrano l'avviso di nuova versione; l'aggiornamento si installa sopra e i dati restano.
- **Web app**: si aggiorna **da sola** a ogni modifica del codice dell'app. Per rifarla a mano:
  https://github.com/Layaris/SIGLAPDF/actions/workflows/web.yml › **Run workflow**.
  Indirizzo: https://dmsigla.pages.dev

## Nota: repository pubblico

Layaris/SIGLAPDF è **pubblico**: chiunque può leggere il codice e, da loggato, scaricare gli
artifact delle Actions. Per questo la chiave va scaricata e l'artifact cancellato (passo 3), e la
password è lunga. Sui repository pubblici i minuti delle Actions sono gratuiti.
