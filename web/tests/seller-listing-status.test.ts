/**
 * src/lib/seller-listing-status.ts — first coverage for this module.
 *
 * Two things are load-bearing and asserted exhaustively here:
 *   1. sellerBadge precedence (cancelled -> sold -> unexpired reservation ->
 *      ended/clock -> ending soon -> active), ported from mobile.
 *   2. The canEdit / canDelete / canCancel gates. They are presentational, but
 *      "presentational" is exactly how a listing with live bids ends up with
 *      an Edit button, so the full badge x bid-count matrix is pinned.
 *
 * `now` is always an explicit epoch number and every timestamp literal carries
 * a Z suffix, so nothing here depends on the runner's timezone.
 */
import { describe, expect, it } from "vitest";
import {
  canCancel,
  canDelete,
  canEdit,
  inBucket,
  sellerBadge,
  type SellerBadge,
  type SellerFilter,
  type SellerStatusInput,
} from "@/lib/seller-listing-status";
import { listingCardStatus } from "@/lib/format";

const NOW = new Date("2026-07-27T12:00:00Z").getTime();
const MIN = 60_000;
const at = (ms: number) => new Date(NOW + ms).toISOString();

const ALL_BADGES: SellerBadge[] = [
  "ACTIVE",
  "ENDING SOON",
  "ENDED",
  "RESERVED",
  "SOLD",
  "CANCELLED",
];

const row = (over: Partial<SellerStatusInput> = {}): SellerStatusInput => ({
  status: "active",
  auction_status: "active",
  ends_at: at(30 * 24 * 60 * MIN),
  reserved_until: null,
  ...over,
});

