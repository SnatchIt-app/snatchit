/** Focused real-handler tests for the local attempt-coordination wiring. */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { totalMismatch } from '../supabase/functions/_shared/money';

const ENV = { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', PRIMARY_CHECKOUT_REPLAY_REREAD_MS: '0' };
const SESSION = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';
const TICKET = 'b2c3d4e5-f6a7-4b8c-9dae-1f2a3b4c5d6e';
const HOLD = 'c3d4e5f6-a7b8-4c9d-aeb1-2a3b4c5d6e7f';
const ORG = 'd4e5f6a7-b8c9-4dae-bf12-3b4c5d6e7f8a';
const BUYER = 'buyer-attempt-1';
const CUSTOMER = 'cus_attempt_1';
const ORDER = 'aaaa0001-bbbb-4ccc-8ddd-eeee00000001';
const FACE = 2500, FEE = 300, CHARGE = 2800;

async function world(opts: { beginError?: boolean; beginMalformed?: boolean; attachError?: boolean; canceledFirst?: boolean; loseFirstPost?: boolean; beginKey?: string; beginState?: string; beginPi?: string | null; beginAttemptId?: string; attachState?: string; attachPi?: string; attachAttemptId?: string; attachLoseFirst?: boolean; remintCanceled?: boolean; storeError?: boolean; storeMalformed?: boolean; storeForeignQuote?: boolean; storeBadState?: boolean; paymentInsertError?: boolean; cancelMode?: 'ok'|'bad-id'|'processing'|'succeeded'|'404'|'network'|'malformed'; markError?: boolean; markMalformed?: boolean; markMissing?: boolean } = {}) {
  const rpcs: Array<{ name: string; params: Record<string, unknown> }> = [];
  const calls: StripeCall[] = [];
  const pis = new Map<string, Record<string, unknown>>();
  const byKey = new Map<string, string>();
  let lostPost = false;
  let lostAttach = false;
  const events: string[] = [];
  const attempts = new Map<string, { state: string; pi_id: string | null }>();
  const keyToId = new Map<string, string>();
  let attemptNo = 0;
  const sb = mockSupabase({
    user: { id: BUYER, email: 'b@example.test' },
    rpc: (name, params) => {
      rpcs.push({ name, params });
      if (name === 'check_rate_limit') return { data: true };
      if (name === 'is_deletion_pending') return { data: false };
      if (name === 'create_primary_checkout') return { data: {
        status: 'ok', order_id: ORDER, org_id: ORG, total_minor: FACE, currency: 'USD',
        buyer_fee_minor: FEE, charge_total_minor: CHARGE,
      } };
      if (name === 'begin_payment_attempt') {
        events.push('begin');
        if (opts.beginError) return { error: { message: 'begin unavailable (test)' } };
        if (opts.beginMalformed) return { data: { attempt_key: params.p_attempt_key } };
        const key = String(params.p_attempt_key);
        const id = keyToId.get(key) ?? `attempt_${++attemptNo}`;
        if (!keyToId.has(key)) { keyToId.set(key, id); attempts.set(id, { state: 'creating', pi_id: null }); }
        return { data: { attempt_id: opts.beginAttemptId ?? id, attempt_key: opts.beginKey ?? key, state: opts.beginState ?? attempts.get(id)!.state, pi_id: opts.beginPi !== undefined ? opts.beginPi : attempts.get(id)!.pi_id } };
      }
      if (name === 'store_payment_attempt_request') {
        events.push('store');
        if (opts.storeError) return { error: { message: 'store unavailable (test)' } };
        if (opts.storeMalformed) return { data: { attempt_id: 'other' } };
        return { data: {
          attempt_id: params.p_attempt_id, order_id: params.p_order_id, buyer_id: params.p_buyer_id,
          session_id: params.p_session_id, pi_id: null, state: opts.storeBadState ? 'canceled' : 'creating',
          face_minor: 2500, buyer_fee_minor: 300,
          amount_minor: opts.storeForeignQuote ? 9999 : 2800, currency: 'USD',
          create_request: params.p_create_request,
        } };
      }
      if (name === 'attach_payment_attempt') {

        events.push('attach');
        if (opts.attachError) return { error: { message: 'attach unavailable (test)' } };
        const id = String(params.p_attempt_id);
        const a = attempts.get(id);
        if (!a) return { error: { message: 'attempt missing' } };
        if (a.pi_id && a.pi_id !== params.p_pi_id) return { error: { message: 'different PI' } };
        a.pi_id = String(params.p_pi_id); a.state = 'open';
        if (opts.attachLoseFirst && !lostAttach) { lostAttach = true; return { error: { message: 'attach committed but response lost' } }; }
        return { data: { attempt_id: opts.attachAttemptId ?? id, state: opts.attachState ?? 'open', pi_id: opts.attachPi ?? a.pi_id, replay: false } };
      }
      if (name === 'mark_payment_attempt_by_pi') {
        events.push('mark');
        if (opts.markError) return { error: { message: 'mark unavailable (test)' } };
        if (opts.markMalformed) return { data: { attempt_id: 'x' } };
        if (opts.markMissing) return { error: { message: 'attempt missing' } };
        const a = [...attempts.values()].find((x) => x.pi_id === params.p_pi_id);
        if (!a) return { error: { message: 'attempt missing' } };
        a.state = String(params.p_state);
        return { data: { attempt_id: 'x', state: a.state, pi_id: a.pi_id } };
      }
      if (name === 'cancel_pending_order') {
        if ([...attempts.values()].some((a) => a.state !== 'canceled')) {
          return { error: { message: 'precondition_failed: order has an unresolved payment attempt' } };
        }
        events.push('order_cancel');
        return { data: { status: 'cancelled', order_id: params.p_order_id } };
      }
      return { error: { message: `unmocked ${name}` } };
    },
    tables: {
      profiles: (q: QueryCall) => q.op === 'select' ? { data: { stripe_customer_id: CUSTOMER } } : { data: null },
      payments: (q: QueryCall) => q.op === 'insert' ? (opts.paymentInsertError ? { error: { code: '23514', message: 'check failed (test)' } } : { data: null }) : q.op === 'select' ? { data: null } : { data: null },
    },
  });
  const stripe = mockStripe(async (c: StripeCall) => {
    calls.push(c);
    if (c.method === 'GET' && c.path === `/customers/${CUSTOMER}`) return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === '/ephemeral_keys') return { ok: true, data: { secret: 'ek' } };
    if (c.method === 'POST' && c.path.startsWith('/payment_intents/') && c.path.endsWith('/cancel')) {
      events.push('stripe_cancel');
      const id = c.path.split('/')[2];
      if (opts.cancelMode === 'network') throw new Error('cancel network (test)');
      if (opts.cancelMode === '404') return { ok: false, status: 404, data: { error: { message: 'missing' } } };
      if (opts.cancelMode === 'malformed') return { ok: true, data: null };
      if (opts.cancelMode === 'bad-id') return { ok: true, data: { id: 'pi_other', status: 'canceled' } };
      if (opts.cancelMode === 'processing') return { ok: true, data: { id, status: 'processing' } };
      if (opts.cancelMode === 'succeeded') return { ok: true, data: { id, status: 'succeeded' } };
      return { ok: true, data: { id, status: 'canceled' } };
    }
    if (c.method === 'POST' && c.path === '/payment_intents') {
      const key = c.idempotencyKey ?? '';
      if (byKey.has(key)) return { ok: true, data: pis.get(byKey.get(key)!)! };
      const body = c.body as Record<string, string>;
      const id = `pi_attempt_${pis.size + 1}`;
      const metadata: Record<string, string> = {};
      for (const [k, v] of Object.entries(body)) if (k.startsWith('metadata[')) metadata[k.slice('metadata['.length, -1)] = v;
      const status = (opts.canceledFirst && pis.size === 0) || (opts.remintCanceled && pis.size === 1) ? 'canceled' : 'requires_payment_method';
      const pi = { id, client_secret: `${id}_secret`, status, livemode: false, amount: Number(body.amount), currency: 'usd', metadata };
      pis.set(id, pi); byKey.set(key, id);
      if (opts.loseFirstPost && !lostPost) {
        lostPost = true;
        events.push('stripe_post');
        return { ok: false, status: 500, data: { error: { message: 'response lost after create' } } };
      }
      events.push('stripe_post');
      return { ok: true, data: { ...pi } };
    }
    return { ok: false, status: 404, data: { error: { message: 'unmocked' } } };
  });
  const edge = await loadEdgeHandler('supabase/functions/primary-checkout/index.ts', {
    supabase: sb, env: { ...ENV },
    provide: { stripeFetch: stripe.stripeFetch, stripeFetchRaw: stripe.stripeFetchRaw, STRIPE_MOBILE_API_VERSION: '2024-04-10', totalMismatch },
  });
  const run = async (key: string, extra: Record<string, unknown> = {}) => {
    const res = await edge.handler(authedJsonRequest({ session_id: SESSION, items: [{ ticket_type_id: TICKET, quantity: 1 }], hold_ids: [HOLD], command_key: key, ...extra }));
    const body = await json(res); events.push('response'); return { res, body };
  };
  return { rpcs, calls, pis, attempts, events, run };
}

