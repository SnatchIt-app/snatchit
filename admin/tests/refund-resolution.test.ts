import { describe, expect, it } from "vitest";
import {
  OBLIGATION_KINDS,
  REFUND_CLASSIFICATIONS,
  refundResolutionState,
} from "../src/lib/refund-resolution";
import type { CaseEvent } from "../src/lib/types";

/**
 * These cases mirror migration 144's close guard (`ops.action_dispatch`,
 * `case_status` arm) and pgTAP 211 section C. The panel must never say a case
 * is closable when the database would refuse it — that is the failure that
 * matters, because it would send an operator to a dead end holding money that
 * is still owed.
 */

const classified = (value: string, at: string, reason = "Stripe shows a partial refund"): CaseEvent => ({
  kind: "classified",
  at,
  data: { classification: value, reason },
});
const obligation = (kind: string, settled: boolean | string, at: string, note?: string): CaseEvent => ({
  kind: "obligation_changed",
  at,
  data: { kind, settled, ...(note ? { note } : {}) },
});

describe("refundResolutionState", () => {
  it("an unclassified case cannot be closed, and says so in the database's words", () => {
    const s = refundResolutionState([{ kind: "status_changed", at: "2026-09-19T10:00:00Z", data: { to: "open" } }]);
    expect(s.classification).toBeNull();
    expect(s.canClose).toBe(false);
    expect(s.blockedReason).toBe("classify this case first (case_refund_classify: A, B or C)");
  });

  it("classification A on an order that was never paid out raises nothing and closes", () => {
    const s = refundResolutionState([classified("A", "2026-09-19T10:00:00Z")]);
    expect(s.classification).toBe("A");
    expect(s.obligations).toEqual([]);
    expect(s.canClose).toBe(true);
    expect(s.blockedReason).toBeNull();
  });

  it("classification B blocks the close until the payout owed is recorded settled", () => {
    const raised = [classified("B", "2026-09-19T10:00:00Z"), obligation("payout_owed", false, "2026-09-19T10:00:01Z")];
    const open = refundResolutionState(raised);
    expect(open.canClose).toBe(false);
    expect(open.unsettled.map((o) => o.kind)).toEqual(["payout_owed"]);
    expect(open.blockedReason).toContain("unsettled obligation(s): payout_owed");

    const settled = refundResolutionState([...raised, obligation("payout_owed", true, "2026-09-19T11:00:00Z", "paid by bank transfer, ref 88120")]);
    expect(settled.canClose).toBe(true);
    expect(settled.unsettled).toEqual([]);
    expect(settled.obligations[0].note).toBe("paid by bank transfer, ref 88120");
  });

  it("the LATEST record per obligation kind wins, so an obligation can be reopened", () => {
    const s = refundResolutionState([
      classified("C", "2026-09-19T10:00:00Z"),
      obligation("remainder_refund_owed", false, "2026-09-19T10:00:01Z"),
      obligation("remainder_refund_owed", true, "2026-09-19T11:00:00Z", "refunded the rest"),
      obligation("remainder_refund_owed", false, "2026-09-19T12:00:00Z", "the refund failed at Stripe"),
    ]);
    expect(s.obligations).toHaveLength(1);
    expect(s.obligations[0].settled).toBe(false);
    expect(s.obligations[0].note).toBe("the refund failed at Stripe");
    expect(s.canClose).toBe(false);
  });

  it("the LATEST classification wins", () => {
    const s = refundResolutionState([
      classified("B", "2026-09-19T10:00:00Z"),
      obligation("payout_owed", true, "2026-09-19T10:30:00Z", "settled"),
      classified("A", "2026-09-19T11:00:00Z", "Stripe actually shows the full amount"),
    ]);
    expect(s.classification).toBe("A");
    expect(s.classifiedReason).toBe("Stripe actually shows the full amount");
    // the obligation B raised does not disappear just because the reading changed
    expect(s.obligations.map((o) => o.kind)).toEqual(["payout_owed"]);
    expect(s.canClose).toBe(true);
  });

  it("several unsettled obligations are all named, in a stable order", () => {
    const s = refundResolutionState([
      classified("C", "2026-09-19T10:00:00Z"),
      obligation("remainder_refund_owed", false, "2026-09-19T10:00:01Z"),
      obligation("reversal_decision", false, "2026-09-19T10:00:02Z"),
    ]);
    expect(s.blockedReason).toContain("remainder_refund_owed, reversal_decision");
  });

  it("settled arriving as the text 'true' is still settled", () => {
    const s = refundResolutionState([classified("B", "2026-09-19T10:00:00Z"), obligation("payout_owed", "true", "2026-09-19T10:30:00Z")]);
    expect(s.canClose).toBe(true);
  });

  it("malformed or empty event data never makes a case look closable", () => {
    const s = refundResolutionState([
      { kind: "classified", at: "2026-09-19T10:00:00Z", data: null },
      { kind: "classified", at: "2026-09-19T10:00:01Z", data: { classification: "" } },
      { kind: "obligation_changed", at: "2026-09-19T10:00:02Z", data: { kind: "" } },
    ]);
    expect(s.classification).toBeNull();
    expect(s.canClose).toBe(false);
  });

  it("an empty log is not closable — the panel cannot pass vacuously", () => {
    expect(refundResolutionState([]).canClose).toBe(false);
  });
});

describe("the vocabularies match migration 144", () => {
  it("offers exactly A, B and C", () => {
    expect(REFUND_CLASSIFICATIONS.map((c) => c.value)).toEqual(["A", "B", "C"]);
  });
  it("offers exactly the three obligation kinds the dispatcher accepts", () => {
    expect([...OBLIGATION_KINDS]).toEqual(["payout_owed", "remainder_refund_owed", "reversal_decision"]);
  });
});
