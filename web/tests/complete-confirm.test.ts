import { describe, expect, it, vi } from "vitest";
import { GoTrueClient } from "@supabase/auth-js";
import { completeConfirm } from "@/lib/auth/complete-confirm";
import { readConfirmLink } from "@/lib/auth/confirm-link";

// What /auth/confirm does with an emailed link, run through the real auth-js client configured
// like the web's browser client (@supabase/ssr forces flowType "pkce"). Only the network is
// mocked. The cross-device case is the owner's: the link was opened in a browser that never
// requested it, so nothing but the link itself is available.

const URL_ = "https://proj.supabase.test/auth/v1";
const b64u = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = (sub: string) => `${b64u({ alg: "HS256", typ: "JWT" })}.${b64u({ sub, exp: Math.floor(Date.now() / 1000) + 3600, aud: "authenticated", role: "authenticated" })}.sig`;

function freshBrowser(userResponse: () => Response) {
  const store = new Map<string, string>();
  const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
    const u = String(input);
    if (u.endsWith("/user")) return userResponse();
    return new Response("{}", { status: 404 });
  });
  const auth = new GoTrueClient({
    url: URL_,
    headers: { apikey: "anon" },
    flowType: "pkce",
    persistSession: true,
    autoRefreshToken: false,
    detectSessionInUrl: false,
    storageKey: "sb-test-auth-token",
    storage: { getItem: (k) => store.get(k) ?? null, setItem: (k, v) => void store.set(k, v), removeItem: (k) => void store.delete(k) },
    fetch: fetchMock as unknown as typeof fetch,
  });
  return { auth, store, fetchMock };
}

const okUser = () => new Response(JSON.stringify({ id: "user-1", aud: "authenticated", email: "person@example.test" }), { status: 200 });
const fragment = (type: string) => `#access_token=${jwt("user-1")}&expires_in=3600&refresh_token=rt-1&token_type=bearer&type=${type}`;

describe("an emailed link opened on another device (no prior browser state)", () => {
  it("password reset lands on Set new password, with the session stored", async () => {
    const { auth, store } = freshBrowser(okUser);
    const link = readConfirmLink(new URLSearchParams("next=%2Freset-password"), fragment("recovery"));
    expect(link.kind).toBe("implicit");
    const out = await completeConfirm(link, auth, "/reset-password");
    expect(out).toEqual({ status: "signed_in", route: "/reset-password" });
    expect([...store.keys()].some((k) => k.startsWith("sb-test-auth-token"))).toBe(true);
  });

  it("sign-up confirmation goes to next (same-origin only)", async () => {
    const { auth } = freshBrowser(okUser);
    const link = readConfirmLink(new URLSearchParams("next=%2Fsell"), fragment("signup"));
    expect(await completeConfirm(link, auth, "/sell")).toEqual({ status: "signed_in", route: "/sell" });
    const { auth: auth2 } = freshBrowser(okUser);
    expect(await completeConfirm(readConfirmLink(new URLSearchParams(""), fragment("signup")), auth2, "https://evil.example/x")).toEqual({
      status: "signed_in",
      route: "/account",
    });
  });

  it("email change goes to settings", async () => {
    const { auth } = freshBrowser(okUser);
    const out = await completeConfirm(readConfirmLink(new URLSearchParams(""), fragment("email_change")), auth, null);
    expect(out).toEqual({ status: "signed_in", route: "/account/settings?email_changed=1" });
  });

  it("a token the server rejects signs nobody in and stores nothing", async () => {
    const { auth, store } = freshBrowser(() => new Response(JSON.stringify({ msg: "invalid JWT" }), { status: 401 }));
    const out = await completeConfirm(readConfirmLink(new URLSearchParams(""), fragment("recovery")), auth, "/reset-password");
    expect(out).toEqual({ status: "invalid" });
    expect([...store.keys()].some((k) => k.startsWith("sb-test-auth-token") && !k.endsWith("code-verifier"))).toBe(false);
  });

  it("used or expired links (GoTrue's error redirect) are invalid", async () => {
    const { auth } = freshBrowser(okUser);
    const link = readConfirmLink(new URLSearchParams(""), "#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired");
    expect(link.kind).toBe("none");
    expect(await completeConfirm(link, auth, null)).toEqual({ status: "invalid" });
  });

  it("the OLD behaviour, for the record: a PKCE ?code= opened in a browser without the verifier cannot complete", async () => {
    const { auth, fetchMock } = freshBrowser(okUser);
    const link = readConfirmLink(new URLSearchParams("next=%2Freset-password&code=abc"), "");
    expect(link.kind).toBe("pkce");
    expect(await completeConfirm(link, auth, "/reset-password")).toEqual({ status: "invalid" });
    expect(fetchMock.mock.calls.some(([u]) => String(u).includes("/token"))).toBe(false); // no exchange is even attempted
  });

  it("first confirmation of a two-step email change is not reported as expired", async () => {
    const { auth } = freshBrowser(okUser);
    const hash = readConfirmLink(new URLSearchParams(""), "#message=Confirmation+link+accepted.+Please+proceed+to+confirm+link+sent+to+the+other+email");
    const query = readConfirmLink(new URLSearchParams("message=Confirmation%20link%20accepted"), "");
    expect(hash.kind).toBe("message");
    expect(query.kind).toBe("message");
    expect(await completeConfirm(hash, auth, null)).toEqual({ status: "first_confirmation" });
    expect(readConfirmLink(new URLSearchParams(""), "#message=x&error=access_denied").kind).toBe("none");
  });
});
