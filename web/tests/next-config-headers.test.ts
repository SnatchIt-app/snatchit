import { afterEach, describe, expect, it, vi } from "vitest";

/**
 * next.config.ts gained a local-preview allowance (SNATCHIT_LOCAL_HARNESS).
 * These pin that, without the flag — or on Vercel, or with a non-loopback or
 * https URL — the security headers and image rules are exactly what they were
 * before the change (the CSP literal below is the pre-change output).
 */

const ENV_KEYS = ["SNATCHIT_LOCAL_HARNESS", "VERCEL", "NEXT_PUBLIC_SUPABASE_URL"] as const;
const saved = Object.fromEntries(ENV_KEYS.map((k) => [k, process.env[k]]));

afterEach(() => {
  for (const k of ENV_KEYS) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
  vi.resetModules();
});

async function load(env: Partial<Record<(typeof ENV_KEYS)[number], string>>) {
  for (const k of ENV_KEYS) delete process.env[k];
  Object.assign(process.env, env);
  vi.resetModules();
  const mod = await import("../next.config");
  const config = mod.default;
  const rules = await config.headers!();
  const csp = rules[0].headers.find((h) => h.key === "Content-Security-Policy")!.value;
  return { config, csp };
}

const PRODUCTION_CSP =
  "default-src 'self'; script-src 'self' 'unsafe-inline' https://js.stripe.com; style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' data: blob: https://hqycwntpfoztoinemqns.supabase.co; font-src 'self'; " +
  "connect-src 'self' https://hqycwntpfoztoinemqns.supabase.co wss://hqycwntpfoztoinemqns.supabase.co " +
  "https://*.ingest.sentry.io https://*.ingest.us.sentry.io https://*.ingest.de.sentry.io https://api.stripe.com; " +
  "frame-src https://js.stripe.com https://hooks.stripe.com; object-src 'none'; base-uri 'self'; form-action 'self'; " +
  "frame-ancestors 'none'; upgrade-insecure-requests";

describe("next.config local harness allowance", () => {
  it("leaves the production CSP and image rules unchanged without the flag", async () => {
    const { config, csp } = await load({ NEXT_PUBLIC_SUPABASE_URL: "https://hqycwntpfoztoinemqns.supabase.co" });
    expect(csp).toBe(PRODUCTION_CSP);
    expect(config.images?.remotePatterns).toHaveLength(1);
    expect(config.images).not.toHaveProperty("dangerouslyAllowLocalIP");
  });

  it("ignores the flag on Vercel", async () => {
    const { config, csp } = await load({ SNATCHIT_LOCAL_HARNESS: "1", VERCEL: "1", NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:3222" });
    expect(csp).not.toContain("http://127.0.0.1:3222");
    expect(csp).not.toContain("ws://127.0.0.1:3222");
    expect(config.images).not.toHaveProperty("dangerouslyAllowLocalIP");
  });

  it("ignores the flag for an https or non-loopback URL", async () => {
    for (const url of ["https://127.0.0.1:3222", "http://example.test:3222", "http://10.0.0.5:3222"]) {
      const { config, csp } = await load({ SNATCHIT_LOCAL_HARNESS: "1", NEXT_PUBLIC_SUPABASE_URL: url });
      expect(csp).not.toMatch(/ http:\/\//);
      expect(config.images).not.toHaveProperty("dangerouslyAllowLocalIP");
    }
  });

  it("allows exactly the loopback harness origin when the flag is set", async () => {
    const { config, csp } = await load({ SNATCHIT_LOCAL_HARNESS: "1", NEXT_PUBLIC_SUPABASE_URL: "http://127.0.0.1:3222" });
    expect(csp).toContain("img-src 'self' data: blob: https://hqycwntpfoztoinemqns.supabase.co https://127.0.0.1 http://127.0.0.1:3222;");
    expect(csp).toMatch(/connect-src [^;]* http:\/\/127\.0\.0\.1:3222 ws:\/\/127\.0\.0\.1:3222;/);
    expect(config.images?.remotePatterns).toContainEqual({
      protocol: "http",
      hostname: "127.0.0.1",
      port: "3222",
      pathname: "/storage/v1/object/public/**",
    });
    expect(config.images?.dangerouslyAllowLocalIP).toBe(true);
  });
});
