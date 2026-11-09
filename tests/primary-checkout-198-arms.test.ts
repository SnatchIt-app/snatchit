/**
 * tests/primary-checkout-198-arms.test.ts — registry 198, A's edge arms in
 * primary-checkout (A, 2026-11-02). Contract: DESIGN-198-FINAL §4.1, §4.2
 * A-1 / A-2 / A-3 / A-4 / A-7, scenarios §5 (2, 11, 12, 13), races R1/R9.
 *
 * Loads the REAL primary-checkout handler (tests/helpers/edge-vm.ts). The
 * order-pis.ts sibling it imports is bound from the REAL module.
 *
 * The RPC fake models the 198 contract as D designed it (the SQL is not merged):
 *   • create_primary_checkout's replay returns carry `order_status` and
 *     `holds_live` (§3.1 BLOCKS P1/P3, §4.1) — `holds_live` is NULL when the
 *     order has no bound hold;
 *   • BLOCK F raises `precondition_failed: feature_disabled` (§3.1);
 *   • BLOCK B binds the named holds to the order it creates, and refuses a hold
 *     bound to an order that is not `cancelled` with the 188 text plus a DETAIL
 *     (§3.1, G3) — simplified to whole holds, which is all these tests need;
 *   • cancel_pending_order is 082:478-525: cancelled → noop_replay, pending →
 *     cancelled, anything else raises order_not_pending.
 * No network, no database, no real key.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { totalMismatch } from '../supabase/functions/_shared/money';
import { buildCancelCommandKey } from '../supabase/functions/stripe-webhook/native';

const ENV: Record<string, string | undefined> = {
  SUPABASE_URL: 'https://x.invalid', SUPABASE_ANON_KEY: 'anon-test', SUPABASE_SERVICE_ROLE_KEY: 'service-test',
  PRIMARY_CHECKOUT_REPLAY_REREAD_MS: '0',
};
const STRIPE_MOBILE_API_VERSION = '2024-04-10';

// Synthetic uuids: version 4, variant 8-b, a hex letter in every group.
const SESSION     = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
const TICKET_TYPE = 'b2c3d4e5-f6a7-4b8c-9dae-1f2a3b4c5d6e';
const HOLD        = 'c3d4e5f6-a7b8-4c9d-aeb1-2a3b4c5d6e7f';
const ORG         = 'd4e5f6a7-b8c9-4dae-bf12-3b4c5d6e7f8a';
const BUYER       = 'buyer-native-198';
const CUSTOMER    = 'cus_test_native198';
const orderUuid = (n: number) => `aaaa${String(n).padStart(4, '0')}-bbbb-4ccc-8ddd-eeee${String(n).padStart(8, '0')}`;

const FACE = 2500;
const FEE  = 300;
const CHARGE = 2800;

const HOLD_INVALID = { error: 'Your ticket hold expired or no longer covers this order. Please start again.', code: 'hold_invalid' };
const ALREADY_PAID = { error: 'Payment already completed for this order.', code: 'already_paid' };
const REPLAY_STATE_UNAVAILABLE = { error: 'This order cannot be resumed. Please contact support.', code: 'replay_state_unavailable' };

interface PayRow {
  id: string; buyer_id: string; mode: string; amount: number; buyer_fee: number; seller_fee: number; total: number;
  status: string; stripe_payment_intent_id: string | null; created_at: string;
  [k: string]: unknown;
}
interface Pi { id: string; client_secret: string; status: string; livemode: boolean; amount: number; currency: string; metadata: Record<string, string> }
interface OrderState { orderId: string; status: string; holdsLive: boolean | null; holds: string[] }

interface WorldOpts {
  /** create_primary_checkout raises this instead of answering */
  rpcError?: { message: string; code?: string; details?: string };
  /** replay returns WITHOUT order_status / holds_live (the pre-198 shape) */
  preShape?: boolean;
  omitOrgId?: boolean;
  currency?: string;
  /** a success return whose fee does not add up */
  incoherentFee?: boolean;
  ephemeralKeyFails?: boolean;
  piCreateFails?: boolean;
  /** public.payments insert fails with this */
  insertError?: { code: string; message: string };
  /** cancel_pending_order errors */
  cancelFails?: boolean;
  /** POST /payment_intents/{id}/cancel is refused (the confirm won, R9) */
  piCancelRefused?: boolean;
  /** GET /payment_intents/{id} answers 503 (Stripe could not be read) */
  piReadFails?: boolean;
  /** the currency a REPLAY return carries (082:449-454 returns the stored order's) */
  replayCurrency?: string;
}

function pick(row: Record<string, unknown>, select: string | null): Record<string, unknown> {
  if (!select || select.trim() === '*') return { ...row };
  const out: Record<string, unknown> = {};
  for (const c of select.split(',').map((s) => s.trim()).filter(Boolean)) if (c in row) out[c] = row[c];
  return out;
}

function matches(row: Record<string, unknown>, f: [string, ...unknown[]]): boolean {
  const [op, col, val] = f as [string, string, unknown];
  if (op === 'eq') return row[col] === val;
  if (op === 'in') return (val as unknown[]).includes(row[col]);
  throw new Error(`payments fake: unmodelled filter ${op}`);
}