const postCalls = (w: Awaited<ReturnType<typeof world>>) => w.calls.filter((c) => c.method === 'POST' && c.path === '/payment_intents');

describe('primary-checkout attempt coordination', () => {
  it('begins before the first Stripe POST and attaches before returning the secret', async () => {
    const w = await world();
    const { res, body } = await w.run('cmd-happy');
    expect(res.status).toBe(200);
    expect(w.events).toEqual(['begin', 'store', 'stripe_post', 'attach', 'response']);
    expect(postCalls(w)).toHaveLength(1);
    expect(w.rpcs.find((r) => r.name === 'attach_payment_attempt')?.params.p_pi_id).toBe(body.paymentIntentId);
  });

  it('missing/error/malformed/foreign-quote/state storage sends NO PI POST or secret', async () => {
    for (const patch of [{ storeError: true }, { storeMalformed: true }, { storeForeignQuote: true }, { storeBadState: true }]) {
      const w = await world(patch);
      const { res, body } = await w.run('cmd-store-bad');
      expect(res.status).toBe(500);
      expect(body).not.toHaveProperty('clientSecret');
      expect(postCalls(w)).toHaveLength(0);
    }
  });

  it('begin error fails closed before any Stripe POST/secret', async () => {
    const w = await world({ beginError: true });
    const { res, body } = await w.run('cmd-begin-error');
    expect(res.status).toBe(500);
    expect(body).not.toHaveProperty('clientSecret');
    expect(postCalls(w)).toHaveLength(0);
  });

  it('malformed begin result fails closed before any Stripe POST/secret', async () => {
    const w = await world({ beginMalformed: true });
    const { res, body } = await w.run('cmd-begin-malformed');
    expect(res.status).toBe(500);
    expect(body).not.toHaveProperty('clientSecret');
    expect(postCalls(w)).toHaveLength(0);
  });

  it('attach error sends no client secret', async () => {
    const w = await world({ attachError: true });
    const { res, body } = await w.run('cmd-attach-error');
    expect(res.status).toBe(500);
    expect(body).not.toHaveProperty('clientSecret');
    expect(postCalls(w)).toHaveLength(1);
  });

  it('a lost POST response retries under the SAME persisted key and same PI', async () => {
    const w = await world({ loseFirstPost: true });
    const first = await w.run('cmd-lost');
    expect(first.res.status).toBe(500);
    expect(first.body).not.toHaveProperty('clientSecret');
    const second = await w.run('cmd-lost');
    expect(second.res.status).toBe(200);
    const posts = postCalls(w);
    expect(posts).toHaveLength(2);
    expect(posts[0].idempotencyKey).toBe(posts[1].idempotencyKey);
    expect(second.body.paymentIntentId).toBe([...w.pis.keys()][0]);
  });

  it('rejects a foreign key/state/PI shape from begin before Stripe POST', async () => {
    for (const patch of [{ beginKey: 'DIFFERENT-key' }, { beginState: 'invalid-state' }, { beginPi: 'pi_foreign' }, { beginState: 'open', beginPi: null }]) {
      const w = await world(patch);
      const { res, body } = await w.run('cmd-bad-begin');
      expect(res.status).toBe(500);
      expect(body).not.toHaveProperty('clientSecret');
      expect(postCalls(w)).toHaveLength(0);
    }
  });

  it('rejects canceled/unknown/mismatched attach outcomes without a secret', async () => {
    for (const patch of [{ attachState: 'canceled' }, { attachState: 'unknown' }, { attachPi: 'pi_other' }, { attachAttemptId: 'attempt_other' }]) {
      const w = await world(patch);
      const { res, body } = await w.run('cmd-bad-attach');
      expect(res.status).toBe(500);
      expect(body).not.toHaveProperty('clientSecret');
      expect(postCalls(w)).toHaveLength(1);
    }
  });

  it('a canceled remint never returns a secret', async () => {
    const w = await world({ canceledFirst: true, remintCanceled: true });
    const { res, body } = await w.run('cmd-remint-canceled');
    expect(res.status).toBe(500);
    expect(body).not.toHaveProperty('clientSecret');
    expect(postCalls(w)).toHaveLength(2);
  });

  it('attach commits but its response is lost; exact retry recovers without a second PI', async () => {
    const w = await world({ attachLoseFirst: true });
    const first = await w.run('cmd-attach-lost');
    expect(first.res.status).toBe(500);
    expect(first.body).not.toHaveProperty('clientSecret');
    const second = await w.run('cmd-attach-lost');
    expect(second.res.status).toBe(200);
    expect(postCalls(w)).toHaveLength(2);
    expect(postCalls(w)[0].idempotencyKey).toBe(postCalls(w)[1].idempotencyKey);
  });

  it('payments-insert failure: exact Stripe cancel → mark canceled → order cancel, then refusal', async () => {
    const w = await world({ paymentInsertError: true });
    const { res, body } = await w.run('cmd-insert-fail');
    expect(res.status).toBe(503);
    expect(body).not.toHaveProperty('clientSecret');
    const iCancel = w.events.indexOf('stripe_cancel');
    const iMark = w.events.indexOf('mark');
    const iOrder = w.events.indexOf('order_cancel');
    expect(iCancel).toBeGreaterThan(-1);
    expect(iMark).toBeGreaterThan(iCancel);
    expect(iOrder).toBeGreaterThan(iMark);
    expect(w.rpcs.filter((r) => r.name === 'mark_payment_attempt_by_pi')).toHaveLength(1);
    expect(w.rpcs.filter((r) => r.name === 'cancel_pending_order')).toHaveLength(1);
  });

  for (const mode of ['bad-id', 'processing', 'succeeded', '404', 'network', 'malformed'] as const) {
    it(`payments-insert failure with cancel ${mode}: no mark/order cancel, pending preserved`, async () => {
      const w = await world({ paymentInsertError: true, cancelMode: mode });
      const { body } = await w.run(`cmd-cancel-bad-${mode}`);
      expect(body).not.toHaveProperty('clientSecret');
      expect(w.events).toContain('stripe_cancel');
      expect(w.events).not.toContain('mark');
      expect(w.events).not.toContain('order_cancel');
      expect([...w.attempts.values()].every((a) => a.state !== 'canceled')).toBe(true);
    });
  }

  for (const patch of [{ markError: true }, { markMalformed: true }, { markMissing: true }] as const) {
    it(`cancel ok but mark ${Object.keys(patch)[0]} blocks order cancel`, async () => {
      const w = await world({ paymentInsertError: true, ...patch });
      await w.run(`cmd-mark-bad-${Object.keys(patch)[0]}`);
      expect(w.events).toContain('stripe_cancel');
      expect(w.events).toContain('mark');
      expect(w.events).not.toContain('order_cancel');
      expect([...w.attempts.values()].every((a) => a.state !== 'canceled')).toBe(true);
    });
  }

  it('pre-attempt quote refusal still cancels the order (no Stripe PI ever created)', async () => {
    const w = await world();
    const { res } = await w.run('cmd-pre-attempt', { expected_total_cents: CHARGE + 1 });
    expect(res.status).toBe(409);
    expect(w.events).toContain('order_cancel');
    expect(w.events).not.toContain('begin');
    expect(w.events).not.toContain('stripe_cancel');
    expect(w.attempts.size).toBe(0);
  });

  it('unknown/lost POST leaves the attempt recoverable and never cancels this order', async () => {
    const w = await world({ loseFirstPost: true });
    const first = await w.run('cmd-unknown-post');
    expect(first.res.status).toBe(500);
    expect(first.body).not.toHaveProperty('clientSecret');
    expect(w.events).not.toContain('stripe_cancel');
    expect(w.events).not.toContain('order_cancel');
    expect([...w.attempts.values()][0].state).toBe('creating');
    const second = await w.run('cmd-unknown-post');
    expect(second.res.status).toBe(200);
    expect(postCalls(w)).toHaveLength(2);
    expect(postCalls(w)[0].idempotencyKey).toBe(postCalls(w)[1].idempotencyKey);
  });

  it('a canceled first PI uses a persisted deterministic remint key', async () => {
    const w = await world({ canceledFirst: true });
    const { res, body } = await w.run('cmd-remint');
    expect(res.status).toBe(200);
    const posts = postCalls(w);
    expect(posts).toHaveLength(2);
    expect(posts[1].idempotencyKey).toBe(`${posts[0].idempotencyKey}_u${(pisId(w, 0))}`);
    expect(body.paymentIntentId).toBe(pisId(w, 1));
    expect(w.events).toEqual(['begin', 'store', 'stripe_post', 'attach', 'mark', 'begin', 'store', 'stripe_post', 'attach', 'response']);
  });
});

function pisId(w: Awaited<ReturnType<typeof world>>, i: number): string {
  return [...w.pis.keys()][i];
}
