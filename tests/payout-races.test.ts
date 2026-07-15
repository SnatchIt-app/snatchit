/**
 * AUDIT 5 — deterministic simulation of the payout release protocol.
 *
 * WHAT THIS PROVES (and what it doesn't): Postgres and Stripe are separate
 * systems — there is NO cross-system atomicity, and these tests don't claim
 * any. Instead they verify the PROTOCOL the production code implements:
 *
 *   1. Claim/transition guards are atomic per-row in Postgres (FOR UPDATE /
 *      conditional UPDATE ... WHERE). Modeled here as serialized state
 *      transitions with the exact same predicates as migration 039 +
 *      confirm_transfer_received (migration 002).
 *   2. Every money-moving path uses the SAME Stripe Idempotency-Key,
 *      `payout_<transfer_id>` — so even when two paths reach Stripe, Stripe
 *      materializes ONE Transfer object.
 *   3. Recovery when Stripe succeeds but the DB write fails: nothing is
 *      recorded, the row stays claimed-but-unpaid, and the Phase 2b sweep
 *      retries with the same key — replay, not double-pay.
 *
 * Every interleaving asserted below must end with exactly ONE Stripe
 * Transfer and a consistent DB row.
 */
import { describe, expect, it } from 'vitest';

// ── Stripe mock with real idempotency-key semantics ─────────────────────────
class StripeMock {
  private byKey = new Map<string, { id: string }>();
  created = 0;
  /** timeoutAfterCreate: request "times out" client-side AFTER Stripe created the transfer. */
  createTransfer(idempotencyKey: string, opts: { timeoutAfterCreate?: boolean } = {}): { id: string } {
    let obj = this.byKey.get(idempotencyKey);
    if (!obj) {
      obj = { id: `tr_${this.created + 1}` };
      this.byKey.set(idempotencyKey, obj);
      this.created += 1;
    }
    if (opts.timeoutAfterCreate) throw new Error('network timeout');
    return obj;
  }
}

// ── Transfer row + the exact production guards ──────────────────────────────
interface Row {
  status: 'pending' | 'seller_sent' | 'buyer_confirmed' | 'auto_released' | 'disputed';
  payout_released_at: string | null;
  stripe_transfer_id: string | null;
  disputed_at: string | null;
  payout_review_status: 'held' | 'manual_review' | null;
}

const freshRow = (): Row => ({
  status: 'seller_sent',
  payout_released_at: null,
  stripe_transfer_id: null,
  disputed_at: null,
  payout_review_status: null,
});

// migration 039 apply_auto_release(): WHERE status='seller_sent' AND
// payout_released_at IS NULL AND review IS DISTINCT FROM 'manual_review'
function applyAutoRelease(row: Row): boolean {
  if (row.status !== 'seller_sent' || row.payout_released_at !== null ||
      row.payout_review_status === 'manual_review') return false;
  row.status = 'auto_released';
  row.payout_review_status = null;
  return true;
}

// migration 002 confirm_transfer_received(): seller_sent → buyer_confirmed
function confirmTransferReceived(row: Row): boolean {
  if (row.status === 'buyer_confirmed') return true; // tolerated (idempotent)
  if (row.status !== 'seller_sent') return false;
  row.status = 'buyer_confirmed';
  return true;
}

// migration 039 admin_release_held_payout(): seller_sent + unpaid only
function adminRelease(row: Row): boolean {
  if (row.status !== 'seller_sent' || row.payout_released_at !== null) return false;
  row.status = 'auto_released';
  row.payout_review_status = null;
  return true;
}

// The shared money-mover (payReleasedTransfer / confirm-and-release step 8+):
// final dispute recheck → Stripe with payout_<id> key → conditional persist.
function payOut(
  row: Row,
  stripe: StripeMock,
  transferId: string,
  opts: { allowedStatuses: Row['status'][]; dbWriteFails?: boolean; stripeTimesOut?: boolean } ,
): 'paid' | 'aborted' | 'stripe-error' | 'db-write-failed' {
  // pre-payment recheck (as close to the money as possible)
  if (row.stripe_transfer_id) return 'paid'; // already done
  if (row.disputed_at !== null || !opts.allowedStatuses.includes(row.status)) return 'aborted';

  let tr: { id: string };
  try {
    tr = stripe.createTransfer(`payout_${transferId}`, { timeoutAfterCreate: opts.stripeTimesOut });
  } catch {
    return 'stripe-error'; // nothing persisted; retry later replays the key
  }

  if (opts.dbWriteFails) return 'db-write-failed'; // Stripe moved money; row still unpaid

  // atomic conditional persist (UPDATE ... WHERE stripe_transfer_id IS NULL)
  if (row.stripe_transfer_id === null) {
    row.stripe_transfer_id = tr.id;
    row.payout_released_at = 'now';
  }
  return 'paid';
}

