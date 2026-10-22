import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/**
 * A redirect from the proxy carries the session cookies a refresh just wrote.
 *
 * getClaims() refreshes an expired access token and hands the rotated cookies
 * to setAll, which writes them on `supabaseResponse`. When the proxy then
 * redirects (aal1 → /mfa, aal2 on /login or /mfa, no session → /login), it
 * used to return a fresh NextResponse.redirect without them: the browser kept
 * the old refresh token, which the auth server refuses once it has been used,
 * and the operator was signed out. The redirect must carry every cookie
 * (host-only, no Domain) and the no-store cache headers @supabase/ssr asks
 * for — and nothing else from the pass-through response.
 */
type CookieWrite = { name: string; value: string; options: Record<string, unknown> };
const ssr = vi.hoisted(() => ({
  claims: null as Record<string, unknown> | null,
  /** Each entry is one setAll call the fake client makes during getClaims(). */
  writes: [] as { cookies: CookieWrite[]; headers: Record<string, string> }[],
}));

vi.mock("server-only", () => ({}));
vi.mock("@supabase/ssr", () => ({
  createServerClient: (_url: string, _key: string, options: Record<string, unknown>) => ({
    auth: {
      getClaims: async () => {
        const cookies = options.cookies as { setAll: (c: CookieWrite[], h: Record<string, string>) => void };
        for (const w of ssr.writes) cookies.setAll(w.cookies, w.headers);
        return { data: ssr.claims ? { claims: ssr.claims } : null, error: null };
      },
    },
  }),
}));

const CACHE_HEADERS = { "Cache-Control": "private, no-cache, no-store, must-revalidate, max-age=0", Expires: "0", Pragma: "no-cache" };
const OPERATOR = "f0000000-0000-4000-8000-0000000000a1";
/** Synthetic values only: what @supabase/ssr writes on a refresh (chunked), with a Domain that must not survive. */
const rotated = (domain = ".snatchitapp.com"): CookieWrite[] => [
  { name: "sb-synthetic-auth-token.0", value: "rotated-part-0", options: { path: "/", sameSite: "lax", httpOnly: false, maxAge: 34560000, domain } },
  { name: "sb-synthetic-auth-token.1", value: "rotated-part-1", options: { path: "/", sameSite: "lax", httpOnly: false, maxAge: 34560000, domain } },
];

beforeEach(() => {
  vi.resetModules();
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://synthetic.supabase.co");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "sb_publishable_SYNTHETICtestvalue00000000000");
  ssr.claims = null;
  ssr.writes = [];
});
afterEach(() => {
  vi.unstubAllEnvs();
});

async function run(path: string) {
  const { NextRequest } = await import("next/server");
  const { updateSession } = await import("@/lib/supabase/proxy");
  return updateSession(new NextRequest(`https://admin.snatchitapp.com${path}`));
}

/** Every Set-Cookie line on the response, one per cookie. */
const setCookies = (res: Response) => res.headers.getSetCookie();

function expectRotatedHostOnly(res: Response) {
  const lines = setCookies(res);
  expect(lines.some((l) => l.startsWith("sb-synthetic-auth-token.0=rotated-part-0"))).toBe(true);
  expect(lines.some((l) => l.startsWith("sb-synthetic-auth-token.1=rotated-part-1"))).toBe(true);
  for (const l of lines) expect(l.toLowerCase(), l).not.toContain("domain=");
  // The other attributes survive.
  for (const l of lines) {
    expect(l).toContain("Path=/");
    expect(l.toLowerCase()).toContain("samesite=lax");
    expect(l).toContain("Max-Age=34560000");
  }
}

