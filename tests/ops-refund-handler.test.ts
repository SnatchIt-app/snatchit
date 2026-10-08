/**
 * tests/ops-refund-handler.test.ts — the console refund executor flow
 * (supabase/functions/ops-refund-execute/handler.ts) over fake adapters.
 *
 * What is asserted is ORDER and FENCING: which database writes happen before
 * which Stripe calls, that an HTTP 2xx is never success by itself, that
 * nothing is adopted without matching identity, and that a retry looks
 * before it posts. No Deno, no network.
 */
import { describe, expect, it } from 'vitest';

import {
  CLAIM_LEASE_SECONDS,
  type ClaimResult,
  type ClaimedAction,
  type Deps,
  type RecordOutcomeResult,
  type StripeListResult,
  type StripeTransportResult,
  runRefundExecution,
} from '../supabase/functions/ops-refund-execute/handler';
import type { StripeRefundObject } from '../supabase/functions/ops-refund-execute/classify';

const ACTION_ID = '11111111-2222-4333-8444-555555555555';
const PAYMENT_ID = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const PI = 'pi_3Abc123';
const KEY = `ops_action_${ACTION_ID}`;
const CALLER = { userId: 'user-1', role: 'platform_admin', aal: 'aal2' };
const INPUT = { actionId: ACTION_ID, caller: CALLER };

const CLAIMED: ClaimedAction = {
  status: 'claimed',
  action_id: ACTION_ID,
  payment_id: PAYMENT_ID,
  stripe_payment_intent_id: PI,
  amount_cents: 5000,
  payment_total_cents: 5000,
  currency: 'usd',
  reason_code: 'duplicate',
  previously_sent: false,
  provider_ref: null,
  attempt: 1,
  stripe_livemode: false,   // test row; every fixture pairs it with a 'test' key
};

function refund(over: Partial<StripeRefundObject> = {}): StripeRefundObject {
  return {
    id: 're_ours',
    status: 'succeeded',
    amount: 5000,
    currency: 'usd',
    payment_intent: PI,
    charge: 'ch_1',
    metadata: { ops_action_id: ACTION_ID, payment_id: PAYMENT_ID, source: 'ops-refund-execute' },
    ...over,
  };
}

type Recorded = { state: string; result: Record<string, unknown> | null; error: string | null; providerRef: string | null };

interface FakeOptions {
  claim?: ClaimResult | ((n: number) => ClaimResult);
  create?: StripeTransportResult | Error | ((body: Record<string, string>, key: string) => StripeTransportResult | Error);
  list?: StripeListResult | Error | (() => StripeListResult | Error);
  /** Throw / refuse recordOutcome for a given state. */
  record?: (state: string, n: number) => RecordOutcomeResult | Error | undefined;
}

function fake(opts: FakeOptions = {}) {
  const calls = { claim: 0, create: [] as Array<{ body: Record<string, string>; key: string }>, list: 0, record: [] as Recorded[] };
  const logs: Array<{ level: string; event: string; fields?: Record<string, unknown> }> = [];
  const alerts: Array<{ event: string; message: string }> = [];
  const deps: Deps = {
    stripeKeyMode: 'test',
    db: {
      async claim(actionId, lease) {
        calls.claim += 1;
        expect(actionId).toBe(ACTION_ID);
        expect(lease).toBe(CLAIM_LEASE_SECONDS);
        const c = opts.claim ?? CLAIMED;
        return typeof c === 'function' ? c(calls.claim) : c;
      },
      async recordOutcome(actionId, state, result, error, providerRef) {
        expect(actionId).toBe(ACTION_ID);
        calls.record.push({ state, result, error, providerRef });
        const r = opts.record?.(state, calls.record.length);
        if (r instanceof Error) throw r;
        return r ?? { status: 'ok', action_id: actionId, state };
      },
    },
    stripe: {
      async createRefund(body, key) {
        calls.create.push({ body, key });
        const c = opts.create ?? { ok: true, status: 200, data: refund() };
        const r = typeof c === 'function' ? c(body, key) : c;
        if (r instanceof Error) throw r;
        return r;
      },
      async listRefunds(pi) {
        calls.list += 1;
        expect(pi).toBe(PI);
        const l = opts.list ?? { ok: true, data: [] };
        const r = typeof l === 'function' ? l() : l;
        if (r instanceof Error) throw r;
        return r;
      },
    },
    now: () => new Date('2026-09-07T00:00:00.000Z'),
    log: {
      info: (event, fields) => logs.push({ level: 'info', event, fields }),
      warn: (event, fields) => logs.push({ level: 'warn', event, fields }),
      error: (event, fields) => logs.push({ level: 'error', event, fields }),
    },
    alert: async (event, message) => { alerts.push({ event, message }); },
  };
  return { deps, calls, logs, alerts };
}

