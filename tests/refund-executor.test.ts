/**
 * E4 — the refund executor (owner ruling D3).
 *
 * WHAT THIS PROVES, AND WHAT IT DOES NOT
 *   Postgres and Stripe are separate systems; there is no cross-system
 *   atomicity and nothing here claims any. These tests verify (a) the pure
 *   decision logic in `refund-execute/executor.ts` exactly, and (b) the
 *   PROTOCOL the edge implements, simulated against a Stripe mock with real
 *   idempotency-key semantics and a `kernel.mark_refund_state` mock that
 *   reproduces 085:1737-1789 line for line (forward-only, write-once ref,
 *   noop-replay, mandatory failure_code) plus registry 199's one addition, the
 *   Stripe-truth guard on `succeeded` (DESIGN-199-FINAL §3.2).
 *
 * CASES THAT CANNOT BE UNIT-TESTED WITHOUT A LIVE DB are called out inline and
 * are written as pure-logic tests against the extracted helper instead:
 *   • the support cumulative cap (085:549-563), the Σ-guard under the payment
 *     lock (085:545) and the delegated-key single-use property
 *     (`refund_idempotency_uq`) are enforced INSIDE `kernel.refund_primary_order`
 *     and are unreachable from TypeScript. What is testable here is the
 *     executor's own re-check of headroom, which is what protects the window
 *     between recording the intent and executing it.
 *   • "wrong venue" has no edge-reachable surface at all — a refund is
 *     payment-scoped and no venue id is a parameter anywhere in the executor.
 *     The test asserts that absence rather than simulating a check.
 */
import { describe, expect, it } from 'vitest';
import {
  assertNoClientPaymentReference,
  buildRefundIdempotencyKey,
  classifyArm,
  classifyStateSyncError,
  classifyStripeRefundError,
  executorHoldOf,
  httpStatusForRpcError,
  isMoneyDenial,
  isUuid,
  planRefund,
  planStateSync,
  planClaimedBatch,
  planPark,
  planReconcile,
  type ClaimedRefund,
  type RefundExecutionContext,
} from '../supabase/functions/refund-execute/executor';

// ── fixtures ────────────────────────────────────────────────────────────────

const REFUND = '11111111-1111-4111-8111-111111111111';
const REFUND_2 = '22222222-2222-4222-8222-222222222222';
const PAYMENT = '33333333-3333-4333-8333-333333333333';
const ORDER = '44444444-4444-4444-8444-444444444444';
const OTHER_ORDER = '55555555-5555-4555-8555-555555555555';
const SALE = '66666666-6666-4666-8666-666666666666';

function ctx(over: Partial<RefundExecutionContext> = {}): RefundExecutionContext {
  return {
    refund_id: REFUND,
    payment_id: PAYMENT,
    order_id: ORDER,
    sale_id: null,
    amount_minor: 11000,
    currency: 'USD',
    reason_code: 'buyer_request',
    status: 'pending',
    stripe_refund_ref: null,
    payment_total_minor: 11000,
    payment_status: 'succeeded',
    stripe_payment_intent_id: 'pi_3QabcDEF',
    stripe_livemode: true,
    prior_non_failed_minor: 0,
    disputed_minor: 0,
    ...over,
  };
}

// ── Stripe mock with REAL idempotency-key semantics ─────────────────────────

interface StripeRefundObj { id: string; status: string; failure_reason?: string; amount: number; payment_intent: string }

class StripeMock {
  private byKey = new Map<string, { obj: StripeRefundObj; body: string }>();
  /** How many distinct Refund objects were actually created. */
  created = 0;
  /** Every request, including replays. */
  calls = 0;
  /** Per-PaymentIntent total actually refunded. The double-refund detector. */
  refundedByPi = new Map<string, number>();

  constructor(private readonly nextStatus: () => string = () => 'succeeded') {}

  create(
    idempotencyKey: string,
    body: Record<string, string>,
    opts: { transportFailureAfterCreate?: boolean; error?: { status: number; code: string } } = {},
  ): StripeRefundObj {
    this.calls += 1;
    if (opts.error) {
      const e = new Error(opts.error.code) as Error & { __stripe: { status: number; error: { code: string } } };
      e.__stripe = { status: opts.error.status, error: { code: opts.error.code } };
      throw e;
    }
    const serialized = JSON.stringify(body);
    const existing = this.byKey.get(idempotencyKey);
    if (existing) {
      if (existing.body !== serialized) {
        const e = new Error('idempotency_error') as Error & { __stripe: { status: number; error: { code: string } } };
        e.__stripe = { status: 400, error: { code: 'idempotency_error' } };
        throw e;
      }
      // Stripe returns the ORIGINAL object. No new money moves.
      if (opts.transportFailureAfterCreate) throw new Error('network timeout');
      return existing.obj;
    }
    const pi = body['payment_intent'];
    const amount = Number(body['amount']);
    const obj: StripeRefundObj = {
      id: `re_${this.created + 1}`,
      status: this.nextStatus(),
      amount,
      payment_intent: pi,
    };
    this.byKey.set(idempotencyKey, { obj, body: serialized });
    this.created += 1;
    this.refundedByPi.set(pi, (this.refundedByPi.get(pi) ?? 0) + amount);
    if (opts.transportFailureAfterCreate) throw new Error('network timeout');
    return obj;
  }
}

// ── kernel.refund + mark_refund_state mock (085:74-95, 085:1737-1789, 199 §3.2) ──

interface RefundRow {
  refund_id: string;
  payment_id: string;
  amount_minor: number;
  status: 'pending' | 'submitted' | 'succeeded' | 'failed';
  stripe_refund_ref: string | null;
  idempotency_key: string;
}

class KernelMock {
  rows = new Map<string, RefundRow>();
  /** Set true to make the next mark_refund_state call fail (DB outage). */
  failNextStateSync = false;
  /**
   * `public.payment_refund_state.status` by `stripe_refund_id` (150): what the
   * webhook has RECORDED Stripe saying about a ref. 199 §3.2's guard reads it.
   */
  stripeState = new Map<string, string>();

  insertRefund(row: RefundRow) {
    // `refund_idempotency_uq` (085:92): the delegated key is single-use.
    for (const r of this.rows.values()) {
      if (r.idempotency_key === row.idempotency_key) {
        return { status: 'idempotency_replay', refund_id: r.refund_id };
      }
    }
    this.rows.set(row.refund_id, { ...row });
    return { status: 'ok', refund_id: row.refund_id };
  }

