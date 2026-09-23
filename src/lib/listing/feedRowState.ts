/**
 * src/lib/listing/feedRowState.ts — the §5 row vocabulary for the V3 home feature and
 * feed/search rows (owner 2026-09-22; B's package §5 + the home/search mockups).
 *
 * Same altitude as cardState.ts and built ON it: cardState decides WHAT is true of the listing
 * (live/sold/ended, which price column, whether a clock is worth showing); this module only
 * formats the §5 strings. It never decides whether an auction closed — `clockLabel` is display
 * of the server's `ends_at`, and a listing's live/ended state stays with `cardStatus`, which the
 * screens already gate on before showing any clock at all.
 *
 * Date words are built from fixed tables, not `toLocaleDateString`: the row must read
 * "Sat 26 Sep · 21:00" on every device locale, and newer ICU spells en-GB September "Sept".
 */

const WEEKDAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

const MIN = 60_000;
const ENDING_SOON_MS = 15 * MIN;   // §5: amber only under 15 minutes. Mirrors cardState's window.

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/** "Sat 26 Sep · 21:00" from the stored event date and time. Empty when unparseable. */
export function rowWhenLabel(eventDate: string, eventTime: string): string {
  const d = new Date(`${eventDate}T${eventTime}`);
  if (Number.isNaN(d.getTime())) return '';
  return `${WEEKDAY[d.getDay()]} ${d.getDate()} ${MONTH[d.getMonth()]} · ${eventTime.slice(0, 5)}`;
}

export interface RowMetaInput {
  eventDate: string;
  eventTime: string;
  venue: string;
  quantity: number;
  ticketType: string;
  bidCount: number | null | undefined;
}

/**
 * The two §3 metadata lines: "Sat 26 Sep · 22:00 · The Foundry" and "2 × GA · 11 bids".
 * Zero bids is "no bids yet" — a count of zero is a claim shaped like activity.
 */
export function rowMeta(input: RowMetaInput): { meta1: string; meta2: string } {
  const bids = input.bidCount ?? 0;
  const bidText = bids === 0 ? 'no bids yet' : bids === 1 ? '1 bid' : `${bids} bids`;
  return {
    meta1: `${rowWhenLabel(input.eventDate, input.eventTime)} · ${input.venue}`,
    meta2: `${input.quantity} × ${input.ticketType} · ${bidText}`,
  };
}

/**
 * The feature drops the date only when the event is genuinely today on this device — the mockup's
 * "19:30 · Lantern Room" under a "Tonight" heading. Grouping by the device calendar is display
 * only; nothing here decides auction or payment state.
 */
export function featureMetaLine(
  input: { eventDate: string; eventTime: string; venue: string },
  nowMs: number,
): string {
  const now = new Date(nowMs);
  const today = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
  if (input.eventDate === today) return `${input.eventTime.slice(0, 5)} · ${input.venue}`;
  return `${rowWhenLabel(input.eventDate, input.eventTime)} · ${input.venue}`;
}

/**
 * The clock forms the mockups draw, §5's amber rule applied:
 *   < 15 minutes            →  "Ending in 11m"   (urgent — the ONLY amber on the row)
 *   later the same day      →  "2h 14m left" / "44m left"
 *   a later calendar day    →  "Ends Sat 20:30"
 *   past                    →  null — a dead clock is not shown, and cardState's
 *                              `showsCountdown` gates this before it is ever called.
 * The same-day boundary is an inference from the mockups (flagged for B); the words for the
 * first form and the amber threshold are §5 text.
 */
export function clockLabel(endsAt: string, nowMs: number): { text: string; urgent: boolean } | null {
  const ends = new Date(endsAt);
  const diff = ends.getTime() - nowMs;
  if (!Number.isFinite(diff) || diff <= 0) return null;

  if (diff < ENDING_SOON_MS) {
    return { text: `Ending in ${Math.max(1, Math.floor(diff / MIN))}m`, urgent: true };
  }

  const now = new Date(nowMs);
  const sameDay =
    ends.getFullYear() === now.getFullYear() &&
    ends.getMonth() === now.getMonth() &&
    ends.getDate() === now.getDate();

  if (sameDay) {
    const totalMin = Math.floor(diff / MIN);
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    return { text: h > 0 ? `${h}h ${m}m left` : `${m}m left`, urgent: false };
  }

  return {
    text: `Ends ${WEEKDAY[ends.getDay()]} ${pad(ends.getHours())}:${pad(ends.getMinutes())}`,
    urgent: false,
  };
}

/** "current bid, all-in" — the §5 caption under the price, from cardState's own label. */
export function priceCaption(priceLabel: string): string {
  return `${priceLabel.toLowerCase()}, all-in`;
}
