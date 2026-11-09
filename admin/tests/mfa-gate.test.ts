import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

/**
 * F4 (OC-15) — /mfa used to start TOTP enrolment for any signed-in account,
 * so a marketplace user who signed in on the console got an authenticator
 * factor created on their account before the operator check ran (which only
 * happened after aal2). ops.whoami() (115:1134-1152) checks auth.uid() and
 * ops.actor_role() only — no aal requirement, unlike ops.assert_reader() —
 * so it answers at aal1. The /mfa page now asks it first: a non-operator is
 * sent to /denied before any factor is listed or created; operators are
 * unchanged. These render the real page and the real session helpers with
 * Supabase and the ops RPC mocked.
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
  usePathname: () => "/mfa",
  useRouter: () => ({ push: () => {}, replace: () => {}, refresh: () => {} }),
  useParams: () => ({}),
}));
vi.mock("@/lib/ops", () => ({ callOps: mocks.callOps }));
vi.mock("@/lib/supabase/server", () => ({ createSupabaseServerClient: async () => ({ auth: { getClaims: mocks.getClaims } }) }));
vi.mock("@/lib/auth/actions", () => ({ signOutAction: async () => {} }));

import MfaPage from "@/app/(auth)/mfa/page";

const USER = "b0000000-0000-4000-8000-0000000000f4";
const ENROL_UI = "Preparing your authenticator";

type Ops = { ok: true; data: unknown } | { ok: false; kind: string; message?: string; unavailable?: boolean };

async function visit({ aal = "aal1", signedIn = true, whoami }: { aal?: string; signedIn?: boolean; whoami?: Ops }) {
  mocks.getClaims.mockResolvedValue(signedIn ? { data: { claims: { sub: USER, aal, email: "x@example.test" } }, error: null } : { data: null, error: null });
  mocks.callOps.mockImplementation(async (fn: string) => (fn === "whoami" && whoami ? whoami : { ok: false, kind: "error", message: `unexpected ${fn}` }));
  try {
    const el = await MfaPage({ searchParams: Promise.resolve({ next: "/orders" }) });
    return { html: renderToStaticMarkup(el), redirect: null as string | null };
  } catch (e) {
    if (e instanceof Redirect) return { html: "", redirect: e.path };
    throw e;
  }
}

beforeEach(() => {
  mocks.callOps.mockReset();
  mocks.getClaims.mockReset();
});

describe("F4 — /mfa checks operator status (ops.whoami at aal1) before enrolment", () => {
  it("an aal1 non-operator (whoami 42501 → denied) goes to /denied and never sees the enrol flow", async () => {
    const r = await visit({ whoami: { ok: false, kind: "denied" } });
    expect(r.redirect).toBe("/denied");
    expect(r.html).not.toContain(ENROL_UI);
    expect(mocks.callOps).toHaveBeenCalledWith("whoami");
  });

  it("whoami answering without an operator role is a non-operator too", async () => {
    for (const data of [{ user_id: USER, role: null, aal: "aal1" }, { user_id: USER, role: "seller", aal: "aal1" }, null]) {
      expect((await visit({ whoami: { ok: true, data } })).redirect, JSON.stringify(data)).toBe("/denied");
    }
  });

  it("a failed check fails closed with the fixed reason code, not the enrol flow", async () => {
    expect((await visit({ whoami: { ok: false, kind: "error", message: "boom" } })).redirect).toBe("/denied?reason=check_failed");
    expect((await visit({ whoami: { ok: false, kind: "error", message: "RPC ops.whoami not available yet", unavailable: true } })).redirect).toBe("/denied?reason=unavailable");
  });

  it("no verified session → /login", async () => {
    expect((await visit({ signedIn: false, whoami: { ok: true, data: { role: "platform_admin" } } })).redirect).toBe("/login");
  });

  it("operators are unchanged: an aal1 platform_admin gets the enrol/verify flow", async () => {
    const r = await visit({ whoami: { ok: true, data: { user_id: USER, role: "platform_admin", aal: "aal1" } } });
    expect(r.redirect).toBeNull();
    expect(r.html).toContain(ENROL_UI);
    expect(r.html).toContain("Two-factor authentication");
  });

  it("risk and support operators also reach the flow; a step-up answer does not lock anyone out", async () => {
    for (const role of ["platform_risk", "platform_support"]) {
      expect((await visit({ whoami: { ok: true, data: { role, aal: "aal1" } } })).html, role).toContain(ENROL_UI);
    }
    // If a future whoami demanded aal2 first, /mfa must still let the session step up.
    expect((await visit({ whoami: { ok: false, kind: "mfa" } })).html).toContain(ENROL_UI);
  });
});

describe("F4 — decideMfaAccess (pure rule)", () => {
  it("maps every whoami answer", async () => {
    const { decideMfaAccess } = await import("@/lib/auth/mfa-access");
    const flow = { type: "flow" };
    const to = (path: string) => ({ type: "redirect", path });
    expect(decideMfaAccess({ signedIn: false, whoami: null })).toEqual(to("/login"));
    expect(decideMfaAccess({ signedIn: true, whoami: null })).toEqual(to("/denied?reason=check_failed"));
    expect(decideMfaAccess({ signedIn: true, whoami: { ok: true, data: { role: "platform_admin", aal: "aal1" } } })).toEqual(flow);
    expect(decideMfaAccess({ signedIn: true, whoami: { ok: true, data: { role: "anon" } } })).toEqual(to("/denied"));
    expect(decideMfaAccess({ signedIn: true, whoami: { ok: false, kind: "denied" } })).toEqual(to("/denied"));
    expect(decideMfaAccess({ signedIn: true, whoami: { ok: false, kind: "mfa" } })).toEqual(flow);
    expect(decideMfaAccess({ signedIn: true, whoami: { ok: false, kind: "paused", message: "x" } })).toEqual(to("/denied?reason=check_failed"));
    expect(decideMfaAccess({ signedIn: true, whoami: { ok: false, kind: "error", message: "x", unavailable: true } })).toEqual(to("/denied?reason=unavailable"));
  });
});
