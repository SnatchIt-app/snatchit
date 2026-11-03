/**
 * src/lib/time/eastern.ts — Eastern time for everything a person reads (owner, 2026-11-02: "we operate in EST,
 * everything about Snatch It should be in EST"; A/TIMEZONE-DECISION-20261102.md).
 *
 * The rule: product display and defaults use America/New_York, labelled EST or EDT (daylight saving applied
 * automatically — never a fixed −05:00 and never the device zone, so a buyer's phone zone cannot change what the
 * app shows). Storage, comparisons, expiry and durations stay UTC instants. Venue event times keep their venue's
 * own zone (ticketWhen.ts whenFromLocal); a stored wall clock is labelled, never converted (easternWallZoneLabel).
 *
 * Parts come from Intl with an explicit timeZone. If the runtime cannot provide them, the US rule since 2007
 * (EDT from the second Sunday of March 02:00 to the first Sunday of November 02:00) — tests pin that both agree
 * every hour of 2026. The label is derived from the offset, not from Intl's zone name, so it reads EST / EDT on
 * every ICU build.
 */

export const EASTERN_ZONE = 'America/New_York';

/** month 1–12, hour 0–23, weekday 0 = Sunday. */
export interface EasternParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  weekday: number;
}

const WEEKDAY_INDEX: Record<string, number> = { Sun: 0, Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6 };
const pad2 = (n: number) => String(n).padStart(2, '0');

/**
 * Two instants that pin the formatter to Eastern, one in each offset.
 * 2026-01-15T12:00Z is 07:00 EST; 2026-07-15T12:00Z is 08:00 EDT.
 *
 * Constructing `Intl.DateTimeFormat` with a `timeZone` does NOT prove the engine honours it: a build
 * without full ICU can accept the option and then format in the DEVICE zone, and the old code cached
 * that formatter as valid — so every reader saw device-zone times and `easternZoneLabel` returned ''
 * because the offset was neither -300 nor -240. Needing BOTH instants is what makes the probe sharp:
 * a zone-blind formatter fails January, and one pinned to a fixed -05:00 passes January and fails July.
 */
const EASTERN_PROBE: readonly (readonly [ms: number, hour: number])[] = [
  [Date.UTC(2026, 0, 15, 12), 7],
  [Date.UTC(2026, 6, 15, 12), 8],
];

/** Does this formatter actually answer in Eastern? Called once, on the formatter it is given. */
function formatsEastern(f: Intl.DateTimeFormat): boolean {
  try {
    for (const [instant, hour] of EASTERN_PROBE) {
      const parts = f.formatToParts(new Date(instant));
      const h = Number(parts.find((p) => p.type === 'hour')?.value);
      const minute = Number(parts.find((p) => p.type === 'minute')?.value);
      if (h % 24 !== hour || minute !== 0) return false;
    }
    return true;
  } catch {
    return false;
  }
}

let formatter: Intl.DateTimeFormat | null | undefined;
function intlFormatter(): Intl.DateTimeFormat | null {
  if (formatter !== undefined) return formatter;
  try {
    const candidate = new Intl.DateTimeFormat('en-US', {
      timeZone: EASTERN_ZONE, hourCycle: 'h23', weekday: 'short', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', minute: 'numeric',
    });
    // One probe per process: a formatter that cannot answer in Eastern is discarded, and every call
    // then routes to `easternPartsByRule`, which ET6 pins against Intl for every hour of 2026.
    formatter = formatsEastern(candidate) ? candidate : null;
  } catch {
    formatter = null;
  }
  return formatter;
}

function partsByIntl(ms: number): EasternParts | null {
  const f = intlFormatter();
  if (!f) return null;
  try {
    const parts = f.formatToParts(new Date(ms));
    const num = (type: string) => Number(parts.find((p) => p.type === type)?.value);
    const weekday = WEEKDAY_INDEX[parts.find((p) => p.type === 'weekday')?.value ?? ''];
    const out = { year: num('year'), month: num('month'), day: num('day'), hour: num('hour') % 24, minute: num('minute'), weekday };
    return Object.values(out).every((v) => Number.isInteger(v)) ? out : null;
  } catch {
    return null;
  }
}

