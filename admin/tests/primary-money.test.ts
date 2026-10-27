import { describe, expect, it } from "vitest";
import {
  doorWouldStillAdmit,
  isValidCommandKey,
  MANUAL_REFUND_NOTE,
  mintRefundKey,
  refundRefusalCopy,
  refundRefusalToken,
  REFUND_REFUSAL_COPY,
  refundSidesAgree,
  toPrimaryReconciliation,
  toRefundOutcome,
  validateRefundInput,
} from "@/lib/primary-money";

const ORDER = "7a000000-0000-4000-8000-0000000000d4";
const PAY = "9a900000-0000-4000-8000-0000000000d4";

const row = (over: Record<string, unknown> = {}) => ({
  payment_id: PAY,
  order_id: ORDER,
  linked_at: "2026-11-30T04:00:00Z",
  payment_status: "succeeded",
  payment_total_minor: 2750,
  stripe_livemode: false,
  order_status: "paid",
  order_total_minor: 2500,
  tickets_issued: 2,
  tickets_voided: 0,
  tickets_admitted: 1,
  tickets_live: 1,
  kernel_refund_minor: 0,
  kernel_refund_count: 0,
  stripe_refund_succeeded_minor: 0,
  stripe_refund_open_minor: 0,
  state: "ok",
  attention: [],
  ...over,
});
const payload = (over: Record<string, unknown> = {}) => ({
  from: null,
  to: null,
  computed_at: "2026-10-27T06:30:00Z",
  currency: "USD",
  basis: "kernel.payment_native.linked_at, UTC calendar day; a NULL bound is open",
  count: 1,
  attention_count: 0,
  critical_count: 0,
  rows: [row()],
  attention: [],
  ...over,
});

describe("the reconciliation read carries both refund sides", () => {
  it("reads a row whole, including the two refund columns that can disagree", () => {
    const r = toPrimaryReconciliation(payload())!;
    expect(r.currency).toBe("USD");
    expect(r.count).toBe(1);
    const x = r.rows[0];
    expect(x).toMatchObject({ paymentId: PAY, orderId: ORDER, orderStatus: "paid", ticketsLive: 1, kernelRefundMinor: 0, stripeRefundSucceededMinor: 0 });
    expect(x.stripeLivemode).toBe(false);
  });
  it("a payload without both arrays is null — a partial read is not a smaller truth", () => {
    for (const bad of [null, {}, payload({ rows: undefined }), payload({ attention: undefined }), payload({ rows: "x" })]) {
      expect(toPrimaryReconciliation(bad)).toBeNull();
    }
  });
  it("attention items keep their code, severity and the server's own sentence", () => {
    const r = toPrimaryReconciliation(
      payload({
        attention_count: 2,
        critical_count: 1,
        attention: [
          { code: "stripe_refunded_tickets_live", severity: "critical", payment_id: PAY, order_id: ORDER, message: "Stripe shows a succeeded refund but tickets of this order are still live" },
          { code: "kernel_refund_without_stripe", severity: "warning", payment_id: PAY, order_id: ORDER, message: "no matching refund in Stripe" },
          { severity: "critical" },
        ],
      }),
    )!;
    expect(r.attention).toHaveLength(2);
    expect(r.attention[0]).toMatchObject({ code: "stripe_refunded_tickets_live", severity: "critical" });
    expect(r.attention[0].message).toContain("still live");
    expect(r.criticalCount).toBe(1);
  });
  it("the two questions the page asks of a row", () => {
    expect(doorWouldStillAdmit(toPrimaryReconciliation(payload())!.rows[0])).toBe(true);
    expect(doorWouldStillAdmit(toPrimaryReconciliation(payload({ rows: [row({ tickets_live: 0 })] }))!.rows[0])).toBe(false);
    expect(refundSidesAgree(toPrimaryReconciliation(payload())!.rows[0])).toBe(true);
    expect(refundSidesAgree(toPrimaryReconciliation(payload({ rows: [row({ kernel_refund_minor: 2500 })] }))!.rows[0])).toBe(false);
    // unknown on either side is not a disagreement
    expect(refundSidesAgree(toPrimaryReconciliation(payload({ rows: [row({ stripe_refund_succeeded_minor: null })] }))!.rows[0])).toBeNull();
  });
});

describe("the console's idempotency key", () => {
  it("matches the server's shape and can never be the delegated dual-control form", () => {
    const key = mintRefundKey("11111111-2222-4333-8444-555555555555");
    expect(key).toBe("pr.11111111-2222-4333-8444-555555555555");
    expect(isValidCommandKey(key)).toBe(true);
    expect(key.length).toBeLessThanOrEqual(80);
    expect(isValidCommandKey("req:abcd1234")).toBe(false);
    for (const bad of ["short", "", "has spaces here", "x".repeat(81), "bad/char!"]) expect(isValidCommandKey(bad), bad).toBe(false);
  });
});

