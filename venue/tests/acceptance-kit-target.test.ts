/**
 * The kit's local target talks to the Docker-free harness (PostgREST + auth stub). Its API URL defaulted to
 * http://localhost:3202 with no way to change it, so a rehearsal could not run on another port (a second
 * harness, or a session told to keep to its own port range). `--url` sets it for the local target only; the
 * guards that make the local target safe stay in lib/target.mjs and are pinned here.
 *
 * The same goes for Chrome's DevTools port (a random port in 9400-9799, unchecked): `--cdp-ports lo-hi` picks it
 * from another range, and a port something already listens on is skipped, so the kit never attaches to a
 * browser it did not start (another session's Chrome on that port would have answered /json/version).
 */
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { makeTarget, PRODUCTION_REF } from "../scripts/acceptance/lib/target.mjs";
import { parsePortRange, pickFreePort } from "../scripts/acceptance/lib/checks.mjs";

const kit = readFileSync(new URL("../scripts/acceptance/accept.mjs", import.meta.url), "utf8");
const cdp = readFileSync(new URL("../scripts/acceptance/lib/cdp.mjs", import.meta.url), "utf8");

describe("the kit's local API URL", () => {
  it("accept.mjs reads --url into the options it hands makeTarget", () => {
    expect(kit).toMatch(/^\s+url: arg\("url"\),$/m);
    expect(kit).toContain("const target = makeTarget(opts);");
  });
  it("defaults to the harness auth stub on :3202 when --url is not given", () => {
    const t = makeTarget({ target: "local", db: "kit_rehears", url: undefined });
    expect(t.url).toBe("http://localhost:3202");
  });
  it("uses a loopback URL on another port", () => {
    for (const url of ["http://localhost:3402", "http://127.0.0.1:9802"]) {
      const t = makeTarget({ target: "local", db: "kit_rehears", url });
      expect(t.url).toBe(url);
      expect(t.describe).toContain(`api=${url}`);
    }
  });
  it("refuses anything that is not plain-http loopback", () => {
    for (const url of ["https://localhost:3402", "http://example.com:3402", "http://localhost.example.com:3402", "http://10.0.0.5:3202"]) {
      expect(() => makeTarget({ target: "local", db: "kit_rehears", url })).toThrow(/loopback/);
    }
  });
  it("still refuses a local database without 'rehears' and any URL naming production", () => {
    expect(() => makeTarget({ target: "local", db: "postgres", url: "http://localhost:3402" })).toThrow(/rehears/);
    expect(() => makeTarget({ target: "local", db: "kit_rehears", url: `https://${PRODUCTION_REF}.supabase.co` })).toThrow(/never targets production/);
  });
});

describe("the kit's Chrome DevTools port", () => {
  it("parses --cdp-ports as <lo>-<hi> and refuses anything else", () => {
    expect(parsePortRange(undefined)).toBeNull();
    expect(parsePortRange("9800-9899")).toEqual([9800, 9899]);
    expect(parsePortRange(" 9850-9850 ")).toEqual([9850, 9850]);
    for (const bad of ["9899-9800", "80-90", "9800", "9800-70000", "a-b", "9800-9899x", ""]) {
      expect(() => parsePortRange(bad)).toThrow(/--cdp-ports/);
    }
  });
  it("picks a port inside the range that nothing listens on, trying each port once", async () => {
    const tried: number[] = [];
    const busy = new Set([9800, 9801, 9803]);
    const port = await pickFreePort([9800, 9803], async (p: number) => {
      tried.push(p);
      return !busy.has(p);
    });
    expect(port).toBe(9802);
    expect(new Set(tried).size).toBe(tried.length);
    expect(tried.every((p) => p >= 9800 && p <= 9803)).toBe(true);
    for (let i = 0; i < 50; i++) {
      const p = await pickFreePort([9800, 9899], async () => true);
      expect(p >= 9800 && p <= 9899).toBe(true);
    }
  });
  it("fails when every port in the range is taken", async () => {
    let calls = 0;
    await expect(
      pickFreePort([9800, 9809], async () => {
        calls++;
        return false;
      }),
    ).rejects.toThrow(/no free port in 9800-9809/);
    expect(calls).toBe(10);
  });
  it("every browser the kit opens uses the parsed range, and cdp.mjs checks the port before Chrome starts", () => {
    expect(kit).toContain('cdpPorts: parsePortRange(arg("cdp-ports")),');
    expect(kit.match(/launchBrowser\(/g)).toHaveLength(1);
    expect(kit).toContain("const openBrowser = () => launchBrowser(opts.chrome, opts.cdpPorts ? { portRange: opts.cdpPorts } : {});");
    expect(kit.match(/await openBrowser\(\)/g)?.length).toBe(3);
    expect(cdp).toMatch(/const port = await pickFreePort\(portRange, portFree\);[\s\S]*mkdtempSync/);
  });
});
