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
 *   noop-replay, mandatory failure_code).
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
  httpStatusForRpcError,
  isMoneyDenial,
  isUuid,
  planRefund,
  planStateSync,
  planSweep,
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

// ── kernel.refund + mark_refund_state mock (085:74-95, 085:1737-1789) ───────

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

  /** Faithful port of kernel.mark_refund_state (085:1737-1789). */
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

  it('the sweep is bounded, oldest-first, deduped, and pending-only', () => {
    const ids = planSweep([
      { refund_id: REFUND_2, created_at: '2026-09-02T10:00:00Z', status: 'pending' },
      { refund_id: REFUND, created_at: '2026-09-01T10:00:00Z', status: 'pending' },
      { refund_id: REFUND, created_at: '2026-09-01T10:00:00Z', status: 'pending' },
      { refund_id: PAYMENT, created_at: '2026-08-01T10:00:00Z', status: 'succeeded' },
      { refund_id: 'not-a-uuid', created_at: '2026-07-01T10:00:00Z', status: 'pending' },
    ], { limit: 10 });
    expect(ids).toEqual([REFUND, REFUND_2]);
  });

  it('the sweep limit is clamped to 100 and floored at 1', () => {
    const rows = Array.from({ length: 200 }, (_, i) => ({
      refund_id: `${String(i).padStart(8, '0')}-0000-4000-8000-000000000000`,
      created_at: `2026-09-0${(i % 9) + 1}T00:00:00Z`,
      status: 'pending' as const,
    }));
    expect(planSweep(rows, { limit: 5000 })).toHaveLength(100);
    expect(planSweep(rows, { limit: 0 })).toHaveLength(1);
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
    const ids = planSweep(rows.map((c, i) => ({ refund_id: c.refund_id, created_at: `2026-09-0${i + 1}T00:00:00Z`, status: 'pending' as const })));
    expect(ids).toHaveLength(3);
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
