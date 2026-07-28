#!/usr/bin/env node
/**
 * Smoke test: builds must already exist (`npm run build`). Starts `next start`
 * on a scratch port, hits the three proof routes plus robots/sitemap, and
 * asserts status codes, key content markers, and security headers.
 */
import { spawn } from "node:child_process";

const PORT = process.env.SMOKE_PORT ?? "3105";
const BASE = `http://127.0.0.1:${PORT}`;
const LISTING_ID = process.env.SMOKE_LISTING_ID ?? "4afe3557-9c34-4e89-8cac-df69223b551c";

const checks = [
  { path: "/", expect: [/Snatch It/i, /all-in/i], status: 200 },
  { path: "/browse", expect: [/Browse tickets/i], status: 200 },
  { path: `/listing/${LISTING_ID}`, expect: [/Buyer Protection/i, /total/i], status: 200 },
  { path: "/listing/00000000-0000-0000-0000-000000000000", expect: [], status: 404 },
  { path: "/robots.txt", expect: [/sitemap/i], status: 200 },
  { path: "/sitemap.xml", expect: [/browse/], status: 200 },
];

const REQUIRED_HEADERS = [
  "content-security-policy",
  "x-content-type-options",
  "referrer-policy",
  "permissions-policy",
];

function wait(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function waitForServer(timeoutMs = 30_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(BASE, { redirect: "manual" });
      if (res.status > 0) return;
    } catch {
      await wait(500);
    }
  }
  throw new Error("server did not start in time");
}

const server = spawn("npx", ["next", "start", "-p", PORT], {
  stdio: ["ignore", "pipe", "pipe"],
  env: { ...process.env, NODE_ENV: "production" },
});
let serverLog = "";
server.stdout.on("data", (d) => (serverLog += d));
server.stderr.on("data", (d) => (serverLog += d));

let failures = 0;
try {
  await waitForServer();
  for (const check of checks) {
    const res = await fetch(`${BASE}${check.path}`);
    const body = await res.text();
    const problems = [];
    if (res.status !== check.status) problems.push(`status ${res.status} ≠ ${check.status}`);
    for (const re of check.expect) {
      if (!re.test(body)) problems.push(`missing ${re}`);
    }
    if (check.path === "/") {
      for (const h of REQUIRED_HEADERS) {
        if (!res.headers.get(h)) problems.push(`missing header ${h}`);
      }
    }
    if (problems.length) {
      failures++;
      console.error(`✗ ${check.path}: ${problems.join("; ")}`);
    } else {
      console.log(`✓ ${check.path} (${res.status})`);
    }
  }
} catch (err) {
  failures++;
  console.error("✗ smoke run failed:", err.message);
  console.error(serverLog.slice(-2000));
} finally {
  server.kill("SIGTERM");
}

process.exit(failures ? 1 : 0);
