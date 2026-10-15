import { readFileSync } from "node:fs";
import path from "node:path";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Redirect audit (owner, 2026-10-15). The owner finished Stripe payout onboarding and landed on
// the legacy Expo export's /login (snatchitwebapp.vercel.app): Stripe's return/refresh URLs point
// at pages that need a session the returning browser doesn't have. Web now owns public
// /payout-return and /payout-refresh on the canonical origin (A repoints the secrets), a
// checkout whose session ended goes back to its own complete page after login, and Cancel on
// "Set new password" signs out this browser only.

const h = vi.hoisted(() => ({
  // eslint-disable-next-line @typescript-eslint/no-unused-vars -- typed so calls can be asserted with an argument
  signOut: vi.fn(async (_opts?: unknown) => ({ error: null as unknown })),
  redirect: vi.fn(),
  jar: [] as { name: string }[],
  deleted: [] as string[],
}));

vi.mock("server-only", () => ({}));
vi.mock("next/headers", () => ({
  cookies: async () => ({ getAll: () => h.jar, delete: (n: string) => void h.deleted.push(n), set: () => {} }),
  headers: async () => new Headers(),
}));
vi.mock("next/image", () => ({ default: () => null }));
vi.mock("next/link", () => ({
  default: ({ href, children, ...rest }: { href: string; children: unknown }) => createElement("a", { href, ...rest }, children as never),
}));
vi.mock("next/navigation", () => ({ redirect: h.redirect, useRouter: () => ({ push: () => {}, replace: () => {} }) }));
vi.mock("@/lib/payouts-actions", () => ({
  checkPayoutStatusAction: async () => ({ status: "connected" }),
  startPayoutOnboardingAction: async () => ({ status: "connected" }),
}));
vi.mock("@/lib/env", () => ({ SITE_URL: "https://app.example.test", SUPABASE_URL: "https://proj.supabase.test", SUPABASE_ANON_KEY: "anon" }));
vi.mock("@/lib/auth/email-links", () => ({ emailLinkAuth: () => ({}), requestEmailChange: async () => ({ error: null }) }));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: async () => ({ auth: { signOut: h.signOut } }) }));

import { PayoutHandoff } from "@/components/account/PayoutHandoff";
import { isMobileUserAgent } from "@/lib/payout-handoff";
import { checkoutLoginHref } from "@/lib/checkout-return";
import { decideProxyRedirect } from "@/lib/auth/proxy-logic";
import { safeInternalPath } from "@/lib/auth/redirect";
import { cancelPasswordResetAction } from "@/lib/auth/actions";
import { isSessionEnded, keptReturnQuery } from "@/lib/checkout-return";
import { payoutCheckOutcome } from "@/lib/payout-check";
import nextConfig from "../next.config";

const SRC = path.resolve(__dirname, "../src");
const read = (rel: string) => readFileSync(path.join(SRC, rel), "utf8");
const page = (kind: "return" | "refresh", signedIn: boolean, mobile: boolean) =>
  renderToStaticMarkup(createElement(PayoutHandoff, { kind, signedIn, mobile }));

const IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148";
const MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15";

beforeEach(() => {
  h.signOut.mockClear();
  h.redirect.mockClear();
  h.jar = [];
  h.deleted = [];
});