describe("proxy redirect after a token refresh", () => {
  it("aal1 on a console route → /mfa, carrying the rotated cookies without Domain and the no-store headers", async () => {
    ssr.claims = { sub: OPERATOR, aal: "aal1" };
    ssr.writes = [{ cookies: rotated(), headers: CACHE_HEADERS }];
    const res = await run("/orders?status=paid");
    expect(res.status).toBe(307);
    expect(new URL(res.headers.get("location")!).pathname + new URL(res.headers.get("location")!).search).toBe("/mfa?next=%2Forders%3Fstatus%3Dpaid");
    expectRotatedHostOnly(res);
    expect(res.headers.get("cache-control")).toBe(CACHE_HEADERS["Cache-Control"]);
    expect(res.headers.get("expires")).toBe("0");
    expect(res.headers.get("pragma")).toBe("no-cache");
  });

  it("aal2 on /login and on /mfa → bounced to next, carrying the rotated cookies", async () => {
    ssr.claims = { sub: OPERATOR, aal: "aal2" };
    for (const path of ["/login?next=%2Fmoney", "/mfa?next=%2Fmoney"]) {
      ssr.writes = [{ cookies: rotated(), headers: CACHE_HEADERS }];
      const res = await run(path);
      expect(res.status, path).toBe(307);
      expect(new URL(res.headers.get("location")!).pathname, path).toBe("/money");
      expectRotatedHostOnly(res);
    }
  });

  it("a refresh that ended the session → /login, carrying the cookie deletions", async () => {
    ssr.claims = null;
    ssr.writes = [
      {
        cookies: [
          { name: "sb-synthetic-auth-token.0", value: "", options: { path: "/", maxAge: 0, domain: ".snatchitapp.com" } },
          { name: "sb-synthetic-auth-token.1", value: "", options: { path: "/", maxAge: 0, domain: ".snatchitapp.com" } },
        ],
        headers: CACHE_HEADERS,
      },
    ];
    const res = await run("/cases");
    expect(new URL(res.headers.get("location")!).pathname).toBe("/login");
    const lines = setCookies(res);
    expect(lines).toHaveLength(2);
    for (const l of lines) {
      expect(l).toMatch(/^sb-synthetic-auth-token\.[01]=;/);
      expect(l).toContain("Max-Age=0");
      expect(l.toLowerCase()).not.toContain("domain=");
    }
  });

  it("the cache headers from the first setAll survive a second setAll (they are only sent once)", async () => {
    ssr.claims = { sub: OPERATOR, aal: "aal1" };
    ssr.writes = [
      { cookies: rotated(), headers: CACHE_HEADERS },
      { cookies: rotated(), headers: {} },
    ];
    const redirect = await run("/orders");
    expect(redirect.headers.get("cache-control")).toBe(CACHE_HEADERS["Cache-Control"]);
    ssr.claims = { sub: OPERATOR, aal: "aal2" };
    const passThrough = await run("/orders");
    expect(passThrough.headers.get("x-middleware-next")).toBe("1");
    expect(passThrough.headers.get("cache-control")).toBe(CACHE_HEADERS["Cache-Control"]);
    expectRotatedHostOnly(passThrough);
  });

  it("only cookies and cache headers are copied: the redirect is not turned into a pass-through", async () => {
    ssr.claims = { sub: OPERATOR, aal: "aal1" };
    ssr.writes = [{ cookies: rotated(), headers: CACHE_HEADERS }];
    const res = await run("/orders");
    expect(res.status).toBe(307);
    expect(res.headers.get("x-middleware-next")).toBeNull();
    expect(res.headers.get("x-middleware-override-headers")).toBeNull();
    expect([...res.headers.keys()].filter((k) => k.startsWith("x-middleware-request-"))).toEqual([]);
  });

  it("no refresh → the redirect sets no cookie and no cache header of its own (control)", async () => {
    ssr.claims = { sub: OPERATOR, aal: "aal1" };
    ssr.writes = [];
    const res = await run("/orders");
    expect(res.status).toBe(307);
    expect(setCookies(res)).toEqual([]);
    expect(res.headers.get("cache-control")).toBeNull();
  });

  it("no redirect → the pass-through response still carries the rotated cookies (unchanged path)", async () => {
    ssr.claims = { sub: OPERATOR, aal: "aal2" };
    ssr.writes = [{ cookies: rotated(), headers: CACHE_HEADERS }];
    const res = await run("/orders");
    expect(res.headers.get("location")).toBeNull();
    expectRotatedHostOnly(res);
  });
});

describe("withSessionCookies", () => {
  it("strips a Domain whatever wrote the cookie, keeps the other attributes, copies only the given headers", async () => {
    const { NextResponse } = await import("next/server");
    const { withSessionCookies } = await import("@/lib/supabase/proxy");
    const from = NextResponse.next();
    from.cookies.set("sb-synthetic-auth-token", "rotated", { domain: ".snatchitapp.com", path: "/", sameSite: "lax", maxAge: 60 });
    from.headers.set("x-synthetic-pass-through", "1");
    const res = withSessionCookies(NextResponse.redirect("https://admin.snatchitapp.com/mfa"), from, { "Cache-Control": "private, no-store" });
    const lines = res.headers.getSetCookie();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatch(/^sb-synthetic-auth-token=rotated;/);
    expect(lines[0].toLowerCase()).not.toContain("domain=");
    expect(lines[0]).toContain("Path=/");
    expect(lines[0]).toContain("Max-Age=60");
    expect(res.cookies.get("sb-synthetic-auth-token")?.domain).toBeUndefined();
    expect(res.headers.get("cache-control")).toBe("private, no-store");
    expect(res.headers.get("x-synthetic-pass-through")).toBeNull();
    expect(res.status).toBe(307);
  });
});
