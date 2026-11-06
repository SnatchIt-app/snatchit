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
interface Pi { id: string; client_secret: string; status: string; livemode: boolean; amount: number; currency: string; customer: string; metadata: Record<string, string> }
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
  binding?: 'ok'|'missing'|'error'|'malformed'|'wrong-pi'|'wrong-buyer'|'wrong-session'|'wrong-amount'|'invalid-state';
  lostFirstPost?: boolean;
  recoveryFailure?: string;
  missingLivemode?: boolean;
  badSecret?: boolean;
  knownRecoveryPi?: string;
  knownPiOverride?: Partial<{ id: string; client_secret: unknown; status: string; livemode: unknown; amount: number; currency: string; customer: string; metadata: Record<string, string> }>;
  replayOnly?: boolean;
  replayHoldsLive?: false | null | 'missing';
  insertRace?: 'exact' | 'wrong-total' | 'wrong-buyer' | 'wrong-fee' | 'wrong-mode' | 'wrong-seller' | 'wrong-listing';
  persistRace?: 'wrong-total' | 'wrong-buyer' | 'wrong-fee' | 'wrong-mode' | 'wrong-seller' | 'succeeded';
  attachLoss?: 'commit-lost' | 'no-commit';
  firstPiCanceled?: boolean;
  loseSaltedPost?: boolean;
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
  let lostKey: string | null = null;
  let lostBody: Record<string, string> | null = null;
  let lostPiId: string | null = null;
  let currentCustomer = CUSTOMER;
  let currentFeeMinor = FEE;
  let replayHoldsLive: boolean | null | 'missing' = true;
  let insertRace: WorldOpts['insertRace'] | null = null;
  let persistRace: WorldOpts['persistRace'] | null = null;
  let persistReadError = false;
  let attachLoss: WorldOpts['attachLoss'] | null = null;
  let firstPiCanceled = opts.firstPiCanceled === true;
  let loseSaltedPost = opts.loseSaltedPost === true;
  let saltedLostKey: string | null = null;
  let saltedLostBody: Record<string, string> | null = null;
  const events: string[] = [];
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
      id, client_secret: `${id}_secret_x`, status: 'succeeded', livemode: false, amount: CHARGE, currency: 'usd', customer: CUSTOMER,
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
      if (name === 'read_payment_attempt_recovery') {
        events.push('recovery');
        if (opts.recoveryFailure) return { error: { message: opts.recoveryFailure } };
        if (opts.knownRecoveryPi) {
          return { data: { attempt_id: 'att_known', attempt_key: 'known-key', order_id: params.p_order_id,
            buyer_id: params.p_buyer_id, session_id: params.p_session_id, pi_id: opts.knownRecoveryPi, state: 'open',
            face_minor: FACE, buyer_fee_minor: FEE, amount_minor: CHARGE, currency: 'USD',
            create_request: { amount: String(CHARGE), currency: 'usd', 'payment_method_types[0]': 'card', customer: CUSTOMER, setup_future_usage: 'on_session', 'metadata[rail]': 'native_primary', 'metadata[mode]': 'native_primary', 'metadata[order_id]': params.p_order_id, 'metadata[buyer_id]': params.p_buyer_id, 'metadata[org_id]': ORG, 'metadata[session_id]': params.p_session_id } } };
        }
        if (saltedLostKey && saltedLostBody) {
          return { data: { attempt_id: 'att_salted', attempt_key: saltedLostKey, order_id: params.p_order_id,
            buyer_id: params.p_buyer_id, session_id: params.p_session_id, pi_id: null, state: 'creating',
            face_minor: FACE, buyer_fee_minor: FEE, amount_minor: CHARGE, currency: 'USD', create_request: saltedLostBody } };
        }
        if (lostKey && lostBody && lostPiId !== null) {
          return { data: { attempt_id: 'att_lost', attempt_key: lostKey, order_id: params.p_order_id,
            buyer_id: params.p_buyer_id, session_id: params.p_session_id, pi_id: lostPiId, state: 'open',
            face_minor: FACE, buyer_fee_minor: FEE, amount_minor: CHARGE, currency: 'USD', create_request: lostBody } };
        }
        if (lostKey && lostBody && lostPiId === null) {
          return { data: { attempt_id: 'att_lost', attempt_key: lostKey, order_id: params.p_order_id,
            buyer_id: params.p_buyer_id, session_id: params.p_session_id, pi_id: null, state: 'creating',
            face_minor: FACE, buyer_fee_minor: FEE, amount_minor: CHARGE, currency: 'USD', create_request: lostBody } };
        }
        return { error: { message: 'precondition_failed: recovery needs exactly one non-canceled attempt (found 0)' } };
      }
      if (name === 'store_payment_attempt_request') {
        events.push('store');
        return { data: {
          attempt_id: params.p_attempt_id, order_id: params.p_order_id, buyer_id: params.p_buyer_id,
          session_id: params.p_session_id, pi_id: null, state: 'creating',
          face_minor: FACE, buyer_fee_minor: Number((params.p_create_request as Record<string, string>).amount) - FACE,
          amount_minor: Number((params.p_create_request as Record<string, string>).amount), currency: 'USD',
          create_request: params.p_create_request,
        } };
      }
      if (name === 'read_payment_attempt_binding') {
        events.push('binding');

        if (opts.binding === 'error') return { error: { message: 'binding read failed (test)' } };
        if (opts.binding === 'missing') return { data: null };
        if (opts.binding === 'malformed') return { data: { attempt_id: 'att' } };
        const b = opts.binding ?? 'ok';
        return { data: {
          attempt_id: 'att_replay', order_id: params.p_order_id,
          buyer_id: b === 'wrong-buyer' ? 'buyer-other' : params.p_buyer_id,
          session_id: b === 'wrong-session' ? 'session-other' : params.p_session_id,
          pi_id: b === 'wrong-pi' ? 'pi_other' : params.p_pi_id,
          state: b === 'invalid-state' ? 'creating' : 'open',
          face_minor: FACE, buyer_fee_minor: FEE,
          amount_minor: b === 'wrong-amount' ? CHARGE + 1 : CHARGE, currency: 'USD',
        } };
      }
      if (name === 'create_primary_checkout') {
        if (opts.replayOnly) {
          return { data: { status: 'idempotency_replay', order_id: orderUuid(1), total_minor: FACE, currency: 'USD', order_status: 'pending', holds_live: true } };
        }
        const k = `${BUYER}|${String(params.p_command_key)}`;
        const existing = orders.get(k);
        // 20261027031000:190-191 (and the unique_violation loser, :496-497):
        // status/order_id/total_minor/currency — no org_id, no fee fields.
        // Registry 198 (DESIGN-198-FINAL §3.1 BLOCKS P1/P3, §4.1) adds
        // order_status + holds_live to both; this suite is about the replay
        // path proper, so its order is always pending with live holds — one
        // of the two shapes A-2 lets through to recoverReplayQuote (the other
        // is a replay with no order_status key at all, the pre-198 shape). A-2's
        // other arms are pinned in primary-checkout-198-arms.test.ts.
        if (existing) {
          return {
            data: {
              status: 'idempotency_replay', order_id: existing, total_minor: FACE, currency: 'USD',
              order_status: 'pending', ...(replayHoldsLive === 'missing' ? {} : { holds_live: replayHoldsLive }),
            },
          };
        }
        const orderId = orderUuid(orders.size + 1);
        orders.set(k, orderId);
        // :515-519 — the success return, the ONLY one carrying org_id.
        return {
          data: {
            status: 'ok', order_id: orderId, ...(opts.omitOrgId ? {} : { org_id: ORG }),
            total_minor: FACE, currency: 'USD', buyer_fee_minor: currentFeeMinor, charge_total_minor: FACE + currentFeeMinor,
          },
        };
      }
      if (name === 'begin_payment_attempt') {
        return { data: { attempt_id: `att_${String(params.p_attempt_key)}`, attempt_key: params.p_attempt_key, state: 'creating', pi_id: null } };
      }
      if (name === 'attach_payment_attempt') {
        events.push('attach');
        if (attachLoss) {
          const mode = attachLoss; attachLoss = null;
          if (mode === 'commit-lost') lostPiId = String(params.p_pi_id);
          return { error: { message: 'attach response lost (test)' } };
        }
        return { data: { attempt_id: params.p_attempt_id, state: 'open', pi_id: params.p_pi_id, replay: false } };
      }
      if (name === 'mark_payment_attempt_by_pi') {
        events.push('mark');
        return { data: { attempt_id: `att_${String(params.p_pi_id)}`, state: params.p_state, pi_id: params.p_pi_id } };
      }
      // cancel_pending_order is DELIBERATELY unmodelled: it answers this error,
      // so A-3's abort-cancel (DESIGN-198-FINAL §4.2 A-3) fails and a dead
      // attempt's order stays pending — the RES-1 state this suite needs (a
      // process that died outside any catch, or whose abort-cancel failed).
      // The successful abort is pinned in primary-checkout-198-arms.test.ts.
      return { error: { message: `unmocked rpc ${name}` } };
    },
    tables: {
      profiles: (q: QueryCall) => (q.op === 'select' ? { data: { stripe_customer_id: opts.noCustomer ? null : currentCustomer } } : { data: null }),
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
          events.push('payments_write');
          const b = q.body as Record<string, unknown>;
          if (insertRace) {
            const row = { ...(b as PayRow), id: `pay_${rows.length + 1}`, created_at: tick() } as PayRow;
            if (insertRace === 'wrong-total') row.total = CHARGE + 1;
            if (insertRace === 'wrong-buyer') row.buyer_id = 'buyer-other';
            if (insertRace === 'wrong-fee') row.buyer_fee = FEE + 1;
            if (insertRace === 'wrong-mode') row.mode = 'legacy';
            if (insertRace === 'wrong-seller') row.seller_id = 'seller-other';
            if (insertRace === 'wrong-listing') row.listing_id = 'listing-other';
            rows.push(row);
            insertRace = null;
            return { error: { message: 'duplicate key value violates unique constraint', code: '23505' } };
          }
          if (rows.some((r) => r.stripe_payment_intent_id === b.stripe_payment_intent_id)) {
            return { error: { message: 'duplicate key value violates unique constraint', code: '23505' } };
          }
          rows.push({ ...(b as PayRow), id: `pay_${rows.length + 1}`, created_at: tick() });
          return { data: null };
        }
        if (q.op === 'select') {
          const piFilter = q.filters.find((f) => f[0] === 'eq' && f[1] === 'stripe_payment_intent_id');
          if (piFilter) {
            events.push('payments_select_pi');
            if (persistReadError) return { error: { message: 'payments read failed (test)' } };
            const piId = piFilter[2] as string;
            if (persistRace && !rows.some((r) => r.stripe_payment_intent_id === piId)) {
              const row: PayRow = {
                id: `pay_race_${rows.length + 1}`, buyer_id: BUYER, mode: 'native_primary', amount: FACE,
                buyer_fee: FEE, seller_fee: 0, total: CHARGE, status: 'pending',
                stripe_payment_intent_id: piId, created_at: tick(), listing_id: null, seller_id: null,
              };
              if (persistRace === 'wrong-total') row.total = CHARGE + 1;
              if (persistRace === 'wrong-buyer') row.buyer_id = 'buyer-other';
              if (persistRace === 'wrong-fee') row.buyer_fee = FEE + 1;
              if (persistRace === 'wrong-mode') row.mode = 'legacy';
              if (persistRace === 'wrong-seller') row.seller_id = 'seller-other';
              if (persistRace === 'succeeded') row.status = 'succeeded';
              rows.push(row);
              persistRace = null;
            }
          }
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

  if (opts.knownRecoveryPi) {
    pis.set(opts.knownRecoveryPi, { id: opts.knownRecoveryPi, client_secret: `${opts.knownRecoveryPi}_secret`, status: 'requires_payment_method', livemode: false, amount: CHARGE, currency: 'usd', customer: CUSTOMER, metadata: { rail: 'native_primary', mode: 'native_primary', order_id: orderUuid(1), buyer_id: BUYER, org_id: ORG, session_id: SESSION }, ...opts.knownPiOverride } as Pi);
  }
  const stripe = mockStripe(async (c: StripeCall) => {
    if (c.method === 'GET' && c.path.startsWith('/customers/')) return { ok: true, data: { id: c.path.split('/')[2] } };
    if (c.method === 'POST' && c.path === '/customers') return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === `/customers/${CUSTOMER}`) return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === '/ephemeral_keys') {
      return opts.ephemeralKeyFails
        ? { ok: false, status: 500, data: { error: { type: 'api_error' } } }
        : { ok: true, data: { secret: 'ek_test_secret' } };
    }
    if (c.method === 'POST' && c.path === '/payment_intents') {
      events.push('stripe_post');
      if (mintHold) { mintHold.reached(); await mintHold.gate; }
      // Stripe idempotency: the same key replays the same object.
      const prior = c.idempotencyKey ? piByIdemKey.get(c.idempotencyKey) : undefined;
      if (prior) return { ok: true, data: { ...pis.get(prior)! } };
      const body = c.body as Record<string, string>;
      const id = `pi_test_native_${pis.size + 1}`;
      const metadata: Record<string, string> = {};
      for (const [k, v] of Object.entries(body)) if (k.startsWith('metadata[')) metadata[k.slice('metadata['.length, -1)] = v;
      const pi: Pi = { id, client_secret: opts.badSecret ? ({ bad: true } as unknown as string) : `${id}_secret_x`, status: firstPiCanceled ? 'canceled' : 'requires_payment_method', livemode: opts.missingLivemode ? undefined as unknown as boolean : false, amount: Number(body.amount), currency: 'usd', customer: CUSTOMER, metadata };
      firstPiCanceled = false;
      pis.set(id, pi);
      if (c.idempotencyKey) piByIdemKey.set(c.idempotencyKey, id);
      if (loseSaltedPost && c.idempotencyKey?.includes('_u')) {
        loseSaltedPost = false; saltedLostKey = c.idempotencyKey; saltedLostBody = body;
        return { ok: false, status: 500, data: { error: { message: 'salted response lost (test)' } } };
      }
      if (opts.lostFirstPost && lostKey === null) {
        lostKey = c.idempotencyKey ?? null; lostBody = body; lostPiId = null;
        return { ok: false, status: 500, data: { error: { message: 'response lost after create' } } };
      }
      return { ok: true, data: { ...pi } };
    }
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      events.push('stripe_get');
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
    const body = await json(res); events.push('response'); return { res, body };
  };
  const piMints = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
  const blockerAlerts = () => edge.sentry.filter((s) => (s.ctx as { activation_blocker?: boolean } | undefined)?.activation_blocker === true);

  const piGets = (piId: string) => stripe.calls.filter((c) => c.method === 'GET' && c.path === `/payment_intents/${piId}`).length;

  return {
    run, rows, pis, stripe, sb, edge, piMints, piGets, blockerAlerts, candidateReadAt, events,
    setCurrentCustomer: (c: string) => { currentCustomer = c; },
    setCurrentFee: (n: number) => { currentFeeMinor = n; },
    getCurrentFee: () => currentFeeMinor,
    setReplayHoldsLive: (h: false | null | 'missing') => { replayHoldsLive = h; },
    setInsertRace: (v: WorldOpts['insertRace'] | null) => { insertRace = v; },
    setPersistRace: (v: WorldOpts['persistRace'] | null) => { persistRace = v; },
    setPersistReadError: (v: boolean) => { persistReadError = v; },
    setAttachLoss: (v: WorldOpts['attachLoss'] | null) => { attachLoss = v; },
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
    console.log('ALL_RPCS', w.sb.rpcs.map((r:any)=>r.name)); expect(second.body.code).toBeUndefined();
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

describe('lost POST recovery negative controls', () => {
  it('generic recovery RPC failure on real replay is 503, after first lost POST, with no extra PI POST/secret', async () => {
    const w = await world({ lostFirstPost: true, recoveryFailure: 'read unavailable (test)' });
    const first = await w.run('cmd-rec-fail');
    expect(first.res.status).toBe(500);
    const second = await w.run('cmd-rec-fail');
    expect(second.res.status).toBe(503);
    expect(second.body).not.toHaveProperty('clientSecret');
    expect(w.events).toContain('recovery');
    expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(1);
  });
  it('found-zero recovery remains 409 quote_unavailable on real replay', async () => {
    const w = await world({ lostFirstPost: true, recoveryFailure: 'precondition_failed: recovery needs exactly one non-canceled attempt (found 0)' });
    await w.run('cmd-found-zero');
    const second = await w.run('cmd-found-zero');
    expect(second.res.status).toBe(409);
    expect(second.body.code).toBe('quote_unavailable');
    expect(w.events).toContain('recovery');
    expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(1);
  });
  it('final binding missing/malformed/wrong PI after recovery POST/attach/paymentswrite returns no secret', async () => {
    for (const binding of ['missing', 'malformed', 'wrong-pi'] as const) {
      const w = await world({ lostFirstPost: true, binding });
      await w.run('cmd-binding-fail');
      const second = await w.run('cmd-binding-fail');
      expect(second.res.status).not.toBe(200);
      expect(second.body).not.toHaveProperty('clientSecret');
      expect(w.events).toContain('recovery');
      expect(w.events).toContain('stripe_post');
      expect(w.events).toContain('attach');
      expect(w.events).toContain('payments_write');
      expect(w.events).toContain('binding');
    }
  });
  it('missing livemode, invalid client_secret object fail closed', async () => {
    for (const opts of [{ lostFirstPost: true, missingLivemode: true }, { lostFirstPost: true, badSecret: true }]) {
      const w = await world(opts);
      await w.run('cmd-bad-pi');
      const r = await w.run('cmd-bad-pi');
      expect(r.res.status).not.toBe(200);
      expect(r.body).not.toHaveProperty('clientSecret');
    }
  });
});

describe('lost POST recovery with no payments row', () => {
  it('same key/body recovers exactly one PI, attaches, persists, returns secret with stored customer', async () => {
    const w = await world({ lostFirstPost: true });
    const first = await w.run('cmd-lost-recover');
    expect(first.res.status).toBe(500);
    expect(first.body).not.toHaveProperty('clientSecret');
    expect(w.rows).toHaveLength(0);
    const second = await w.run('cmd-lost-recover');
    expect(second.res.status).toBe(200);
    expect(second.body.clientSecret).toBe('pi_test_native_1_secret_x');
    expect(second.body.customerEphemeralKeySecret).toBe('ek_test_secret');
    const posts = w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
    expect(posts).toHaveLength(2);
    expect(posts[0].idempotencyKey).toBe(posts[1].idempotencyKey);
    expect(posts[1].body).toEqual(posts[0].body);
    expect([...w.pis.keys()]).toHaveLength(1);
    expect(w.rows).toHaveLength(1);
    expect(w.rows[0]).toMatchObject({ amount: FACE, buyer_fee: FEE, total: CHARGE, stripe_livemode: false });
    expect(w.events).toEqual(['store', 'stripe_post', 'response', 'recovery', 'stripe_post', 'attach', 'payments_select_pi', 'payments_write', 'binding', 'response']);
  });
});

describe('known open PI recovery with no payments row', () => {
  it('GETs the exact PI and makes ZERO new POST before secret', async () => {
    const w = await world({ replayOnly: true, knownRecoveryPi: 'pi_known_recovery' });
    const r = await w.run('cmd-known');
    expect(r.res.status).toBe(200);
    expect(r.body.clientSecret).toBe('pi_known_recovery_secret');
    expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(0);
    expect(w.events).toContain('recovery');
    expect(w.events).toContain('stripe_get');
    expect(w.events).toContain('attach');
    expect(w.events).toContain('payments_write');
    expect(w.events).toContain('binding');
  });
});

describe('recovery current customer and holds gates', () => {
  it('changed current customer refuses before any recovery PI POST/secret/paymentwrite', async () => {
    const w = await world({ lostFirstPost: true });
    await w.run('cmd-customer');
    w.setCurrentCustomer('cus_changed');
    const r = await w.run('cmd-customer');
    expect(r.res.status).toBe(503);
    expect(r.body).not.toHaveProperty('clientSecret');
    expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(1);
    expect(w.events).not.toContain('payments_write');
  });
  for (const [label, holds] of [['false', false], ['null', null], ['missing', 'missing']] as const) {
    it(`replay holds_live ${label} uses hold-invalid with zero recovery PI POST/secret`, async () => {
      const w = await world({ lostFirstPost: true });
      await w.run(`cmd-holds-${label}`);
      w.setReplayHoldsLive(holds as false | null | 'missing');
      const r = await w.run(`cmd-holds-${label}`);
      expect(r.res.status).toBe(409);
      expect(r.body.code).toBe('hold_invalid');
      expect(r.body).not.toHaveProperty('clientSecret');
      expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(1);
    });
  }
});

describe('recovery preserves the stored quote', () => {
  it('new current fee affects a separate fresh checkout, not the lost-POST original quote', async () => {
    const w = await world({ lostFirstPost: true });
    await w.run('cmd-fee');
    const firstPosts = w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
    const firstKey = firstPosts[0].idempotencyKey;
    const firstBody = firstPosts[0].body as Record<string, string>;
    w.setCurrentFee(FEE + 777);

    const fresh = await w.run('cmd-fee-fresh');
    expect(fresh.res.status).toBe(200);
    expect(fresh.body.buyer_fee).toBe(FEE + 777);
    expect(fresh.body.total).toBe(FACE + FEE + 777);

    const replay = await w.run('cmd-fee');
    expect(replay.res.status).toBe(200);
    expect(replay.body.buyer_fee).toBe(FEE);
    expect(replay.body.total).toBe(CHARGE);
    const originalPosts = w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents' && c.idempotencyKey === firstKey);
    expect(originalPosts).toHaveLength(2);
    expect(originalPosts[1].body).toEqual(firstBody);
    expect(firstBody.amount).toBe(String(CHARGE));

    const before = w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents').length;
    const r = await w.run('cmd-fee', { expected_total_cents: CHARGE + 1 });
    expect(r.res.status).toBe(409);
    expect(r.body.code).toBe('total_mismatch');
    expect(r.body).not.toHaveProperty('clientSecret');
    expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(before);
  });
});

describe('known-PI recovery payments-row controls', () => {
  const base = { replayOnly: true, knownRecoveryPi: 'pi_known_recovery' } as const;
  const posts = (w: Awaited<ReturnType<typeof world>>) => w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');
  const idx = (w: Awaited<ReturnType<typeof world>>, e: string, from = 0) => w.events.indexOf(e, from);

  it('exact pending row created by INSERT 23505 is reread, never upserted; secret only after binding', async () => {
    const w = await world({ ...base });
    w.setInsertRace('exact');
    const r = await w.run('cmd-row-race-ok');
    expect(r.res.status).toBe(200);
    expect(r.body.clientSecret).toBeDefined();
    expect(rowsCount(w)).toBe(1);
    expect(posts(w)).toHaveLength(0);
    const firstSelect = idx(w, 'payments_select_pi');
    const insert = idx(w, 'payments_write');
    const reread = idx(w, 'payments_select_pi', firstSelect + 1);
    const binding = idx(w, 'binding');
    expect(firstSelect).toBeGreaterThan(-1);
    expect(insert).toBeGreaterThan(firstSelect);
    expect(reread).toBeGreaterThan(insert);
    expect(binding).toBeGreaterThan(reread);
    expect(idx(w, 'response', binding)).toBeGreaterThan(binding);
  });

  for (const race of ['wrong-buyer', 'wrong-fee', 'wrong-total', 'wrong-mode', 'wrong-seller', 'wrong-listing'] as const) {
    it(`23505 reread with ${race} refuses 503, no secret, one row, no extra PI POST`, async () => {
      const w = await world({ ...base });
      w.setInsertRace(race);
      const r = await w.run(`cmd-row-race-${race}`);
      expect(r.res.status).toBe(503);
      expect(r.body).not.toHaveProperty('clientSecret');
      expect(rowsCount(w)).toBe(1);
      expect(posts(w)).toHaveLength(0);
    });
  }

  it('row inserted between candidate scan and persist select hits mismatch branch; no blind insert/overwrite', async () => {
    const w = await world({ ...base });
    w.setPersistRace('wrong-total');
    const r = await w.run('cmd-row-persist-race');
    expect(w.candidateReadAt.length).toBeGreaterThan(0);
    expect(r.res.status).toBe(503);
    expect(r.body).not.toHaveProperty('clientSecret');
    expect(rowsCount(w)).toBe(1);
    expect(posts(w)).toHaveLength(0);
    expect(w.events).not.toContain('payments_write');
    expect(idx(w, 'payments_select_pi')).toBeGreaterThan(-1);
  });

  it('exact succeeded row answers already_paid and is never overwritten', async () => {
    const w = await world({ ...base });
    w.setPersistRace('succeeded');
    const r = await w.run('cmd-row-terminal');
    expect(r.res.status).toBe(409);
    expect(r.body.code).toBe('already_paid');
    expect(r.body).not.toHaveProperty('clientSecret');
    expect(rowsCount(w)).toBe(1);
    expect(w.rows[0].status).toBe('succeeded');
    expect(w.events).not.toContain('payments_write');
    expect(posts(w)).toHaveLength(0);
  });

  it('payments persist read error refuses 503 with no secret/insert/POST', async () => {
    const w = await world({ ...base });
    w.setPersistReadError(true);
    const r = await w.run('cmd-row-read-error');
    expect(r.res.status).toBe(503);
    expect(r.body).not.toHaveProperty('clientSecret');
    expect(rowsCount(w)).toBe(0);
    expect(w.events).not.toContain('payments_write');
    expect(posts(w)).toHaveLength(0);
  });
});

function rowsCount(w: { rows: unknown[] }): number { return w.rows.length; }

describe('lost attach and authoritative canceled remint', () => {
  const posts = (w: Awaited<ReturnType<typeof world>>) => w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');

  it('attach commits but response is lost: retry is GET-only, idempotent attach, then one secret', async () => {
    const w = await world({ lostFirstPost: true });
    expect((await w.run('cmd-attach-lost')).res.status).toBe(500);
    w.setAttachLoss('commit-lost');
    expect((await w.run('cmd-attach-lost')).res.status).toBe(503);
    const before = posts(w).length;
    const r = await w.run('cmd-attach-lost');
    expect(r.res.status).toBe(200);
    expect(r.body.clientSecret).toBeDefined();
    expect(posts(w)).toHaveLength(before);
    expect(w.rows).toHaveLength(1);
    expect(w.events.filter((e) => e === 'attach').length).toBeGreaterThanOrEqual(2);
  });

  it('attach never commits: retry uses the same POST key/body and only one Stripe PI', async () => {
    const w = await world({ lostFirstPost: true });
    expect((await w.run('cmd-attach-nocommit')).res.status).toBe(500);
    w.setAttachLoss('no-commit');
    expect((await w.run('cmd-attach-nocommit')).res.status).toBe(503);
    const r = await w.run('cmd-attach-nocommit');
    expect(r.res.status).toBe(200);
    const ps = posts(w);
    expect(ps.length).toBeGreaterThanOrEqual(3);
    expect(new Set(ps.map((p) => p.idempotencyKey)).size).toBe(1);
    expect(ps.every((p) => JSON.stringify(p.body) === JSON.stringify(ps[0].body))).toBe(true);
    expect(w.pis.size).toBe(1);
    expect(w.rows).toHaveLength(1);
  });

  it('fresh canceled PI remints deterministically; lost salted POST retries the SAME salted key/body, one live PI', async () => {
    const w = await world({ firstPiCanceled: true, loseSaltedPost: true });
    expect((await w.run('cmd-remint')).res.status).toBe(500);
    const first = posts(w);
    expect(first).toHaveLength(2);
    expect(first[1].idempotencyKey).toBe(`${first[0].idempotencyKey}_upi_test_native_1`);
    const r = await w.run('cmd-remint');
    expect(r.res.status).toBe(200);
    const all = posts(w);
    expect(all[all.length - 1].idempotencyKey).toBe(first[1].idempotencyKey);
    expect(all[all.length - 1].body).toEqual(first[1].body);
    expect([...w.pis.values()].filter((p) => p.status !== 'canceled')).toHaveLength(1);
    expect([...w.pis.values()].filter((p) => p.status === 'canceled')).toHaveLength(1);
  });

  it('confirmed canceled PI is attached/marked canceled before 409, never open forever, no secret', async () => {
    const w = await world({ replayOnly: true, knownRecoveryPi: 'pi_known_recovery', knownPiOverride: { status: 'canceled' } });
    const r = await w.run('cmd-canceled-recovery');
    expect(r.res.status).toBe(409);
    expect(r.body.code).toBe('replay_state_unavailable');
    expect(r.body).not.toHaveProperty('clientSecret');
    expect(w.events).toContain('attach');
    expect(w.events).toContain('mark');
    expect(w.events).not.toContain('payments_write');
    expect(posts(w)).toHaveLength(0);
  });
});

describe('replay abort isolation', () => {
  it('a successful fresh checkout and its replay never call cancel_pending_order for the owner order', async () => {
    const w = await world();
    expect((await w.run('cmd-replay-isolation')).res.status).toBe(200);
    expect((await w.run('cmd-replay-isolation')).res.status).toBe(200);
    expect(w.sb.rpcs.some((r: { name: string }) => r.name === 'cancel_pending_order')).toBe(false);
  });
});

describe('known PI recovery identity/quote matrix', () => {
  const base = { replayOnly: true, knownRecoveryPi: 'pi_known_recovery' } as const;
  const cases: Array<[string, Record<string, unknown>, number]> = [
    ['wrong id', { id: 'pi_other' }, 503],
    ['wrong customer', { customer: 'cus_other' }, 503],
    ['wrong amount', { amount: CHARGE + 1 }, 503],
    ['wrong currency', { currency: 'eur' }, 503],
    ['wrong order metadata', { metadata: { rail: 'native_primary', mode: 'native_primary', order_id: 'other', buyer_id: BUYER, org_id: ORG, session_id: SESSION } }, 503],
    ['wrong buyer metadata', { metadata: { rail: 'native_primary', mode: 'native_primary', order_id: orderUuid(1), buyer_id: 'other', org_id: ORG, session_id: SESSION } }, 503],
    ['wrong session metadata', { metadata: { rail: 'native_primary', mode: 'native_primary', order_id: orderUuid(1), buyer_id: BUYER, org_id: ORG, session_id: 'other' } }, 503],
    ['wrong org metadata', { metadata: { rail: 'native_primary', mode: 'native_primary', order_id: orderUuid(1), buyer_id: BUYER, org_id: 'other', session_id: SESSION } }, 503],
    ['wrong rail', { metadata: { rail: 'other', mode: 'native_primary', order_id: orderUuid(1), buyer_id: BUYER, org_id: ORG, session_id: SESSION } }, 503],
    ['wrong mode', { metadata: { rail: 'native_primary', mode: 'other', order_id: orderUuid(1), buyer_id: BUYER, org_id: ORG, session_id: SESSION } }, 503],
    ['canceled', { status: 'canceled' }, 409],
    ['processing', { status: 'processing' }, 409],
    ['succeeded', { status: 'succeeded' }, 409],
    ['missing secret', { client_secret: undefined }, 409],
    ['number secret', { client_secret: 123 }, 409],
    ['object secret', { client_secret: { x: 1 } }, 409],
    ['whitespace secret', { client_secret: '   ' }, 409],
    ['missing livemode', { livemode: undefined }, 503],
    ['nonboolean livemode', { livemode: 'false' }, 503],
  ];
  for (const [label, override, status] of cases) {
    it(`${label} refuses with status ${status}, no POST/secret/paymentswrite`, async () => {
      const w = await world({ ...base, knownPiOverride: override as never });
      const r = await w.run(`cmd-known-${label}`);
      expect(r.res.status).toBe(status);
      expect(r.body).not.toHaveProperty('clientSecret');
      expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(0);
      expect(w.events).toContain('recovery');
      expect(w.events).toContain('stripe_get');
      expect(w.events).not.toContain('payments_write');
    });
  }
  for (const live of [false, true]) {
    it(`valid known PI persists livemode ${live}`, async () => {
      const w = await world({ ...base, knownPiOverride: { livemode: live } as never });
      const r = await w.run(`cmd-known-live-${live}`);
      expect(r.res.status).toBe(200);
      expect(w.rows[0].stripe_livemode).toBe(live);
      expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(0);
    });
  }
});

describe('replay attempt binding gate', () => {
  const cases: Array<[string, 'missing'|'error'|'malformed'|'wrong-pi'|'wrong-buyer'|'wrong-session'|'wrong-amount'|'invalid-state']> = [
    ['missing', 'missing'], ['error', 'error'], ['malformed', 'malformed'], ['wrong PI', 'wrong-pi'],
    ['wrong buyer', 'wrong-buyer'], ['wrong session', 'wrong-session'],
    ['wrong charge', 'wrong-amount'], ['invalid state', 'invalid-state'],
  ];
  for (const [label, binding] of cases) {
    it(`${label} binding sends NO client secret and makes NO new PI POST`, async () => {
      const w = await world({ binding });
      await w.run('cmd-bind');
      const postsAfterFirst = w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents').length;
      const second = await w.run('cmd-bind');
      expect(second.res.status).not.toBe(200);
      expect(second.body).not.toHaveProperty('clientSecret');
      expect(w.stripe.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents')).toHaveLength(postsAfterFirst);
    });
  }
});
});
