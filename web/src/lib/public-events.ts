import { allInFromDollars, buyerTotalCents, dollarsToCents } from "@snatchit/core";
import type { WebListing } from "@/lib/listings";
import {
  categoryLabel,
  coverImageUrl,
  fmtEventDate,
  fmtEventTime,
  listingCardStatus,
  neighborhoodLabel,
} from "@/lib/format";

/**
 * Public event-discovery contract for the marketing site.
 *
 * This is a PROJECTION of the same rows /browse renders — getActiveListings'
 * predicate (status='active' AND auction_status='active' AND ends_at > now())
 * is the one canonical definition of "publicly discoverable", and this module
 * never re-decides it. It only reshapes a WebListing into display data and
 * strips everything a marketing page has no business seeing.
 *
 * Deliberately EVENT-shaped rather than listing-shaped: production today has
 * no events table — the event fields live denormalized on each marketplace
 * listing — but the ratified Phase 2 schema introduces catalog.event /
 * catalog.event_session as the primary-ticketing model. Consumers of this
 * shape never learn which backing model produced it, so when primary
 * ticketing lands the same contract serves both without a marketing-side
 * change.
 *
 * Excluded on purpose, not by omission: seller_id, winner_user_id,
 * transfer_method, starting_bid, and every operational/status column. The
 * marketing site displays and deep-links; it does not reason about sellers,
 * auctions' internals, or inventory state.
 *
 * All prices are ALL-IN buyer prices (base × (1 + BUYER_FEE_RATE)) in integer
 * cents plus a preformatted label — the same fee-inclusive standard every
 * public surface of the product shows. Never expose base prices here; a
 * marketing card showing $2.00 next to a product page charging $2.20 is a
 * bait-and-switch bug.
 */
export type PublicEvent = {
  id: string;
  title: string;
  venue: string;
  /** The product is Miami-only; neighborhood is the real location field. */
  city: "Miami";
  neighborhood: { key: string; label: string };
  category: { key: string; label: string };
  /**
   * Miami-local by product definition. event_date/event_time are stored as
   * plain date/time strings and formatted without timezone conversion —
   * consumers deriving "this weekend" should treat these as America/New_York
   * wall-clock values, never as UTC.
   */
  date: string; // YYYY-MM-DD
  time: string; // HH:MM:SS
  dateLabel: string; // "Sat, Oct 17, 2026" — app's own formatter
  timeLabel: string; // "11:00 PM"
  /** Public storage URL (auction-media bucket is public-read). */
  imageUrl: string;
  /** Canonical product page. Deep-link here; do not reconstruct routes. */
  url: string;
  /** "live" | "ending_soon" — ending_soon means the LISTING closes within 24h. */
  status: "live" | "ending_soon";
  /** When the listing itself stops being purchasable (ISO). Not the event date. */
  listingEndsAt: string;
  ticketType: string;
  quantity: number;
  pricing: {
    currency: "USD";
    /** Current price to beat, all-in. For Buy Now-only display, prefer buyNow. */
    currentAllInCents: number;
    currentAllInLabel: string; // e.g. "$6.60 all-in"
    buyNow:
      | { enabled: true; allInCents: number; allInLabel: string }
      | { enabled: false };
  };
  /** Real demand signals only. There is no trending score — do not invent one. */
  demand: { bidCount: number };
};

export function toPublicEvent(l: WebListing, siteUrl: string, now: Date = new Date()): PublicEvent {
  const status = listingCardStatus(l, now);
  return {
    id: l.id,
    title: l.event_name,
    venue: l.venue,
    city: "Miami",
    neighborhood: { key: l.neighborhood, label: neighborhoodLabel(l.neighborhood) },
    category: { key: l.category, label: categoryLabel(l.category) },
    date: l.event_date,
    time: l.event_time,
    dateLabel: fmtEventDate(l.event_date),
    timeLabel: fmtEventTime(l.event_time),
    imageUrl: coverImageUrl(l.cover_image_path),
    url: `${siteUrl}/listing/${l.id}`,
    status: status === "ENDING SOON" ? "ending_soon" : "live",
    listingEndsAt: l.ends_at,
    ticketType: l.ticket_type,
    quantity: l.quantity,
    pricing: {
      currency: "USD",
      currentAllInCents: buyerTotalCents(dollarsToCents(l.current_bid)),
      currentAllInLabel: `${allInFromDollars(l.current_bid)} all-in`,
      buyNow:
        l.buy_now_enabled && l.buy_now_price
          ? {
              enabled: true,
              allInCents: buyerTotalCents(dollarsToCents(l.buy_now_price)),
              allInLabel: `${allInFromDollars(l.buy_now_price)} all-in`,
            }
          : { enabled: false },
    },
    demand: { bidCount: l.bid_count },
  };
}

/**
 * Inclusive event_date window. Dates compare lexicographically because both
 * sides are YYYY-MM-DD — no Date construction, so no timezone drift on
 * date-only values (the same reason fmtEventDate avoids the Date parser).
 */
export function inDateWindow(eventDate: string, from?: string, to?: string): boolean {
  if (from && eventDate < from) return false;
  if (to && eventDate > to) return false;
  return true;
}

export type PublicEventSort = "soonest" | "ending" | "most_bids";

/**
 * Deterministic orderings from real fields. "soonest" (default) is soonest
 * EVENT first — the discovery-natural order; /browse's own default is
 * "ending" (listing closes first). "most_bids" is the only demand ordering we
 * can offer honestly: bid_count is trigger-maintained from real bids, and no
 * view/impression/trending signal exists in the product today.
 */
export function sortPublicEvents(events: PublicEvent[], sort: PublicEventSort): PublicEvent[] {
  const byId = (a: PublicEvent, b: PublicEvent) => a.id.localeCompare(b.id);
  const copy = [...events];
  switch (sort) {
    case "most_bids":
      return copy.sort(
        (a, b) => b.demand.bidCount - a.demand.bidCount || a.date.localeCompare(b.date) || byId(a, b),
      );
    case "ending":
      return copy.sort((a, b) => a.listingEndsAt.localeCompare(b.listingEndsAt) || byId(a, b));
    case "soonest":
    default:
      return copy.sort(
        (a, b) => a.date.localeCompare(b.date) || a.time.localeCompare(b.time) || byId(a, b),
      );
  }
}

/** Clamp a raw ?limit= into [1, 50]; anything unparseable gets the default. */
export function clampLimit(raw: string | null, fallback = 12): number {
  // Number(null) and Number("") are 0, not NaN — without this guard an absent
  // ?limit clamped to 1 instead of the default. Same coercion family as the
  // fmtEventTime("") midnight bug.
  if (raw == null || raw.trim() === "") return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n)) return fallback;
  return Math.min(50, Math.max(1, n));
}

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/** Accept only literal YYYY-MM-DD; anything else is treated as absent. */
export function parseDateParam(raw: string | null): string | undefined {
  return raw && DATE_RE.test(raw) ? raw : undefined;
}

export function parseSortParam(raw: string | null): PublicEventSort {
  return raw === "ending" || raw === "most_bids" ? raw : "soonest";
}
