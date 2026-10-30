import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import {
  ACTION_LABEL,
  connectCapability,
  FAILURE_COPY,
  failureFromEdge,
  nextConnectAction,
  onboardingBody,
  parseConnectSnapshot,
  parseOrgConnectState,
  safeStripeUrl,
  type ConnectFailureKind,
} from "@/lib/org/connect-contract";

const OK = {
  status: "ok",
  org_id: "24232848-0bcf-4fa9-8040-c8bd2dc38ed2",
  org_status: "approved",
  connect_bound: true,
  connect_account_ref: "masked:call_kernel.get_org_connect_ref",
  connect_account_last4: "4242",
  connect_transfers_active: false,
  connect_state_synced_at: "2026-10-26T20:00:00Z",
};

describe("parseOrgConnectState — the state-for-humans read (093 §6)", () => {
  it("reads the whole shape, including an unbound org", () => {
    expect(parseOrgConnectState(OK)).toEqual({
      orgId: OK.org_id,
      orgStatus: "approved",
      bound: true,
      last4: "4242",
      transfersActive: false,
      syncedAt: "2026-10-26T20:00:00Z",
    });
    const unbound = parseOrgConnectState({ ...OK, connect_bound: false, connect_account_ref: null, connect_account_last4: null, connect_transfers_active: null, connect_state_synced_at: null });
    expect(unbound).toMatchObject({ bound: false, last4: null, transfersActive: null, syncedAt: null });
  });
  it("anything that is not a status:'ok' object with an org id is null — never a half-read state", () => {
    for (const v of [null, undefined, 1, "ok", [], {}, { status: "ok" }, { status: "error", org_id: OK.org_id }, { ...OK, org_id: "" }]) expect(parseOrgConnectState(v), String(v)).toBeNull();
  });
  // The ref below is a synthetic placeholder in the acct_ SHAPE; never paste a real
  // Stripe account id into a test — the pre-push scanner refuses it, correctly.
  it("refuses to surface a last4 if the server ever sent a real account ref instead of the mask", () => {
    const leaked = parseOrgConnectState({ ...OK, connect_account_ref: "acct_0000000000SYNTHETIC" });
    expect(leaked?.bound).toBe(true);
    expect(leaked?.last4).toBeNull();
    // a mask with no last4 is fine; a non-mask is the only case that suppresses it
    expect(parseOrgConnectState({ ...OK, connect_account_last4: "not a last4!" })?.last4).toBeNull();
  });
});

describe("parseConnectSnapshot — the edge's answer", () => {
  const snap = {
    status: "onboarding_incomplete",
    org_id: OK.org_id,
    connect_account_last4: "4242",
    transfers_active: false,
    payouts_enabled: false,
    details_submitted: true,
    requirements_due: ["individual.verification.document", 7],
    disabled_reason: "requirements.past_due",
    requirements_deadline: "2026-11-30T00:00:00Z",
    checked_at: "2026-10-26T20:30:00Z",
    url: "https://connect.stripe.com/setup/e/acct_1/abc",
  };
  it("keeps the fields, drops non-string requirement entries, and carries an https Stripe url", () => {
    const s = parseConnectSnapshot(snap)!;
    expect(s.status).toBe("onboarding_incomplete");
    expect(s.requirementsDue).toEqual(["individual.verification.document"]);
    expect(s.payoutsEnabled).toBe(false);
    expect(s.detailsSubmitted).toBe(true);
    expect(s.url).toBe(snap.url);
    expect(parseConnectSnapshot({ ...snap, url: undefined })?.url).toBeNull();
  });
  it("a payload with no status is null", () => {
    for (const v of [null, {}, { org_id: OK.org_id }]) expect(parseConnectSnapshot(v)).toBeNull();
  });
  it("only an https stripe.com link is ever handed to the operator", () => {
    expect(safeStripeUrl("https://connect.stripe.com/x")).toBe("https://connect.stripe.com/x");
    expect(safeStripeUrl("https://stripe.com/x")).toBe("https://stripe.com/x");
    for (const bad of ["http://connect.stripe.com/x", "https://stripe.com.evil.test/x", "https://evil.test/stripe.com", "javascript:alert(1)", "", null, 42, "//connect.stripe.com/x"]) {
      expect(safeStripeUrl(bad), String(bad)).toBeNull();
    }
  });
});

describe("who may do what — the endpoint gate and SoD-1", () => {
  it("org_owner on aal2 may bind; org_owner on aal1 is offered step-up, not a refusal", () => {
    expect(connectCapability({ isOrgOwner: true, isOrgFinance: false, aal: "aal2" })).toEqual({ mayView: true, mayInitiate: true, mayBind: true, needsStepUp: false });
    expect(connectCapability({ isOrgOwner: true, isOrgFinance: false, aal: "aal1" })).toEqual({ mayView: true, mayInitiate: true, mayBind: false, needsStepUp: true });
    expect(connectCapability({ isOrgOwner: true, isOrgFinance: false, aal: null })).toMatchObject({ mayBind: false, needsStepUp: true });
  });
  it("org_finance may view and initiate but never bind, on any aal", () => {
    for (const aal of ["aal1", "aal2", null] as const) {
      expect(connectCapability({ isOrgOwner: false, isOrgFinance: true, aal })).toEqual({ mayView: true, mayInitiate: true, mayBind: false, needsStepUp: false });
    }
  });
  it("nobody else sees the panel — a venue role is not an org role", () => {
    for (const aal of ["aal2", "aal1", null] as const) {
      expect(connectCapability({ isOrgOwner: false, isOrgFinance: false, aal })).toEqual({ mayView: false, mayInitiate: false, mayBind: false, needsStepUp: false });
    }
  });
});

