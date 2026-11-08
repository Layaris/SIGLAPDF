// Piccoli aiuti per pilotare la web app Flutter con Playwright tramite l'albero di accessibilità.
const sem = (p) => p.locator('flt-semantics');
async function enableSemantics(p) {
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
}
// Tocca il centro di un elemento (i clic "veri" di Playwright vengono intercettati dai nodi sopra).
async function tapLoc(p, loc, wait = 900) {
  await loc.first().waitFor({ state: 'attached', timeout: 15000 });
  // Non usare scrollIntoView: sposterebbe solo l'albero di accessibilità, non la pagina disegnata.
  const vp = p.viewportSize();
  let b;
  for (let i = 0; i < 12; i++) {
    b = await loc.first().boundingBox();
    if (!b) throw new Error('elemento senza posizione');
    const cy = b.y + b.height / 2;
    if (cy > 70 && cy < vp.height - 100) break;
    await p.mouse.move(vp.width / 2, vp.height / 2);
    await p.mouse.wheel(0, cy - vp.height / 2);
    await p.waitForTimeout(500);
  }
  await p.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
  await p.waitForTimeout(wait);
}
// Tocca l'elemento con quell'etichetta (aria-label) o, in mancanza, con quel testo visibile.
async function tap(p, name, opts = {}) {
  const exact = opts.exact ?? false;
  const vp = p.viewportSize();
  const find = () => p.evaluate(([name, exact, nth]) => {
    const m = (t) => { t = (t || '').trim(); return exact ? t === name : (t === name || t.startsWith(name)); };
    const ok = (e) => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
    const els = [...document.querySelectorAll('flt-semantics')].filter(ok);
    let hits = els.filter((e) => m(e.getAttribute('aria-label')));
    if (!hits.length) hits = els.filter((e) => m(e.textContent) && ![...e.children].some((c) => c.tagName === 'FLT-SEMANTICS' && m(c.textContent)));
    const e = hits[nth]; if (!e) return null;
    const r = e.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }, [name, exact, opts.nth ?? 0]);
  let c = null;
  for (let i = 0; i < 30 && !c; i++) { c = await find(); if (!c) await p.waitForTimeout(500); }
  if (!c) throw new Error('non trovato: ' + name);
  for (let i = 0; i < 12 && (c.y < 70 || c.y > vp.height - 100); i++) {
    await p.mouse.move(vp.width / 2, vp.height / 2); await p.mouse.wheel(0, c.y - vp.height / 2); await p.waitForTimeout(500);
    c = await find(); if (!c) throw new Error('perso: ' + name);
  }
  await p.mouse.click(c.x, c.y);
  await p.waitForTimeout(opts.wait ?? 900);
}
async function dump(p, tag) {
  const l = await p.evaluate(() => [...document.querySelectorAll('flt-semantics')].map(e => (e.getAttribute('role') || '') + ':' + (e.getAttribute('aria-label') || '').replace(/\n/g, ' | ').slice(0, 70)).filter(s => s.length > 1));
  console.log('== ' + tag + '\n' + [...new Set(l)].join('\n'));
}
async function typeInto(p, label, text) {
  const loc = p.locator(`input[aria-label="${label}"], textarea[aria-label="${label}"], flt-semantics[aria-label="${label}"]`);
  for (let i = 0; i < 8 && await loc.count() === 0; i++) {
    const vp = p.viewportSize(); await p.mouse.move(vp.width / 2, vp.height / 2); await p.mouse.wheel(0, 250); await p.waitForTimeout(500);
  }
  await tapLoc(p, loc, 300);
  await p.keyboard.press('Control+A');
  await p.keyboard.type(text, { delay: 5 });
  await p.waitForTimeout(200);
}
module.exports = { enableSemantics, tap, tapLoc, dump, typeInto };

