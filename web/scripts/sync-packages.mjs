#!/usr/bin/env node
/**
 * Re-vendors the @snatchit/* shared packages into web/vendor as npm tarballs
 * and reinstalls them. Run after ANY change under ../packages:
 *
 *   npm run sync:packages
 *
 * Why tarballs instead of file:../packages symlinks: `vercel build` pins the
 * build root to web/, so sources outside it cannot resolve. Vendored tarballs
 * make web/ fully self-contained for Vercel/CI while packages/ stays the
 * source of truth (parity tests still import ../packages directly). The
 * pnpm monorepo planned for after App Review replaces this mechanism.
 */
import { execSync } from "node:child_process";
import { mkdirSync, readdirSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const webDir = join(dirname(fileURLToPath(import.meta.url)), "..");
const vendorDir = join(webDir, "vendor");
const packagesDir = join(webDir, "..", "packages");

mkdirSync(vendorDir, { recursive: true });
for (const f of readdirSync(vendorDir)) {
  if (f.endsWith(".tgz")) rmSync(join(vendorDir, f));
}

for (const pkg of ["types", "core", "design-tokens"]) {
  execSync(`npm pack "${join(packagesDir, pkg)}" --pack-destination "${vendorDir}"`, {
    stdio: "inherit",
  });
}

execSync("npm install --no-audit --no-fund", { cwd: webDir, stdio: "inherit" });
console.log("\n✓ vendored packages synced");
