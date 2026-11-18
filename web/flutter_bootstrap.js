{{flutter_js}}
{{flutter_build_config}}
// Avvio senza il service worker di Flutter (deprecato): la web app usa solo sigla_sw.js,
// registrato in index.html. Due service worker sullo stesso sito si sostituirebbero a vicenda.
_flutter.loader.load();
