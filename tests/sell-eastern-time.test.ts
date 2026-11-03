/**
 * tests/sell-eastern-time.test.ts — the sell form's event date and time are Eastern (owner, 2026-11-02: "we
 * operate in EST"; A's ruling for the sell form: the form says its times are Eastern, its pickers default to
 * America/New_York, and the stored listing event_date / event_time are New York wall clock — existing rows are
 * never rewritten).
 *
 * The native pickers draw a Date's DEVICE-LOCAL wall clock and the form stores what they show, so the form's
 * Dates are wall-clock carriers: their local parts are New York's wall clock in every phone zone.
 * src/lib/sell/eventWallClock.ts builds and reads those carriers; CreateListingScreen and listingDraft use it.
 *
 * Every behavioural case runs with the process zone set to UTC, America/Los_Angeles and America/New_York in turn,
 * and the answers must not move: a seller's phone zone never changes what the form shows or stores. A witness
 * per anchor proves the device zone really disagrees there, so a device-zone fallback could not pass. Europe/Madrid
 * joins where a defect only shows east of UTC (toISOString's day) or where the phone skips an hour New York keeps.
 *
 * Anchors (A): 2026-11-02 04:59:59Z vs 05:00:00Z (ET midnight in EST), 2026-11-01 03:59:59Z vs 04:00:00Z (ET
 * midnight in EDT), the 25-hour 2026-11-01, the 23-hour 2026-03-08, and the evening 2026-11-03T02:14Z
 * (Mon 2 Nov 21:14 EST = Mon 18:14 in Los Angeles = Tue 02:14 UTC).
 *
 * Negative controls (run by hand, each must FAIL): put the screen's old device-zone helpers back in
 * eventWallClock.ts (SE1–SE4); drop the gap repair (SE2c); render no note (SE5); put toISOString / new Date()
 * back in the screen (SE6, and listing-draft-wiring W11).
 */
import { readFileSync } from 'node:fs';
import { afterEach, describe, expect, it } from 'vitest';

import {
  easternNextHourTime,
  easternTodayDate,
  eventDayString,
  eventTimeDisplay,
  eventTimeString,
  SELL_TIME_COPY,
} from '@/src/lib/sell/eventWallClock';

const ZONES = ['UTC', 'America/Los_Angeles', 'America/New_York'] as const;
const original = process.env.TZ;
afterEach(() => { if (original === undefined) delete process.env.TZ; else process.env.TZ = original; });

