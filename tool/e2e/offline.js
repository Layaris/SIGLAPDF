// Prova end-to-end: la web app installata si apre anche senza internet o con il server che non risponde.
//
// Uso (dopo tool/build_web.sh):
//   node tool/e2e/offline.js [cartella-build]          (in CI: dentro tool/e2e dopo npm install)
//   NODE_PATH=$(npm root -g) node tool/e2e/offline.js   (nel container, Playwright globale)
//
// Passi: 1) prima apertura con la rete, profilo compilato, service worker attivo e file salvati;
// 2) rete spenta: si ricarica, l'app si apre con i dati e apre un PDF (pdf.js dalla copia);
// 3) dati cambiati senza rete restano dopo un altro ricaricamento;
// 4) rete "appesa" (nessuna risposta) e server che risponde 500: l'app si apre lo stesso, in fretta;
// 5) versione nuova: si installa in sottofondo e si attiva intera;
// 6) in tutto il percorso nessuna richiesta ad altri siti.
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const L = require('../screenshots/lib');

const ROOT = path.resolve(process.argv[2] || path.join(__dirname, '../../build/web'));
const PDF = path.join(__dirname, '../screenshots/modulo-esempio.pdf');
const PORT = 8790;
const URL = `http://localhost:${PORT}/`;
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.otf': 'font/otf', '.ttf': 'font/ttf', '.frag': 'application/octet-stream' };

// Modo del server di prova: 'ok', 'hang' (non risponde mai, come una rete appesa) o '500'.
let mode = 'ok';
let newBuild = null;
const hanging = [];
function setMode(m) {
  mode = m;
  // Le connessioni rimaste appese si chiudono, altrimenti occupano i posti del browser per questo sito.
  if (m !== 'hang') hanging.splice(0).forEach((r) => r.destroy());
}
function serve() {
  return http.createServer((req, res) => {
    if (mode === 'hang') { hanging.push(req.socket); return; } // nessuna risposta
    if (mode === '500') { res.writeHead(500); res.end('errore'); return; }
    let rel = decodeURIComponent(new globalThis.URL(req.url, URL).pathname);
    if (rel.endsWith('/')) rel += 'index.html';
    const file = path.join(ROOT, rel);
    if (rel === '/sigla_sw.js' && newBuild) {
      // Versione nuova pubblicata: stesso service worker con un altro numero di build.
      res.writeHead(200, { 'content-type': 'text/javascript', 'cache-control': 'no-cache' });
      res.end(fs.readFileSync(file, 'utf8').replace(/const BUILD = "[^"]*";/, `const BUILD = "${newBuild}";`));
      return;
    }
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-cache' });
    fs.createReadStream(file).pipe(res);
  }).listen(PORT);
}

function check(cond, msg) {
  if (!cond) throw new Error('PROVA FALLITA: ' + msg);
  console.log('✓', msg);
}

// Vero se il testo compare nell'albero di accessibilità (etichette, testo, valori dei campi).
async function hasText(p, text, ms = 10000) {
  for (let t = 0; t < ms; t += 500) {
    const ok = await p.evaluate((text) => [...document.querySelectorAll('flt-semantics, input, textarea')].some((e) =>
      (e.getAttribute('aria-label') || '').includes(text) || (e.textContent || '').includes(text) || (e.value || '').includes(text)), text);
    if (ok) return true;
    await p.waitForTimeout(500);
  }
  return false;
}

async function appOpen(p, ms = 20000) {
  // Aperta = la barra di navigazione è nell'albero di accessibilità. L'albero si accende toccando il
  // segnaposto di Flutter, che compare solo quando l'app è partita: si riprova finché serve.
  const end = Date.now() + ms;
  while (Date.now() < end) {
    await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click()).catch(() => {});
    if (await hasText(p, 'Documenti', 500)) return;
    await p.waitForTimeout(300);
  }
  throw new Error("l'app non si è aperta entro " + ms + ' ms');
}

