/**
 * ticketWhen — the event's date, doors and start in ONE named zone (Q02: exact event/date/timezone).
 * Pinned with an explicit zone so the result does not depend on the machine running the suite.
 */
import { describe, expect, it } from 'vitest';

import { entryRestrictionLine, whenLine } from '@/src/lib/tickets/ticketWhen';

describe('whenLine', () => {
  it('W1: renders doors and start in the event zone and names the zone', () => {
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

describe('entryRestrictionLine', () => {
  it('R1: only a server-supplied minimum age becomes a line, and it says ID is checked', () => {
    expect(entryRestrictionLine(21)).toBe('21+ · ID checked at the door');
    expect(entryRestrictionLine(null)).toBeNull();
    expect(entryRestrictionLine(undefined)).toBeNull();
    expect(entryRestrictionLine(0)).toBeNull();
  });
});
