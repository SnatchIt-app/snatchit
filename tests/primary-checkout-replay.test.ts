/**
 * tests/primary-checkout-replay.test.ts — primary-checkout-1 / primary-checkout-4
 * (A, 2026-11-02).
 *
 * Loads the REAL primary-checkout handler (tests/helpers/edge-vm.ts) and pins the
 * retry contract the file (§10/§11) and E2_primary_checkout.md §10 promise: the
 * same (buyer, command_key) gets the SAME order and the SAME PaymentIntent back,
 * and a retry never mints a second PI.
 *
 *   • primary-checkout-1: venue.create_primary_checkout's two
 *     `idempotency_replay` returns carry NO org_id, by design
 *     (20261027031000:190-191 and :496-497, reasoned at :506-514). The org_id
 *     guard ran before `if (isReplay)`, so EVERY replay (double-tap, retry,
 *     retry after payment) answered 503 org_id_unavailable with a false
 *     activation-blocker alert, and the replay branch was dead code.
 *   • primary-checkout-4: once the replay branch runs, recoverReplayQuote must
 *     find this order's live PI. (a) The candidate read is capped at 10 rows, so
 *     with no ORDER BY a repeat buyer's historic succeeded rows at the same face
 *     can crowd this order's row out. (b) A transient Stripe GET failure is
 *     "try again" (503 replay_recovery_failed), not "start again" (409
 *     quote_unavailable) — the latter sends the client to a NEW command_key, a
 *     second order and a second PI on the same holds.
 *
 * The fakes are exact where it matters:
 *   • the RPC fake mirrors 20261027031000: the first call for a (buyer, key)
 *     returns the success shape WITH org_id and the fee fields (:515-519); every
 *     later call returns the replay shape WITHOUT them (:190-191).
 *   • Stripe POST /payment_intents honours Idempotency-Key (same key ⇒ same PI),
 *     and GET returns the PI with exactly the metadata the handler wrote.
 *   • public.payments honours eq/in, .order() and .limit(). With no .order() it
 *     returns heap (insertion) order — an order Postgres is free to return.
 * No network, no database, no real key.
 *
 * Review follow-ups (A, 2026-11-02), each its own describe below:
 *   • guard placement: a fresh return without org_id is refused BEFORE the
 *     Stripe Customer step (no customer create, no profiles write, no
 *     ephemeral key), so a Customer-step fault cannot turn the activation
 *     blocker into a bare 500.
 *   • a THROWN replay probe (network/timeout) is 503 replay_recovery_failed,
 *     the same as a 5xx status, not the top-level 500.
 *   • the in-flight race: a same-key request whose candidate read lands before
 *     the first request has written its payments row re-reads ONCE after a
 *     short wait (PRIMARY_CHECKOUT_REPLAY_REREAD_MS, default 2000; '0' here so
 *     the suite does not sleep) and finds that row. If it still finds nothing,
 *     the answer is today's 409 quote_unavailable (since 198's A-4 its text
 *     sends the buyer back to ticket selection; status and code unchanged).
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { totalMismatch } from '../supabase/functions/_shared/money';

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
const BUYER       = 'buyer-native-1';
const CUSTOMER    = 'cus_test_native';
const orderUuid = (n: number) => `aaaa${String(n).padStart(4, '0')}-bbbb-4ccc-8ddd-eeee${String(n).padStart(8, '0')}`;

const FACE = 2500;   // total_minor — face value
const FEE  = 300;    // buyer_fee_minor
const CHARGE = 2800; // charge_total_minor — the only PI amount

interface PayRow {
  id: string; buyer_id: string; mode: string; amount: number; buyer_fee: number; seller_fee: number; total: number;
  status: string; stripe_payment_intent_id: string | null; created_at: string;
  [k: string]: unknown;
}
interface Pi { id: string; client_secret: string; status: string; livemode: boolean; amount: number; metadata: Record<string, string> }
type Probe = (piId: string) => { ok: boolean; status: number; data: unknown } | null;

interface WorldOpts {
  /** N historic native_primary rows for this buyer, same face, status succeeded, PIs for OTHER orders */
  history?: number;
  /** a contract break: the RPC's SUCCESS return omits org_id */
  omitOrgId?: boolean;
  /** profiles holds no stripe_customer_id, so the Customer step would create one and write it back */
  noCustomer?: boolean;
  /** POST /ephemeral_keys fails, so the Customer step throws */
  ephemeralKeyFails?: boolean;
  /** merged over ENV; an undefined value unsets the key */
  env?: Record<string, string | undefined>;
}