  /**
   * Faithful port of kernel.mark_refund_state (085:1737-1789) as registry 199
   * replaces it (DESIGN-199-FINAL §3.2, G1): 085's body byte for byte plus ONE
   * check, the Stripe-truth guard, placed after the failure-code check and
   * before the write. The order is otherwise unchanged (noop → direction → ref
   * mandatory → write-once → failure code → guard), so refund_state_backwards
   * still reaches classifyStateSyncError as `converged`.
   */
  markRefundState(
    refundId: string,
    newStatus: 'submitted' | 'succeeded' | 'failed',
    ref: string | null,
    failureCode: string | null,
  ): { status: string } {
    if (this.failNextStateSync) {
      this.failNextStateSync = false;
      throw new Error('57P01: terminating connection due to administrator command');
    }
    const row = this.rows.get(refundId);
    if (!row) throw new Error(`not_found: refund ${refundId}`);
    if (row.status === newStatus && (ref === null || row.stripe_refund_ref === ref)) {
      return { status: 'noop_replay' };
    }
    const forward =
      (row.status === 'pending' && newStatus === 'submitted') ||
      (row.status === 'submitted' && (newStatus === 'succeeded' || newStatus === 'failed'));
    if (!forward) throw new Error(`precondition_failed: refund_state_backwards (${row.status} → ${newStatus})`);
    if (ref === null) throw new Error('invalid_input: stripe_refund_ref is mandatory');
    if (row.stripe_refund_ref !== null && row.stripe_refund_ref !== ref) {
      throw new Error('conflict_locked: stripe_refund_ref is write-once');
    }
    if (newStatus === 'failed' && !failureCode) throw new Error('invalid_input: failure_code is mandatory for failed');
    // 199 §3.2 (I-R1): never succeeded for a ref Stripe has recorded failed or
    // canceled. SQL keys on p_stripe_refund_ref; write-once above makes it the row's.
    if (newStatus === 'succeeded') {
      const stripe = this.stripeState.get(ref);
      if (stripe === 'failed' || stripe === 'canceled') {
        throw new Error(`precondition_failed: refund_failed_at_stripe (${ref} is ${stripe})`);
      }
    }
    row.status = newStatus;
    row.stripe_refund_ref = row.stripe_refund_ref ?? ref;
    return { status: 'ok' };
  }
}

/**
 * The edge's money leg, exactly as `index.ts` sequences it: plan → Stripe →
 * mark_refund_state. Returns what the edge returns.
 */
function runExecutor(
  kernel: KernelMock,
  stripe: StripeMock,
  context: RefundExecutionContext,
  opts: { expectedOrderId?: string | null; transportFailureAfterCreate?: boolean; stripeError?: { status: number; code: string } } = {},
): { outcome: string; code?: string; ref?: string | null } {
  const plan = planRefund(context, { order_id: opts.expectedOrderId ?? null });
  if (plan.kind === 'refuse') return { outcome: 'refused', code: plan.code };
  if (plan.kind === 'noop_replay') return { outcome: 'noop_replay', code: plan.reason, ref: plan.stripe_refund_ref };

  let obj: StripeRefundObj;
  try {
    obj = stripe.create(plan.idempotency_key, plan.body, {
      transportFailureAfterCreate: opts.transportFailureAfterCreate,
      error: opts.stripeError,
    });
  } catch (err) {
    const tagged = err as Error & { __stripe?: { status: number; error: { code: string } } };
    const verdict = tagged.__stripe
      ? classifyStripeRefundError(tagged.__stripe)
      : classifyStripeRefundError(tagged);
    // THE CREATE-ERROR RULE: no `re_…` exists, so NOTHING is written.
    expect(verdict.writesState).toBe(false);
    return { outcome: 'stripe_error', code: verdict.class };
  }

  const sync = planStateSync(obj);
  if (sync.kind === 'refuse') return { outcome: 'state_sync_deferred', code: sync.code };
  let last = 'state_sync_deferred';
  for (const step of sync.steps) {
    try {
      kernel.markRefundState(context.refund_id, step.new_status, step.stripe_refund_ref, step.failure_code);
      last = step.new_status;
    } catch (err) {
      const verdict = classifyStateSyncError((err as Error).message);
      if (verdict.kind === 'converged') {
        return { outcome: 'noop_replay', code: 'converged_elsewhere', ref: obj.id };
      }
      return {
        outcome: 'state_sync_deferred',
        code: verdict.kind === 'conflict' ? 'state_sync_conflict' : 'mark_refund_state_failed',
        ref: obj.id,
      };
    }
  }
  return { outcome: last, ref: obj.id };
}

/** Re-read the DB row into a fresh execution context, as a later sweep would. */
function reload(kernel: KernelMock, base: RefundExecutionContext): RefundExecutionContext {
  const row = kernel.rows.get(base.refund_id)!;
  return { ...base, status: row.status, stripe_refund_ref: row.stripe_refund_ref, amount_minor: row.amount_minor };
}

function seed(kernel: KernelMock, c: RefundExecutionContext, key = `k:${c.refund_id}`) {
  kernel.insertRefund({
    refund_id: c.refund_id,
    payment_id: c.payment_id,
    amount_minor: c.amount_minor,
    status: 'pending',
    stripe_refund_ref: null,
    idempotency_key: key,
  });
}

// ════════════════════════════════════════════════════════════════════════════
// 1. The Stripe idempotency key
// ════════════════════════════════════════════════════════════════════════════

