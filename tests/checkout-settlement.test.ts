/**
 * tests/checkout-settlement.test.ts — RC4 finding F (checkout false-alarm).
 *
 * SUBJECT: what the buyer is told AFTER the Stripe PaymentSheet has already
 * returned success — i.e. after the card may already be charged.
 *
 * Two claims were raised against src/screens/checkout/CheckoutNative.tsx:
 *   F1. the `mark_listing_sold` failure branch (:285-296 pre-fix) applies no
 *       benign/expected-error filter, so a settlement refusal that is NOT a
 *       failure surfaces "Payment Received … Please contact support."
 *   F2. the same path sets the sold state (:315 pre-fix) regardless, so the
 *       buyer sees that support alert and then "Purchase complete!".
 *
 * The first `describe` below transcribes the SHIPPED sequence literally and
 * shows what it produces (documenting the pre-fix behaviour). The rest pin the
 * fixed contract in src/lib/payments.ts: three distinct outcomes — completed /
 * pending / failed — from the real server error shapes.
 *
 * Error strings are the exact `RAISE EXCEPTION` texts of
 * supabase/migrations/20260906100000_checkout_reservation_authority.sql
 * (mark_listing_sold :193, :207; complete_auction_payment :237, :251) and the
 * confirm-payment response bodies of supabase/functions/confirm-payment/index.ts
 * (:208-210 unverified, :315-323 settled).
 *
 * No network, no Supabase, no Stripe: the client module is loaded against a
 * recording fake of `supabase`.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { supabase } from '@/src/lib/supabase';
import {
  finalizePurchase,
  isExpectedCheckoutError,
  isSettlementPendingError,
  SETTLEMENT_COPY,
} from '@/src/lib/payments';

// ── Recording fake of the app's Supabase client ─────────────────────────────
// vi.mock and vi.hoisted are both hoisted above the imports above, so the
// state the factory closes over has to be hoisted with it.
const h = vi.hoisted(() => ({
  state: {
    session: { access_token: 'jwt-buyer' } as { access_token: string } | null,
    // { data, error } exactly as supabase.functions.invoke resolves it
    confirm: { data: null as unknown, error: null as unknown },
    rpc: {} as Record<string, { data?: unknown; error?: { message: string; code?: string } | null }>,
    transferRow: null as { id: string } | null,
    calls: [] as string[],
    rpcArgs: [] as { name: string; args: Record<string, unknown> }[],
  },
}));

vi.mock('@/src/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: async () => ({ data: { session: h.state.session } }),
    },
    functions: {
      invoke: async (name: string) => {
        h.state.calls.push(`fn:${name}`);
        return h.state.confirm;
      },
    },
    rpc: async (name: string, args: Record<string, unknown>) => {
      h.state.calls.push(`rpc:${name}`);
      h.state.rpcArgs.push({ name, args });
      return h.state.rpc[name] ?? { data: null, error: null };
    },
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => {
            h.state.calls.push(`select:${table}`);
            return { data: h.state.transferRow, error: null };
          },
        }),
      }),
    }),
  },
}));

const LISTING = 'listing-0001';
const BUYER = 'buyer-holder';
const PI = 'pi_test_1';

// ── Server fixtures ─────────────────────────────────────────────────────────

/** confirm-payment 200 after settle_verified_payment ran (index.ts:315-323). */
const CONFIRM_SETTLED = {
  data: { success: true, stripe_verified: true, outcome: 'settled', transfer_id: 'transfer-1' },
  error: null,
};
/** …the webhook got there first: the contract reports it idempotently. */
const CONFIRM_ALREADY_SETTLED = {
  data: { success: true, stripe_verified: true, outcome: 'already_settled', transfer_id: 'transfer-1' },
  error: null,
};
/** confirm-payment 200 `unverified()` — Stripe has NOT succeeded the PI yet
 *  (index.ts:208-210, :247-258). Nothing was written. Genuinely uncertain. */
const CONFIRM_UNVERIFIED = {
  data: { success: true, stripe_verified: false },
  error: null,
};
/** the listing settled to a DIFFERENT payment: money captured, cannot fulfil. */
const CONFIRM_UNFULFILLABLE = {
  data: { success: true, stripe_verified: true, outcome: 'unfulfillable', transfer_id: null },
  error: null,
};

