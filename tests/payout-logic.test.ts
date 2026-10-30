/**
 * tests/payout-logic.test.ts — pure payout decision logic
 * (supabase/functions/_shared/payout-logic.ts).
 *
 * Maps to the 2026-08-04 incident's mandatory scenario list. Scenarios that
 * live in I/O or the database (Stripe accepting a source_transaction
 * transfer while the charge is pending; UPDATE … WHERE payout_released_at
 * IS NULL atomicity; stripe_webhook_events event_id dedup) are enforced by
 * those layers and verified against production evidence — what's testable
 * deterministically is the decision logic below.
 */
import { describe, expect, it } from 'vitest';

import {
  buildPayoutIdempotencyKey,
  classifyPayoutPostFailure,
  classifyPayoutStripeError,
  isCrossModeStripeError,
  maxTransferableCents,
  payoutEligibility,
  reasonCodeForErrorClass,
  rowIsLiveActionable,
  shouldPageSentry,
} from '../supabase/functions/_shared/payout-logic';

const ELIGIBLE_BASE = {
  paymentStatus:    'succeeded',
  transferStatus:   'buyer_confirmed',
  disputedAt:       null as string | null,
  payoutReleasedAt: null as string | null,
  chargeRefunded:   false,
};

describe('idempotency key — deterministic, audit-linked, attempt-scoped', () => {
  it('same attempt → byte-identical key (safe retries, races, duplicate cron runs)', () => {
    const a = buildPayoutIdempotencyKey('tr-1', 1);
    const b = buildPayoutIdempotencyKey('tr-1', 1);
    expect(a).toBe(b);
    expect(a).toBe('payout_tr-1_a1');
  });

  it('a new attempt (only after the previous is terminal) → new key, never a stale replay', () => {
    expect(buildPayoutIdempotencyKey('tr-1', 1)).not.toBe(buildPayoutIdempotencyKey('tr-1', 2));
  });

  it('different logical payouts never share a key', () => {
    expect(buildPayoutIdempotencyKey('tr-1', 1)).not.toBe(buildPayoutIdempotencyKey('tr-2', 1));
  });

  it('key space is disjoint from every earlier incident generation', () => {
    const key = buildPayoutIdempotencyKey('tr-1', 1);
    expect(key).not.toBe('payout_tr-1');                 // pre-incident bare key
    expect(key).not.toBe('payout_tr-1_acct_A');          // destination-salted gen
    expect(key).not.toBe('payout_tr-1_acct_A_ready');    // pre-flight gen
    expect(key).not.toBe('payout_tr-1_acct_A_src');      // source_transaction gen (pre-attempt ledger)
  });

  it('refuses a non-positive / non-integer attempt number (a key must map to one ledger row)', () => {
    expect(() => buildPayoutIdempotencyKey('tr-1', 0)).toThrow();
    expect(() => buildPayoutIdempotencyKey('tr-1', 1.5)).toThrow();
  });
});

describe('POST /transfers failure → attempt outcome', () => {
  it('network (no status), 5xx, 409 in-flight, 429 and idempotency_error → unknown (a transfer MAY exist; reconcile first)', () => {
    expect(classifyPayoutPostFailure(null, null)).toBe('unknown');
    expect(classifyPayoutPostFailure(500, { message: 'boom' })).toBe('unknown');
    expect(classifyPayoutPostFailure(503, null)).toBe('unknown');
    expect(classifyPayoutPostFailure(409, { message: 'in flight' })).toBe('unknown');
    expect(classifyPayoutPostFailure(429, { message: 'rate limited' })).toBe('unknown');
    expect(classifyPayoutPostFailure(400, { type: 'idempotency_error', message: 'Keys for idempotent requests...' })).toBe('unknown');
  });

  it('definite 4xx → failed_not_created (the attempt closes; a fresh attempt may open later)', () => {
    expect(classifyPayoutPostFailure(400, { type: 'invalid_request_error', message: 'No such destination' })).toBe('failed_not_created');
    expect(classifyPayoutPostFailure(402, { type: 'invalid_request_error', message: 'Insufficient funds in Stripe account.' })).toBe('failed_not_created');
    expect(classifyPayoutPostFailure(403, null)).toBe('failed_not_created');
    expect(classifyPayoutPostFailure(404, null)).toBe('failed_not_created');
  });
});

describe('Stripe error classification — operational states are not exceptions', () => {
  it('insufficient available balance → expected operational state, no Sentry page', () => {
    const cls = classifyPayoutStripeError(
      'Insufficient funds in Stripe account.    You can use the /v1/balance endpoint to view your Stripe balance (for more details, see stripe.com/docs/api#balance).',
    );
    expect(cls).toBe('insufficient_funds');
    expect(reasonCodeForErrorClass(cls)).toBe('PAYOUT_INSUFFICIENT_FUNDS');
    expect(shouldPageSentry(cls)).toBe(false);
  });

  it('inactive transfers capability → expected operational state, no Sentry page', () => {
    const cls = classifyPayoutStripeError(
      'Your destination account needs to have at least one of the following capabilities enabled: transfers, crypto_transfers, legacy_payments',
    );
    expect(cls).toBe('destination_capability');
    expect(reasonCodeForErrorClass(cls)).toBe('PAYOUT_DESTINATION_NOT_READY');
    expect(shouldPageSentry(cls)).toBe(false);
  });

  it('idempotency parameter mismatch → code bug, MUST page Sentry', () => {
    const cls = classifyPayoutStripeError(
      'Keys for idempotent requests can only be used with the same parameters they were first used with.',
    );
    expect(cls).toBe('idempotency_params');
    expect(reasonCodeForErrorClass(cls)).toBe('PAYOUT_IDEMPOTENCY_BUG');
    expect(shouldPageSentry(cls)).toBe(true);
  });

  it('anything unrecognized → unexpected exception, pages Sentry', () => {
    const cls = classifyPayoutStripeError('No such destination: acct_x');
    expect(cls).toBe('unexpected');
    expect(reasonCodeForErrorClass(cls)).toBe('PAYOUT_TRANSFER_FAILED');
    expect(shouldPageSentry(cls)).toBe(true);
  });
});