async function world(opts: WorldOpts = {}) {
  let clock = Date.parse('2026-10-01T00:00:00Z');
  const tick = () => new Date((clock += 60_000)).toISOString();

  const rows: PayRow[] = [];
  const pis = new Map<string, Pi>();
  const piByIdemKey = new Map<string, string>();
  const orders = new Map<string, OrderState>();          // `${buyer}|${command_key}` → order
  const boundTo = new Map<string, string>();             // hold_id → order_id (BLOCK B)
  const byId = (id: string) => [...orders.values()].find((o) => o.orderId === id);

  const sb = mockSupabase({
    user: { id: BUYER, email: 'buyer@example.test' },
    rpc: (name, params) => {
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'is_deletion_pending') return { data: false };
      if (name === 'create_primary_checkout') {
        if (opts.rpcError) return { error: opts.rpcError };
        const k = `${BUYER}|${String(params.p_command_key)}`;
        const existing = orders.get(k);
        if (existing) {
          // §3.1 BLOCK P1/P3: the replay gains order_status + holds_live (§4.1).
          return {
            data: {
              status: 'idempotency_replay', order_id: existing.orderId, total_minor: FACE, currency: opts.replayCurrency ?? 'USD',
              ...(opts.preShape ? {} : { order_status: existing.status, holds_live: existing.holdsLive }),
            },
          };
        }
        const holdIds = params.p_hold_ids as string[];
        // §3.1 BLOCK B: a hold bound to an order that is not cancelled is not bindable.
        const taken = holdIds.filter((h) => { const o = boundTo.get(h); return o !== undefined && byId(o)?.status !== 'cancelled'; });
        if (taken.length > 0) {
          return {
            error: {
              code: 'P0001',
              message: `precondition_failed: holds do not cover item (type ${TICKET_TYPE}, need 1, held 0)`,
              details: `bound_to_pending_order_units=${taken.length} other_batch_units=0`,
            },
          };
        }
        const orderId = orderUuid(orders.size + 1);
        orders.set(k, { orderId, status: 'pending', holdsLive: true, holds: [...holdIds] });
        for (const h of holdIds) boundTo.set(h, orderId);
        return {
          data: {
            status: 'ok', order_id: orderId, ...(opts.omitOrgId ? {} : { org_id: ORG }),
            total_minor: FACE, currency: opts.currency ?? 'USD',
            buyer_fee_minor: opts.incoherentFee ? FEE + 1 : FEE, charge_total_minor: CHARGE,
          },
        };
      }
      if (name === 'read_payment_attempt_recovery') {
        return { error: { message: 'precondition_failed: recovery needs exactly one non-canceled attempt (found 0)' } };
      }
      if (name === 'read_payment_attempt_binding') {

        return { data: { attempt_id: 'att_replay', order_id: params.p_order_id, buyer_id: params.p_buyer_id,
          session_id: params.p_session_id, pi_id: params.p_pi_id, state: 'open',
          face_minor: FACE, buyer_fee_minor: FEE, amount_minor: CHARGE, currency: 'USD' } };
      }
      if (name === 'begin_payment_attempt') {
        return { data: { attempt_id: `att_${String(params.p_attempt_key)}`, attempt_key: params.p_attempt_key, state: 'creating', pi_id: null } };
      }
      if (name === 'store_payment_attempt_request') {
        return { data: { attempt_id: params.p_attempt_id, order_id: params.p_order_id, buyer_id: params.p_buyer_id, session_id: params.p_session_id, pi_id: null, state: 'creating', face_minor: FACE, buyer_fee_minor: FEE, amount_minor: CHARGE, currency: 'USD', create_request: params.p_create_request } };
      }
      if (name === 'attach_payment_attempt') {
        return { data: { attempt_id: params.p_attempt_id, state: 'open', pi_id: params.p_pi_id, replay: false } };
      }
      if (name === 'mark_payment_attempt_by_pi') {
        return { data: { attempt_id: `att_${String(params.p_pi_id)}`, state: params.p_state, pi_id: params.p_pi_id } };
      }
      if (name === 'cancel_pending_order') {
        if (opts.cancelFails) return { error: { message: 'connection reset (test)' } };
        const o = byId(String(params.p_order_id));
        if (!o) return { error: { message: `not_found: order ${String(params.p_order_id)}`, code: 'P0002' } };
        if (o.status === 'cancelled') return { data: { status: 'noop_replay', order_id: o.orderId } };
        if (o.status !== 'pending') return { error: { message: `precondition_failed: order_not_pending (status=${o.status})`, code: 'P0001' } };
        o.status = 'cancelled';
        return { data: { status: 'cancelled', order_id: o.orderId } };
      }
      return { error: { message: `unmocked rpc ${name}` } };
    },
    tables: {
      profiles: (q: QueryCall) => (q.op === 'select' ? { data: { stripe_customer_id: CUSTOMER } } : { data: null }),
      payments: (q: QueryCall) => {
        if (q.op === 'insert') {
          if (opts.insertError) return { error: opts.insertError };
          const b = q.body as Record<string, unknown>;
          if (rows.some((r) => r.stripe_payment_intent_id === b.stripe_payment_intent_id)) {
            return { error: { message: 'duplicate key value violates unique constraint', code: '23505' } };
          }
          rows.push({ ...(b as PayRow), id: `pay_${rows.length + 1}`, created_at: tick() });
          return { data: null };
        }
        if (q.op === 'select') {
          let out = rows.filter((r) => q.filters.every((f) => matches(r, f)));
          for (const [col, o] of [...q.order].reverse()) {
            const asc = (o as { ascending?: boolean } | undefined)?.ascending !== false;
            out = [...out].sort((x, y) => (String(x[col]) < String(y[col]) ? (asc ? -1 : 1) : String(x[col]) > String(y[col]) ? (asc ? 1 : -1) : 0));
          }
          if (q.limit !== null) out = out.slice(0, q.limit);
          const picked = out.map((r) => pick(r, q.select));
          return { data: q.terminal === 'list' ? picked : picked[0] ?? null };
        }
        return { error: { message: `payments fake: unmodelled op ${q.op}` } };
      },
    },
  });

  const stripe = mockStripe(async (c: StripeCall) => {
    if (c.method === 'GET' && c.path === `/customers/${CUSTOMER}`) return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === '/ephemeral_keys') {
      return opts.ephemeralKeyFails
        ? { ok: false, status: 500, data: { error: { type: 'api_error' } } }
        : { ok: true, data: { secret: 'ek_test_secret' } };
    }
    if (c.method === 'POST' && c.path === '/payment_intents') {
      if (opts.piCreateFails) return { ok: false, status: 500, data: { error: { type: 'api_error', message: 'stripe down (test)' } } };
      const prior = c.idempotencyKey ? piByIdemKey.get(c.idempotencyKey) : undefined;
      if (prior) return { ok: true, data: { ...pis.get(prior)! } };
      const body = c.body as Record<string, string>;
      const id = `pi_test_native198_${pis.size + 1}`;
      const metadata: Record<string, string> = {};
      for (const [k, v] of Object.entries(body)) if (k.startsWith('metadata[')) metadata[k.slice('metadata['.length, -1)] = v;
      const pi: Pi = { id, client_secret: `${id}_secret_x`, status: 'requires_payment_method', livemode: false, amount: Number(body.amount), currency: 'usd', metadata };
      pis.set(id, pi);
      if (c.idempotencyKey) piByIdemKey.set(c.idempotencyKey, id);
      return { ok: true, data: { ...pi } };
    }
    const cancelM = c.method === 'POST' ? c.path.match(/^\/payment_intents\/([^/]+)\/cancel$/) : null;
    if (cancelM) {
      const pi = pis.get(cancelM[1]);
      if (!pi) return { ok: false, status: 404, data: { error: { code: 'resource_missing' } } };
      if (opts.piCancelRefused) return { ok: false, status: 400, data: { error: { code: 'payment_intent_unexpected_state' } } };
      pi.status = 'canceled';
      return { ok: true, data: { ...pi } };
    }
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      if (opts.piReadFails) return { ok: false, status: 503, data: { error: { type: 'api_error', message: 'stripe unreadable (test)' } } };
      const pi = pis.get(c.path.split('/')[2]);
      return pi ? { ok: true, data: { ...pi } } : { ok: false, status: 404, data: { error: { code: 'resource_missing' } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });

  const edge = await loadEdgeHandler('supabase/functions/primary-checkout/index.ts', {
    supabase: sb,
    env: { ...ENV },
    provide: { stripeFetch: stripe.stripeFetch, stripeFetchRaw: stripe.stripeFetchRaw, STRIPE_MOBILE_API_VERSION, totalMismatch },
  });

  const run = async (commandKey: string, extra: Record<string, unknown> = {}) => {
    const res = await edge.handler(authedJsonRequest({
      session_id: SESSION, items: [{ ticket_type_id: TICKET_TYPE, quantity: 1 }], hold_ids: [HOLD], command_key: commandKey, ...extra,
    }));
    return { res, body: await json(res) };
  };
  const order = (commandKey: string) => orders.get(`${BUYER}|${commandKey}`)!;
  const cancels = () => sb.rpcs.filter((r) => r.name === 'cancel_pending_order');
  const piMints = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
  const piCancels = () => stripe.calls.filter((c) => c.method === 'POST' && /^\/payment_intents\/[^/]+\/cancel$/.test(c.path));
  const blockerAlerts = () => edge.sentry.filter((s) => (s.ctx as { activation_blocker?: boolean } | undefined)?.activation_blocker === true);
  const stageLines = (stage: string) => edge.logs
    .filter((l) => l.level === 'log' && typeof l.args[0] === 'string' && l.args[0].includes('"primary-checkout-stage"'))
    .map((l) => JSON.parse(l.args[0] as string) as Record<string, unknown>)
    .filter((l) => l.stage === stage);

  return { run, order, rows, pis, stripe, sb, edge, cancels, piMints, piCancels, blockerAlerts, stageLines };
}