/** mark_listing_sold / complete_auction_payment before the payments row is
 *  promoted to `succeeded` (migration 20260906100000 :193 / :237). */
const ERR_NOT_YET_CONFIRMED = {
  message: 'No verified payment found for this listing. Payment must be confirmed before the sale can complete.',
  code: 'P0001',
};
/** settle_listing_for_payment returned `unfulfillable` (migration :207 / :251):
 *  the listing is bound to ANOTHER payment. pgTAP 120 F2. */
const ERR_ALREADY_SOLD = { message: 'This listing has already been sold.', code: 'P0001' };

function reset(over: Partial<typeof h.state> = {}) {
  h.state.session = { access_token: 'jwt-buyer' };
  h.state.confirm = { data: null, error: null };
  h.state.rpc = {};
  h.state.transferRow = null;
  h.state.calls = [];
  h.state.rpcArgs = [];
  Object.assign(h.state, over);
}

beforeEach(() => reset());

// ===========================================================================
// 1. Reproduction — the SHIPPED sequence, transcribed literally
// ===========================================================================
/**
 * Byte-faithful transcription of CheckoutNative.tsx handleConfirmPurchase
 * :281-315 as it stood BEFORE this change (PaymentSheet has already returned
 * with no error at this point), including the shipped confirmPaymentSuccess
 * which discards the response body. Frozen on purpose: it must not drift with
 * the fix, because its whole job is to show what the buyer used to see.
 */
async function shippedSequence(): Promise<{ alerts: string[]; screen: string | null }> {
  const alerts: string[] = [];
  let screen: string | null = null;

  // confirmPaymentSuccess (payments.ts:107-128, pre-fix): fire and forget —
  // `data` is never read, so stripe_verified never reaches the screen.
  const { error: fnError } = (await supabase.functions.invoke('confirm-payment', {})) as {
    error: { message: string } | null;
  };
  if (fnError) {
    /* logged, not thrown */
  }

  const { error: rpcError } = (await supabase.rpc('mark_listing_sold', {
    p_listing_id: LISTING,
    p_user_id: BUYER,
  })) as { error: { message: string } | null };

  if (rpcError) {
    alerts.push(
      'Payment Received: Your payment was processed but we had trouble updating the listing. Please contact support.',
    );
  }

  await supabase.rpc('ensure_transfer_exists', { p_listing_id: LISTING });
  const { data: transferRow } = (await supabase
    .from('transfers')
    .select('id')
    .eq('listing_id', LISTING)
    .maybeSingle()) as { data: { id: string } | null };
  if (transferRow?.id) {
    /* setPostPurchaseTransferId */
  }

  screen = 'Purchase complete!'; // :315 setSold(true) — unconditional
  return { alerts, screen };
}

describe('reproduction — pre-fix CheckoutNative sequence (CheckoutNative.tsx:281-315)', () => {
  it('F1+F2: a SUCCESSFUL purchase still awaiting Stripe confirmation showed the support alert AND "Purchase complete!"', async () => {
    // Real, documented shape: PaymentSheet succeeded, Stripe has not flipped
    // the PI to `succeeded` yet, so confirm-payment writes nothing and
    // mark_listing_sold refuses with "No verified payment found…".
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { mark_listing_sold: { data: null, error: ERR_NOT_YET_CONFIRMED } },
    });

    const out = await shippedSequence();

    // This is the defect: an alarming alert on a purchase that is fine…
    expect(out.alerts).toHaveLength(1);
    expect(out.alerts[0]).toMatch(/contact support/i);
    // …immediately followed by the success screen (F2).
    expect(out.screen).toBe('Purchase complete!');
  });

  it('F2: even a genuinely UNFULFILLABLE settlement ended on "Purchase complete!"', async () => {
    reset({
      confirm: CONFIRM_UNFULFILLABLE,
      rpc: { mark_listing_sold: { data: null, error: ERR_ALREADY_SOLD } },
    });

    const out = await shippedSequence();

    expect(out.alerts[0]).toMatch(/contact support/i);
    expect(out.screen).toBe('Purchase complete!');
  });

  it('F1 premise check: after the WEBHOOK settles, mark_listing_sold does NOT refuse — it returns already_settled with no error', async () => {
    // settle_listing_for_payment (migration 20260906100000 :139-151) returns
    // 'already_settled' when the listing is sold and the bound transfer is THIS
    // payment's, and mark_listing_sold (:205-210) only raises
    // "This listing has already been sold." on 'unfulfillable'. So the claimed
    // "correct server refusal after settlement" is not a refusal at all.
    reset({
      confirm: CONFIRM_ALREADY_SETTLED,
      rpc: { mark_listing_sold: { data: null, error: null } },
      transferRow: { id: 'transfer-1' },
    });

    const out = await shippedSequence();

    expect(out.alerts).toEqual([]);
    expect(out.screen).toBe('Purchase complete!');
  });
});

