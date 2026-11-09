/**
 * tests/primary-lapse-canceller.test.ts — registry 198, A-6 (A, 2026-11-02).
 * Contract: DESIGN-198-FINAL §4.2 A-6 steps 1-4, §3.3 (the sweep's report
 * mode), §5 scenarios 5 / 9 / 13 / 14 / 19, races R3 / R9, O11 / O13.
 *
 * Loads the REAL primary-lapse-canceller handler (tests/helpers/edge-vm.ts).
 * Its `../primary-checkout/order-pis.ts` import is not a sibling, so it is
 * provided here FROM THE REAL MODULE — never a stub.
 *
 * The sweep fake models 198's report mode as D designed it (the SQL is not
 * merged): `sweep_expired_inventory_holds(p_limit => 0)` writes nothing and
 * returns the four 081 keys plus `skipped_busy` and `lapsed_orders[]`
 * ({order_id, buyer_id, event_session_id, total_minor, currency, lapsed_at,
 * lapse}); any other p_limit returns `lapsed_orders: null`. The pre-198 body
 * returns the four keys only.
 * No network, no database, no real key.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { cancelLapsedOrderPaymentIntents } from '../supabase/functions/primary-checkout/order-pis';
import { buildCancelCommandKey } from '../supabase/functions/stripe-webhook/native';

const SERVICE_KEY = 'service-test';
const CRON_SECRET = 'cron-secret-test';
const ENV: Record<string, string | undefined> = {
  SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: SERVICE_KEY, INTERNAL_CRON_SECRET: CRON_SECRET,
};

// Synthetic uuids: version 4, variant 8-b, a hex letter in every group.
const SESSION       = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
const OTHER_SESSION = 'f1e2d3c4-b5a6-4f7e-9d8c-7b6a5f4e3d2c';
const ORG           = 'd4e5f6a7-b8c9-4dae-bf12-3b4c5d6e7f8a';
const BUYER         = 'e5f6a7b8-c9d0-4eab-8c12-4c5d6e7f8a9b';
const orderUuid = (n: number) => `aaaa${String(n).padStart(4, '0')}-bbbb-4ccc-8ddd-eeee${String(n).padStart(8, '0')}`;
const FACE = 2500;
const CHARGE = 2800;

interface PayRow { buyer_id: string; mode: string; amount: number; buyer_fee: number; total: number; status: string; stripe_payment_intent_id: string; created_at: string }
interface Pi { id: string; amount: number; currency: string; client_secret: string; status: string; metadata: Record<string, string> }
interface ReviewRow { payment_id: null; listing_id: null; rpc_name: string; error_message: string; resolved: boolean }

type Lapsed = Record<string, unknown>;
const lapsed = (n: number, over: Lapsed = {}): Lapsed => ({
  order_id: orderUuid(n), buyer_id: BUYER, event_session_id: SESSION, total_minor: FACE, currency: 'USD',
  lapsed_at: '2026-11-02T10:00:00.123456+00:00', lapse: 'expired', ...over,
});

interface WorldOpts {
  /** the lapse report; undefined → the pre-198 body (no lapsed_orders key) */
  report?: Lapsed[];
  sweepError?: { message: string; code?: string };
  /** GET on these PI ids answers this status */
  probeFails?: Record<string, number>;
  /** POST /payment_intents/{id}/cancel on these PI ids answers this status */
  cancelFails?: Record<string, number>;
  cancelBodies?: Record<string, unknown>;
  attemptReadError?: boolean;
  binding?: 'missing-rpc' | 'missing' | 'wrong-pi' | 'wrong-quote' | 'unsafe-state';
}

function matches(row: Record<string, unknown>, f: [string, ...unknown[]]): boolean {
  const [op, col, val] = f as [string, string, unknown];
  if (op === 'eq') return row[col] === val;
  if (op === 'in') return (val as unknown[]).includes(row[col]);
  throw new Error(`fake: unmodelled filter ${op}`);
}

