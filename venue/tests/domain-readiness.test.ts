/**
 * Domain readiness for https://venue.snatchitapp.com. The same build must run on any host
 * (localhost, a *.vercel.app preview, the custom domain) without a host baked in:
 *   - the Supabase session cookies are host-only (no Domain attribute), so a venue session is
 *     never sent to admin.snatchitapp.com, snatchitapp.com or any other sibling host;
 *   - they are Secure (never sent over plain http) and HttpOnly (no script can read the refresh
 *     token): every Supabase call is server-side, so no browser code needs the session;
 *   - production responses carry HSTS (max-age only: no includeSubDomains, no preload);
 *   - sign-out redirects with a relative Location;
 *   - no absolute URL is hard-coded in src/, and the security headers carry no host.
 *
 * The real @supabase/ssr client runs here. GoTrue is replaced by a stubbed global fetch, so no
 * request leaves the process, and next/headers is a recording cookie store.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { NextRequest } from "next/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const jar = vi.hoisted(() => ({
  cookies: [] as { name: string; value: string }[],
  set: [] as { name: string; value: string; options: Record<string, unknown> }[],
}));
vi.mock("next/headers", () => ({
  cookies: async () => ({
    getAll: () => jar.cookies,
    set: (name: string, value: string, options: Record<string, unknown>) => jar.set.push({ name, value, options }),
  }),
}));

const URL_LOCAL = "http://localhost:3202"; // never reached: fetch is stubbed
const COOKIE = "sb-localhost-auth-token"; // @supabase/ssr: sb-<first host label>-auth-token
const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
// Built at runtime (unsigned, HS256 header) so no token-shaped literal is committed.
const token = (exp: number) => [b64({ alg: "HS256", typ: "JWT" }), b64({ sub: "u1", role: "authenticated", aud: "authenticated", exp, iat: exp - 3600, email: "m@example.test", aal: "aal1", session_id: "s1" }), "unsigned"].join(".");
const user = { id: "u1", aud: "authenticated", role: "authenticated", email: "m@example.test", app_metadata: {}, user_metadata: {}, created_at: "2026-10-21T00:00:00Z" };
const session = (exp: number, refresh = "refresh-new") => ({ access_token: token(exp), refresh_token: refresh, token_type: "bearer", expires_in: exp - Math.floor(Date.now() / 1000), expires_at: exp, user });
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const gotrue = vi.fn(async (input: RequestInfo | URL) => {
  const url = String(input instanceof Request ? input.url : input);
  if (!url.startsWith(URL_LOCAL)) throw new Error(`unexpected fetch to ${url}`);
  if (url.includes("/auth/v1/token")) return json(session(Math.floor(Date.now() / 1000) + 3600));
  if (url.includes("/auth/v1/user")) return json(user);
  if (url.includes("/auth/v1/logout")) return new Response(null, { status: 204 });
  return json({ message: "not stubbed" }, 404);
});

beforeEach(() => {
  vi.resetModules();
  jar.cookies = [];
  jar.set = [];
  gotrue.mockClear();
  vi.stubGlobal("fetch", gotrue);
  vi.stubEnv("NEXT_PUBLIC_VENUE_DATA_SOURCE", "database");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", URL_LOCAL);
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "placeholder-anon-key");
});
afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

// Next calls a route handler with the incoming Request. /logout ignores it, but the tests pass a real one,
// so a regression to `NextResponse.redirect(new URL("/login", request.url))` fails on the Location
// assertion (absolute URL) instead of with a TypeError on a missing request.
type RouteHandler = (request: Request) => Promise<Response>;
const logoutRequest = () => new Request("https://venue.snatchitapp.com/logout", { method: "POST" });

const hostOnly = (options: Record<string, unknown>) => {
  expect(options.domain).toBeUndefined();
  expect(options.path).toBe("/");
  expect(options.sameSite).toBe("lax");
  expect(options.secure).toBe(true);
  expect(options.httpOnly).toBe(true);
};

describe("session cookies are host-only (no Domain attribute), Secure and HttpOnly", () => {
  it("sign-in through the server client writes auth cookies without a Domain", async () => {
    const { createSupabaseServerClient } = await import("@/lib/supabase/server");
    const sb = await createSupabaseServerClient();
    const { error } = await sb.auth.signInWithPassword({ email: "m@example.test", password: "placeholder" });
    expect(error).toBeNull();
    const auth = jar.set.filter((c) => c.name.startsWith(COOKIE));
    expect(auth.length).toBeGreaterThan(0);
    auth.forEach((c) => hostOnly(c.options));
  });

  it("a refresh in the proxy sets host-only cookies on the response (no Domain= in Set-Cookie)", async () => {
    const { refreshSession } = await import("@/lib/supabase/proxy");
    const expired = `base64-${b64(session(Math.floor(Date.now() / 1000) - 120, "refresh-old"))}`;
    const res = await refreshSession(new NextRequest("https://venue.snatchitapp.com/o/x/v/y/events", { headers: { cookie: `${COOKIE}=${expired}` } }));
    expect(gotrue.mock.calls.some(([u]) => String(u).includes("grant_type=refresh_token"))).toBe(true);
    const setCookies = res.headers.getSetCookie().filter((c) => c.startsWith(COOKIE));
    expect(setCookies.length).toBeGreaterThan(0);
    for (const c of setCookies) {
      expect(c).not.toMatch(/;\s*domain=/i);
      expect(c).toMatch(/;\s*path=\//i);
      expect(c).toMatch(/;\s*secure(;|$)/i);
      expect(c).toMatch(/;\s*httponly(;|$)/i);
      expect(c).toMatch(/;\s*samesite=lax/i);
    }
  });

  it("sign-out clears the cookies host-only too (a Domain mismatch would leave the session behind)", async () => {
    jar.cookies = [{ name: COOKIE, value: `base64-${b64(session(Math.floor(Date.now() / 1000) + 3600))}` }];
    const { POST } = await import("@/app/logout/route");
    const logout: RouteHandler = POST;
    await logout(logoutRequest());
    const cleared = jar.set.filter((c) => c.name.startsWith(COOKIE));
    expect(cleared.length).toBeGreaterThan(0);
    cleared.forEach((c) => {
      hostOnly(c.options);
      expect(c.value).toBe("");
    });
  });
});

describe("HttpOnly costs nothing: no browser code reads the session", () => {
  const files = (dir: string): string[] =>
    readdirSync(dir).flatMap((n) => {
      const p = join(dir, n);
      return statSync(p).isDirectory() ? files(p) : /\.(ts|tsx)$/.test(n) ? [p] : [];
    });
  const src = new URL("../src", import.meta.url).pathname;
  it("no browser Supabase client and no document.cookie anywhere in src/", () => {
    const hits = files(src).filter((f) => /createBrowserClient|document\.cookie/.test(readFileSync(f, "utf8")));
    expect(hits).toEqual([]);
  });
  it("no client component imports Supabase or the server client", () => {
    const client = files(src).filter((f) => /^\s*["']use client["']/m.test(readFileSync(f, "utf8")));
    expect(client.length).toBeGreaterThan(0);
    const hits = client.filter((f) => /@supabase\/|@\/lib\/supabase\//.test(readFileSync(f, "utf8")));
    expect(hits).toEqual([]);
  });
});

describe("redirects are relative", () => {
  it("POST /logout answers 303 with a relative Location: /login (no host in it)", async () => {
    const { POST } = await import("@/app/logout/route");
    const logout: RouteHandler = POST;
    const res = await logout(logoutRequest());
    expect(res.status).toBe(303);
    expect(res.headers.get("location")).toBe("/login");
  });
  it("sign-in returns to a relative path only (safeInternalPath), never a host", async () => {
    const { safeInternalPath } = await import("@/lib/auth/redirect");
    expect(safeInternalPath("/o/a/v/b/events", "/")).toBe("/o/a/v/b/events");
    for (const bad of ["https://venue.snatchitapp.com/x", "//admin.snatchitapp.com/x", "/\\evil.example"]) expect(safeInternalPath(bad, "/")).toBe("/");
  });
});

describe("no host is hard-coded", () => {
  const files = (dir: string): string[] =>
    readdirSync(dir).flatMap((n) => {
      const p = join(dir, n);
      return statSync(p).isDirectory() ? files(p) : /\.(ts|tsx|css|mjs|js)$/.test(n) ? [p] : [];
    });
  it("src/ contains no absolute http(s) URL", () => {
    const src = new URL("../src", import.meta.url).pathname;
    const hits = files(src).filter((f) => /https?:\/\//.test(readFileSync(f, "utf8")));
    expect(hits).toEqual([]);
  });
  it("the security headers (CSP included) name no host", async () => {
    const { default: config } = await import("../next.config");
    const rules = await config.headers!();
    const values = rules.flatMap((r) => r.headers.map((h) => h.value)).join("\n");
    expect(values).toContain("default-src 'self'");
    expect(values).toContain("connect-src 'self'");
    expect(values).not.toMatch(/https?:|\*\.|snatchitapp|vercel\.app|supabase/i);
  });
});

describe("transport headers", () => {
  const header = async (key: string) => {
    const { default: config } = await import("../next.config");
    const rules = await config.headers!();
    return rules.flatMap((r) => r.headers).find((h) => h.key.toLowerCase() === key.toLowerCase())?.value;
  };
  it("production sends Strict-Transport-Security with max-age only (no includeSubDomains, no preload)", async () => {
    expect(await header("Strict-Transport-Security")).toBe("max-age=63072000");
  });
  it("next dev sends no HSTS (as admin/next.config.ts)", async () => {
    vi.stubEnv("NODE_ENV", "development");
    expect(await header("Strict-Transport-Security")).toBeUndefined();
  });
  it("Permissions-Policy turns off the browser features the dashboard never uses (as admin)", async () => {
    expect(await header("Permissions-Policy")).toBe("camera=(), microphone=(), geolocation=(), payment=(), usb=()");
  });
});
