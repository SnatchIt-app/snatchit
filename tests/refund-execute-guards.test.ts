/**
 * tests/refund-execute-guards.test.ts — the REAL refund-execute handler
 * (supabase/functions/refund-execute/index.ts) driven through tests/helpers/edge-vm.ts.
 *
 * tests/refund-executor.test.ts exercises the pure decisions in executor.ts and
 * a hand-written copy of the sequencing; nothing there loads index.ts, so the
 * auth gate and the mode an action runs in were never under test. These cases
 * load the genuine handler with a mocked Supabase (a faithful
 * kernel.mark_refund_state, 085:1737-1789) and a Stripe mock that REMEMBERS
 * refunds but FORGETS idempotency keys on demand (Stripe keeps a key's result
 * for 24 hours; 093:1255-1274).
 *
 *   G  refunds-3 — `action: execute` requires a platform operator at aal2,
 *      decided by ops.whoami() run as the caller, and refuses everyone else
 *      before any refund is read, without naming a refund, order, amount or ref.
 *   X  refunds-1 — `action: execute` never creates blind: it lists the
 *      PaymentIntent's refunds for metadata.refund_id before any POST, so a
 *      retry after Stripe forgot the key records the first refund instead of
 *      minting a second. A refund_state_backwards that carries a DIFFERENT ref
 *      is a second real refund, and pages instead of passing as a converged race.
 *
 * Nothing here talks to a network, a database or a real Stripe key.
 */
import { describe, expect, it } from 'vitest';
import { planRefund } from '../supabase/functions/refund-execute/executor';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type StripeCall } from './helpers/edge-vm';

// ── fixtures (a hex letter in every uuid group) ─────────────────────────────

const REFUND = 'aaaa1111-bbbb-4ccc-8ddd-eeee11112222';
const PAYMENT = 'aaaa2222-bbbb-4ccc-8ddd-eeee22223333';
const ORDER = 'aaaa3333-bbbb-4ccc-8ddd-eeee33334444';
const OTHER_ORDER = 'aaaa4444-bbbb-4ccc-8ddd-eeee44445555';
const OPERATOR = 'aaaa5555-bbbb-4ccc-8ddd-eeee55556666';
const VENUE_OWNER = 'aaaa6666-bbbb-4ccc-8ddd-eeee66667777';
const PI = 'pi_guardsTestA1';
const AMOUNT = 4000;          // a partial, one-ticket refund on an 11000 payment
const TOTAL = 11000;

const ENV = {
  SUPABASE_URL: 'https://x.invalid',
  SUPABASE_ANON_KEY: 'anon-test',
  SUPABASE_SERVICE_ROLE_KEY: 'service-test',
  INTERNAL_CRON_SECRET: 'cron-test-only',
};

// ── Stripe: refunds persist, idempotency keys can be forgotten ──────────────

interface StripeRefund { id: string; object: 'refund'; status: string; amount: number; payment_intent: string; metadata: Record<string, string> }

class StripeWithMemory {
  refunds: StripeRefund[] = [];
  private byKey = new Map<string, { id: string; body: string }>();
  /** The next POST is CREATED server-side, then the response is lost (transport throw). */
  loseNextResponse = false;
  /** Runs at the start of every POST /refunds — used to interleave a concurrent actor. */
  onPost: (() => void) | null = null;

  /** Stripe's 24h idempotency retention has elapsed: every key is a fresh key again. */
  forgetKeys() { this.byKey.clear(); }
  refundedOn(pi: string) { return this.refunds.filter((r) => r.payment_intent === pi).reduce((s, r) => s + r.amount, 0); }