async function world(opts: WorldOpts = {}) {
  let clock = Date.parse('2026-11-02T09:00:00Z');
  const tick = () => new Date((clock += 60_000)).toISOString();
  const rows: PayRow[] = [];
  const pis = new Map<string, Pi>();
  const attempts: Array<Record<string, unknown>> = [];
  const reviews: ReviewRow[] = [];
  /** null → marker reads work; 'error' → the read answers an error; 'throw' → it rejects */
  let markerReads: null | 'error' | 'throw' = null;
  const setMarkerReads = (mode: null | 'error' | 'throw') => { markerReads = mode; };

  /** a PI minted for order n (metadata exactly as primary-checkout writes it) and its payments row */
  const addPi = (n: number, piStatus: string, o: { rowStatus?: string; session?: string; metaOrder?: string; face?: number; orphan?: boolean } = {}) => {
    const id = `pi_test_lapse_${pis.size + 1}`;
    pis.set(id, {
      id, amount: CHARGE, currency: 'usd', client_secret: `${id}_secret_x`, status: piStatus,
      metadata: {
        rail: 'native_primary', mode: 'native_primary', order_id: o.metaOrder ?? orderUuid(n), buyer_id: BUYER,
        org_id: ORG, session_id: o.session ?? SESSION,
      },
    });
    if (o.orphan) {
      attempts.push({
        order_id: orderUuid(n), buyer_id: BUYER, session_id: SESSION, pi_id: id,
        state: 'open', face_minor: FACE, buyer_fee_minor: CHARGE - FACE, amount_minor: CHARGE, currency: 'USD',
      });
    } else {
      rows.push({
        buyer_id: BUYER, mode: 'native_primary', amount: o.face ?? FACE, buyer_fee: CHARGE - FACE, total: CHARGE,
        status: o.rowStatus ?? (piStatus === 'succeeded' ? 'succeeded' : 'pending'), stripe_payment_intent_id: id, created_at: tick(),
      });
    }
    return id;
  };

  const sb = mockSupabase({
    rpc: (name, params, schema) => {
      if (name === 'sweep_expired_inventory_holds') {
        if (opts.sweepError) return { error: opts.sweepError };
        const base = { swept: 0, released_qty: 0, batches_touched: 0, errors: 0 };
        if (opts.report === undefined) return { data: base };
        return { data: { ...base, skipped_busy: 0, lapsed_orders: params.p_limit === 0 ? opts.report : null } };
      }
      if (name === 'read_lapse_payment_attempts') {
        expect(schema).toBe('venue');
        return opts.attemptReadError
          ? { error: { code: 'PGRST202', message: 'function not found' } }
          : { data: attempts.filter((a) => a.order_id === params.p_order_id) };
      }
      if (name === 'mark_payment_attempt_by_pi') {
        const attempt = attempts.find((a) => a.pi_id === params.p_pi_id);
        if (attempt) attempt.state = params.p_state;
        return { data: { attempt_id: `att_${String(params.p_pi_id)}`, state: params.p_state, pi_id: params.p_pi_id } };
      }
      if (name === 'read_payment_attempt_binding') {
        if (opts.binding === 'missing-rpc') return { error: { code: 'PGRST202', message: 'function not found' } };
        if (opts.binding === 'missing') return { data: null };
        const row = rows.find((r) => r.stripe_payment_intent_id === params.p_pi_id);
        const attempt = attempts.find((a) => a.pi_id === params.p_pi_id);
        return { data: {
          attempt_id: 'attempt-fixture', order_id: params.p_order_id,
          buyer_id: params.p_buyer_id, session_id: params.p_session_id,
          pi_id: opts.binding === 'wrong-pi' ? 'pi_other' : params.p_pi_id,
          state: opts.binding === 'unsafe-state' ? 'processing' : row?.status === 'failed' ? 'failed' : 'open',
          face_minor: row?.amount ?? attempt?.face_minor, buyer_fee_minor: row?.buyer_fee ?? attempt?.buyer_fee_minor,
          amount_minor: opts.binding === 'wrong-quote' ? CHARGE + 1 : row?.total ?? attempt?.amount_minor, currency: 'USD',
        } };
      }
      if (name === 'cancel_pending_order') {
        expect(schema).toBe('venue');
        return { data: { status: 'cancelled', order_id: params.p_order_id } };
      }
      return { error: { message: `unmocked rpc ${name}` } };
    },
    tables: {
      payments: (q: QueryCall) => {
        if (q.op !== 'select') return { error: { message: `payments fake: unmodelled op ${q.op}` } };
        let out = rows.filter((r) => q.filters.every((f) => matches(r as unknown as Record<string, unknown>, f)));
        for (const [col, o] of [...q.order].reverse()) {
          const asc = (o as { ascending?: boolean } | undefined)?.ascending !== false;
          out = [...out].sort((x, y) => {
            const a = String((x as unknown as Record<string, unknown>)[col]); const b = String((y as unknown as Record<string, unknown>)[col]);
            return a < b ? (asc ? -1 : 1) : a > b ? (asc ? 1 : -1) : 0;
          });
        }
        if (q.limit !== null) out = out.slice(0, q.limit);
        return { data: out.map((r) => ({ ...r })) };
      },
      webhook_retries: (q: QueryCall) => {
        if (q.op === 'insert') { reviews.push(q.body as ReviewRow); return { data: null }; }
        if (q.op === 'select') {
          if (markerReads === 'error') return { error: { message: 'webhook_retries fake: read refused', code: '57014' } };
          if (markerReads === 'throw') throw new Error('webhook_retries fake: connection reset');
          const out = reviews.filter((r) => q.filters.every((f) => matches(r as unknown as Record<string, unknown>, f)));
          return { data: (q.limit !== null ? out.slice(0, q.limit) : out).map(() => ({ id: 'wr_1' })) };
        }
        return { error: { message: `webhook_retries fake: unmodelled op ${q.op}` } };
      },
    },
  });

  let cancelBodies: Record<string, unknown> | undefined;
  const stripe = mockStripe(async (c: StripeCall) => {
    const cancelM = c.method === 'POST' ? c.path.match(/^\/payment_intents\/([^/]+)\/cancel$/) : null;
    if (cancelM) {
      const pi = pis.get(cancelM[1]);
      if (!pi) return { ok: false, status: 404, data: { error: { code: 'resource_missing' } } };
      const refused = opts.cancelFails?.[pi.id];
      if (refused) return { ok: false, status: refused, data: { error: { code: 'payment_intent_unexpected_state' } } };
      pi.status = 'canceled';
      if (cancelBodies?.[pi.id] !== undefined) return { ok: true, data: cancelBodies[pi.id] };
      return { ok: true, data: { ...pi } };
    }
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      const id = c.path.split('/')[2];
      const forced = opts.probeFails?.[id];
      if (forced) return { ok: false, status: forced, data: { error: { type: 'api_error' } } };
      const pi = pis.get(id);
      return pi ? { ok: true, data: { ...pi } } : { ok: false, status: 404, data: { error: { code: 'resource_missing' } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });

  const edge = await loadEdgeHandler('supabase/functions/primary-lapse-canceller/index.ts', {
    supabase: sb,
    env: { ...ENV },
    provide: { stripeFetchRaw: stripe.stripeFetchRaw, cancelLapsedOrderPaymentIntents },
  });

  const run = async (bearer: string | null = CRON_SECRET) => {
    const headers: Record<string, string> = { 'content-type': 'application/json' };
    if (bearer !== null) headers.authorization = `Bearer ${bearer}`;
    const res = await edge.handler(new Request('https://edge.test/primary-lapse-canceller', { method: 'POST', body: '{}', headers }));
    return { res, body: await json(res) };
  };
  const piCancels = () => stripe.calls.filter((c) => c.method === 'POST' && /\/cancel$/.test(c.path));
  const orderCancels = () => sb.rpcs.filter((r) => r.name === 'cancel_pending_order');
  const alerts = (needle: string) => edge.sentry.filter((s) => String((s.error as Error).message ?? s.error).includes(needle));

  return { run, addPi, pis, rows, attempts, reviews, sb, stripe, edge, piCancels, orderCancels, alerts, setMarkerReads, setCancelBodies: (b: Record<string, unknown> | undefined) => { cancelBodies = b; } };
}

// ═══════════════════════════════════════════════════════════════════════════

describe('A-6 auth — the internal cron secret, exactly as refund-execute\'s sweep (refund-execute/index.ts:630-633)', () => {
  it.each([
    ['no Authorization header', null],
    ['a wrong bearer', 'not-the-secret'],
    ['an empty bearer', ''],
  ])('%s → 401, and nothing is read or cancelled', async (_label, bearer) => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method');
    const r = await w.run(bearer);
    expect(r.res.status).toBe(401);
    expect(w.sb.rpcs).toEqual([]);
    expect(w.stripe.calls).toEqual([]);
  });

  it.each([
    ['INTERNAL_CRON_SECRET', CRON_SECRET],
    ['the runtime service-role key', SERVICE_KEY],
  ])('%s → runs', async (_label, bearer) => {
    const w = await world({ report: [] });
    const r = await w.run(bearer);
    expect(r.res.status).toBe(200);
  });

  it('an UNSET INTERNAL_CRON_SECRET never matches an empty bearer (the length > 0 guard)', async () => {
    const w = await world({ report: [] });
    const edge = await loadEdgeHandler('supabase/functions/primary-lapse-canceller/index.ts', {
      supabase: w.sb, env: { ...ENV, INTERNAL_CRON_SECRET: undefined, SUPABASE_SERVICE_ROLE_KEY: '' },
      provide: { stripeFetchRaw: w.stripe.stripeFetchRaw, cancelLapsedOrderPaymentIntents },
    });
    const res = await edge.handler(new Request('https://edge.test/x', { method: 'POST', body: '{}', headers: { authorization: 'Bearer ' } }));
    expect(res.status).toBe(401);
  });
});

describe('A-6 step 1 — the report comes from the sweep in REPORT MODE (§3.3, O10)', () => {
  it('calls venue.sweep_expired_inventory_holds with exactly {p_limit: 0} on a service_role venue client, once', async () => {
    const w = await world({ report: [] });
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.sb.rpcs.map((x) => [x.name, x.params, x.schema])).toEqual([['sweep_expired_inventory_holds', { p_limit: 0 }, 'venue']]);
    expect(w.sb.clients.some((c) => c.key === SERVICE_KEY && c.schema === 'venue')).toBe(true);
  });

  it('a sweep WITHOUT lapsed_orders (the pre-198 body) fails closed: 503 lapse_report_unavailable + activation-blocker alert, nothing touched', async () => {
    const w = await world({ report: undefined });
    const r = await w.run();
    expect(r.res.status).toBe(503);
    expect(r.body.error).toBe('lapse_report_unavailable');
    expect(w.edge.sentry.filter((s) => (s.ctx as { activation_blocker?: boolean } | undefined)?.activation_blocker === true)).toHaveLength(1);
    expect(w.stripe.calls).toEqual([]);
  });

  it('a sweep error is a 500 with an alert', async () => {
    const w = await world({ sweepError: { message: 'permission denied for function sweep_expired_inventory_holds', code: '42501' } });
    const r = await w.run();
    expect(r.res.status).toBe(500);
    expect(r.body.error).toBe('sweep_report_failed');
    expect(w.edge.sentry).toHaveLength(1);
  });
});