function deferred<T = void>() {
  let resolve!: (v: T) => void;
  const promise = new Promise<T>((r) => { resolve = r; });
  return { promise, resolve };
}

/** the replay candidate read is the only payments select filtered on `mode` */
const isCandidateRead = (q: QueryCall) => q.op === 'select' && q.filters.some((f) => f[0] === 'eq' && f[1] === 'mode');

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
  // fail loudly rather than silently ignore a filter the fake does not model
  throw new Error(`payments fake: unmodelled filter ${op}`);
}

async function world(opts: WorldOpts = {}) {
  let clock = Date.parse('2026-10-01T00:00:00Z');
  const tick = () => new Date((clock += 60_000)).toISOString();

  const rows: PayRow[] = [];
  const pis = new Map<string, Pi>();
  const piByIdemKey = new Map<string, string>();
  const orders = new Map<string, string>(); // `${buyer}|${command_key}` → order_id
  let probe: Probe | null = null;
  /** Date.now() of each replay candidate read, in order */
  const candidateReadAt: number[] = [];
  /** runs BEFORE a candidate read is evaluated; a returned promise is awaited first */
  let onCandidateRead: ((n: number) => Promise<unknown> | void) | null = null;
  /** while set, POST /payment_intents signals `reached` and then waits on `gate` */
  let mintHold: { gate: Promise<void>; reached: () => void } | null = null;

  for (let i = 1; i <= (opts.history ?? 0); i++) {
    const id = `pi_test_hist_${i}`;
    pis.set(id, {
      id, client_secret: `${id}_secret_x`, status: 'succeeded', livemode: false, amount: CHARGE,
      metadata: { rail: 'native_primary', mode: 'native_primary', order_id: orderUuid(900 + i), buyer_id: BUYER, org_id: ORG, session_id: SESSION },
    });
    rows.push({
      id: `pay_hist_${i}`, buyer_id: BUYER, mode: 'native_primary', amount: FACE, buyer_fee: FEE, seller_fee: 0, total: CHARGE,
      status: 'succeeded', stripe_payment_intent_id: id, created_at: tick(), listing_id: null, seller_id: null,
    });
  }

  const sb = mockSupabase({
    user: { id: BUYER, email: 'buyer@example.test' },
    rpc: (name, params) => {
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'is_deletion_pending') return { data: false };
      if (name === 'create_primary_checkout') {
        const k = `${BUYER}|${String(params.p_command_key)}`;
        const existing = orders.get(k);
        // 20261027031000:190-191 (and the unique_violation loser, :496-497):
        // status/order_id/total_minor/currency — no org_id, no fee fields.
        // Registry 198 (DESIGN-198-FINAL §3.1 BLOCKS P1/P3, §4.1) adds
        // order_status + holds_live to both; this suite is about the replay
        // path proper, so its order is always pending with live holds — the
        // only state A-2 lets through to recoverReplayQuote. A-2's other arms
        // are pinned in primary-checkout-198-arms.test.ts.
        if (existing) {
          return {
            data: {
              status: 'idempotency_replay', order_id: existing, total_minor: FACE, currency: 'USD',
              order_status: 'pending', holds_live: true,
            },
          };
        }
        const orderId = orderUuid(orders.size + 1);
        orders.set(k, orderId);
        // :515-519 — the success return, the ONLY one carrying org_id.
        return {
          data: {
            status: 'ok', order_id: orderId, ...(opts.omitOrgId ? {} : { org_id: ORG }),
            total_minor: FACE, currency: 'USD', buyer_fee_minor: FEE, charge_total_minor: CHARGE,
          },
        };
      }
      // cancel_pending_order is DELIBERATELY unmodelled: it answers this error,
      // so A-3's abort-cancel (DESIGN-198-FINAL §4.2 A-3) fails and a dead
      // attempt's order stays pending — the RES-1 state this suite needs (a
      // process that died outside any catch, or whose abort-cancel failed).
      // The successful abort is pinned in primary-checkout-198-arms.test.ts.
      return { error: { message: `unmocked rpc ${name}` } };
    },
    tables: {
      profiles: (q: QueryCall) => (q.op === 'select' ? { data: { stripe_customer_id: opts.noCustomer ? null : CUSTOMER } } : { data: null }),
      payments: async (q: QueryCall) => {
        if (isCandidateRead(q)) {
          candidateReadAt.push(Date.now());
          // Only a hook that RETURNS a promise is awaited: a synchronous hook
          // (e.g. one that releases another request) must not yield before the
          // rows below are read, or the other request could write first.
          const pending = onCandidateRead?.(candidateReadAt.length);
          if (pending) await pending;
        }
        if (q.op === 'insert') {
          const b = q.body as Record<string, unknown>;
          if (rows.some((r) => r.stripe_payment_intent_id === b.stripe_payment_intent_id)) {
            return { error: { message: 'duplicate key value violates unique constraint', code: '23505' } };
          }
          rows.push({ ...(b as PayRow), id: `pay_${rows.length + 1}`, created_at: tick() });
          return { data: null };
        }
        if (q.op === 'select') {
          let out = rows.filter((r) => q.filters.every((f) => matches(r, f)));
          // last .order() is the least significant key: apply in reverse, stable sort
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
    if (c.method === 'POST' && c.path === '/customers') return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === `/customers/${CUSTOMER}`) return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === '/ephemeral_keys') {
      return opts.ephemeralKeyFails
        ? { ok: false, status: 500, data: { error: { type: 'api_error' } } }
        : { ok: true, data: { secret: 'ek_test_secret' } };
    }
    if (c.method === 'POST' && c.path === '/payment_intents') {
      if (mintHold) { mintHold.reached(); await mintHold.gate; }
      // Stripe idempotency: the same key replays the same object.
      const prior = c.idempotencyKey ? piByIdemKey.get(c.idempotencyKey) : undefined;
      if (prior) return { ok: true, data: { ...pis.get(prior)! } };
      const body = c.body as Record<string, string>;
      const id = `pi_test_native_${pis.size + 1}`;
      const metadata: Record<string, string> = {};
      for (const [k, v] of Object.entries(body)) if (k.startsWith('metadata[')) metadata[k.slice('metadata['.length, -1)] = v;
      const pi: Pi = { id, client_secret: `${id}_secret_x`, status: 'requires_payment_method', livemode: false, amount: Number(body.amount), metadata };
      pis.set(id, pi);
      if (c.idempotencyKey) piByIdemKey.set(c.idempotencyKey, id);
      return { ok: true, data: { ...pi } };
    }
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      const id = c.path.split('/')[2];
      const forced = probe?.(id) ?? null;
      if (forced) return forced;
      const pi = pis.get(id);
      return pi ? { ok: true, data: { ...pi } } : { ok: false, status: 404, data: { error: { code: 'resource_missing' } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });

  const env: Record<string, string | undefined> = { ...ENV, ...opts.env };
  const edge = await loadEdgeHandler('supabase/functions/primary-checkout/index.ts', {
    supabase: sb,
    env,
    provide: { stripeFetch: stripe.stripeFetch, stripeFetchRaw: stripe.stripeFetchRaw, STRIPE_MOBILE_API_VERSION, totalMismatch },
  });

  const run = async (commandKey: string, extra: Record<string, unknown> = {}) => {
    const res = await edge.handler(authedJsonRequest({
      session_id: SESSION, items: [{ ticket_type_id: TICKET_TYPE, quantity: 1 }], hold_ids: [HOLD], command_key: commandKey, ...extra,
    }));
    return { res, body: await json(res) };
  };
  const piMints = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
  const blockerAlerts = () => edge.sentry.filter((s) => (s.ctx as { activation_blocker?: boolean } | undefined)?.activation_blocker === true);

  const piGets = (piId: string) => stripe.calls.filter((c) => c.method === 'GET' && c.path === `/payment_intents/${piId}`).length;

  return {
    run, rows, pis, stripe, sb, edge, piMints, piGets, blockerAlerts, candidateReadAt,
    setProbe: (p: Probe | null) => { probe = p; },
    setOnCandidateRead: (h: ((n: number) => Promise<unknown> | void) | null) => { onCandidateRead = h; },
    holdMint: (gate: Promise<void>, reached: () => void) => { mintHold = { gate, reached }; },
  };
}

describe('primary-checkout-1 — an idempotency_replay is never answered 503 org_id_unavailable', () => {
  it('a double-tap with the same command_key gets the SAME order and PaymentIntent back, and no second PI is minted', async () => {
    const w = await world();
    const first = await w.run('cmd-double-tap');
    expect(first.res.status).toBe(200);
    expect(first.body.total).toBe(CHARGE);
    const piId = first.body.paymentIntentId as string;
    expect(w.pis.get(piId)?.metadata.org_id).toBe(ORG);

    const second = await w.run('cmd-double-tap');
    expect(second.body.code).toBeUndefined();
    expect(second.res.status).toBe(200);
    expect(second.body.order_id).toBe(first.body.order_id);
    expect(second.body.paymentIntentId).toBe(piId);
    expect(second.body.clientSecret).toBe(first.body.clientSecret);
    // the ORIGINAL quote, read back from the payments row — not re-derived
    expect([second.body.amount, second.body.buyer_fee, second.body.total]).toEqual([FACE, FEE, CHARGE]);

    expect(w.piMints()).toHaveLength(1);
    expect(w.rows).toHaveLength(1);
    expect(w.blockerAlerts()).toEqual([]);
  });

  it('a retry after the buyer already paid answers 409 already_paid, not 503', async () => {
    const w = await world();
    const first = await w.run('cmd-paid');
    expect(first.res.status).toBe(200);
    const pi = w.pis.get(first.body.paymentIntentId as string)!;
    pi.status = 'succeeded';
    w.rows[0].status = 'succeeded';

    const retry = await w.run('cmd-paid');
    expect(retry.res.status).toBe(409);
    expect(retry.body.code).toBe('already_paid');
    expect(w.piMints()).toHaveLength(1);
    expect(w.blockerAlerts()).toEqual([]);
  });

  it('a NON-replay success return without org_id still fails closed before any PaymentIntent is minted', async () => {
    // Regression pin for the guard's new position: it must still stand in
    // front of every fresh mint.
    const w = await world({ omitOrgId: true });
    const r = await w.run('cmd-no-org');
    expect(r.res.status).toBe(503);
    expect(r.body.code).toBe('org_id_unavailable');
    expect(r.res.headers.get('Retry-After')).toBe('300');
    expect(w.piMints()).toHaveLength(0);
    expect(w.rows).toHaveLength(0);
    expect(w.blockerAlerts()).toHaveLength(1);
  });
});

describe('primary-checkout-4 — replay recovery finds the live PaymentIntent', () => {
  it('(a) a repeat buyer with 10 succeeded same-face rows still gets this order\'s live PI back, not quote_unavailable', async () => {
    const w = await world({ history: 10 });
    const first = await w.run('cmd-repeat-buyer');
    expect(first.res.status).toBe(200);
    expect(w.rows.filter((r) => r.status === 'succeeded')).toHaveLength(10);

    const retry = await w.run('cmd-repeat-buyer');
    expect(retry.body.code).toBeUndefined();
    expect(retry.res.status).toBe(200);
    expect(retry.body.paymentIntentId).toBe(first.body.paymentIntentId);
    expect(retry.body.order_id).toBe(first.body.order_id);
    expect(w.piMints()).toHaveLength(1);
  });

  it.each([503, 500, 429])('(b) a transient Stripe GET failure (%i) on the candidate PI is 503 replay_recovery_failed, not 409 quote_unavailable', async (status) => {
    const w = await world();
    const first = await w.run('cmd-transient');
    expect(first.res.status).toBe(200);
    const piId = first.body.paymentIntentId as string;
    w.setProbe((id) => (id === piId ? { ok: false, status, data: { error: { type: 'api_error' } } } : null));

    const retry = await w.run('cmd-transient');
    expect(retry.res.status).toBe(503);
    expect(retry.body.code).toBe('replay_recovery_failed');
    expect(retry.res.headers.get('Retry-After')).toBe('10');
    expect(w.piMints()).toHaveLength(1);

    // and once Stripe answers again, the SAME PI comes back
    w.setProbe(null);
    const again = await w.run('cmd-transient');
    expect(again.res.status).toBe(200);
    expect(again.body.paymentIntentId).toBe(piId);
    expect(w.piMints()).toHaveLength(1);
  });

  it('(b, boundary) a PI Stripe reports as missing (404) still cannot confirm: 409 quote_unavailable, unchanged', async () => {
    const w = await world();
    const first = await w.run('cmd-missing');
    expect(first.res.status).toBe(200);
    const piId = first.body.paymentIntentId as string;
    w.setProbe((id) => (id === piId ? { ok: false, status: 404, data: { error: { code: 'resource_missing' } } } : null));

    const retry = await w.run('cmd-missing');
    expect(retry.res.status).toBe(409);
    expect(retry.body.code).toBe('quote_unavailable');
    expect(w.piMints()).toHaveLength(1);
  });
});

describe('review follow-up — the org_id guard stands in front of the Stripe Customer step on the fresh path', () => {
  it('a fresh return without org_id is refused before any Customer get/create, profiles write or ephemeral key', async () => {
    // noCustomer: had §10 run, it would have created a Stripe Customer and
    // written profiles.stripe_customer_id for a checkout that is then refused.
    const w = await world({ omitOrgId: true, noCustomer: true });
    const r = await w.run('cmd-no-org-no-customer');
    expect(r.res.status).toBe(503);
    expect(r.body.code).toBe('org_id_unavailable');
    expect(r.res.headers.get('Retry-After')).toBe('300');
    expect(w.blockerAlerts()).toHaveLength(1);
    expect(w.stripe.calls.map((c) => `${c.method} ${c.path}`)).toEqual([]);
    expect(w.sb.queries.filter((q) => q.table === 'profiles').map((q) => q.op)).toEqual([]);
    expect(w.rows).toHaveLength(0);
  });

  it('a Customer-step fault cannot mask the activation blocker: still 503 org_id_unavailable with its alert, not a bare 500', async () => {
    const w = await world({ omitOrgId: true, ephemeralKeyFails: true });
    const r = await w.run('cmd-no-org-ek-fails');
    expect(r.res.status).toBe(503);
    expect(r.body.code).toBe('org_id_unavailable');
    expect(w.blockerAlerts()).toHaveLength(1);
    expect(w.piMints()).toHaveLength(0);
  });
});

describe('review follow-up — a replay probe that THROWS is retryable, not the top-level 500', () => {
  it.each([
    ['a network failure', () => new TypeError('fetch failed')],
    ['a timeout', () => new DOMException('The operation timed out.', 'TimeoutError')],
  ])('%s on the candidate PI GET answers 503 replay_recovery_failed, and the SAME key then gets the SAME PI', async (_label, makeErr) => {
    const w = await world();
    const first = await w.run('cmd-probe-throws');
    expect(first.res.status).toBe(200);
    const piId = first.body.paymentIntentId as string;
    w.setProbe((id) => { if (id === piId) throw makeErr(); return null; });

    const retry = await w.run('cmd-probe-throws');
    expect(retry.res.status).toBe(503);
    expect(retry.body).toEqual({ error: 'Service temporarily unavailable. Please try again shortly.', code: 'replay_recovery_failed' });
    expect(retry.res.headers.get('Retry-After')).toBe('10');
    expect(w.edge.sentry.map((s) => (s.error as Error).message).filter((m) => m.startsWith('replay recovery failed:'))).toHaveLength(1);
    expect(w.piMints()).toHaveLength(1);

    w.setProbe(null);
    const again = await w.run('cmd-probe-throws');
    expect(again.res.status).toBe(200);
    expect(again.body.paymentIntentId).toBe(piId);
    expect(w.piMints()).toHaveLength(1);
  });
});

describe('review follow-up — the in-flight same-key race: ONE re-read before answering quote_unavailable', () => {
  type W = Awaited<ReturnType<typeof world>>;

  /**
   * Request A (fresh) is held inside its PaymentIntent mint: its order exists,
   * its PI does not yet, and its payments row is not written. Request B (same
   * key, so the RPC answers idempotency_replay) then does its candidate read
   * and finds nothing of A's. That first read lets A go; B's re-read is held
   * until A has finished, which is what the production wait buys.
   */
  async function raceSameKey(w: W, key: string) {
    const gate = deferred();
    const reached = deferred();
    w.holdMint(gate.promise, reached.resolve);
    const rowsBefore = w.rows.length;
    const a = w.run(key);
    await reached.promise;
    expect(w.rows).toHaveLength(rowsBefore);
    w.setOnCandidateRead((n) => {
      if (n === 1) { expect(w.rows).toHaveLength(rowsBefore); gate.resolve(); return; }
      return a;
    });
    const b = w.run(key);
    const [ra, rb] = await Promise.all([a, b]);
    return { ra, rb };
  }

  it('a same-key request that looks before the first has written its payments row gets the SAME order and PI back', async () => {
    const w = await world();
    const { ra, rb } = await raceSameKey(w, 'cmd-race');
    expect(ra.res.status).toBe(200);
    expect(rb.body.code).toBeUndefined();
    expect(rb.res.status).toBe(200);
    expect(rb.body.order_id).toBe(ra.body.order_id);
    expect(rb.body.paymentIntentId).toBe(ra.body.paymentIntentId);
    expect(rb.body.clientSecret).toBe(ra.body.clientSecret);
    expect([rb.body.amount, rb.body.buyer_fee, rb.body.total]).toEqual([FACE, FEE, CHARGE]);
    expect(w.candidateReadAt).toHaveLength(2);
    expect(w.piMints()).toHaveLength(1);
    expect(w.rows).toHaveLength(1);
  });

  it('a repeat buyer in the same race: the re-read finds the new row and does not GET the historic PIs a second time', async () => {
    const w = await world({ history: 3 });
    const { ra, rb } = await raceSameKey(w, 'cmd-race-repeat');
    expect(rb.res.status).toBe(200);
    expect(rb.body.paymentIntentId).toBe(ra.body.paymentIntentId);
    expect(w.candidateReadAt).toHaveLength(2);
    // each historic PI was shown not to be this order's on the first pass;
    // that cannot change, so the re-read does not ask Stripe again
    for (let i = 1; i <= 3; i++) expect(w.piGets(`pi_test_hist_${i}`)).toBe(1);
    expect(w.piGets(ra.body.paymentIntentId as string)).toBe(1);
    expect(w.piMints()).toHaveLength(1);
  });

  it('if the re-read still finds nothing, the answer is today\'s 409 quote_unavailable, unchanged, after exactly one re-read', async () => {
    const w = await world();
    // the first attempt dies before any PI (and its A-3 abort-cancel fails,
    // see the rpc fake): an order exists, pending, no PI, no row
    const first = await w.run('cmd-dead', { expected_total_cents: CHARGE + 1 });
    expect(first.res.status).toBe(409);
    expect(first.body.code).toBe('total_mismatch');
    expect(w.piMints()).toHaveLength(0);

    const retry = await w.run('cmd-dead');
    expect(retry.res.status).toBe(409);
    // A-4 (§4.2 A-4): same status and code; the text now says where to restart
    expect(retry.body).toEqual({ error: 'This checkout expired. Please select your tickets again.', code: 'quote_unavailable' });
    expect(retry.res.headers.get('Retry-After')).toBeNull();
    expect(w.candidateReadAt).toHaveLength(2);
    expect(w.piMints()).toHaveLength(0);
  });

  it('the wait is injectable: PRIMARY_CHECKOUT_REPLAY_REREAD_MS=0 does not sleep the 2s default', async () => {
    const w = await world();
    await w.run('cmd-dead-zero', { expected_total_cents: CHARGE + 1 });
    await w.run('cmd-dead-zero');
    expect(w.candidateReadAt).toHaveLength(2);
    expect(w.candidateReadAt[1] - w.candidateReadAt[0]).toBeLessThan(1900);
  });

  it('the wait defaults to 2s when PRIMARY_CHECKOUT_REPLAY_REREAD_MS is unset', async () => {
    const w = await world({ env: { PRIMARY_CHECKOUT_REPLAY_REREAD_MS: undefined } });
    await w.run('cmd-dead-default', { expected_total_cents: CHARGE + 1 });
    const retry = await w.run('cmd-dead-default');
    expect(retry.body.code).toBe('quote_unavailable');
    expect(w.candidateReadAt).toHaveLength(2);
    expect(w.candidateReadAt[1] - w.candidateReadAt[0]).toBeGreaterThanOrEqual(1900);
  }, 30_000);
});