type W = Awaited<ReturnType<typeof world>>;

/**
 * A fresh checkout, then the same key replayed with the order in `patch` state.
 * `siblingStatus` adds a second PI for the SAME order (the salted re-mint
 * primary-checkout §11 can produce) with its own payments row, newest.
 */
async function replayWith(w: W, key: string, patch: Partial<OrderState>, piStatus?: string, siblingStatus?: string) {
  const first = await w.run(key);
  expect(first.res.status).toBe(200);
  Object.assign(w.order(key), patch);
  if (piStatus) w.pis.get(first.body.paymentIntentId as string)!.status = piStatus;
  if (siblingStatus) {
    const base = w.rows.find((r) => r.stripe_payment_intent_id === first.body.paymentIntentId)!;
    const firstPi = w.pis.get(first.body.paymentIntentId as string)!;
    const id = `pi_test_native198_sibling_${w.pis.size + 1}`;
    w.pis.set(id, { ...firstPi, id, client_secret: `${id}_secret_x`, status: siblingStatus, metadata: { ...firstPi.metadata } });
    w.rows.push({
      ...base, id: `pay_${w.rows.length + 1}`, stripe_payment_intent_id: id,
      status: siblingStatus === 'succeeded' ? 'succeeded' : 'pending', created_at: '2026-10-02T00:00:00.000Z',
    });
  }
  const callsBefore = w.stripe.calls.length;
  const replay = await w.run(key);
  return { first, replay, stripeAfter: w.stripe.calls.slice(callsBefore) };
}

