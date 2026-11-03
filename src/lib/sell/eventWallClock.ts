/**
 * src/lib/sell/eventWallClock.ts — the sell form's event date and time are New York wall clock (owner, 2026-11-02:
 * "we operate in EST"; A's ruling for the sell form: the form states that its times are Eastern, its pickers
 * default to America/New_York, and the stored listing event_date / event_time are New York wall clock — existing
 * rows are never rewritten). Tested by tests/sell-eastern-time.test.ts under three phone zones.
 *
 * WALL-CLOCK CARRIERS — the native date and time pickers draw a Date's DEVICE-LOCAL wall clock, and the form
 * stores what they show. So the form's Dates carry a wall clock, not an instant: their LOCAL year / month / day
 * (and hour / minute) ARE New York's wall clock, on any phone. The defaults and the earliest pickable day are
 * built here from New York's parts (eastern.ts) into such carriers, and the stored strings are read back from the
 * same local parts. Reading local parts is therefore not a device-zone reading of an instant: there is no instant
 * — the carrier was built from New York's parts, or set by the picker from what the seller saw.
 *
 * A STORED WALL CLOCK IS LABELLED, NEVER CONVERTED — event_date + event_time carry no zone. The time row shows them
 * as they are, followed by easternWallZoneLabel's EST or EDT for that date and time; they are never shifted into
 * another zone or reinterpreted (A, 2026-11-02).
 */

import { easternParts, easternWallZoneLabel } from '@/src/lib/time/eastern';

/** What the form says about its times (pinned by SE5). Never a bare "ET", never a fixed offset. */
export const SELL_TIME_COPY = {
  easternNote: 'Times are Eastern Time (EST/EDT).',
} as const;

const HOUR_MS = 3_600_000;
const pad2 = (n: number) => String(n).padStart(2, '0');
const toMs = (now: Date | number) => (typeof now === 'number' ? now : now.getTime());

/**
 * New York's calendar day at `now`, as a local-midnight carrier: the date row's default and the date picker's
 * earliest day. (A phone whose own zone skips midnight that day lands at 01:00 — the same local day, which is
 * all that is read.) An invalid `now` gives an invalid Date.
 */
export function easternTodayDate(now: Date | number = Date.now()): Date {
  const p = easternParts(toMs(now));
  return p ? new Date(p.year, p.month - 1, p.day) : new Date(Number.NaN);
}

/**
 * New York's next whole hour after `now`, as a local carrier whose hours and minutes read it: the time row's
 * default (the form used to take the phone's next hour). It is the next REAL hour: New York's offsets are whole
 * hours, so its hours start on UTC's, and the next one is found as an instant first — 01:30 EST on 8 March is
 * followed by 03:00 EDT, never by the 02:00 New York skips, and 01:30 EDT on 1 November by 01:00 EST.
 *
 * Only the carrier's hours and minutes are read (the stored event_time, the draft's clock, the time row); its
 * day is not. So when the PHONE's own zone skips that hour on that day (its spring-forward — Madrid's 02:00 on
 * 2026-03-29), the carrier is built on the day before, where the hour exists, instead of letting Date move the
 * clock forward an hour.
 */
export function easternNextHourTime(now: Date | number = Date.now()): Date {
  const ms = toMs(now);
  const p = Number.isFinite(ms) ? easternParts(Math.floor(ms / HOUR_MS) * HOUR_MS + HOUR_MS) : null;
  if (!p) return new Date(Number.NaN);
  const carrier = new Date(p.year, p.month - 1, p.day, p.hour, p.minute);
  if (carrier.getHours() === p.hour && carrier.getMinutes() === p.minute) return carrier;
  return new Date(p.year, p.month - 1, p.day - 1, p.hour, p.minute);
}

/** The carrier's own calendar day, 'YYYY-MM-DD' — the stored event_date (never toISOString's UTC day). */
export function eventDayString(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

/** The carrier's own clock, 'HH:MM:SS' — the stored event_time. */
export function eventTimeString(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

/**
 * The time row: the stored wall clock as it is, in the row's 12-hour style ("10:00 PM"), then EST or EDT for the
 * EVENT date and that clock — "10:00 PM EST". Labelled, never converted: the clock text is the stored event_time,
 * untouched, and easternWallZoneLabel only names New York's zone for it. A clock New York reads twice (01:xx on the
 * first Sunday of November) or never (02:xx on the second Sunday of March) gets no label rather than a guess; the
 * form's standing note still says its times are Eastern.
 */
export function eventTimeDisplay(date: Date, time: Date): string {
  const h = time.getHours();
  const clock = `${h % 12 || 12}:${pad2(time.getMinutes())} ${h < 12 ? 'AM' : 'PM'}`;
  const zone = easternWallZoneLabel(eventDayString(date), eventTimeString(time));
  return zone ? `${clock} ${zone}` : clock;
}
