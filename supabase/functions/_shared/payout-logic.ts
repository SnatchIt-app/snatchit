/**
 * _shared/payout-logic.ts — pure, dependency-free payout decision logic.
 *
 * Everything here is deterministic data-in/data-out so the vitest suite can
 * exercise it directly (Deno edge modules with https imports can't be loaded
 * by vitest; this file must stay import-free). The I/O shell around it lives
 * in _shared/payouts.ts.
 */

/**
 * Deterministic Stripe Idempotency-Key for ONE payout attempt.
 *
 * `payout_<transferId>_a<attemptNo>`
 *   • the key belongs to the attempt row in public.payout_attempts, whose
 *     request parameters (destination, amount, currency) are frozen at claim
 *     time — so any replay of this key carries byte-identical parameters
 *     from every caller (confirm-and-release, the cron sweep, recovery);
 *   • a new attempt (new number, new key) opens ONLY after the previous one
 *     is terminal (succeeded / failed / reversal_required), and only after an
 *     open attempt was reconciled against Stripe (list by transfer_group) —
 *     that, not the key, is what prevents a second real transfer once
 *     Stripe forgets the key after 24h (F08);
 *   • the `_a<n>` suffix keeps the space disjoint from every earlier
 *     generation (`payout_<id>`, `..._r1`, `..._ready`, `..._<acct>_src`).
 * No randomness: every key is reconstructible from audit data.
 */
export function buildPayoutIdempotencyKey(transferId: string, attemptNo: number): string {
  if (!Number.isInteger(attemptNo) || attemptNo < 1) {
    throw new Error(`buildPayoutIdempotencyKey: attemptNo must be a positive integer (got ${attemptNo})`);
  }
  return `payout_${transferId}_a${attemptNo}`;
}

/**
 * What a failed POST /v1/transfers means for the attempt ledger.
 *
 *   failed_not_created — Stripe DEFINITELY did not create a transfer: a
 *                        4xx that is not an idempotency/in-flight signal.
 *                        The attempt closes; a fresh attempt may open later.
 *   unknown            — a transfer MAY exist: network error (no status),
 *                        5xx, 409 (idempotency key in flight elsewhere),
 *                        429, or `idempotency_error` (key reused with other
 *                        parameters — the ORIGINAL transfer under that key
 *                        exists). The attempt stays open under its lease
 *                        and is reconciled by listing transfer_group before
 *                        any new POST.
 */
export type PayoutPostOutcome = 'failed_not_created' | 'unknown';

export function classifyPayoutPostFailure(
  status: number | null,
  error: { type?: string; code?: string; message?: string } | null | undefined,
): PayoutPostOutcome {
  if (status === null || status === undefined) return 'unknown';
  if (status >= 500) return 'unknown';
  if (status === 409 || status === 429) return 'unknown';
  if (error?.type === 'idempotency_error') return 'unknown';
  if (status >= 400) return 'failed_not_created';
  return 'unknown';
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

/**
 * Stripe's signature for addressing an object with the wrong-mode key
 * ("No such payment_intent: 'pi_…'; a similar object exists in test mode,
 * but a live mode key was used…" — and the mirrored live/test variant).
 * A row that produces this while marked live is a data-integrity incident:
 * quarantine it (stripe_livemode = false), never silently continue.
 */
export function isCrossModeStripeError(message: string): boolean {
  return /similar object exists in (test|live) mode/i.test(message);
}

/**
 * The mode boundary for financial automation: only rows explicitly marked
 * live (payments.stripe_livemode = true) may enter refund/payout/
 * reconciliation paths. false = preserved-but-inert test-era audit data;
 * null = unclassified and therefore NOT actionable (fail closed).
 */
export function rowIsLiveActionable(stripeLivemode: boolean | null | undefined): boolean {
  return stripeLivemode === true || (stripeLivemode === false && allowTestModeMoney());
}

/**
 * Sandbox-only switch. `ALLOW_TEST_MODE_MONEY=1` in an isolated test project's
 * edge secrets admits stripe_livemode = false rows into the money rails so a
 * Stripe TEST key can exercise real Connect test transfers end to end. It is
 * never set in production (release checklist asserts its absence); NULL
 * (unclassified) rows are never admitted by anyone. The database twin is the
 * GUC app.allow_test_mode_money (ALTER DATABASE on the sandbox only).
 */
export function allowTestModeMoney(): boolean {
  try {
    // deno-lint-ignore no-explicit-any
    const d = (globalThis as any).Deno;
    return !!d?.env?.get && d.env.get('ALLOW_TEST_MODE_MONEY') === '1';
  } catch {
    return false;
  }
}
