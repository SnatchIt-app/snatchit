/**
 * Money and transfer deadlines read in Eastern Time (owner, 2026-11-02: "we operate in EST, everything about
 * Snatch It should be in EST"; A's rulings, A/TIMEZONE-DECISION-20261102.md). The deadline is shown as New York's
 * wall clock with its zone, EST or EDT (src/lib/time/eastern.ts) — never the phone's zone, which must not move a
 * money deadline. The instant behind it is untouched: every comparison and timer stays in UTC ms. A owns these
 * sentences; only the zone and the label changed.
 *
 *   site                                          shape (at 2026-11-03T02:14Z)
 *   nextAction.ts      sellerNextAction           "Send by Mon 2 Nov · 21:14 EST"                    (My Listings)
 *   transferState.ts   buyerReviewDeadlineLine    "…, or report a problem, before Mon 2 Nov · 21:14 EST."
 *                      sellerReleaseLine          "Release decision at Mon 2 Nov · 21:14 EST."
 *                      sellerHoldLine             "Payout held until Mon 2 Nov · 21:14 EST."
 *   orderPresentation  shortDeadline              "by Mon 09:14 PM EST"  (12h as before; fixed en-US words)
 *                      orderWhenWhereLine         a STORED wall clock — labelled, never converted
 *
 * Every case runs under the process zones UTC, America/Los_Angeles and America/New_York and must give the same
 * answer; a witness per anchor shows the device zone really disagrees there, so a device-zone fallback could not
 * pass. Anchors are A's discriminating ones plus an evening one (Mon 2 Nov 21:14 EST = Mon 18:14 in LA = Tue
 * 02:14 UTC).
 *
 * Negative controls (run by hand, each must FAIL): put the device getters back in nextAction.easternDeadline (TD1,
 * TD2), in transferState.easternDateTime (TD1–TD5), or toLocaleDateString/TimeString(undefined, …) back in
 * shortDeadline (TD1, TD7) and orderWhenWhereLine (TD7).
 */
import { afterEach, describe, expect, it, vi } from 'vitest';

import { orderProgress, orderProgressA11y, orderWhenWhereLine, shortDeadline } from '@/src/lib/orders/orderPresentation';
import { msUntilNextSellerLineChange, sellerNextAction } from '@/src/lib/seller/nextAction';
import { buyerReviewDeadlineLine, sellerHoldLine, sellerReleaseLine } from '@/src/lib/transfer/transferState';

const ZONES = ['UTC', 'America/Los_Angeles', 'America/New_York'] as const;
const original = process.env.TZ;
afterEach(() => {
  if (original === undefined) delete process.env.TZ;
  else process.env.TZ = original;
  vi.restoreAllMocks();
});

/** Runs `fn` under each process zone and returns the answers, which must all be equal. */
function underEveryZone<T>(fn: () => T): T {
  const answers = ZONES.map((z) => { process.env.TZ = z; return fn(); });
  for (const a of answers) expect(a).toEqual(answers[0]);
  return answers[0];
}

const WEEKDAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTH = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const pad = (n: number) => String(n).padStart(2, '0');
/** The old reading: the instant in the DEVICE zone, row format, no label — what a device-zone fallback shows. */
const deviceRow = (iso: string, zone: string) => {
  process.env.TZ = zone;
  const d = new Date(iso);
  return `${WEEKDAY[d.getDay()]} ${d.getDate()} ${MONTH[d.getMonth()]} · ${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

const sold = (expires_at: string) => ({ listingStatus: 'sold', transfer: { status: 'pending', expires_at } });
/** Every deadline line for one server instant, read at a clock well before it. */
const lines = (iso: string) => ({
  send: sellerNextAction(sold(iso), Date.parse(iso) - 86_400_000)?.line,
  review: buyerReviewDeadlineLine(iso),
  release: sellerReleaseLine(iso),
  hold: sellerHoldLine('held', iso),
  short: shortDeadline(iso),
});
const expected = (row: string, short: string) => ({
  send: `Send by ${row}`,
  review: `Confirm you received the tickets, or report a problem, before ${row}.`,
  release: `Release decision at ${row}.`,
  hold: `Payout held until ${row}.`,
  short,
});

describe('money deadlines are New York wall clock + EST/EDT, whatever the phone says', () => {
  it('TD1: evening anchor 2026-11-03T02:14Z is Mon 2 Nov 21:14 EST — an LA phone reads 18:14, a UTC phone Tue 02:14', () => {
    const iso = '2026-11-03T02:14:00Z';
    expect(underEveryZone(() => lines(iso))).toEqual(expected('Mon 2 Nov · 21:14 EST', 'by Mon 09:14 PM EST'));
    expect(deviceRow(iso, 'America/Los_Angeles')).toBe('Mon 2 Nov · 18:14');
    expect(deviceRow(iso, 'UTC')).toBe('Tue 3 Nov · 02:14');
  });

  it('TD2: ET midnight in EST — 04:59:59Z is still Sun 1 Nov, 05:00:00Z is Mon 2 Nov 00:00', () => {
    expect(underEveryZone(() => lines('2026-11-02T04:59:59Z'))).toEqual(expected('Sun 1 Nov · 23:59 EST', 'by Sun 11:59 PM EST'));
    expect(underEveryZone(() => lines('2026-11-02T05:00:00Z'))).toEqual(expected('Mon 2 Nov · 00:00 EST', 'by Mon 12:00 AM EST'));
    expect(deviceRow('2026-11-02T04:59:59Z', 'UTC')).toBe('Mon 2 Nov · 04:59');                 // a UTC phone is already on the 2nd
    expect(deviceRow('2026-11-02T05:00:00Z', 'America/Los_Angeles')).toBe('Sun 1 Nov · 21:00');  // an LA phone is still on the 1st
  });

  it('TD3: ET midnight in EDT — 03:59:59Z is still Sat 31 Oct, 04:00:00Z is Sun 1 Nov 00:00', () => {
    expect(underEveryZone(() => lines('2026-11-01T03:59:59Z'))).toEqual(expected('Sat 31 Oct · 23:59 EDT', 'by Sat 11:59 PM EDT'));
    expect(underEveryZone(() => lines('2026-11-01T04:00:00Z'))).toEqual(expected('Sun 1 Nov · 00:00 EDT', 'by Sun 12:00 AM EDT'));
    expect(deviceRow('2026-11-01T03:59:59Z', 'UTC')).toBe('Sun 1 Nov · 03:59');
    expect(deviceRow('2026-11-01T04:00:00Z', 'America/Los_Angeles')).toBe('Sat 31 Oct · 21:00');
  });

  it('TD4: the 25-hour 2026-11-01 — 01:30 happens twice, and the label tells them apart (EDT at 05:30Z, EST at 06:30Z)', () => {
    expect(underEveryZone(() => lines('2026-11-01T05:30:00Z'))).toEqual(expected('Sun 1 Nov · 01:30 EDT', 'by Sun 01:30 AM EDT'));
    expect(underEveryZone(() => lines('2026-11-01T06:30:00Z'))).toEqual(expected('Sun 1 Nov · 01:30 EST', 'by Sun 01:30 AM EST'));
    expect(deviceRow('2026-11-01T05:30:00Z', 'America/Los_Angeles')).toBe('Sat 31 Oct · 22:30');
    expect(deviceRow('2026-11-01T06:30:00Z', 'UTC')).toBe('Sun 1 Nov · 06:30');
  });

  it('TD5: the 23-hour 2026-03-08 — 01:59 EST is followed by 03:00 EDT', () => {
    expect(underEveryZone(() => lines('2026-03-08T06:59:00Z'))).toEqual(expected('Sun 8 Mar · 01:59 EST', 'by Sun 01:59 AM EST'));
    expect(underEveryZone(() => lines('2026-03-08T07:00:00Z'))).toEqual(expected('Sun 8 Mar · 03:00 EDT', 'by Sun 03:00 AM EDT'));
    expect(deviceRow('2026-03-08T07:00:00Z', 'America/Los_Angeles')).toBe('Sat 7 Mar · 23:00');
    expect(deviceRow('2026-03-08T07:00:00Z', 'UTC')).toBe('Sun 8 Mar · 07:00');
  });

  it('TD6: the deadline comparison stays an instant — the same boundary and the same timer under every zone', () => {
    const iso = '2026-11-03T02:14:00Z';
    const at = Date.parse(iso);
    expect(underEveryZone(() => [sellerNextAction(sold(iso), at - 1)?.kind, sellerNextAction(sold(iso), at)?.kind])).toEqual(['send_by', 'window_passed']);
    expect(underEveryZone(() => msUntilNextSellerLineChange([sold(iso)], at - 90_000))).toBe(90_000);
    // Unparseable stays unparseable: no time is invented.
    expect(underEveryZone(() => [buyerReviewDeadlineLine('not-a-date'), sellerReleaseLine(''), shortDeadline('garbage')])).toEqual([null, null, null]);
    expect(underEveryZone(() => sellerNextAction(sold('not-a-date'), at)?.line)).toBe('Send the tickets');
  });

  it('TD7: the device LOCALE never spells it either — a French phone still reads "by Mon 09:14 PM EST"', () => {
    // Simulate a device whose default locale is fr-FR: every locale-default Date formatter answers in French.
    const date = Date.prototype.toLocaleDateString;
    const time = Date.prototype.toLocaleTimeString;
    const both = Date.prototype.toLocaleString;
    vi.spyOn(Date.prototype, 'toLocaleDateString').mockImplementation(function (this: Date, l?: Intl.LocalesArgument, o?: Intl.DateTimeFormatOptions) { return date.call(this, l ?? 'fr-FR', o); });
    vi.spyOn(Date.prototype, 'toLocaleTimeString').mockImplementation(function (this: Date, l?: Intl.LocalesArgument, o?: Intl.DateTimeFormatOptions) { return time.call(this, l ?? 'fr-FR', o); });
    vi.spyOn(Date.prototype, 'toLocaleString').mockImplementation(function (this: Date, l?: Intl.LocalesArgument, o?: Intl.DateTimeFormatOptions) { return both.call(this, l ?? 'fr-FR', o); });
    // Witness: the simulated device really does speak French.
    expect(new Date(2026, 9, 24).toLocaleDateString(undefined, { weekday: 'short' })).toBe('sam.');
    expect(new Date(2026, 9, 24).toLocaleDateString(undefined, { month: 'short' })).toBe('oct.');
    expect(underEveryZone(() => shortDeadline('2026-11-03T02:14:00Z'))).toBe('by Mon 09:14 PM EST');
    expect(underEveryZone(() => orderWhenWhereLine('2026-10-24', '19:30:00', 'Lantern Room'))).toBe('Sat 24 Oct · 19:30 EDT · Lantern Room');
  });

  it('TD8: the order progress a11y sentence carries the labelled deadline', () => {
    const a11y = () => orderProgressA11y(orderProgress({ status: 'seller_sent', buyerConfirmedAt: null, payoutReleasedAt: null, autoReleaseAt: '2026-11-03T02:14:00Z' })!);
    expect(underEveryZone(a11y)).toContain('Your confirmation, current step, by Mon 09:14 PM EST.');
  });
});

describe('orderWhenWhereLine — a stored wall clock is labelled, never converted (A, 2026-11-02)', () => {
  it('TW1: the stored date and time print as stored, with EST/EDT for that date; fixed en-US words', () => {
    expect(underEveryZone(() => orderWhenWhereLine('2026-10-24', '19:30:00', 'Lantern Room'))).toBe('Sat 24 Oct · 19:30 EDT · Lantern Room');
    expect(underEveryZone(() => orderWhenWhereLine('2026-12-05', '19:30', 'The Foundry'))).toBe('Sat 5 Dec · 19:30 EST · The Foundry');
    // Before the fall-back hour, and the evening after it.
    expect(underEveryZone(() => orderWhenWhereLine('2026-11-01', '00:30:00', null))).toBe('Sun 1 Nov · 00:30 EDT');
    expect(underEveryZone(() => orderWhenWhereLine('2026-11-01', '21:00:00', null))).toBe('Sun 1 Nov · 21:00 EST');
    // Witness: read as an instant and shown in an LA phone's zone, the stored 19:30 would move — it must not.
    process.env.TZ = 'America/Los_Angeles';
    expect(new Date('2026-10-24T19:30:00-04:00').getHours()).toBe(16);
  });

  it('TW2: a wall clock that happens twice or never gets no label — the stored text is still shown as stored', () => {
    expect(underEveryZone(() => orderWhenWhereLine('2026-11-01', '01:30:00', 'Venue'))).toBe('Sun 1 Nov · 01:30 · Venue');
    expect(underEveryZone(() => orderWhenWhereLine('2026-03-08', '02:30', 'Venue'))).toBe('Sun 8 Mar · 02:30 · Venue');
  });

  it('TW3: no time, no label; no date, no label; absent parts still drop out', () => {
    expect(underEveryZone(() => orderWhenWhereLine('2026-10-24', null, 'Lantern Room'))).toBe('Sat 24 Oct · Lantern Room');
    expect(underEveryZone(() => orderWhenWhereLine(null, '19:30:00', 'Lantern Room'))).toBe('19:30 · Lantern Room');
    expect(underEveryZone(() => orderWhenWhereLine(null, null, null))).toBe('');
  });
});
