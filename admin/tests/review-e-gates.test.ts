import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * E-L3 — four gates whose planted mutants survived the suite (independent
 * review of #121): requireOperator's aal2 redirect, the founder-only money
 * permissions, the OrderActions canRelease/canRefund props, and the proxy
 * matcher. Each test here was checked to fail with its gate removed; the
 * counts are in the commit message.
 */
const mocks = vi.hoisted(() => ({ callOps: vi.fn(), getClaims: vi.fn() }));

class Redirect extends Error {
  constructor(public path: string) {
    super(`NEXT_REDIRECT ${path}`);
  }
}

vi.mock("server-only", () => ({}));
vi.mock("next/navigation", () => ({
  redirect: (path: string) => {
    throw new Redirect(path);
  },
  notFound: () => {
    throw new Error("notFound");
  },
  usePathname: () => "/",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: async () => ({ auth: { getClaims: mocks.getClaims } }) }));
vi.mock("@/lib/supabase/proxy", () => ({ updateSession: vi.fn() }));

import { requireOperator } from "@/lib/auth/session";
import { allowedRoles, canRequest } from "@/lib/permissions";
import { OrderActions } from "@/components/orders/OrderActions";
import { config as proxyConfig } from "@/proxy";
import type { OperatorRole, OrderDetail } from "@/lib/types";

const USER = "b0000000-0000-4000-8000-0000000000e3";
const PAY = "9a900000-0000-4000-8000-0000000000e3";
const TR = "7a000000-0000-4000-8000-0000000000e3";

beforeEach(() => {
  mocks.callOps.mockReset();
  mocks.getClaims.mockReset();
});

// ---------------------------------------------------------------------------

async function operator({ signedIn = true, aal, whoami }: { signedIn?: boolean; aal?: string; whoami?: unknown }) {
  mocks.getClaims.mockResolvedValue(signedIn ? { data: { claims: { sub: USER, email: "x@example.test", ...(aal === undefined ? {} : { aal }) } }, error: null } : { data: null, error: null });
  mocks.callOps.mockImplementation(async (fn: string) => (fn === "whoami" && whoami ? whoami : { ok: false, kind: "error", message: `unexpected ${fn}` }));
  try {
    return { operator: await requireOperator(), redirect: null as string | null };
  } catch (e) {
    if (e instanceof Redirect) return { operator: null, redirect: e.path };
    throw e;
  }
}

describe("E-L3a — requireOperator sends a verified aal1 session to /mfa before asking the database anything", () => {
  const admin = { ok: true, data: { user_id: USER, role: "platform_admin", aal: "aal2" } };

  it("aal1 → /mfa, and ops.whoami is not called", async () => {
    const r = await operator({ aal: "aal1", whoami: admin });
    expect(r.redirect).toBe("/mfa");
    expect(mocks.callOps).not.toHaveBeenCalled();
  });

  it("a session with no aal claim, or an unknown one, is not aal2 → /mfa", async () => {
    for (const aal of [undefined, "aal3", "AAL2", ""]) {
      expect((await operator({ aal, whoami: admin })).redirect, String(aal)).toBe("/mfa");
    }
    expect(mocks.callOps).not.toHaveBeenCalled();
  });

  it("no verified session → /login, nothing asked of the database", async () => {
    expect((await operator({ signedIn: false, whoami: admin })).redirect).toBe("/login");
    expect(mocks.callOps).not.toHaveBeenCalled();
  });

  it("control: aal2 + whoami platform_admin → the operator, with the role from the database", async () => {
    const r = await operator({ aal: "aal2", whoami: admin });
    expect(r.redirect).toBeNull();
    expect(r.operator).toMatchObject({ id: USER, aal: "aal2", role: "platform_admin" });
    expect(mocks.callOps).toHaveBeenCalledWith("whoami");
  });

  it("aal2 but the database denies, or answers without an operator role → /denied", async () => {
    expect((await operator({ aal: "aal2", whoami: { ok: false, kind: "denied" } })).redirect).toBe("/denied");
    expect((await operator({ aal: "aal2", whoami: { ok: true, data: { user_id: USER, role: "seller" } } })).redirect).toBe("/denied");
  });
});

// ---------------------------------------------------------------------------

const ROLES: (OperatorRole | null | undefined)[] = ["platform_admin", "platform_risk", "platform_support", null, undefined];

describe("E-L3b — payout_release and refund_execute can be requested by a platform_admin only (ops.action_allowed_roles mirror)", () => {
  it("canRequest: founder only, for both money verbs", () => {
    for (const role of ROLES) {
      expect(canRequest(role, "refund_execute"), `refund_execute ${String(role)}`).toBe(role === "platform_admin");
      expect(canRequest(role, "payout_release"), `payout_release ${String(role)}`).toBe(role === "platform_admin");
    }
    expect(allowedRoles("refund_execute")).toEqual(["platform_admin"]);
    expect(allowedRoles("payout_release")).toEqual(["platform_admin"]);
  });

  it("support still has its own verbs (control), so the gate above is not 'nobody may do anything'", () => {
    expect(canRequest("platform_support", "user_restrict")).toBe(true);
    expect(canRequest("platform_support", "case_note")).toBe(true);
    expect(canRequest("platform_risk", "dispute_resolve")).toBe(true);
  });
});

// ---------------------------------------------------------------------------

const detail = (): OrderDetail =>
  ({
    payment: { id: PAY, status: "succeeded", total: 9900 },
    transfer: { id: TR, status: "seller_sent", payout_review_status: "manual_review" },
    listing: null,
    buyer: null,
    seller: null,
    disputes: [],
    dispute_resolutions: [],
    payout_decisions: [],
    refund: { refund_actions: [] },
    seller_funds_state: null,
    cases: [],
    actions: [],
    evidence: [],
    bank_payout: { tracked: false, note: null },
    raw: {},
  }) as unknown as OrderDetail;

const clear = { kind: "clear" } as const;
const forms = (html: string) => html.split("<form").slice(1).map((f) => f.slice(0, f.indexOf("</form>")));
const moneyForms = (html: string) => forms(html).map((f) => f.match(/name="action_type" value="([^"]*)"/)?.[1]).filter((t) => t === "payout_release" || t === "refund_execute");
const panelTitles = (html: string) => [...html.matchAll(/<h2 class="title-section">([^<]*)<\/h2>/g)].map((m) => m[1]);

function orderActions(over: { role?: OperatorRole; canRelease?: boolean; canRefund?: boolean; disputeOpen?: boolean } = {}) {
  return renderToStaticMarkup(
    createElement(OrderActions, {
      d: detail(),
      me: { role: over.role ?? "platform_admin" },
      path: `/orders/${PAY}`,
      refundEnabled: true,
      disputeOpen: over.disputeOpen ?? false,
      canRelease: over.canRelease ?? true,
      canRefund: over.canRefund ?? true,
      guards: { release: clear, refund: clear },
    }),
  );
}

describe("E-L3b (rendered) — a non-founder sees no money form, with the reason", () => {
  it("platform_support and platform_risk: neither form, both notices; the guards being clear changes nothing", () => {
    for (const role of ["platform_support", "platform_risk"] as const) {
      const html = orderActions({ role });
      expect(moneyForms(html), role).toEqual([]);
      expect(html).toContain("Only a founder can request a payout release.");
      expect(html).toContain("Only a founder can request a refund.");
    }
  });

  it("control: platform_admin gets both forms and neither notice", () => {
    const html = orderActions({ role: "platform_admin" });
    expect(moneyForms(html)).toEqual(["payout_release", "refund_execute"]);
    expect(html).not.toContain("Only a founder");
  });
});

describe("E-L3c — OrderActions offers a money form only when the page's state check (canRelease / canRefund) says so", () => {
  it("canRelease false (transfer not seller_sent, already released, or disputed): no release panel and no release form, even with a clear guard", () => {
    const html = orderActions({ canRelease: false });
    expect(moneyForms(html)).toEqual(["refund_execute"]);
    expect(panelTitles(html)).not.toContain("Release held payout");
  });

  it("canRefund false (payment not succeeded): no refund panel and no refund form, even with a clear guard", () => {
    const html = orderActions({ canRefund: false });
    expect(moneyForms(html)).toEqual(["payout_release"]);
    expect(panelTitles(html)).not.toContain("Execute refund");
  });

  it("neither: no money form at all and the 'nothing applies' notice", () => {
    const html = orderActions({ canRelease: false, canRefund: false });
    expect(moneyForms(html)).toEqual([]);
    expect(html).toContain("No state-changing action applies to this order right now.");
  });

  it("control: both true → both panels and both forms, no 'nothing applies' notice", () => {
    const html = orderActions();
    expect(moneyForms(html)).toEqual(["payout_release", "refund_execute"]);
    expect(panelTitles(html)).toEqual(expect.arrayContaining(["Release held payout", "Execute refund"]));
    expect(html).not.toContain("No state-changing action applies");
  });
});

// ---------------------------------------------------------------------------

describe("E-L3d — the proxy matcher covers every console route and skips only framework assets and images", () => {
  async function compiled(): Promise<RegExp> {
    // Next's own matcher compiler (build/analysis/get-page-static-info), so the test reads the matcher the way the build does.
    const { getMiddlewareMatchers } = await import("next/dist/build/analysis/get-page-static-info");
    const matchers = getMiddlewareMatchers(proxyConfig.matcher, {} as never) as { regexp: string }[];
    expect(matchers).toHaveLength(1);
    return new RegExp(matchers[0].regexp);
  }

  it("is one constant string (statically analysable; a variable would be ignored by the build)", () => {
    expect(Array.isArray(proxyConfig.matcher)).toBe(true);
    expect(proxyConfig.matcher).toHaveLength(1);
    expect(typeof proxyConfig.matcher[0]).toBe("string");
  });

  it("runs on the console routes, the auth screens and anything else a page could be served from", async () => {
    const re = await compiled();
    for (const path of ["/", "/login", "/mfa", "/denied", "/orders", `/orders/${PAY}`, "/cases", "/system", "/search", "/money", "/users/x", "/marketplace/x", "/api/anything", "/orders.rsc", "/x.js", "/x.json", "/x.css", "/x.svgx", "/svg", "/png"]) {
      expect(re.test(path), path).toBe(true);
    }
  });

  it("skips only _next/static, _next/image, favicon.ico and image files", async () => {
    const re = await compiled();
    for (const path of ["/_next/static/chunks/main.js", "/_next/static/css/app.css", "/_next/image", "/favicon.ico", "/logo.svg", "/img/x.png", "/x.jpg", "/x.jpeg", "/x.gif", "/x.webp", "/x.ico", "/a/b/c.PNG".toLowerCase()]) {
      expect(re.test(path), path).toBe(false);
    }
  });
});
