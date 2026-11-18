# Novità di Sigla (per la prossima pubblicazione)

Qui si scrivono, in parole semplici, le novità **visibili** per chi usa l'app.
Quando si lancia *Pubblica*, la sezione "Prossima versione" va in automatico nelle note della release e
nel CHANGELOG di Layaris/DMReleases, e qui diventa "build-N".

<!-- novita:next -->

## Prossima versione

- Compilazione automatica più precisa sui moduli italiani: "Cognome e nome" nell'ordine giusto, luogo e provincia di nascita, "Luogo, data", date con le barre (__/__/____), "Cod. Fisc.", domicilio, recapito telefonico, viale/corso/piazza senza ripetere "Via"
- I campi di altre persone ("Nome del padre", "dell'alunno") e le date diverse da oggi ("Data di scadenza") non ricevono più i tuoi dati
- Riconosce i consensi privacy (Acconsento / Non acconsento) e i tuoi dati personalizzati del profilo (es. "Cittadinanza", "Patente")
- Nuovo dato nel profilo: provincia di nascita
- Moduli compilabili: provincia e sesso anche nei menu a tendina, indirizzo completo nei campi su più righe, nomi dei campi comprensibili
- Riconoscimento AI: se una pagina non riesce le altre restano, avviso oltre le 10 pagine, caselle M/F e Sì/No, messaggio chiaro se il credito è finito
- Riconoscimento AI anche con Google Gemini e NanoGPT, oltre a Claude: in automatico prova prima Gemini, poi NanoGPT, poi Claude, e se uno non risponde passa da solo al successivo. In Impostazioni la chiave e il modello di ognuno e "Prova la connessione"
- Con l'AI la compilazione è più completa: prima cerca i campi sul dispositivo (posizioni precise), poi l'AI aggiunge quelli che mancano; se l'AI non risponde restano i campi trovati
- Web app installata sul telefono o sul computer: si apre subito anche senza internet, con i tuoi dati, e apre i PDF
- Privacy: le foto dello scanner e i PDF ricevuti con "Apri con" non restano più nella memoria dell'app
- Se l'archivio del telefono non si apre, l'app parte lo stesso con un avviso (prima restava bianca)
- Disegno della firma: "Annulla" annulla anche "Cancella"
- Il simbolo € diventa "EUR" nel PDF (prima spariva), anche nell'anteprima
- Sul computer compare "PDF salvato" / "Backup salvato"; la rotellina non sposta più il documento sotto i fogli aperti
- Inglese: "Undo", "Signature", "Initials" nell'editor, plurali corretti, date dei recenti in inglese
- Schermi piccoli: i pulsanti delle impostazioni non spezzano più le parole

## build-5 · 8 novembre 2026

- Compilazione automatica: riconosce anche le caselle scritte dopo l'opzione, come "Sì [ ] No [ ]" e "M [ ] F [ ]"
- PDF esportato: firme e testi restano sopra i campi colorati del modulo (prima potevano finire coperti)
- I campi compilabili delle pagine ruotate si vedono e si toccano nell'editor
- Pagine più nitide sul computer (prima potevano restare sfocate dopo le miniature) e file più leggeri
  quando la stessa sigla è su molte pagine
- Backup: con il blocco firme attivo, esportare o sostituire chiede l'impronta o il PIN; un backup rovinato
  non cancella più i dati a metà; il blocco firme resta quello del telefono
- Firma importata da foto: funzionano anche le immagini a 16 bit; dopo un errore non si salva la foto precedente
- Modelli: se la firma predefinita è cambiata, non viene deformata
- Profilo aggiornato subito dopo un import; "Controlla ora" dice se il controllo non è riuscito
- Lingua "Sistema": l'app segue subito la lingua del telefono