// ═══════════════════════════════════════════════════════════════════════════

describe('A-1 — feature_disabled is 503 sales_paused (§4.2 A-1, §5 scenario 2)', () => {
  it('BLOCK F\'s refusal answers 503 {code:sales_paused}, no Retry-After, not an activation blocker, and nothing is minted', async () => {
    const w = await world({ rpcError: { code: 'P0001', message: 'precondition_failed: feature_disabled' } });
    const r = await w.run('cmd-paused');
    expect(r.res.status).toBe(503);
    expect(r.body).toEqual({ error: 'Ticket sales are paused for this event.', code: 'sales_paused' });
    expect(r.res.headers.get('Retry-After')).toBeNull();
    expect(w.blockerAlerts()).toEqual([]);
    expect(w.stripe.calls).toEqual([]);
    expect(w.cancels()).toEqual([]);
    expect(w.rows).toHaveLength(0);
  });

  it('the rpc-refused log line carries the DETAIL (BLOCK B\'s unit counts); the client body never does', async () => {
    const details = 'bound_to_pending_order_units=2 other_batch_units=0';
    const w = await world({
      rpcError: { code: 'P0001', message: `precondition_failed: holds do not cover item (type ${TICKET_TYPE}, need 2, held 0)`, details },
    });
    const r = await w.run('cmd-bound-elsewhere');
    expect(r.res.status).toBe(409);
    expect(r.body).toEqual(HOLD_INVALID);
    expect(JSON.stringify(r.body)).not.toContain('bound_to_pending_order_units');
    const [line] = w.stageLines('rpc-refused');
    expect(line.details).toBe(details);
  });
});

// 201 (D, #239) and 093/198's organization gate: two refusals a buyer cannot fix.
// They used to reach the generic arm, which relays the RPC's own text, and
// org_not_active's text names the organization's INTERNAL status. Both now answer
// one stable buyer-safe code (OC-201-CLIENT-REFUSAL-TRACE-1; E's #239 review).
const SALES_UNAVAILABLE = { error: 'Ticket sales aren’t available for this event.', code: 'sales_unavailable' };
describe('201 — venue not approved / organization not active are 409 sales_unavailable, never the server phrase', () => {
  it('venue is not approved (reserve and checkout share the literal) → 409 sales_unavailable, nothing minted', async () => {
    const w = await world({ rpcError: { code: 'P0001', message: 'precondition_failed: venue is not approved' } });
    const r = await w.run('cmd-venue-unapproved');
    expect(r.res.status).toBe(409);
    expect(r.body).toEqual(SALES_UNAVAILABLE);
    expect(w.stripe.calls).toEqual([]);
    expect(w.rows).toHaveLength(0);
    expect(w.blockerAlerts()).toEqual([]);
  });

  // E review of c78788d9: match 201's TOKEN, not only its prose. 201 will raise
  // `precondition_failed: venue_not_approved — venue is not approved` (a token
  // ahead of the house wording), so a later reword of the sentence cannot silently
  // fall through to the generic arm. Both forms map, so this edge is correct
  // against 201 before and after that change.
  it('the venue_not_approved TOKEN maps too, with or without the prose after it', async () => {
    for (const message of ['precondition_failed: venue_not_approved — venue is not approved', 'precondition_failed: venue_not_approved']) {
      const w = await world({ rpcError: { code: 'P0001', message } });
      const r = await w.run(`cmd-token-${message.length}`);
      expect(r.res.status).toBe(409);
      expect(r.body).toEqual(SALES_UNAVAILABLE);
      expect(JSON.stringify(r.body)).not.toContain('venue_not_approved');
    }
  });

  it.each(['applied', 'suspended', 'closed', 'missing'])('org_not_active (%s) → the same code, and the internal status never reaches the buyer', async (status) => {
    const w = await world({ rpcError: { code: 'P0001', message: `precondition_failed: org_not_active — a ${status} organization may not sell` } });
    const r = await w.run(`cmd-org-${status}`);
    expect(r.res.status).toBe(409);
    expect(r.body).toEqual(SALES_UNAVAILABLE);
    expect(JSON.stringify(r.body)).not.toContain(status);
    expect(JSON.stringify(r.body)).not.toContain('org_not_active');
    expect(w.stripe.calls).toEqual([]);
  });

  it('control: another precondition still takes the generic arm, and feature_disabled is still 503 sales_paused', async () => {
    const other = await world({ rpcError: { code: 'P0001', message: 'precondition_failed: bad_item (quantity)' } });
    const ro = await other.run('cmd-other');
    expect(ro.res.status).toBe(409);
    expect(ro.body).toEqual({ error: 'bad_item (quantity)', code: 'precondition_failed' });
    const paused = await world({ rpcError: { code: 'P0001', message: 'precondition_failed: feature_disabled' } });
    const rp = await paused.run('cmd-paused-2');
    expect(rp.res.status).toBe(503);
    expect(rp.body.code).toBe('sales_paused');
  });
});

