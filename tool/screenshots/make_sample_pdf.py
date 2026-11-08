"""Crea modulo-esempio.pdf: un modulo di iscrizione inventato, usato per gli screenshot.

Uso: python3 tool/screenshots/make_sample_pdf.py
Tutti i nomi e i dati sono di fantasia.
"""
import pathlib

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen import canvas

OUT = pathlib.Path(__file__).with_name('modulo-esempio.pdf')
W, H = A4
INK = HexColor('#1B2A4A')
GREY = HexColor('#5A6478')
BLUE = HexColor('#2347D9')


POS = {}  # punti utili per gli screenshot, in frazioni della pagina (origine in alto a sinistra)


def mark(name, page, x0, x1, baseline, size=11):
    POS[name] = {'page': page, 'x': (x0 + x1) / 2 / W, 'y': (H - baseline - size * 0.35) / H, 'w': (x1 - x0) / W}


def field(c, x, y, label, width):
    c.setFont('Helvetica', 11)
    c.setFillColor(INK)
    c.drawString(x, y, label)
    lx = x + c.stringWidth(label, 'Helvetica', 11) + 6
    c.drawString(lx, y, '_' * int((width - (lx - x)) / c.stringWidth('_', 'Helvetica', 11)))


def box_choice(c, x, y, label, options):
    c.setFont('Helvetica', 11)
    c.setFillColor(INK)
    c.drawString(x, y, label)
    cx = x + c.stringWidth(label, 'Helvetica', 11) + 14
    for opt in options:
        mark(f'opt-{opt}', 1, cx - 3, cx + c.stringWidth(opt + ' [   ]', 'Helvetica', 11) + 3, y)
        c.drawString(cx, y, opt)
        cx += c.stringWidth(opt, 'Helvetica', 11) + 6
        c.drawString(cx, y, '[   ]')
        cx += c.stringWidth('[   ]', 'Helvetica', 11) + 22


c = canvas.Canvas(str(OUT), pagesize=A4)
c.setTitle('Modulo di iscrizione (esempio)')

# Pagina 1
c.setFillColor(BLUE)
c.rect(0, H - 8, W, 8, stroke=0, fill=1)
c.setFillColor(INK)
c.setFont('Helvetica-Bold', 18)
c.drawString(56, H - 70, 'Circolo Culturale Il Melograno')
c.setFont('Helvetica', 11)
c.setFillColor(GREY)
c.drawString(56, H - 88, 'Via dei Tigli 12, 40100 Bologna  ·  esempio di modulo (dati di fantasia)')
c.setFillColor(INK)
c.setFont('Helvetica-Bold', 14)
c.drawString(56, H - 130, "Domanda di iscrizione per l'anno 2027")

y = H - 175
x, wl = 56, W - 112
field(c, x, y, 'Nome:', wl / 2 - 10)
field(c, x + wl / 2 + 10, y, 'Cognome:', wl / 2 - 10)
y -= 34
field(c, x, y, 'Nato/a a', wl * 0.62)
field(c, x + wl * 0.62 + 10, y, 'il', wl * 0.38 - 10)
y -= 34
field(c, x, y, 'Codice fiscale:', wl)
y -= 34
field(c, x, y, 'Residente in', wl * 0.62)
field(c, x + wl * 0.62 + 10, y, 'CAP', wl * 0.38 - 10)
y -= 34
field(c, x, y, 'Via', wl)
y -= 34
field(c, x, y, 'Telefono:', wl / 2 - 10)
field(c, x + wl / 2 + 10, y, 'Email:', wl / 2 - 10)
y -= 40
box_choice(c, x, y, 'Sesso', ['M', 'F'])
y -= 30
box_choice(c, x, y, 'Desidero ricevere la newsletter', ['Sì', 'No'])

y -= 44
c.setFont('Helvetica', 10)
c.setFillColor(GREY)
for line in [
    'Il/la sottoscritto/a chiede di essere iscritto/a al Circolo per l\'anno indicato e dichiara di aver',
    'letto il regolamento allegato (pagina 2). La quota annuale è di 25 euro.',
]:
    c.drawString(x, y, line)
    if 'quota' in line:
        pre = line[:line.index('La quota')]
        x0 = x + c.stringWidth(pre, 'Helvetica', 10)
        mark('quota', 1, x0, x0 + c.stringWidth(line[len(pre):], 'Helvetica', 10), y, 10)
    y -= 15

y -= 30
field(c, x, y, 'Luogo e data', wl * 0.48)
c.setFont('Helvetica', 11)
c.setFillColor(INK)
c.drawString(x + wl * 0.56, y, 'Firma')
c.line(x + wl * 0.56 + 36, y - 2, x + wl, y - 2)
c.showPage()

# Pagina 2
c.setFillColor(BLUE)
c.rect(0, H - 8, W, 8, stroke=0, fill=1)
c.setFillColor(INK)
c.setFont('Helvetica-Bold', 14)
c.drawString(56, H - 70, 'Regolamento del Circolo (estratto)')
c.setFont('Helvetica', 10.5)
y = H - 100
for i, art in enumerate([
    'Le attività si svolgono nella sede del Circolo dal lunedì al sabato.',
    'La tessera è personale e va mostrata all\'ingresso degli eventi.',
    'La quota non è rimborsabile in caso di recesso.',
    'I soci possono proporre attività e laboratori al consiglio direttivo.',
    'I dati personali sono trattati solo per la gestione delle iscrizioni.',
], start=1):
    c.drawString(56, y, f'Art. {i}. {art}')
    y -= 22
y -= 30
c.drawString(56, y, 'Firma per accettazione del regolamento')
c.line(270, y - 2, W - 56, y - 2)
mark('riga-firma-p2', 2, 270, W - 56, y - 2 + 11 * 0.35)  # la riga stessa
c.showPage()
c.save()
OUT.with_name('posizioni.json').write_text(__import__('json').dumps(POS, indent=1))
print('Creato', OUT)