// Disegna una firma "corsiva" inventata dentro il riquadro (x, y, w, h): anelli di cicloide + svolazzo.
async function drawSignature(p, box) {
  const cy = box.y + box.height * 0.5, x0 = box.x + box.width * 0.08, x1 = box.x + box.width * 0.9;
  const pts = [];
  const n = 260, loops = 7.5;
  for (let i = 0; i <= n; i++) {
    const t = (i / n) * loops * 2 * Math.PI;
    const amp = box.height * (0.16 + 0.1 * Math.sin(i / n * Math.PI));
    const x = x0 + (x1 - x0) * (i / n) - amp * 0.55 * Math.sin(t);
    const y = cy - amp * Math.cos(t) * (i < 40 ? 1.8 : 1) + (i / n) * box.height * 0.08;
    pts.push([x, y]);
  }
  await p.mouse.move(pts[0][0], pts[0][1]); await p.mouse.down();
  for (const [x, y] of pts) await p.mouse.move(x, y, { steps: 1 });
  await p.mouse.up();
  // Svolazzo sotto
  const u = [];
  for (let i = 0; i <= 60; i++) { const s = i / 60; u.push([x0 + (x1 - x0) * (0.05 + 0.95 * s), cy + box.height * 0.3 - Math.sin(s * Math.PI) * box.height * 0.12]); }
  await p.mouse.move(u[0][0], u[0][1]); await p.mouse.down();
  for (const [x, y] of u) await p.mouse.move(x, y, { steps: 1 });
  await p.mouse.up();
  await p.waitForTimeout(400);
}
module.exports.drawSignature = drawSignature;

// Tocca uno strumento della barra in basso dell'editor, scorrendola con un trascinamento lento.
async function toolbarTap(p, name, opts = {}) {
  const vp = p.viewportSize();
  const find = () => p.evaluate(([name, H]) => {
    const els = [...document.querySelectorAll('flt-semantics[role="button"]')].filter(e => {
      const r = e.getBoundingClientRect(); return r.top > H - 120 && (e.textContent.trim() === name || e.getAttribute('aria-label') === name);
    });
    if (!els.length) return null;
    const r = els[0].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }, [name, vp.height]);
  for (let i = 0; i < 14; i++) {
    let c = await find();
    // Non ancora nell'albero: prima torna all'inizio della barra, poi scorre a sinistra.
    if (!c) c = i < 2 ? { x: -200, y: vp.height - 40 } : { x: vp.width + 200, y: vp.height - 40 };
    if (c.x > 40 && c.x < vp.width - 40) { await p.mouse.click(c.x, c.y); await p.waitForTimeout(opts.wait ?? 900); return; }
    const dx = Math.max(-260, Math.min(260, vp.width / 2 - c.x));
    const sx = dx < 0 ? vp.width - 30 : 30;
    await p.mouse.move(sx, c.y); await p.mouse.down();
    await p.mouse.move(sx + dx, c.y, { steps: 30 }); await p.waitForTimeout(250); await p.mouse.up();
    await p.waitForTimeout(700);
  }
  throw new Error('strumento non raggiungibile: ' + name);
}
module.exports.toolbarTap = toolbarTap;

// Riquadro (x, y, w, h) del primo nodo con quell'etichetta.
async function boxOf(p, label) {
  return p.evaluate((label) => {
    const e = [...document.querySelectorAll('flt-semantics')].find(e => (e.getAttribute('aria-label') || '').startsWith(label));
    if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height };
  }, label);
}
async function drag(p, x1, y1, x2, y2) {
  await p.mouse.move(x1, y1); await p.mouse.down(); await p.mouse.move(x2, y2, { steps: 15 }); await p.mouse.up(); await p.waitForTimeout(500);
}
module.exports.boxOf = boxOf; module.exports.drag = drag;
// Sposta l'elemento con quell'etichetta finché il suo centro è su (tx, ty).
// Il trascinamento "perde" i primi pixel (soglia del gesto): la stima e la compensa.
async function moveTo(p, label, tx, ty) {
  let slop = 8;
  for (let i = 0; i < 8; i++) {
    const b = await boxOf(p, label);
    if (!b) throw new Error('elemento non trovato: ' + label);
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    const ex = tx - cx, ey = ty - cy, d = Math.hypot(ex, ey);
    if (process.env.DEBUG_SHOTS) console.log('moveTo', label, i, Math.round(cx), Math.round(cy), '->', Math.round(tx), Math.round(ty), 'soglia', slop.toFixed(1));
    if (d < 1.5) return;
    const ux = ex / d, uy = ey / d, len = d + slop;
    await p.mouse.move(cx, cy); await p.mouse.down();
    await p.mouse.move(cx + ux * len, cy + uy * len, { steps: 24 }); await p.waitForTimeout(150); await p.mouse.up();
    await p.waitForTimeout(450);
    const a = await boxOf(p, label);
    const moved = ((a.x + a.w / 2 - cx) * ux + (a.y + a.h / 2 - cy) * uy);
    if (moved > 0.5) slop = Math.max(0, Math.min(30, len - moved));
  }
}
module.exports.moveTo = moveTo;
async function scrollTop(p) {
  const vp = p.viewportSize(); await p.mouse.move(vp.width / 2, vp.height / 2); await p.mouse.wheel(0, -5000); await p.waitForTimeout(800);
}
module.exports.scrollTop = scrollTop;
