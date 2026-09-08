/**
 * src/lib/listing/sellerListing.ts — the pure, tested seller-listing model.
 *
 * The seller "My Listings" card and the edit-eligibility gate both derive their
 * state from the same listing fields. That derivation (the status badge, the
 * edit/delete/cancel gates, the countdown) lives here so it is proven once and
 * cannot drift between the card and the screen.
 *
 * The edit gate mirrors the server: once a bid exists or the auction is no longer
 * active, a listing is contractual and can only be cancelled, never edited or
 * deleted. `guard_listing_state_columns` + RLS enforce this server-side; this is
 * the frozen client mirror.
 */

export type SellerBadge = 'active' | 'ending_soon' | 'ended' | 'reserved' | 'sold' | 'cancelled';

/** The minimal listing shape these functions read. */
export interface SellerListingLike {
  status: string;
  auction_status: string;
  ends_at: string;
  reserved_until?: string | null;
  bid_count: number;
}

const ENDING_SOON_MS = 15 * 60 * 1000;

/** The seller-facing status for a listing. `now` is injectable for tests. */
export function sellerBadge(l: SellerListingLike, now: number = Date.now()): SellerBadge {
  if (l.auction_status === 'cancelled') return 'cancelled';
  if (l.status === 'sold') return 'sold';
  if (l.status === 'reserved' && l.reserved_until && new Date(l.reserved_until).getTime() > now) {
    return 'reserved';
  }
  const clockExpired = new Date(l.ends_at).getTime() <= now;
  if (l.auction_status === 'ended' || clockExpired) return 'ended';
  if (new Date(l.ends_at).getTime() - now <= ENDING_SOON_MS) return 'ending_soon';
  return 'active';
}

const BADGE_LABEL: Record<SellerBadge, string> = {
  active: 'Active',
  ending_soon: 'Ending soon',
  ended: 'Ended',
  reserved: 'Reserved',
  sold: 'Sold',
  cancelled: 'Cancelled',
};

export function sellerBadgeLabel(badge: SellerBadge): string {
  return BADGE_LABEL[badge];
}

export function sellerBadgeTone(badge: SellerBadge): 'neutral' | 'success' | 'warning' | 'danger' {
  switch (badge) {
    case 'active':       return 'success';
    case 'ending_soon':  return 'danger';
    case 'sold':         return 'success';
    case 'reserved':     return 'warning';
    default:             return 'neutral'; // ended, cancelled
  }
}

/** A live listing with no bids can be edited or deleted outright. */
export function canEditListing(l: SellerListingLike): boolean {
  return l.bid_count === 0 && l.auction_status === 'active' && l.status !== 'sold';
}
export const canDeleteListing = canEditListing;

/** A live listing WITH bids can only be cancelled (voids bids, keeps the record). */
export function canCancelListing(l: SellerListingLike): boolean {
  return l.bid_count > 0 && l.auction_status === 'active';
}

/** "3d 4h left" / "2h 5m left" / "12m left" / "Ended". `now` injectable for tests. */
export function timeLeftLabel(endsAt: string, now: number = Date.now()): string {
  const diff = new Date(endsAt).getTime() - now;
  if (diff <= 0) return 'Ended';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 23) return `${Math.floor(h / 24)}d ${h % 24}h left`;
  if (h > 0) return `${h}h ${m}m left`;
  return `${m}m left`;
}
