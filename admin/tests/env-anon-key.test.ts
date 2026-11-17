import { afterEach, describe, expect, it, vi } from "vitest";

/**
 * F3 (OC-14) — NEXT_PUBLIC_SUPABASE_ANON_KEY is inlined into the browser
 * bundle. A service_role JWT or an sb_secret_ key placed there would hand
 * every visitor a key that bypasses RLS. env.ts must refuse both at startup,
 * in every environment, without printing the key. All keys below are
 * synthetic: unsigned, made up here, valid for nothing.
 */
const b64url = (o: unknown) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (payload: Record<string, unknown>) => `${b64url({ alg: "HS256", typ: "JWT" })}.${b64url(payload)}.c3ludGhldGljLW5vdC1hLXNpZ25hdHVyZQ`;

const SERVICE_JWT = jwt({ iss: "supabase", ref: "synthetic-test-ref", role: "service_role", iat: 1756000000, exp: 2071360000 });
// Real payloads often encode to base64url's own alphabet ('-' and '_'); this one does, on purpose.
const SERVICE_JWT_URLSAFE = jwt({ iss: "supabase", ref: "~~~~??", role: "service_role" });
const ANON_JWT = jwt({ iss: "supabase", ref: "synthetic-test-ref", role: "anon", iat: 1756000000, exp: 2071360000 });
const AUTHED_JWT = jwt({ iss: "supabase", ref: "synthetic-test-ref", role: "authenticated", sub: "u" });
const SECRET = "sb_secret_SYNTHETICtestvalue0000000000000000";
const PUBLISHABLE = "sb_publishable_SYNTHETICtestvalue00000000000";

async function loadEnv(env: Record<string, string | undefined>) {
  vi.resetModules();
  for (const [k, v] of Object.entries(env)) vi.stubEnv(k, v);
  return import("@/lib/env");
}

async function refusal(env: Record<string, string | undefined>): Promise<Error | null> {
  try {
    await loadEnv(env);
    return null;
  } catch (e) {
    return e as Error;
  }
}

const prod = { NODE_ENV: "production", NEXT_PUBLIC_SUPABASE_URL: "https://synthetic.supabase.co", NEXT_PUBLIC_SITE_URL: "https://admin.snatchitapp.com" };

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("F3 — env.ts refuses privileged keys in NEXT_PUBLIC_SUPABASE_ANON_KEY", () => {
  it("a legacy JWT whose role is service_role is refused, and the key is not echoed", async () => {
    for (const nodeEnv of [{}, prod]) {
      const e = await refusal({ ...nodeEnv, NEXT_PUBLIC_SUPABASE_ANON_KEY: SERVICE_JWT });
      expect(e, JSON.stringify(nodeEnv)).toBeInstanceOf(Error);
      expect(e!.message).toMatch(/NEXT_PUBLIC_SUPABASE_ANON_KEY/);
      expect(e!.message).toMatch(/service_role/);
      for (const part of SERVICE_JWT.split(".")) expect(e!.message).not.toContain(part);
    }
  });

  it("a service_role JWT whose payload uses base64url's - and _ is still decoded and refused", async () => {
    expect(SERVICE_JWT_URLSAFE.split(".")[1]).toMatch(/-/);
    expect(SERVICE_JWT_URLSAFE.split(".")[1]).toMatch(/_/);
    const e = await refusal({ NEXT_PUBLIC_SUPABASE_ANON_KEY: SERVICE_JWT_URLSAFE });
    expect(e).toBeInstanceOf(Error);
    expect(e!.message).toMatch(/service_role/);
  });

  it("an sb_secret_ key is refused (also with stray whitespace), and the key is not echoed", async () => {
    for (const key of [SECRET, `  ${SECRET}\n`]) {
      for (const nodeEnv of [{}, prod]) {
        const e = await refusal({ ...nodeEnv, NEXT_PUBLIC_SUPABASE_ANON_KEY: key });
        expect(e, JSON.stringify(nodeEnv)).toBeInstanceOf(Error);
        expect(e!.message).toMatch(/sb_secret_/);
        expect(e!.message).not.toContain(SECRET);
        expect(e!.message).not.toContain(SECRET.slice("sb_secret_".length));
      }
    }
  });

  it("a JWT for any role other than anon is refused too", async () => {
    const e = await refusal({ NEXT_PUBLIC_SUPABASE_ANON_KEY: AUTHED_JWT });
    expect(e).toBeInstanceOf(Error);
    expect(e!.message).not.toContain(AUTHED_JWT.split(".")[1]);
  });

  it("an anon JWT, an sb_publishable_ key, the CI placeholder and no key at all pass (controls)", async () => {
    for (const key of [ANON_JWT, PUBLISHABLE, "ci-placeholder-anon-key", undefined]) {
      expect(await refusal({ NEXT_PUBLIC_SUPABASE_ANON_KEY: key }), String(key)).toBeNull();
    }
    for (const key of [ANON_JWT, PUBLISHABLE]) {
      const env = await loadEnv({ ...prod, NEXT_PUBLIC_SUPABASE_ANON_KEY: key });
      expect(env.SUPABASE_ANON_KEY).toBe(key);
    }
  });
});

describe("F3 — anonKeyProblem (pure rule)", () => {
  it("classifies keys without returning them", async () => {
    const { anonKeyProblem } = await import("@/lib/env-policy");
    expect(anonKeyProblem(SERVICE_JWT)).toMatch(/service_role/);
    expect(anonKeyProblem(SECRET)).toMatch(/sb_secret_/);
    expect(anonKeyProblem(AUTHED_JWT)).toMatch(/not "anon"/);
    expect(anonKeyProblem(ANON_JWT)).toBeNull();
    expect(anonKeyProblem(PUBLISHABLE)).toBeNull();
    expect(anonKeyProblem(null)).toBeNull();
    // Not a decodable JWT and not a secret prefix: not ours to judge (the CI placeholder is one).
    expect(anonKeyProblem("a.b.c")).toBeNull();
    for (const k of [SERVICE_JWT, SECRET, AUTHED_JWT]) expect(anonKeyProblem(k)).not.toContain(k);
  });
});
