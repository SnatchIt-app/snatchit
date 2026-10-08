/**
 * src/lib/transfer-wording.ts — the web marketplace status lines.
 *
 * Authority: PAYMENT_STATE_WORDING_TABLE_20260924.md §2h (A's ruling,
 * 2026-09-25) with §2a-§2d and §2i. One asserting test per finding
 * (W-1a … W-6), plus the acceptance criteria as invariants over an
 * exhaustive input matrix.
 *
 * Finding ids are RECONSTRUCTED from §2h — the original findings file was
 * lost with D's scratchpad. The rules are the committed ones; only the
 * id↔rule mapping is a reconstruction, pending A's confirmation.
 *
 * Every timestamp literal carries a Z suffix and the module formats in a
 * fixed zone, so nothing here depends on the runner's timezone.
 */
import { describe, expect, it } from "vitest";
import {
  DISPUTE_RESOLUTIONS,
  buyerPurchaseLine,
  buyerStateAlert,
  fmtMoment,
  sellerPayoutLine,
  sellerPayoutParagraph,
  sellerStateAlert,
  transferBadgeLabel,
  type BuyerLineInput,
  type Audience,
  type OrderRowInput,
  type SellerLineInput,
  type WordingTransferStatus,
} from "@/lib/transfer-wording";

const STATUSES: WordingTransferStatus[] = [
  "pending",
  "seller_sent",
  "buyer_confirmed",
  "disputed",
  "expired",
  "auto_released",
  "reversed",
];

const buyer = (o: Partial<BuyerLineInput> = {}): BuyerLineInput => ({
  status: "pending",
  buyer_confirmed_at: null,
  dispute_resolved_at: null,
  dispute_resolution: null,
  delivery_email: "b@example.test",
  delivery_phone: null,
  ...o,
});

const seller = (o: Partial<SellerLineInput> = {}): SellerLineInput => ({
  status: "pending",
  dispute_resolved_at: null,
  dispute_resolution: null,
  payout_released_at: null,
  payout_review_status: null,
  payout_hold_until: null,
  auto_release_at: null,
  ...o,
});

// ─── One test per finding ────────────────────────────────────────────────

describe("W-1a — buyer 'expired' must not assert a refund", () => {
  it("states the expiry only", () => {
    const line = buyerPurchaseLine(buyer({ status: "expired" }));
    expect(line.text).toBe("Order expired — the seller didn't send the tickets in time.");
    expect(line.text.toLowerCase()).not.toContain("refund");
  });
});

describe("W-1b — seller 'expired' must not assert the buyer's refund", () => {
  it("states that no payout is owed, and nothing about the buyer's money", () => {
    const line = sellerPayoutLine(seller({ status: "expired" }));
    expect(line.text).toBe("Order expired — no payout for this order");
    expect(line.text.toLowerCase()).not.toContain("refund");
  });
});

describe("W-4 — \"Disputed — support is reviewing\" asserts a process the row does not record", () => {
  it("open dispute: states the payout freeze, not who is reviewing", () => {
    const line = buyerPurchaseLine(buyer({ status: "disputed" }));
    expect(line.text).toBe("Issue reported — the seller's payout is frozen until this is resolved.");
    expect(line.text.toLowerCase()).not.toContain("review");
    expect(line.text.toLowerCase()).not.toContain("support");
  });

  it("the open-dispute line is reachable (positive control for W-4)", () => {
    expect(buyerPurchaseLine(buyer({ status: "disputed" })).text).toContain("Issue reported");
  });
});

describe("W-6 — a decided dispute must not render as open", () => {
  it.each([
    ["resolved_buyer_refunded", "Resolved in your favour"],
    ["resolved_partial_refund", "Resolved"],
    ["resolved_seller_paid", "Resolved in the seller's favour"],
  ])("decided (%s) states the decision only", (resolution, expected) => {
    const line = buyerPurchaseLine(
      buyer({ status: "disputed", dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: resolution }),
    );
    expect(line.text).toBe(expected);
  });

  it("seller side: a decided-for-buyer dispute says no payout, never 'on hold'", () => {
    const line = sellerPayoutLine(
      seller({ status: "disputed", dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: "resolved_buyer_refunded" }),
    );
    expect(line.text).toBe("Resolved for the buyer — no payout for this order");
    expect(line.text.toLowerCase()).not.toContain("on hold");
  });
});

