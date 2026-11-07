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
- ⬜ Rifinitura grafica e accessibilità
- ⬜ Test completi
- ⬜ Build web; workflow GitHub per APK e IPA pubblicati su DMReleases

## Idee future
- Documenti recenti
- Font aggiuntivi per la firma scritta
- "Apri con" su iOS (share extension e tipi documento)
- pdf.js incluso nella web app per il render offline
