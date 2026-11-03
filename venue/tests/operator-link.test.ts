import { existsSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { operatorEventPath } from "@/lib/links";

/**
 * S1 — the operator deep link to one event's setup page. It must point at the dashboard's REAL operator
 * route (src/app/o/[org]/v/[venue]/events/[event]/page.tsx), carry no query string (no role/state/preview
 * controls, nothing for a log to keep) and no host (CSP is connect-src 'self').
 */
const O = "0a0a0a0a-0a0a-40a0-80a0-0a0a0a0a0a0a";
const V = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const E = "11111111-1111-4111-8111-111111111111";

describe("operatorEventPath", () => {
  it("matches the route folder that actually exists in src/app", () => {
    const routeDir = path.resolve(__dirname, "../src/app/o/[org]/v/[venue]/events/[event]");
    expect(existsSync(path.join(routeDir, "page.tsx"))).toBe(true);
    const template = routeDir.slice(path.resolve(__dirname, "../src/app").length).replace("[org]", O).replace("[venue]", V).replace("[event]", E);
    expect(operatorEventPath(O, V, E)).toBe(template);
    expect(operatorEventPath(O, V, E)).toBe(`/o/${O}/v/${V}/events/${E}`);
  });
  it("is host-agnostic and carries no query string or fragment", () => {
    const p = operatorEventPath(O, V, E) as string;
    expect(p.startsWith("/")).toBe(true);
    expect(p).not.toMatch(/^https?:|\/\//);
    const u = new URL(p, "http://placeholder.invalid");
    expect(u.search).toBe("");
    expect(u.hash).toBe("");
    expect(p).not.toMatch(/[?#&=]|role|state|preview/);
  });
  it("encodes every segment so an id can never break out of its slot or smuggle a query", () => {
    const p = operatorEventPath("o/../x", "v?role=org_owner", "e#frag &state=denied") as string;
    expect(p).toBe(`/o/${encodeURIComponent("o/../x")}/v/${encodeURIComponent("v?role=org_owner")}/events/${encodeURIComponent("e#frag &state=denied")}`);
    expect(p.split("/")).toHaveLength(7); // "", o, {org}, v, {venue}, events, {event}
    expect(p).not.toMatch(/[?#&= ]/);
    const u = new URL(p, "http://placeholder.invalid");
    expect(u.search).toBe("");
    expect(u.hash).toBe("");
  });
  it("passes uuid and fixture ids through unchanged (they need no encoding)", () => {
    expect(operatorEventPath("smp_org_wynwood", "smp_ven_room", "smp_evt_1")).toBe("/o/smp_org_wynwood/v/smp_ven_room/events/smp_evt_1");
    expect(operatorEventPath(O, V, E)).toContain(E);
  });
  it("refuses an empty or blank id in any position (null, never a path with a hole in it)", () => {
    expect(operatorEventPath("", V, E)).toBeNull();
    expect(operatorEventPath(O, "", E)).toBeNull();
    expect(operatorEventPath(O, V, "")).toBeNull();
    expect(operatorEventPath(O, V, "   ")).toBeNull();
    expect(operatorEventPath(undefined as unknown as string, V, E)).toBeNull();
    expect(operatorEventPath(O, null as unknown as string, E)).toBeNull();
  });
});
