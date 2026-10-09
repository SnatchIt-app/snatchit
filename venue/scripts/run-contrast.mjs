/**
 * Rendered-contrast sweep. Drives headless Chrome over CDP so the measurement
 * happens on the painted page, not on the stylesheet. Each page carries its
 * own positive AND negative control, and the run fails if either misbehaves.
 */
import { execFile } from "node:child_process";
import { readFileSync } from "node:fs";
const SCRIPT = readFileSync(new URL("./contrast-probe.js", import.meta.url), "utf8");
const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const PORT = 9777;
// node scripts/run-contrast.mjs [base]   (default http://localhost:3300)
const V = `${process.argv[2] ?? "http://localhost:3300"}/o/smp_org_wynwood/v/smp_ven_room`;
const E = `${V}/events/smp_evt_sat_music`;
const PAGES = [
  ["overview", V], ["events", `${V}/events`], ["event", E], ["tickets", `${E}/inventory`],
  ["guest list", `${E}/attendees`], ["check-in", `${E}/door`], ["create", `${V}/events/new`],
  ["finished event", `${V}/events/smp_evt_done`],
  ["empty", `${V}/events?state=empty`], ["filtered to nothing", `${V}/events?state=nodata`],
  ["error", `${E}/inventory?state=error`], ["denied", `${E}/door?role=venue_finance`],
  ["loading", `${V}/events?state=loading`], ["guest list / finance", `${E}/attendees?role=venue_finance`],
];
const chrome = execFile(CHROME, ["--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check", `--remote-debugging-port=${PORT}`, "--user-data-dir=/tmp/venue-contrast-cdp", "about:blank"]);
await new Promise((r) => setTimeout(r, 6000));
const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
const target = list.find((t) => t.type === "page");
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let id = 0;
const send = (method, params) => new Promise((res) => {
  const myId = ++id;
  const onMsg = (e) => { const m = JSON.parse(e.data); if (m.id === myId) { ws.removeEventListener("message", onMsg); res(m.result); } };
  ws.addEventListener("message", onMsg);
  ws.send(JSON.stringify({ id: myId, method, params }));
});
await send("Page.enable", {});
const results = [];
for (const [name, url] of PAGES) {
  await send("Page.navigate", { url });
  await new Promise((r) => setTimeout(r, 2500));
  const r = await send("Runtime.evaluate", { expression: SCRIPT, returnByValue: true, awaitPromise: true });
  results.push([name, r.result?.value]);
}
ws.close(); chrome.kill();
let bad = 0, totalChecked = 0, controlFailures = 0;
for (const [name, v] of results) {
  if (!v) { console.log(`${name.padEnd(22)} NO RESULT`); bad++; continue; }
  totalChecked += v.checked;
  if (!v.controlsOk) controlFailures++;
  console.log(`${name.padEnd(22)} checked ${String(v.checked).padStart(4)}  failures ${v.failureCount}  controls ${v.controlsOk ? "ok" : "BROKEN"}`);
  for (const f of v.fails) console.log(`    ${f.got} < ${f.need}  ${f.px}px  "${f.txt}"  ${f.cls}`);
  bad += v.failureCount;
}
console.log(`\nTOTAL text elements measured: ${totalChecked}`);
console.log(`TOTAL contrast failures: ${bad}`);
console.log(`Pages where the controls misbehaved: ${controlFailures}`);