// ===========================================================================
// 2. The fix — three distinct post-charge outcomes
// ===========================================================================

describe('isSettlementPendingError', () => {
  it('treats the "payment not promoted yet" refusals as not-yet, not never', () => {
    expect(isSettlementPendingError(ERR_NOT_YET_CONFIRMED.message)).toBe(true);
    expect(isSettlementPendingError('Payment has not succeeded; cannot settle the listing.')).toBe(true);
    expect(isSettlementPendingError('Network request failed')).toBe(true);
  });

  it('never swallows a terminal refusal — the buyer paid and cannot be served', () => {
    expect(isSettlementPendingError(ERR_ALREADY_SOLD.message)).toBe(false);
    expect(isSettlementPendingError('This listing is already reserved by another buyer.')).toBe(false);
  });

  it('is a SEPARATE axis from the pre-payment expected-error list', () => {
    // "already sold" is benign BEFORE the charge (nothing was taken) and
    // terminal AFTER it. The two lists must not be merged.
    expect(isExpectedCheckoutError(ERR_ALREADY_SOLD.message)).toBe(true);
    expect(isSettlementPendingError(ERR_ALREADY_SOLD.message)).toBe(false);
  });

  it('recognises BOTH server wordings of "already sold"', () => {
    // The edge functions and the SQL word the same fact differently; the
    // shipped /already sold/i matched only the first.
    expect(isExpectedCheckoutError('This listing is already sold.')).toBe(true);      // create-payment-intent :451
    expect(isExpectedCheckoutError('This listing has already been sold.')).toBe(true); // migration :207
  });
});

