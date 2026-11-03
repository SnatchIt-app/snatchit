/**
 * src/lib/time/eastern.ts — the one Eastern-time source for product display (owner, 2026-11-02: "we operate in
 * EST, everything about Snatch It should be in EST"; A/TIMEZONE-DECISION-20261102.md). Label = EST / EDT.
 *
 * Every case runs with the process zone set to UTC, America/Los_Angeles and America/New_York in turn, and the
 * answers must not move: a buyer's phone zone never changes what the app shows. A witness per anchor proves the
 * device zone really does disagree there, so a helper that fell back to it could not pass.
 *
 * Anchors (A, from D's SQL audit — ones that discriminate):
 *   2026-11-02 04:59:59Z vs 05:00:00Z   ET midnight in EST
 *   2026-11-01 03:59:59Z vs 04:00:00Z   ET midnight in EDT
 *   2026-11-01 is 25 hours in ET (01:00–01:59 happens twice: EDT, then EST)
 *   2026-03-08 is 23 hours in ET (02:00–02:59 never happens)
 *
 * Negative controls (run by hand, each must FAIL): read the parts with the Date's local getters (ET1–ET4);
 * label from a fixed -05:00 (ET3); drop the repeated-hour distinction (ET3); let the rule fallback ignore DST (ET6).
 */
import { afterEach, describe, expect, it, vi } from 'vitest';

