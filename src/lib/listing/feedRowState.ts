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
 *
 * Eastern time (owner, 2026-11-02: Snatch It operates in Eastern Time; A's rulings). Every day, weekday and
 * clock here is New York's, from src/lib/time/eastern.ts — never the device zone, so a buyer's phone zone
 * cannot change what a row says. A clock read off an instant says EST or EDT; a listing's stored date and time
 * are labelled, never converted (`listingWhenLabel`). The countdown arithmetic itself (`ends_at` minus now) is
 * zone-free and unchanged.
 */

import {
  dayKeyDiff,
  easternDayKey,
  easternParts,
  easternWallZoneLabel,
  easternZoneLabel,
} from '@/src/lib/time/eastern';

const WEEKDAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

const MIN = 60_000;
const ENDING_SOON_MS = 15 * MIN;   // §5: amber only under 15 minutes. Mirrors cardState's window.

function pad(n: number): string {
  return String(n).padStart(2, '0');
}

/**
 * "Sat 26 Sep · 21:00" — the shared row SHAPE for a calendar date and a wall-clock time. Empty when unparseable.
 *
 * It carries no zone. A listing's stored date and time go through `listingWhenLabel`, which adds the EST / EDT
 * for them; a caller formatting an instant should pass that instant's New York date and clock (`easternParts`) and
 * add the instant's own label (`easternZoneLabel`), because a wall clock that happens twice cannot say which it was.
 */
export function rowWhenLabel(eventDate: string, eventTime: string): string {
  const d = new Date(`${eventDate}T${eventTime}`);
  if (Number.isNaN(d.getTime())) return '';
  return `${WEEKDAY[d.getDay()]} ${d.getDate()} ${MONTH[d.getMonth()]} · ${eventTime.slice(0, 5)}`;
}

/** `time` with the stored wall clock's EST / EDT after it, or alone when the wall clock has no single label. */
function withWallZone(time: string, eventDate: string, eventTime: string): string {
  const zone = easternWallZoneLabel(eventDate, eventTime);
  return zone ? `${time} ${zone}` : time;
}

/**
 * "Sat 24 Oct · 19:30 EDT" — a listing's stored event date and time, with its zone. Empty when unparseable.
 *
 * LABELLED, NEVER CONVERTED (A, 2026-11-02). `event_date` / `event_time` are the seller's New York wall clock and
 * carry no zone: the text is shown exactly as stored and only the EST or EDT in force at that date and time is
 * appended (`easternWallZoneLabel`). Nothing here reads the stored text as an instant, shifts it to another zone or
 * reinterprets it. A time that happens twice (01:xx on the first Sunday of November), one that never happens
 * (02:xx on the second Sunday of March) or a malformed time gets no label rather than a guess, and is shown
 * unlabelled.
 */
export function listingWhenLabel(eventDate: string, eventTime: string): string {
  const text = rowWhenLabel(eventDate, eventTime);
  return text ? withWallZone(text, eventDate, eventTime) : '';
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
 * The two §3 metadata lines: "Sat 26 Sep · 22:00 EDT · The Foundry" and "2 × GA · 11 bids".
 * Zero bids is "no bids yet" — a count of zero is a claim shaped like activity.
 */
/** "no bids yet" / "1 bid" / "6 bids" — a count of zero is a claim shaped like activity. */
export function bidCountText(bidCount: number | null | undefined): string {
  const bids = bidCount ?? 0;
  return bids === 0 ? 'no bids yet' : bids === 1 ? '1 bid' : `${bids} bids`;
}

export function rowMeta(input: RowMetaInput): { meta1: string; meta2: string } {
  return {
    meta1: `${listingWhenLabel(input.eventDate, input.eventTime)} · ${input.venue}`,
    meta2: `${input.quantity} × ${input.ticketType} · ${bidCountText(input.bidCount)}`,
  };
}

/**
 * The feature drops the date only when the event is genuinely today in New York — the mockup's
 * "19:30 EST · Lantern Room" under a "Tonight" heading, the same "today" sections.ts buckets on. The stored
 * time keeps its label either way (labelled, never converted — `listingWhenLabel`). Display only; nothing
 * here decides auction or payment state.
 */
export function featureMetaLine(
  input: { eventDate: string; eventTime: string; venue: string },
  nowMs: number,
): string {
  if (input.eventDate === easternDayKey(nowMs)) {
    return `${withWallZone(input.eventTime.slice(0, 5), input.eventDate, input.eventTime)} · ${input.venue}`;
  }
  return `${listingWhenLabel(input.eventDate, input.eventTime)} · ${input.venue}`;
}

/**
 * The clock forms the mockups draw, §5's amber rule applied:
 *   < 15 minutes            →  "Ending in 11m"   (urgent — the ONLY amber on the row)
 *   later the same day      →  "2h 14m left" / "44m left"
 *   1–6 calendar days ahead →  "Ends Sat 20:30 EDT"
 *   7 or more days ahead    →  "Ends 27 Oct 23:47 EDT" (the weekday would repeat today's)
 *   past                    →  null — a dead clock is not shown, and cardState's
 *                              `showsCountdown` gates this before it is ever called.
 * "Day" is New York's calendar day and the weekday, date and HH:MM are New York's, so the absolute
 * forms carry the EST / EDT in force when the auction ends. The two duration forms are a difference
 * of instants: zone-free, and unlabelled.
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

  const endsMs = ends.getTime();
  const at = easternParts(endsMs);
  const nowDay = easternDayKey(nowMs);
  const endsDay = easternDayKey(endsMs);
  // New York calendar days, differenced as dates, so neither a DST change nor the phone's zone moves the count.
  const days = nowDay && endsDay ? dayKeyDiff(nowDay, endsDay) : null;
  if (!at || days === null) return null;

  if (days === 0) {
    const totalMin = Math.floor(diff / MIN);
    const h = Math.floor(totalMin / 60);
    const m = totalMin % 60;
    return { text: h > 0 ? `${h}h ${m}m left` : `${m}m left`, urgent: false };
  }

  const zone = easternZoneLabel(endsMs);
  const clock = `${pad(at.hour)}:${pad(at.minute)}${zone ? ` ${zone}` : ''}`;
  // A weekday names one day only inside the next six. Next week's same weekday read as today —
  // a 7-day listing published Tuesday night said "Ends Tue 23:47" — so from there on, the date.
  if (days >= 7) {
    return { text: `Ends ${at.day} ${MONTH[at.month - 1]} ${clock}`, urgent: false };
  }
  return { text: `Ends ${WEEKDAY[at.weekday]} ${clock}`, urgent: false };
}

/** "current bid, all-in" — the §5 caption under the price, from cardState's own label. */
export function priceCaption(priceLabel: string): string {
  return `${priceLabel.toLowerCase()}, all-in`;
}