(async () => {
  check(fs.existsSync(path.join(ROOT, 'sigla_sw.js')), 'build con il service worker (' + ROOT + ')');
  const sw = fs.readFileSync(path.join(ROOT, 'sigla_sw.js'), 'utf8');
  check(!sw.includes('__BUILD__') && !sw.includes('__PRECACHE__'), 'service worker con numero di build ed elenco dei file');
  const server = serve();
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, serviceWorkers: 'allow' });
  const external = [];
  ctx.on('request', (r) => { if (!r.url().startsWith(URL) && !r.url().startsWith('data:') && !r.url().startsWith('blob:')) external.push(r.url()); });
  const p = await ctx.newPage();
  p.on('pageerror', (e) => console.log('Errore nella pagina:', e.message));
  p.on('filechooser', async (c) => { await c.setFiles(PDF); });

  try {
    // 1) Prima apertura con la rete
    await p.goto(URL);
    await appOpen(p, 60000);
    await L.tap(p, 'Profilo', { exact: true });
    await L.typeInto(p, 'Nome', 'Giulia');
    await L.typeInto(p, 'Città', 'Bologna');
    await p.waitForTimeout(800);
    await p.evaluate(() => navigator.serviceWorker.ready);
    // Il motore grafico si salva alla prima apertura: si aspetta che la copia sia completa.
    const cached = await p.evaluate(async () => {
      for (let i = 0; i < 40; i++) {
        const keys = await caches.keys();
        const k = keys.find((x) => x.startsWith('sigla-app-'));
        if (k) {
          const urls = (await (await caches.open(k)).keys()).map((r) => new URL(r.url).pathname);
          if (urls.some((u) => u.endsWith('.wasm')) && urls.includes('/pdfjs/pdf.worker.min.mjs')) return { k, urls };
        }
        await new Promise((r) => setTimeout(r, 500));
      }
      return null;
    });
    check(cached, 'copia sul dispositivo con app, motore grafico (wasm) e pdf.js');
    check(cached.urls.includes('/main.dart.js') && cached.urls.includes('/'), 'copia con main.dart.js e pagina iniziale');
    check(!cached.urls.some((u) => u.includes('version.json')), 'version.json non salvato');

    // 2) Senza rete: si apre con i dati e apre un PDF
    await ctx.setOffline(true);
    const t0 = Date.now();
    await p.reload();
    await appOpen(p);
    console.log(`  aperta senza rete in ${Date.now() - t0} ms`);
    await L.tap(p, 'Profilo', { exact: true });
    // I valori dei campi sono disegnati, non nell'albero: si controllano nome e conteggio nella scheda in alto.
    check(await hasText(p, 'Giulia') && await hasText(p, '2 di 13 dati compilati'), 'senza rete il profilo salvato è lì (nome e città)');
    await L.tap(p, 'Documenti', { exact: true });
    await L.tap(p, 'Apri PDF', { wait: 4500 });
    check(await hasText(p, 'Pagina 1 di', 15000), 'senza rete un PDF si apre (pdf.js dalla copia)');
    await L.tap(p, 'Indietro', { wait: 1500 }).catch(async () => { await p.mouse.click(28, 30); await p.waitForTimeout(1500); });

    // 3) Modifica fatta senza rete: resta sul dispositivo
    await L.tap(p, 'Profilo', { exact: true });
    await L.typeInto(p, 'Telefono', '333 000 1111');
    await p.waitForTimeout(800);
    await p.reload();
    await appOpen(p);
    await L.tap(p, 'Profilo', { exact: true });
    check(await hasText(p, '3 di 13 dati compilati'), 'modifica fatta senza rete ancora presente dopo il ricaricamento');
    await ctx.setOffline(false);

    // 4a) Rete appesa: il server non risponde mai (le route di Playwright scavalcherebbero il service worker)
    setMode('hang');
    let t = Date.now();
    await p.reload({ waitUntil: 'commit' });
    await appOpen(p, 15000);
    const hung = Date.now() - t;
    check(hung < 15000, `con la rete appesa si apre lo stesso (${hung} ms)`);

    // 4b) Server che risponde 500
    setMode('500');
    t = Date.now();
    await p.reload();
    await appOpen(p, 15000);
    check(true, `con il server in errore (500) si apre lo stesso (${Date.now() - t} ms)`);
    setMode('ok');

    // 5) Versione nuova: si scarica in sottofondo e si attiva tutta insieme (copia nuova, vecchia tolta)
    newBuild = 'e2e-nuova';
    await p.reload();
    await appOpen(p);
    let keys = [];
    for (let i = 0; i < 40; i++) {
      keys = await p.evaluate(() => caches.keys()).catch(() => []);
      if (keys.length === 1 && keys[0] === 'sigla-app-e2e-nuova') break;
      await p.waitForTimeout(500);
    }
    check(keys.length === 1 && keys[0] === 'sigla-app-e2e-nuova', 'versione nuova attivata, copia vecchia cancellata (' + keys.join(', ') + ')');
    await appOpen(p);
    check(await hasText(p, 'Documenti'), "dopo l'aggiornamento l'app è aperta");

    // 6) Nessuna richiesta ad altri siti
    check(external.length === 0, 'nessuna richiesta ad altri siti' + (external.length ? ': ' + external.slice(0, 5).join(', ') : ''));
    console.log('Tutte le prove offline superate.');
  } catch (e) {
    await p.screenshot({ path: path.join(__dirname, 'errore-offline.png') }).catch(() => {});
    console.error(e.message || e);
    process.exitCode = 1;
  } finally {
    await browser.close();
    server.close();
  }
})();