describe("W-3 — \"Confirmed\" for auto_released, and for buyer_confirmed without the record", () => {
  it("auto_released reads 'Released', never 'Confirmed'", () => {
    const line = buyerPurchaseLine(buyer({ status: "auto_released" }));
    expect(line.text).toBe("Released");
    expect(line.text).not.toContain("Confirmed");
  });

  it("buyer_confirmed WITH buyer_confirmed_at reads 'Confirmed'", () => {
    expect(buyerPurchaseLine(buyer({ status: "buyer_confirmed", buyer_confirmed_at: "2026-09-24T20:31:03Z" })).text)
      .toBe("Confirmed");
  });

  it("a seller-win leaves buyer_confirmed with no record — states the decision", () => {
    const line = buyerPurchaseLine(
      buyer({ status: "buyer_confirmed", buyer_confirmed_at: null, dispute_resolution: "resolved_seller_paid" }),
    );
    expect(line.text).toBe("Resolved in the seller's favour");
    expect(line.text).not.toContain("Confirmed");
  });

  it("buyer_confirmed with neither record nor decision reads 'Order closed' (A, 2026-10-05)", () => {
    expect(buyerPurchaseLine(buyer({ status: "buyer_confirmed" })).text).toBe("Order closed");
  });
});

describe("W-2 — \"Paid out\" from payoutReleasedAt alone, on a reversed row", () => {
  it("'reversed' outranks payout_released_at", () => {
    const line = sellerPayoutLine(
      seller({ status: "reversed", payout_released_at: "2026-09-20T10:00:00Z" }),
    );
    expect(line.text).toBe("Payout reversed");
  });

  it("states no amount and no cause", () => {
    const { text } = sellerPayoutLine(seller({ status: "reversed", payout_released_at: "2026-09-20T10:00:00Z" }));
    expect(text).not.toMatch(/\$|dispute|operator|fully|all/i);
  });

  it("the buyer side derives nothing from the seller's reversal", () => {
    expect(buyerPurchaseLine(buyer({ status: "reversed" })).text).toBe("");
  });
});

describe("W-5 — \"On hold\" and \"Payout processing\", and the rest of the precedence", () => {
  it("payout evidence reads 'Payout released', never 'Paid out' or 'received'", () => {
    const { text } = sellerPayoutLine(
      seller({ status: "buyer_confirmed", payout_released_at: "2026-09-24T21:00:00Z" }),
    );
    expect(text).toBe("Payout released");
    expect(text).not.toMatch(/paid out|received/i);
  });

  it("manual_review has no date", () => {
    const { text } = sellerPayoutLine(seller({ status: "seller_sent", payout_review_status: "manual_review" }));
    expect(text).toBe("Payout under review");
    expect(text).not.toMatch(/\d/);
  });

  it("a hold with a stored end names it; without one, no end is implied", () => {
    expect(sellerPayoutLine(seller({ status: "seller_sent", payout_review_status: "held", payout_hold_until: "2026-10-02T23:00:00Z" })).text)
      .toBe("Payout held until Oct 2, 7:00 PM");
    const noEnd = sellerPayoutLine(seller({ status: "seller_sent", payout_review_status: "held" }));
    expect(noEnd.text).toBe("Payout held");
    expect(noEnd.text).not.toContain("event");
  });

  it("seller_sent states the scheduled decision time, not a countdown", () => {
    const { text } = sellerPayoutLine(seller({ status: "seller_sent", auto_release_at: "2026-09-27T16:30:00Z" }));
    expect(text).toBe("Release decision at Sep 27, 12:30 PM");
    expect(text).not.toMatch(/passed|remaining|left|Expired/i);
  });

  it("released by decision but not yet paid is 'payout pending'", () => {
    expect(sellerPayoutLine(seller({ status: "auto_released" })).text).toBe("Release approved — payout pending");
  });
});

