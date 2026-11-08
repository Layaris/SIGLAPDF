// Rifà gli screenshot di Sigla per Layaris/DMReleases (telefono e computer, chiaro e scuro).
//
// Uso (dalla cartella del progetto):
//   flutter build web --release --no-web-resources-cdn
//   (cd build/web && python3 -m http.server 8766 &)
//   python3 tool/screenshots/make_sample_pdf.py        # solo se cambi il modulo di esempio
//   NODE_PATH=$(npm root -g) node tool/screenshots/screenshots.js [cartella-uscita] [url]
//
// Scrive i PNG con i nomi usati in DMReleases (sigla/grafica/screenshot e docs/assets/sigla/screenshot).
// Tutti i dati sono di fantasia. Pilota la web app tramite l'albero di accessibilità di Flutter (lib.js).
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const L = require('./lib');

const OUT = path.resolve(process.argv[2] || 'build/screenshots');
const URL = process.argv[3] || 'http://localhost:8766/';
const PDF = path.join(__dirname, 'modulo-esempio.pdf');
const POS = JSON.parse(fs.readFileSync(path.join(__dirname, 'posizioni.json'), 'utf8'));
const PHONE = { width: 390, height: 844 };
const DSF = 540 / 390; // PNG del telefono larghi 540 px, come quelli già pubblicati

const PROFILO = {
  'Nome': 'Giulia', 'Cognome': 'Ferraresi', 'Data di nascita': '12/05/1988', 'Luogo di nascita': 'Modena',
  'Codice fiscale': 'FRRGLI88E52F257K', 'Indirizzo': 'Via delle Rose 8', 'CAP': '40121', 'Città': 'Bologna',
  'Provincia': 'BO', 'Telefono': '333 123 4567', 'Email': 'giulia@esempio.it',
};

// Punto del modulo (frazioni della pagina) in coordinate dello schermo.
async function onPage(p, key, dy = 0) {
  const pos = POS[key];
  const b = await L.boxOf(p, `Pagina ${pos.page} di`);
  if (!b) { await L.dump(p, 'pagina mancante'); await p.screenshot({ path: path.join(OUT, 'errore.png') }); throw new Error('pagina non visibile: ' + pos.page); }
  // Il nodo della pagina include un margine di 16 px ai lati e 8 px sopra e sotto, e può essere
  // tagliato dal bordo della finestra: l'altezza si ricava dalla larghezza (A4).
  const w = b.w - 32, h = w * 842 / 595;
  const top = b.y > 70 ? b.y + 8 : b.y + b.h - 8 - h;
  const pg = { x: b.x + 16, y: top, w, h };
  return { x: pg.x + pos.x * pg.w, y: pg.y + pos.y * pg.h + dy, w: pos.w * pg.w, page: pg };
}