/** Runs `fn` under each process zone and returns the answers, which must all be equal. */
function underEveryZone<T>(fn: () => T): T {
  const answers = ZONES.map((z) => { process.env.TZ = z; return fn(); });
  for (const a of answers) expect(a).toEqual(answers[0]);
  return answers[0];
}
const ms = (iso: string) => Date.parse(iso);
/** A carrier's local wall clock: [year, month 1–12, day, hour, minute]. */
const local = (d: Date) => [d.getFullYear(), d.getMonth() + 1, d.getDate(), d.getHours(), d.getMinutes()];
/** The device-zone reading of an instant, as a fallback would produce it. */
const deviceDay = (iso: string, zone: string) => {
  process.env.TZ = zone;
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const EVENING = '2026-11-03T02:14:00Z';
const code = (rel: string) => readFileSync(rel, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');

describe('the defaults are New York’s, as local carriers the pickers draw', () => {
  it('SE1: today is New York’s calendar day at local midnight — ET midnight in EST and in EDT, the evening, both DST days', () => {
    expect(underEveryZone(() => local(easternTodayDate(ms('2026-11-02T04:59:59Z'))))).toEqual([2026, 11, 1, 0, 0]);
    expect(underEveryZone(() => local(easternTodayDate(ms('2026-11-02T05:00:00Z'))))).toEqual([2026, 11, 2, 0, 0]);
    expect(underEveryZone(() => local(easternTodayDate(ms('2026-11-01T03:59:59Z'))))).toEqual([2026, 10, 31, 0, 0]);
    expect(underEveryZone(() => local(easternTodayDate(ms('2026-11-01T04:00:00Z'))))).toEqual([2026, 11, 1, 0, 0]);
    expect(underEveryZone(() => local(easternTodayDate(ms(EVENING))))).toEqual([2026, 11, 2, 0, 0]);
    expect(underEveryZone(() => local(easternTodayDate(new Date(EVENING))))).toEqual([2026, 11, 2, 0, 0]);   // a Date works too
    expect(underEveryZone(() => local(easternTodayDate(ms('2026-11-01T06:30:00Z'))))).toEqual([2026, 11, 1, 0, 0]);  // 01:30 EST, hour 25
    expect(underEveryZone(() => local(easternTodayDate(ms('2026-03-09T03:59:59Z'))))).toEqual([2026, 3, 8, 0, 0]);   // 23:59 EDT, hour 23
    // Witnesses: at these instants the phone's own calendar is on another day.
    expect(deviceDay('2026-11-02T04:59:59Z', 'UTC')).toBe('2026-11-02');
    expect(deviceDay('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('2026-11-01');
    expect(deviceDay('2026-11-01T03:59:59Z', 'UTC')).toBe('2026-11-01');
    expect(deviceDay('2026-11-01T04:00:00Z', 'America/Los_Angeles')).toBe('2026-10-31');
    expect(deviceDay(EVENING, 'UTC')).toBe('2026-11-03');
    expect(deviceDay('2026-03-09T03:59:59Z', 'UTC')).toBe('2026-03-09');
  });

  it('SE2: the default time is New York’s next whole hour — 22:00 at 21:14 EST, whatever the phone says', () => {
    expect(underEveryZone(() => local(easternNextHourTime(ms(EVENING))))).toEqual([2026, 11, 2, 22, 0]);
    expect(underEveryZone(() => local(easternNextHourTime(ms('2026-11-02T04:59:59Z'))))).toEqual([2026, 11, 2, 0, 0]);  // 23:59:59 EST
    expect(underEveryZone(() => local(easternNextHourTime(ms('2026-11-02T05:00:00Z'))))).toEqual([2026, 11, 2, 1, 0]);  // on the hour: the next one, as before
    // Witness: the old default was the PHONE's next hour — 03:00 on a UTC phone, 19:00 on a Los Angeles one.
    const deviceNextHour = (zone: string) => { process.env.TZ = zone; const d = new Date(EVENING); d.setHours(d.getHours() + 1, 0, 0, 0); return d.getHours(); };
    expect(deviceNextHour('UTC')).toBe(3);
    expect(deviceNextHour('America/Los_Angeles')).toBe(19);
  });

  it('SE2b: across New York’s own clock changes the next hour is the next REAL hour — never the 02:00 New York skips on 8 March', () => {
    expect(underEveryZone(() => local(easternNextHourTime(ms('2026-11-01T05:30:00Z'))))).toEqual([2026, 11, 1, 1, 0]);  // 01:30 EDT → 01:00 EST
    expect(underEveryZone(() => local(easternNextHourTime(ms('2026-11-01T06:30:00Z'))))).toEqual([2026, 11, 1, 2, 0]);  // 01:30 EST → 02:00 EST
    expect(underEveryZone(() => local(easternNextHourTime(ms('2026-03-08T06:30:00Z'))))).toEqual([2026, 3, 8, 3, 0]);   // 01:30 EST → 03:00 EDT
    // Witness: a wall-clock "+1" would ask a US phone for 02:00 on 8 March, which it moves to 03:00 on its own.
    for (const zone of ['America/New_York', 'America/Los_Angeles']) {
      process.env.TZ = zone;
      expect(new Date(2026, 2, 8, 2, 0).getHours(), zone).toBe(3);
    }
  });

  it('SE2c: a New York hour the PHONE skips (Madrid, 2026-03-29 02:00) keeps its clock — only the carrier’s unread day moves', () => {
    const at = ms('2026-03-29T05:30:00Z');                     // 01:30 EDT; the next hour is 02:00 EDT
    for (const zone of [...ZONES, 'Europe/Madrid']) {
      process.env.TZ = zone;
      const t = easternNextHourTime(at);
      expect([t.getHours(), t.getMinutes()], zone).toEqual([2, 0]);
      expect(eventTimeString(t), zone).toBe('02:00:00');
    }
    process.env.TZ = 'Europe/Madrid';
    expect(new Date(2026, 2, 29, 2, 0).getHours()).toBe(3);   // witness: the plain carrier would read 03:00 there
  });
});

describe('what is stored, and what the time row says', () => {
  it('SE3: the stored day and time are the carrier’s own wall clock — never its UTC date', () => {
    // toISOString stored the day BEFORE for a midnight carrier east of UTC, and the day AFTER for an evening one west of it.
    const read = () => [
      eventDayString(new Date(2026, 10, 2)), eventDayString(new Date(2026, 10, 2, 21, 14)),
      eventTimeString(new Date(2026, 10, 2, 21, 14, 5)), eventTimeString(new Date(2026, 10, 2)),
    ];
    expect(underEveryZone(read)).toEqual(['2026-11-02', '2026-11-02', '21:14:05', '00:00:00']);
    process.env.TZ = 'Europe/Madrid';
    expect(read()).toEqual(['2026-11-02', '2026-11-02', '21:14:05', '00:00:00']);
    // Witnesses: what toISOString made of the same carriers.
    expect(new Date(2026, 10, 2).toISOString().split('T')[0]).toBe('2026-11-01');
    process.env.TZ = 'America/Los_Angeles';
    expect(new Date(2026, 10, 2, 21, 14).toISOString().split('T')[0]).toBe('2026-11-03');
  });

  it('SE4: the time row shows the wall clock as it is, labelled EST or EDT for the EVENT date — never the phone’s zone', () => {
    // The time carrier sits on 1 January (EST) throughout: the label follows the event date, not the carrier's day.
    const show = (y: number, m: number, d: number, hh: number, mm: number) => eventTimeDisplay(new Date(y, m - 1, d), new Date(2026, 0, 1, hh, mm));
    expect(underEveryZone(() => [show(2026, 11, 2, 22, 0), show(2026, 7, 4, 21, 0), show(2026, 12, 5, 0, 0), show(2026, 12, 5, 12, 5)]))
      .toEqual(['10:00 PM EST', '9:00 PM EDT', '12:00 AM EST', '12:05 PM EST']);
    // A clock New York reads twice (01:30 on 1 Nov) or never (02:30 on 8 Mar) gets no label rather than a guess.
    expect(underEveryZone(() => [show(2026, 11, 1, 1, 30), show(2026, 3, 8, 2, 30)])).toEqual(['1:30 AM', '2:30 AM']);
    // Witness: the phone's own zone name would have said PST / UTC for the same row.
    process.env.TZ = 'America/Los_Angeles';
    expect(new Date(2026, 10, 2, 22, 0).toLocaleTimeString('en-US', { timeZoneName: 'short' })).toMatch(/PST/);
    process.env.TZ = 'UTC';
    expect(new Date(2026, 10, 2, 22, 0).toLocaleTimeString('en-US', { timeZoneName: 'short' })).toMatch(/UTC/);
  });

  it('SE4b: the clock keeps the row’s 12-hour style — the same text the old formatter drew, every hour', () => {
    const old = (t: Date) => t.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', hour12: true }).replace(/ /g, ' ');
    underEveryZone(() => {
      for (let hh = 0; hh < 24; hh++) {
        for (const mm of [0, 5, 59]) {
          const t = new Date(2026, 11, 5, hh, mm);
          expect(eventTimeDisplay(new Date(2026, 11, 5), t), `${hh}:${mm}`).toBe(`${old(t)} EST`);
        }
      }
      return null;
    });
  });
});

describe('the screen says so, and uses these', () => {
  it('SE5: the form states its times are Eastern, in the Event section straight after the date and time rows', () => {
    expect(SELL_TIME_COPY.easternNote).toBe('Times are Eastern Time (EST/EDT).');
    expect(Object.values(SELL_TIME_COPY).join(' ')).not.toMatch(/\bET\b|-05:00|UTC|device|phone/);
    const src = code('src/screens/CreateListingScreen.tsx');
    const time = src.indexOf('<SelectRow label="Time"');
    const note = src.indexOf('{SELL_TIME_COPY.easternNote}');
    expect(time).toBeGreaterThan(0);
    expect(note).toBeGreaterThan(time);
    expect(src.slice(time, note)).not.toMatch(/<Section|<\/Section>/);
  });

  it('SE6: the screen builds and reads its event date and time only through eventWallClock — no phone today, no UTC day', () => {
    const src = code('src/screens/CreateListingScreen.tsx');
    expect(src).not.toMatch(/toISOString\(\)\.split/);
    expect(src).not.toMatch(/setHours\(/);
    expect(src).not.toMatch(/minimumDate=\{[^}]*new Date\(\)/);
    expect(src.match(/minimumDate=\{pickerMode === 'date' \? easternTodayDate\(\) : undefined\}/g)).toHaveLength(2);   // iOS and Android
    expect(src).toMatch(/event_date:\s+eventDayString\(eventDate\)/);
    expect(src).toMatch(/event_time:\s+eventTimeString\(eventTime\)/);
    expect(src).toMatch(/function defaultDate\(\) \{ return easternTodayDate\(\); \}/);
    expect(src).toMatch(/function defaultTime\(\) \{ return easternNextHourTime\(\); \}/);
    expect(src).toMatch(/value=\{eventTimeDisplay\(eventDate, eventTime\)\}/);
  });
});