const lastRecord = (calls: ReturnType<typeof fake>['calls']) => calls.record[calls.record.length - 1];

function assertNoSecrets(...things: unknown[]) {
  const s = JSON.stringify(things);
  expect(s).not.toMatch(/sk_(live|test)_/);
  expect(s).not.toMatch(/rk_(live|test)_/);
}

describe('happy path — full refund', () => {
  it('claim → processing → POST (key + metadata) → succeeded_at_provider 200', async () => {
    const f = fake();
    const res = await runRefundExecution(INPUT, f.deps);

    expect(res.http).toBe(200);
    expect(res.body).toMatchObject({ action_id: ACTION_ID, state: 'succeeded_at_provider', provider_ref: 're_ours' });

    expect(f.calls.claim).toBe(1);
    expect(f.calls.list).toBe(0);
    expect(f.calls.create).toHaveLength(1);
    expect(f.calls.create[0].key).toBe(KEY);
    expect(f.calls.create[0].body).toMatchObject({
      payment_intent: PI, amount: '5000', reason: 'duplicate',
      'metadata[ops_action_id]': ACTION_ID, 'metadata[payment_id]': PAYMENT_ID,
    });

    expect(f.calls.record.map((r) => r.state)).toEqual(['processing', 'succeeded_at_provider']);
    expect(f.calls.record[0].result).toMatchObject({ stripe_request_started_at: '2026-09-07T00:00:00.000Z', attempt: 1, partial: false });
    expect(f.calls.record[1]).toMatchObject({
      providerRef: 're_ours',
      result: { refund_status: 'succeeded', amount: 5000, currency: 'usd', charge: 'ch_1', payment_intent: PI },
    });
  });

  it('processing is recorded BEFORE the Stripe call', async () => {
    const order: string[] = [];
    const f = fake({
      record: (state) => { order.push(`record:${state}`); return undefined; },
      create: () => { order.push('stripe:create'); return { ok: true, status: 200, data: refund() }; },
    });
    await runRefundExecution(INPUT, f.deps);
    expect(order).toEqual(['record:processing', 'stripe:create', 'record:succeeded_at_provider']);
  });
});