describe("sellerBadge — precedence", () => {
  it("cancelled wins over everything, including sold and a live reservation", () => {
    expect(sellerBadge(row({ auction_status: "cancelled" }), NOW)).toBe("CANCELLED");
    expect(sellerBadge(row({ auction_status: "cancelled", status: "sold" }), NOW)).toBe("CANCELLED");
    expect(
      sellerBadge(
        row({ auction_status: "cancelled", status: "reserved", reserved_until: at(30 * MIN) }),
        NOW,
      ),
    ).toBe("CANCELLED");
    expect(sellerBadge(row({ auction_status: "cancelled", ends_at: at(-MIN) }), NOW)).toBe("CANCELLED");
  });

  it("sold wins over a reservation and over the clock", () => {
    expect(sellerBadge(row({ status: "sold", reserved_until: at(30 * MIN) }), NOW)).toBe("SOLD");
    expect(sellerBadge(row({ status: "sold", ends_at: at(-MIN) }), NOW)).toBe("SOLD");
    expect(sellerBadge(row({ status: "sold", auction_status: "ended" }), NOW)).toBe("SOLD");
    // Only the `status` column marks a seller row sold — auction_status alone
    // does not, unlike listingCardStatus. Pinned so the divergence is visible.
    expect(sellerBadge(row({ auction_status: "sold" }), NOW)).toBe("ACTIVE");
  });

  it("an unexpired reservation outranks the clock; an expired one falls through", () => {
    expect(sellerBadge(row({ status: "reserved", reserved_until: at(30 * MIN) }), NOW)).toBe("RESERVED");
    expect(
      sellerBadge(row({ status: "reserved", reserved_until: at(30 * MIN), ends_at: at(-MIN) }), NOW),
    ).toBe("RESERVED");
    // Expired hold -> deliberately NOT reserved (matches cleanup_expired_reservations).
    expect(sellerBadge(row({ status: "reserved", reserved_until: at(-1) }), NOW)).toBe("ACTIVE");
    expect(
      sellerBadge(row({ status: "reserved", reserved_until: at(-MIN), ends_at: at(-MIN) }), NOW),
    ).toBe("ENDED");
    // Missing / unparseable reserved_until also falls through (fails closed).
    expect(sellerBadge(row({ status: "reserved", reserved_until: null }), NOW)).toBe("ACTIVE");
    expect(sellerBadge(row({ status: "reserved", reserved_until: "garbage" }), NOW)).toBe("ACTIVE");
    expect(sellerBadge(row({ status: "reserved", reserved_until: "" }), NOW)).toBe("ACTIVE");
  });

  it("uses exclusive reservation and inclusive clock boundaries", () => {
    // reserved_until === now is NOT still reserved (strict >).
    expect(sellerBadge(row({ status: "reserved", reserved_until: at(0) }), NOW)).toBe("ACTIVE");
    expect(sellerBadge(row({ status: "reserved", reserved_until: at(1) }), NOW)).toBe("RESERVED");
    // ends_at === now IS ended (<=).
    expect(sellerBadge(row({ ends_at: at(0) }), NOW)).toBe("ENDED");
    expect(sellerBadge(row({ ends_at: at(1) }), NOW)).toBe("ENDING SOON");
    // ENDING SOON window is 15 minutes, inclusive.
    expect(sellerBadge(row({ ends_at: at(15 * MIN) }), NOW)).toBe("ENDING SOON");
    expect(sellerBadge(row({ ends_at: at(15 * MIN + 1) }), NOW)).toBe("ACTIVE");
    // auction_status='ended' beats a future clock.
    expect(sellerBadge(row({ auction_status: "ended" }), NOW)).toBe("ENDED");
  });

  it("BUG: an unparseable ends_at falls open to ACTIVE (and therefore editable)", () => {
    // NaN loses both comparisons, so a row whose end time cannot be read is
    // shown as ACTIVE and canEdit/canDelete return true for it.
    // Expected: ENDED (fail closed). Same defect as listingCardStatus, which
    // returns LIVE for the same input. ends_at is NOT NULL in the DB, so this
    // is latent rather than live.
    const bad = row({ ends_at: "garbage" });
    expect(sellerBadge(bad, NOW)).toBe("ACTIVE");
    expect(canEdit(sellerBadge(bad, NOW), 0)).toBe(true);
    expect(sellerBadge(row({ ends_at: "" }), NOW)).toBe("ACTIVE");
    // A null ends_at coerces to epoch 0 and does end up ENDED.
    expect(sellerBadge(row({ ends_at: null as unknown as string }), NOW)).toBe("ENDED");
  });

  it("matches status strings exactly (case-sensitive)", () => {
    expect(sellerBadge(row({ auction_status: "CANCELLED" }), NOW)).toBe("ACTIVE");
    expect(sellerBadge(row({ status: "SOLD" }), NOW)).toBe("ACTIVE");
    expect(sellerBadge(row({ status: "<script>" }), NOW)).toBe("ACTIVE");
  });

  it("agrees with listingCardStatus on a cancelled-but-sold row", () => {
    // Both modules must treat cancelled as terminal, not sold — otherwise the
    // seller sees CANCELLED while buyers see a SOLD card.
    const cancelledSold = { status: "sold", auction_status: "cancelled", ends_at: at(30 * MIN) };
    expect(sellerBadge({ ...cancelledSold, reserved_until: null }, NOW)).toBe("CANCELLED");
    expect(listingCardStatus(cancelledSold, new Date(NOW))).toBe("ENDED");
  });
});

describe("inBucket", () => {
  it("puts every badge in exactly one of active / sold / ended", () => {
    const exclusive: SellerFilter[] = ["active", "sold", "ended"];
    for (const badge of ALL_BADGES) {
      const hits = exclusive.filter((b) => inBucket(badge, false, b));
      expect(hits, `${badge} -> ${hits.join(",")}`).toHaveLength(1);
    }
  });

  it("maps each badge to the tab mobile shows it in", () => {
    expect(inBucket("ACTIVE", false, "active")).toBe(true);
    expect(inBucket("ENDING SOON", false, "active")).toBe(true);
    expect(inBucket("RESERVED", false, "active")).toBe(true);
    expect(inBucket("SOLD", false, "sold")).toBe(true);
    expect(inBucket("ENDED", false, "ended")).toBe(true);
    expect(inBucket("CANCELLED", false, "ended")).toBe(true);
  });

  it("'all' takes everything and 'needs_action' ignores the badge entirely", () => {
    for (const badge of ALL_BADGES) {
      expect(inBucket(badge, false, "all"), badge).toBe(true);
      expect(inBucket(badge, true, "needs_action"), badge).toBe(true);
      expect(inBucket(badge, false, "needs_action"), badge).toBe(false);
    }
  });

  it("returns undefined (falsy — filters the row out) for an unknown bucket", () => {
    expect(inBucket("SOLD", true, "archived" as SellerFilter)).toBeUndefined();
  });
});