const CRON = { allowedStatuses: ['auto_released', 'buyer_confirmed'] as Row['status'][] };
const BUYER = { allowedStatuses: ['buyer_confirmed'] as Row['status'][] };

describe('payout race simulations (protocol model)', () => {
  it('cron claim vs buyer confirmation — cron wins the row: buyer path cannot pay twice', () => {
    const row = freshRow(); const stripe = new StripeMock();
    expect(applyAutoRelease(row)).toBe(true);          // cron claims (row lock)
    expect(confirmTransferReceived(row)).toBe(false);  // buyer RPC loses: not seller_sent
    payOut(row, stripe, 't1', CRON);
    expect(stripe.created).toBe(1);
    expect(row.stripe_transfer_id).toBe('tr_1');
  });

  it('cron claim vs buyer confirmation — buyer wins the row: cron cannot claim', () => {
    const row = freshRow(); const stripe = new StripeMock();
    expect(confirmTransferReceived(row)).toBe(true);   // buyer confirms first
    expect(applyAutoRelease(row)).toBe(false);         // cron claim fails
    payOut(row, stripe, 't1', BUYER);
    expect(stripe.created).toBe(1);
  });

  it('both paths somehow reach Stripe → idempotency key still yields ONE transfer', () => {
    // Even if a future refactor broke the state machine, the shared
    // payout_<id> key is the last line of defense.
    const row = freshRow(); const stripe = new StripeMock();
    stripe.createTransfer('payout_t1');                // path A hits Stripe
    stripe.createTransfer('payout_t1');                // path B hits Stripe
    expect(stripe.created).toBe(1);
    payOut(row, stripe, 't1', BUYER);                  // aborted (still seller_sent)
    expect(stripe.created).toBe(1);
  });

  it('cron vs admin release racing — one claim wins, one payout', () => {
    const row = freshRow(); const stripe = new StripeMock();
    expect(applyAutoRelease(row)).toBe(true);
    expect(adminRelease(row)).toBe(false);             // admin loses: not seller_sent
    payOut(row, stripe, 't1', CRON);
    payOut(row, stripe, 't1', CRON);                   // 2b sweep sees it again
    expect(stripe.created).toBe(1);
  });

  it('Stripe succeeds, DB write fails → 2b sweep replays the key, no double pay', () => {
    const row = freshRow(); const stripe = new StripeMock();
    applyAutoRelease(row);
    expect(payOut(row, stripe, 't1', { ...CRON, dbWriteFails: true })).toBe('db-write-failed');
    expect(row.stripe_transfer_id).toBeNull();         // honest: DB doesn't know yet
    expect(stripe.created).toBe(1);                    // money DID move once
    // next cron run, Phase 2b picks up the auto_released+unpaid row:
    expect(payOut(row, stripe, 't1', CRON)).toBe('paid');
    expect(stripe.created).toBe(1);                    // replay, not a second transfer
    expect(row.stripe_transfer_id).toBe('tr_1');
  });

  it('duplicate function invocation (two overlapping crons) → one transfer', () => {
    const row = freshRow(); const stripe = new StripeMock();
    const claimA = applyAutoRelease(row);
    const claimB = applyAutoRelease(row);              // second invocation
    expect([claimA, claimB].filter(Boolean)).toHaveLength(1);
    if (claimA) payOut(row, stripe, 't1', CRON);
    if (claimB) payOut(row, stripe, 't1', CRON);
    payOut(row, stripe, 't1', CRON);                   // both also sweep in 2b
    expect(stripe.created).toBe(1);
  });

  it('retry after a network timeout where Stripe DID create the transfer → one transfer', () => {
    const row = freshRow(); const stripe = new StripeMock();
    applyAutoRelease(row);
    expect(payOut(row, stripe, 't1', { ...CRON, stripeTimesOut: true })).toBe('stripe-error');
    expect(row.stripe_transfer_id).toBeNull();
    expect(stripe.created).toBe(1);                    // created despite the timeout
    expect(payOut(row, stripe, 't1', CRON)).toBe('paid'); // retry replays the key
    expect(stripe.created).toBe(1);
    expect(row.stripe_transfer_id).toBe('tr_1');
  });

  it('a dispute arriving between claim and payment freezes the money', () => {
    const row = freshRow(); const stripe = new StripeMock();
    applyAutoRelease(row);
    row.status = 'disputed'; row.disputed_at = 'now';  // chargeback webhook fires
    expect(payOut(row, stripe, 't1', CRON)).toBe('aborted');
    expect(stripe.created).toBe(0);
  });

  it('a dispute before the buyer-confirm payment aborts it too', () => {
    const row = freshRow(); const stripe = new StripeMock();
    confirmTransferReceived(row);
    row.disputed_at = 'now';                           // dispute recorded mid-flight
    expect(payOut(row, stripe, 't1', BUYER)).toBe('aborted');
    expect(stripe.created).toBe(0);
  });
});
