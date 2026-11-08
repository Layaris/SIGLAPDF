# Preparare la prima pubblicazione (una volta sola, solo dal sito di GitHub)

Non serve installare niente: si fa tutto dal browser, con l'account **Layaris**.
Alla fine GitHub avrà i "secret" che servono al workflow **Pubblica** per creare l'APK firmato
e pubblicarlo su Layaris/DMReleases. L'IPA per iPhone per ora non si fa.

## Passo 1 · Creare un token di accesso

1. Aprire https://github.com/settings/personal-access-tokens/new
2. Compilare:
   - **Token name:** `Sigla pubblicazione`
   - **Expiration:** la durata più lunga disponibile (es. 1 anno). Alla scadenza si rifà da qui.
   - **Resource owner:** `Layaris`
   - **Repository access:** *Only select repositories* › scegliere **Layaris/SIGLAPDF** e **Layaris/DMReleases**
3. In **Permissions › Repository permissions** impostare:
   - **Contents:** *Read and write*
   - **Secrets:** *Read and write*
   - (Metadata diventa *Read-only* da solo: va bene)
4. Premere **Generate token** e **copiare** il token (inizia con `github_pat_`).
   Si vede una volta sola: se si perde, se ne crea un altro.

## Passo 2 · Salvare il token come secret

1. Aprire https://github.com/Layaris/SIGLAPDF/settings/secrets/actions/new
2. **Name:** `DMRELEASES_TOKEN`
3. **Secret:** incollare il token
4. Premere **Add secret**

## Passo 3 · Scegliere la password della chiave di firma

1. Generare una password di **almeno 20 caratteri**, solo lettere e numeri (per esempio con il
   gestore di password del browser o del telefono).
2. **Salvarla subito** nel gestore di password con il nome `Sigla - chiave Android`.
3. Aprire di nuovo https://github.com/Layaris/SIGLAPDF/settings/secrets/actions/new
4. **Name:** `ANDROID_KEYSTORE_PASSWORD` · **Secret:** la password · **Add secret**

## Passo 4 · Creare la chiave (la avvia Claude, oppure a mano)

A mano: https://github.com/Layaris/SIGLAPDF/actions/workflows/keystore.yml › **Run workflow** ›
lasciare *Sostituisci* spento › **Run workflow**. Dura circa un minuto.

Poi, nella pagina dell'esecuzione finita (spunta verde), in fondo alla sezione **Artifacts**,
scaricare **sigla-chiave-backup** e conservare lo zip insieme alla password (chiavetta, cloud
personale). Resta scaricabile per 1 giorno.

> **Molto importante:** chiave + password servono per sempre. Se si perdono, gli aggiornamenti
> futuri non si potranno installare sopra l'app già installata.

## Passo 5 · Controllo

In https://github.com/Layaris/SIGLAPDF/settings/secrets/actions devono esserci 5 secret:
`DMRELEASES_TOKEN`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS` (gli ultimi tre li crea il passo 4).

## Passo 6 · Pubblicare (lo avvia Claude, oppure a mano)

https://github.com/Layaris/SIGLAPDF/actions/workflows/release.yml › **Run workflow** › lasciare
**APK** acceso e **IPA** spento › **Run workflow**. Dura circa 10–15 minuti. Alla fine l'APK è in
https://github.com/Layaris/DMReleases/releases con il nome **Sigla · build N**.

## Web app online (facoltativo, una volta sola)

1. Aprire https://github.com/Layaris/SIGLAPDF/settings/pages
2. In **Build and deployment › Source** scegliere **GitHub Actions** (si salva da solo).
3. Avviare https://github.com/Layaris/SIGLAPDF/actions/workflows/web.yml › **Run workflow**
   (oppure chiedere a Claude). Dopo 3–5 minuti la web app è su https://layaris.github.io/SIGLAPDF/

Per aggiornarla basta rilanciare lo stesso workflow.

## Nota: repository pubblico

Layaris/SIGLAPDF è **pubblico**: chiunque può leggere il codice e scaricare gli artifact delle
Actions. Per questo la password della chiave deve essere lunga. Se preferisci renderlo privato:
*Settings › General › Danger Zone › Change visibility*. Attenzione: sui repository privati i minuti
delle Actions sono limitati dal piano GitHub, sui pubblici sono gratuiti.
