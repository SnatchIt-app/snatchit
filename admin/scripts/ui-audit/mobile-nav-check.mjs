#!/usr/bin/env node
// F9 — interaction check for the mobile navigation in a real headless Chrome (LOCAL harness only).
//   node admin/scripts/ui-audit/mobile-nav-check.mjs --app http://localhost:3200 [--shots <dir>] [--label dark]
// Requires admin/scripts/ui-audit/cdp.mjs (same client as the UI audit).
import { join } from "node:path";
import { launchBrowser } from "./cdp.mjs";

const arg = (k, d) => {
  const i = process.argv.indexOf(`--${k}`);
  return i >= 0 ? process.argv[i + 1] : d;
};
const APP = arg("app", "http://localhost:3200");
const SHOTS = arg("shots", "");
const LABEL = arg("label", "build");
const results = [];
const check = (id, ok, detail = "") => {
  results.push({ id, ok: !!ok });
  console.log(`${ok ? "PASS" : "FAIL"}  ${id}${ok ? "" : `  — ${JSON.stringify(detail)}`}`);
};
const state = (p) =>
  p.evaluate(`(() => { const b = document.querySelector('button[aria-controls="mobile-nav"]'); const n = document.getElementById('mobile-nav');
    const vis = (e) => !!e && getComputedStyle(e).display !== 'none' && e.getBoundingClientRect().height > 0;
    const aside = document.querySelector('aside');
    return { button: vis(b), expanded: b && b.getAttribute('aria-expanded'), nav: vis(n), links: n ? [...n.querySelectorAll('a')].map(a => a.getAttribute('href')) : [],
      current: n ? [...n.querySelectorAll('a[aria-current="page"]')].map(a => a.getAttribute('href')) : [], focusIsButton: document.activeElement === b,
      sidebar: vis(aside), path: location.pathname, overflowX: document.documentElement.scrollWidth - innerWidth }; })()`);

const br = await launchBrowser(arg("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"));
try {
  const p = await br.newPage({ width: 1440, height: 900 });
  await p.goto(`${APP}/login`);
  await p.fill("#email", arg("email", "founder.b@example.test"));
  await p.fill("#password", arg("password", "harness-pass-123"));
  await p.click('button[type="submit"]');
  check("harness sign-in", await p.waitFor("location.pathname !== '/login'", 20000));

  await p.viewport(390, 844, true);
  await p.goto(`${APP}/cases`);
  let s = await state(p);
  check("390: Menu button visible, collapsed; no sidebar; menu closed", s.button && s.expanded === "false" && !s.sidebar && !s.nav, s);
  check("390: no horizontal page overflow on /cases", s.overflowX <= 1, s.overflowX);
  if (SHOTS) await p.screenshot(join(SHOTS, `f9-${LABEL}-390-closed.png`));

  await p.click('button[aria-controls="mobile-nav"]');
  await p.waitFor("!!document.getElementById('mobile-nav')", 3000);
  s = await state(p);
  check("390: click opens menu, aria-expanded=true", s.nav && s.expanded === "true", s);
  check("390: menu lists exactly the 8 sidebar sections", JSON.stringify(s.links) === JSON.stringify(["/", "/cases", "/orders", "/money", "/users", "/marketplace", "/reports", "/system"]), s.links);
  check("390: aria-current marks Cases only", JSON.stringify(s.current) === JSON.stringify(["/cases"]), s.current);
  if (SHOTS) await p.screenshot(join(SHOTS, `f9-${LABEL}-390-open.png`));

  await p.key("Escape", "Escape", 27);
  await p.waitFor("!document.getElementById('mobile-nav')", 3000);
  s = await state(p);
  check("390: Escape closes and returns focus to the button", !s.nav && s.expanded === "false" && s.focusIsButton, s);

  await p.key("Enter", "Enter", 13);
  await p.waitFor("!!document.getElementById('mobile-nav')", 3000);
  s = await state(p);
  check("390: keyboard Enter on the focused button opens the menu", s.nav, s);

  await p.click('#mobile-nav a[href="/money"]');
  await p.waitFor("location.pathname === '/money'", 15000);
  await p.waitFor("!document.getElementById('mobile-nav')", 5000);
  s = await state(p);
  check("390: choosing Money navigates and closes the menu", s.path === "/money" && !s.nav && s.expanded === "false", s);

  await p.click('button[aria-controls="mobile-nav"]');
  await p.waitFor("!!document.getElementById('mobile-nav')", 3000);
  await p.evaluate("document.activeElement.blur()");
  await p.key("g", "KeyG", 71);
  await p.key("s", "KeyS", 83);
  await p.waitFor("location.pathname === '/system'", 15000);
  await p.waitFor("!document.getElementById('mobile-nav')", 5000);
  s = await state(p);
  check("390: g-s shortcut navigation also closes an open menu", s.path === "/system" && !s.nav, s);

  for (const [w, h] of [[768, 1024], [1440, 900]]) {
    await p.viewport(w, h, false);
    await p.goto(`${APP}/cases`);
    s = await state(p);
    check(`${w}: sidebar shown, Menu button hidden (desktop unchanged)`, s.sidebar && !s.button && !s.nav, s);
  }

  // Signed out: no menu leaks onto the auth screens.
  const anon = await br.newPage({ width: 390, height: 844 });
  await anon.viewport(390, 844, true);
  await anon.goto(`${APP}/login`);
  s = await state(anon);
  check("signed out /login: no Menu button, no section links", !s.button && !s.nav, s);
  await anon.goto(`${APP}/cases`);
  s = await state(anon);
  check("signed out /cases: redirected to /login, no menu", s.path === "/login" && !s.button, s);
} finally {
  await br.close();
}
const failed = results.filter((r) => !r.ok).length;
console.log(`${results.length - failed}/${results.length} F9 checks passed`);
process.exit(failed ? 1 : 0);
