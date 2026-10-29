/**
 * src/lib/tickets/ticketWhen.ts — the event's date, doors and start as the ticket shows them.
 *
 * Event times are exact instants (A, from D's 162). The ticket shows them on the VENUE's clock:
 *   - `whenFromLocal` — preferred: D's 182 `get_primary_session` returns `starts_at_local` /
 *     `doors_at_local` ('YYYY-MM-DD HH24:MI', already in the venue zone) and the IANA `timezone`.
 *     The date and clock come from the string's own parts, so the device zone never moves them;
 *     the zone is only used to NAME it ("EST").
 *   - `whenLine` — fallback when only an instant is known (get_my_tickets): formatted in the given
 *     zone, or the device's when none is known, and always naming the zone it used.
 * Display only; nothing here decides whether doors are open.
 */

export interface WhenLine {
  /** "Mon, Nov 30" */
  date: string;
  /** "Doors 10:00 PM · 11:00 PM EST" (doors only when known) */
  times: string;
  /** "EST" / "GMT-5" — whatever Intl names the zone; '' when it cannot be resolved */
  zone: string;
}

const WEEKDAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'] as const;
const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const;

function fmt(d: Date, opts: Intl.DateTimeFormatOptions, timeZone?: string): string {
  try {
    return new Intl.DateTimeFormat('en-US', { ...opts, ...(timeZone ? { timeZone } : {}) }).format(d);
  } catch {
    return new Intl.DateTimeFormat('en-US', opts).format(d);
  }
}

function zoneName(d: Date, timeZone?: string): string {
  if (Number.isNaN(d.getTime())) return '';
  try {
    const parts = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short', ...(timeZone ? { timeZone } : {}) }).formatToParts(d);
    return parts.find((p) => p.type === 'timeZoneName')?.value ?? '';
  } catch {
    return '';
  }
}

export function whenLine(startsAt: string, doorsAt: string | null | undefined, timeZone?: string): WhenLine | null {
  const start = new Date(startsAt);
  if (Number.isNaN(start.getTime())) return null;
  const time = (d: Date) => fmt(d, { hour: 'numeric', minute: '2-digit' }, timeZone);
  const zone = zoneName(start, timeZone);
  const doors = doorsAt ? new Date(doorsAt) : null;
  const doorsText = doors && !Number.isNaN(doors.getTime()) ? `Doors ${time(doors)} · ` : '';
  return {
    date: fmt(start, { weekday: 'short', month: 'short', day: 'numeric' }, timeZone),
    times: `${doorsText}${time(start)}${zone ? ` ${zone}` : ''}`,
    zone,
  };
}

const LOCAL = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$/;

function parseLocal(s: string | null | undefined): { y: number; mo: number; d: number; h: number; mi: number } | null {
  if (!s) return null;
  const m = LOCAL.exec(s);
  if (!m) return null;
  const [y, mo, d, h, mi] = m.slice(1).map(Number);
  if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;
  return { y, mo, d, h, mi };
}

function clock12(h: number, mi: number): string {
  const suffix = h < 12 ? 'AM' : 'PM';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(mi).padStart(2, '0')} ${suffix}`;
}

/** From 182's venue-local strings. Null when the start string is missing or malformed. */
export function whenFromLocal(input: {
  startsAtLocal: string | null;
  doorsAtLocal: string | null;
  timezone: string | null;
  /** The absolute start instant — used only to name the zone (EST vs EDT). */
  startsAt: string | null;
}): WhenLine | null {
  const start = parseLocal(input.startsAtLocal);
  if (!start) return null;
  // The weekday of a calendar date is zone-free: compute it in UTC from the date parts alone.
  const weekday = WEEKDAY[new Date(Date.UTC(start.y, start.mo - 1, start.d)).getUTCDay()];
  const doors = parseLocal(input.doorsAtLocal);
  const zone = input.timezone && input.startsAt ? zoneName(new Date(input.startsAt), input.timezone) : '';
  const doorsText = doors ? `Doors ${clock12(doors.h, doors.mi)} · ` : '';
  return {
    date: `${weekday}, ${MONTH[start.mo - 1]} ${start.d}`,
    times: `${doorsText}${clock12(start.h, start.mi)}${zone ? ` ${zone}` : ''}`,
    zone,
  };
}

const AGE_LINE: Record<string, string> = {
  '21_plus': '21+ · ID checked at the door',
  '18_plus': '18+ · ID checked at the door',
  all_ages: 'All ages',
};

/** 182 `age_restriction` → the ticket's entry line. Null (not specified) or unknown values say nothing. */
export function entryRestrictionLine(policy: string | null | undefined): string | null {
  if (!policy) return null;
  return AGE_LINE[policy] ?? null;
}
