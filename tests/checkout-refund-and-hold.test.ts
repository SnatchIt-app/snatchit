/**
 * tests/checkout-refund-and-hold.test.ts — Premium batch 1: the refund states
 * (A-03, CFT-308), the not-held state (CFT-301, D9-UX-1), the pay gating margin
 * (A-04, CFT-302/305) and the price-change reconciliation (A-02, CFT-304).
 *
 * Every rule is exercised as behaviour with mocked dependencies. Nothing here
 * touches Stripe or the network.
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';

// payments.ts imports the supabase client, which pulls in react-native. Nothing
// in these tests reaches the network; the client is a no-op stand-in.
vi.mock('@/src/lib/supabase', () => ({
  supabase: { auth: { getSession: async () => ({ data: { session: null } }) }, functions: { invoke: async () => ({ data: null, error: null }) }, rpc: async () => ({ data: null, error: null }) },
}));

import {
  _resetSetupInFlight,
  decideCheckoutSetup,
  isRefundConfirmed,
  pickSettled,
  settledKind,
  type SetupDeps,
} from '../src/lib/checkout/setupDecision';
import { payControl, PAY_EXPIRY_MARGIN_MS, withinExpiryMargin, type PayControlInput } from '../src/lib/checkout/payControl';
import { fmtHoldUntil, notHeldCopy, notHeldReason, REFUND_COPY } from '../src/lib/checkout/holdState';
import { isExpectedCheckoutError, isPriceChangedMessage, PriceChangedError, reconcilePriceChange } from '../src/lib/payments';

const NOW = new Date('2026-09-14T18:00:00Z');
const LIVE_HOLD = { status: 'reserved', reserved_by: 'buyer', reserved_until: '2026-09-14T18:09:00Z' };

function deps(over: Partial<SetupDeps<string>> = {}) {
  return {
    fetchSettledPayment: vi.fn(async () => null),
    fetchListing: vi.fn(async () => LIVE_HOLD),
    createIntent: vi.fn(async () => 'pi_new'),
    now: () => NOW,
    ...over,
  } as SetupDeps<string> & { createIntent: ReturnType<typeof vi.fn> };
}

beforeEach(() => _resetSetupInFlight());

const SUCCEEDED = { status: 'succeeded' };
const REFUNDED_CONFIRMED = { status: 'refunded', refunded_at: '2026-09-13T10:00:00Z', amount_refunded_cents: 11000, total: 11000 };
const REFUNDED_UNDATED = { status: 'refunded', refunded_at: null, amount_refunded_cents: 11000, total: 11000 };
const REFUNDED_PARTIAL = { status: 'refunded', refunded_at: '2026-09-13T10:00:00Z', amount_refunded_cents: 5000, total: 11000 };

describe('refund states never reach the success screen', () => {
  it('a confirmed refund is its own kind, and creates no intent', async () => {
    const d = deps({ fetchSettledPayment: vi.fn(async () => REFUNDED_CONFIRMED) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'buy_now' }, d);
    expect(r).toEqual({ kind: 'refunded' });
    expect(d.createIntent).not.toHaveBeenCalled();
  });

  it('an undated refund is pending, not confirmed', async () => {
    const d = deps({ fetchSettledPayment: vi.fn(async () => REFUNDED_UNDATED) });
    const r = await decideCheckoutSetup({ listingId: 'L', buyerId: 'buyer', mode: 'auction' }, d);
    expect(r).toEqual({ kind: 'refund_pending' });
    expect(d.createIntent).not.toHaveBeenCalled();
  });

  it('a partial refund is pending, not confirmed', () => {
    expect(isRefundConfirmed(REFUNDED_PARTIAL)).toBe(false);
    expect(settledKind(REFUNDED_PARTIAL)).toBe('refund_pending');
  });

  it('succeeded outranks refunded whatever order the rows arrive in', () => {
    expect(pickSettled([REFUNDED_CONFIRMED, SUCCEEDED])?.status).toBe('succeeded');
    expect(pickSettled([SUCCEEDED, REFUNDED_CONFIRMED])?.status).toBe('succeeded');
    expect(settledKind(pickSettled([REFUNDED_CONFIRMED, SUCCEEDED]))).toBe('already_settled');
  });

  it('already_settled means succeeded only', () => {
    expect(settledKind(SUCCEEDED)).toBe('already_settled');
    expect(settledKind(REFUNDED_CONFIRMED)).not.toBe('already_settled');
    expect(settledKind({ status: 'pending' })).toBeNull();
  });

  it('refund copy promises nothing about the bank and never says the purchase succeeded', () => {
    for (const c of Object.values(REFUND_COPY)) {
      const text = `${c.kicker} ${c.title} ${c.body}`;
      expect(text).not.toMatch(/business days|within \d|by (tomorrow|friday)/i);
      expect(text).not.toMatch(/you're in|purchase (complete|confirmed)|tickets are (ready|confirmed)/i);
      expect(text).toMatch(/no purchase was made/i);
    }
    expect(REFUND_COPY.refunded.kicker).toBe('Payment refunded');
    expect(REFUND_COPY.refund_pending.kicker).not.toMatch(/refunded$/i);
  });
});

describe('a lost hold is reported for what the client knows', () => {
  const NOW_MS = NOW.getTime();

  it('says "released" only when this screen released it', () => {
    expect(notHeldReason({ releasedByUs: true, reservedUntilMs: NOW_MS + 60_000, nowMs: NOW_MS })).toBe('released_by_us');
    expect(notHeldCopy('released_by_us').title).toMatch(/released/i);
  });

  it('says "ran out" only when the deadline it showed has passed', () => {
    expect(notHeldReason({ releasedByUs: false, reservedUntilMs: NOW_MS - 1, nowMs: NOW_MS })).toBe('ran_out');
    expect(notHeldCopy('ran_out').title).toMatch(/ran out/i);
  });

  it('is neutral when the hold vanished before its deadline (the D9-UX-1 case)', () => {
    const reason = notHeldReason({ releasedByUs: false, reservedUntilMs: NOW_MS + 8 * 60_000, nowMs: NOW_MS });
    expect(reason).toBe('unknown');
    const copy = notHeldCopy(reason);
    expect(copy.title).not.toMatch(/expired|released|ran out/i);
  });

  it('never claims a charge, and always points back to the listing', () => {
    for (const r of ['released_by_us', 'ran_out', 'unknown'] as const) {
      const c = notHeldCopy(r);
      expect(c.body).toMatch(/nothing was charged/i);
      expect(c.body).toMatch(/go back to the listing/i);
    }
  });

  it('the control becomes Back to listing, not Try again', () => {
    const base: PayControlInput = {
      authLoading: false, paymentLoading: false, confirming: false,
      paymentReady: false, paymentError: true, holdLost: true, formattedTotal: '$110',
    };
    expect(payControl(base)).toEqual({ label: 'Back to listing', loading: false, disabled: false, action: 'back' });
    // A lost hold outranks a stale ready flag too.
    expect(payControl({ ...base, paymentReady: true }).action).toBe('back');
  });

  it('keeps Try again for transient setup errors where the hold may be live', () => {
    const p = payControl({
      authLoading: false, paymentLoading: false, confirming: false,
      paymentReady: false, paymentError: true, holdLost: false, formattedTotal: '$110',
    });
    expect(p.action).toBe('retry');
  });

  it('formats the actual deadline, and degrades to null rather than throwing', () => {
    expect(fmtHoldUntil(Date.UTC(2026, 8, 14, 21, 14), 'en-US')).toMatch(/\d{1,2}:14/);
    expect(fmtHoldUntil(Number.NaN, 'en-US')).toBeNull();
  });
});

describe('Pay is withdrawn inside the expiry margin (A-04)', () => {
  const ready: PayControlInput = {
    authLoading: false, paymentLoading: false, confirming: false,
    paymentReady: true, paymentError: false, formattedTotal: '$110',
  };

  it('the margin is 15 seconds and owned by the contract', () => {
    expect(PAY_EXPIRY_MARGIN_MS).toBe(15_000);
  });

  it('offers Pay with time to spare', () => {
    expect(payControl({ ...ready, reservationMsLeft: PAY_EXPIRY_MARGIN_MS + 1 }).action).toBe('pay');
    expect(payControl({ ...ready, reservationMsLeft: null }).action).toBe('pay');
  });

  it('withdraws Pay at or under the margin, including zero', () => {
    for (const ms of [PAY_EXPIRY_MARGIN_MS, 1_000, 0]) {
      const p = payControl({ ...ready, reservationMsLeft: ms });
      expect(p.action).toBe('none');
      expect(p.disabled).toBe(true);
      expect(withinExpiryMargin(ms)).toBe(true);
    }
  });

  it('a reconciliation in progress shows no Pay and no retry', () => {
    const p = payControl({ ...ready, checking: true, paymentError: true });
    expect(p).toEqual({ label: 'Checking your payment', loading: true, disabled: true, action: 'none' });
  });
});

describe('price change requires a fresh acceptance (A-02)', () => {
  it('is recognised as an expected checkout refusal, not a system failure', () => {
    expect(isExpectedCheckoutError('Price changed. Please review the updated total and try again.')).toBe(true);
    expect(isPriceChangedMessage('Price changed. Please review the updated total and try again.')).toBe(true);
  });

  it('carries the server total on the typed error', () => {
    const e = new PriceChangedError('Price changed.', 12100);
    expect(e).toBeInstanceOf(Error);
    expect(e.serverTotalCents).toBe(12100);
  });

  it('offers the new total only when the fresh listing agrees with the server', () => {
    const r = reconcilePriceChange({ serverTotalCents: 12100, freshTotalCents: 12100, acceptedTotalCents: 11000 });
    expect(r).toEqual({ outcome: 'accept_required', previousCents: 11000, nextAcceptedCents: 12100 });
  });

  it('offers nothing when the fresh listing disagrees, or could not be read', () => {
    expect(reconcilePriceChange({ serverTotalCents: 12100, freshTotalCents: 13200, acceptedTotalCents: 11000 })).toEqual({ outcome: 'mismatch' });
    expect(reconcilePriceChange({ serverTotalCents: 12100, freshTotalCents: null, acceptedTotalCents: 11000 })).toEqual({ outcome: 'mismatch' });
  });

  it('never auto-accepts: the accepted total only changes through the returned next value', () => {
    const r = reconcilePriceChange({ serverTotalCents: 12100, freshTotalCents: 12100, acceptedTotalCents: 11000 });
    expect(r.outcome === 'accept_required' && r.previousCents).toBe(11000);
  });
});
