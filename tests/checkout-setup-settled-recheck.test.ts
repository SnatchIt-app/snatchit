/**
 * tests/checkout-setup-settled-recheck.test.ts: F6, found by C's critical-flow audit (2026-10-12).
 *
 * decideCheckoutSetup reads the buyer's settled payments first and the listing second. If the webhook settles the
 * payment in between (payment succeeded, listing sold), the listing read sees "not mine" and the old code returned
 * `not_held`. Its copy (holdState.ts) says "Nothing was charged", to a buyer who was just charged. This is likeliest
 * on the 3-D Secure return, which remounts checkout while the webhook is in flight.
 *
 * The rule: before claiming `not_held`, read the settled payments once more. Whatever that re-read establishes wins.
 * A failed re-read establishes nothing, so the answer is the existing payment_status_unknown state, never "not held".
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  _resetSetupInFlight,
  decideCheckoutSetup,
  decideRevalidation,
  type ListingRead,
  type SettledRead,
  type SetupDeps,
} from '../src/lib/checkout/setupDecision';

const NOW = new Date('2026-10-12T05:00:00Z');
const SOLD = { status: 'sold', reserved_by: null, reserved_until: null };
const EXPIRED_HOLD = { status: 'reserved', reserved_by: 'buyer', reserved_until: '2026-10-12T04:50:00Z' };
const LIVE_HOLD = { status: 'reserved', reserved_by: 'buyer', reserved_until: '2026-10-12T05:09:00Z' };
const INPUT = { listingId: 'L', buyerId: 'buyer', mode: 'buy_now' as const };

/** fetchSettledPayment answers from a queue: one entry per call, an Error entry throws. */
function deps(settledAnswers: unknown[], listing: unknown) {
  const queue = [...settledAnswers];
  const d = {
    fetchSettledPayment: vi.fn(async () => {
      const next = queue.shift();
      if (next instanceof Error) throw next;
      return next as never;
    }),
    fetchListing: vi.fn(async () => listing as never),
    createIntent: vi.fn(async () => 'pi_new'),
    now: () => NOW,
  };
  return d as SetupDeps<string> & { [K in keyof SetupDeps<string>]: ReturnType<typeof vi.fn> };
}

beforeEach(() => _resetSetupInFlight());

describe('F6: the payment settles between the settled read and the listing read', () => {
  it('a succeeded payment visible on the re-read is the completed settlement, never "not held"', async () => {
    const d = deps([[], [{ status: 'succeeded' }]], SOLD);
    const r = await decideCheckoutSetup(INPUT, d);
    expect(r).toEqual({ kind: 'already_settled' });
    expect(d.fetchSettledPayment).toHaveBeenCalledTimes(2);
    expect(d.createIntent).not.toHaveBeenCalled();
  });

  it('a refund visible on the re-read is reported as the refund it is, never "not held"', async () => {
    const d = deps([[], [{ status: 'refunded' }]], SOLD);
    const r = await decideCheckoutSetup(INPUT, d);
    expect(r.kind).toBe('refund_unconfirmed');
    expect(d.createIntent).not.toHaveBeenCalled();
  });

  it('a failed re-read establishes nothing: payment status unknown, never "not held"', async () => {
    const d = deps([[], new Error('network')], SOLD);
    const r = await decideCheckoutSetup(INPUT, d);
    expect(r).toEqual({ kind: 'payment_status_unknown', detail: 'network' });
    expect(d.createIntent).not.toHaveBeenCalled();
  });
});

describe('F6: unchanged paths', () => {
  it('no settled payment on either read: still not_held (an expired hold, nothing charged)', async () => {
    const d = deps([[], []], EXPIRED_HOLD);
    expect(await decideCheckoutSetup(INPUT, d)).toEqual({ kind: 'not_held' });
    expect(d.fetchSettledPayment).toHaveBeenCalledTimes(2);
    expect(d.createIntent).not.toHaveBeenCalled();
  });

  it('a live hold is not re-read: one settled read, one intent', async () => {
    const d = deps([[]], LIVE_HOLD);
    expect(await decideCheckoutSetup(INPUT, d)).toEqual({ kind: 'ready', intent: 'pi_new' });
    expect(d.fetchSettledPayment).toHaveBeenCalledTimes(1);
    expect(d.createIntent).toHaveBeenCalledTimes(1);
  });

  it('auction mode never reads the listing, so it never re-reads either', async () => {
    const d = deps([[]], SOLD);
    expect((await decideCheckoutSetup({ ...INPUT, mode: 'auction' }, d)).kind).toBe('ready');
    expect(d.fetchListing).not.toHaveBeenCalled();
    expect(d.fetchSettledPayment).toHaveBeenCalledTimes(1);
  });
});

/**
 * The same race in decideRevalidation (the independent reviewer's finding, 2026-10-12): the settled read, then the
 * listing read, then `lost`, whose copy is again "Nothing was charged". The same rule applies: re-read the settled
 * payments once before `lost`.
 */
function revalDeps(settledAnswers: (SettledRead | Error)[], listing: ListingRead) {
  const queue = [...settledAnswers];
  return {
    readSettled: vi.fn(async (): Promise<SettledRead> => {
      const next = queue.shift();
      if (next instanceof Error) throw next;
      return next as SettledRead;
    }),
    readListing: vi.fn(async (): Promise<ListingRead> => listing),
  };
}
const REVAL = { buyerId: 'buyer', isBuyNow: true, now: NOW };

describe('F6 in decideRevalidation: the payment settles between the two reads', () => {
  it('a succeeded payment visible on the re-read is already_settled, never "lost"', async () => {
    const d = revalDeps([{ rows: [] }, { rows: [{ status: 'succeeded' } as never] }], { listing: SOLD as never });
    expect(await decideRevalidation(REVAL, d)).toEqual({ kind: 'already_settled' });
    expect(d.readSettled).toHaveBeenCalledTimes(2);
  });

  it('a refund visible on the re-read is reported as the refund it is, never "lost"', async () => {
    const d = revalDeps([{ rows: [] }, { rows: [{ status: 'refunded' } as never] }], { listing: SOLD as never });
    expect((await decideRevalidation(REVAL, d)).kind).toBe('refund_unconfirmed');
  });

  it('a failed re-read establishes nothing: payment status unknown, never "lost"', async () => {
    const d = revalDeps([{ rows: [] }, { error: { code: '08006', message: 'connection' } }], { listing: SOLD as never });
    expect(await decideRevalidation(REVAL, d)).toEqual({ kind: 'payment_status_unknown', detail: '08006: connection' });
  });

  it('a thrown re-read establishes nothing either', async () => {
    const d = revalDeps([{ rows: [] }, new Error('network')], { listing: SOLD as never });
    expect(await decideRevalidation(REVAL, d)).toEqual({ kind: 'payment_status_unknown', detail: 'no-code: network' });
  });

  it('no settled payment on either read: still lost (one re-read, nothing charged)', async () => {
    const d = revalDeps([{ rows: [] }, { rows: [] }], { listing: EXPIRED_HOLD as never });
    expect(await decideRevalidation(REVAL, d)).toEqual({ kind: 'lost' });
    expect(d.readSettled).toHaveBeenCalledTimes(2);
  });

  it('a live hold is not re-read', async () => {
    const d = revalDeps([{ rows: [] }], { listing: LIVE_HOLD as never });
    expect((await decideRevalidation(REVAL, d)).kind).toBe('held');
    expect(d.readSettled).toHaveBeenCalledTimes(1);
  });
});
