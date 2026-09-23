/**
 * src/lib/checkout/listingSummary.ts — the checkout summary read (finding F1).
 *
 * WHAT WAS WRONG
 * Build 16 selected `cover_image_url` from `listings`. That column does not
 * exist: it appears in no migration in this repo, and the sandbox has only
 * `cover_image_path`. PostgREST rejects the WHOLE select with 400, so the
 * screen lost not just the artwork but the event name, venue, date, time and
 * `reserved_until` — the countdown's only source. The handset logs show that
 * 400 on every checkout mount of the QA matrix.
 *
 * Money was never affected: this read touches no payment state and its failure
 * never blocked Buy Now. What it cost was the screen's ability to say what was
 * being bought and how long the hold had left — on the one screen where the
 * money leaves.
 *
 * WHY A COLUMN LIST AND NOT `*`
 * A wildcard would also have survived the drift, but it fetches whatever the
 * table happens to carry. The named list is the contract: if a column is
 * renamed again, the test suite fails here rather than the screen going quiet.
 *
 * `cover_image_url` stays in the ROW TYPE but out of the SELECT. Some rows in
 * other environments may still carry a legacy absolute URL, and the renderer
 * already accepts either form (`contract: 'legacy'` → `mediaUrlForStoredValue`),
 * so if a caller ever supplies it the cover still resolves. Nothing here
 * requests it.
 */

/** Exactly the columns the summary needs; every one verified to exist. */
export const LISTING_SUMMARY_COLUMNS =
  // V3 (owner 2026-09-23): + ticket_type for the identity line's "2 × GA". Same authorized
  // row, display only. Flagged to A: this file hosts checkout's summary read.
  'cover_image_path, event_name, venue, event_date, event_time, reserved_until, quantity, ticket_type';

export type ListingSummaryRow = {
  cover_image_path?: string | null;
  /** Legacy absolute URL. NOT selected — tolerated if a caller has one. */
  cover_image_url?: string | null;
  event_name?: string | null;
  venue?: string | null;
  event_date?: string | null;
  event_time?: string | null;
  reserved_until?: string | null;
  /** Tickets in the listing. The price covers all of them (whole-listing pricing). */
  quantity?: number | null;
  ticket_type?: string | null;
};

export type ListingSummary = {
  /** Storage path or legacy URL; null means "show the placeholder". */
  cover: string | null;
  eventName: string;
  venue: string;
  date: string;
  time: string;
  /** Null when unknown; the screen then shows no ticket count. */
  quantity: number | null;
  /** Null when unknown; the identity line then counts plain "tickets". */
  ticketType: string | null;
};

/** '' and '   ' are absences, not values — a blank must not reach the renderer. */
function present(v: string | null | undefined): string | null {
  if (typeof v !== 'string') return null;
  const t = v.trim();
  return t.length > 0 ? t : null;
}

/**
 * Build the summary from the row, falling back to what navigation already
 * knew. A blank column falls back too: the old code passed '' straight
 * through, which rendered an empty heading and a broken image source.
 */
export function mapListingSummary(
  row: ListingSummaryRow | null | undefined,
  fallback: { eventName: string; venue: string },
): ListingSummary {
  const r = row ?? {};
  return {
    cover: present(r.cover_image_path) ?? present(r.cover_image_url),
    eventName: present(r.event_name) ?? fallback.eventName,
    venue: present(r.venue) ?? fallback.venue,
    date: present(r.event_date) ?? '',
    time: present(r.event_time) ?? '',
    quantity: typeof r.quantity === 'number' && Number.isFinite(r.quantity) && r.quantity > 0 ? Math.floor(r.quantity) : null,
    ticketType: present(r.ticket_type),
  };
}

/**
 * The hold deadline in epoch ms, or null when there is none to show.
 * An unparseable timestamp returns null rather than NaN, which would have
 * rendered as a nonsense countdown.
 */
export function reservedUntilMs(row: ListingSummaryRow | null | undefined): number | null {
  const raw = present(row?.reserved_until);
  if (raw == null) return null;
  const ms = new Date(raw).getTime();
  return Number.isFinite(ms) ? ms : null;
}

/**
 * "2 tickets" / "1 ticket". Whole-listing pricing: the total covers every
 * ticket in the listing, so the count sits next to the total, never as a
 * per-ticket price.
 */
export function ticketCountLabel(quantity: number | null): string | null {
  if (quantity == null) return null;
  return `${quantity} ${quantity === 1 ? 'ticket' : 'tickets'}`;
}

/**
 * De-dup rule (owner 2026-09-23): the sticky Total renders only when the pay control's own
 * label does not already state an amount — on the action or beside it, never both.
 */
export function labelCarriesAmount(label: string): boolean {
  return /\$\d/.test(label);
}