describe('A-6 steps 2-3 — per lapsed order, act on the PaymentIntent\'s status', () => {
  it.each(['requires_payment_method', 'requires_confirmation', 'requires_action'])(
    '%s → POST cancel, cancellation_reason=abandoned, Idempotency-Key pi_lapse_cancel_{pi}; the webhook writes cancelled (O11)',
    async (status) => {
      const w = await world({ report: [lapsed(1)] });
      const pi = w.addPi(1, status);
      const r = await w.run();
      expect(r.res.status).toBe(200);
      expect(w.piCancels().map((c) => [c.path, c.idempotencyKey, c.body])).toEqual([
        [`/payment_intents/${pi}/cancel`, `pi_lapse_cancel_${pi}`, { cancellation_reason: 'abandoned' }],
      ]);
      expect(w.orderCancels()).toEqual([]);
    },
  );

  it('a declined attempt (payments row failed, PI requires_payment_method, §5 scenario 14) is found and cancelled', async () => {
    const w = await world({ report: [lapsed(1)] });
    const pi = w.addPi(1, 'requires_payment_method', { rowStatus: 'failed' });
    await w.run();
    expect(w.piCancels().map((c) => c.path)).toEqual([`/payment_intents/${pi}/cancel`]);
  });

  it.each(['missing-rpc', 'missing', 'wrong-pi', 'wrong-quote', 'unsafe-state'] as const)(
    'refuses Stripe and order writes when the attempt binding is %s',
    async (binding) => {
      const w = await world({ report: [lapsed(1)], binding });
      const pi = w.addPi(1, 'requires_payment_method');
      const r = await w.run();
      expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'error' }]);
      expect(w.sb.rpcs.find((x) => x.name === 'read_payment_attempt_binding')?.params).toEqual({
        p_order_id: orderUuid(1), p_buyer_id: BUYER, p_session_id: SESSION, p_pi_id: pi,
      });
      expect(w.piCancels()).toEqual([]);
      expect(w.orderCancels()).toEqual([]);
      expect(w.sb.rpcs.some((x) => x.name === 'mark_payment_attempt_by_pi')).toBe(false);
    },
  );

  it('keeps the authorization held when the requires-capture binding RPC is unavailable', async () => {
    const w = await world({ report: [lapsed(1)], binding: 'missing-rpc' });
    w.addPi(1, 'requires_capture');
    const r = await w.run();
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'anomaly' }]);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('recovers an attached attempt with no public payment row and cancels only after Stripe confirms', async () => {
    const w = await world({ report: [lapsed(1)] });
    const id = w.addPi(1, 'requires_payment_method', { orphan: true });
    expect(w.rows).toHaveLength(0);
    const first = await w.run();
    expect(first.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'cancel_requested' }]);
    expect(w.orderCancels()).toEqual([]);
    const second = await w.run();
    expect(second.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'order_cancelled' }]);
    expect(w.piCancels().map((c) => c.path)).toEqual([`/payment_intents/${id}/cancel`]);
    expect(w.orderCancels()).toHaveLength(1);
  });

  it('a succeeded attempt without a payment row protects a visible live sibling', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method');
    w.addPi(1, 'succeeded', { orphan: true });
    const r = await w.run();
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'paid' }]);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('refuses when Stripe returns a different quote for an attached attempt', async () => {
    const w = await world({ report: [lapsed(1)] });
    const id = w.addPi(1, 'requires_payment_method', { orphan: true });
    w.pis.get(id)!.amount += 1;
    const r = await w.run();
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'error' }]);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('also validates Stripe quote when a tracked attempt has a public payment row', async () => {
    const w = await world({ report: [lapsed(1)] });
    const id = w.addPi(1, 'requires_payment_method', { orphan: true });
    w.rows.push({
      buyer_id: BUYER, mode: 'native_primary', amount: FACE, buyer_fee: CHARGE - FACE, total: CHARGE,
      status: 'pending', stripe_payment_intent_id: id, created_at: '2026-11-02T09:00:00Z',
    });
    w.pis.get(id)!.amount += 1;
    const r = await w.run();
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'error' }]);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('keeps the order open and never mints a PI when a stranded attempt has no attached Stripe id', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method', { orphan: true });
    Object.assign(w.attempts[0], { state: 'creating', pi_id: null });
    const r = await w.run();
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'error' }]);
    expect(w.stripe.calls).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('refuses to cancel even a visible payment if the attempt roster cannot be read', async () => {
    const w = await world({ report: [lapsed(1)], attemptReadError: true });
    w.addPi(1, 'requires_payment_method');
    const r = await w.run();
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'error' }]);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('processing → skipped (no cancel, no order write); the next run decides (§5 scenario 19)', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'processing', { rowStatus: 'processing' });
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('succeeded → nothing is cancelled, and lapsed_order_paid is alerted ONCE per order across runs (O13), with a durable review row', async () => {
    const w = await world({ report: [lapsed(1)] });
    const pi = w.addPi(1, 'succeeded');
    await w.run();
    await w.run();
    await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
    const paid = w.alerts('lapsed_order_paid');
    expect(paid).toHaveLength(1);
    expect(paid[0].ctx).toMatchObject({ order_id: orderUuid(1), pi_ids: [pi] });
    expect(w.reviews).toEqual([{
      payment_id: null, listing_id: null, rpc_name: 'primary-lapse-canceller',
      error_message: `lapsed_order_paid:${orderUuid(1)}`, resolved: false,
    }]);
  });

  it('a succeeded PI with a still-live sibling → the sibling is NOT cancelled (its cancel event would cancel the paid order)', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method');
    w.addPi(1, 'succeeded');
    await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.alerts('lapsed_order_paid')).toHaveLength(1);
  });

  it('a PROCESSING PI with a still-live sibling → the sibling is NOT cancelled either (deviation D3: the money may yet win); in_flight, retried next run', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method');
    w.addPi(1, 'processing');
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'in_flight' }]);
  });

  it('canceled while the order is still pending → cancel_pending_order with buildCancelCommandKey(order, pi)', async () => {
    const w = await world({ report: [lapsed(1)] });
    const pi = w.addPi(1, 'canceled', { rowStatus: 'failed' });
    await w.run();
    expect(w.piCancels()).toEqual([]);
    const markIdx = w.sb.rpcs.findIndex((r) => r.name === 'mark_payment_attempt_by_pi');
    const cancelIdx = w.sb.rpcs.findIndex((r) => r.name === 'cancel_pending_order');
    expect(markIdx).toBeGreaterThanOrEqual(0);
    expect(markIdx).toBeLessThan(cancelIdx);
    expect(w.orderCancels().map((c) => c.params)).toEqual([
      { p_order_id: orderUuid(1), p_reason_code: 'payment_failed', p_command_key: buildCancelCommandKey(orderUuid(1), pi) },
    ]);
  });

  // D's ratification, A-6 precedence (D2/D3): cancel_pending_order runs ONLY
  // when no sibling PI of the order is processing, succeeded or
  // requires_capture. The order-level precedence already guarantees it — paid,
  // anomaly and in_flight all return before the cancel_pending_order step —
  // and these pin it.
  it.each([
    ['processing', 'in_flight'],
    ['succeeded', 'paid'],
    ['requires_capture', 'anomaly'],
  ])('a canceled PI with a %s sibling → cancel_pending_order is NOT called (order-level precedence); outcome %s', async (sibling, outcome) => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'canceled', { rowStatus: 'failed' });
    w.addPi(1, sibling);
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.orderCancels()).toEqual([]);
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome }]);
  });

  // D's ratification C2 (A's suggestion A): requires_capture is an anomaly for
  // this automatic-capture rail, AND an authorization held on the buyer's card.
  // It is cancelled under the lapse key to release it, unless a sibling is
  // succeeded or processing (D3); the outcome stays `anomaly`, alerted.
  it('requires_capture → cancelled with pi_lapse_cancel_{pi} (releases the authorization); outcome anomaly, alerted naming order and PI; no order write (the webhook writes cancelled, O11)', async () => {
    const w = await world({ report: [lapsed(1)] });
    const pi = w.addPi(1, 'requires_capture');
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.piCancels().map((c) => [c.path, c.idempotencyKey, c.body])).toEqual([
      [`/payment_intents/${pi}/cancel`, `pi_lapse_cancel_${pi}`, { cancellation_reason: 'abandoned' }],
    ]);
    expect(w.pis.get(pi)!.status).toBe('canceled');
    expect(w.orderCancels()).toEqual([]);
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'anomaly' }]);
    expect(w.alerts('anomaly').map((s) => s.ctx)).toEqual([{ order_id: orderUuid(1), pi_id: pi, authorization: 'released' }]);
  });

  it('requires_capture whose cancel Stripe refuses → anomaly, and the alert says the authorization may still be held; the batch continues', async () => {
    const w = await world({ report: [lapsed(1), lapsed(2, { total_minor: FACE + 500 })], cancelFails: { pi_test_lapse_1: 400 } });
    expect(w.addPi(1, 'requires_capture')).toBe('pi_test_lapse_1');
    const good = w.addPi(2, 'requires_payment_method', { face: FACE + 500 });
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.piCancels().map((c) => c.path)).toEqual(['/payment_intents/pi_test_lapse_1/cancel', `/payment_intents/${good}/cancel`]);
    expect(w.pis.get('pi_test_lapse_1')!.status).toBe('requires_capture');
    expect(r.body.results).toEqual([
      { order_id: orderUuid(1), outcome: 'anomaly' },
      { order_id: orderUuid(2), outcome: 'cancel_requested' },
    ]);
    const [alert] = w.alerts('anomaly');
    expect(alert.ctx).toEqual({ order_id: orderUuid(1), pi_id: 'pi_test_lapse_1', authorization: 'may_still_be_held' });
    expect(String((alert.error as Error).message)).toContain('authorization may still be held');
  });

  it('requires_capture with a PROCESSING sibling → NOT cancelled (D3); anomaly, and the alert says the authorization may still be held', async () => {
    const w = await world({ report: [lapsed(1)] });
    const pi = w.addPi(1, 'requires_capture');
    w.addPi(1, 'processing');
    const r = await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'anomaly' }]);
    const [alert] = w.alerts('anomaly');
    expect(alert.ctx).toEqual({ order_id: orderUuid(1), pi_id: pi, authorization: 'may_still_be_held' });
    expect(String((alert.error as Error).message)).toContain('authorization may still be held');
  });

  it('requires_capture with a SUCCEEDED sibling → NOT cancelled (D3); paid, lapsed_order_paid alerted', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_capture');
    w.addPi(1, 'succeeded');
    const r = await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'paid' }]);
    expect(w.alerts('lapsed_order_paid')).toHaveLength(1);
  });

  it('no PaymentIntent found → A-4\'s default: the order is left alone', async () => {
    const w = await world({ report: [lapsed(1)] });
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.stripe.calls).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
    expect(w.edge.sentry).toEqual([]);
  });

  it('a same-face PI whose metadata names ANOTHER order is not this order\'s: left alone', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method', { metaOrder: orderUuid(77) });
    await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
  });

  it('a PI whose metadata.session_id is not the order\'s session → anomaly: nothing touched, alerted', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method', { session: OTHER_SESSION });
    await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.orderCancels()).toEqual([]);
    expect(w.alerts('session')).toHaveLength(1);
  });

  it('one order\'s Stripe failure never blocks the batch: the next order is still cancelled, and the run reports it once', async () => {
    // addPi numbers PIs in call order, so order 1's PI is pi_test_lapse_1.
    // Order 2 has another face: were both at one face, order 1's unreadable PI
    // would be a candidate for order 2 as well, and the shared search answers
    // "could not look" for it too (primary-checkout-4b, by design).
    const w = await world({ report: [lapsed(1), lapsed(2, { total_minor: FACE + 500 })], probeFails: { pi_test_lapse_1: 503 } });
    expect(w.addPi(1, 'requires_payment_method')).toBe('pi_test_lapse_1');
    const good = w.addPi(2, 'requires_payment_method', { face: FACE + 500 });
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.piCancels().map((c) => c.path)).toEqual([`/payment_intents/${good}/cancel`]);
    expect((r.body.counts as Record<string, number>).error).toBe(1);
    expect(w.alerts('lapse canceller')).toHaveLength(1);
  });

  it('a malformed report entry is skipped as an anomaly and the rest still run', async () => {
    const w = await world({ report: [lapsed(1, { order_id: 'not-a-uuid' }), lapsed(2)] });
    w.addPi(2, 'requires_payment_method');
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.piCancels()).toHaveLength(1);
    expect((r.body.counts as Record<string, number>).anomaly).toBe(1);
  });

  it('never sends buyer_id back (§4.2 A-6 step 4)', async () => {
    const w = await world({ report: [lapsed(1), lapsed(2)] });
    w.addPi(1, 'requires_payment_method');
    const r = await w.run();
    expect(JSON.stringify(r.body)).not.toContain(BUYER);
    expect(r.body.results).toEqual([
      { order_id: orderUuid(1), outcome: 'cancel_requested' },
      { order_id: orderUuid(2), outcome: 'no_pi' },
    ]);
  });
});

