#!/usr/bin/env node
/**
 * Screenshot capture for the demo, using the Chrome already on this machine.
 * Same method the earlier venue captures used (docs/venue-dashboard/PREVIEW.md
 * "17 headless-Chrome captures") — no new dependency, no CI involvement.
 *
 *   node scripts/capture.mjs <outDir> <label>    # dev server must be running
 *
 * Chrome headless clamps the window narrower than ~500px, so the phone shots
 * are taken at 500px and that is stated rather than passed off as 375px.
 */
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { resolve } from "node:path";

const CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const V = "/o/smp_org_wynwood/v/smp_ven_room";
const E = `${V}/events/smp_evt_sat_music`;
const DONE = `${V}/events/smp_evt_done`;

/**
 * Each route carries the string that proves IT rendered — not the not-found
 * boundary, whose markup ships inside every page's payload in dev, and not a
 * generic marker that would pass for any page.
 */
const SHOTS = [
  ["overview", V, /Needs your attention|Nothing needs your attention/],
  ["events", `${V}/events`, /Next session|No events yet/],
  ["event", E, /Getting ready|Happening now|Finished/],
  ["event-blocked", `${V}/events/smp_evt_reggaeton`, /Add a ticket type before going on sale/],
  ["tickets", `${E}/inventory`, /Needs attention|No ticket types yet/],
  ["guests", `${E}/attendees`, /Guest list|Who paid/],
  ["checkin", `${E}/door`, /Right now at the door|isn&#x27;t open to you/],
  ["create", `${V}/events/new`, /New event/],
  ["review-finished", DONE, /Finished|complete/],
  ["state-empty", `${V}/events?state=empty`, /No events yet/],
  ["state-nomatch", `${V}/events?state=nodata`, /No events match these filters/],
  ["state-error", `${E}/inventory?state=error`, /couldn&#x27;t be loaded/],
  ["state-denied", `${E}/door?role=venue_finance`, /isn&#x27;t open to you/],
  ["state-loading", `${V}/events?state=loading`, /Loading/],
];

const [outDirArg, label = "shot", portArg = "3300"] = process.argv.slice(2);
const outDir = resolve(outDirArg);
const base = `http://localhost:${portArg}`;
mkdirSync(outDir, { recursive: true });

/**
 * Next's dev server compiles a route on first request, and Chrome will happily
 * screenshot the 404 that flashes while it does. Warm every route first and
 * then assert the served HTML is not the not-found page, so a run that silently
 * captured 404s fails instead of producing a misleading comparison.
 */
async function warm(path, marker) {
  for (let i = 0; i < 2; i++) {
    // The dev server drops connections while it compiles a heavy route; retry
    // rather than let a transient reset masquerade as a failed capture.
    let html = "";
    for (let attempt = 0; attempt < 6; attempt++) {
      try {
        const res = await fetch(`${base}${path}`, { redirect: "follow" });
        html = await res.text();
        break;
      } catch (e) {
        if (attempt === 5) throw e;
        await new Promise((r) => setTimeout(r, 2000));
      }
    }
    if (i === 1) {
      if (!marker.test(html)) throw new Error(`${path} did not render its own content (expected ${marker})`);
      if (!html.includes("Demo — sample data")) throw new Error(`no demo strip at ${path}`);
    }
  }
}

for (const [name, path, marker] of SHOTS) {
  await warm(path, marker);
  for (const [size, dims] of [["desktop", "1280,2200"], ["phone", "500,1400"]]) {
    const file = `${outDir}/${label}-${name}-${size}.png`;
    execFileSync(CHROME, [
      "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
      `--window-size=${dims}`, `--screenshot=${file}`, "--virtual-time-budget=4000",
      `${base}${path}`,
    ], { stdio: "ignore" });
  }
  console.log(name);
}
