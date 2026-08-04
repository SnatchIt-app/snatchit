/**
 * _shared/payout-logic.ts — pure, dependency-free payout decision logic.
 *
 * Everything here is deterministic data-in/data-out so the vitest suite can
 * exercise it directly (Deno edge modules with https imports can't be loaded
 * by vitest; this file must stay import-free). The I/O shell around it lives
 * in _shared/payouts.ts.
 */

/**
 * Deterministic Stripe Idempotency-Key for one logical seller payout.
 *
 * `payout_<transferId>_<destination>_src`
 *   • same logical payout (same transfer row, same connected account) →
 *     same key from every caller, so races and retries replay ONE Stripe
 *     Transfer — never two;
 *   • destination change (seller re-onboarded) → new key → genuinely new
 *     attempt instead of a stale 24h replay;
 *   • `_src` marks the source_transaction request generation, keeping it
 *     disjoint from keys burned by earlier code (`payout_<id>`,
 *     `..._r1`, `..._ready`) whose parameters differ.
 * No randomness: every key is reconstructible from audit data.
 */
export function buildPayoutIdempotencyKey(transferId: string, destination: string): string {
  return `payout_${transferId}_${destination}_src`;
}

/**
 * Classify a Stripe /transfers error so expected operational states are
 * recorded as payout decisions instead of paging as production exceptions.
 */
export type PayoutErrorClass =
  | 'insufficient_funds'      // platform available balance can't fund it (expected pre-source_transaction)
  | 'destination_capability'  // connected account can't receive transfers yet
  | 'idempotency_params'      // key reused with different parameters — a CODE BUG
  | 'unexpected';             // anything else — real exception, page it

export function classifyPayoutStripeError(message: string): PayoutErrorClass {
  const m = message.toLowerCase();
  if (m.includes('insufficient funds')) return 'insufficient_funds';
  if (m.includes('capabilities enabled') || m.includes('capability')) return 'destination_capability';
  if (m.includes('idempotent') && m.includes('parameters')) return 'idempotency_params';
  return 'unexpected';
}

/** Reason codes recorded in payout_decisions for each class. */
export function reasonCodeForErrorClass(cls: PayoutErrorClass): string {
  switch (cls) {
    case 'insufficient_funds':     return 'PAYOUT_INSUFFICIENT_FUNDS';
    case 'destination_capability': return 'PAYOUT_DESTINATION_NOT_READY';
    case 'idempotency_params':     return 'PAYOUT_IDEMPOTENCY_BUG';
    case 'unexpected':             return 'PAYOUT_TRANSFER_FAILED';
  }
}

/** Only these error classes go to Sentry; the rest are operational states. */
export function shouldPageSentry(cls: PayoutErrorClass): boolean {
  return cls === 'unexpected' || cls === 'idempotency_params';
}

export interface PayoutEligibilityInput {
  paymentStatus:    string;        // payments.status
  transferStatus:   string;        // transfers.status
  disputedAt:       string | null;
  payoutReleasedAt: string | null;
  chargeRefunded:   boolean;       // Stripe charge.refunded (full refund)
}

export type PayoutEligibility =
  | { eligible: true }
  | { eligible: false; reason: string };

/**
 * A payout may be attempted ONLY for money the platform verifiably holds:
 * payment succeeded (DB) AND charge not fully refunded (Stripe truth),
 * transfer in a releasable state, not disputed, not already paid.
 */
export function payoutEligibility(i: PayoutEligibilityInput): PayoutEligibility {
  if (i.payoutReleasedAt !== null)      return { eligible: false, reason: 'ALREADY_RELEASED' };
  if (i.disputedAt !== null)            return { eligible: false, reason: 'DISPUTED' };
  if (i.paymentStatus !== 'succeeded')  return { eligible: false, reason: 'PAYMENT_NOT_SUCCEEDED' };
  if (i.chargeRefunded)                 return { eligible: false, reason: 'CHARGE_REFUNDED' };
  if (!['buyer_confirmed', 'auto_released'].includes(i.transferStatus)) {
    return { eligible: false, reason: `TRANSFER_STATUS_${i.transferStatus.toUpperCase()}` };
  }
  return { eligible: true };
}

/**
 * Ceiling for a source_transaction transfer: the charge's un-refunded
 * remainder. Stripe enforces amount ≤ charge amount; we additionally cap by
 * partial refunds so a partially-refunded order can never over-pay the
 * seller from unrelated platform balance.
 */
export function maxTransferableCents(chargeAmountCents: number, amountRefundedCents: number): number {
  return Math.max(0, chargeAmountCents - amountRefundedCents);
}