describe('partial refunds are refused by the handler (defense in depth)', () => {
  it('amount_cents < payment_total_cents → failed 422, no Stripe call', async () => {
    const f = fake({ claim: { ...CLAIMED, amount_cents: 1234 } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(res.body).toMatchObject({ state: 'failed' });
    expect(f.calls.create).toHaveLength(0);
    expect(f.calls.list).toBe(0);
    expect(f.calls.record).toHaveLength(1);
    expect(f.calls.record[0]).toMatchObject({ state: 'failed', result: { refused: 'partial_refund_unsupported', amount_cents: 1234, payment_total_cents: 5000 } });
  });

  it('amount_cents > payment_total_cents is refused the same way', async () => {
    const f = fake({ claim: { ...CLAIMED, amount_cents: 9999 } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(f.calls.create).toHaveLength(0);
  });
});

describe('the refund OBJECT decides, never the HTTP status', () => {
  it('pending → processing 202, provider_ref recorded, NOT success', async () => {
    const f = fake({ create: { ok: true, status: 200, data: refund({ status: 'pending' }) } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(202);
    expect(res.body).toMatchObject({ state: 'processing', provider_ref: 're_ours' });
    expect(lastRecord(f.calls)).toMatchObject({
      state: 'processing', providerRef: 're_ours',
      result: { refund_status: 'pending', provider_ref: 're_ours', needs_action: false },
    });
    expect(f.calls.record.some((r) => r.state === 'succeeded_at_provider')).toBe(false);
  });

  it('requires_action → processing 202 with needs_action + next_action', async () => {
    const next = { type: 'display_details', display_details: { email_sent: { email_sent_at: 1 } } };
    const f = fake({ create: { ok: true, status: 200, data: refund({ status: 'requires_action', next_action: next }) } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(202);
    expect(lastRecord(f.calls)).toMatchObject({
      state: 'processing',
      result: { refund_status: 'requires_action', needs_action: true, next_action: next },
    });
  });

  it('failed → failed 422 with failure_reason', async () => {
    const f = fake({ create: { ok: true, status: 200, data: refund({ status: 'failed', failure_reason: 'lost_or_stolen_card' }) } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'failed', result: { failure_reason: 'lost_or_stolen_card' } });
  });

  it('canceled → failed 422', async () => {
    const f = fake({ create: { ok: true, status: 200, data: refund({ status: 'canceled' }) } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'failed', result: { failure_reason: 'canceled' } });
  });

  it('unrecognised status → unknown 502', async () => {
    const f = fake({ create: { ok: true, status: 200, data: refund({ status: 'something_new' }) } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'unknown' });
  });

  it('2xx whose object does not match the claim (amount) → unknown 502, never success', async () => {
    const f = fake({ create: { ok: true, status: 200, data: refund({ amount: 2500 }) } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(res.body).not.toHaveProperty('provider_ref');
    expect(lastRecord(f.calls)).toMatchObject({
      state: 'unknown', providerRef: null,
      result: { mismatch: { amount: { expected: 5000, actual: 2500 } } },
    });
  });
});

describe('claim fencing — no Stripe call without a claim', () => {
  it.each<[string, ClaimResult]>([
    ['claim_busy (duplicate request)', { status: 'refused', reason: 'claim_busy' }],
    ['disabled at execution time', { status: 'refused', reason: 'disabled' }],
    ['paused', { status: 'refused', reason: 'paused' }],
    ['approval_missing', { status: 'refused', reason: 'approval_missing' }],
    ['approval_stale (hash no longer matches)', { status: 'refused', reason: 'approval_stale' }],
    ['terminal', { status: 'refused', reason: 'terminal' }],
    ['succeeded_at_provider (waiting for webhook)', { status: 'refused', reason: 'succeeded_at_provider' }],
    ['not_found', { status: 'refused', reason: 'not_found' }],
    ['wrong_type', { status: 'refused', reason: 'wrong_type' }],
  ])('%s → 409 {reason}, no Stripe call, no outcome write', async (_label, claim) => {
    const f = fake({ claim });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(409);
    expect(res.body).toMatchObject({ action_id: ACTION_ID, error: 'claim_refused', reason: claim.status === 'refused' ? claim.reason : '' });
    expect(f.calls.create).toHaveLength(0);
    expect(f.calls.list).toBe(0);
    expect(f.calls.record).toHaveLength(0);
  });

  it('already_refunded_locally → records succeeded, 200, no Stripe call', async () => {
    const f = fake({ claim: { status: 'refused', reason: 'already_refunded_locally' } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(200);
    expect(res.body).toMatchObject({ state: 'succeeded' });
    expect(f.calls.record).toEqual([{ state: 'succeeded', result: { note: 'already refunded locally' }, error: null, providerRef: null }]);
    expect(f.calls.create).toHaveLength(0);
  });

  it('concurrent requests: first claim wins → exactly one createRefund', async () => {
    let taken = false;
    const claim = (): ClaimResult => {
      if (taken) return { status: 'refused', reason: 'claim_busy' };
      taken = true;
      return CLAIMED;
    };
    const f = fake({ claim });
    const [a, b] = await Promise.all([runRefundExecution(INPUT, f.deps), runRefundExecution(INPUT, f.deps)]);
    expect([a.http, b.http].sort()).toEqual([200, 409]);
    expect(f.calls.claim).toBe(2);
    expect(f.calls.create).toHaveLength(1);
  });

  it('malformed claim payload → 500 claim_invalid, no Stripe call', async () => {
    const f = fake({ claim: { ...CLAIMED, stripe_payment_intent_id: 'ch_notapi' } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(500);
    expect(res.body).toMatchObject({ error: 'claim_invalid' });
    expect(f.calls.create).toHaveLength(0);
  });

  it('claim without payment_total_cents → 500 claim_invalid, no Stripe call (the partial guard needs the total)', async () => {
    const { payment_total_cents: _omit, ...withoutTotal } = CLAIMED;
    const f = fake({ claim: withoutTotal as unknown as ClaimResult });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(500);
    expect(res.body).toMatchObject({ error: 'claim_invalid' });
    expect(f.calls.create).toHaveLength(0);
    expect(f.calls.record).toHaveLength(0);
  });

  it('refusal diagnostics (state, claimed_until) are passed through', async () => {
    const f = fake({ claim: { status: 'refused', reason: 'claim_busy', state: 'processing', claimed_until: '2026-09-07T00:02:00Z' } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.body).toMatchObject({ reason: 'claim_busy', state: 'processing', claimed_until: '2026-09-07T00:02:00Z' });
  });

  it('non-usd claim → 500 claim_invalid, no Stripe call', async () => {
    const f = fake({ claim: { ...CLAIMED, currency: 'eur' } });
    expect((await runRefundExecution(INPUT, f.deps)).http).toBe(500);
    expect(f.calls.create).toHaveLength(0);
  });
});

describe('crash / outcome-write failures', () => {
  it('recordOutcome(processing) throws → no createRefund, error surfaced', async () => {
    const f = fake({ record: (state) => (state === 'processing' ? new Error('db down sk_live_SECRET123') : undefined) });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(500);
    expect(res.body).toMatchObject({ error: 'outcome_unrecordable' });
    expect(f.calls.create).toHaveLength(0);
    assertNoSecrets(res.body, f.logs);
  });

  it('recordOutcome(processing) refused (state moved under us) → 409, no createRefund', async () => {
    const f = fake({ record: (state) => (state === 'processing' ? { status: 'refused', reason: 'terminal' } : undefined) });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(409);
    expect(res.body).toMatchObject({ error: 'outcome_refused', reason: 'terminal' });
    expect(f.calls.create).toHaveLength(0);
  });

  it('provider success then recordOutcome throws → 500 outcome_unrecorded with provider_ref; retry adopts by list without a second POST', async () => {
    // Attempt 1: Stripe says succeeded; the ledger write fails.
    const f1 = fake({ record: (state) => (state === 'succeeded_at_provider' ? new Error('connection reset') : undefined) });
    const r1 = await runRefundExecution(INPUT, f1.deps);
    expect(r1.http).toBe(500);
    expect(r1.body).toMatchObject({ error: 'outcome_unrecorded', state: 'succeeded_at_provider', provider_ref: 're_ours' });
    expect(f1.calls.create).toHaveLength(1);
    expect(f1.alerts.some((a) => a.event === 'ops-refund-execute:outcome-unrecorded')).toBe(true);

    // Attempt 2: the claim reports previously_sent; the handler lists first and adopts.
    const f2 = fake({
      claim: { ...CLAIMED, previously_sent: true, attempt: 2 },
      list: { ok: true, data: [refund({ id: 're_other', metadata: { source: 'dashboard' } }), refund()] },
    });
    const r2 = await runRefundExecution(INPUT, f2.deps);
    expect(r2.http).toBe(200);
    expect(r2.body).toMatchObject({ state: 'succeeded_at_provider', provider_ref: 're_ours' });
    expect(f2.calls.list).toBe(1);
    expect(f2.calls.create).toHaveLength(0);
    expect(f2.calls.record).toHaveLength(1);
    expect(f2.calls.record[0]).toMatchObject({ state: 'succeeded_at_provider', providerRef: 're_ours', result: { adopted_existing_refund: true } });
  });

  it('late callback: recordOutcome returns {refused, terminal} → logged, no throw, 409 outcome_refused', async () => {
    const f = fake({ record: (state) => (state === 'succeeded_at_provider' ? { status: 'refused', reason: 'terminal', state: 'failed' } : undefined) });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(409);
    expect(res.body).toMatchObject({ error: 'outcome_refused', reason: 'terminal', attempted_state: 'succeeded_at_provider', provider_ref: 're_ours' });
    expect(f.logs.some((l) => l.level === 'warn' && l.event === 'ops-refund-execute.outcome_refused')).toBe(true);
  });

  it('a thrown bug still yields a 500 response, never a rejection', async () => {
    const f = fake({ claim: () => { throw new Error('boom sk_test_abc'); } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(500);
    expect(res.body).toMatchObject({ error: 'internal_error' });
    assertNoSecrets(res.body, f.logs, f.alerts);
  });
});

describe('unknown outcome and recovery', () => {
  it('transport error, nothing listed → unknown 502, retry is possible', async () => {
    const f = fake({ create: new Error('fetch failed: Bearer sk_live_ABC'), list: { ok: true, data: [] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(res.body).toMatchObject({ state: 'unknown' });
    expect(f.calls.list).toBe(1);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'unknown', result: { stripe_error_class: 'network' } });
    assertNoSecrets(res.body, f.calls.record, f.logs, f.alerts);
  });

  it('transport error, but the list shows ours → adopted succeeded_at_provider 200', async () => {
    const f = fake({ create: new Error('socket hang up'), list: { ok: true, data: [refund()] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(200);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'succeeded_at_provider', providerRef: 're_ours', result: { resolved_after: 'network', adopted_existing_refund: true } });
  });

  it('transport error and the list itself fails → unknown 502 (we cannot see)', async () => {
    const f = fake({ create: new Error('fetch failed'), list: new Error('fetch failed again') });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'unknown', result: { reconcile: 'list_failed' } });
  });

  it('409 idempotency_key_in_use → list; ours pending → processing 202', async () => {
    const f = fake({
      create: { ok: false, status: 409, data: { error: { code: 'idempotency_key_in_use', message: 'in use' } } },
      list: { ok: true, data: [refund({ status: 'pending' })] },
    });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(202);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'processing', providerRef: 're_ours' });
  });

  it('unknown recorded on attempt 1, attempt 2 (previously_sent) recovers by list-adopt without POST', async () => {
    const f1 = fake({ create: new Error('fetch failed'), list: { ok: true, data: [] } });
    expect((await runRefundExecution(INPUT, f1.deps)).http).toBe(502);

    const f2 = fake({ claim: { ...CLAIMED, previously_sent: true, attempt: 2 }, list: { ok: true, data: [refund()] } });
    const r2 = await runRefundExecution(INPUT, f2.deps);
    expect(r2.http).toBe(200);
    expect(f2.calls.create).toHaveLength(0);
    expect(f2.calls.record.map((r) => r.state)).toEqual(['succeeded_at_provider']);
  });

  it('previously_sent but nothing listed → POST under the same key (replay-or-create-once)', async () => {
    const f = fake({ claim: { ...CLAIMED, previously_sent: true, attempt: 2 }, list: { ok: true, data: [] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(200);
    expect(f.calls.list).toBe(1);
    expect(f.calls.create).toHaveLength(1);
    expect(f.calls.create[0].key).toBe(KEY);
    expect(f.calls.record.map((r) => r.state)).toEqual(['processing', 'succeeded_at_provider']);
    expect(f.calls.record[0].result).toMatchObject({ attempt: 2 });
  });

  it('previously_sent with list failing → unknown 502 and NO POST', async () => {
    const f = fake({ claim: { ...CLAIMED, previously_sent: true }, list: new Error('fetch failed') });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(f.calls.create).toHaveLength(0);
  });

  it('provider_ref recorded but not listed on the intent → unknown 502 and NO POST', async () => {
    const f = fake({ claim: { ...CLAIMED, previously_sent: true, provider_ref: 're_gone' }, list: { ok: true, data: [] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(f.calls.create).toHaveLength(0);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'unknown', result: { reconcile: 'provider_ref_not_listed', prior_provider_ref: 're_gone' } });
  });

  it('adopted refund in requires_action → processing 202, no POST', async () => {
    const f = fake({ claim: { ...CLAIMED, attempt: 2 }, list: { ok: true, data: [refund({ status: 'requires_action' })] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(202);
    expect(f.calls.create).toHaveLength(0);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'processing', result: { needs_action: true } });
  });

  it('adopted refund failed at Stripe → failed 422, no second POST (a new action is required)', async () => {
    const f = fake({ claim: { ...CLAIMED, previously_sent: true }, list: { ok: true, data: [refund({ status: 'failed', failure_reason: 'expired_or_canceled_card' })] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(f.calls.create).toHaveLength(0);
  });
});

describe('adoption identity — never mark success on a refund whose facts differ', () => {
  it.each<[string, Partial<StripeRefundObject>]>([
    ['amount', { amount: 4999 }],
    ['payment_intent', { payment_intent: 'pi_someoneElse' }],
    ['currency', { currency: 'eur' }],
  ])('retry list: a refund with our metadata but a different %s → unknown 502, no success, no POST over it', async (_label, over) => {
    const f = fake({ claim: { ...CLAIMED, previously_sent: true }, list: { ok: true, data: [refund(over)] } });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(502);
    expect(res.body).not.toHaveProperty('provider_ref');
    expect(f.calls.create).toHaveLength(0);
    expect(f.calls.record.some((r) => r.state === 'succeeded_at_provider')).toBe(false);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'unknown', providerRef: null });
    expect(lastRecord(f.calls).result).toHaveProperty('mismatch');
  });

  it.each<[string, Partial<StripeRefundObject>]>([
    ['foreign action id', { id: 're_foreign', metadata: { ops_action_id: '99999999-2222-4333-8444-555555555555' } }],
    ['missing metadata', { id: 're_dash', metadata: {} }],
  ])('retry list: a refund with %s is NOT adopted (identical facts notwithstanding); the POST replays under our own key', async (_label, over) => {
    // The listed refund matches PI/amount/currency exactly but is not ours.
    // It must be ignored: the handler falls through to the idempotent POST,
    // and the outcome comes from THAT object (here: pending), never from the
    // foreign one.
    const f = fake({
      claim: { ...CLAIMED, previously_sent: true },
      list: { ok: true, data: [refund(over)] },
      create: { ok: true, status: 200, data: refund({ status: 'pending' }) },
    });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(f.calls.list).toBe(1);
    expect(f.calls.create).toHaveLength(1);
    expect(f.calls.create[0].key).toBe(KEY);
    expect(res.http).toBe(202);
    expect(res.body).toMatchObject({ state: 'processing', provider_ref: 're_ours' });
    expect(f.calls.record.some((r) => r.providerRef === over.id)).toBe(false);
    expect(f.calls.record.some((r) => r.state === 'succeeded_at_provider')).toBe(false);
  });

  it('charge_already_refunded with a validated refund of ours → adopted', async () => {
    const f = fake({
      create: { ok: false, status: 400, data: { error: { type: 'invalid_request_error', code: 'charge_already_refunded', message: 'already refunded' } } },
      list: { ok: true, data: [refund()] },
    });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(200);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'succeeded_at_provider', providerRef: 're_ours' });
  });

  it('charge_already_refunded by another route (no refund with our metadata) → failed 422, nothing adopted', async () => {
    const f = fake({
      create: { ok: false, status: 400, data: { error: { type: 'invalid_request_error', code: 'charge_already_refunded', message: 'already refunded' } } },
      list: { ok: true, data: [refund({ id: 're_dash', metadata: { source: 'dashboard' } })] },
    });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(res.body).not.toHaveProperty('provider_ref');
    expect(lastRecord(f.calls)).toMatchObject({ state: 'failed', providerRef: null, result: { stripe_error_class: 'charge_already_refunded' } });
  });

  it('definite 4xx → failed 422 with a redacted message', async () => {
    const f = fake({
      create: { ok: false, status: 400, data: { error: { type: 'invalid_request_error', code: 'amount_too_large', message: 'Refund amount exceeds; key sk_live_ABC123' } } },
    });
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(422);
    expect(f.calls.list).toBe(0);
    expect(lastRecord(f.calls)).toMatchObject({ state: 'failed', result: { stripe_error_code: 'amount_too_large' } });
    assertNoSecrets(res.body, f.calls.record, f.logs, f.alerts);
  });
});

describe('mode guard — required on BOTH sides before any Stripe call (incl. the reconciliation list)', () => {
  type Case = { name: string; keyMode: unknown; rowMode: unknown; code: string };
  const invalid: Case[] = [
    { name: 'missing key mode (undefined)', keyMode: undefined, rowMode: false, code: 'key_mode_unknown' },
    { name: 'null key mode', keyMode: null, rowMode: false, code: 'key_mode_unknown' },
    { name: 'malformed key mode', keyMode: 'sandbox', rowMode: false, code: 'key_mode_unknown' },
    { name: 'missing payment mode (field absent)', keyMode: 'test', rowMode: undefined, code: 'row_mode_unclassified' },
    { name: 'null payment mode', keyMode: 'test', rowMode: null, code: 'row_mode_unclassified' },
    { name: 'malformed payment mode (string)', keyMode: 'test', rowMode: 'true', code: 'row_mode_unclassified' },
    { name: 'live key on a test row', keyMode: 'live', rowMode: false, code: 'cross_mode' },
    { name: 'test key on a live row', keyMode: 'test', rowMode: true, code: 'cross_mode' },
  ];
  for (const c of invalid) {
    it(`${c.name} → failed 422, ZERO Stripe calls (create and list), failure recorded`, async () => {
      const claim: Record<string, unknown> = { ...CLAIMED, previously_sent: true, attempt: 2 }; // would otherwise reconcile-first
      if (c.rowMode === undefined) delete claim.stripe_livemode; else claim.stripe_livemode = c.rowMode;
      const f = fake({ claim: claim as unknown as ClaimedAction });
      (f.deps as unknown as { stripeKeyMode: unknown }).stripeKeyMode = c.keyMode;
      const res = await runRefundExecution(INPUT, f.deps);
      expect(res.http).toBe(422);
      expect(f.calls.create).toHaveLength(0);
      expect(f.calls.list).toBe(0);
      expect(lastRecord(f.calls)).toMatchObject({ state: 'failed', result: { mode_check: c.code } });
      expect(f.calls.record.filter((r) => r.state === 'processing')).toHaveLength(0);
      assertNoSecrets(res.body, f.calls.record, f.logs, f.alerts);
    });
  }

  it('valid live/live → proceeds to Stripe and succeeds', async () => {
    const f = fake({ claim: { ...CLAIMED, stripe_livemode: true } });
    f.deps.stripeKeyMode = 'live';
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(200);
    expect(f.calls.create).toHaveLength(1);
  });

  it('valid test/test → proceeds to Stripe and succeeds', async () => {
    const f = fake({ claim: { ...CLAIMED, stripe_livemode: false } });
    f.deps.stripeKeyMode = 'test';
    const res = await runRefundExecution(INPUT, f.deps);
    expect(res.http).toBe(200);
    expect(f.calls.create).toHaveLength(1);
  });
});
