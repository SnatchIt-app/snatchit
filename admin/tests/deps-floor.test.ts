import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * F6 (OC-11) — next is pinned exactly, at or above the patched 16.3.8.
 * 16.3.3 carried GHSA-vcvr-r3jv-pc5j (critical, next/og RCE), GHSA-cjq9-62q9-8jv4
 * (high, Image Optimization SSRF) and five moderate/low advisories, all fixed
 * by 16.3.8. A floor, not an equality: a later patch passes, a downgrade or a
 * range does not, and the lockfile must agree with package.json.
 */
const root = resolve(__dirname, "..");
const pkg = JSON.parse(readFileSync(resolve(root, "package.json"), "utf8")) as { dependencies: Record<string, string> };
const lock = JSON.parse(readFileSync(resolve(root, "package-lock.json"), "utf8")) as {
  packages: Record<string, { version?: string; dependencies?: Record<string, string> }>;
};

const FLOOR = [16, 3, 8] as const;
const parts = (v: string) => v.split(".").map((n) => Number(n));
const atLeast = (v: string, floor: readonly number[]) => {
  const p = parts(v);
  for (let i = 0; i < floor.length; i++) {
    if (p[i] !== floor[i]) return p[i] > floor[i];
  }
  return true;
};

describe("F6 — next security floor", () => {
  it("package.json pins next to an exact version at or above 16.3.8", () => {
    const v = pkg.dependencies.next;
    expect(v).toMatch(/^\d+\.\d+\.\d+$/);
    expect(atLeast(v, FLOOR), v).toBe(true);
  });

  it("the lockfile resolves next and @next/env to that same version", () => {
    const v = pkg.dependencies.next;
    expect(lock.packages[""].dependencies?.next).toBe(v);
    expect(lock.packages["node_modules/next"].version).toBe(v);
    expect(lock.packages["node_modules/@next/env"].version).toBe(v);
  });

  it("the floor check itself orders versions correctly", () => {
    expect(atLeast("16.3.8", FLOOR)).toBe(true);
    expect(atLeast("16.3.10", FLOOR)).toBe(true);
    expect(atLeast("16.4.0", FLOOR)).toBe(true);
    expect(atLeast("17.0.0", FLOOR)).toBe(true);
    expect(atLeast("16.3.7", FLOOR)).toBe(false);
    expect(atLeast("16.3.3", FLOOR)).toBe(false);
    expect(atLeast("16.2.99", FLOOR)).toBe(false);
  });
});
