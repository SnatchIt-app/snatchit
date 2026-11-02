/**
 * Eastern time on the feed rows and Home's sections (owner, 2026-11-02: Snatch It operates in Eastern Time;
 * A's rulings). `clockLabel`, `featureMetaLine`, a listing's stored date line and src/lib/home/sections.ts read
 * New York's calendar and clock — never the phone's. The ABSOLUTE clock forms ("Ends Mon 21:14 EST") and a
 * listing's stored date and time carry EST / EDT; the duration forms ("2h 14m left", "Ending in 11m") are
 * zone-free and unchanged.
 *
 * Every case runs with the process zone set to UTC, America/Los_Angeles and America/New_York in turn and must
 * give the same answer. Each anchor has a WITNESS that the device zone really disagrees there, so a helper that
 * fell back to the device could not pass.
 *
 * Anchors (A's): 2026-11-02 04:59:59Z / 05:00:00Z (ET midnight in EST), 2026-11-01 03:59:59Z / 04:00:00Z (ET
 * midnight in EDT), the 25-hour 2026-11-01 (01:30 EDT at 05:30Z, then 01:30 EST at 06:30Z), the 23-hour
 * 2026-03-08, and the evening 2026-11-03T02:14Z (Mon 2 Nov 21:14 EST = Mon 18:14 LA = Tue 02:14 UTC).
 *
 * Negative controls (run by hand; each must FAIL): clockLabel's same-day test, day count, weekday/date and HH:MM
 * back on device getters (EK1–EK6); featureMetaLine's "today" back on the device calendar (EF1, EF2); the listing
 * line without the label (EL1, EL3); sections back on device midnight (ES1–ES5).
 */
import { afterEach, describe, expect, it } from 'vitest';

import { groupByEventDate, sectionFor } from '@/src/lib/home/sections';
import {
  clockLabel,
  featureMetaLine,
  listingWhenLabel,
  rowMeta,
  rowWhenLabel,
} from '@/src/lib/listing/feedRowState';
import { easternParts } from '@/src/lib/time/eastern';

const ZONES = ['UTC', 'America/Los_Angeles', 'America/New_York'] as const;
const original = process.env.TZ;
afterEach(() => { if (original === undefined) delete process.env.TZ; else process.env.TZ = original; });

