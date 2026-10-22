/**
 * DST probe for the dated clock (A's review of 7088ff94, 2026-10-21). In America/New_York the clocks
 * go forward on 2027-03-14, inside the seven-day window: from 10:00 on 9 Mar to 09:00 on 16 Mar is
 * under 7 × 24 hours by the wall clock, but it is 7 calendar days, so the label must be dated.
 * The calendar-day count uses UTC midnights of the LOCAL dates, so the 23-hour day can't move it.
 */
process.env.TZ = 'America/New_York';

import { describe, expect, it } from 'vitest';

import { clockLabel } from '@/src/lib/listing/feedRowState';

describe('clockLabel across a DST change', () => {
  it('K6: 9 Mar 10:00 → 16 Mar 09:00 (spring forward between) reads "Ends 16 Mar 09:00"', () => {
    const now = new Date(2027, 2, 9, 10, 0).getTime();          // local New York wall time
    const ends = new Date(2027, 2, 16, 9, 0).toISOString();
    expect(new Date(now).getTimezoneOffset()).not.toBe(new Date(ends).getTimezoneOffset()); // the DST change is real
    expect(clockLabel(ends, now)).toEqual({ text: 'Ends 16 Mar 09:00', urgent: false });
  });

  it('K7: six calendar days across the change still read as a weekday', () => {
    const now = new Date(2027, 2, 9, 10, 0).getTime();
    expect(clockLabel(new Date(2027, 2, 15, 9, 0).toISOString(), now)).toEqual({ text: 'Ends Mon 09:00', urgent: false });
  });
});