describe("what the console refuses before sending", () => {
  it("a bad order id, amount, reason or key", () => {
    const ok = { orderId: ORDER, amountMinor: 2500, reasonCode: "buyer_request", commandKey: "pr.abcd1234" };
    expect(validateRefundInput(ok)).toEqual([]);
    expect(validateRefundInput({ ...ok, orderId: "nope" }).map((p) => p.field)).toContain("orderId");
    for (const amt of [0, -1, 2.5, NaN]) expect(validateRefundInput({ ...ok, amountMinor: amt }).map((p) => p.field), String(amt)).toContain("amountMinor");
    expect(validateRefundInput({ ...ok, reasonCode: "  " }).map((p) => p.field)).toContain("reasonCode");
    expect(validateRefundInput({ ...ok, commandKey: "req:x" }).map((p) => p.field)).toContain("commandKey");
  });
  it("an amount above the order's own total is refused with the number", () => {
    const p = validateRefundInput({ orderId: ORDER, amountMinor: 9999, reasonCode: "x", commandKey: "pr.abcd1234" }, 2750);
    expect(p.map((x) => x.field)).toContain("amountMinor");
    expect(p[0].message).toContain("2750");
  });
});

describe("the receipt is the only thing read as recorded", () => {
  it("ok is recorded, a replay says so, and an unrecognised status is NOT success", () => {
    expect(toRefundOutcome({ status: "ok", refund_id: "r1", voided_atoms: 2, full: true })).toMatchObject({ kind: "recorded", refundId: "r1", voided: 2, full: true });
    expect(toRefundOutcome({ status: "idempotency_replay", refund_id: "r1" })).toMatchObject({ kind: "replayed", refundId: "r1" });
    for (const bad of [null, "ok", {}, { status: "queued" }, { status: "processing" }]) {
      expect(toRefundOutcome(bad).kind, JSON.stringify(bad)).toBe("refused");
    }
  });
  it("the unrecognised-status copy tells the operator not to refund in Stripe yet", () => {
    expect(REFUND_REFUSAL_COPY.unknown_status).toContain("NOT recorded");
    expect(REFUND_REFUSAL_COPY.no_receipt).toContain("do not refund in Stripe");
  });
});

describe("refusals in the operator's words", () => {
  it("each server token maps to its own copy", () => {
    const cases: [string, string][] = [
      ["step_up_required: aal2 session required", "step_up_required"],
      ["step_up_unavailable", "step_up_unavailable"],
      ["insufficient_privilege: platform role required", "insufficient_privilege"],
      ["actions_disabled", "actions_disabled"],
      ["invalid_input: command key must be 8-80 chars of [A-Za-z0-9._:-]", "invalid_input"],
      ["invalid_input: a req: key is the dual-control delegated arm", "invalid_input"],
      ["not_found: order", "not_found"],
      ["precondition_failed: over_refund", "over_refund"],
      ["precondition_failed: support_cap", "support_cap"],
    ];
    for (const [message, token] of cases) {
      expect(refundRefusalToken(message), message).toBe(token);
      expect(refundRefusalCopy(message), message).toBe(REFUND_REFUSAL_COPY[token]);
    }
  });
  it("the kernel's own phrasings are recognised without the token", () => {
    expect(refundRefusalToken("precondition_failed: refund would exceed the amount paid")).toBe("over_refund");
    expect(refundRefusalToken("precondition_failed: conflict_locked (resale_state=listed)")).toBe("atom_not_voidable");
    expect(refundRefusalToken("an aal2 session is required")).toBe("step_up_required");
  });
  it("an unknown refusal keeps the server's sentence, and no copy claims money moved", () => {
    expect(refundRefusalCopy("something_new: with detail")).toContain("something_new: with detail");
    expect(refundRefusalCopy(null)).toContain("Nothing was recorded");
    for (const copy of Object.values(REFUND_REFUSAL_COPY)) {
      expect(copy.toLowerCase()).not.toMatch(/money (was |is )?(sent|moved|refunded)|refund (was )?(sent|completed|issued)/);
    }
  });
  it("the note beside the button says plainly that no money moves", () => {
    expect(MANUAL_REFUND_NOTE).toContain("does not move money");
    expect(MANUAL_REFUND_NOTE).toContain("voids");
    expect(MANUAL_REFUND_NOTE).toContain("Stripe Dashboard");
  });
});