/** Runs `fn` under each process zone and returns the answer, which must be the same in all three. */
function underEveryZone<T>(fn: () => T): T {
  const answers = ZONES.map((z) => { process.env.TZ = z; return fn(); });
  for (const a of answers) expect(a).toEqual(answers[0]);
  return answers[0];
}
const ms = (iso: string) => Date.parse(iso);
const pad = (n: number) => String(n).padStart(2, '0');
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/** How the DEVICE reads an instant in `zone` — what a device-zone fallback would show. */
function device(iso: string, zone: string) {
  process.env.TZ = zone;
  const d = new Date(iso);
  return {
    day: `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    clock: `${WD[d.getDay()]} ${pad(d.getHours())}:${pad(d.getMinutes())}`,
  };
}

describe('clockLabel — New York\'s day, weekday and clock; the absolute forms say EST / EDT', () => {
  it('EK1: the evening anchor — an auction ending Mon 21:14 EST reads that way on every phone', () => {
    const now = ms('2026-11-01T17:00:00Z');   // Sun 1 Nov 12:00 EST
    expect(underEveryZone(() => clockLabel('2026-11-03T02:14:00Z', now))).toEqual({ text: 'Ends Mon 21:14 EST', urgent: false });
    // Witness: a UTC phone reads Tue 02:14, an LA phone Mon 18:14.
    expect(device('2026-11-03T02:14:00Z', 'UTC').clock).toBe('Tue 02:14');
    expect(device('2026-11-03T02:14:00Z', 'America/Los_Angeles').clock).toBe('Mon 18:14');
  });

  it('EK2: the same-day boundary is New York midnight in EST (05:00Z)', () => {
    const now = ms('2026-11-02T04:00:00Z');   // Sun 1 Nov 23:00 EST
    expect(underEveryZone(() => clockLabel('2026-11-02T04:59:00Z', now))).toEqual({ text: '59m left', urgent: false });
    expect(underEveryZone(() => clockLabel('2026-11-02T05:00:00Z', now))).toEqual({ text: 'Ends Mon 00:00 EST', urgent: false });
    // Witness: on a UTC phone (both the 2nd) and an LA phone (both the 1st) now and 05:00Z are the SAME device
    // day, so a device-calendar test would say "1h 0m left".
    expect(device('2026-11-02T04:00:00Z', 'UTC').day).toBe(device('2026-11-02T05:00:00Z', 'UTC').day);
    expect(device('2026-11-02T04:00:00Z', 'America/Los_Angeles').day).toBe(device('2026-11-02T05:00:00Z', 'America/Los_Angeles').day);
  });

  it('EK3: the same-day boundary is New York midnight in EDT (04:00Z)', () => {
    const now = ms('2026-11-01T03:00:00Z');   // Sat 31 Oct 23:00 EDT
    expect(underEveryZone(() => clockLabel('2026-11-01T03:59:00Z', now))).toEqual({ text: '59m left', urgent: false });
    expect(underEveryZone(() => clockLabel('2026-11-01T04:00:00Z', now))).toEqual({ text: 'Ends Sun 00:00 EDT', urgent: false });
    expect(device('2026-11-01T03:00:00Z', 'UTC').day).toBe(device('2026-11-01T04:00:00Z', 'UTC').day);
    expect(device('2026-11-01T03:00:00Z', 'America/Los_Angeles').day).toBe(device('2026-11-01T04:00:00Z', 'America/Los_Angeles').day);
  });

  it('EK4: the 25-hour 2026-11-01 — 01:30 happens twice and says which; 24 hours can still be "today"', () => {
    const before = ms('2026-10-31T16:00:00Z');   // Sat 12:00 EDT
    expect(underEveryZone(() => clockLabel('2026-11-01T05:30:00Z', before))).toEqual({ text: 'Ends Sun 01:30 EDT', urgent: false });
    expect(underEveryZone(() => clockLabel('2026-11-01T06:30:00Z', before))).toEqual({ text: 'Ends Sun 01:30 EST', urgent: false });
    expect(device('2026-11-01T05:30:00Z', 'UTC').clock).toBe('Sun 05:30');
    // 00:30 EDT → 23:30 EST is 24 hours inside ONE New York day; no phone in UTC or LA sees one day there.
    const early = ms('2026-11-01T04:30:00Z');
    expect(underEveryZone(() => clockLabel('2026-11-02T04:30:00Z', early))).toEqual({ text: '24h 0m left', urgent: false });
    expect(device('2026-11-01T04:30:00Z', 'UTC').day).not.toBe(device('2026-11-02T04:30:00Z', 'UTC').day);
    expect(device('2026-11-01T04:30:00Z', 'America/Los_Angeles').day).not.toBe(device('2026-11-02T04:30:00Z', 'America/Los_Angeles').day);
  });

  it('EK5: the 23-hour 2026-03-08 — 03:30 EDT after the gap; seven calendar days across it are dated', () => {
    expect(underEveryZone(() => clockLabel('2026-03-08T07:30:00Z', ms('2026-03-07T17:00:00Z')))).toEqual({ text: 'Ends Sun 03:30 EDT', urgent: false });
    const tue = ms('2026-03-03T15:00:00Z');      // Tue 3 Mar 10:00 EST
    expect(underEveryZone(() => clockLabel('2026-03-09T13:00:00Z', tue))).toEqual({ text: 'Ends Mon 09:00 EDT', urgent: false });
    // Under 7 × 24 hours by the clock, but seven New York calendar days: dated.
    expect(underEveryZone(() => clockLabel('2026-03-10T13:00:00Z', tue))).toEqual({ text: 'Ends 10 Mar 09:00 EDT', urgent: false });
    expect(device('2026-03-10T13:00:00Z', 'America/Los_Angeles').clock).toBe('Tue 06:00');
  });

  it('EK6: the seven-day cutover counts New York days — Mon 9 Nov 18:00 EST is seven days from Mon 2 Nov 21:14 EST', () => {
    const now = ms('2026-11-03T02:14:00Z');      // Mon 2 Nov 21:14 EST
    expect(underEveryZone(() => clockLabel('2026-11-09T04:30:00Z', now))).toEqual({ text: 'Ends Sun 23:30 EST', urgent: false });
    expect(underEveryZone(() => clockLabel('2026-11-09T23:00:00Z', now))).toEqual({ text: 'Ends 9 Nov 18:00 EST', urgent: false });
    // Witness: a UTC phone is on Tue 3 Nov, so Mon 9 Nov 23:00 UTC is only six of ITS days away and would read "Ends Mon 23:00".
    expect(device('2026-11-03T02:14:00Z', 'UTC').day).toBe('2026-11-03');
    expect(device('2026-11-09T23:00:00Z', 'UTC').clock).toBe('Mon 23:00');
  });

  it('EK7: the duration forms carry no label and are the same everywhere; a dead clock is null', () => {
    const now = ms('2026-11-03T02:00:00Z');
    expect(underEveryZone(() => clockLabel(new Date(now + 11 * 60_000).toISOString(), now))).toEqual({ text: 'Ending in 11m', urgent: true });
    expect(underEveryZone(() => clockLabel('2026-11-02T19:14:00Z', ms('2026-11-02T17:00:00Z')))).toEqual({ text: '2h 14m left', urgent: false });
    expect(underEveryZone(() => clockLabel('2026-11-03T01:59:59Z', now))).toBeNull();
    expect(underEveryZone(() => clockLabel('not-a-date', now))).toBeNull();
  });
});

describe('featureMetaLine — "today" is New York\'s today', () => {
  it('EF1: at Mon 2 Nov 21:14 EST tonight\'s event drops its date; tomorrow\'s keeps it', () => {
    const now = ms('2026-11-03T02:14:00Z');
    expect(underEveryZone(() => featureMetaLine({ eventDate: '2026-11-02', eventTime: '22:00:00', venue: 'Lantern Room' }, now)))
      .toBe('22:00 EST · Lantern Room');
    expect(underEveryZone(() => featureMetaLine({ eventDate: '2026-11-03', eventTime: '19:30:00', venue: 'Lantern Room' }, now)))
      .toBe('Tue 3 Nov · 19:30 EST · Lantern Room');
    expect(device('2026-11-03T02:14:00Z', 'UTC').day).toBe('2026-11-03');   // a UTC phone calls the 3rd "today"
  });

  it('EF2: the day turns at New York midnight (05:00Z in EST)', () => {
    const event = { eventDate: '2026-11-01', eventTime: '23:30', venue: 'V' };
    expect(underEveryZone(() => featureMetaLine(event, ms('2026-11-02T04:59:59Z')))).toBe('23:30 EST · V');
    expect(underEveryZone(() => featureMetaLine(event, ms('2026-11-02T05:00:00Z')))).toBe('Sun 1 Nov · 23:30 EST · V');
    expect(device('2026-11-02T04:59:59Z', 'UTC').day).toBe('2026-11-02');
    expect(device('2026-11-02T05:00:00Z', 'America/Los_Angeles').day).toBe('2026-11-01');
  });

  it('EF3: a stored time that happens twice is shown without a label', () => {
    expect(underEveryZone(() => featureMetaLine({ eventDate: '2026-11-01', eventTime: '01:30', venue: 'V' }, ms('2026-11-01T12:00:00Z'))))
      .toBe('01:30 · V');
  });
});

describe('a listing\'s stored date and time — labelled, never converted (A, 2026-11-02)', () => {
  it('EL1: the stored wall clock is shown as stored, with the EST / EDT for that date and time', () => {
    expect(underEveryZone(() => listingWhenLabel('2026-10-24', '19:30'))).toBe('Sat 24 Oct · 19:30 EDT');
    expect(underEveryZone(() => listingWhenLabel('2026-12-05', '19:30:00'))).toBe('Sat 5 Dec · 19:30 EST');
    expect(underEveryZone(() => listingWhenLabel('2026-11-01', '03:00:00'))).toBe('Sun 1 Nov · 03:00 EST');
    // Witness: treating the stored text as a device-local instant and CONVERTING it would move the time —
    // an LA phone would show 22:30, a UTC phone 15:30.
    process.env.TZ = 'America/Los_Angeles';
    expect(easternParts(new Date('2026-10-24T19:30').getTime())?.hour).toBe(22);
    process.env.TZ = 'UTC';
    expect(easternParts(new Date('2026-10-24T19:30').getTime())?.hour).toBe(15);
  });

  it('EL2: a time that happens twice or never, or a malformed value, is shown unlabelled (or not at all)', () => {
    expect(underEveryZone(() => listingWhenLabel('2026-11-01', '01:30'))).toBe('Sun 1 Nov · 01:30');
    expect(underEveryZone(() => listingWhenLabel('2026-03-08', '02:30'))).toBe('Sun 8 Mar · 02:30');
    expect(underEveryZone(() => listingWhenLabel('not-a-date', '19:30'))).toBe('');
    expect(underEveryZone(() => listingWhenLabel('2026-10-24', ''))).toBe('');
  });

  it('EL3: the feed row\'s first meta line carries it; the bare shape stays zone-free for callers that format an instant', () => {
    const m = underEveryZone(() => rowMeta({
      eventDate: '2026-10-24', eventTime: '19:30:00', venue: 'Lantern Room', quantity: 2, ticketType: 'GA', bidCount: 3,
    }));
    expect(m).toEqual({ meta1: 'Sat 24 Oct · 19:30 EDT · Lantern Room', meta2: '2 × GA · 3 bids' });
    expect(underEveryZone(() => rowWhenLabel('2026-10-24', '19:30'))).toBe('Sat 24 Oct · 19:30');
  });
});

describe('sections — Home\'s Tonight / This week / Later turn at New York midnight', () => {
  it('ES1: ET midnight in EST (05:00Z): the 2nd becomes "Tonight" and the 1st leaves', () => {
    const before = ms('2026-11-02T04:59:59Z');
    const after = ms('2026-11-02T05:00:00Z');
    expect(underEveryZone(() => [sectionFor('2026-11-02', before), sectionFor('2026-11-02', after)])).toEqual(['week', 'tonight']);
    expect(underEveryZone(() => [sectionFor('2026-11-01', before), sectionFor('2026-11-01', after)])).toEqual(['tonight', 'undated']);
    expect(device('2026-11-02T04:59:59Z', 'UTC').day).toBe('2026-11-02');
    expect(device('2026-11-02T05:00:00Z', 'America/Los_Angeles').day).toBe('2026-11-01');
  });

  it('ES2: ET midnight in EDT (04:00Z)', () => {
    expect(underEveryZone(() => [sectionFor('2026-11-01', ms('2026-11-01T03:59:59Z')), sectionFor('2026-11-01', ms('2026-11-01T04:00:00Z'))]))
      .toEqual(['week', 'tonight']);
    expect(device('2026-11-01T03:59:59Z', 'UTC').day).toBe('2026-11-01');
    expect(device('2026-11-01T04:00:00Z', 'America/Los_Angeles').day).toBe('2026-10-31');
  });

  it('ES3: the thresholds are unchanged — 1–7 New York days is "This week", 8 or more "Later"', () => {
    const after = ms('2026-11-02T05:00:00Z');
    expect(underEveryZone(() => [sectionFor('2026-11-09', after), sectionFor('2026-11-10', after)])).toEqual(['week', 'later']);
    const before = ms('2026-11-02T04:59:59Z');
    expect(underEveryZone(() => [sectionFor('2026-11-08', before), sectionFor('2026-11-09', before)])).toEqual(['week', 'later']);
  });

  it('ES4: the 25-hour Nov 1 and the 23-hour Mar 8 are one day each', () => {
    expect(underEveryZone(() => sectionFor('2026-11-01', ms('2026-11-02T04:30:00Z')))).toBe('tonight');   // 23:30 EST, hour 25
    expect(underEveryZone(() => sectionFor('2026-03-08', ms('2026-03-09T03:59:59Z')))).toBe('tonight');   // 23:59:59 EDT
    expect(underEveryZone(() => [sectionFor('2026-03-08', ms('2026-03-09T04:00:00Z')), sectionFor('2026-03-09', ms('2026-03-09T04:00:00Z'))]))
      .toEqual(['undated', 'tonight']);
    expect(device('2026-11-02T04:30:00Z', 'UTC').day).toBe('2026-11-02');
  });

  it('ES5: the evening anchor groups by New York\'s Monday; an instant and its day key group identically', () => {
    const now = ms('2026-11-03T02:14:00Z');   // Mon 2 Nov 21:14 EST
    const rows = [
      { id: 'a', event_date: '2026-11-10' },
      { id: 'b', event_date: '2026-11-02' },
      { id: 'c', event_date: '2026-11-03' },
      { id: 'd', event_date: '2026-11-01' },
      { id: 'e', event_date: '2026-11-09' },
      { id: 'f', event_date: '2026-13-01' },
      { id: 'g', event_date: null },
    ];
    const shape = (today: number | string) =>
      groupByEventDate(rows, (r) => r.event_date, today).map((s) => [s.key, s.label, s.items.map((r) => r.id)]);
    const expected = [
      ['tonight', 'Tonight', ['b']],
      ['week', 'This week', ['c', 'e']],
      ['later', 'Later', ['a']],
      ['undated', null, ['d', 'f', 'g']],
    ];
    expect(underEveryZone(() => shape(now))).toEqual(expected);
    expect(underEveryZone(() => shape('2026-11-02'))).toEqual(expected);
    expect(device('2026-11-03T02:14:00Z', 'UTC').day).toBe('2026-11-03');   // a UTC phone would call 'c' tonight
    expect(underEveryZone(() => [sectionFor('not-a-date', now), sectionFor('', now), sectionFor('2026-11-3', now)])).toEqual(['undated', 'undated', 'undated']);
  });
});