describe("payout return / refresh on the canonical origin", () => {
  it("both routes are public: the proxy never sends them to a login page", () => {
    for (const pathname of ["/payout-return", "/payout-refresh"]) {
      expect(decideProxyRedirect({ pathname, search: "", isAuthed: false, nextParam: null })).toEqual({ type: "none" });
    }
  });

  it("signed out on a phone (the app's in-app browser): open the app, or log in and come back to payouts", () => {
    const html = page("return", false, true);
    expect(html).toContain('href="snatchit://payout-return"');
    expect(html).toContain('href="/login?next=%2Faccount%2Fsettings"');
    expect(html).not.toContain("Checking payout status");
  });

  it("refresh hands off to the app's refresh route", () => {
    expect(page("refresh", false, true)).toContain('href="snatchit://payout-refresh"');
  });

  it("signed out on a desktop: no app link, log in is the way on", () => {
    const html = page("return", false, false);
    expect(html).not.toContain("snatchit://");
    expect(html).toContain('href="/login?next=%2Faccount%2Fsettings"');
  });

  it("signed in: the live status check and payout settings, never a login page or a claimed status", () => {
    const html = page("return", true, false);
    expect(html).toContain("Checking payout status");
    expect(html).toContain('href="/account/settings"');
    expect(html).not.toContain("/login");
    expect(html).not.toContain("snatchit://");
    expect(page("return", true, true)).toContain('href="snatchit://payout-return"');
  });

  it("no legacy or marketing host appears on these pages", () => {
    for (const html of [page("return", false, true), page("refresh", true, true)]) {
      expect(html).not.toMatch(/snatchitwebapp|snatchti\.com|vercel\.app|https?:\/\/snatchitapp\.com\/payout/);
    }
  });

  it("the app handoff is offered on phones and tablets only", () => {
    expect(isMobileUserAgent(IPHONE)).toBe(true);
    expect(isMobileUserAgent("Mozilla/5.0 (Linux; Android 15; Pixel 9)")).toBe(true);
    expect(isMobileUserAgent(MAC)).toBe(false);
    expect(isMobileUserAgent(null)).toBe(false);
  });

  it("a status is shown only when the check returned one without an error (never an unread 'Not connected')", () => {
    expect(payoutCheckOutcome({ status: "connected" })).toEqual({ kind: "status", status: "connected" });
    expect(payoutCheckOutcome({ status: "onboarding_required" })).toEqual({ kind: "status", status: "onboarding_required" });
    // getPayoutStatus answers an edge error as not_connected + error — that is a failed check
    expect(payoutCheckOutcome({ status: "not_connected", error: "Edge function returned 502" })).toEqual({ kind: "failed" });
    expect(payoutCheckOutcome({})).toEqual({ kind: "failed" });
    expect(payoutCheckOutcome(undefined)).toEqual({ kind: "failed" });
    expect(read("components/account/PayoutSetup.tsx")).toContain("payoutCheckOutcome(res)");
  });

  it("the signed-in heading claims nothing before the check answers", () => {
    expect(page("return", true, false)).not.toMatch(/checked with Stripe just now/);
  });

  it("both pages are thin wrappers over the handoff with their kind", () => {
    expect(read("app/payout-return/page.tsx")).toContain('kind="return"');
    expect(read("app/payout-refresh/page.tsx")).toContain('kind="refresh"');
  });
});