describe('A-2 — the replay rule on order_status / holds_live (§4.2 A-2, §4.1, O1, O17)', () => {
  it('order_status=paid → the existing already_paid answer, before any Stripe call', async () => {
    const w = await world();
    const { replay, stripeAfter } = await replayWith(w, 'cmd-r-paid', { status: 'paid', holdsLive: false });
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(ALREADY_PAID);
    expect(stripeAfter).toEqual([]);
    expect(w.cancels()).toEqual([]);
  });

  // D's ratification C1: venue."order".status is CHECK-constrained to exactly
  // pending / paid / partially_refunded / refunded / cancelled. The two refund
  // states are a paid order later refunded: already_paid, and NEVER the
  // terminal replay_state_unavailable an out-of-set value gets.
  it.each(['refunded', 'partially_refunded'])('order_status=%s (paid, then refunded) → already_paid too, never a client_secret, never replay_state_unavailable', async (status) => {
    const w = await world();
    const { replay, stripeAfter } = await replayWith(w, `cmd-r-${status}`, { status, holdsLive: false });
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(ALREADY_PAID);
    expect(replay.res.headers.get('Retry-After')).toBeNull();
    expect(stripeAfter).toEqual([]);
    expect(w.edge.sentry).toEqual([]);
    expect(w.cancels()).toEqual([]);
  });

  it('order_status=cancelled → 409 hold_invalid ("start again"), before any Stripe call', async () => {
    const w = await world();
    const { replay, stripeAfter } = await replayWith(w, 'cmd-r-cancelled', { status: 'cancelled', holdsLive: false });
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(HOLD_INVALID);
    expect(stripeAfter).toEqual([]);
  });

  it.each([
    ['false (lapsed, §5 scenario 11)', false],
    ['NULL (no bound hold)', null],
  ])('pending + holds_live %s → 409 hold_invalid, and the order\'s live PI is cancelled with pi_lapse_cancel_{pi}', async (_label, holdsLive) => {
    const w = await world();
    const { first, replay } = await replayWith(w, `cmd-r-lapsed-${String(holdsLive)}`, { holdsLive });
    const piId = first.body.paymentIntentId as string;
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(HOLD_INVALID);
    expect(replay.body.clientSecret).toBeUndefined();
    expect(w.piCancels().map((c) => [c.path, c.idempotencyKey, c.body])).toEqual([
      [`/payment_intents/${piId}/cancel`, `pi_lapse_cancel_${piId}`, { cancellation_reason: 'abandoned' }],
    ]);
    expect(w.pis.get(piId)!.status).toBe('canceled');
    // the webhook's payment_intent.canceled branch writes 'cancelled', not the edge (O11)
    expect(w.cancels()).toEqual([]);
    expect(w.piMints()).toHaveLength(1);
  });

  it('pending + lapsed, but the PI already SUCCEEDED (finalize in flight) → already_paid, never "start again", and nothing is cancelled', async () => {
    const w = await world();
    const { replay } = await replayWith(w, 'cmd-r-lapsed-paid', { holdsLive: false }, 'succeeded');
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(ALREADY_PAID);
    expect(w.piCancels()).toEqual([]);
    expect(w.cancels()).toEqual([]);
  });

  it('pending + lapsed, PI processing → 503 replay_recovery_failed (retry the SAME key), nothing cancelled', async () => {
    const w = await world();
    const { replay } = await replayWith(w, 'cmd-r-lapsed-processing', { holdsLive: false }, 'processing');
    expect(replay.res.status).toBe(503);
    expect(replay.body.code).toBe('replay_recovery_failed');
    expect(replay.res.headers.get('Retry-After')).toBe('10');
    expect(w.piCancels()).toEqual([]);
    expect(w.cancels()).toEqual([]);
  });

  it('pending + lapsed, Stripe refuses the cancel (the confirm won, R9) → 503 replay_recovery_failed, not "start again"', async () => {
    const w = await world({ piCancelRefused: true });
    const { replay } = await replayWith(w, 'cmd-r-lapsed-refused', { holdsLive: false });
    expect(replay.res.status).toBe(503);
    expect(replay.body.code).toBe('replay_recovery_failed');
    expect(w.piCancels()).toHaveLength(1);
  });

  it('pending + lapsed, PI already canceled → cancel_pending_order under the webhook\'s own key, then 409 hold_invalid', async () => {
    const w = await world();
    const { first, replay } = await replayWith(w, 'cmd-r-lapsed-dead', { holdsLive: false }, 'canceled');
    const piId = first.body.paymentIntentId as string;
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(HOLD_INVALID);
    expect(w.piCancels()).toEqual([]);
    expect(w.cancels().map((c) => [c.params, c.schema])).toEqual([[
      { p_order_id: first.body.order_id, p_reason_code: 'payment_failed', p_command_key: buildCancelCommandKey(first.body.order_id as string, piId) },
      'venue',
    ]]);
    expect(w.order('cmd-r-lapsed-dead').status).toBe('cancelled');
  });

  it('pending + holds_live=true → the existing recoverReplayQuote path: the SAME PI back', async () => {
    const w = await world();
    const { first, replay } = await replayWith(w, 'cmd-r-live', {});
    expect(replay.res.status).toBe(200);
    expect(replay.body.paymentIntentId).toBe(first.body.paymentIntentId);
    expect(replay.body.clientSecret).toBe(first.body.clientSecret);
    expect(w.piCancels()).toEqual([]);
  });

  it('pending + lapsed, Stripe cannot be read (GET 503) → 503 replay_recovery_failed + Retry-After 10 (transient: retry the SAME key), nothing cancelled', async () => {
    const opts: WorldOpts = {};
    const w = await world(opts);
    const first = await w.run('cmd-r-lapsed-unreadable');
    expect(first.res.status).toBe(200);
    Object.assign(w.order('cmd-r-lapsed-unreadable'), { holdsLive: false });
    opts.piReadFails = true;
    const replay = await w.run('cmd-r-lapsed-unreadable');
    expect(replay.res.status).toBe(503);
    expect(replay.body.code).toBe('replay_recovery_failed');
    expect(replay.res.headers.get('Retry-After')).toBe('10');
    expect(w.piCancels()).toEqual([]);
    expect(w.cancels()).toEqual([]);
  });

  // A's refinement R5 (ratified by D): an ANOMALY is permanent — a
  // requires_capture PI never leaves that state on its own — so a 503 would
  // send the client back on the SAME key forever. It is hold_invalid ("start
  // again") plus an alert naming the order and the PI.
  // D's ratification C2 (A's suggestion A): a requires_capture PI is an
  // AUTHORIZATION held on the buyer's card. It is cancelled FIRST, under the
  // lapse key, to release it — unless a sibling PI is succeeded or processing
  // (D3). The webhook's payment_intent.canceled branch then writes 'cancelled'
  // (O11), never the edge.
  it('pending + lapsed, PI requires_capture (this rail never produces it) → the PI is CANCELLED with pi_lapse_cancel_{pi} to release the authorization, then 409 hold_invalid + an alert naming order and PI (not a blocker); a second replay answers the same, never 503', async () => {
    const w = await world();
    const { first, replay } = await replayWith(w, 'cmd-r-lapsed-anomaly', { holdsLive: false }, 'requires_capture');
    const piId = first.body.paymentIntentId as string;
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(HOLD_INVALID);
    expect(replay.res.headers.get('Retry-After')).toBeNull();
    expect(w.piCancels().map((c) => [c.path, c.idempotencyKey, c.body])).toEqual([
      [`/payment_intents/${piId}/cancel`, `pi_lapse_cancel_${piId}`, { cancellation_reason: 'abandoned' }],
    ]);
    expect(w.pis.get(piId)!.status).toBe('canceled');
    expect(w.cancels()).toEqual([]);
    expect(w.blockerAlerts()).toEqual([]);
    const anomalyAlerts = w.edge.sentry.filter((s) => String((s.error as Error).message).includes('anomaly'));
    expect(anomalyAlerts.map((s) => s.ctx)).toEqual([
      { order_id: first.body.order_id, pi_id: piId, activation_blocker: false, authorization: 'released' },
    ]);

    const again = await w.run('cmd-r-lapsed-anomaly');
    expect(again.res.status).toBe(409);
    expect(again.body).toEqual(HOLD_INVALID);
    expect(again.res.headers.get('Retry-After')).toBeNull();
  });

  it('pending + lapsed, PI requires_capture whose cancel Stripe REFUSES → still 409 hold_invalid (never 503) + the alert, which says the authorization may still be held', async () => {
    const w = await world({ piCancelRefused: true });
    const { first, replay } = await replayWith(w, 'cmd-r-anomaly-cancel-refused', { holdsLive: false }, 'requires_capture');
    const piId = first.body.paymentIntentId as string;
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(HOLD_INVALID);
    expect(replay.res.headers.get('Retry-After')).toBeNull();
    expect(w.piCancels().map((c) => c.idempotencyKey)).toEqual([`pi_lapse_cancel_${piId}`]);
    expect(w.pis.get(piId)!.status).toBe('requires_capture');
    expect(w.cancels()).toEqual([]);
    const anomalyAlerts = w.edge.sentry.filter((s) => String((s.error as Error).message).includes('anomaly'));
    expect(anomalyAlerts.map((s) => s.ctx)).toEqual([
      { order_id: first.body.order_id, pi_id: piId, activation_blocker: false, authorization: 'may_still_be_held' },
    ]);
    expect(String((anomalyAlerts[0].error as Error).message)).toContain('authorization may still be held');
  });

  it('pending + lapsed, PI requires_capture with a PROCESSING sibling → NOT cancelled (D3: its canceled event would cancel the order the sibling\'s money is landing on); 409 hold_invalid + the alert says the authorization may still be held', async () => {
    const w = await world();
    const { first, replay } = await replayWith(w, 'cmd-r-anomaly-processing-sib', { holdsLive: false }, 'requires_capture', 'processing');
    const piId = first.body.paymentIntentId as string;
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(HOLD_INVALID);
    expect(w.piCancels()).toEqual([]);
    expect(w.pis.get(piId)!.status).toBe('requires_capture');
    expect(w.cancels()).toEqual([]);
    const anomalyAlerts = w.edge.sentry.filter((s) => String((s.error as Error).message).includes('anomaly'));
    expect(anomalyAlerts.map((s) => s.ctx)).toEqual([
      { order_id: first.body.order_id, pi_id: piId, activation_blocker: false, authorization: 'may_still_be_held' },
    ]);
    expect(String((anomalyAlerts[0].error as Error).message)).toContain('authorization may still be held');
  });

  it('pending + lapsed, PI requires_capture with a SUCCEEDED sibling → already_paid (a paid order speaks first) and NOTHING is cancelled (D3)', async () => {
    const w = await world();
    const { replay } = await replayWith(w, 'cmd-r-anomaly-succeeded-sib', { holdsLive: false }, 'requires_capture', 'succeeded');
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(ALREADY_PAID);
    expect(w.piCancels()).toEqual([]);
    expect(w.cancels()).toEqual([]);
  });

  it('a replay WITHOUT an order_status key (the pre-198 shape: 198 rolled back under this edge) → the existing recoverReplayQuote path: the SAME PI back, no alert', async () => {
    const w = await world({ preShape: true });
    const first = await w.run('cmd-r-preshape');
    expect(first.res.status).toBe(200);
    // holds_live is not consulted without order_status: the pre-198 edge never read it
    Object.assign(w.order('cmd-r-preshape'), { holdsLive: false });
    const replay = await w.run('cmd-r-preshape');
    expect(replay.res.status).toBe(200);
    expect(replay.body.paymentIntentId).toBe(first.body.paymentIntentId);
    expect(replay.body.clientSecret).toBe(first.body.clientSecret);
    expect(w.edge.sentry).toEqual([]);
    expect(w.piCancels()).toEqual([]);
    expect(w.cancels()).toEqual([]);
    expect(w.piMints()).toHaveLength(1);
  });

  // D's ratification C1: a PRESENT order_status outside the CHECK set's five is
  // a state no retry can change, so the answer is TERMINAL — 409, no
  // Retry-After — and no client loops on the same key. The activation-blocker
  // alert is kept. (A MISSING key is the pre-198 shape: R1, the test above.)
  it.each([
    ['an unrecognised value', 'refund_review'],
    ['NULL', null],
    ['not a string', 7],
  ])('a replay whose order_status is PRESENT but %s is TERMINAL: 409 replay_state_unavailable, no Retry-After, activation blocker, no client_secret, no Stripe call; a same-key retry answers the same', async (_label, status) => {
    const w = await world();
    const key = `cmd-r-unknown-${String(status)}`;
    const { replay, stripeAfter } = await replayWith(w, key, { status: status as unknown as string });
    expect(replay.res.status).toBe(409);
    expect(replay.body).toEqual(REPLAY_STATE_UNAVAILABLE);
    expect(replay.body.clientSecret).toBeUndefined();
    expect(replay.res.headers.get('Retry-After')).toBeNull();
    expect(w.blockerAlerts()).toHaveLength(1);
    expect(stripeAfter).toEqual([]);
    expect(w.cancels()).toEqual([]);

    const again = await w.run(key);
    expect(again.res.status).toBe(409);
    expect(again.body).toEqual(REPLAY_STATE_UNAVAILABLE);
    expect(again.res.headers.get('Retry-After')).toBeNull();
  });
});

