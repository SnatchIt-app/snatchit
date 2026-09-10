/**
 * tests/checkout-setup-reentry.test.ts — checkout mount behaviour, with every
 * external call mocked. These exercise the orchestrator CheckoutNative runs on
 * mount (src/lib/checkout/setupDecision.ts), not the text of the screen.
 *
 * D5 review, blocking item 1: after 3-D Secure the return URL remounts
 * checkout/[id]. A remount after a successful charge must render the completed
 * settlement and create nothing; it must never say "reservation expired"; and
 * auction mode must not mint a second intent.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import {
  _resetSetupInFlight,
  decideCheckoutSetup,
  holdIsMine,
  isSettled,
  type SetupDeps,
} from '../src/lib/checkout/setupDecision';

const NOW = new Date('2026-09-10T18:00:00Z');
const LIVE_HOLD = { status: 'reserved', reserved_by: 'buyer', reserved_until: '2026-09-10T18:09:00Z' };
const SOLD = { status: 'sold', reserved_by: null, reserved_until: null };

function deps(over: Partial<SetupDeps<string>> = {}) {
  const d = {
    fetchSettledPayment: vi.fn(async () => null),
    fetchListing: vi.fn(async () => LIVE_HOLD),
    createIntent: vi.fn(async () => 'pi_new'),
    now: () => NOW,
    ...over,
  };
  return d as SetupDeps<string> & { [K in keyof SetupDeps<string>]: ReturnType<typeof vi.fn> };
}

beforeEach(() => _resetSetupInFlight());

describe('(a) buy_now re-entry after a succeeded payment', () => {
  it('shows completed settlement and calls nothing that could charge', async () => {
    const d = deps({ fetchSettledPayment: vi.fn(async () => ({ status: 'succeeded' })), fetchListing: vi.fn(async () => SOLD) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    expect(r).toEqual({ kind: 'already_settled' });
    expect(d.createIntent).not.toHaveBeenCalled();
    expect(d.fetchListing).not.toHaveBeenCalled(); // settled decides before the hold is even read
  });

  it('a refunded purchase is also settled: never re-charge a refunded buyer', async () => {
    const d = deps({ fetchSettledPayment: vi.fn(async () => ({ status: 'refunded' })) });
    expect((await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d)).kind).toBe('already_settled');
    expect(d.createIntent).not.toHaveBeenCalled();
  });
});

describe('(b) auction re-entry after a succeeded payment', () => {
  it('same result, and no second intent', async () => {
    const d = deps({ fetchSettledPayment: vi.fn(async () => ({ status: 'succeeded' })) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'auction' }, d);
    expect(r).toEqual({ kind: 'already_settled' });
    expect(d.createIntent).not.toHaveBeenCalled();
  });
});

describe('(c) no prior payment + live reservation', () => {
  it('creates exactly one intent and reports ready', async () => {
    const d = deps();
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    expect(r).toEqual({ kind: 'ready', intent: 'pi_new' });
    expect(d.createIntent).toHaveBeenCalledTimes(1);
  });

  it('auction with no prior payment skips the hold check and creates one intent', async () => {
    const d = deps({ fetchListing: vi.fn(async () => SOLD) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'auction' }, d);
    expect(r.kind).toBe('ready');
    expect(d.fetchListing).not.toHaveBeenCalled();
    expect(d.createIntent).toHaveBeenCalledTimes(1);
  });
});

describe('(d) two rapid re-entries', () => {
  it('share one in-flight setup: at most one intent', async () => {
    let release!: () => void;
    const gate = new Promise<void>((res) => { release = res; });
    const d = deps({ createIntent: vi.fn(async () => { await gate; return 'pi_once'; }) });
    const p1 = decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    const p2 = decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    release();
    const [r1, r2] = await Promise.all([p1, p2]);
    expect(r1).toEqual({ kind: 'ready', intent: 'pi_once' });
    expect(r2).toEqual(r1);
    expect(d.createIntent).toHaveBeenCalledTimes(1);
    expect(d.fetchSettledPayment).toHaveBeenCalledTimes(1);
  });

  it('a different buyer or listing is not deduplicated', async () => {
    const d = deps();
    await Promise.all([
      decideCheckoutSetup({ listingId: 'L', buyerId: 'a', mode: 'auction' }, d),
      decideCheckoutSetup({ listingId: 'L', buyerId: 'b', mode: 'auction' }, d),
    ]);
    expect(d.createIntent).toHaveBeenCalledTimes(2);
  });
});

describe('(e) "reservation expired" is unreachable once a payment succeeded', () => {
  it('a sold listing with the buyer\'s succeeded payment never reports expired', async () => {
    const d = deps({ fetchSettledPayment: vi.fn(async () => ({ status: 'succeeded' })), fetchListing: vi.fn(async () => SOLD) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    expect(r.kind).not.toBe('reservation_expired');
    expect(r.kind).toBe('already_settled');
  });

  it('a sold listing WITHOUT a payment by this buyer does report expired (someone else bought it)', async () => {
    const d = deps({ fetchListing: vi.fn(async () => SOLD) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    expect(r).toEqual({ kind: 'reservation_expired' });
    expect(d.createIntent).not.toHaveBeenCalled();
  });

  it('an unreadable listing is unverifiable, not expired, and creates nothing', async () => {
    const d = deps({ fetchListing: vi.fn(async () => null) });
    expect((await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d)).kind).toBe('reservation_unverifiable');
    expect(d.createIntent).not.toHaveBeenCalled();
  });
});

describe('predicates', () => {
  it('settled is exactly succeeded or refunded', () => {
    expect(isSettled({ status: 'succeeded' })).toBe(true);
    expect(isSettled({ status: 'refunded' })).toBe(true);
    for (const s of ['pending', 'processing', 'failed', 'canceled']) expect(isSettled({ status: s })).toBe(false);
    expect(isSettled(null)).toBe(false);
  });

  it('a hold is mine only while reserved, by me, and not yet expired', () => {
    expect(holdIsMine(LIVE_HOLD, 'buyer', NOW)).toBe(true);
    expect(holdIsMine(LIVE_HOLD, 'other', NOW)).toBe(false);
    expect(holdIsMine({ ...LIVE_HOLD, reserved_until: '2026-09-10T17:59:00Z' }, 'buyer', NOW)).toBe(false);
    expect(holdIsMine(SOLD, 'buyer', NOW)).toBe(false);
  });
});

describe('the screen runs this orchestrator on mount (thin wiring check)', () => {
  const src = readFileSync(resolve(__dirname, '..', 'src/screens/checkout/CheckoutNative.tsx'), 'utf8');
  it('settlement is rendered from the decision and the sheet is never initialised for it', () => {
    expect(src).toContain('decideCheckoutSetup(');
    const block = src.slice(src.indexOf("decision.kind === 'already_settled'"), src.indexOf("decision.kind === 'reservation_unverifiable'"));
    expect(block).toContain("setSettlement('completed')");
    expect(block).toContain('confirmedRef.current = true');
    expect(block).toContain('return;');
    expect(block).not.toMatch(/initPaymentSheet|presentPaymentSheet|createPaymentIntent/);
  });
  it('the own-rows payment read is scoped to listing AND buyer and to settled statuses', () => {
    const start = src.indexOf("from('payments')");
    const q = src.slice(start, src.indexOf('maybeSingle()', start));
    expect(q).toContain("eq('listing_id', lid)");
    expect(q).toContain("eq('buyer_id', bid)");
    expect(q).toContain("in('status', [...SETTLED_STATUSES])");
  });
});