// ─── Acceptance criteria as invariants over an exhaustive matrix ──────────

const RESOLUTIONS = [null, ...DISPUTE_RESOLUTIONS];
const TIMES = [null, "2026-09-24T20:00:00Z"];

function everyBuyerLine(): string[] {
  const out: string[] = [];
  for (const status of STATUSES)
    for (const dispute_resolution of RESOLUTIONS)
      for (const dispute_resolved_at of TIMES)
        for (const buyer_confirmed_at of TIMES)
          for (const delivery_email of [null, "b@example.test"])
            out.push(buyerPurchaseLine(buyer({ status, dispute_resolution, dispute_resolved_at, buyer_confirmed_at, delivery_email })).text);
  return out;
}

function everySellerLine(): string[] {
  const out: string[] = [];
  for (const status of STATUSES)
    for (const dispute_resolution of RESOLUTIONS)
      for (const dispute_resolved_at of TIMES)
        for (const payout_released_at of TIMES)
          for (const payout_review_status of [null, "manual_review", "held"])
            for (const payout_hold_until of TIMES)
              for (const auto_release_at of TIMES)
                out.push(sellerPayoutLine(seller({ status, dispute_resolution, dispute_resolved_at, payout_released_at, payout_review_status, payout_hold_until, auto_release_at })).text);
  return out;
}

describe("acceptance criteria (§2h), over every reachable input", () => {
  it("the matrix is non-trivial and the matcher can fire — positive control", () => {
    const all = [...everyBuyerLine(), ...everySellerLine()];
    expect(all.length).toBeGreaterThan(500);
    expect(all.filter((t) => t !== "").length).toBeGreaterThan(100);
    // The /refund/i matcher used below does fire on the withdrawn strings.
    expect(["Expired — refunded in full", "Expired — buyer refunded"].filter((t) => /refund/i.test(t)))
      .toHaveLength(2);
  });

  it("1. no string containing 'refund' is reachable from these surfaces", () => {
    expect([...everyBuyerLine(), ...everySellerLine()].filter((t) => /refund/i.test(t))).toEqual([]);
  });

  it("3. no payout string says 'received', and completion never appears on a reversed row", () => {
    expect(everySellerLine().filter((t) => /received/i.test(t))).toEqual([]);
    for (const dispute_resolution of RESOLUTIONS)
      for (const payout_released_at of TIMES)
        expect(sellerPayoutLine(seller({ status: "reversed", dispute_resolution, payout_released_at })).text)
          .toBe("Payout reversed");
  });

  it("4. 'Confirmed' is reachable only with buyer_confirmed_at", () => {
    for (const status of STATUSES)
      for (const dispute_resolution of RESOLUTIONS) {
        const text = buyerPurchaseLine(buyer({ status, dispute_resolution, buyer_confirmed_at: null })).text;
        expect(text, `${status}/${dispute_resolution}`).not.toContain("Confirmed");
      }
    expect(buyerPurchaseLine(buyer({ status: "buyer_confirmed", buyer_confirmed_at: "2026-09-24T20:31:03Z" })).text)
      .toBe("Confirmed");
  });

  it("4. nothing derives a payout from resolved_seller_paid alone", () => {
    const { text } = sellerPayoutLine(
      seller({ status: "disputed", dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: "resolved_seller_paid" }),
    );
    expect(text).toBe("Resolved in your favour — payout pending");
    expect(text).not.toMatch(/released|paid/i);
  });

  it("5. no copy asserts a human activity", () => {
    const all = [...everyBuyerLine(), ...everySellerLine()];
    expect(all.filter((t) => /support is reviewing|our team|typically|within \d+ hours/i.test(t))).toEqual([]);
  });

  it("6. a resolved dispute never renders as open", () => {
    for (const resolution of DISPUTE_RESOLUTIONS) {
      const b = buyerPurchaseLine(buyer({ status: "disputed", dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: resolution })).text;
      const s = sellerPayoutLine(seller({ status: "disputed", dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: resolution })).text;
      expect(b, resolution).toMatch(/^Resolved/);
      expect(s, resolution).not.toContain("the buyer reported an issue");
    }
  });
});

