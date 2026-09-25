import { describe, expect, it } from "vitest";
import {
  CONFIRM_AND_RELEASE_DRAIN_END_AT,
  CONFIRM_AND_RELEASE_SWITCHOVER_AT,
  DISPUTE_RESOLUTION_LABELS,
  PAYMENT_STATUS_LABELS,
  SQL_WRITER_FIX_AT,
  decisionProvenance,
  decisionProvenanceNote,
  labelFor,
  payoutStateLabel,
  transferStateLabel,
} from "../src/lib/format";

// A's ratified truth conditions (PAYMENT_STATE_WORDING_TABLE §2h/§2i, findings a5/a6,
// F1-ADMIN-1). Each block states the claim the label is allowed to make.

describe("a5 — a buyer confirmation is the confirmation RECORD, never the status", () => {
  it("a genuine confirmation reads as one", () => {
    expect(transferStateLabel({ status: "buyer_confirmed", buyer_confirmed_at: "2026-09-20T10:00:00Z" }))
      .toBe("Buyer confirmed");
  });

  it("a seller-win carries the same status and must NOT read as a confirmation", () => {
    const sellerWin = { status: "buyer_confirmed", buyer_confirmed_at: null, dispute_resolution: "resolved_seller_paid" };
    expect(transferStateLabel(sellerWin)).toBe("Resolved — seller (no buyer confirmation)");
    expect(transferStateLabel(sellerWin).toLowerCase()).not.toContain("buyer confirmed");
    // and it must not imply a payout either
    expect(transferStateLabel(sellerWin).toLowerCase()).not.toMatch(/paid|payout|released/);
  });

  it("a status-only row with no resolution is named, not guessed", () => {
    expect(transferStateLabel({ status: "buyer_confirmed", buyer_confirmed_at: null }))
      .toBe("Confirmed status, no confirmation record");
  });

  it("every other status is unchanged from the bare vocabulary", () => {
    for (const s of ["pending", "seller_sent", "auto_released", "disputed", "expired", "reversed"]) {
      expect(transferStateLabel({ status: s })).toBe(labelFor("transfer", s));
    }
  });

  // Control: the helper must be able to produce the confirmation label at all, so the
  // negative assertions above are not vacuously true.
  it("CONTROL: the confirmation label is reachable", () => {
    expect(transferStateLabel({ status: "buyer_confirmed", buyer_confirmed_at: "2026-01-01T00:00:00Z" }))
      .toContain("Buyer confirmed");
  });
});

describe("ruling 2 — payout evidence, with reversed taking precedence", () => {
  it("a reversed transfer never reads as released, even with a release timestamp", () => {
    const reversed = { status: "reversed", payout_released_at: "2026-09-20T10:00:00Z" };
    expect(payoutStateLabel(reversed)).toBe("Reversed (a reversal was recorded; amount not stored)");
    // it must not claim money is owed back: that is payout_attempts.reversal_required,
    // a different fact from a different writer (A's R2).
    expect(payoutStateLabel(reversed).toLowerCase()).not.toMatch(/owed|owes|pending return/);
    expect(payoutStateLabel(reversed).toLowerCase()).not.toMatch(/^released|paid/);
  });

  it("a release is stated only from payout_released_at", () => {
    expect(payoutStateLabel({ status: "buyer_confirmed", payout_released_at: "2026-09-20T10:00:00Z" }))
      .toBe("Released to connected account");
    expect(payoutStateLabel({ status: "buyer_confirmed", payout_released_at: null })).toBe("Not released");
  });

  it("a hold or manual review is not a release", () => {
    expect(payoutStateLabel({ status: "seller_sent", payout_review_status: "manual_review" })).toBe("Not released — manual review");
    expect(payoutStateLabel({ status: "seller_sent", payout_review_status: "held" })).toBe("Not released — held");
  });

  it("no payout label anywhere says the seller RECEIVED the money", () => {
    const rows = [
      { status: "reversed", payout_released_at: "2026-09-20T10:00:00Z" },
      { status: "buyer_confirmed", payout_released_at: "2026-09-20T10:00:00Z" },
      { status: "seller_sent", payout_review_status: "manual_review" },
      { status: "seller_sent" },
    ];
    for (const r of rows) expect(payoutStateLabel(r).toLowerCase()).not.toContain("received");
  });
});

describe("resolved_seller_paid is a decision, not a payment", () => {
  it("the label refuses the payout claim its enum name makes", () => {
    const l = DISPUTE_RESOLUTION_LABELS.resolved_seller_paid;
    expect(l).toBe("Resolved — seller (decision; payout not implied)");
    expect(l.toLowerCase()).not.toMatch(/\bpaid\b|\breceived\b/);
  });

  it("the vocabulary is registered, so the raw value is never humanized into a payment claim", () => {
    expect(labelFor("dispute_resolution", "resolved_seller_paid")).toBe(DISPUTE_RESOLUTION_LABELS.resolved_seller_paid);
    // what it would otherwise have shown:
    expect(labelFor("dispute_resolution", "resolved_seller_paid")).not.toBe("Resolved Seller Paid");
  });

  it("the buyer-side resolutions say a refund is required, not done", () => {
    expect(DISPUTE_RESOLUTION_LABELS.resolved_buyer_refunded).toMatch(/refund required/i);
    expect(DISPUTE_RESOLUTION_LABELS.resolved_partial_refund).toMatch(/refund required/i);
  });
});

