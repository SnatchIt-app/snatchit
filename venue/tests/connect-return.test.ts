import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  CONNECT_CONTEXT_COOKIE,
  CONNECT_CONTEXT_TTL_SECONDS,
  CONNECT_REFRESH_PATH,
  CONNECT_RETURN_PATH,
  connectContextCookieOptions,
  isPayoutsRole,
  parseConnectContext,
  payoutsPath,
  resolveLanding,
} from "@/lib/org/connect-return";

const A = "24232848-0bcf-4fa9-8040-c8bd2dc38ed2";
const B = "5e8db24b-a0ac-440a-9f00-fa15ee3bbb75";
// A third org the caller holds no role in. Hex, with letters: an all-digit uuid
// has a 12-digit tail that reads as a card number to the pre-push scanner.
const STRANGER = "7c1d9e4a-3b86-4c27-8f05-d1ae6b9c2f34";

describe("the two paths this app owns", () => {
  it("are static, because the edge's URLs may carry no query or fragment", () => {
    expect(CONNECT_RETURN_PATH).toBe("/connect/return");
    expect(CONNECT_REFRESH_PATH).toBe("/connect/refresh");
    for (const p of [CONNECT_RETURN_PATH, CONNECT_REFRESH_PATH]) {
      expect(p).not.toContain("?");
      expect(p).not.toContain("#");
      expect(p).not.toContain(":");
      expect(p.startsWith("/")).toBe(true);
    }
  });
  it("the routes exist in the app at exactly those paths", () => {
    const src = resolve(__dirname, "../src");
    expect(readFileSync(resolve(src, "app/connect/return/page.tsx"), "utf8")).toContain("ConnectReturnPage");
    expect(readFileSync(resolve(src, "app/connect/refresh/page.tsx"), "utf8")).toContain("ConnectRefreshPage");
  });
});

describe("the context cookie", () => {
  it("is Lax, because the trip back from Stripe is a top-level cross-site GET a Strict cookie would not survive", () => {
    const o = connectContextCookieOptions();
    expect(o.sameSite).toBe("lax");
    expect(o.httpOnly).toBe(true);
    expect(o.secure).toBe(true);
    expect(o.path).toBe("/");
    expect(o.maxAge).toBe(CONNECT_CONTEXT_TTL_SECONDS);
    expect(o).not.toHaveProperty("domain"); // host-only: never offered to a sibling host
    expect(o.name).toBe(CONNECT_CONTEXT_COOKIE);
  });
  it("holds one org id and nothing else; anything else is discarded, not repaired", () => {
    expect(parseConnectContext(A)).toBe(A.toLowerCase());
    expect(parseConnectContext(` ${A.toUpperCase()} `)).toBe(A.toLowerCase());
    for (const bad of [null, undefined, "", "not-a-uuid", `${A},${B}`, `${A}; path=/`, "../../etc", "https://evil.test", `${A}/../x`]) {
      expect(parseConnectContext(bad), String(bad)).toBeNull();
    }
  });
});

describe("where the operator lands", () => {
  it("the cookie is honoured only when the caller still holds a payouts role there", () => {
    expect(resolveLanding(A, [A, B])).toEqual({ kind: "org", orgId: A, path: `/o/${A}/payouts` });
    // a stale or planted cookie for an org the caller does not hold is ignored, not followed
    expect(resolveLanding(STRANGER, [A, B])).toEqual({ kind: "choose", orgIds: [A, B] });
  });
  it("with no cookie: one eligible org goes straight there, several ask, none says so", () => {
    expect(resolveLanding(null, [B])).toEqual({ kind: "org", orgId: B, path: `/o/${B}/payouts` });
    expect(resolveLanding(null, [A, B])).toEqual({ kind: "choose", orgIds: [A, B] });
    expect(resolveLanding(null, [])).toEqual({ kind: "none" });
    expect(resolveLanding(A, [])).toEqual({ kind: "none" });
  });
  it("junk in the eligible list cannot become a destination, and duplicates collapse", () => {
    expect(resolveLanding(null, ["nope", "../admin", ""])).toEqual({ kind: "none" });
    expect(resolveLanding(null, [A, A.toUpperCase()])).toEqual({ kind: "org", orgId: A, path: `/o/${A}/payouts` });
  });
  it("every destination is built from a validated uuid, so an open redirect is not expressible", () => {
    expect(payoutsPath(A)).toBe(`/o/${A}/payouts`);
    for (const bad of ["https://evil.test", "//evil.test", "nope", "", `${A}?x=1`]) expect(payoutsPath(bad), bad).toBeNull();
  });
  it("only the two org roles that may see payouts count — a venue role never does", () => {
    expect(isPayoutsRole("org_owner")).toBe(true);
    expect(isPayoutsRole("org_finance")).toBe(true);
    for (const r of ["org_admin", "org_member", "venue_manager", "venue_scanner", "venue_finance", "fan", ""]) expect(isPayoutsRole(r), r).toBe(false);
  });
});

describe("the handlers read nothing from the URL", () => {
  const src = resolve(__dirname, "../src");
  it("neither route takes searchParams, and neither redirects to anything but an internally built path", () => {
    for (const f of ["app/connect/return/page.tsx", "app/connect/refresh/page.tsx"]) {
      const text = readFileSync(resolve(src, f), "utf8");
      expect(text, f).not.toContain("searchParams");
      // the only redirect targets are landing.path (built from a uuid), the login route, or "/"
      const targets = [...text.matchAll(/redirect\(([^)]*)\)/g)].map((m) => m[1]);
      expect(targets.length, f).toBeGreaterThan(0);
      for (const t of targets) expect(t, `${f}: ${t}`).toMatch(/landing\.path|\/login\?next=|"\/"/);
    }
  });
  it("the refresh route does not mint a link on its own — a GET from Stripe must not call out", () => {
    const text = readFileSync(resolve(src, "app/connect/refresh/page.tsx"), "utf8");
    expect(text).not.toContain("startOrgOnboarding");
    expect(text).not.toContain("callOnboardingEdge");
    expect(text).toContain("retry=1");
  });
  it("the payouts page treats the retry flag as decoration only, never as state", () => {
    const text = readFileSync(resolve(src, "app/o/[org]/payouts/page.tsx"), "utf8");
    expect(text).toContain('sp.retry === "1"');
    expect(text).toContain("Decoration only");
    // the state still comes from the server read
    expect(text).toContain("readOrgConnect");
  });
});