describe('finalizePurchase — (a) settlement COMPLETED', () => {
  it('returns completed when the settlement RPC succeeds', async () => {
    reset({
      confirm: CONFIRM_SETTLED,
      rpc: { mark_listing_sold: { data: null, error: null }, ensure_transfer_exists: { data: null, error: null } },
      transferRow: { id: 'transfer-1' },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('completed');
    expect(out.transferId).toBe('transfer-1');
    expect(SETTLEMENT_COPY.completed.alert).toBe(false);
    expect(SETTLEMENT_COPY.completed.title).toBe('Purchase complete!');
  });

  it('is completed when the WEBHOOK settled first (RPC no-ops with already_settled)', async () => {
    reset({
      confirm: CONFIRM_ALREADY_SETTLED,
      rpc: { mark_listing_sold: { data: null, error: null } },
      transferRow: { id: 'transfer-1' },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('completed');
  });

  it('is completed when confirm-payment reports the sale settled, even if the legacy RPC then refuses', async () => {
    // Defensive: the edge holds service_role and just wrote through
    // settle_verified_payment. Its own outcome is authoritative over the
    // shipped-client follow-up RPC.
    reset({
      confirm: CONFIRM_ALREADY_SETTLED,
      rpc: { mark_listing_sold: { data: null, error: ERR_ALREADY_SOLD } },
      transferRow: { id: 'transfer-1' },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('completed');
  });

  it('routes an auction win through complete_auction_payment', async () => {
    reset({
      confirm: CONFIRM_SETTLED,
      rpc: { complete_auction_payment: { data: null, error: null } },
      transferRow: { id: 'transfer-1' },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'auction' });

    expect(out.outcome).toBe('completed');
    expect(h.state.rpcArgs[0]).toEqual({
      name: 'complete_auction_payment',
      args: { p_listing_id: LISTING, p_user_id: BUYER },
    });
  });
});

describe('finalizePurchase — (c) outcome UNCERTAIN / pending (regression for F1)', () => {
  it('classifies "No verified payment found…" as pending, NOT as a support-alert failure', async () => {
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { mark_listing_sold: { data: null, error: ERR_NOT_YET_CONFIRMED } },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('pending');
    // F1: no alert at all, and nothing about contacting support.
    expect(SETTLEMENT_COPY.pending.alert).toBe(false);
    expect(SETTLEMENT_COPY.pending.body).not.toMatch(/contact support/i);
    // …and it must actually reassure the buyer.
    expect(SETTLEMENT_COPY.pending.body).toMatch(/pay again/i);
  });

  it('classifies the same refusal on the auction path as pending', async () => {
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { complete_auction_payment: { data: null, error: ERR_NOT_YET_CONFIRMED } },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'auction' });

    expect(out.outcome).toBe('pending');
  });

  it('is pending when the settlement RPC never reached the server', async () => {
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { mark_listing_sold: { data: null, error: { message: 'Network request failed' } } },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('pending');
  });

  it('is pending on an UNRECOGNISED refusal while confirm-payment says Stripe has not succeeded the charge', async () => {
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { mark_listing_sold: { data: null, error: { message: 'deadlock detected', code: '40P01' } } },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('pending');
  });

  it('does not touch transfers while the outcome is uncertain', async () => {
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { mark_listing_sold: { data: null, error: ERR_NOT_YET_CONFIRMED } },
    });

    await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(h.state.calls).toEqual(['fn:confirm-payment', 'rpc:mark_listing_sold']);
  });
});

describe('finalizePurchase — (b) settlement genuinely FAILED', () => {
  it('keeps the actionable alert when the listing is bound to another payment', async () => {
    reset({
      confirm: CONFIRM_UNFULFILLABLE,
      rpc: { mark_listing_sold: { data: null, error: ERR_ALREADY_SOLD } },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('failed');
    expect(SETTLEMENT_COPY.failed.alert).toBe(true);
    expect(SETTLEMENT_COPY.failed.body).toMatch(/contact support/i);
    expect(out.detail).toContain('This listing has already been sold.');
  });

  it('stays failed — never pending — when the listing is gone but Stripe has not verified yet', async () => {
    // The terminal check must run BEFORE the "Stripe hasn't succeeded it yet"
    // pending rule, or a listing sold to someone else would be reported as a
    // calm "your order will appear shortly".
    reset({
      confirm: CONFIRM_UNVERIFIED,
      rpc: { mark_listing_sold: { data: null, error: ERR_ALREADY_SOLD } },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('failed');
  });

  it('fails when an auction win is blocked by another buyer’s live Buy-Now hold', async () => {
    reset({
      confirm: CONFIRM_UNFULFILLABLE,
      rpc: {
        complete_auction_payment: {
          data: null,
          error: { message: 'This listing is already reserved by another buyer.', code: 'P0001' },
        },
      },
    });

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'auction' });

    expect(out.outcome).toBe('failed');
  });

  it('fails on an unrecognised refusal once Stripe HAS verified the charge', async () => {
    reset({
      confirm: CONFIRM_SETTLED,
      // settle reported 'settled' would short-circuit; use a verified confirm
      // whose contract outcome is not a settlement.
      rpc: { mark_listing_sold: { data: null, error: { message: 'permission denied for table listings', code: '42501' } } },
    });
    h.state.confirm = { data: { success: true, stripe_verified: true, outcome: null, transfer_id: null }, error: null };

    const out = await finalizePurchase({ listingId: LISTING, userId: BUYER, paymentIntentId: PI, mode: 'buy_now' });

    expect(out.outcome).toBe('failed');
  });
});

describe('finalizePurchase — F2 regression: the success screen is not shown for pending or failed', () => {
  it('only the completed outcome carries the "Purchase complete!" screen', () => {
    expect(SETTLEMENT_COPY.completed.title).toBe('Purchase complete!');
    expect(SETTLEMENT_COPY.pending.title).not.toBe('Purchase complete!');
    expect(SETTLEMENT_COPY.failed.title).not.toBe('Purchase complete!');
  });

  it('exactly one outcome raises an alert, and it is the failure', () => {
    const alerting = (['completed', 'pending', 'failed'] as const).filter((k) => SETTLEMENT_COPY[k].alert);
    expect(alerting).toEqual(['failed']);
  });
});