// Reviewer E + the round-3 review: an anomaly order stays pending and stays in
// the report on EVERY run (every 1-2 minutes), and Stripe replays a refused
// cancel's cached result for the same Idempotency-Key for ~24h — so an
// unmarked anomaly alert is a pager loop. It gets the paid alert's durable
// once-per-order marker, under its OWN error_message prefix.
describe('A-6 anomaly alert — once per order, the paid alert\'s marker idiom, a distinct marker', () => {
  const anomalyMarker = (n: number) => `lapsed_order_anomaly:${orderUuid(n)}`;
  const paidMarker = (n: number) => `lapsed_order_paid:${orderUuid(n)}`;
  const review = (error_message: string): ReviewRow => ({
    payment_id: null, listing_id: null, rpc_name: 'primary-lapse-canceller', error_message, resolved: false,
  });

  it('two consecutive runs over the same anomaly order (requires_capture, cancel refused and replayed under one key) alert EXACTLY ONCE; the outcome is still reported on both runs', async () => {
    const w = await world({ report: [lapsed(1)], cancelFails: { pi_test_lapse_1: 400 } });
    expect(w.addPi(1, 'requires_capture')).toBe('pi_test_lapse_1');
    const r1 = await w.run();
    const r2 = await w.run();
    // The premise: the same cancel, under the same key, both runs.
    expect(w.piCancels().map((c) => c.idempotencyKey)).toEqual(['pi_lapse_cancel_pi_test_lapse_1', 'pi_lapse_cancel_pi_test_lapse_1']);
    expect(r1.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'anomaly' }]);
    expect(r2.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'anomaly' }]);
    const alerts = w.alerts('anomaly');
    expect(alerts).toHaveLength(1);
    expect(alerts[0].ctx).toEqual({ order_id: orderUuid(1), pi_id: 'pi_test_lapse_1', authorization: 'may_still_be_held' });
    expect(w.reviews).toEqual([review(anomalyMarker(1))]);
  });

  it('a session-mismatch anomaly (nothing touched at all) is alerted once across three runs as well', async () => {
    const w = await world({ report: [lapsed(1)] });
    w.addPi(1, 'requires_payment_method', { session: OTHER_SESSION });
    await w.run();
    await w.run();
    await w.run();
    expect(w.piCancels()).toEqual([]);
    expect(w.alerts('anomaly')).toHaveLength(1);
    expect(w.reviews).toEqual([review(anomalyMarker(1))]);
  });

  it('a paid alert and an anomaly alert for DIFFERENT orders each fire once across runs', async () => {
    const w = await world({
      report: [lapsed(1), lapsed(2, { total_minor: FACE + 500 })], cancelFails: { pi_test_lapse_1: 400 },
    });
    expect(w.addPi(1, 'requires_capture')).toBe('pi_test_lapse_1');
    const won = w.addPi(2, 'succeeded', { face: FACE + 500 });
    for (let i = 0; i < 3; i++) {
      const r = await w.run();
      expect(r.body.results).toEqual([
        { order_id: orderUuid(1), outcome: 'anomaly' },
        { order_id: orderUuid(2), outcome: 'paid' },
      ]);
    }
    const anomaly = w.alerts('anomaly');
    const paid = w.alerts('lapsed_order_paid');
    expect(anomaly).toHaveLength(1);
    expect(anomaly[0].ctx).toMatchObject({ order_id: orderUuid(1), pi_id: 'pi_test_lapse_1' });
    expect(paid).toHaveLength(1);
    expect(paid[0].ctx).toMatchObject({ order_id: orderUuid(2), pi_ids: [won] });
    expect(w.reviews).toEqual([review(anomalyMarker(1)), review(paidMarker(2))]);
  });

  it('the SAME order: an anomaly, then (a sibling succeeds) a paid alert — neither marker suppresses the other, each fires once', async () => {
    const w = await world({ report: [lapsed(1)], cancelFails: { pi_test_lapse_1: 400 } });
    expect(w.addPi(1, 'requires_capture')).toBe('pi_test_lapse_1');
    const sib = w.addPi(1, 'requires_payment_method');
    const r1 = await w.run();
    expect(r1.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'anomaly' }]);
    // The buyer's sheet confirms the sibling after the lapse (R9).
    w.pis.get(sib)!.status = 'succeeded';
    w.rows.find((r) => r.stripe_payment_intent_id === sib)!.status = 'succeeded';
    const r2 = await w.run();
    const r3 = await w.run();
    expect(r2.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'paid' }]);
    expect(r3.body.results).toEqual([{ order_id: orderUuid(1), outcome: 'paid' }]);
    expect(w.alerts('anomaly')).toHaveLength(1);
    expect(w.alerts('lapsed_order_paid')).toHaveLength(1);
    expect(w.reviews).toEqual([review(anomalyMarker(1)), review(paidMarker(1))]);
  });

  it.each([
    ['anomaly', 'error'],
    ['anomaly', 'throw'],
    ['lapsed_order_paid', 'error'],
    ['lapsed_order_paid', 'throw'],
  ] as const)('%s: a marker that cannot be read (read %s) → the alert fires anyway, even though a marker row exists (never silent)', async (needle, mode) => {
    const w = await world({ report: [lapsed(1)], cancelFails: { pi_test_lapse_1: 400 } });
    w.addPi(1, needle === 'anomaly' ? 'requires_capture' : 'succeeded');
    await w.run();
    expect(w.alerts(needle)).toHaveLength(1);
    expect(w.reviews).toHaveLength(1); // the marker IS there …
    w.setMarkerReads(mode);
    const r = await w.run(); // … but this run cannot see it
    expect(r.res.status).toBe(200);
    expect(r.body.results).toEqual([{ order_id: orderUuid(1), outcome: needle === 'anomaly' ? 'anomaly' : 'paid' }]);
    expect(w.alerts(needle)).toHaveLength(2);
  });
});