describe('A-3 — a success-path abort cancels the order it just created (§4.2 A-3, §5 scenario 12, G13)', () => {
  const abortKey = (orderId: unknown) => `edge_abort:${String(orderId)}`;

  it('total_mismatch: the order is cancelled under edge_abort:{order}, and a retry with a NEW key on the same hold rebinds and gets a PI', async () => {
    const w = await world();
    const first = await w.run('cmd-a3-mismatch', { expected_total_cents: CHARGE + 1 });
    expect(first.res.status).toBe(409);
    expect(first.body.code).toBe('total_mismatch');
    const orderId = w.order('cmd-a3-mismatch').orderId;
    expect(w.cancels().map((c) => [c.params, c.schema])).toEqual([[
      { p_order_id: orderId, p_reason_code: 'payment_failed', p_command_key: abortKey(orderId) },
      'venue',
    ]]);
    expect(w.sb.clients.some((c) => c.key === 'service-test' && c.schema === 'venue')).toBe(true);
    expect(w.order('cmd-a3-mismatch').status).toBe('cancelled');
    expect(w.piMints()).toHaveLength(0);

    const retry = await w.run('cmd-a3-mismatch-retry');
    expect(retry.res.status).toBe(200);
    expect(retry.body.clientSecret).toBeTruthy();
  });

  it('quote_incoherent → cancelled', async () => {
    const w = await world({ incoherentFee: true });
    const r = await w.run('cmd-a3-incoherent');
    expect(r.body.code).toBe('quote_incoherent');
    expect(w.cancels().map((c) => c.params.p_command_key)).toEqual([abortKey(w.order('cmd-a3-incoherent').orderId)]);
  });

  it('a non-USD order → cancelled', async () => {
    const w = await world({ currency: 'EUR' });
    const r = await w.run('cmd-a3-eur');
    expect(r.body.code).toBe('unsupported_currency');
    expect(w.cancels().map((c) => c.params.p_command_key)).toEqual([abortKey(w.order('cmd-a3-eur').orderId)]);
  });

  it('org_id missing (503 org_id_unavailable) → cancelled, and the blocker answer is unchanged', async () => {
    const w = await world({ omitOrgId: true });
    const r = await w.run('cmd-a3-no-org');
    expect(r.res.status).toBe(503);
    expect(r.body.code).toBe('org_id_unavailable');
    expect(w.blockerAlerts()).toHaveLength(1);
    expect(w.cancels().map((c) => c.params.p_command_key)).toEqual([abortKey(w.order('cmd-a3-no-org').orderId)]);
  });

  it('a Stripe Customer-step failure → cancelled; the answer is still the top-level 500', async () => {
    const w = await world({ ephemeralKeyFails: true });
    const r = await w.run('cmd-a3-customer');
    expect(r.res.status).toBe(500);
    expect(r.body).toEqual({ error: 'Internal server error' });
    expect(w.cancels().map((c) => c.params.p_command_key)).toEqual([abortKey(w.order('cmd-a3-customer').orderId)]);
  });

  it('a PaymentIntent create failure with unknown PI → order stays pending/recoverable, never blind-cancelled', async () => {
    const w = await world({ piCreateFails: true });
    const r = await w.run('cmd-a3-pi');
    expect(r.res.status).toBe(500);
    expect(r.body).toEqual({ error: 'Failed to create payment intent' });
    expect(w.cancels()).toEqual([]);
    expect(w.order('cmd-a3-pi').status).toBe('pending');
  });

  it('a payments insert failure → the orphan PI is cancelled FIRST, then the order', async () => {
    const w = await world({ insertError: { code: '23514', message: 'new row violates check constraint' } });
    const r = await w.run('cmd-a3-insert');
    expect(r.res.status).toBe(503);
    expect(r.body.code).toBe('payments_shape_unmigrated');
    const orderId = w.order('cmd-a3-insert').orderId;
    expect(w.cancels().map((c) => c.params.p_command_key)).toEqual([abortKey(orderId)]);
    const piCancelAt = w.stripe.calls.findIndex((c) => /\/cancel$/.test(c.path));
    expect(piCancelAt).toBeGreaterThanOrEqual(0);
    // the order cancel is an rpc, the PI cancel a Stripe call: order them by the stage log
    const stages = w.edge.logs.map((l) => String(l.args[0])).filter((s) => s.includes('"orphan-pi-canceled"') || s.includes('"abort-order-cancelled"'));
    expect(stages.map((s) => (JSON.parse(s) as { stage: string }).stage)).toEqual(['orphan-pi-canceled', 'abort-order-cancelled']);
  });

  it('a failing abort-cancel never changes the answer: still 409 total_mismatch, and it is reported', async () => {
    const w = await world({ cancelFails: true });
    const r = await w.run('cmd-a3-cancel-fails', { expected_total_cents: CHARGE + 1 });
    expect(r.res.status).toBe(409);
    expect(r.body.code).toBe('total_mismatch');
    expect(w.cancels()).toHaveLength(1);
    expect(w.edge.sentry.some((s) => String((s.error as Error).message).includes('edge_abort'))).toBe(true);
  });

  it('the happy path cancels nothing', async () => {
    const w = await world();
    const r = await w.run('cmd-a3-happy');
    expect(r.res.status).toBe(200);
    expect(w.cancels()).toEqual([]);
  });

  it('only the request that CREATED the order aborts it: a replay\'s total_mismatch cancels nothing', async () => {
    const w = await world();
    const first = await w.run('cmd-a3-replay');
    expect(first.res.status).toBe(200);
    const replay = await w.run('cmd-a3-replay', { expected_total_cents: CHARGE + 1 });
    expect(replay.res.status).toBe(409);
    expect(replay.body.code).toBe('total_mismatch');
    expect(w.cancels()).toEqual([]);
    expect(w.order('cmd-a3-replay').status).toBe('pending');
  });

  // The property above, defended where a replay DOES reach an abort site: the
  // top-level catch (a thrown Customer step) and the currency refusal both call
  // abortFreshOrder, which must find nothing armed for a replayed order — its
  // client may already hold the client_secret.
  it('a REPLAYED order whose Stripe Customer step throws is never cancelled: still the top-level 500, the order stays pending', async () => {
    const opts: WorldOpts = {};
    const w = await world(opts);
    const first = await w.run('cmd-a3-replay-customer');
    expect(first.res.status).toBe(200);
    opts.ephemeralKeyFails = true;
    const replay = await w.run('cmd-a3-replay-customer');
    expect(replay.res.status).toBe(500);
    expect(replay.body).toEqual({ error: 'Internal server error' });
    expect(w.cancels()).toEqual([]);
    expect(w.piCancels()).toEqual([]);
    expect(w.order('cmd-a3-replay-customer').status).toBe('pending');
  });

  it('a REPLAYED non-USD order is never cancelled: 409 unsupported_currency, the order stays pending', async () => {
    const opts: WorldOpts = {};
    const w = await world(opts);
    const first = await w.run('cmd-a3-replay-eur');
    expect(first.res.status).toBe(200);
    opts.replayCurrency = 'EUR';
    const replay = await w.run('cmd-a3-replay-eur');
    expect(replay.res.status).toBe(409);
    expect(replay.body.code).toBe('unsupported_currency');
    expect(w.cancels()).toEqual([]);
    expect(w.order('cmd-a3-replay-eur').status).toBe('pending');
  });
});