  route = (c: StripeCall) => {
    if (c.method === 'POST' && c.path === '/refunds') {
      this.onPost?.();
      const body = c.body as Record<string, string>;
      const serialized = JSON.stringify(body);
      const hit = c.idempotencyKey ? this.byKey.get(c.idempotencyKey) : undefined;
      let obj: StripeRefund;
      if (hit) {
        if (hit.body !== serialized) return { ok: false, status: 400, data: { error: { type: 'invalid_request_error', code: 'idempotency_error' } } };
        obj = this.refunds.find((r) => r.id === hit.id)!;     // replay inside the window: the ORIGINAL object
      } else {
        const metadata: Record<string, string> = {};
        for (const [k, v] of Object.entries(body)) {
          const m = /^metadata\[(.+)\]$/.exec(k);
          if (m) metadata[m[1]] = v;
        }
        obj = { id: `re_${this.refunds.length + 1}`, object: 'refund', status: 'succeeded', amount: Number(body.amount), payment_intent: body.payment_intent, metadata };
        this.refunds.push(obj);
        if (c.idempotencyKey) this.byKey.set(c.idempotencyKey, { id: obj.id, body: serialized });
      }
      if (this.loseNextResponse) {
        this.loseNextResponse = false;
        throw new Error('network timeout: response lost after Stripe created the refund');
      }
      return { ok: true, data: obj };
    }
    const list = /^\/refunds\?payment_intent=([^&]+)&limit=100$/.exec(c.path);
    if (c.method === 'GET' && list) {
      const pi = decodeURIComponent(list[1]);
      return { ok: true, data: { object: 'list', data: this.refunds.filter((r) => r.payment_intent === pi), has_more: false } };
    }
    const one = /^\/refunds\/(re_[A-Za-z0-9]+)$/.exec(c.path);
    if (c.method === 'GET' && one) {
      const r = this.refunds.find((x) => x.id === one[1]);
      return r ? { ok: true, data: r } : { ok: false, status: 404, data: { error: { code: 'resource_missing' } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  };
}

// ── kernel.refund + mark_refund_state (faithful port of 085:1737-1789) ──────

interface Row { status: 'pending' | 'submitted' | 'succeeded' | 'failed'; stripe_refund_ref: string | null }

class Kernel {
  row: Row = { status: 'pending', stripe_refund_ref: null };
  /** When set, the NEXT get_refund_execution_context returns THIS once (a read taken before a concurrent write). */
  staleNextContext: Row | null = null;

  context(refundId: string) {
    if (refundId !== REFUND) return null;           // 093: unknown id ⇒ SQL NULL
    const r = this.staleNextContext ?? this.row;
    this.staleNextContext = null;
    return {
      refund_id: REFUND, payment_id: PAYMENT, order_id: ORDER, sale_id: null,
      amount_minor: AMOUNT, currency: 'USD', reason_code: 'buyer_request',
      status: r.status, stripe_refund_ref: r.stripe_refund_ref,
      payment_total_minor: TOTAL, payment_status: 'succeeded',
      stripe_payment_intent_id: PI, stripe_livemode: true,
      prior_non_failed_minor: 0, disputed_minor: 0,
    };
  }

  mark(newStatus: string, ref: string | null, failureCode: string | null): Record<string, unknown> {
    const row = this.row;
    if (row.status === newStatus && (ref === null || row.stripe_refund_ref === ref)) return { status: 'noop_replay' };
    const forward = (row.status === 'pending' && newStatus === 'submitted')
      || (row.status === 'submitted' && (newStatus === 'succeeded' || newStatus === 'failed'));
    if (!forward) throw new Error(`precondition_failed: refund_state_backwards (${row.status} → ${newStatus})`);
    if (ref === null) throw new Error('invalid_input: stripe_refund_ref is mandatory (non-pending rows carry it)');
    if (row.stripe_refund_ref !== null && row.stripe_refund_ref !== ref) throw new Error('conflict_locked: stripe_refund_ref is write-once');
    if (newStatus === 'failed' && !failureCode) throw new Error('invalid_input: failure_code is mandatory for failed');
    row.status = newStatus as Row['status'];
    row.stripe_refund_ref = row.stripe_refund_ref ?? ref;
    return { status: 'ok' };
  }
}

// ── harness ─────────────────────────────────────────────────────────────────

type WhoAmI = { data?: unknown; error?: { message: string; code?: string } };
const OPERATOR_AAL2: WhoAmI = { data: { user_id: OPERATOR, role: 'platform_admin', aal: 'aal2', email_masked: 'o***@x.invalid' } };
const NOT_AN_OPERATOR: WhoAmI = { error: { message: 'insufficient_privilege: operator role required', code: '42501' } };

async function harness(opts: { user?: string; whoami?: WhoAmI; claim?: unknown[] } = {}) {
  const stripe = new StripeWithMemory();
  const transport = mockStripe(stripe.route);
  const kernel = new Kernel();
  const sb = mockSupabase({
    user: { id: opts.user ?? OPERATOR },
    rpc: async (name, params) => {
      if (name === 'whoami') return opts.whoami ?? OPERATOR_AAL2;
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'get_refund_execution_context') return { data: kernel.context(params.p_refund_id as string) };
      if (name === 'mark_refund_state') {
        try {
          return { data: kernel.mark(params.p_new_status as string, params.p_stripe_refund_ref as string | null, params.p_failure_code as string | null) };
        } catch (err) {
          return { data: null, error: { message: (err as Error).message } };
        }
      }
      if (name === 'claim_refunds_for_execution') return { data: { refunds: opts.claim ?? [] } };
      return { data: null, error: { message: `unmocked rpc ${name}` } };
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/refund-execute/index.ts', {
    supabase: sb,
    env: ENV,
    // `exports`: index.ts ends with `export { buildRefundIdempotencyKey, executeOne }`
    // (index.ts:846), which the loader's module-less transpile turns into
    // `exports.x = …`; an empty sink keeps the genuine file loadable unchanged.
    provide: { stripeFetchRaw: transport.stripeFetchRaw, exports: {} },
  });
  const execute = async (body: Record<string, unknown> = {}, token = 'user-session-jwt') => {
    const res = await edge.handler(authedJsonRequest({ action: 'execute', refund_id: REFUND, ...body }, { token }));
    return { status: res.status, body: await json(res) };
  };
  const sweep = async () => {
    const res = await edge.handler(authedJsonRequest({ action: 'sweep' }, { token: ENV.INTERNAL_CRON_SECRET }));
    return { status: res.status, body: await json(res) };
  };
  const calls = () => transport.calls.map((c) => `${c.method} ${c.path.split('?')[0]}`);
  const rpcNames = () => sb.rpcs.map((r) => r.name);
  return { stripe, transport, kernel, sb, edge, execute, sweep, calls, rpcNames };
}

/** Every case transpiles and loads the genuine handler; on a loaded machine that alone can pass vitest's 5s default. */
const LOAD_BUDGET_MS = 30_000;

/** Nothing that identifies the refund, its order, its payment or its money. */
function expectNoLeak(body: Record<string, unknown>) {
  const text = JSON.stringify(body);
  for (const secretish of [REFUND, ORDER, PAYMENT, PI, String(AMOUNT), String(TOTAL), 're_']) {
    expect(text).not.toContain(secretish);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// G — refunds-3: who may drive the money leg
// ════════════════════════════════════════════════════════════════════════════

describe('G: action:execute is a platform-operator-at-aal2 action, decided in the database', { timeout: LOAD_BUDGET_MS }, () => {
  it('G1 a venue org_owner session holding a refund id is refused before any refund is read or any Stripe call', async () => {
    const h = await harness({ user: VENUE_OWNER, whoami: NOT_AN_OPERATOR });
    const r = await h.execute({ expected_order_id: ORDER });
    expect(r.status).toBe(403);
    expect(r.body.error).toBe('forbidden');
    expectNoLeak(r.body);
    expect(h.transport.calls).toHaveLength(0);
    expect(h.rpcNames()).not.toContain('get_refund_execution_context');
    expect(h.rpcNames()).not.toContain('mark_refund_state');
    expect(h.kernel.row).toEqual({ status: 'pending', stripe_refund_ref: null });
    // The decision is the DATABASE's, made as the caller: ops.whoami on the
    // `ops` schema, through a client carrying the caller's own JWT.
    expect(h.sb.rpcs.find((x) => x.name === 'whoami')?.schema).toBe('ops');
    expect(h.sb.clients.some((c) => c.key === ENV.SUPABASE_ANON_KEY && c.authHeader === 'Bearer user-session-jwt')).toBe(true);
  });

  it('G2 a platform operator on an aal1 session is refused with step_up_required, nothing executed', async () => {
    const h = await harness({ whoami: { data: { user_id: OPERATOR, role: 'platform_admin', aal: 'aal1' } } });
    const r = await h.execute();
    expect(r.status).toBe(403);
    expect(r.body.error).toBe('forbidden');
    expect(String(r.body.detail)).toMatch(/step_up_required/);
    expectNoLeak(r.body);
    expect(h.transport.calls).toHaveLength(0);
    expect(h.rpcNames()).not.toContain('get_refund_execution_context');
  });

  it('G3 a whoami answer for a DIFFERENT user than the verified token is refused', async () => {
    const h = await harness({ user: VENUE_OWNER, whoami: OPERATOR_AAL2 });
    const r = await h.execute();
    expect(r.status).toBe(403);
    expectNoLeak(r.body);
    expect(h.transport.calls).toHaveLength(0);
  });

  it('G4 a role outside the platform set is refused even at aal2 (fail closed on anything unexpected)', async () => {
    const h = await harness({ whoami: { data: { user_id: OPERATOR, role: 'org_owner', aal: 'aal2' } } });
    const r = await h.execute();
    expect(r.status).toBe(403);
    expectNoLeak(r.body);
    expect(h.transport.calls).toHaveLength(0);
  });

  it('G5 control: a platform operator at aal2 executes the refund', async () => {
    const h = await harness();
    const r = await h.execute({ expected_order_id: ORDER });
    expect(r.status).toBe(200);
    expect(r.body.status).toBe('succeeded');
    expect(h.stripe.refundedOn(PI)).toBe(AMOUNT);
    expect(h.kernel.row).toEqual({ status: 'succeeded', stripe_refund_ref: 're_1' });
  });
});

// ════════════════════════════════════════════════════════════════════════════
// X — refunds-1: execute never creates blind after an unknown prior outcome
// ════════════════════════════════════════════════════════════════════════════

describe('X: action:execute establishes what exists at Stripe before it may create', { timeout: LOAD_BUDGET_MS }, () => {
  it('X1 lost response, then Stripe forgets the key, then the operator retries: ONE refund, recorded — never a second', async () => {
    const h = await harness();
    h.stripe.loseNextResponse = true;
    const first = await h.execute();
    expect(first.body.status).toBe('stripe_error');
    expect(first.body.retryable).toBe(true);                 // the response invites the retry
    expect(h.kernel.row).toEqual({ status: 'pending', stripe_refund_ref: null });
    expect(h.stripe.refunds).toHaveLength(1);                // …but Stripe DID create re_1

    h.stripe.forgetKeys();                                   // 25 hours later
    const retry = await h.execute();
    expect(h.stripe.refunds).toHaveLength(1);
    expect(h.stripe.refundedOn(PI)).toBe(AMOUNT);            // 4000, not 8000
    expect(retry.status).toBe(200);
    expect(retry.body.status).toBe('succeeded');
    expect(retry.body.stripe_refund_ref).toBe('re_1');
    expect(h.kernel.row).toEqual({ status: 'succeeded', stripe_refund_ref: 're_1' });
  });

  it('X2 a fresh row: the PaymentIntent is listed BEFORE the one POST, which still goes out under refund_<refund_id>', async () => {
    const h = await harness();
    const r = await h.execute();
    expect(r.body.status).toBe('succeeded');
    expect(h.calls()).toEqual(['GET /refunds', 'POST /refunds']);
    const post = h.transport.calls[1];
    expect(post.idempotencyKey).toBe(`refund_${REFUND}`);
    expect((post.body as Record<string, string>)['metadata[refund_id]']).toBe(REFUND);
    expect((post.body as Record<string, string>)['payment_intent']).toBe(PI);
  });

  it('X3 the caller\'s expected_order_id is still enforced: a mismatch is refused with NO Stripe call at all', async () => {
    const h = await harness();
    const r = await h.execute({ expected_order_id: OTHER_ORDER });
    expect(r.status).toBe(409);
    expect(r.body.code).toBe('binding_order_mismatch');
    expect(h.transport.calls).toHaveLength(0);
    expect(h.kernel.row).toEqual({ status: 'pending', stripe_refund_ref: null });
  });

  it('X6 the order assertion is checked BEFORE reconcile reads Stripe, on a submitted row too (which reconcile would fetch)', async () => {
    const h = await harness();
    h.stripe.refunds.push({ id: 're_1', object: 'refund', status: 'succeeded', amount: AMOUNT, payment_intent: PI, metadata: { refund_id: REFUND } });
    h.kernel.row = { status: 'submitted', stripe_refund_ref: 're_1' };
    const r = await h.execute({ expected_order_id: OTHER_ORDER });
    expect(r.status).toBe(409);
    expect(r.body.code).toBe('binding_order_mismatch');
    expect(h.transport.calls).toHaveLength(0);
    expect(h.kernel.row).toEqual({ status: 'submitted', stripe_refund_ref: 're_1' });
  });

  it('X7 a submitted row is finished from its own ref (GET), never POSTed', async () => {
    const h = await harness();
    h.stripe.refunds.push({ id: 're_1', object: 'refund', status: 'succeeded', amount: AMOUNT, payment_intent: PI, metadata: { refund_id: REFUND } });
    h.kernel.row = { status: 'submitted', stripe_refund_ref: 're_1' };
    const r = await h.execute({ expected_order_id: ORDER });
    expect(h.transport.calls.filter((c) => c.method === 'POST')).toHaveLength(0);
    expect(r.body.stripe_refund_ref).toBe('re_1');
    expect(h.stripe.refunds).toHaveLength(1);
  });

  it('X4 a refund_state_backwards carrying a DIFFERENT ref is a second real refund: it pages, never "converged"', async () => {
    // The residual the edge cannot close (needs SQL): the sweep obeys a
    // DB-issued 'create' for a row whose key was first used by an earlier
    // execute (no refund.execute_claim row, 093:1347-1356) and Stripe has
    // since forgotten. Meanwhile a concurrent reconcile recorded re_1. The
    // sweep's POST mints re_2 and mark_refund_state(submitted, re_2) raises
    // refund_state_backwards BEFORE its write-once check (085:1761-1769).
    const h = await harness({
      claim: [{ refund_id: REFUND, created_at: '2026-10-01T00:00:00Z', status: 'pending', execution_mode: 'create', attempt: 1, command_key: `refund.execute:${REFUND}` }],
    });
    h.stripe.refunds.push({ id: 're_1', object: 'refund', status: 'succeeded', amount: AMOUNT, payment_intent: PI, metadata: { refund_id: REFUND } });
    h.kernel.staleNextContext = { status: 'pending', stripe_refund_ref: null };
    h.stripe.onPost = () => { h.kernel.row = { status: 'submitted', stripe_refund_ref: 're_1' }; };

    const r = await h.sweep();
    const result = (r.body.results as Array<Record<string, unknown>>)[0];
    expect(result.outcome).not.toBe('noop_replay');
    expect(result.code).toBe('state_sync_conflict');
    expect(result.retryable).toBe(false);
    const page = h.edge.sentry.find((s) => s.tag === 'refund-execute:state-sync');
    expect(page).toBeDefined();
    expect(page!.ctx).toMatchObject({ refund_id: REFUND, stripe_refund_ref: 're_2', recorded_stripe_refund_ref: 're_1' });
  });

  it('X5 control: a benign race on the SAME ref (another worker already advanced it) still converges silently', async () => {
    const h = await harness({
      claim: [{ refund_id: REFUND, created_at: '2026-10-01T00:00:00Z', status: 'pending', execution_mode: 'create', attempt: 1, command_key: `refund.execute:${REFUND}` }],
    });
    // Another worker POSTed under the SAME key inside Stripe's window and
    // recorded re_1 all the way to succeeded after our context read.
    const plan = planRefund(h.kernel.context(REFUND)!);
    if (plan.kind !== 'stripe_create') throw new Error('fixture: expected a create plan');
    await h.stripe.route({ method: 'POST', path: '/refunds', body: plan.body, idempotencyKey: plan.idempotency_key });
    h.kernel.row = { status: 'succeeded', stripe_refund_ref: 're_1' };
    h.kernel.staleNextContext = { status: 'pending', stripe_refund_ref: null };

    const r = await h.sweep();                               // replays refund_<id> → Stripe returns re_1
    const result = (r.body.results as Array<Record<string, unknown>>)[0];
    expect(h.stripe.refunds).toHaveLength(1);
    expect(result.outcome).toBe('noop_replay');
    expect(result.code).toBe('converged_elsewhere');
    expect(h.edge.sentry.filter((s) => s.tag === 'refund-execute:state-sync')).toHaveLength(0);
  });
});
