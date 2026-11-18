// Service worker di Sigla: la web app installata si apre subito, anche senza internet.
//
// Flutter 3.47 non ha più un service worker suo (quello generato si cancella da solo), quindi è
// scritto a mano, come in PackSnap. Regole:
// - pagina iniziale: prima dalla rete, ma se non risponde entro 3 secondi (rete assente o "appesa")
//   dalla copia salvata;
// - file dell'app (codice, motore grafico, pdf.js, font, icone): dalla copia di QUESTA versione,
//   dalla rete solo se mancano. I nomi dei file di Flutter non hanno l'impronta, per questo la copia
//   ha nel nome il numero di build: a ogni pubblicazione questo file cambia (tool/build_web.sh scrive
//   il numero di build e l'elenco dei file nei due segnaposto qui sotto) e la versione nuova si
//   scarica tutta in sottofondo;
// - mai le richieste ad altri siti (servizi AI con la chiave dell'utente) né version.json;
// - una versione nuova si installa e ASPETTA: la attiva index.html all'apertura dopo (o subito se è
//   pronta nei primi secondi), tutta insieme, così file vecchi e nuovi non si mescolano.
const BUILD = '__BUILD__';
const CACHE = 'sigla-app-' + BUILD;
const PRECACHE = __PRECACHE__;
const PAGE_TIMEOUT_MS = 3000;

self.addEventListener('install', (event) => {
  // Niente skipWaiting qui: la nuova versione aspetta il via (vedi sopra).
  event.waitUntil(
    caches.open(CACHE).then((cache) =>
      cache.addAll(PRECACHE.map((u) => new Request(u, { cache: 'reload' }))),
    ),
  );
});

self.addEventListener('message', (event) => {
  if (event.data === 'sigla-activate') self.skipWaiting();
  // Alla primissima apertura la pagina carica il motore grafico prima che il service worker sia
  // attivo: index.html manda l'elenco dei file già usati e qui si salvano (solo di questo sito).
  if (event.data && event.data.type === 'sigla-cache' && Array.isArray(event.data.urls)) {
    event.waitUntil(caches.open(CACHE).then((cache) => Promise.all(event.data.urls.map(async (u) => {
      const url = new URL(u, self.location.href);
      if (url.origin !== self.location.origin || url.search || url.pathname.endsWith('/version.json')) return;
      if (await cache.match(url.href)) return;
      try {
        const res = await fetch(url.href);
        if (res.status === 200) await cache.put(url.href, res);
      } catch (_) {}
    }))));
  }
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(
        keys.filter((k) => k.startsWith('sigla-app-') && k !== CACHE).map((k) => caches.delete(k)),
      ))
      .then(() => self.clients.claim()),
  );
});

// Salva una copia: solo risposte complete (le parziali, 206, no).
function save(req, res) {
  if (res.status !== 200 || res.type === 'opaque') return;
  const copy = res.clone();
  caches.open(CACHE).then((cache) => cache.put(req, copy)).catch(() => {});
}

function page(event) {
  return caches.open(CACHE).then(async (cache) => {
    const saved = await cache.match('./');
    const net = fetch(event.request).then((res) => {
      if (res.status === 200) cache.put('./', res.clone()).catch(() => {});
      return res;
    });
    if (!saved) return net.catch(() => Response.error());
    // La rete ha qualche secondo; poi, se non risponde, fallisce o dà errore (es. 500), la copia.
    const timeout = new Promise((resolve) => setTimeout(() => resolve(saved), PAGE_TIMEOUT_MS));
    return Promise.race([net.then((res) => (res.ok ? res : saved), () => saved), timeout]);
  });
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // version.json e le richieste con parametri non si salvano.
  if (url.pathname.endsWith('/version.json') || url.search) return;

  if (req.mode === 'navigate') {
    event.respondWith(page(event));
    return;
  }
  event.respondWith(
    caches.match(req, { cacheName: CACHE }).then((hit) => hit || fetch(req).then((res) => {
      save(req, res);
      return res;
    })),
  );
});