describe('lapse cancel body confirmation', () => {
  const cases: Array<[string, unknown]> = [
    ['processing body', { id: 'pi_test_lapse_1', status: 'processing' }],
    ['succeeded body', { id: 'pi_test_lapse_1', status: 'succeeded' }],
    ['missing status', { id: 'pi_test_lapse_1' }],
    ['null body', null],
    ['wrong id', { id: 'pi_other', status: 'canceled' }],
  ];
  for (const [label, body] of cases) {
    it(`${label} does NOT mark canceled or cancel the order`, async () => {
      const w = await world({ report: [lapsed(1)] });
      const pi = w.addPi(1, 'requires_payment_method');
      // The id is deterministic; inject the body for this PI.
      w.setCancelBodies({ [pi]: body });
      const r = await w.run();
      expect(r.res.status).toBe(200);
      expect(w.orderCancels()).toEqual([]);
      expect(w.sb.rpcs.some((x) => x.name === 'mark_payment_attempt_by_pi')).toBe(false);
    });
  }
  it('a confirmed canceled body marks before any order cancellation', async () => {
    const w = await world({ report: [lapsed(1)] });
    const pi = w.addPi(1, 'requires_payment_method');
    w.setCancelBodies({ [pi]: { id: pi, status: 'canceled' } });
    const r = await w.run();
    expect(r.res.status).toBe(200);
    expect(w.orderCancels()).toEqual([]);
    const names = w.sb.rpcs.map((x) => x.name);
    expect(names.indexOf('mark_payment_attempt_by_pi')).toBeGreaterThanOrEqual(0);
  });
});
