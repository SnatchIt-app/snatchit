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
const BASE = "http://localhost:3300";
const V = "/o/smp_org_wynwood/v/smp_ven_room";
const E = `${V}/events/smp_evt_sat_music`;
const DONE = `${V}/events/smp_evt_done`;

const SHOTS = [
  ["overview", V],
  ["events", `${V}/events`],
  ["event", E],
  ["event-blocked", `${V}/events/smp_evt_reggaeton`],
  ["tickets", `${E}/inventory`],
  ["guests", `${E}/attendees`],
  ["checkin", `${E}/door`],
  ["create", `${V}/events/new`],
  ["review-finished", DONE],
  ["state-empty", `${V}/events?state=empty`],
  ["state-nomatch", `${V}/events?state=nodata`],
  ["state-error", `${E}/inventory?state=error`],
  ["state-denied", `${E}/door?role=venue_finance`],
  ["state-loading", `${V}/events?state=loading`],
];

const [outDirArg, label = "shot"] = process.argv.slice(2);
const outDir = resolve(outDirArg);
mkdirSync(outDir, { recursive: true });

for (const [name, path] of SHOTS) {
  for (const [size, dims] of [["desktop", "1280,2200"], ["phone", "500,1400"]]) {
    const file = `${outDir}/${label}-${name}-${size}.png`;
    execFileSync(CHROME, [
      "--headless", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
      `--window-size=${dims}`, `--screenshot=${file}`, "--virtual-time-budget=4000",
      `${BASE}${path}`,
    ], { stdio: "ignore" });
    console.log(`${label}-${name}-${size}`);
  }
}