describe("fmtMoment", () => {
  it("formats in a fixed zone, so the string does not depend on the runner", () => {
    expect(fmtMoment("2026-09-24T20:31:03Z")).toBe("Sep 24, 4:31 PM");
  });
  it("null and unparseable input produce no date, never 'Invalid Date'", () => {
    expect(fmtMoment(null)).toBeNull();
    expect(fmtMoment("")).toBeNull();
    expect(fmtMoment("not-a-date")).toBeNull();
  });
});

// ─── The two transfer panels and the badge (A's rulings, 2026-10-05) ──────

const AUDIENCES: Audience[] = ["buyer", "seller"];

const row = (o: Partial<OrderRowInput> = {}): OrderRowInput => ({
  status: "pending",
  buyer_confirmed_at: null,
  dispute_resolved_at: null,
  dispute_resolution: null,
  payout_released_at: null,
  payout_review_status: null,
  payout_hold_until: null,
  auto_release_at: null,
  ...o,
});

describe("W-1c — the buyer panel must not assert a refund from 'expired'", () => {
  it("states the cancellation only", () => {
    const a = buyerStateAlert(row({ status: "expired" }));
    expect(a?.text).toBe("The seller didn't send the tickets in time, so this order was cancelled.");
    expect(a?.text.toLowerCase()).not.toContain("refund");
  });
});

describe("W-1d — the seller panel must not assert the buyer's refund from 'expired'", () => {
  it("states the cancellation and that no payout is owed, with no assumed window length", () => {
    const a = sellerStateAlert(row({ status: "expired" }));
    expect(a?.text).toBe(
      "The transfer window passed without a transfer, so this order was cancelled. No payout for this order.",
    );
    expect(a?.text.toLowerCase()).not.toContain("refund");
    // §2a: the window is transfers.expires_at, read from the row — never a
    // constant baked into copy.
    expect(a?.text).not.toMatch(/\d+\s*-?\s*hour|24/i);
  });
});

describe("the panels: no asserted human activity, and no decided dispute shown as open", () => {
  it("buyer: an open dispute names the payout freeze, not a team or an SLA", () => {
    const a = buyerStateAlert(row({ status: "disputed" }));
    expect(a?.text).toBe("Issue reported. The seller's payout is frozen until this is resolved.");
    expect(a?.text).not.toMatch(/our team|typically|24 hours/i);
  });

  it("seller: an open dispute says frozen, never 'on hold while our team reviews'", () => {
    const a = sellerStateAlert(row({ status: "disputed" }));
    expect(a?.text).toBe("The buyer reported a problem. Your payout is frozen until this is resolved.");
    expect(a?.text).not.toMatch(/our team|on hold/i);
  });

  it.each(DISPUTE_RESOLUTIONS)("a decided dispute (%s) never renders as open on either panel", (res) => {
    const d = { status: "disputed" as const, dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: res };
    expect(buyerStateAlert(row(d))?.text).not.toMatch(/Issue reported/);
    expect(sellerStateAlert(row(d))?.text).not.toMatch(/reported a problem/);
  });

  it("seller: a seller-win claims a payout only with payout evidence", () => {
    const d = { status: "disputed" as const, dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: "resolved_seller_paid" };
    expect(sellerStateAlert(row(d))?.text).toBe("Resolved in your favour — payout pending.");
    expect(sellerStateAlert(row({ ...d, payout_released_at: "2026-09-25T10:00:00Z" }))?.text)
      .toBe("Resolved in your favour. Payout released.");
  });

  it("seller: a seller-win under review or on a hold reads items 7-8, not 'pending'", () => {
    const d = { status: "disputed" as const, dispute_resolved_at: "2026-09-24T20:00:00Z", dispute_resolution: "resolved_seller_paid" };
    expect(sellerStateAlert(row({ ...d, payout_review_status: "manual_review" }))?.text)
      .toBe("Resolved in your favour. Payout under review.");
    expect(sellerStateAlert(row({ ...d, payout_review_status: "held", payout_hold_until: "2026-10-02T23:00:00Z" }))?.text)
      .toBe("Resolved in your favour. Payout held until Oct 2, 7:00 PM.");
    expect(sellerStateAlert(row({ ...d, payout_review_status: "held" }))?.text)
      .toBe("Resolved in your favour. Payout held.");
  });

  it("seller: completion claims a payout only with payout evidence", () => {
    expect(sellerStateAlert(row({ status: "auto_released" }))?.text)
      .toBe("Transfer complete. No payout has been recorded yet — make sure payouts are set up in Settings.");
    expect(sellerStateAlert(row({ status: "auto_released", payout_released_at: "2026-09-25T10:00:00Z" }))?.text)
      .toBe("Transfer complete and payout released.");
  });

  it("buyer: the no-record cell is closed, and a seller-win states the decision", () => {
    expect(buyerStateAlert(row({ status: "buyer_confirmed" }))?.text).toBe("This order is closed.");
    expect(buyerStateAlert(row({ status: "buyer_confirmed", dispute_resolution: "resolved_seller_paid" }))?.text)
      .toBe("The dispute was resolved in the seller's favour.");
  });
});