describe('A-4 — RES-1: a replay with no usable PaymentIntent is told to restart from ticket selection (§4.2 A-4, §5 scenario 13)', () => {
  it('409 quote_unavailable (code and status unchanged) whose message sends the buyer back to selection; the stranded order is NOT cancelled', async () => {
    // a first attempt that died before its PI AND whose A-3 cancel failed:
    // the order is pending, its holds live and bound, and no PI exists
    const w = await world({ cancelFails: true });
    const first = await w.run('cmd-a4', { expected_total_cents: CHARGE + 1 });
    expect(first.body.code).toBe('total_mismatch');
    const cancelsAfterFirst = w.cancels().length;

    const retry = await w.run('cmd-a4');
    expect(retry.res.status).toBe(409);
    expect(retry.body).toEqual({ error: 'This checkout expired. Please select your tickets again.', code: 'quote_unavailable' });
    expect(retry.res.headers.get('Retry-After')).toBeNull();
    expect(w.cancels()).toHaveLength(cancelsAfterFirst);
    expect(w.piCancels()).toEqual([]);
  });
});

describe('A-7 — immediate-settling payment methods only (§4.2 A-7, O12)', () => {
  it('the PaymentIntent pins payment_method_types to card and does not enable automatic_payment_methods', async () => {
    const w = await world();
    const r = await w.run('cmd-a7');
    expect(r.res.status).toBe(200);
    const [mint] = w.piMints();
    const body = mint.body as Record<string, string>;
    expect(body['payment_method_types[0]']).toBe('card');
    expect(Object.keys(body).filter((k) => k.startsWith('payment_method_types'))).toEqual(['payment_method_types[0]']);
    expect(Object.keys(body).filter((k) => k.startsWith('automatic_payment_methods'))).toEqual([]);
  });
});
