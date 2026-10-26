/**
 * ticketWhen — the event's date, doors and start in ONE named zone (Q02: exact event/date/timezone).
 *
 * A's rule (from D's 162, 2026-10-26): event times are exact instants; display local times from the
 * session's `*_local` fields (D's 182: 'YYYY-MM-DD HH24:MI' in the venue zone) or in the venue
 * timezone — never the device's when the venue's is known. 21+ is display-only, from 182's
 * `age_restriction` (all_ages | 18_plus | 21_plus | null).
 *
 * Pinned with explicit zones/strings so results do not depend on the machine running the suite.
 * Negative control (run by hand, must FAIL): build the local date with `new Date(local)` (device
 * zone) instead of the string's own parts — W4 fails on a non-New-York machine and W5 always.
 */
import { describe, expect, it } from 'vitest';

import { entryRestrictionLine, whenFromLocal, whenLine } from '@/src/lib/tickets/ticketWhen';

describe('whenLine — instant + zone (fallback when only the instant is known)', () => {
  it('W1: renders doors and start in the given zone and names the zone', () => {
    const w = whenLine('2026-12-01T04:00:00Z', '2026-12-01T03:00:00Z', 'America/New_York');
    expect(w).not.toBeNull();
    expect(w!.date).toMatch(/Nov 30/);
    expect(w!.times).toMatch(/^Doors 10:00 PM · 11:00 PM EST$/);
    expect(w!.zone).toBe('EST');
  });

  it('W2: the same instant in another zone is a different clock and a different zone name', () => {
    const w = whenLine('2026-12-01T04:00:00Z', null, 'America/Los_Angeles');
    expect(w!.times).toMatch(/^8:00 PM PST$/);
    expect(w!.date).toMatch(/Nov 30/);
  });

  it('W3: no doors time → start only; an unparseable start → null', () => {
    expect(whenLine('2026-12-01T04:00:00Z', null, 'America/New_York')!.times).toBe('11:00 PM EST');
    expect(whenLine('not-a-date', null, 'America/New_York')).toBeNull();
  });
});

describe('whenFromLocal — the venue-local strings 182 returns, with the zone named', () => {
  it('W4: "2026-11-30 23:00" + doors "2026-11-30 22:00" in New York reads Mon, Nov 30 · Doors 10:00 PM · 11:00 PM EST', () => {
    const w = whenFromLocal({ startsAtLocal: '2026-11-30 23:00', doorsAtLocal: '2026-11-30 22:00', timezone: 'America/New_York', startsAt: '2026-12-01T04:00:00Z' });
    expect(w).toEqual({ date: 'Mon, Nov 30', times: 'Doors 10:00 PM · 11:00 PM EST', zone: 'EST' });
  });

  it('W5: the date comes from the string, not the device clock — a 00:30 start stays on its own day', () => {
    const w = whenFromLocal({ startsAtLocal: '2026-12-01 00:30', doorsAtLocal: null, timezone: 'America/New_York', startsAt: '2026-12-01T05:30:00Z' });
    expect(w!.date).toBe('Tue, Dec 1');
    expect(w!.times).toBe('12:30 AM EST');
  });

  it('W6: an unknown zone keeps the local clock and omits the zone name rather than guessing one', () => {
    const w = whenFromLocal({ startsAtLocal: '2026-11-30 23:00', doorsAtLocal: null, timezone: 'Not/AZone', startsAt: '2026-12-01T04:00:00Z' });
    expect(w).toEqual({ date: 'Mon, Nov 30', times: '11:00 PM', zone: '' });
  });

  it('W7: malformed local strings give null (the screen falls back), never NaN text', () => {
    expect(whenFromLocal({ startsAtLocal: '30/11/2026 11pm', doorsAtLocal: null, timezone: 'America/New_York', startsAt: null })).toBeNull();
    expect(whenFromLocal({ startsAtLocal: null, doorsAtLocal: null, timezone: 'America/New_York', startsAt: null })).toBeNull();
  });
});

describe('entryRestrictionLine — 182 age_restriction, display only', () => {
  it('R1: 21_plus and 18_plus say the age and that ID is checked; all_ages says so; null says nothing', () => {
    expect(entryRestrictionLine('21_plus')).toBe('21+ · ID checked at the door');
    expect(entryRestrictionLine('18_plus')).toBe('18+ · ID checked at the door');
    expect(entryRestrictionLine('all_ages')).toBe('All ages');
    expect(entryRestrictionLine(null)).toBeNull();
    expect(entryRestrictionLine(undefined)).toBeNull();
  });

  it('R2: a value outside the contract set shows nothing rather than a guessed age', () => {
    expect(entryRestrictionLine('25_plus')).toBeNull();
    expect(entryRestrictionLine('')).toBeNull();
  });
});
