#!/usr/bin/env bash
# Costruisce la web app pronta da pubblicare, in build/web (usato anche da .github/workflows/web.yml).
#  1. flutter build web (pdf.js e font inclusi, niente CDN);
#  2. scrive nel service worker il numero di build e l'elenco dei file da salvare subito sul
#     dispositivo (pdf.js compreso, che si carica solo aprendo un PDF);
#  3. controlla che non restino segnaposti.
# Il motore grafico (canvaskit) non è nell'elenco: il browser ne usa una sola variante e la salva
# alla prima apertura.
#
# Uso: tool/build_web.sh [NUMERO_DI_BUILD]   (senza numero: data e ora)
set -euo pipefail
cd "$(dirname "$0")/.."

build=${1:-$(date -u +%Y%m%d%H%M)}
if ! [[ "$build" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "Numero di build non valido: $build" >&2
  exit 1
fi
version=$(grep '^version:' pubspec.yaml | sed -E 's/version: *([^+]+).*/\1/')

flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --base-href / \
  --dart-define=APP_VERSION="$version" --dart-define=APP_BUILD="web-$build"

python3 - "$build" <<'PY'
import json, pathlib, sys
build = sys.argv[1]
web = pathlib.Path('build/web')
skip_dirs = ('canvaskit/',)
skip = {'sigla_sw.js', 'flutter_service_worker.js', 'version.json', '_headers', 'index.html'}
files = ['./']
for f in sorted(web.rglob('*')):
    rel = f.relative_to(web).as_posix()
    if f.is_dir() or rel in skip or rel.startswith(skip_dirs) or rel.endswith(('.symbols', '.map')) \
            or rel.startswith('_') or rel == 'assets/NOTICES':
        continue
    files.append(rel)
sw = web / 'sigla_sw.js'
text = sw.read_text()
for a, b in [("const BUILD = '__BUILD__';", f"const BUILD = {json.dumps(build)};"),
             ('const PRECACHE = __PRECACHE__;', f'const PRECACHE = {json.dumps(files, indent=2)};')]:
    if text.count(a) != 1:
        sys.exit(f'Segnaposto non trovato una volta sola in sigla_sw.js: {a}')
    text = text.replace(a, b)
sw.write_text(text)
print(f'Service worker: build {build}, {len(files)} file salvati subito')
PY

if grep -q "__BUILD__\|__PRECACHE__" build/web/sigla_sw.js; then
  echo "Errore: in build/web/sigla_sw.js è rimasto un segnaposto" >&2
  exit 1
fi
if command -v node > /dev/null && ! node --check build/web/sigla_sw.js; then
  echo "Errore: build/web/sigla_sw.js non è JavaScript valido" >&2
  exit 1
fi
echo "Web app pronta in build/web (build $build)."