describe('payout eligibility — only money the platform verifiably holds', () => {
  it('succeeded + buyer_confirmed + clean → eligible', () => {
    expect(payoutEligibility(ELIGIBLE_BASE)).toEqual({ eligible: true });
  });

  it('auto_released transfers are also releasable (cron self-heal path)', () => {
    expect(payoutEligibility({ ...ELIGIBLE_BASE, transferStatus: 'auto_released' }))
      .toEqual({ eligible: true });
  });

  it('full refund before payout (DB flag) → PAYMENT_NOT_SUCCEEDED', () => {
    expect(payoutEligibility({ ...ELIGIBLE_BASE, paymentStatus: 'refunded' }))
      .toEqual({ eligible: false, reason: 'PAYMENT_NOT_SUCCEEDED' });
  });

  it('full refund before payout (Stripe truth, DB lagging) → CHARGE_REFUNDED', () => {
    expect(payoutEligibility({ ...ELIGIBLE_BASE, chargeRefunded: true }))
      .toEqual({ eligible: false, reason: 'CHARGE_REFUNDED' });
  });

  it('already-released payout (duplicate confirmation / duplicate cron) → ALREADY_RELEASED', () => {
    expect(payoutEligibility({ ...ELIGIBLE_BASE, payoutReleasedAt: '2026-08-04T18:00:00Z' }))
      .toEqual({ eligible: false, reason: 'ALREADY_RELEASED' });
  });

  it('disputed / chargeback state → DISPUTED, payout frozen', () => {
    expect(payoutEligibility({ ...ELIGIBLE_BASE, disputedAt: '2026-08-04T18:00:00Z' }))
      .toEqual({ eligible: false, reason: 'DISPUTED' });
  });

  it('pending / seller_sent / reversed transfers are never payable', () => {
    for (const transferStatus of ['pending', 'seller_sent', 'reversed', 'expired', 'disputed']) {
      const r = payoutEligibility({ ...ELIGIBLE_BASE, transferStatus });
      expect(r.eligible).toBe(false);
    }
  });
});

describe('transfer amount ceiling — never draw unrelated platform balance', () => {
  it('un-refunded charge: full charge amount is transferable', () => {
    expect(maxTransferableCents(220, 0)).toBe(220);
  });

  it('partial refund reduces the ceiling; a 180¢ seller net no longer fits after a 100¢ refund', () => {
    const cap = maxTransferableCents(220, 100);
    expect(cap).toBe(120);
    expect(180 <= cap).toBe(false);
  });

  it('full refund → ceiling 0, nothing transferable', () => {
    expect(maxTransferableCents(220, 220)).toBe(0);
  });

  it('over-refund edge (disputes) clamps at 0, never negative', () => {
    expect(maxTransferableCents(220, 500)).toBe(0);
  });
});

// ── Mode boundary (migration 045 + Sentry REACT-NATIVE-8) ────────────────────

describe('live/test mode boundary — automation acts on explicit live rows only', () => {
  it('live row is actionable (live PaymentIntent proceeds normally)', () => {
    expect(rowIsLiveActionable(true)).toBe(true);
  });

  it('test-era row is inert for refund/payout/reconciliation, preserved for audit', () => {
    expect(rowIsLiveActionable(false)).toBe(false);
  });

  it('unclassified row fails CLOSED — never actionable', () => {
    expect(rowIsLiveActionable(null)).toBe(false);
    expect(rowIsLiveActionable(undefined)).toBe(false);
  });

  it("recognizes Stripe's cross-mode signature (test object addressed with live key)", () => {
    expect(isCrossModeStripeError(
      "No such payment_intent: 'pi_3TN1LSGdOzCmGbHw02bMiDxP'; a similar object exists in test mode, but a live mode key was used to make this request.",
    )).toBe(true);
  });

  it('recognizes the mirrored variant (live object addressed with test key)', () => {
    expect(isCrossModeStripeError(
      "No such payment_intent: 'pi_x'; a similar object exists in live mode, but a test mode key was used to make this request.",
    )).toBe(true);
  });

  it('a genuinely missing LIVE PaymentIntent is NOT classified cross-mode — it must page', () => {
    expect(isCrossModeStripeError("No such payment_intent: 'pi_gone'")).toBe(false);
  });

  it('unrelated Stripe errors are not cross-mode', () => {
    expect(isCrossModeStripeError('Insufficient funds in Stripe account.')).toBe(false);
    expect(isCrossModeStripeError(
      'Your destination account needs to have at least one of the following capabilities enabled: transfers',
    )).toBe(false);
  });
});