async function shot(p, name) {
  // Mouse su una zona neutra e attesa: niente tooltip negli screenshot.
  const vp = p.viewportSize();
  await p.mouse.move(vp.width / 2, vp.height * 0.45);
  await p.waitForTimeout(1600);
  await p.screenshot({ path: path.join(OUT, name) });
  console.log('✓', name);
}

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const udata = fs.mkdtempSync(path.join(require('os').tmpdir(), 'sigla-shots-'));
  const ctx = await chromium.launchPersistentContext(udata, { viewport: PHONE, deviceScaleFactor: DSF, colorScheme: 'light', acceptDownloads: true });
  const p = ctx.pages()[0];
  p.on('pageerror', (e) => console.log('Errore nella pagina:', e.message));
  p.on('filechooser', async (c) => { await c.setFiles(PDF); });
  await p.goto(URL); await p.waitForTimeout(7000);
  await L.enableSemantics(p);

  // Profilo "Io" + un secondo profilo
  await L.tap(p, 'Profilo', { exact: true });
  for (const [k, v] of Object.entries(PROFILO)) await L.typeInto(p, k, v);
  await L.tap(p, 'F', { exact: true });
  await L.scrollTop(p);
  await L.tap(p, 'Profilo', { exact: true, nth: 0 }); // chip "+ Profilo" (la scheda in basso viene dopo)
  await p.keyboard.type('Mamma'); await p.keyboard.press('Enter'); await p.waitForTimeout(1000);
  await L.typeInto(p, 'Nome', 'Anna'); await L.typeInto(p, 'Cognome', 'Ferraresi');
  await L.scrollTop(p);
  await L.tap(p, 'Io', { exact: true });
  await L.scrollTop(p);
  await shot(p, 'telefono-profilo.png');

  // Firme: firma scritta in corsivo e sigla
  await L.tap(p, 'Firme', { exact: true });
  await L.tap(p, 'Nuova firma'); await L.tap(p, 'Scrivi');
  await L.typeInto(p, 'Nome e cognome', 'Giulia Ferraresi');
  await L.tap(p, 'Salva'); await p.keyboard.press('Enter'); await p.waitForTimeout(1200);
  await L.tap(p, 'Nuova sigla'); await L.tap(p, 'Scrivi');
  await L.typeInto(p, 'Iniziali', 'G.F.');
  await L.tap(p, 'Salva'); await p.keyboard.press('Enter'); await p.waitForTimeout(1200);
  await shot(p, 'telefono-firme.png');

  // Documento: apri, compila dal profilo
  await L.tap(p, 'Documenti', { exact: true });
  await L.tap(p, 'Apri PDF', { wait: 4500 });
  await L.toolbarTap(p, 'Compila', { wait: 3000 });
  await shot(p, 'telefono-campi-trovati.png');
  await L.tap(p, 'Inserisci', { wait: 5500 }); // aspetta che sparisca l'avviso sopra la barra

  // Evidenziatore sulla quota e cerchio a penna intorno a "Sì [ ]"
  await L.toolbarTap(p, 'Evidenzia', { wait: 1200 });
  const q = await onPage(p, 'quota');
  await L.moveTo(p, 'Evidenziatore', q.x, q.y);
  await L.toolbarTap(p, 'Fatto');
  const si = await onPage(p, 'opt-Sì'); // prima della penna: in modalità disegno la pagina non è nell'albero
  await L.toolbarTap(p, 'Penna', { wait: 800 });
  const pts = [];
  for (let k = 0; k <= 44; k++) {
    const t = -0.5 + (k / 44) * 2.2 * Math.PI;
    pts.push([si.x + si.w * 0.62 * Math.cos(t), si.y + si.page.h * 0.012 * Math.sin(t)]);
  }
  await p.mouse.move(...pts[0]); await p.mouse.down();
  for (const pt of pts) await p.mouse.move(...pt);
  await p.mouse.up(); await p.waitForTimeout(400);
  await L.toolbarTap(p, 'Fatto');
  await shot(p, 'telefono-modulo-compilato.png');

  // Pagina 2: firma con la data sulla riga "Firma per accettazione"
  await p.mouse.move(195, 400); await p.mouse.wheel(0, 420); await p.waitForTimeout(900);
  await L.toolbarTap(p, 'Firma e data', { wait: 1200 });
  const riga = await onPage(p, 'riga-firma-p2');
  const fb = await L.boxOf(p, 'Firma con data');
  // La firma occupa il 74% in alto dell'elemento, la data sta sotto la riga.
  await L.moveTo(p, 'Firma con data', riga.x, riga.y - fb.h * 0.2);
  await L.toolbarTap(p, 'Fatto');
  await shot(p, 'telefono-firma-e-data.png');

  // Computer: editor con le miniature a lato (finestra larga)
  await p.setViewportSize({ width: 1280, height: 800 }); await p.waitForTimeout(1500);
  await L.scrollTop(p);
  await shot(p, 'computer-modulo-compilato.png');
  await p.setViewportSize(PHONE); await p.waitForTimeout(1500);

  // Esporta (il PDF finisce nei Recenti) e torna ai Documenti
  await L.tap(p, 'Esporta PDF', { wait: 4000 });
  await p.keyboard.press('Escape'); await p.waitForTimeout(800);
  await L.tap(p, 'Indietro', { wait: 1500 }).catch(async () => { await p.mouse.click(28, 30); await p.waitForTimeout(1500); });
  await shot(p, 'telefono-documenti.png');
  await p.setViewportSize({ width: 1280, height: 800 }); await p.waitForTimeout(1500);
  await shot(p, 'computer-documenti.png');
  await p.setViewportSize(PHONE); await p.waitForTimeout(1500);

  // Impostazioni
  await L.tap(p, 'Impostazioni', { exact: true });
  await shot(p, 'telefono-impostazioni.png');

  // Tema scuro
  await p.emulateMedia({ colorScheme: 'dark' }); await p.waitForTimeout(1200);
  await L.tap(p, 'Firme', { exact: true });
  await shot(p, 'telefono-firme-scuro.png');
  await L.tap(p, 'Documenti', { exact: true });
  await L.scrollTop(p);
  await shot(p, 'telefono-documenti-scuro.png');

  await ctx.close();
  fs.rmSync(udata, { recursive: true, force: true });
  console.log('Screenshot in', OUT);
})().catch((e) => { console.error(e); process.exit(1); });
