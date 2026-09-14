#!/usr/bin/env node
// Admin console UI audit — responsive + accessibility checks in a real (headless) Chrome.
// LOCAL ONLY: point it at a console served against the synthetic harness (admin/scripts/local-stack.sh).
//
//   node admin/scripts/ui-audit/audit.mjs --app http://localhost:3200 --label light --out /tmp/ui-audit
//
// Per page x viewport (390, 768, 1024, 1440): horizontal page overflow; rendered text contrast
// (WCAG 1.4.3: 4.5:1, 3:1 for large text; disabled controls exempt; text over background images
// reported for manual review); controls without an accessible name (Chrome accessibility tree);
// touch targets under 24x24 px at 390 (WCAG 2.5.8, inline text links exempt); one <main>, one <h1>,
// <html lang>. Keyboard focus: at 1440 and 390, Tab through up to 30 stops and flag any focused
// element with no outline and no box-shadow (WCAG 2.4.7). Signs in with the harness operator.
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { launchBrowser } from "./cdp.mjs";

const arg = (k, d) => {
  const i = process.argv.indexOf(`--${k}`);
  return i >= 0 ? process.argv[i + 1] : d;
};
const APP = arg("app", "http://localhost:3200");
const LABEL = arg("label", "build");
const OUT = arg("out", "/tmp/ui-audit");
const CHROME = arg("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
const EMAIL = arg("email", "founder.b@example.test");
const PASSWORD = arg("password", "harness-pass-123");
const SHOTS = arg("shots", "");
mkdirSync(OUT, { recursive: true });

const VIEWPORTS = [
  { name: "390", w: 390, h: 844, mobile: true },
  { name: "768", w: 768, h: 1024, mobile: false },
  { name: "1024", w: 1024, h: 800, mobile: false },
  { name: "1440", w: 1440, h: 900, mobile: false },
];
const PAGES = ["/", "/cases", "/orders", "/orders/9a900000-0000-4000-8000-000000000001", "/money", "/users", "/users/b0000000-0000-4000-8000-000000000001", "/marketplace", "/marketplace/11570000-0000-4000-8000-000000000001", "/reports", "/system", "/search?q=founder", "/does-not-exist"];

const IN_PAGE = `(() => {
  const parse = (c) => { const m = c && c.match(/rgba?\\(([^)]+)\\)/); if (!m) return null; const p = m[1].split(/[\\s,\\/]+/).filter(Boolean).map(Number); return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 }; };
  const lin = (v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
  const lum = (c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  const blend = (fg, bg) => ({ r: fg.r * fg.a + bg.r * (1 - fg.a), g: fg.g * fg.a + bg.g * (1 - fg.a), b: fg.b * fg.a + bg.b * (1 - fg.a), a: 1 });
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const visible = (el) => { const r = el.getBoundingClientRect(); if (r.width <= 1 || r.height <= 1) return false; for (let e = el; e; e = e.parentElement) { const cs = getComputedStyle(e); if (cs.display === 'none' || cs.visibility === 'hidden') return false; } return true; };
  function background(el) {
    const layers = [];
    for (let e = el; e; e = e.parentElement) {
      const cs = getComputedStyle(e);
      if (cs.backgroundImage && cs.backgroundImage !== 'none') return { image: true };
      const c = parse(cs.backgroundColor);
      if (c && c.a > 0) { layers.push(c); if (c.a >= 1) break; }
    }
    let base = { r: 255, g: 255, b: 255, a: 1 };
    for (let i = layers.length - 1; i >= 0; i--) base = blend(layers[i], base);
    return base;
  }
  const opacity = (el) => { let o = 1; for (let e = el; e; e = e.parentElement) o *= Number(getComputedStyle(e).opacity || 1); return o; };
  const label = (el) => el.tagName.toLowerCase() + (el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\\s+/).slice(0, 3).join('.') : '');
  const out = { overflowX: Math.max(0, document.documentElement.scrollWidth - window.innerWidth), contrast: [], imageBg: 0, textChecked: 0, smallTargets: [], h1: document.querySelectorAll('h1').length, main: document.querySelectorAll('main').length, lang: document.documentElement.lang || '' };
  const seen = new Set();
  for (const el of document.querySelectorAll('body *')) {
    if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'svg', 'SVG'].includes(el.tagName)) continue;
    const own = [...el.childNodes].filter((n) => n.nodeType === 3 && n.textContent.trim()).map((n) => n.textContent.trim()).join(' ');
    if (!own || !visible(el)) continue;
    if (el.closest(':disabled,[aria-disabled="true"]')) continue;
    const cs = getComputedStyle(el);
    const bg = background(el);
    if (bg.image) { out.imageBg++; continue; }
    const fg0 = parse(cs.color); if (!fg0) continue;
    const fg = { ...fg0, a: fg0.a * opacity(el) };
    const r = ratio(blend(fg, bg), bg);
    const size = parseFloat(cs.fontSize); const bold = Number(cs.fontWeight) >= 700;
    const need = size >= 24 || (size >= 18.66 && bold) ? 3 : 4.5;
    out.textChecked++;
    if (r + 1e-6 < need) {
      const key = label(el) + '|' + own.slice(0, 30);
      if (!seen.has(key)) { seen.add(key); out.contrast.push({ el: label(el), text: own.slice(0, 40), ratio: Math.round(r * 100) / 100, need }); }
    }
  }
  if (window.innerWidth <= 480) {
    for (const el of document.querySelectorAll('a[href],button,input:not([type=hidden]),select,textarea,summary')) {
      if (!visible(el)) continue;
      const r = el.getBoundingClientRect();
      if (r.width >= 24 && r.height >= 24) continue;
      const inline = el.tagName === 'A' && el.parentElement && /^(P|LI|DD|TD|SPAN|DIV)$/.test(el.parentElement.tagName) && el.parentElement.textContent.trim().length > el.textContent.trim().length + 2;
      if (inline) continue;
      out.smallTargets.push({ el: label(el), text: (el.textContent || el.getAttribute('aria-label') || '').trim().slice(0, 30), w: Math.round(r.width), h: Math.round(r.height) });
    }
  }
  return out;
})()`;

async function unnamedControls(page) {
  const { nodes } = await page.send("Accessibility.getFullAXTree", {});
  const roles = new Set(["button", "link", "textbox", "combobox", "searchbox", "checkbox", "radio", "menuitem", "switch", "listbox"]);
  return nodes.filter((n) => !n.ignored && roles.has(n.role?.value) && !(n.name?.value || "").trim()).map((n) => n.role.value);
}

async function focusAudit(page, stops = 30) {
  await page.evaluate("document.activeElement && document.activeElement.blur(); window.scrollTo(0,0)");
  const missing = [];
  let count = 0;
  for (let i = 0; i < stops; i++) {
    await page.key("Tab", "Tab", 9);
    const f = await page.evaluate(`(() => { const e = document.activeElement; if (!e || e === document.body) return null;
      const cs = getComputedStyle(e); const r = e.getBoundingClientRect();
      const ring = (cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0) || (cs.boxShadow && cs.boxShadow !== 'none');
      return { el: e.tagName.toLowerCase() + (e.id ? '#' + e.id : ''), text: (e.textContent || e.getAttribute('aria-label') || e.getAttribute('name') || '').trim().slice(0, 30), ring, visible: r.width > 0 && r.height > 0 }; })()`);
    if (!f) continue;
    count++;
    if (f.visible && !f.ring) missing.push(f);
  }
  return { stops: count, missing };
}

const br = await launchBrowser(CHROME);
const report = { app: APP, label: LABEL, at: new Date().toISOString(), pages: [] };
try {
  const page = await br.newPage({ width: 1440, height: 900 });
  await page.send("Accessibility.enable", {});
  // login page, signed out
  for (const vp of VIEWPORTS) {
    await page.viewport(vp.w, vp.h, vp.mobile);
    await page.goto(`${APP}/login`);
    const r = await page.evaluate(IN_PAGE);
    report.pages.push({ path: "/login", viewport: vp.name, ...r, unnamed: await unnamedControls(page), focus: vp.name === "1440" || vp.name === "390" ? await focusAudit(page, 12) : null });
  }
  await page.viewport(1440, 900);
  await page.goto(`${APP}/login`);
  await page.fill("#email", EMAIL);
  await page.fill("#password", PASSWORD);
  await page.click('button[type="submit"]');
  if (!(await page.waitFor("location.pathname !== '/login'", 20000))) throw new Error("harness sign-in failed");
  for (const path of PAGES) {
    for (const vp of VIEWPORTS) {
      await page.viewport(vp.w, vp.h, vp.mobile);
      await page.goto(`${APP}${path}`);
      await page.waitFor("document.readyState === 'complete'", 8000);
      const r = await page.evaluate(IN_PAGE);
      const entry = { path, viewport: vp.name, ...r, unnamed: await unnamedControls(page), focus: vp.name === "1440" || vp.name === "390" ? await focusAudit(page) : null };
      report.pages.push(entry);
      if (SHOTS && ["/", "/orders", "/money", "/system"].includes(path)) await page.screenshot(join(SHOTS, `audit-${LABEL}-${path === "/" ? "today" : path.slice(1)}-${vp.name}.png`));
    }
  }
} finally {
  await br.close();
}

const rows = report.pages;
const sum = (f) => rows.reduce((n, r) => n + f(r), 0);
const totals = {
  pageViews: rows.length,
  overflowViews: rows.filter((r) => r.overflowX > 1).length,
  contrastFailures: sum((r) => r.contrast.length),
  textElementsChecked: sum((r) => r.textChecked),
  textOverBackgroundImage: sum((r) => r.imageBg),
  unnamedControls: sum((r) => r.unnamed.length),
  smallTargetsAt390: sum((r) => r.smallTargets.length),
  focusStops: sum((r) => r.focus?.stops ?? 0),
  focusWithoutIndicator: sum((r) => r.focus?.missing.length ?? 0),
  pagesWithoutSingleMain: rows.filter((r) => r.main !== 1 && r.path !== "/does-not-exist").length,
  pagesWithoutSingleH1: rows.filter((r) => r.h1 !== 1).length,
  langMissing: rows.filter((r) => !r.lang).length,
};
report.totals = totals;
writeFileSync(join(OUT, `ui-audit-${LABEL}.json`), JSON.stringify(report, null, 2));
const md = [`# UI audit — ${LABEL}`, "", `App ${APP} · ${report.at}`, "", "| Metric | Value |", "|---|---|", ...Object.entries(totals).map(([k, v]) => `| ${k} | ${v} |`), "", "| Page | VP | overflow px | contrast fails | unnamed | small targets | focus w/o ring | h1 | main |", "|---|---|---|---|---|---|---|---|---|",
  ...rows.map((r) => `| ${r.path} | ${r.viewport} | ${r.overflowX} | ${r.contrast.length} | ${r.unnamed.length} | ${r.smallTargets.length} | ${r.focus ? r.focus.missing.length + "/" + r.focus.stops : "—"} | ${r.h1} | ${r.main} |`)].join("\n");
writeFileSync(join(OUT, `ui-audit-${LABEL}.md`), md);
console.log(JSON.stringify(totals));
process.exit(0);