describe("checkout: a session that ended after payment comes back to its own complete page", () => {
  const LISTING = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1";

  it("login link carries only the PaymentIntent id, the status and the mode — never the client secret", () => {
    const href = checkoutLoginHref(LISTING, "pi_3QabcDEF12345678", "auction")!;
    expect(href.startsWith("/login?next=")).toBe(true);
    const next = decodeURIComponent(href.slice("/login?next=".length));
    expect(next).toBe(`/checkout/${LISTING}/complete?payment_intent=pi_3QabcDEF12345678&redirect_status=succeeded&mode=auction`);
    expect(href).not.toMatch(/secret/i);
    // and it survives the login page's own sanitizer unchanged
    expect(safeInternalPath(next, "/account")).toBe(next);
  });

  it.each([
    ["a non-UUID listing", "../../evil", "pi_3QabcDEF12345678"],
    ["no PaymentIntent", LISTING, null],
    ["a PaymentIntent with injected characters", LISTING, "pi_3Qabc&next=//evil.com"],
    ["a client secret instead of an id", LISTING, "pi_3QabcDEF12345678_secret_xyz"],
  ])("%s → no link", (_l, listing, pi) => {
    expect(checkoutLoginHref(listing as string, pi as string | null, "buy_now")).toBeNull();
  });

  it("only finalize's AUTH_REQUIRED is a session-ended state", () => {
    expect(isSessionEnded({ error: "AUTH_REQUIRED" })).toBe(true);
    expect(isSessionEnded({ error: "Payment could not be verified" })).toBe(false);
    expect(isSessionEnded({})).toBe(false);
    expect(isSessionEnded(null)).toBe(false);
  });

  it("the client secret leaves the address bar; what the page needs stays", () => {
    expect(keptReturnQuery("?payment_intent=pi_test&payment_intent_client_secret=zzz&redirect_status=succeeded&mode=auction")).toBe(
      "?payment_intent=pi_test&redirect_status=succeeded&mode=auction",
    );
    expect(keptReturnQuery("?payment_intent_client_secret=zzz&utm_source=x")).toBe("");
    expect(keptReturnQuery("")).toBe("");
  });

  it("the complete page sends no Referer and is never cached", async () => {
    const rules = await nextConfig.headers!();
    const rule = rules.find((r) => r.source === "/checkout/:id/complete");
    expect(rule?.headers).toEqual(
      expect.arrayContaining([
        { key: "Referrer-Policy", value: "no-referrer" },
        { key: "Cache-Control", value: "no-store" },
      ]),
    );
  });

  it("the complete page and the inline form show a login step, not the raw AUTH_REQUIRED code", () => {
    const complete = read("app/checkout/[id]/complete/page.tsx");
    expect(complete).toContain("if (isSessionEnded(result)) {");
    expect(complete).toContain("checkoutLoginHref(params.id, paymentIntentId, mode)");
    expect(complete).toContain("keptReturnQuery(window.location.search)");
    const form = read("components/checkout/PaymentForm.tsx");
    expect(form).toContain("if (isSessionEnded(result)) {");
    // The charged-but-unrecorded state renders before (and instead of) the form with its Pay button.
    const block = form.slice(form.indexOf("if (paidNeedsLogin) {"), form.indexOf("<form onSubmit"));
    expect(block).toContain("Log in to finish");
    expect(block).not.toContain('type="submit"');
  });
});

describe("Cancel on Set new password", () => {
  it("signs out THIS browser only and says the password didn't change", async () => {
    await cancelPasswordResetAction();
    expect(h.signOut).toHaveBeenCalledTimes(1);
    expect(h.signOut).toHaveBeenCalledWith({ scope: "local" });
    expect(h.redirect).toHaveBeenCalledWith("/login?reset=cancelled");
    expect(read("app/login/page.tsx")).toContain("Password not changed. You've been signed out on this browser.");
  });

  it("if Supabase can't sign out, this browser's auth cookies are cleared anyway (the note stays true)", async () => {
    h.signOut.mockResolvedValueOnce({ error: { status: 503, name: "AuthRetryableFetchError" } });
    h.jar = [{ name: "sb-proj-auth-token.0" }, { name: "sb-proj-auth-token.1" }, { name: "theme" }];
    await cancelPasswordResetAction();
    expect(h.deleted).toEqual(["sb-proj-auth-token.0", "sb-proj-auth-token.1"]);
    expect(h.redirect).toHaveBeenCalledWith("/login?reset=cancelled");
  });

  it("a normal Cancel leaves cookie clearing to signOut (no manual deletes)", async () => {
    h.jar = [{ name: "sb-proj-auth-token" }];
    await cancelPasswordResetAction();
    expect(h.deleted).toEqual([]);
  });

  it("only a reset link gets the sign-out Cancel; Password from settings just goes back", () => {
    expect(read("lib/auth/complete-confirm.ts")).toContain('route: "/reset-password?recovery=1"');
    const form = read("components/auth/ResetPasswordForm.tsx");
    expect(form).toContain("<form action={cancelPasswordResetAction}>");
    expect(form).toContain('href="/account/settings"');
    expect(read("app/reset-password/page.tsx")).toContain('sp.recovery === "1"');
  });

  it("the confirm page refreshes the server layout after storing the session (header shows signed in)", () => {
    const src = read("app/auth/confirm/page.tsx");
    const i = src.indexOf("router.replace(outcome.route);");
    expect(i).toBeGreaterThan(-1);
    expect(src.indexOf("router.refresh();", i)).toBeGreaterThan(i);
  });
});