describe("F1-ADMIN-1 — a recorded refund is not a settled refund (ruling 3, interim)", () => {
  it("the payment status label does not assert settlement", () => {
    expect(PAYMENT_STATUS_LABELS.refunded).toBe("Refund recorded (not confirmed settled)");
    expect(labelFor("payment", "refunded")).not.toBe("Refunded");
  });
});

describe("a6 — provenance is per WRITER, ordered so the permanent case wins", () => {
  const BEFORE_MIGRATION = "2026-09-24T20:30:00Z";
  const BETWEEN = "2026-09-24T20:31:10Z";          // migration applied, v38 not yet current
  const IN_DRAIN = "2026-09-24T20:34:00Z";         // after switchover, inside the 400 s drain
  const AFTER_DRAIN = "2026-09-24T20:40:00Z";
  const A3 = { decision: "manual_review", evidence: { attempt_id: "att-1" } };

  it("confirm-and-release has THREE regions, not two", () => {
    expect(decisionProvenance("edge:confirm-and-release", BEFORE_MIGRATION)).toBe("status_derived");
    expect(decisionProvenance("edge:confirm-and-release", BETWEEN)).toBe("status_derived");
    expect(decisionProvenance("edge:confirm-and-release", IN_DRAIN)).toBe("maybe_status_derived");
    expect(decisionProvenance("edge:confirm-and-release", AFTER_DRAIN)).toBe("reliable");
  });

  it("the drain window is the documented wall-clock limit, not a guess", () => {
    expect(Date.parse(CONFIRM_AND_RELEASE_DRAIN_END_AT) - Date.parse(CONFIRM_AND_RELEASE_SWITCHOVER_AT)).toBe(400_000);
    expect(CONFIRM_AND_RELEASE_SWITCHOVER_AT).toBe("2026-09-24T20:31:20.378Z");
  });

  it("a4 (stripe-webhook) flips at the migration, with no drain window", () => {
    expect(SQL_WRITER_FIX_AT).toBe("2026-09-24T20:31:03Z");
    expect(Date.parse(SQL_WRITER_FIX_AT)).toBeLessThan(Date.parse(CONFIRM_AND_RELEASE_SWITCHOVER_AT));
    expect(decisionProvenance("edge:stripe-webhook", BEFORE_MIGRATION)).toBe("status_derived");
    expect(decisionProvenance("edge:stripe-webhook", BETWEEN)).toBe("reliable");
  });

  it("a3 is identified by its OWN evidence, so the claimer's actor cannot mislabel it", () => {
    // claimed by the cron: actor is cron:…, and by actor alone this would read "reliable"
    expect(decisionProvenance("cron:enforce-transfer-expiry", BEFORE_MIGRATION, A3)).toBe("status_derived");
    expect(decisionProvenance("cron:enforce-transfer-expiry", BETWEEN, A3)).toBe("reliable");
    // claimed by confirm-and-release: it is still a SQL writer, so no drain window applies
    expect(decisionProvenance("edge:confirm-and-release", BETWEEN, A3)).toBe("reliable");
    expect(decisionProvenance("edge:confirm-and-release", IN_DRAIN, A3)).toBe("reliable");
  });

  it("the permanently-unreliable writer is checked FIRST, even when its evidence looks like a3", () => {
    // recordManualReviewOnce puts attempt_id in evidence at index.ts:976-977 and :984.
    // If the a3 test ran first, these rows would be handed a boundary and pass as reliable.
    const looksLikeA3 = { decision: "manual_review", evidence: { attempt_id: "att-9", unmatched_stripe_transfer_ids: ["tr_1"] } };
    for (const when of [BEFORE_MIGRATION, BETWEEN, IN_DRAIN, AFTER_DRAIN, null]) {
      expect(decisionProvenance("edge:enforce-transfer-expiry", when, looksLikeA3)).toBe("never_reads_confirmation");
    }
  });

  it("writers that never derived from status are never annotated", () => {
    for (const when of [BEFORE_MIGRATION, BETWEEN, AFTER_DRAIN]) {
      expect(decisionProvenance("cron:enforce-transfer-expiry", when)).toBe("reliable");
      expect(decisionProvenance("admin:0f9c2d61-0000-4000-8000-000000000001", when)).toBe("reliable");
    }
  });

  it("an affected writer with an unreadable timestamp is flagged, not trusted", () => {
    expect(decisionProvenance("edge:confirm-and-release", null)).toBe("status_derived");
    expect(decisionProvenance("edge:stripe-webhook", "not a date")).toBe("status_derived");
    expect(decisionProvenance("cron:enforce-transfer-expiry", null, A3)).toBe("status_derived");
  });

  it("each provenance has its own operator note, and reliable has none", () => {
    expect(decisionProvenanceNote("edge:confirm-and-release", AFTER_DRAIN)).toBeNull();
    expect(decisionProvenanceNote("edge:confirm-and-release", BEFORE_MIGRATION)).toMatch(/derived from status/);
    expect(decisionProvenanceNote("edge:confirm-and-release", IN_DRAIN)).toMatch(/rolling out/);
    expect(decisionProvenanceNote("edge:enforce-transfer-expiry", AFTER_DRAIN)).toMatch(/does not read the confirmation record/);
  });
});
