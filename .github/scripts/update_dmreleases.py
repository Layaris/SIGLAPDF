"""Aggiorna i file di Sigla in Layaris/DMReleases dopo una pubblicazione.

- sigla/latest.json e docs/sigla/latest.json (letti dall'app e dal sito)
- sigla/CHANGELOG.md: la sezione "Prossima versione" diventa "build N"
- README.md: blocco <!-- sigla:latest --> con il link all'ultima versione
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
a = p.parse_args()

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

changelog = root / 'sigla' / 'CHANGELOG.md'
if changelog.exists():
    c = changelog.read_text(encoding='utf-8')
    heading = '## Prossima versione (in preparazione)'
    if heading in c:
        c = c.replace(heading, f'## build-{a.build} · {data_it}', 1)
        c = c.replace('<!-- changelog:next -->', f'<!-- changelog:next -->\n\n{heading}\n\n- Nessuna novità per ora', 1)
        changelog.write_text(c, encoding='utf-8')

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