describe("control: scope is what decides local vs every device (real auth-js)", () => {
  let urls: URL[] = [];
  beforeEach(() => {
    urls = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        urls.push(new URL(typeof input === "string" ? input : input instanceof URL ? input.href : input.url));
        return new Response(null, { status: 204 });
      }),
    );
  });
  afterEach(() => vi.unstubAllGlobals());

  it("signOut() defaults to global; signOut({ scope: 'local' }) does not", async () => {
    const { GoTrueClient } = await import("@supabase/auth-js");
    const mem = new Map<string, string>();
    const session = {
      access_token: "a.b.c",
      refresh_token: "r",
      expires_in: 3600,
      expires_at: Math.floor(Date.now() / 1000) + 3600,
      token_type: "bearer",
      user: { id: "u", aud: "authenticated", app_metadata: {}, user_metadata: {}, created_at: "" },
    };
    const make = () => {
      mem.set("sb-test-auth-token", JSON.stringify(session));
      return new GoTrueClient({
        url: "https://proj.supabase.test/auth/v1",
        storageKey: "sb-test-auth-token",
        storage: { getItem: (k) => mem.get(k) ?? null, setItem: (k, v) => void mem.set(k, v), removeItem: (k) => void mem.delete(k) },
        autoRefreshToken: false,
        persistSession: true,
      });
    };
    await make().signOut();
    await make().signOut({ scope: "local" });
    const scopes = urls.filter((u) => u.pathname.endsWith("/logout")).map((u) => u.searchParams.get("scope"));
    expect(scopes).toEqual(["global", "local"]);
  });
});

describe("Log in comes back to the page you were on (WEB-06)", () => {
  it("keeps the path and its filters", async () => {
    const { loginHrefFor } = await import("@/lib/auth/login-href");
    expect(loginHrefFor("/browse", "category=clubs&sort=price_asc")).toBe(`/login?next=${encodeURIComponent("/browse?category=clubs&sort=price_asc")}`);
    expect(loginHrefFor("/listing/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1", "")).toBe(
      `/login?next=${encodeURIComponent("/listing/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1")}`,
    );
    expect(loginHrefFor("/browse", "?q=club")).toBe(`/login?next=${encodeURIComponent("/browse?q=club")}`);
  });

  it("drops credential-like query keys (Stripe client secret, codes, tokens)", async () => {
    const { loginHrefFor } = await import("@/lib/auth/login-href");
    const href = loginHrefFor("/checkout/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1/complete", "payment_intent=pi_test&payment_intent_client_secret=zzz&redirect_status=succeeded&code=abc&access_token=t");
    const next = decodeURIComponent(href.slice("/login?next=".length));
    expect(next).toBe("/checkout/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1/complete?payment_intent=pi_test&redirect_status=succeeded");
    expect(href).not.toMatch(/secret|code=|token/i);
  });

  it("plain /login from auth pages and from home; never an external or auth destination", async () => {
    const { loginHrefFor } = await import("@/lib/auth/login-href");
    for (const p of ["/login", "/signup", "/forgot-password", "/reset-password", "/auth/confirm"]) expect(loginHrefFor(p, "next=%2Fsell")).toBe("/login");
    expect(loginHrefFor("/", "")).toBe("/login");
    expect(loginHrefFor("//evil.example", "")).toBe("/login");
    expect(loginHrefFor("/\\evil", "")).toBe("/login");
  });

  it("the header and the save / bid / buy buttons use it", () => {
    const header = read("components/site/Header.tsx");
    expect(header).toContain("<LoginLink className={LOGIN_LINK_CLS} />");
    expect(read("components/site/LoginLink.tsx")).toContain("loginHrefFor(pathname, searchParams.toString())");
    for (const f of ["components/SaveButton.tsx", "components/listing/BuyNowButton.tsx", "components/listing/BidPanel.tsx"]) {
      expect(read(f), f).toContain("router.push(loginHrefFor(pathname, window.location.search));");
    }
  });
});