import {
  dayKeyDiff,
  easternClock12,
  easternDayKey,
  easternOffsetMinutes,
  easternParts,
  easternPartsByRule,
  easternWallZoneLabel,
  easternZoneLabel,
} from '@/src/lib/time/eastern';

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
/** The device-zone reading of an instant, as a fallback would produce it. */
const deviceDay = (iso: string, zone: string) => {
  process.env.TZ = zone;
  const d = new Date(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};

describe('easternDayKey — the calendar day in New York, whatever the phone says', () => {
  it('ET1: ET midnight in EST is 05:00Z (2026-11-02), and the witness shows UTC and LA phones disagree', () => {
    expect(underEveryZone(() => easternDayKey(ms('2026-11-02T04:59:59Z')))).toBe('2026-11-01');
    expect(underEveryZone(() => easternDayKey(ms('2026-11-02T05:00:00Z')))).toBe('2026-11-02');
    expect(deviceDay('2026-11-02T04:59:59Z', 'UTC')).toBe('2026-11-02');                 // a UTC phone is already on the 2nd
    expect(deviceDay('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('2026-11-01');  // an LA phone is still on the 1st
  });

  it('ET2: ET midnight in EDT is 04:00Z (2026-11-01)', () => {
    expect(underEveryZone(() => easternDayKey(ms('2026-11-01T03:59:59Z')))).toBe('2026-10-31');
    expect(underEveryZone(() => easternDayKey(ms('2026-11-01T04:00:00Z')))).toBe('2026-11-01');
    expect(deviceDay('2026-11-01T03:59:59Z', 'UTC')).toBe('2026-11-01');
    expect(deviceDay('2026-11-01T04:00:00Z', 'America/Los_Angeles')).toBe('2026-10-31');
  });

  it('ET4: 2026-11-01 is 25 hours long in New York, 2026-03-08 is 23', () => {
    const hours = (from: string, to: string) => (ms(to) - ms(from)) / 3_600_000;
    expect(underEveryZone(() => [easternDayKey(ms('2026-11-01T04:00:00Z')), easternDayKey(ms('2026-11-02T04:59:59Z'))])).toEqual(['2026-11-01', '2026-11-01']);
    expect(hours('2026-11-01T04:00:00Z', '2026-11-02T05:00:00Z')).toBe(25);
    expect(underEveryZone(() => [easternDayKey(ms('2026-03-08T05:00:00Z')), easternDayKey(ms('2026-03-09T03:59:59Z')), easternDayKey(ms('2026-03-09T04:00:00Z'))]))
      .toEqual(['2026-03-08', '2026-03-08', '2026-03-09']);
    expect(hours('2026-03-08T05:00:00Z', '2026-03-09T04:00:00Z')).toBe(23);
  });

  it('ET5: day differences are whole calendar days across both DST changes', () => {
    expect(dayKeyDiff('2026-10-31', '2026-11-02')).toBe(2);
    expect(dayKeyDiff('2026-03-07', '2026-03-09')).toBe(2);
    expect(dayKeyDiff('2026-11-02', '2026-11-02')).toBe(0);
    expect(dayKeyDiff('2026-11-03', '2026-11-02')).toBe(-1);
    expect(dayKeyDiff('2026-11-3', '2026-11-02')).toBeNull();
    expect(dayKeyDiff('', '2026-11-02')).toBeNull();
  });
});

describe('easternParts / easternClock12 / the EST–EDT label', () => {
  it('ET3: the repeated 01:30 on 2026-11-01 reads EDT then EST; the rest of the day is EST, the day before EDT', () => {
    expect(underEveryZone(() => [easternClock12(ms('2026-11-01T05:30:00Z')), easternZoneLabel(ms('2026-11-01T05:30:00Z'))])).toEqual(['1:30 AM', 'EDT']);
    expect(underEveryZone(() => [easternClock12(ms('2026-11-01T06:30:00Z')), easternZoneLabel(ms('2026-11-01T06:30:00Z'))])).toEqual(['1:30 AM', 'EST']);
    expect(underEveryZone(() => easternZoneLabel(ms('2026-11-02T02:12:00Z')))).toBe('EST');
    expect(underEveryZone(() => easternZoneLabel(ms('2026-10-31T23:00:00Z')))).toBe('EDT');
    expect(underEveryZone(() => [easternOffsetMinutes(ms('2026-11-01T05:30:00Z')), easternOffsetMinutes(ms('2026-11-01T06:30:00Z'))])).toEqual([-240, -300]);
  });

  it('ET3b: spring forward 2026-03-08 — 01:59 EST is followed by 03:00 EDT', () => {
    expect(underEveryZone(() => [easternClock12(ms('2026-03-08T06:59:00Z')), easternZoneLabel(ms('2026-03-08T06:59:00Z'))])).toEqual(['1:59 AM', 'EST']);
    expect(underEveryZone(() => [easternClock12(ms('2026-03-08T07:00:00Z')), easternZoneLabel(ms('2026-03-08T07:00:00Z'))])).toEqual(['3:00 AM', 'EDT']);
  });

  it('ET1b: parts carry the New York weekday, date and 24h clock; midnight is hour 0, never 24', () => {
    expect(underEveryZone(() => easternParts(ms('2026-11-03T02:14:00Z')))).toEqual({ year: 2026, month: 11, day: 2, hour: 21, minute: 14, weekday: 1 });
    expect(underEveryZone(() => easternParts(ms('2026-11-02T05:00:00Z')))).toEqual({ year: 2026, month: 11, day: 2, hour: 0, minute: 0, weekday: 1 });
    expect(underEveryZone(() => easternClock12(ms('2026-11-02T05:00:00Z')))).toBe('12:00 AM');
    expect(underEveryZone(() => easternClock12(ms('2026-11-02T17:05:00Z')))).toBe('12:05 PM');
    expect(easternParts(Number.NaN)).toBeNull();
    expect(easternDayKey(Number.NaN)).toBeNull();
    expect(easternClock12(Number.NaN)).toBe('');
    expect(easternZoneLabel(Number.NaN)).toBe('');
  });

  it('ET6: the rule fallback (US DST: 2nd Sunday of March 02:00, 1st Sunday of November 02:00) agrees with Intl every hour of 2026', () => {
    process.env.TZ = 'UTC';
    for (let t = ms('2026-01-01T00:00:00Z'); t < ms('2027-01-01T00:00:00Z'); t += 3_600_000) {
      expect(easternPartsByRule(t), new Date(t).toISOString()).toEqual(easternParts(t));
    }
  });
});

describe('easternWallZoneLabel — a stored New York wall clock is labelled, never converted (A, 2026-11-02)', () => {
  it('EW1: winter and summer dates get EST and EDT; the stored text itself is not touched', () => {
    expect(underEveryZone(() => easternWallZoneLabel('2026-12-05', '19:30'))).toBe('EST');
    expect(underEveryZone(() => easternWallZoneLabel('2026-07-04', '21:00'))).toBe('EDT');
    expect(underEveryZone(() => easternWallZoneLabel('2026-11-01', '00:30'))).toBe('EDT');   // before the fall-back hour
    expect(underEveryZone(() => easternWallZoneLabel('2026-11-01', '03:00'))).toBe('EST');
    expect(underEveryZone(() => easternWallZoneLabel('2026-03-08', '03:30'))).toBe('EDT');
  });

  it('EW2: an ambiguous or impossible wall clock, or a malformed value, gets no label rather than a guess', () => {
    expect(easternWallZoneLabel('2026-11-01', '01:30')).toBe('');   // happens twice
    expect(easternWallZoneLabel('2026-03-08', '02:30')).toBe('');   // never happens
    expect(easternWallZoneLabel('2026-12-05', '')).toBe('');
    expect(easternWallZoneLabel('2026-12-5', '19:30')).toBe('');
    expect(easternWallZoneLabel(null, '19:30')).toBe('');
  });
});

/**
 * ET7 — the Intl construction probe (E's finding on c36).
 *
 * `new Intl.DateTimeFormat('en-US', { timeZone })` succeeding does NOT prove the engine honours the
 * zone: a build without full ICU can accept the option and format in the DEVICE zone. The old code
 * cached that formatter as valid, so `partsByIntl` never returned null, the rule fallback never fired,
 * and every reader saw device-zone times with the EST/EDT suffix silently absent.
 *
 * These cases stub `Intl` and re-import the module per case, because the formatter is cached per
 * process — `vi.resetModules()` is what rebuilds it. Only ET7d uses the real Intl.
 */
const partsFrom = (d: Date, offsetMinutes: number) => {
  const t = new Date(d.getTime() + offsetMinutes * 60_000);
  const wk = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][t.getUTCDay()];
  return [
    { type: 'weekday', value: wk },
    { type: 'year', value: String(t.getUTCFullYear()) },
    { type: 'month', value: String(t.getUTCMonth() + 1) },
    { type: 'day', value: String(t.getUTCDate()) },
    { type: 'hour', value: String(t.getUTCHours()) },
    { type: 'minute', value: String(t.getUTCMinutes()) },
  ];
};

/** A formatter that ACCEPTS timeZone and ignores it, answering in UTC — the ICU-less engine. */
const zoneBlindIntl = { DateTimeFormat: class { formatToParts(d: Date) { return partsFrom(d, 0); } } };
/** A formatter pinned to a fixed -05:00: right in January, wrong in July. */
const fixedOffsetIntl = { DateTimeFormat: class { formatToParts(d: Date) { return partsFrom(d, -300); } } };
/** A constructor that throws — the path the original `catch` already handled. */
const throwingCtorIntl = { DateTimeFormat: class { constructor() { throw new Error('no ICU'); } } };
/** A formatter that constructs and then throws when used — the path the probe's own catch handles. */
const throwingFormatIntl = { DateTimeFormat: class { formatToParts(): never { throw new Error('no ICU data'); } } };

const freshEastern = async (fakeIntl?: unknown) => {
  vi.resetModules();
  if (fakeIntl) vi.stubGlobal('Intl', fakeIntl);
  return import('@/src/lib/time/eastern');
};

describe('ET7 — a formatter that does not actually answer in Eastern is discarded', () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.resetModules(); });

  const JAN = Date.UTC(2026, 0, 15, 12);   // 07:00 EST
  const JUL = Date.UTC(2026, 6, 15, 12);   // 08:00 EDT

  it('ET7a: a zone-blind Intl (accepts timeZone, formats in UTC) falls back to the rule, and the label is not blank', async () => {
    const m = await freshEastern(zoneBlindIntl);
    // Without the probe this returned the UTC parts — hour 12 — and the label was ''.
    expect(m.easternParts(JAN)).toEqual(m.easternPartsByRule(JAN));
    expect(m.easternParts(JUL)).toEqual(m.easternPartsByRule(JUL));
    expect(m.easternParts(JAN)?.hour).toBe(7);
    expect(m.easternParts(JUL)?.hour).toBe(8);
    expect(m.easternZoneLabel(JAN)).toBe('EST');
    expect(m.easternZoneLabel(JUL)).toBe('EDT');
  });

  it('ET7b: a fixed -05:00 Intl passes January and fails July, so it is discarded and July still reads EDT', async () => {
    const m = await freshEastern(fixedOffsetIntl);
    // This is why the probe needs BOTH instants: January alone cannot tell this formatter from a good one.
    expect(m.easternParts(JAN)?.hour).toBe(7);
    expect(m.easternParts(JUL)?.hour).toBe(8);
    expect(m.easternZoneLabel(JUL)).toBe('EDT');
    expect(m.easternParts(JUL)).toEqual(m.easternPartsByRule(JUL));
  });

  it('ET7c: an Intl that throws — on construction or on use — falls back to the rule', async () => {
    const a = await freshEastern(throwingCtorIntl);
    expect(a.easternParts(JUL)).toEqual(a.easternPartsByRule(JUL));
    expect(a.easternZoneLabel(JUL)).toBe('EDT');
    vi.unstubAllGlobals();
    const b = await freshEastern(throwingFormatIntl);
    expect(b.easternParts(JAN)).toEqual(b.easternPartsByRule(JAN));
    expect(b.easternZoneLabel(JAN)).toBe('EST');
  });

  it('ET7d: CONTROL — on a real zone-aware Intl the formatter is kept and Intl is what answers', async () => {
    const spy = vi.spyOn(Intl.DateTimeFormat.prototype, 'formatToParts');
    const m = await freshEastern();            // no stub: the real Intl
    expect(m.easternParts(JAN)?.hour).toBe(7);
    expect(spy).toHaveBeenCalled();            // the probe did not disable a good engine
    spy.mockRestore();
  });
});
