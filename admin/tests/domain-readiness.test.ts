import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

/**
 * F5 — readiness for https://admin.snatchitapp.com.
 *
 * 1. Session cookies are host-only. admin., venue. and the consumer web app
 *    will be siblings under snatchitapp.com; a cookie with
 *    Domain=.snatchitapp.com would be sent to all of them. Nothing in the
 *    console passes a cookie domain to @supabase/ssr, and every cookie the
 *    library hands back is written without one.
 * 2. On a Vercel production deploy NEXT_PUBLIC_SITE_URL must be the console's
 *    own origin: admin.snatchitapp.com, or snatchit-admin.vercel.app during
 *    the transition.
 * 3. The CSP and headers carry no host-specific value for the console itself.
 */
const ssr = vi.hoisted(() => ({
  serverCalls: [] as { url: string; key: string; options: Record<string, unknown> }[],
  browserCalls: [] as { url: string; key: string; options: Record<string, unknown> | undefined }[],
  claims: { sub: "f0000000-0000-4000-8000-0000000000a1", aal: "aal2" } as Record<string, unknown>,
  cookieWrites: [] as { name: string; value: string; options: Record<string, unknown> }[],
}));

vi.mock("server-only", () => ({}));
vi.mock("@supabase/ssr", () => ({
  createServerClient: (url: string, key: string, options: Record<string, unknown>) => {
    ssr.serverCalls.push({ url, key, options });
    return {
      auth: {
        getClaims: async () => {
          // What @supabase/ssr does on a refresh: hand the new cookies to setAll.
          // A domain here must not survive into the response.
          const cookies = options.cookies as { setAll: (c: unknown[], h: Record<string, string>) => void };
          cookies.setAll([{ name: "sb-test-auth-token", value: "synthetic", options: { path: "/", sameSite: "lax", maxAge: 60, domain: ".snatchitapp.com" } }], {});
          return { data: { claims: ssr.claims }, error: null };
        },
      },
    };
  },
  createBrowserClient: (url: string, key: string, options?: Record<string, unknown>) => {
    ssr.browserCalls.push({ url, key, options });
    return {};
  },
}));
vi.mock("next/headers", () => ({
  cookies: async () => ({
    getAll: () => [],
    set: (name: string, value: string, options: Record<string, unknown>) => ssr.cookieWrites.push({ name, value, options }),
  }),
}));

const env = { NEXT_PUBLIC_SUPABASE_URL: "https://synthetic.supabase.co", NEXT_PUBLIC_SUPABASE_ANON_KEY: "sb_publishable_SYNTHETICtestvalue00000000000" };

beforeEach(() => {
  vi.resetModules();
  for (const [k, v] of Object.entries(env)) vi.stubEnv(k, v);
  ssr.serverCalls.length = 0;
  ssr.browserCalls.length = 0;
  ssr.cookieWrites.length = 0;
});
afterEach(() => {
  vi.unstubAllEnvs();
});

const noDomain = (o: Record<string, unknown> | undefined) => !o || !("domain" in o) || o.domain === undefined;

describe("F5 — Supabase session cookies are host-only", () => {
  it("server client: no cookieOptions.domain, and a domain handed to setAll is not written", async () => {
    const { createSupabaseServerClient } = await import("@/lib/supabase/server");
    const client = await createSupabaseServerClient();
    expect(ssr.serverCalls).toHaveLength(1);
    expect(noDomain(ssr.serverCalls[0].options.cookieOptions as Record<string, unknown> | undefined)).toBe(true);
    await (client as unknown as { auth: { getClaims: () => Promise<unknown> } }).auth.getClaims();
    expect(ssr.cookieWrites).toHaveLength(1);
    expect(ssr.cookieWrites[0].options).toEqual({ path: "/", sameSite: "lax", maxAge: 60 });
  });

  it("proxy client: no cookieOptions.domain, and the refreshed Set-Cookie has no Domain attribute", async () => {
    const { NextRequest } = await import("next/server");
    const { updateSession } = await import("@/lib/supabase/proxy");
    const res = await updateSession(new NextRequest("https://admin.snatchitapp.com/orders"));
    expect(ssr.serverCalls).toHaveLength(1);
    expect(noDomain(ssr.serverCalls[0].options.cookieOptions as Record<string, unknown> | undefined)).toBe(true);
    const setCookie = res.headers.get("set-cookie") ?? "";
    expect(setCookie).toContain("sb-test-auth-token=synthetic");
    expect(setCookie.toLowerCase()).not.toContain("domain=");
    expect(res.cookies.get("sb-test-auth-token")?.domain).toBeUndefined();
  });

  it("browser client (MFA flow): no cookieOptions.domain", async () => {
    const { getSupabaseBrowserClient } = await import("@/lib/supabase/client");
    getSupabaseBrowserClient();
    expect(ssr.browserCalls).toHaveLength(1);
    expect(noDomain(ssr.browserCalls[0].options?.cookieOptions as Record<string, unknown> | undefined)).toBe(true);
  });

  it("hostOnlyCookie drops domain and keeps everything else", async () => {
    const { hostOnlyCookie } = await import("@/lib/supabase/cookie-options");
    expect(hostOnlyCookie({ domain: ".snatchitapp.com", path: "/", httpOnly: false, sameSite: "lax", secure: true, maxAge: 5 })).toEqual({ path: "/", httpOnly: false, sameSite: "lax", secure: true, maxAge: 5 });
    expect(hostOnlyCookie(undefined)).toEqual({});
  });
});

