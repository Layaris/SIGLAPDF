"""Copia gli screenshot in Layaris/DMReleases (sigla/grafica/screenshot e docs/assets/sigla/screenshot).

Uso: python3 tool/screenshots/copy_to_dmreleases.py <cartella-screenshot> <cartella-DMReleases>
Telefono: 540 px di larghezza. Computer: ridotti a 1280x800. PNG ottimizzati.
"""
import pathlib
import sys

from PIL import Image

src, dm = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
targets = [dm / 'sigla' / 'grafica' / 'screenshot', dm / 'docs' / 'assets' / 'sigla' / 'screenshot']
for t in targets:
    t.mkdir(parents=True, exist_ok=True)
for f in sorted(src.glob('*.png')):
    if f.name.startswith(('debug', 'errore')):
        continue
    im = Image.open(f).convert('RGB')
    size = (1280, 800) if f.name.startswith('computer-') else (540, round(im.height * 540 / im.width))
    if im.size != size:
        im = im.resize(size, Image.LANCZOS)
    for t in targets:
        im.save(t / f.name, optimize=True)
    print('✓', f.name, size)
