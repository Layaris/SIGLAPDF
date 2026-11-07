# Roadmap di Sigla

Legenda: ✅ fatto · 🔶 in corso · ⬜ da fare

## Fase 1 — Base
- ✅ Documentazione iniziale (CLAUDE.md, README, ROADMAP, ARCHITECTURE)
- ✅ Progetto Flutter (android, ios, web), dipendenze
- ✅ Tema chiaro/scuro "inchiostro e carta"
- ✅ Navigazione adattiva: Documenti, Firme, Profilo, Impostazioni

## Fase 2 — Firme
- ✅ Archivio locale (Hive, IndexedDB sul web)
- ✅ Libreria firme: firme e sigle, rinomina, elimina, predefinita
- ✅ Disegno a mano: Bezier, pressione, colore, spessore, undo/redo, cancella, PNG ritagliato

## Fase 3 — Import e firma scritta
- ✅ Import da immagine con scontorno (Otsu, trasparenza, bordi morbidi, ritaglio, ricolorazione)
- ✅ Anteprima con cursore della soglia
- ✅ Firma scritta con font corsivo incluso

## Fase 4 — PDF
- ✅ Apertura da file picker
- ✅ Render pagine, zoom e scorrimento
- ✅ Elementi: firma, sigla, testo, data, spunta, croce (trascina, ridimensiona, elimina)
- ✅ Sigla tutte le pagine
- ✅ Undo/redo nell'editor
- ✅ Esportazione con flatten, salva o condividi

## Fase 5 — Profilo e campi
- ✅ Profilo con campi fissi e personalizzati (salvataggio automatico)
- ✅ Inserimento rapido di un dato del profilo
- ✅ AcroForm: rilevamento, compilazione, autocompilazione
- ✅ Riconoscimento locale dei campi non segnalati con anteprima

## Fase 6 — Extra
- ✅ Riconoscimento AI opzionale (API Anthropic)
- ✅ Backup cifrato .sigla (unisci / sostituisci)
- ✅ Blocco biometrico delle firme (mobile)
- ✅ Scanner documenti (mobile) e immagini → PDF (web)
- ✅ "Apri con" / condividi su Android

## Fase 7 — Rifinitura
- ✅ Rifinitura grafica e accessibilità (icone, temi, aree di tocco ≥ 48, Semantics)
- ✅ Test completi (unit e widget) e prove end-to-end nel browser con Playwright
- ✅ Build web offline (pdf.js e CanvasKit inclusi)
- ✅ Workflow GitHub manuale per APK e IPA pubblicati su DMReleases (non ancora eseguito)
- ✅ Cartella `sigla/` e pagina del sito in DMReleases
- ⬜ Prima build APK/IPA su GitHub (verifica reale di Android e iOS)

## Fase 8 — Dopo il rilascio
- ✅ OCR sul dispositivo per i PDF scansionati (Android, Google ML Kit, offline)
- ✅ Chiave di firma creata su GitHub (workflow "Crea chiave di firma")

## Fase 9 — Grafica
- ✅ Illustrazioni (firma animata, foglio firmato), schede firme con linea, intestazione profilo

## Migliorie proposte (in ordine di utilità)
1. ⬜ **Documenti recenti**: elenco degli ultimi PDF esportati, da riaprire o ricondividere
2. ⬜ **Modelli di posizionamento**: ricordare dove si firma un modulo ricorrente e riapplicarlo
3. ⬜ **Firma con data automatica**: firma + data sotto in un solo elemento
4. ⬜ **Sigla tutte: scelta dell'angolo** (basso destra/sinistra, alto) e salto della pagina con la firma
5. ⬜ **Pinch per lo zoom** e miniature delle pagine per saltare tra le pagine
6. ⬜ **Più profili** (es. tuo e di un familiare) da scegliere in "Compila"
7. ⬜ **Riordina, ruota ed elimina pagine**, unisci più PDF
8. ⬜ **Scrittura a mano libera ed evidenziatore** sul PDF
9. ⬜ **Campi a scelta multipla** nel riconoscimento (caselle ☐ accanto a "Sì/No", "M/F")
10. ⬜ **Avviso di nuova versione** nell'app (legge `sigla/latest.json` su DMReleases)
11. ⬜ **Pubblicare la web app** (Cloudflare Pages) e linkarla da DMReleases
12. ⬜ **Chiave API nel portachiavi sicuro** (Keychain/Keystore) invece che in Hive
13. ⬜ **Font con più caratteri** per i testi nel PDF (oggi Helvetica WinAnsi)
14. ⬜ **"Apri con" su iPhone** (share extension) quando si farà l'IPA
15. ⬜ **Inglese** come seconda lingua

## Idee future
- Pubblicare la web app (es. Cloudflare Pages) e linkarla da DMReleases
- Avviso di nuova versione nell'app (legge `sigla/latest.json`)
- Chiave API nel portachiavi sicuro (Keychain/Keystore) invece che in Hive
- Font con più caratteri per i testi nel PDF (oggi Helvetica WinAnsi)
- Documenti recenti
- Font aggiuntivi per la firma scritta
- "Apri con" su iOS (share extension e tipi documento)
- pdf.js incluso nella web app per il render offline