describe("canEdit / canDelete / canCancel — full matrix", () => {
  const EDITABLE: SellerBadge[] = ["ACTIVE", "ENDING SOON"];
  const CANCELLABLE: SellerBadge[] = ["ACTIVE", "ENDING SOON", "RESERVED"];

  it("NO badge permits editing or deleting a listing that has bids", () => {
    // The gate that matters: bids create a financial obligation, so the item
    // must be immutable. Re-checked server-side against the real bids count
    // because listings.bid_count is seller-writable.
    for (const badge of ALL_BADGES) {
      for (const bids of [1, 2, 50, 0.5]) {
        expect(canEdit(badge, bids), `${badge}/${bids}`).toBe(false);
        expect(canDelete(badge, bids), `${badge}/${bids}`).toBe(false);
      }
    }
  });

  it("permits edit/delete only for ACTIVE and ENDING SOON at zero bids", () => {
    for (const badge of ALL_BADGES) {
      const expected = EDITABLE.includes(badge);
      expect(canEdit(badge, 0), badge).toBe(expected);
      expect(canDelete(badge, 0), badge).toBe(expected);
    }
  });

  it("permits cancel only for live/reserved badges that actually have bids", () => {
    for (const badge of ALL_BADGES) {
      expect(canCancel(badge, 0), `${badge}/0`).toBe(false);
      expect(canCancel(badge, 1), `${badge}/1`).toBe(CANCELLABLE.includes(badge));
      expect(canCancel(badge, 99), `${badge}/99`).toBe(CANCELLABLE.includes(badge));
    }
  });

  it("never offers edit and cancel at the same time", () => {
    for (const badge of ALL_BADGES) {
      for (const bids of [0, 1, 2, 99]) {
        expect(canEdit(badge, bids) && canCancel(badge, bids), `${badge}/${bids}`).toBe(false);
      }
    }
  });

  it("fails closed on NaN and negative bid counts", () => {
    // A NaN count (e.g. a failed head-count query coerced to a number) must
    // not unlock edit or cancel.
    for (const badge of ALL_BADGES) {
      for (const bids of [NaN, -1, -99]) {
        expect(canEdit(badge, bids), `${badge}/${bids}`).toBe(false);
        expect(canDelete(badge, bids), `${badge}/${bids}`).toBe(false);
        expect(canCancel(badge, bids), `${badge}/${bids}`).toBe(false);
      }
    }
  });

  it("treats a terminal badge as immutable regardless of bid count", () => {
    for (const badge of ["SOLD", "ENDED", "CANCELLED"] as SellerBadge[]) {
      for (const bids of [0, 1, 99, NaN]) {
        expect(canEdit(badge, bids), `${badge}/${bids}`).toBe(false);
        expect(canDelete(badge, bids), `${badge}/${bids}`).toBe(false);
        expect(canCancel(badge, bids), `${badge}/${bids}`).toBe(false);
      }
    }
  });

  it("end-to-end: a bid on an ending-soon listing removes edit and adds cancel", () => {
    const listing = row({ ends_at: at(10 * MIN) });
    const badge = sellerBadge(listing, NOW);
    expect(badge).toBe("ENDING SOON");
    expect(canEdit(badge, 0)).toBe(true);
    expect(canCancel(badge, 0)).toBe(false);
    expect(canEdit(badge, 1)).toBe(false);
    expect(canCancel(badge, 1)).toBe(true);
  });
});
