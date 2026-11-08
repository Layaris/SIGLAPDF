"""Aggiorna i file di Sigla in Layaris/DMReleases dopo una pubblicazione.

- sigla/latest.json e docs/sigla/latest.json (letti dall'app e dal sito)
- sigla/CHANGELOG.md: la sezione "Prossima versione" diventa "build N", con le novità di NOVITA.md
- README.md: blocco <!-- sigla:latest --> con il link all'ultima versione
- (facoltativo) note della release: novità + testo di sigla/release.md
- (facoltativo) NOVITA.md di SIGLAPDF: "Prossima versione" diventa "build N" e se ne apre una nuova
"""
import argparse
import datetime as dt
import json
import pathlib
import re

p = argparse.ArgumentParser()
p.add_argument('--root', required=True)
p.add_argument('--build', required=True, type=int)
p.add_argument('--version', required=True)
p.add_argument('--apk', default='')
p.add_argument('--ipa', default='')
p.add_argument('--novita', default='', help='NOVITA.md di SIGLAPDF')
p.add_argument('--release-notes-out', default='', help='dove scrivere le note della release')
a = p.parse_args()

PLACEHOLDER = 'Nessuna novità per ora'


def next_bullets(text, heading):
    """Righe "- ..." della sezione che inizia con heading (fino alla prossima "## ")."""
    if heading not in text:
        return []
    body = text.split(heading, 1)[1]
    body = body.split('\n## ', 1)[0]
    out = []
    for line in body.splitlines():
        if line.startswith('- '):
            out.append(line.rstrip())
        elif out and line.startswith('  ') and line.strip():
            out[-1] += ' ' + line.strip()  # riga a capo dello stesso punto
        elif not line.strip():
            continue
        elif out:
            out.append(None)  # testo che non fa parte dell'elenco: chiude il punto precedente
    return [l for l in out if l and PLACEHOLDER not in l]

root = pathlib.Path(a.root)
tag = f'sigla-build-{a.build}'
base = f'https://github.com/Layaris/DMReleases/releases/download/{tag}/'
today = dt.date.today().isoformat()
mesi = ['gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio', 'agosto',
        'settembre', 'ottobre', 'novembre', 'dicembre']
d = dt.date.today()
data_it = f'{d.day} {mesi[d.month - 1]} {d.year}'

latest_path = root / 'sigla' / 'latest.json'
try:
    latest = json.loads(latest_path.read_text(encoding='utf-8'))
except (FileNotFoundError, json.JSONDecodeError):
    latest = {}
latest['app'] = 'sigla'
if a.apk:
    latest.update(version=a.version, build=a.build, date=today, apk=base + a.apk)
if a.ipa:
    latest.update(ipa_version=a.version, ipa_build=a.build, ipa_date=today, ipa=base + a.ipa)
text = json.dumps(latest, ensure_ascii=False, indent=2) + '\n'
latest_path.write_text(text, encoding='utf-8')
(root / 'docs' / 'sigla' / 'latest.json').write_text(text, encoding='utf-8')

novita_path = pathlib.Path(a.novita) if a.novita else None
novita = novita_path.read_text(encoding='utf-8') if novita_path and novita_path.exists() else ''
bullets = next_bullets(novita, '## Prossima versione')

changelog = root / 'sigla' / 'CHANGELOG.md'
if changelog.exists():
    c = changelog.read_text(encoding='utf-8')
    heading = '## Prossima versione (in preparazione)'
    if heading in c:
        start = c.index(heading)
        end = c.find('\n## ', start + len(heading))
        end = len(c) if end < 0 else end
        # Testo già scritto in DMReleases (senza il segnaposto) + novità di NOVITA.md non ancora presenti.
        lines = [l for l in c[start + len(heading):end].strip().splitlines() if PLACEHOLDER not in l]
        lines += [b for b in bullets if b not in lines]
        body = '\n'.join(lines).strip() or f'- {PLACEHOLDER}'
        c = c[:start] + f'{heading}\n\n- {PLACEHOLDER}\n\n## build-{a.build} · {data_it}\n\n{body}\n' + c[end:]
        changelog.write_text(c, encoding='utf-8')
        bullets = [l for l in lines if l.startswith('- ')]

if a.release_notes_out:
    base_notes = (root / 'sigla' / 'release.md').read_text(encoding='utf-8')
    notes = ('### Novità\n\n' + '\n'.join(bullets) + '\n\n') if bullets else ''
    pathlib.Path(a.release_notes_out).write_text(notes + base_notes, encoding='utf-8')

if novita_path and novita and '## Prossima versione' in novita:
    n = novita.replace('## Prossima versione', f'## build-{a.build} · {data_it}', 1)
    n = n.replace('<!-- novita:next -->', f'<!-- novita:next -->\n\n## Prossima versione\n\n- {PLACEHOLDER}', 1)
    novita_path.write_text(n, encoding='utf-8')

readme = root / 'README.md'
if readme.exists():
    r = readme.read_text(encoding='utf-8')
    parti = []
    if a.apk:
        parti.append(f'[Android {a.version} (build {a.build})]({base}{a.apk})')
    if a.ipa:
        parti.append(f'[iPhone {a.version} (build {a.build})]({base}{a.ipa})')
    blocco = f'**Ultima versione:** {" · ".join(parti)} del {data_it}.'
    r = re.sub(r'(<!-- sigla:latest -->\n).*?(\n<!-- /sigla:latest -->)', lambda m: m.group(1) + blocco + m.group(2), r, flags=re.S)
    readme.write_text(r, encoding='utf-8')
print('Aggiornato', tag)
