/**
 * venue/.vercelignore — what a CLI deploy from venue/ must never upload. The Vercel CLI does not
 * read .gitignore (the 2026-10-06 demo deploy uploaded the gitignored tsconfig.tsbuildinfo and
 * next-env.d.ts); it adds .vercelignore to its own built-in list using the `ignore` package's
 * gitignore semantics, which is what this test applies.
 */
import { existsSync, readFileSync } from "node:fs";
import ignore from "ignore";
import { describe, expect, it } from "vitest";

const file = new URL("../.vercelignore", import.meta.url);
const rules = () => ignore().add(readFileSync(file, "utf8"));

describe("venue/.vercelignore", () => {
  it("exists next to package.json (the directory the CLI deploys from)", () => {
    expect(existsSync(file)).toBe(true);
  });
  it.each([
    ".env",
    ".env.local",
    ".env.production",
    ".env.development",
    ".env.production.local",
    ".env.local.example-harness",
    "src/.env",
    ".vercel/project.json",
    ".next/server/app/page.js",
    "node_modules/next/package.json",
    "tsconfig.tsbuildinfo",
    "next-env.d.ts",
    "scripts/acceptance/.runs/sandbox/state.json",
    "scripts/acceptance/.runs/local/baseline.json",
    "scripts/acceptance/.runs/sandbox/evidence-browser-x.json",
    "scripts/local/state/postgrest.conf",
    "server.pem",
    "AuthKey_TEST.p8",
    ".f-handoff/notes.md",
    "coverage/index.html",
    "npm-debug.log",
  ])("never uploads %s", (path) => {
    expect(rules().ignores(path)).toBe(true);
  });
  it.each([
    "package.json",
    "package-lock.json",
    "next.config.ts",
    "vercel.json",
    "tsconfig.json",
    "postcss.config.mjs",
    "src/proxy.ts",
    "src/app/layout.tsx",
    "src/app/globals.css",
    "src/app/o/[org]/v/[venue]/loading.tsx",
    "src/lib/env.ts",
    "public/sn-logo.svg",
  ])("still uploads %s (needed to build)", (path) => {
    expect(rules().ignores(path)).toBe(false);
  });
});
