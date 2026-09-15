/**
 * src/lib/listing/cardHandoff.ts — what a tapped card hands to the detail screen.
 *
 * Home and Search cards pushed `/listing/{id}` and nothing else, so the detail
 * screen opened on a full-screen spinner while the row loaded — even though the
 * card the user just tapped already showed the artwork, the event, the venue,
 * the date and the price. This carries exactly those DISPLAY values across, in
 * memory and keyed by listing id, so the detail screen can paint them on its
 * first frame and swap in the fresh row when it arrives.
 *
 * DISPLAY ONLY (contract A-17). Nothing here is a listing row, nothing here is
 * money as a number, and nothing here may reach `detailState`, a checkout
 * total, a reservation or a bid. The transactional controls stay gated on the
 * fetched row exactly as before; the handoff only replaces the spinner.
 *
 * In memory rather than route params: the push stays `/listing/${id}` (deep
 * links, typed routes and the existing source guards are untouched), and there
 * is no string parsing on the way back out. Bounded, so a long session of
 * browsing never accumulates.
 */

export interface CardHandoff {
  /** The RAW stored cover value. EventMedia resolves it, exactly as on the card. */
  coverPath: string | null;
  eventName: string;
  venue: string;
  /**
   * "YYYY-MM-DD" and "HH:MM:SS" as stored. The detail screen formats them with
   * its own formatter, so the line does not change shape when the row lands.
   */
  eventDate: string;
  eventTime: string;
  neighborhood: string | null;
  /**
   * The card's price eyebrow and its preformatted all-in amount — "Buy now",
   * "$66". Strings from the card, never numbers: nothing can be computed from them.
   */
  priceLabel: string;
  priceAllIn: string;
}

/** Enough for a back-and-forth through a feed; nothing accumulates past it. */
export const MAX_STAGED_HANDOFFS = 16;

const staged = new Map<string, CardHandoff>();

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/**
 * Normalizes whatever a card offers into a handoff, or nothing. Tolerant of
 * missing and blank fields: a handoff is only worth painting when it has a name
 * to show, and every other field degrades to empty rather than to a crash.
 */
export function parseCardHandoff(raw: unknown): CardHandoff | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const eventName = text(r.eventName);
  if (!eventName) return null;
  return {
    coverPath: text(r.coverPath) || null,
    eventName,
    venue: text(r.venue),
    eventDate: text(r.eventDate),
    eventTime: text(r.eventTime),
    neighborhood: text(r.neighborhood) || null,
    priceLabel: text(r.priceLabel),
    priceAllIn: text(r.priceAllIn),
  };
}

/** Called by a card right before it pushes the detail route. */
export function stageCardHandoff(listingId: string, raw: unknown): void {
  const parsed = parseCardHandoff(raw);
  if (!listingId || !parsed) return;
  // Re-insert so the newest entry is last; the oldest is evicted past the bound.
  staged.delete(listingId);
  staged.set(listingId, parsed);
  while (staged.size > MAX_STAGED_HANDOFFS) {
    const oldest = staged.keys().next().value;
    if (oldest === undefined) break;
    staged.delete(oldest);
  }
}

/**
 * Read by the detail screen when it mounts. Left in place rather than consumed:
 * a strict-mode double mount or a back-and-forth to the same listing must not
 * lose it, and the bound above keeps the map small.
 */
export function readCardHandoff(listingId: string): CardHandoff | null {
  return staged.get(listingId) ?? null;
}

export function clearCardHandoffs(): void {
  staged.clear();
}