describe("the badge reads the row and the audience, not the status alone", () => {
  it("buyer_confirmed is complete only with the confirmation record", () => {
    for (const aud of AUDIENCES) {
      expect(transferBadgeLabel(row({ status: "buyer_confirmed", buyer_confirmed_at: "2026-09-24T20:31:03Z" }), aud))
        .toBe("Transfer Complete");
      expect(transferBadgeLabel(row({ status: "buyer_confirmed" }), aud)).toBe("Closed");
      expect(transferBadgeLabel(row({ status: "buyer_confirmed", dispute_resolution: "resolved_seller_paid" }), aud))
        .toBe("Closed");
    }
  });

  it("seller_sent is the seller's own update, not a delivery fact", () => {
    for (const aud of AUDIENCES) expect(transferBadgeLabel(row({ status: "seller_sent" }), aud)).toBe("Marked sent");
  });

  it("auto_released is a release decision, never payout evidence (§2i)", () => {
    for (const aud of AUDIENCES) {
      expect(transferBadgeLabel(row({ status: "auto_released" }), aud)).toBe("Released");
      expect(transferBadgeLabel(row({ status: "auto_released" }), aud)).not.toMatch(/Payout/);
    }
  });

  it("reversed is the SELLER's payout event; the buyer is never told it (§2c)", () => {
    expect(transferBadgeLabel(row({ status: "reversed" }), "seller")).toBe("Payout Reversed");
    expect(transferBadgeLabel(row({ status: "reversed" }), "buyer")).toBe("Closed");
    expect(transferBadgeLabel(row({ status: "reversed" }), "buyer")).not.toMatch(/Payout|Payment|Reversed/);
  });

  it("no buyer-facing badge states a payout fact, over every input", () => {
    for (const status of STATUSES)
      for (const dispute_resolution of RESOLUTIONS)
        for (const payout_released_at of TIMES)
          expect(transferBadgeLabel(row({ status, dispute_resolution, payout_released_at }), "buyer"),
                 `${status}/${dispute_resolution}`).not.toMatch(/Payout|Paid|Reversed/);
  });

  it("a decided dispute does not badge as open", () => {
    for (const aud of AUDIENCES) {
      expect(transferBadgeLabel(row({ status: "disputed" }), aud)).toBe("Disputed");
      expect(transferBadgeLabel(row({ status: "disputed", dispute_resolved_at: "2026-09-24T20:00:00Z" }), aud))
        .toBe("Dispute Resolved");
    }
  });

  it("no badge asserts completion without the record, over every input", () => {
    // Checking only the literal "Confirmed" was vacuous here: the badge says
    // "Transfer Complete", which asserts the same thing in other words and
    // survived the mutant. Match the claim, not the word.
    for (const status of STATUSES)
      for (const dispute_resolution of RESOLUTIONS)
        for (const aud of AUDIENCES)
          expect(transferBadgeLabel(row({ status, dispute_resolution }), aud), `${status}/${dispute_resolution}/${aud}`)
            .not.toMatch(/Confirmed|Complete/);
    expect(transferBadgeLabel(row({ status: "buyer_confirmed", buyer_confirmed_at: "2026-09-24T20:31:03Z" }), "seller"))
      .toBe("Transfer Complete");
  });
});

