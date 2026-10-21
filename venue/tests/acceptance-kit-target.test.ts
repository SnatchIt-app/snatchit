/**
 * The kit's local target talks to the Docker-free harness (PostgREST + auth stub). Its API URL defaulted to
 * http://localhost:3202 with no way to change it, so a rehearsal could not run on another port (a second
 * harness, or a session told to keep to its own port range). `--url` sets it for the local target only; the
 * guards that make the local target safe stay in lib/target.mjs and are pinned here.
 */
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { makeTarget, PRODUCTION_REF } from "../scripts/acceptance/lib/target.mjs";

const kit = readFileSync(new URL("../scripts/acceptance/accept.mjs", import.meta.url), "utf8");

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
