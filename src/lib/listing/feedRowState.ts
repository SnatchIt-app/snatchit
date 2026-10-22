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
/** "no bids yet" / "1 bid" / "6 bids" — a count of zero is a claim shaped like activity. */
export function bidCountText(bidCount: number | null | undefined): string {
  const bids = bidCount ?? 0;
  return bids === 0 ? 'no bids yet' : bids === 1 ? '1 bid' : `${bids} bids`;
}

export function rowMeta(input: RowMetaInput): { meta1: string; meta2: string } {
  return {
    meta1: `${rowWhenLabel(input.eventDate, input.eventTime)} · ${input.venue}`,
    meta2: `${input.quantity} × ${input.ticketType} · ${bidCountText(input.bidCount)}`,
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
 *   1–6 calendar days ahead →  "Ends Sat 20:30"
 *   7 or more days ahead    →  "Ends 27 Oct 23:47" (the weekday would repeat today's)
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

  const hhmm = `${pad(ends.getHours())}:${pad(ends.getMinutes())}`;
  // A weekday names one day only inside the next six. Next week's same weekday read as today —
  // a 7-day listing published Tuesday night said "Ends Tue 23:47" — so from there on, the date.
  if (calendarDaysBetween(now, ends) >= 7) {
    return { text: `Ends ${ends.getDate()} ${MONTH[ends.getMonth()]} ${hhmm}`, urgent: false };
  }
  return { text: `Ends ${WEEKDAY[ends.getDay()]} ${hhmm}`, urgent: false };
}

/** Local calendar days from `a` to `b`, by midnight, so a DST change doesn't move the count. */
function calendarDaysBetween(a: Date, b: Date): number {
  const dayA = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const dayB = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((dayB - dayA) / 86_400_000);
}

/** "current bid, all-in" — the §5 caption under the price, from cardState's own label. */
export function priceCaption(priceLabel: string): string {
  return `${priceLabel.toLowerCase()}, all-in`;
}
