/**
 * Seller-facing listing status, ported verbatim from mobile's
 * SellerListingCard.getBadge (src/components/SellerListingCard.tsx).
 *
 * Precedence is load-bearing and must not be reordered:
 *   cancelled → sold → reserved(unexpired) → ended/clock-expired
 *   → ending-soon(≤15min) → active
 *
 * An EXPIRED reservation deliberately falls through to ENDED/ACTIVE rather
 * than showing RESERVED — matching mobile, and matching the DB, where
 * cleanup_expired_reservations() releases the hold.
 *
 * `now` is a parameter so this stays pure: badges are computed once on the
 * server and passed down, which also avoids a hydration mismatch on the
 * time-sensitive ENDING SOON / ENDED boundaries.
 */

export type SellerBadge = "ACTIVE" | "ENDING SOON" | "ENDED" | "RESERVED" | "SOLD" | "CANCELLED";

export type SellerStatusInput = {
  status: string;
  auction_status: string;
  ends_at: string;
  reserved_until: string | null;
};

const ENDING_SOON_MS = 15 * 60 * 1000; // matches mobile

export function sellerBadge(l: SellerStatusInput, now: number): SellerBadge {
  if (l.auction_status === "cancelled") return "CANCELLED";
  if (l.status === "sold") return "SOLD";
  if (l.status === "reserved" && l.reserved_until && new Date(l.reserved_until).getTime() > now) {
    return "RESERVED";
  }
  const clockExpired = new Date(l.ends_at).getTime() <= now;
  if (l.auction_status === "ended" || clockExpired) return "ENDED";
  if (new Date(l.ends_at).getTime() - now <= ENDING_SOON_MS) return "ENDING SOON";
  return "ACTIVE";
}

/** Filter buckets from mobile's my-listings tabs — mutually exclusive. */
export type SellerFilter = "all" | "active" | "needs_action" | "sold" | "ended";

export function inBucket(badge: SellerBadge, needsTicketSend: boolean, bucket: SellerFilter): boolean {
  switch (bucket) {
    case "all":
      return true;
    case "needs_action":
      return needsTicketSend;
    case "sold":
      return badge === "SOLD";
    case "ended":
      return badge === "ENDED" || badge === "CANCELLED";
    case "active":
      return badge === "ACTIVE" || badge === "ENDING SOON" || badge === "RESERVED";
  }
}

/**
 * Eligibility, mirroring mobile's SellerListingCard gates. These are
 * PRESENTATIONAL ONLY — every one of them is re-checked server-side in
 * seller-listings.ts against the real `bids` row count, because
 * listings.bid_count is NOT protected by guard_listing_state_columns() and
 * a seller can write to it directly.
 */
export function canEdit(badge: SellerBadge, realBidCount: number): boolean {
  return (badge === "ACTIVE" || badge === "ENDING SOON") && realBidCount === 0;
}

export function canDelete(badge: SellerBadge, realBidCount: number): boolean {
  return (badge === "ACTIVE" || badge === "ENDING SOON") && realBidCount === 0;
}

export function canCancel(badge: SellerBadge, realBidCount: number): boolean {
  return (badge === "ACTIVE" || badge === "ENDING SOON" || badge === "RESERVED") && realBidCount > 0;
}