describe("what the screen offers next", () => {
  it("unbound → set up; bound and inactive → continue; bound and active → the Stripe dashboard; unreadable → check again", () => {
    const base = parseOrgConnectState(OK)!;
    expect(nextConnectAction({ ...base, bound: false })).toBe("set_up");
    expect(nextConnectAction({ ...base, bound: true, transfersActive: false })).toBe("continue");
    expect(nextConnectAction({ ...base, bound: true, transfersActive: null })).toBe("continue");
    expect(nextConnectAction({ ...base, bound: true, transfersActive: true })).toBe("open_dashboard");
    expect(nextConnectAction(null)).toBe("none");
    for (const k of Object.keys(ACTION_LABEL)) expect(ACTION_LABEL[k as keyof typeof ACTION_LABEL].length).toBeGreaterThan(3);
  });
});

describe("the edge's refusals in the operator's words", () => {
  it("each code maps to its own kind", () => {
    expect(failureFromEdge(403, "dashboard_requires_owner").kind).toBe("requires_owner");
    expect(failureFromEdge(403, "step_up_unavailable").kind).toBe("step_up_required");
    expect(failureFromEdge(403, "forbidden").kind).toBe("forbidden");
    expect(failureFromEdge(409, null).kind).toBe("replacement_required");
    expect(failureFromEdge(429, null).kind).toBe("rate_limited");
    expect(failureFromEdge(503, "connect_state_unavailable").kind).toBe("state_unavailable");
    expect(failureFromEdge(400, "unexpected_field").kind).toBe("invalid_request");
    expect(failureFromEdge(400, "invalid_org_id").kind).toBe("invalid_request");
    expect(failureFromEdge(405, "method_not_allowed").kind).toBe("invalid_request");
    expect(failureFromEdge(500, "malformed_account_ref").kind).toBe("server_error");
    expect(failureFromEdge(404, null).kind).toBe("not_enabled");
    expect(failureFromEdge(501, null).kind).toBe("not_enabled");
    expect(failureFromEdge(500, null).kind).toBe("server_error");
    expect(failureFromEdge(503, null, "x").detail).toBe("x");
  });
  it("every kind has copy, and no copy claims money moved or that a destination was set", () => {
    const kinds: ConnectFailureKind[] = ["not_enabled", "forbidden", "requires_owner", "step_up_required", "replacement_required", "rate_limited", "state_unavailable", "invalid_request", "transport", "server_error"];
    for (const k of kinds) {
      const copy = FAILURE_COPY[k];
      expect(copy, k).toBeTruthy();
      expect(copy.toLowerCase(), k).not.toMatch(/paid out|payout sent|money (was )?(sent|moved)|account (is )?(now )?connected/);
    }
    expect(FAILURE_COPY.requires_owner).toContain("owner");
    expect(FAILURE_COPY.not_enabled).toContain("not enabled");
  });
});

describe("the request body the edge accepts", () => {
  it("carries exactly org_id, and only adds the optional keys when asked", () => {
    expect(onboardingBody(OK.org_id)).toEqual({ org_id: OK.org_id });
    expect(onboardingBody(OK.org_id, { statusOnly: true })).toEqual({ org_id: OK.org_id, status_only: true });
    expect(onboardingBody(OK.org_id, { commandKey: "k-1" })).toEqual({ org_id: OK.org_id, command_key: "k-1" });
    expect(onboardingBody(OK.org_id, { statusOnly: false })).toEqual({ org_id: OK.org_id });
  });
  it("never names a redirect target — the edge refuses a caller-supplied one", () => {
    const keys = Object.keys(onboardingBody(OK.org_id, { statusOnly: true, commandKey: "k" }));
    expect(keys.sort()).toEqual(["command_key", "org_id", "status_only"]);
    for (const k of keys) expect(k).not.toMatch(/url/);
  });
});

describe("when the live Stripe read and the stored mirror disagree (E-F6)", () => {
  const actions = readFileSync(resolve(__dirname, "../src/components/org/ConnectActions.tsx"), "utf8");
  const page = readFileSync(resolve(__dirname, "../src/app/o/[org]/payouts/page.tsx"), "utf8");

  it("says so, instead of showing two panels that contradict each other in silence", () => {
    // 2026-10-27: the owner saw "ready" from the live read and "Not yet" from the
    // stored copy, eleven seconds after the account was created.
    expect(actions).toMatch(/storedBehind/);
    expect(actions).toMatch(/still says no/);
  });

  it("explains that going on sale reads the STORED copy, which is what actually gates selling", () => {
    expect(actions).toMatch(/Going on sale reads the stored copy/);
  });

  it("offers NO button to reconcile it — kernel.sync_org_connect_state is service_role only, and 093 forbids a human path", () => {
    expect(actions).not.toMatch(/sync_org_connect_state\s*\(/);
    expect(actions).toMatch(/none may ever be added|no human path/i);
    // Nothing on this surface may claim it can write the stored value.
    expect(actions).toMatch(/neither this page nor this button can write it/);
  });

  it("only fires when the live read is ready and the stored copy is not", () => {
    expect(actions).toMatch(/const liveReady = snapshot\.transfersActive === true/);
    expect(actions).toMatch(/const storedBehind = liveReady && storedTransfersActive !== true/);
  });

  it("is fed the stored value by the page, not re-derived in the client", () => {
    expect(page).toMatch(/storedTransfersActive=\{state\?\.transfersActive \?\? null\}/);
  });
});