describe('Stripe idempotency key — derived from the refund id, never the request', () => {
  it('is refund_<refund_id>, per EDGE_FUNCTION_SPEC:559-560', () => {
    expect(buildRefundIdempotencyKey(REFUND)).toBe(`refund_${REFUND}`);
  });

  it('is stable across independent workers with no shared state', () => {
    expect(buildRefundIdempotencyKey(REFUND)).toBe(buildRefundIdempotencyKey(REFUND));
  });

  it('is distinct per refund row, so two refunds on one payment never collide', () => {
    expect(buildRefundIdempotencyKey(REFUND)).not.toBe(buildRefundIdempotencyKey(REFUND_2));
  });

  it('refuses to be built from anything that is not a uuid', () => {
    expect(() => buildRefundIdempotencyKey('order-123')).toThrow(/non-uuid/);
    expect(() => buildRefundIdempotencyKey('00000000-0000-0000-0000-000000000000')).toThrow(/non-uuid/);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 2. THE PROPERTY THAT MATTERS MOST — it cannot refund the wrong payment/order
// ════════════════════════════════════════════════════════════════════════════

describe('binding — incapable of refunding the wrong payment or order', () => {
  it('refuses a request that tries to name the payment at all', () => {
    for (const key of ['payment_id', 'payment_intent', 'stripe_payment_intent_id', 'charge', 'stripe_refund_id']) {
      const r = assertNoClientPaymentReference({ action: 'execute', refund_id: REFUND, [key]: 'pi_evil' });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.code).toBe('client_supplied_payment_reference');
    }
  });

  it('accepts a request that names only the refund and the caller assertion', () => {
    expect(assertNoClientPaymentReference({ action: 'execute', refund_id: REFUND, expected_order_id: ORDER }).ok).toBe(true);
  });

  it('a null-valued forbidden key is not treated as a smuggled reference', () => {
    expect(assertNoClientPaymentReference({ refund_id: REFUND, payment_id: null }).ok).toBe(true);
  });

  it('refuses when the caller asserts a DIFFERENT order than the refund binds to', () => {
    const plan = planRefund(ctx(), { order_id: OTHER_ORDER });
    expect(plan.kind).toBe('refuse');
    if (plan.kind === 'refuse') expect(plan.code).toBe('binding_order_mismatch');
  });

  it('proceeds when the caller assertion matches the DB binding', () => {
    expect(planRefund(ctx(), { order_id: ORDER }).kind).toBe('stripe_create');
  });

  it('proceeds when the caller asserts nothing (the binding is DB-derived either way)', () => {
    expect(planRefund(ctx(), {}).kind).toBe('stripe_create');
  });

  it('refuses when the payment_native XOR does not hold — both subjects', () => {
    const plan = planRefund(ctx({ sale_id: SALE }));
    expect(plan.kind).toBe('refuse');
    if (plan.kind === 'refuse') expect(plan.code).toBe('binding_subject_ambiguous');
  });

  it('refuses when the payment_native XOR does not hold — neither subject', () => {
    const plan = planRefund(ctx({ order_id: null, sale_id: null }));
    expect(plan.kind).toBe('refuse');
    if (plan.kind === 'refuse') expect(plan.code).toBe('binding_subject_ambiguous');
  });

  it('sends the PaymentIntent that came from the refund row, and no other', () => {
    const plan = planRefund(ctx({ stripe_payment_intent_id: 'pi_bound' }));
    expect(plan.kind).toBe('stripe_create');
    if (plan.kind === 'stripe_create') {
      expect(plan.body['payment_intent']).toBe('pi_bound');
      expect(plan.body['metadata[refund_id]']).toBe(REFUND);
      expect(plan.body['metadata[payment_id]']).toBe(PAYMENT);
      expect(plan.body['metadata[order_id]']).toBe(ORDER);
      expect(plan.body['metadata[source]']).toBe('refund-execute');
    }
  });

  it('refuses a malformed PaymentIntent rather than shipping it to Stripe', () => {
    for (const bad of ['ch_123', 'pi', 'seti_123', '']) {
      const plan = planRefund(ctx({ stripe_payment_intent_id: bad }));
      expect(plan.kind).toBe('refuse');
    }
  });

  it('WRONG VENUE: the executor takes no venue parameter anywhere — a refund is payment-scoped', () => {
    // There is nothing to simulate: no venue/org id reaches Stripe or the
    // context. Org authority lives in the RPCs (`admin_refund` role checks,
    // `refund_primary_order`'s platform/delegated arms), never here. This test
    // pins that absence so a future refactor cannot quietly add one.
    const plan = planRefund(ctx());
    expect(plan.kind).toBe('stripe_create');
    if (plan.kind === 'stripe_create') {
      const keys = Object.keys(plan.body).join(',');
      expect(keys).not.toMatch(/venue|org/i);
    }
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 3. Full and partial refunds
// ════════════════════════════════════════════════════════════════════════════

describe('full refund', () => {
  it('moves the full amount once and lands succeeded', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx({ amount_minor: 11000, payment_total_minor: 11000 });
    seed(kernel, c);
    const r = runExecutor(kernel, stripe, c);
    expect(r.outcome).toBe('succeeded');
    expect(stripe.created).toBe(1);
    expect(stripe.refundedByPi.get('pi_3QabcDEF')).toBe(11000);
    expect(kernel.rows.get(REFUND)!.status).toBe('succeeded');
    expect(kernel.rows.get(REFUND)!.stripe_refund_ref).toBe('re_1');
  });
});

describe('partial refund', () => {
  it('sends exactly the row amount, not the payment total', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx({ amount_minor: 4000, payment_total_minor: 11000 });
    seed(kernel, c);
    runExecutor(kernel, stripe, c);
    expect(stripe.refundedByPi.get('pi_3QabcDEF')).toBe(4000);
  });

  it('a second partial refund on the same payment is a DIFFERENT row and a DIFFERENT key', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const first = ctx({ refund_id: REFUND, amount_minor: 4000, payment_total_minor: 11000 });
    seed(kernel, first, 'k:first');
    runExecutor(kernel, stripe, first);

    const second = ctx({ refund_id: REFUND_2, amount_minor: 3000, payment_total_minor: 11000, prior_non_failed_minor: 4000 });
    seed(kernel, second, 'k:second');
    runExecutor(kernel, stripe, second);

    expect(stripe.created).toBe(2);
    expect(stripe.refundedByPi.get('pi_3QabcDEF')).toBe(7000);
  });

  it('refuses the partial that would breach the payment total (the Σ-guard, re-checked)', () => {
    const plan = planRefund(ctx({ amount_minor: 8000, payment_total_minor: 11000, prior_non_failed_minor: 4000 }));
    expect(plan.kind).toBe('refuse');
    if (plan.kind === 'refuse') expect(plan.code).toBe('amount_exceeds_headroom');
  });

  it('refuses an amount larger than the payment itself', () => {
    const plan = planRefund(ctx({ amount_minor: 20000, payment_total_minor: 11000 }));
    expect(plan.kind).toBe('refuse');
    if (plan.kind === 'refuse') expect(plan.code).toBe('amount_exceeds_payment_total');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 4. Duplicate request / replay
// ════════════════════════════════════════════════════════════════════════════

describe('duplicate request', () => {
  it('a repeated record with the same command key returns the SAME refund id (085:484-487)', () => {
    const kernel = new KernelMock();
    const a = kernel.insertRefund({ refund_id: REFUND, payment_id: PAYMENT, amount_minor: 11000, status: 'pending', stripe_refund_ref: null, idempotency_key: 'req:abc' });
    const b = kernel.insertRefund({ refund_id: REFUND_2, payment_id: PAYMENT, amount_minor: 11000, status: 'pending', stripe_refund_ref: null, idempotency_key: 'req:abc' });
    expect(a.status).toBe('ok');
    expect(b.status).toBe('idempotency_replay');
    expect(b.refund_id).toBe(REFUND);
    expect(kernel.rows.size).toBe(1);
  });

  it('a re-delivered execute job is an application-level no-op', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);
    expect(runExecutor(kernel, stripe, c).outcome).toBe('succeeded');

    // Re-delivery: the worker reloads the row and sees a terminal state.
    const replayed = runExecutor(kernel, stripe, reload(kernel, c));
    expect(replayed.outcome).toBe('noop_replay');
    expect(replayed.code).toBe('already_succeeded');
    expect(stripe.calls).toBe(1); // Stripe was never even contacted again
    expect(stripe.created).toBe(1);
  });

  it('a row already at submitted is a no-op, not a second Stripe call', () => {
    const plan = planRefund(ctx({ status: 'submitted', stripe_refund_ref: 're_1' }));
    expect(plan.kind).toBe('noop_replay');
    if (plan.kind === 'noop_replay') expect(plan.reason).toBe('already_submitted');
  });

  it('a row already at failed is a no-op — it is terminal, never retried into a second refund', () => {
    const plan = planRefund(ctx({ status: 'failed', stripe_refund_ref: 're_1' }));
    expect(plan.kind).toBe('noop_replay');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 5. Stripe timeout — money moved, the response was lost
// ════════════════════════════════════════════════════════════════════════════

describe('Stripe timeout (created server-side, response lost)', () => {
  it('leaves the row pending, then the sweep replays the SAME key and converges', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);

    // Attempt 1: Stripe creates the refund, the client never sees the answer.
    const first = runExecutor(kernel, stripe, c, { transportFailureAfterCreate: true });
    expect(first.outcome).toBe('stripe_error');
    expect(first.code).toBe('network');
    expect(kernel.rows.get(REFUND)!.status).toBe('pending'); // NOTHING was written
    expect(stripe.created).toBe(1);                          // but money DID move

    // Attempt 2 (the sweep): same key → Stripe returns the ORIGINAL object.
    const second = runExecutor(kernel, stripe, reload(kernel, c));
    expect(second.outcome).toBe('succeeded');
    expect(second.ref).toBe('re_1');
    expect(stripe.created).toBe(1);                          // still ONE refund
    expect(stripe.refundedByPi.get('pi_3QabcDEF')).toBe(11000);
  });

  it('a transport failure never writes state — the create-error rule', () => {
    const v = classifyStripeRefundError(new Error('network timeout'));
    expect(v.class).toBe('network');
    expect(v.retryable).toBe(true);
    expect(v.writesState).toBe(false);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 6. Stripe succeeds, then the DB write fails
// ════════════════════════════════════════════════════════════════════════════

describe('Stripe succeeded → mark_refund_state failed', () => {
  it('reconciles on retry instead of double-refunding', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);

    kernel.failNextStateSync = true;
    const first = runExecutor(kernel, stripe, c);
    expect(first.outcome).toBe('state_sync_deferred');
    expect(first.ref).toBe('re_1');
    expect(kernel.rows.get(REFUND)!.status).toBe('pending');
    expect(stripe.created).toBe(1);

    const second = runExecutor(kernel, stripe, reload(kernel, c));
    expect(second.outcome).toBe('succeeded');
    expect(kernel.rows.get(REFUND)!.stripe_refund_ref).toBe('re_1');
    expect(stripe.created).toBe(1);
    expect(stripe.refundedByPi.get('pi_3QabcDEF')).toBe(11000);
  });

  it('a partial callback (submitted written, succeeded lost) still converges', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);

    // Simulate: submitted lands, the process dies before `succeeded`.
    const plan = planRefund(c);
    expect(plan.kind).toBe('stripe_create');
    if (plan.kind !== 'stripe_create') return;
    const obj = stripe.create(plan.idempotency_key, plan.body);
    kernel.markRefundState(REFUND, 'submitted', obj.id, null);
    expect(kernel.rows.get(REFUND)!.status).toBe('submitted');

    // The sweep only picks up `pending`, so `submitted` is the webhook's to
    // finish. A direct re-execute is a documented no-op, never a second refund.
    const replay = runExecutor(kernel, stripe, reload(kernel, c));
    expect(replay.outcome).toBe('noop_replay');
    expect(stripe.created).toBe(1);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 7. DB failure then worker retry / concurrency
// ════════════════════════════════════════════════════════════════════════════

describe('worker retry and concurrency', () => {
  it('two workers racing the same refund produce exactly ONE Stripe refund', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);

    // Both read `pending` before either writes — the real interleaving.
    const snapshotA = { ...c };
    const snapshotB = { ...c };
    const a = runExecutor(kernel, stripe, snapshotA);
    const b = runExecutor(kernel, stripe, snapshotB);

    expect(stripe.created).toBe(1);
    expect(stripe.calls).toBe(2);
    expect(stripe.refundedByPi.get('pi_3QabcDEF')).toBe(11000);
    expect(a.outcome).toBe('succeeded');
    // The loser's forward-only write is refused as `refund_state_backwards`
    // (085:1757-1761). That is a BENIGN convergence, not a failure: the same
    // deterministic key means the winner holds the same `re_…`. Classifying it
    // as retryable is how a healthy race becomes a hot loop against Stripe.
    expect(b.outcome).toBe('noop_replay');
    expect(b.code).toBe('converged_elsewhere');
    expect(kernel.rows.get(REFUND)!.stripe_refund_ref).toBe('re_1');
    expect(kernel.rows.get(REFUND)!.status).toBe('succeeded');
  });

  it('classifies a state-sync outcome: backwards = converged, write-once clash = incident', () => {
    expect(classifyStateSyncError('precondition_failed: refund_state_backwards (succeeded → submitted)'))
      .toEqual({ kind: 'converged', page: false });
    expect(classifyStateSyncError('conflict_locked: stripe_refund_ref is write-once'))
      .toEqual({ kind: 'conflict', page: true });
    expect(classifyStateSyncError('not_found: refund x')).toEqual({ kind: 'conflict', page: true });
    expect(classifyStateSyncError('57P01: terminating connection')).toEqual({ kind: 'retry', page: true });
  });

  it('an amount mutated between attempts is caught BY STRIPE, not silently honoured', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx({ amount_minor: 4000, payment_total_minor: 11000 });
    seed(kernel, c);
    const p1 = planRefund(c);
    if (p1.kind !== 'stripe_create') throw new Error('unreachable');
    stripe.create(p1.idempotency_key, p1.body);

    // Same refund id, tampered amount → same key, different params.
    const p2 = planRefund(ctx({ amount_minor: 9000, payment_total_minor: 11000 }));
    if (p2.kind !== 'stripe_create') throw new Error('unreachable');
    expect(p2.idempotency_key).toBe(p1.idempotency_key);
    expect(() => stripe.create(p2.idempotency_key, p2.body)).toThrow(/idempotency_error/);
    expect(stripe.created).toBe(1);
  });

  it('the idempotency conflict is classified as a bug: never retried, always paged', () => {
    const v = classifyStripeRefundError({ status: 400, error: { code: 'idempotency_error' } });
    expect(v.class).toBe('idempotency_conflict');
    expect(v.retryable).toBe(false);
    expect(v.page).toBe(true);
    expect(v.writesState).toBe(false);
  });

  // RULING: 093 slice 10i (docs/phase2/_impl/H1_refund_architecture.md §4).
  // The two assertions these replace pinned planSweep's CLIENT-SIDE re-derivation
  // of the work list — the pending-only filter, the oldest-first sort and the
  // bound. All three moved INTO kernel.claim_refunds_for_execution, where they
  // are enforced against a worker rather than performed by one, and are pinned by
  // supabase/tests/158_refund_execution_claim.sql B1-B6. Nothing they asserted was
  // dropped: eligibility, ordering, bounding and dedup are all still proven, and
  // the batch now additionally carries a DB-issued lease and execution mode.
  it('the claimed batch is taken as issued: dedup and well-formedness only, never re-selection', () => {
    const rows = planClaimedBatch([
      { refund_id: REFUND, created_at: '2026-09-01T10:00:00Z', status: 'pending', execution_mode: 'create', attempt: 1, command_key: `refund.execute:${REFUND}` },
      { refund_id: REFUND_2, created_at: '2026-09-02T10:00:00Z', status: 'submitted', execution_mode: 'reconcile', attempt: 3, command_key: `refund.execute:${REFUND_2}` },
      { refund_id: REFUND, created_at: '2026-09-01T10:00:00Z', status: 'pending', execution_mode: 'create', attempt: 1, command_key: `refund.execute:${REFUND}` },
    ]);
    // DB order is preserved verbatim — the worker does not re-sort what the
    // database already ordered oldest-money-first.
    expect(rows.map((r) => r.refund_id)).toEqual([REFUND, REFUND_2]);
    expect(rows[1].execution_mode).toBe('reconcile');
  });

  it('a row that is not a well-formed DB claim is DROPPED, never guessed at', () => {
    const rows = planClaimedBatch([
      { refund_id: 'not-a-uuid', created_at: '2026-07-01T10:00:00Z', status: 'pending', execution_mode: 'create', attempt: 1, command_key: 'refund.execute:not-a-uuid' },
      // a mode nobody issued
      { refund_id: REFUND, created_at: '2026-09-01T10:00:00Z', status: 'pending', execution_mode: 'force' as never, attempt: 1, command_key: `refund.execute:${REFUND}` },
      // a command key the caller minted rather than the database
      { refund_id: REFUND_2, created_at: '2026-09-01T10:00:00Z', status: 'pending', execution_mode: 'create', attempt: 1, command_key: 'sweep:whatever' },
    ]);
    expect(rows).toHaveLength(0);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 7b. Reconcile — the branch that exists because Stripe forgets (24h keys)
// ════════════════════════════════════════════════════════════════════════════

describe('reconcile', () => {
  it('a submitted row is finished by FETCHING its own ref, never by creating again', () => {
    const plan = planReconcile(ctx({ status: 'submitted', stripe_refund_ref: 're_abc123' }));
    expect(plan.kind).toBe('fetch_ref');
    if (plan.kind === 'fetch_ref') expect(plan.stripe_refund_ref).toBe('re_abc123');
  });

  it('a pending row with an expired key must ESTABLISH existence before it may create', () => {
    const plan = planReconcile(ctx());
    expect(plan.kind).toBe('search_then_create');
    if (plan.kind === 'search_then_create') {
      expect(plan.payment_intent).toBe('pi_3QabcDEF');
      // the search key is the metadata every created refund carries
      expect(plan.metadata_refund_id).toBe(REFUND);
      expect(plan.create.idempotency_key).toBe(`refund_${REFUND}`);
      expect(plan.create.body['metadata[refund_id]']).toBe(REFUND);
    }
  });

  it('reconcile refuses exactly what the create path refuses — it is not a bypass', () => {
    expect(planReconcile(ctx({ stripe_livemode: null })).kind).toBe('refuse');
    expect(planReconcile(ctx({ order_id: ORDER, sale_id: SALE })).kind).toBe('refuse');
    expect(planReconcile(ctx({ amount_minor: 999999 })).kind).toBe('refuse');
  });

  it('a terminal row is a no-op in reconcile too — money that settled is never re-touched', () => {
    expect(planReconcile(ctx({ status: 'succeeded', stripe_refund_ref: 're_x' })).kind).toBe('noop_replay');
    expect(planReconcile(ctx({ status: 'failed', stripe_refund_ref: 're_y' })).kind).toBe('noop_replay');
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 8. Tombstoned buyer
// ════════════════════════════════════════════════════════════════════════════

describe('tombstoned buyer — the refund binds to the payment, not the customer', () => {
  /**
   * VERIFIED IN THE SCHEMA, cited rather than mocked:
   *   • `kernel.refund.payment_id references public.payments(id) on delete
   *     restrict` (085:76) and `kernel.payment_native.payment_id … on delete
   *     restrict` (085:42) — the payment row cannot be deleted out from under
   *     a refund at all.
   *   • `kernel.sweep_deletion_pending` (077:1865-2050) is the ONLY erasure
   *     writer. Its terminal write set is: `identity_ext.deletion_state`,
   *     `org_member`, `platform_role`, `org_invite`, `public.listings`, plus
   *     four no-op hooks. It touches NEITHER `public.payments` NOR
   *     `kernel.payment_native` NOR `kernel.refund`. `stripe_payment_intent_id`
   *     therefore survives erasure intact.
   *   • The refund goes to the CARD via the PaymentIntent. No Stripe Customer,
   *     no `profiles.stripe_customer_id`, no buyer identity is a parameter of
   *     `POST /v1/refunds` here.
   */
  it('needs no buyer identity: nothing identity-shaped reaches Stripe', () => {
    const plan = planRefund(ctx());
    expect(plan.kind).toBe('stripe_create');
    if (plan.kind === 'stripe_create') {
      const keys = Object.keys(plan.body).join(',');
      expect(keys).not.toMatch(/buyer|customer|identity|email/i);
      expect(plan.body['payment_intent']).toBe('pi_3QabcDEF');
    }
  });

  it('executes identically whether or not the buyer is erased', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);
    // Erasure changes nothing in the execution context — there is no field for
    // it. Same plan, same key, same call.
    const before = planRefund(c);
    const after = planRefund({ ...c });
    expect(JSON.stringify(before)).toBe(JSON.stringify(after));
    expect(runExecutor(kernel, stripe, c).outcome).toBe('succeeded');
  });

  it('reaching succeeded is what UNBLOCKS deletion (BP-12 arm 1, 085:249-262)', () => {
    // BP-12 blocks while status in ('pending','submitted'). Only a terminal
    // clears it — which is exactly why the executor writes `succeeded` when
    // Stripe's own object says so, rather than parking at `submitted`.
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx();
    seed(kernel, c);
    const blocked = (s: string) => s === 'pending' || s === 'submitted';
    expect(blocked(kernel.rows.get(REFUND)!.status)).toBe(true);
    runExecutor(kernel, stripe, c);
    expect(blocked(kernel.rows.get(REFUND)!.status)).toBe(false);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 9. Cancelled event
// ════════════════════════════════════════════════════════════════════════════

describe('event cancellation — catalog.cancel_event refunds are ordinary rows', () => {
  /**
   * `catalog.cancel_event` (088:1612+) never calls `refund_primary_order`. It
   * INSERTs `kernel.refund` rows directly at 088:1664 (paid_pending sales),
   * 088:1721 (resold atoms) and 088:1779 (primary orders), each born `pending`
   * with key `<command_key>:sale:<id>` or `<command_key>:order:<id>`. Being
   * refund-row-driven is precisely what makes them executable with no special
   * case.
   */
  it('executes an event_cancelled row through the identical path', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx({ reason_code: 'event_cancelled' });
    kernel.insertRefund({
      refund_id: REFUND, payment_id: PAYMENT, amount_minor: 11000,
      status: 'pending', stripe_refund_ref: null,
      idempotency_key: 'cancel-evt-7:order:' + ORDER,
    });
    const r = runExecutor(kernel, stripe, c);
    expect(r.outcome).toBe('succeeded');
    const plan = planRefund(c);
    if (plan.kind === 'stripe_create') expect(plan.body['metadata[reason]']).toBe('event_cancelled');
  });

  it('a cancellation fan-out of N rows drains as N distinct refunds, one per row', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const rows = [0, 1, 2].map((i) => ctx({
      refund_id: `aaaaaaaa-0000-4000-8000-00000000000${i}`,
      payment_id: `bbbbbbbb-0000-4000-8000-00000000000${i}`,
      stripe_payment_intent_id: `pi_evt${i}`,
      amount_minor: 5000,
      payment_total_minor: 5000,
      reason_code: 'event_cancelled',
    }));
    rows.forEach((c, i) => seed(kernel, c, `cancel-evt-7:order:${i}`));
    const claimed = planClaimedBatch(rows.map((c, i) => ({
      refund_id: c.refund_id, created_at: `2026-09-0${i + 1}T00:00:00Z`, status: 'pending' as const,
      execution_mode: 'create' as const, attempt: 1, command_key: `refund.execute:${c.refund_id}`,
    })));
    expect(claimed).toHaveLength(3);
    rows.forEach((c) => runExecutor(kernel, stripe, c));
    expect(stripe.created).toBe(3);
    expect([...stripe.refundedByPi.values()]).toEqual([5000, 5000, 5000]);
  });

  it('replaying the whole cancellation sweep refunds nothing twice', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx({ reason_code: 'event_cancelled' });
    seed(kernel, c, 'cancel-evt-7:order:x');
    runExecutor(kernel, stripe, c);
    runExecutor(kernel, stripe, reload(kernel, c));
    runExecutor(kernel, stripe, reload(kernel, c));
    expect(stripe.created).toBe(1);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 10. Wrong order / already-refunded order / chargeback
// ════════════════════════════════════════════════════════════════════════════

describe('already-refunded order', () => {
  it('a payment with no headroom left is refused before Stripe', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();
    const c = ctx({ amount_minor: 11000, payment_total_minor: 11000, prior_non_failed_minor: 11000 });
    seed(kernel, c);
    const r = runExecutor(kernel, stripe, c);
    expect(r.outcome).toBe('refused');
    expect(r.code).toBe('amount_exceeds_headroom');
    expect(stripe.calls).toBe(0);
  });

  it('Stripe answering charge_already_refunded is terminal and paged, never retried', () => {
    const v = classifyStripeRefundError({ status: 400, error: { code: 'charge_already_refunded' } });
    expect(v.retryable).toBe(false);
    expect(v.page).toBe(true);
    expect(v.writesState).toBe(false);
  });

  it('a payment whose row is not succeeded/refunded is refused', () => {
    for (const s of ['pending', 'processing', 'failed']) {
      const plan = planRefund(ctx({ payment_status: s }));
      expect(plan.kind).toBe('refuse');
      if (plan.kind === 'refuse') expect(plan.code).toBe('payment_not_refundable');
    }
  });
});

describe('chargeback interaction', () => {
  it('a lost/charge_refunded dispute consumes headroom exactly as 088:1661 computes it', () => {
    // total 11000, dispute took 11000 back → no headroom for a refund.
    const plan = planRefund(ctx({ amount_minor: 11000, payment_total_minor: 11000, disputed_minor: 11000 }));
    expect(plan.kind).toBe('refuse');
    if (plan.kind === 'refuse') expect(plan.code).toBe('amount_exceeds_headroom');
  });

  it('a partial chargeback leaves exactly the remaining headroom refundable', () => {
    expect(planRefund(ctx({ amount_minor: 4000, payment_total_minor: 11000, disputed_minor: 7000 })).kind).toBe('stripe_create');
    expect(planRefund(ctx({ amount_minor: 4001, payment_total_minor: 11000, disputed_minor: 7000 })).kind).toBe('refuse');
  });

  it('Stripe refusing a disputed charge is terminal and paged — the dispute rail owns that money', () => {
    const v = classifyStripeRefundError({ status: 400, error: { code: 'charge_disputed' } });
    expect(v.class).toBe('charge_disputed');
    expect(v.retryable).toBe(false);
    expect(v.page).toBe(true);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 11. Mode boundary, state-sync planning, error taxonomy, authority routing
// ════════════════════════════════════════════════════════════════════════════

describe('mode boundary (migration 045)', () => {
  it('refuses a test-era payment and an unclassified one — fail closed', () => {
    for (const lm of [false, null]) {
      const plan = planRefund(ctx({ stripe_livemode: lm }));
      expect(plan.kind).toBe('refuse');
      if (plan.kind === 'refuse') expect(plan.code).toBe('payment_not_livemode');
    }
  });
});

describe('mark_refund_state planning', () => {
  it('always writes submitted first, so the write-once ref lands even if the process dies', () => {
    const p = planStateSync({ id: 're_1', status: 'succeeded' });
    expect(p.kind).toBe('sync');
    if (p.kind === 'sync') {
      expect(p.steps[0].new_status).toBe('submitted');
      expect(p.steps[1].new_status).toBe('succeeded');
    }
  });

  it('records failed with a mandatory failure_code (085:1769-1771)', () => {
    const p = planStateSync({ id: 're_1', status: 'failed', failure_reason: 'expired_or_canceled_card' });
    if (p.kind !== 'sync') throw new Error('unreachable');
    expect(p.steps[1]).toEqual({ new_status: 'failed', stripe_refund_ref: 're_1', failure_code: 'expired_or_canceled_card' });
  });

  it('substitutes a failure_code when Stripe supplies none, so the RPC cannot reject the write', () => {
    const p = planStateSync({ id: 're_1', status: 'failed' });
    if (p.kind !== 'sync') throw new Error('unreachable');
    expect(p.steps[1].failure_code).toBe('stripe_refund_failed');
  });

  it('stops at submitted while Stripe is still pending', () => {
    const p = planStateSync({ id: 're_1', status: 'pending' });
    if (p.kind !== 'sync') throw new Error('unreachable');
    expect(p.steps).toHaveLength(1);
  });

  it('refuses to record anything that is not a re_ reference', () => {
    for (const bad of ['ch_1', 'pi_1', '', undefined, 42]) {
      expect(planStateSync({ id: bad as unknown, status: 'succeeded' }).kind).toBe('refuse');
    }
  });

  it('the forward-only machine rejects a backwards write (085:1757-1761)', () => {
    const kernel = new KernelMock();
    kernel.insertRefund({ refund_id: REFUND, payment_id: PAYMENT, amount_minor: 100, status: 'pending', stripe_refund_ref: null, idempotency_key: 'k' });
    kernel.markRefundState(REFUND, 'submitted', 're_1', null);
    kernel.markRefundState(REFUND, 'succeeded', 're_1', null);
    expect(() => kernel.markRefundState(REFUND, 'submitted', 're_1', null)).toThrow(/refund_state_backwards/);
  });

  it('the ref is write-once: a different ref on the same row is a conflict', () => {
    const kernel = new KernelMock();
    kernel.insertRefund({ refund_id: REFUND, payment_id: PAYMENT, amount_minor: 100, status: 'pending', stripe_refund_ref: null, idempotency_key: 'k' });
    kernel.markRefundState(REFUND, 'submitted', 're_1', null);
    expect(() => kernel.markRefundState(REFUND, 'succeeded', 're_2', null)).toThrow(/write-once/);
  });
});

describe('Stripe error taxonomy', () => {
  const cases: Array<[unknown, string, boolean]> = [
    [{ status: 429, error: { code: 'rate_limit' } }, 'rate_limited', true],
    [{ status: 500, error: { type: 'api_error' } }, 'api_error', true],
    [{ status: 409, error: { code: 'idempotency_key_in_use' } }, 'idempotency_in_use', true],
    [{ status: 400, error: { code: 'balance_insufficient' } }, 'balance_insufficient', true],
    [{ status: 404, error: { code: 'resource_missing' } }, 'resource_missing', false],
    [{ status: 400, error: { type: 'invalid_request_error' } }, 'invalid_request', false],
  ];
  it.each(cases)('%o → %s (retryable=%s)', (input, cls, retryable) => {
    const v = classifyStripeRefundError(input as { status: number; error: { code?: string; type?: string } });
    expect(v.class).toBe(cls);
    expect(v.retryable).toBe(retryable);
  });

  it('NO error class ever writes refund state — the create-error rule is total', () => {
    const all = [
      ...cases.map(([i]) => classifyStripeRefundError(i as { status: number })),
      classifyStripeRefundError(new Error('boom')),
      classifyStripeRefundError({ status: 400, error: { code: 'idempotency_error' } }),
      classifyStripeRefundError({ status: 418, error: {} }),
    ];
    expect(all.every((v) => v.writesState === false)).toBe(true);
  });
});

describe('authority routing (PFA-23)', () => {
  it('a req: command key selects the delegated arm', () => {
    expect(classifyArm(`req:${ORDER}`)).toBe('delegated');
  });

  it('anything else is the direct (platform) arm', () => {
    expect(classifyArm('refund-execute:abc')).toBe('direct');
    expect(classifyArm('request:abc')).toBe('direct');
  });

  it('the four denial codes route to record_money_denial', () => {
    for (const m of ['insufficient_privilege: nope', 'sod_violation', 'step_up_required', 'step_up_unavailable']) {
      expect(isMoneyDenial(m)).toBe(true);
    }
    expect(isMoneyDenial('precondition_failed: over_refund')).toBe(false);
  });

  it('RPC errors map to the spec failure table', () => {
    expect(httpStatusForRpcError('insufficient_privilege: platform only')).toBe(403);
    expect(httpStatusForRpcError('not_found: order x')).toBe(404);
    expect(httpStatusForRpcError('precondition_failed: over_refund')).toBe(409);
    expect(httpStatusForRpcError('conflict_locked: atom listed')).toBe(409);
    expect(httpStatusForRpcError('frozen: atom is transfer-frozen')).toBe(409);
    expect(httpStatusForRpcError('invalid_input: bad amount')).toBe(400);
    expect(httpStatusForRpcError('something else entirely')).toBe(500);
  });
});

describe('uuid discipline', () => {
  it('rejects the nil uuid, non-uuids and non-strings', () => {
    expect(isUuid(REFUND)).toBe(true);
    expect(isUuid('00000000-0000-0000-0000-000000000000')).toBe(false);
    expect(isUuid('order-1')).toBe(false);
    expect(isUuid(null)).toBe(false);
    expect(isUuid(12)).toBe(false);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 199 — executor holds (DESIGN-199-FINAL §3.4, §4, §5.3)
// ════════════════════════════════════════════════════════════════════════════

describe('executor holds — get_refund_execution_context raises for a held row (199 §3.4)', () => {
  // The exact texts D's body raises (§4): `precondition_failed: executor_hold %
  // (refund %)`, errcode P0001, for a pending/submitted row whose
  // kernel.refund_executor_hold is manual_record or parked.
  it('names the hold from the raise, for both holds D defines', () => {
    expect(executorHoldOf(`precondition_failed: executor_hold manual_record (refund ${REFUND})`)).toBe('manual_record');
    expect(executorHoldOf(`precondition_failed: executor_hold parked (refund ${REFUND})`)).toBe('parked');
  });

  it('anything else is not a hold: a transient read failure must never be mistaken for one', () => {
    expect(executorHoldOf('canceling statement due to statement timeout')).toBeNull();
    expect(executorHoldOf('precondition_failed: over_refund')).toBeNull();
    // An unknown hold kind is not mapped; it stays context_read_failed (409,
    // still no Stripe call), which is the fail-closed direction.
    expect(executorHoldOf(`precondition_failed: executor_hold quarantined (refund ${REFUND})`)).toBeNull();
    expect(executorHoldOf('')).toBeNull();
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 199 — the Stripe-truth guard on succeeded (DESIGN-199-FINAL §3.2, §5.4, §6 R7/R8)
// ════════════════════════════════════════════════════════════════════════════

describe('mark_refund_state never writes succeeded over a recorded Stripe failure (199 §3.2) — the port', () => {
  function submitted(ref = 're_1'): KernelMock {
    const kernel = new KernelMock();
    kernel.insertRefund({ refund_id: REFUND, payment_id: PAYMENT, amount_minor: 100, status: 'pending', stripe_refund_ref: null, idempotency_key: 'k' });
    kernel.markRefundState(REFUND, 'submitted', ref, null);
    return kernel;
  }
  const thrown = (fn: () => unknown): string => {
    try { fn(); } catch (err) { return (err as Error).message; }
    return '';
  };

  it.each(['failed', 'canceled'])('refuses submitted → succeeded while Stripe has recorded the ref %s, with D\'s exact text; the row stays submitted', (stripeStatus) => {
    const kernel = submitted();
    kernel.stripeState.set('re_1', stripeStatus);
    expect(thrown(() => kernel.markRefundState(REFUND, 'succeeded', 're_1', null)))
      .toBe(`precondition_failed: refund_failed_at_stripe (re_1 is ${stripeStatus})`);
    expect(kernel.rows.get(REFUND)).toMatchObject({ status: 'submitted', stripe_refund_ref: 're_1' });
  });

  it('the executor classes that refusal as retry and pages (§3.2): the row stays submitted for the next reconcile', () => {
    expect(classifyStateSyncError('precondition_failed: refund_failed_at_stripe (re_1 is failed)')).toEqual({ kind: 'retry', page: true });
  });

  it('control: no observation, or a succeeded one, and succeeded lands exactly as before; failed is never guarded', () => {
    const none = submitted();
    expect(none.markRefundState(REFUND, 'succeeded', 're_1', null)).toEqual({ status: 'ok' });
    const ok = submitted();
    ok.stripeState.set('re_1', 'succeeded');
    expect(ok.markRefundState(REFUND, 'succeeded', 're_1', null)).toEqual({ status: 'ok' });
    const failed = submitted();
    failed.stripeState.set('re_1', 'failed');
    expect(failed.markRefundState(REFUND, 'failed', 're_1', 'expired_or_canceled_card')).toEqual({ status: 'ok' });
  });

  it('check order is 085\'s, the guard last: direction first, so a backwards write is still refund_state_backwards → converged (G1)', () => {
    // pending → succeeded over a failed observation: direction refuses first.
    const pending = new KernelMock();
    pending.insertRefund({ refund_id: REFUND, payment_id: PAYMENT, amount_minor: 100, status: 'pending', stripe_refund_ref: null, idempotency_key: 'k' });
    pending.stripeState.set('re_1', 'failed');
    const msg = thrown(() => pending.markRefundState(REFUND, 'succeeded', 're_1', null));
    expect(msg).toMatch(/refund_state_backwards \(pending → succeeded\)/);
    expect(classifyStateSyncError(msg).kind).toBe('converged');
    // §6 R8: the webhook verb already set failed; the executor replays submitted.
    const done = submitted();
    done.stripeState.set('re_1', 'failed');
    done.markRefundState(REFUND, 'failed', 're_1', 'expired_or_canceled_card');
    const replay = thrown(() => done.markRefundState(REFUND, 'submitted', 're_1', null));
    expect(classifyStateSyncError(replay).kind).toBe('converged');
    expect(done.rows.get(REFUND)!.status).toBe('failed');
  });

  it('check order: noop and write-once still precede the guard', () => {
    // An identical terminal is noop_replay before any guard is consulted.
    const settled = submitted();
    settled.markRefundState(REFUND, 'succeeded', 're_1', null);
    settled.stripeState.set('re_1', 'failed');
    expect(settled.markRefundState(REFUND, 'succeeded', 're_1', null)).toEqual({ status: 'noop_replay' });
    // A different ref is the write-once conflict, not the guard.
    const other = submitted('re_1');
    other.stripeState.set('re_2', 'failed');
    expect(thrown(() => other.markRefundState(REFUND, 'succeeded', 're_2', null))).toMatch(/write-once/);
  });

  it('§6 R7: Stripe fails the refund before the executor binds it — the kernel never says succeeded, and the next sweep fetches the ref', () => {
    const kernel = new KernelMock();
    const stripe = new StripeMock();               // the create answers succeeded (a cached / stale response)
    const c = ctx();
    seed(kernel, c);
    kernel.stripeState.set('re_1', 'failed');      // the webhook recorded re_1 failed first
    const r = runExecutor(kernel, stripe, c);
    expect(r).toEqual({ outcome: 'state_sync_deferred', code: 'mark_refund_state_failed', ref: 're_1' });
    expect(kernel.rows.get(REFUND)).toMatchObject({ status: 'submitted', stripe_refund_ref: 're_1' });
    expect(planReconcile(reload(kernel, c))).toEqual({ kind: 'fetch_ref', stripe_refund_ref: 're_1' });
    expect(stripe.created).toBe(1);
  });
});

// ════════════════════════════════════════════════════════════════════════════
// 199 — parking what the sweep must stop re-claiming (DESIGN-199-FINAL §3.6, §5.2)
// ════════════════════════════════════════════════════════════════════════════

describe('park planning — only a non-retryable sweep outcome is parked (199 §5.2, refunds-7)', () => {
  const row: ClaimedRefund = {
    refund_id: REFUND, created_at: '2026-10-01T00:00:00Z', status: 'pending',
    execution_mode: 'create', attempt: 3, command_key: `refund.execute:${REFUND}`,
  };

  it.each([
    ['refused', 'reconcile_ambiguous'],
    ['refused', 'binding_order_mismatch'],
    ['stripe_error', 'charge_disputed'],
    ['stripe_error', 'resource_missing'],
    ['state_sync_deferred', 'state_sync_conflict'],
  ])('%s / %s with retryable:false → park under the DB-issued key, fenced by the claim attempt', (outcome, code) => {
    expect(planPark(row, { outcome, code, retryable: false })).toEqual({
      p_refund_id: REFUND, p_attempt: 3, p_outcome: outcome, p_reason_code: code, p_command_key: `refund.execute:${REFUND}`,
    });
  });

  it('never parks a retryable outcome, or one whose retryability is unknown (undefined)', () => {
    expect(planPark(row, { outcome: 'stripe_error', code: 'rate_limited', retryable: true })).toBeNull();
    expect(planPark(row, { outcome: 'refused', code: 'context_read_failed' })).toBeNull();
    expect(planPark(row, { outcome: 'state_sync_deferred', code: 'state_sync_unverified', retryable: true })).toBeNull();
  });

  it('never parks a converged or recorded outcome, even one marked retryable:false', () => {
    for (const outcome of ['noop_replay', 'submitted', 'succeeded', 'failed']) {
      expect(planPark(row, { outcome, code: 'converged_elsewhere', retryable: false })).toBeNull();
    }
  });

  it('never parks an executor_hold refusal: the row is already held, so a park would only be a noop_replay', () => {
    expect(planPark(row, { outcome: 'refused', code: 'executor_hold', retryable: false })).toBeNull();
  });

  it('a code outside the verb\'s reason_code shape (^[a-z][a-z0-9_]{0,63}$) is parked as unclassified, never sent raw', () => {
    for (const code of [undefined, '', 'Bad-Code', '9lives', 'x'.repeat(65)]) {
      expect(planPark(row, { outcome: 'stripe_error', code, retryable: false })?.p_reason_code).toBe('unclassified');
    }
    expect(planPark(row, { outcome: 'stripe_error', code: 'x'.repeat(64), retryable: false })?.p_reason_code).toBe('x'.repeat(64));
  });
});

// E review of ed7e4a8a: `retryable: false` carried two unrelated meanings. "This
// refund is wrong" (charge_disputed, resource_missing, idempotency_conflict) is
// per-row and needs a human, so parking is right. "We cannot talk to Stripe at
// all" (401/403: a revoked, rotated, restricted or wrong-mode key) says nothing
// about the row, and parking it turns one instantly fixable config fault into N
// rows of durable state, each needing its own aal2 re-arm.
describe('a Stripe auth fault is non-retryable but never parked', () => {
  it.each([
    [401, { type: 'invalid_request_error', message: 'Invalid API Key provided' }],
    [403, { type: 'invalid_request_error', message: 'The provided key does not have the required permissions' }],
    [403, { type: 'permission_error' }],
  ] as const)('HTTP %i is auth_error: not retried with the same key, always paged', (status, error) => {
    const v = classifyStripeRefundError({ status, error: { ...error } });
    expect(v).toMatchObject({ class: 'auth_error', retryable: false, page: true, writesState: false });
  });

  it('control: the per-row 4xx classes are unchanged (they still park)', () => {
    expect(classifyStripeRefundError({ status: 400, error: { code: 'charge_disputed' } }).class).toBe('charge_disputed');
    expect(classifyStripeRefundError({ status: 404, error: { code: 'resource_missing' } }).class).toBe('resource_missing');
    expect(classifyStripeRefundError({ status: 400, error: { type: 'invalid_request_error' } }).class).toBe('invalid_request');
  });

  it('a non-2xx with no JSON error body is classified on its status alone (a proxy-generated 502)', () => {
    expect(classifyStripeRefundError({ status: 502, error: undefined })).toMatchObject({ class: 'api_error', retryable: true });
    expect(classifyStripeRefundError({ status: 401, error: undefined })).toMatchObject({ class: 'auth_error', retryable: false });
  });

  it('planPark never parks an auth_error (the executor_hold shape: non-retryable, not parked)', () => {
    const row = { refund_id: 'r1', created_at: '2026-10-01T00:00:00Z', status: 'pending' as const, execution_mode: 'create' as const, attempt: 2, command_key: 'refund.execute:r1' };
    expect(planPark(row, { outcome: 'stripe_error', code: 'auth_error', retryable: false })).toBeNull();
    expect(planPark(row, { outcome: 'stripe_error', code: 'charge_disputed', retryable: false })).not.toBeNull();   // control
  });
});