/** Day of the month of the nth Sunday (n ≥ 1) of a month, in the proleptic UTC calendar. */
function nthSunday(year: number, monthIndex: number, n: number): number {
  const firstWeekday = new Date(Date.UTC(year, monthIndex, 1)).getUTCDay();
  return 1 + ((7 - firstWeekday) % 7) + 7 * (n - 1);
}

/** The US rule alone (exported for the agreement test): EDT from 07:00Z on the 2nd Sunday of March to 06:00Z on the 1st Sunday of November. */
export function easternPartsByRule(ms: number): EasternParts | null {
  if (!Number.isFinite(ms)) return null;
  const year = new Date(ms).getUTCFullYear();
  const start = Date.UTC(year, 2, nthSunday(year, 2, 2), 7);
  const end = Date.UTC(year, 10, nthSunday(year, 10, 1), 6);
  const offset = ms >= start && ms < end ? -240 : -300;
  const d = new Date(ms + offset * 60_000);
  return { year: d.getUTCFullYear(), month: d.getUTCMonth() + 1, day: d.getUTCDate(), hour: d.getUTCHours(), minute: d.getUTCMinutes(), weekday: d.getUTCDay() };
}

/** New York's wall clock for an instant (UTC ms), or null for an invalid instant. */
export function easternParts(ms: number): EasternParts | null {
  if (!Number.isFinite(ms)) return null;
  return partsByIntl(ms) ?? easternPartsByRule(ms);
}

/** New York's offset from UTC at an instant, in minutes: −240 (EDT) or −300 (EST). */
export function easternOffsetMinutes(ms: number): number | null {
  const p = easternParts(ms);
  if (!p) return null;
  const wall = Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute);
  return Math.round((wall - Math.floor(ms / 60_000) * 60_000) / 60_000);
}

/** "EST" or "EDT" for an instant; '' when it cannot be told. */
export function easternZoneLabel(ms: number): 'EST' | 'EDT' | '' {
  const offset = easternOffsetMinutes(ms);
  return offset === -300 ? 'EST' : offset === -240 ? 'EDT' : '';
}

/** New York's calendar day, 'YYYY-MM-DD' — the day boundary for "today", "tonight", draft expiry and defaults. */
export function easternDayKey(ms: number): string | null {
  const p = easternParts(ms);
  return p ? `${p.year}-${pad2(p.month)}-${pad2(p.day)}` : null;
}

const DAY_KEY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Whole calendar days from one 'YYYY-MM-DD' to another (DST-proof: the keys are differenced as UTC dates). */
export function dayKeyDiff(from: string, to: string): number | null {
  const a = DAY_KEY.exec(from);
  const b = DAY_KEY.exec(to);
  if (!a || !b) return null;
  return Math.round((Date.UTC(+b[1], +b[2] - 1, +b[3]) - Date.UTC(+a[1], +a[2] - 1, +a[3])) / 86_400_000);
}

/** "9:14 PM" in New York; '' for an invalid instant. The caller adds the label. */
export function easternClock12(ms: number): string {
  const p = easternParts(ms);
  if (!p) return '';
  return `${p.hour % 12 || 12}:${pad2(p.minute)} ${p.hour < 12 ? 'AM' : 'PM'}`;
}

const WALL_TIME = /^(\d{2}):(\d{2})(?::\d{2})?$/;

/**
 * The label for a STORED New York wall clock (a listing's event_date + event_time, which carry no zone): EST or EDT
 * for that date and time. The stored text is shown as it is — this never converts or reinterprets it (A, 2026-11-02:
 * existing rows are display-labelled only). A time that happens twice (01:xx on the first Sunday of November), one
 * that never happens (02:xx on the second Sunday of March) or a malformed value gets no label rather than a guess.
 */
export function easternWallZoneLabel(date: string | null | undefined, time: string | null | undefined): 'EST' | 'EDT' | '' {
  const d = DAY_KEY.exec(date ?? '');
  const t = WALL_TIME.exec(time ?? '');
  if (!d || !t) return '';
  const [y, m, day, h, mi] = [+d[1], +d[2], +d[3], +t[1], +t[2]];
  const wall = Date.UTC(y, m - 1, day, h, mi);
  const fits = [-240, -300].filter((offset) => {
    const p = easternParts(wall - offset * 60_000);
    return !!p && p.year === y && p.month === m && p.day === day && p.hour === h && p.minute === mi;
  });
  if (fits.length !== 1) return '';
  return fits[0] === -300 ? 'EST' : 'EDT';
}