describe("the seller payout paragraph (§2e): a scheduled time, never a countdown", () => {
  it("states exactly the scheduled decision, and promises no outcome", () => {
    const t = sellerPayoutParagraph(row({ status: "seller_sent", auto_release_at: "2026-09-27T16:30:00Z" }));
    expect(t).toBe("Release decision at Sep 27, 12:30 PM.");
    // The decision can be a release, a hold or manual review, and a buyer
    // confirmation does not guarantee a payout either (§2e, A 2026-10-05).
    expect(t).not.toMatch(/releases|payout|confirm/i);
  });

  it("says nothing at all when auto_release_at is absent", () => {
    expect(sellerPayoutParagraph(row({ status: "seller_sent", auto_release_at: null }))).toBe("");
  });

  it("never says the window has passed, and never reads a countdown", () => {
    for (const auto_release_at of [null, "2020-01-01T00:00:00Z", "2030-01-01T00:00:00Z"]) {
      const t = sellerPayoutParagraph(row({ status: "seller_sent", auto_release_at }));
      expect(t).not.toMatch(/window has passed|being processed|remaining|left\b/i);
    }
  });

  it("a hold names its stored end, or implies none, and does not characterise it", () => {
    expect(sellerPayoutParagraph(row({ payout_review_status: "held", payout_hold_until: "2026-10-02T23:00:00Z" })))
      .toBe("Your payout is held until Oct 2, 7:00 PM.");
    expect(sellerPayoutParagraph(row({ payout_review_status: "held" }))).toBe("Your payout is held.");
    for (const payout_hold_until of TIMES)
      expect(sellerPayoutParagraph(row({ payout_review_status: "held", payout_hold_until })))
        .not.toMatch(/standard|protection|after the event/i);
  });

  it("manual review carries no date", () => {
    const t = sellerPayoutParagraph(row({ payout_review_status: "manual_review" }));
    expect(t).toContain("under manual review");
    expect(t).not.toMatch(/\d{4}|Sep|Oct/);
  });
});

describe("criterion 1 over the panels and the badge too", () => {
  it("no 'refund' string is reachable from any of them", () => {
    const out: string[] = [];
    for (const status of STATUSES)
      for (const dispute_resolution of RESOLUTIONS)
        for (const dispute_resolved_at of TIMES)
          for (const payout_released_at of TIMES)
            for (const buyer_confirmed_at of TIMES) {
              const r = row({ status, dispute_resolution, dispute_resolved_at, payout_released_at, buyer_confirmed_at });
              out.push(buyerStateAlert(r)?.text ?? "", sellerStateAlert(r)?.text ?? "",
                       transferBadgeLabel(r, "buyer"), transferBadgeLabel(r, "seller"), sellerPayoutParagraph(r));
            }
    expect(out.length).toBeGreaterThan(500);
    expect(out.filter((t) => /refund/i.test(t))).toEqual([]);
    // positive control: the withdrawn panel strings would have matched
    expect([
      "The seller didn't send in time, so this order was cancelled and refunded in full.",
      "The 24-hour window passed without a transfer, so the buyer was refunded.",
    ].filter((t) => /refund/i.test(t))).toHaveLength(2);
  });
});