const PROD = { NODE_ENV: "production", NEXT_PUBLIC_VERCEL_ENV: "production", NEXT_PUBLIC_ENV_LABEL: "production" };

async function boot(siteUrl: string, extra: Record<string, string> = PROD): Promise<Error | null> {
  vi.resetModules();
  for (const [k, v] of Object.entries({ ...extra, NEXT_PUBLIC_SITE_URL: siteUrl })) vi.stubEnv(k, v);
  try {
    await import("@/lib/env");
    return null;
  } catch (e) {
    return e as Error;
  }
}

describe("F5 — production NEXT_PUBLIC_SITE_URL must be the console's own host", () => {
  it("accepts admin.snatchitapp.com and the transition host snatchit-admin.vercel.app (controls)", async () => {
    for (const url of ["https://admin.snatchitapp.com", "https://admin.snatchitapp.com/", "https://snatchit-admin.vercel.app", "https://ADMIN.snatchitapp.com"]) {
      expect(await boot(url), url).toBeNull();
    }
  });

  it("refuses any other host, a port, credentials, or plain http", async () => {
    for (const url of [
      "https://venue.snatchitapp.com",
      "https://snatchitapp.com",
      "https://www.snatchitapp.com",
      "https://admin.snatchitapp.com.evil.example",
      "https://evil.example/admin.snatchitapp.com",
      "https://snatchit-admin-git-main-gnvprod.vercel.app",
      "https://admin.snatchitapp.com:8443",
      "https://user:pass@admin.snatchitapp.com",
      "http://admin.snatchitapp.com",
      "https://localhost",
      "not a url",
    ]) {
      const e = await boot(url);
      expect(e, url).toBeInstanceOf(Error);
      expect(e!.message, url).toMatch(/NEXT_PUBLIC_SITE_URL/);
    }
  });

  it("the refusal shows the host, never the raw value (it could carry credentials)", async () => {
    const e = await boot("https://operator:hunter2-synthetic@admin.snatchitapp.com");
    expect(e!.message).toContain('host "admin.snatchitapp.com"');
    expect(e!.message).not.toContain("hunter2-synthetic");
    expect(e!.message).not.toContain("operator:");
  });

  it("preview and local builds are not held to the production host list", async () => {
    expect(await boot("https://snatchit-admin-abc123.vercel.app", { NODE_ENV: "production", NEXT_PUBLIC_VERCEL_ENV: "preview", NEXT_PUBLIC_ENV_LABEL: "staging" })).toBeNull();
    expect(await boot("http://localhost:3200", { NODE_ENV: "production" })).toBeNull();
  });

  it("the allowlist is exactly the two documented hosts", async () => {
    const { PRODUCTION_SITE_HOSTS } = await import("@/lib/env-policy");
    expect(PRODUCTION_SITE_HOSTS).toEqual(["admin.snatchitapp.com", "snatchit-admin.vercel.app"]);
  });
});

describe("F5 — CSP and headers are host-agnostic for the console itself", () => {
  it("form-action and frame-ancestors are origin-relative; nothing names a console host", async () => {
    vi.stubEnv("NODE_ENV", "production");
    const { default: config } = await import("../next.config");
    const rules = await config.headers!();
    const headers = Object.fromEntries(rules[0].headers.map((h) => [h.key, h.value]));
    const csp = headers["Content-Security-Policy"].split(";").map((d) => d.trim());
    expect(rules[0].source).toBe("/(.*)");
    expect(csp).toContain("form-action 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("base-uri 'self'");
    expect(csp.find((d) => d.startsWith("connect-src"))).toMatch(/^connect-src 'self' /);
    const all = JSON.stringify(headers);
    for (const host of ["snatchitapp.com", "vercel.app", "localhost"]) expect(all, host).not.toContain(host);
    expect(headers["X-Frame-Options"]).toBe("DENY");
    // Server Actions stay same-origin only (Next's default when allowedOrigins is unset).
    expect((config as { experimental?: { serverActions?: { allowedOrigins?: string[] } } }).experimental?.serverActions?.allowedOrigins).toBeUndefined();
  });
});
