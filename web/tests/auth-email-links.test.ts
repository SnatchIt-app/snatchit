import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Regression for the owner's iPhone "Link expired" (2026-10-14). The web's SSR auth client is
// PKCE-only, so every auth email it sent asked GoTrue for a PKCE link (code_challenge in the
// request). That link only completes in the browser that requested it; opened from Gmail on
// another device or browser, GoTrue verified the token and nothing could exchange the ?code=.
// The fix sends these emails on the implicit flow. The decisive, testable fact is the request:
// no code_challenge means GoTrue's link returns the session itself, usable on any device.

vi.mock("server-only", () => ({}));
vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://proj.supabase.test");
vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-test-key");
vi.stubEnv("NEXT_PUBLIC_SITE_URL", "https://app.example.test");

type Call = { url: URL; method: string; headers: Headers; body: Record<string, unknown> };
let calls: Call[] = [];

beforeEach(() => {
  calls = [];
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      const body = init?.body ? JSON.parse(String(init.body)) : {};
      calls.push({ url, method: (init?.method ?? "GET").toUpperCase(), headers: new Headers(init?.headers), body });
      const payload = url.pathname.endsWith("/signup") ? { id: "u1", email: body.email, identities: [{}] } : {};
      return new Response(JSON.stringify(payload), { status: 200, headers: { "Content-Type": "application/json" } });
    }),
  );
});
afterEach(() => vi.unstubAllGlobals());

const REDIRECT = "https://app.example.test/auth/confirm?next=%2Freset-password";

describe("auth emails are requested on the implicit flow (work on any device)", () => {
  it("password reset: no PKCE challenge, redirect_to kept", async () => {
    const { emailLinkAuth } = await import("@/lib/auth/email-links");
    await emailLinkAuth().resetPasswordForEmail("person@example.test", { redirectTo: REDIRECT });
    const c = calls.find((x) => x.url.pathname === "/auth/v1/recover")!;
    expect(c).toBeDefined();
    expect(c.url.searchParams.get("redirect_to")).toBe(REDIRECT);
    expect(c.body.email).toBe("person@example.test");
    // supabase-js sends the key with null on the implicit flow; GoTrue treats an empty challenge
    // as "not PKCE" and returns the session in the link instead of a ?code=.
    expect(c.body.code_challenge ?? null).toBeNull();
    expect(c.body.code_challenge_method ?? null).toBeNull();
  });

  it("control: a PKCE client sends a challenge for the same call (the test can tell them apart)", async () => {
    const { createClient } = await import("@supabase/supabase-js");
    const mem = new Map<string, string>();
    const pkce = createClient("https://proj.supabase.test", "anon-test-key", {
      auth: {
        flowType: "pkce",
        persistSession: true,
        storage: { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => void mem.set(k, v), removeItem: (k) => void mem.delete(k) },
      },
    }).auth;
    await pkce.resetPasswordForEmail("person@example.test", { redirectTo: REDIRECT });
    const c = calls.find((x) => x.url.pathname === "/auth/v1/recover")!;
    expect(typeof c.body.code_challenge).toBe("string");
    expect(String(c.body.code_challenge).length).toBeGreaterThan(20);
  });

  it("sign-up confirmation: no PKCE challenge, emailRedirectTo kept", async () => {
    const { emailLinkAuth } = await import("@/lib/auth/email-links");
    await emailLinkAuth().signUp({
      email: "new@example.test",
      password: "long-enough-pass",
      options: { emailRedirectTo: "https://app.example.test/auth/confirm?next=%2Faccount" },
    });
    const c = calls.find((x) => x.url.pathname === "/auth/v1/signup")!;
    expect(c).toBeDefined();
    expect(c.url.searchParams.get("redirect_to")).toBe("https://app.example.test/auth/confirm?next=%2Faccount");
    expect(c.body.code_challenge ?? null).toBeNull();
  });

  it("email change: PUT /user with the person's token, no PKCE challenge, no session rotation", async () => {
    const { requestEmailChange } = await import("@/lib/auth/email-links");
    const out = await requestEmailChange("access-jwt", "next@example.test", "https://app.example.test/auth/confirm");
    expect(out.error).toBeNull();
    expect(calls).toHaveLength(1);
    const c = calls[0];
    expect(c.method).toBe("PUT");
    expect(c.url.pathname).toBe("/auth/v1/user");
    expect(c.url.searchParams.get("redirect_to")).toBe("https://app.example.test/auth/confirm");
    expect(c.headers.get("authorization")).toBe("Bearer access-jwt");
    expect(c.headers.get("apikey")).toBe("anon-test-key");
    expect(c.body).toEqual({ email: "next@example.test" });
  });

  it("email change on a network failure returns an error instead of throwing", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => { throw new TypeError("fetch failed"); }));
    const { requestEmailChange } = await import("@/lib/auth/email-links");
    const out = await requestEmailChange("t", "x@example.test", "https://app.example.test/auth/confirm");
    expect(out.error).toMatchObject({ status: 0 });
  });

  it("email change surfaces GoTrue's error message", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response(JSON.stringify({ msg: "Email rate limit exceeded" }), { status: 429 })));
    const { requestEmailChange } = await import("@/lib/auth/email-links");
    const out = await requestEmailChange("t", "x@example.test", "https://app.example.test/auth/confirm");
    expect(out.error).toMatchObject({ message: "Email rate limit exceeded", status: 429 });
  });
});
