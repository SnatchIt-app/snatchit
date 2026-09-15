/**
 * tests/l1-edge-coupling.test.ts — L1 (B-2, release sprint 2026-09): a stale
 * cancellation or failure must never free the Buy-Now hold that the buyer's
 * REPLACEMENT attempt is using.
 *
 * Loads the REAL stripe-webhook and create-payment-intent handlers
 * (tests/helpers/edge-vm.ts) against ONE shared in-memory world — payments
 * rows, the listing's hold, Stripe PaymentIntents — so the two handlers race
 * exactly as production can: Stripe may deliver payment_intent.canceled
 * before create-payment-intent's next statement runs.
 *
 * The world's RPCs model the database contracts the edges rely on:
 *   * release_reservation(listing, buyer)        — pre-127, buyer-scoped: frees
 *     the hold whenever the buyer holds it (the L1 defect's mechanism).
 *   * release_reservation_for_payment(l, b, pay) — 127: bound to one payment,
 *     refuses while another buy_now attempt by the buyer is pending/processing
 *     (live_sibling_attempt). Only that rule is modelled here; 127's full SQL
 *     is pinned by pgTAP 194.
 *
 * Contract under test (docs/release/PRODUCTION_RELEASE_PACKAGE.md, "127's
 * required edge changes and deployment coupling"):
 *   W. stripe-webhook claims only pending/processing rows and releases through
 *      release_reservation_for_payment(listing, buyer, payment.id); an absent RPC
 *      (DB without 127) is logged and non-fatal, with no fallback to the
 *      buyer-scoped release.
 *   C. create-payment-intent inserts the replacement (P2) pending row BEFORE it
 *      cancels the superseded intent (P1); P2's secret is returned only after P1
 *      is provably cancelled; on refusal P2 is cancelled and ALWAYS retired
 *      locally (its secret was never exposed), and the 409 is unchanged.
 * Every case here fails against the pre-sprint handlers at df9e0d3 except the
 * ones labelled "preservation".
 */
import { describe, expect, it } from 'vitest';
import {
  authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, signedStripeWebhookRequest,
  type QueryCall, type RpcHandler, type StripeCall,
} from './helpers/edge-vm';
import { dollarsToCents, feeBreakdown, totalMismatch } from '../supabase/functions/_shared/money';

const SECRET = 'whsec_test_only';
const LISTING = 'listing-0001';
const SELLER = 'seller-0001';
const HOLDER = 'buyer-holder';
const CUSTOMER = 'cus_test_1';

type Status = 'pending' | 'processing' | 'succeeded' | 'failed' | 'refunded';
interface PaymentRow {
  id: string; stripe_payment_intent_id: string | null; status: Status; listing_id: string; buyer_id: string;
  seller_id: string; mode: string; total: number; amount: number; created_at: string;
}
interface Pi { id: string; status: string; amount: number; currency: string; client_secret: string }

const inFuture = () => new Date(Date.now() + 5 * 60_000).toISOString();

function world(init: { payments: PaymentRow[]; pis: Pi[]; price?: number; rpcAbsent?: boolean;
  /** migration 130 absent (PGRST202) or erroring for the checkout claim RPCs */
  claimRpc?: 'present' | 'absent' | 'error';
  /** an unordered SELECT may legitimately return the newest row first (Postgres heap order) */
  unorderedNewestFirst?: boolean;
  /** the first N claim calls see another request's brief claim (e.g. a double tap mid-reuse) */
  claimHeldTimes?: number;
  /** delay a Stripe call whose path matches, once (a stalled network call) */
  stall?: { match: RegExp; ms: number };
  /** delay the payments INSERT (a stalled database call) */
  insertStallMs?: number;
  /** extra env for create-payment-intent (e.g. shrunken E-1 budgets) */
  checkoutEnv?: Record<string, string>;
  /** migration 132 absent (PGRST202) or erroring for the group claim RPCs */
  groupRpc?: 'present' | 'absent' | 'error';
  /** the first N group claims see another request's brief claim */
  groupHeldTimes?: number;
  /** Stripe replays an intent for a repeated idempotency key (returning its current state) */
  idempotentStripe?: boolean;
}) {
  const payments = init.payments.map((p) => ({ ...p }));
  const pis = new Map(init.pis.map((p) => [p.id, { ...p }]));
  const listing = {
    id: LISTING, seller_id: SELLER, current_bid: 100, buy_now_price: init.price ?? 200, buy_now_enabled: true,
    status: 'reserved', auction_status: 'active', winner_user_id: null, winning_bid_amount: null,
    reserved_by: HOLDER as string | null, reserved_until: inFuture() as string | null, ends_at: inFuture(),
  };
  const timeline: string[] = [];
  const completedEvents = new Set<string>();
  let nextPi = 1;

  const match = (row: Record<string, unknown>, filters: unknown[][]) => filters.every((f) => {
    const [op, col] = f as [string, string];
    if (op === 'eq') return row[col] === f[2];
    if (op === 'neq') return row[col] !== f[2];
    if (op === 'in') return (f[2] as unknown[]).includes(row[col]);
    if (op === 'not' && f[2] === 'in') {
      const list = String(f[3]).replace(/[()"]/g, '').split(',');
      return !list.includes(String(row[col]));
    }
    throw new Error(`world: unmodelled filter ${JSON.stringify(f)}`);
  });

  const paymentsTable = async (q: QueryCall) => {
    const rows = payments as unknown as Record<string, unknown>[];
    if (q.op === 'insert') {
      if (init.insertStallMs) await new Promise((r) => setTimeout(r, init.insertStallMs));
      const body = q.body as Record<string, unknown>;
      if (rows.some((r) => r.stripe_payment_intent_id === body.stripe_payment_intent_id)) {
        return { data: null, error: { message: 'duplicate key', code: '23505' } };
      }
      if (insertFails) { timeline.push(`db:insert-failed:${String(body.stripe_payment_intent_id)}`); return { data: null, error: { message: 'insert boom', code: 'XX000' } }; }
      const row = { id: `pay_${String(body.stripe_payment_intent_id)}`, created_at: new Date().toISOString(), ...body } as unknown as PaymentRow;
      payments.push(row);
      timeline.push(`db:insert:${row.stripe_payment_intent_id}`);
      return { data: null };
    }
    const hit = rows.filter((r) => match(r, q.filters));
    if (q.op === 'update') {
      for (const r of hit) Object.assign(r, q.body as Record<string, unknown>);
      for (const r of hit) timeline.push(`db:update:${String(r.stripe_payment_intent_id)}->${String((q.body as Record<string, unknown>).status)}`);
      return { data: q.terminal === 'list' ? hit : hit[0] ?? null };
    }
    let out = hit;
    const ord = q.order.find((o) => o[0] === 'created_at');
    const desc = ord ? (ord[1] as { ascending?: boolean } | undefined)?.ascending === false : !!init.unorderedNewestFirst;
    if (ord || init.unorderedNewestFirst) {
      out = [...hit].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)) || rows.indexOf(a) - rows.indexOf(b));
      if (desc) out.reverse();
    }
    return { data: q.terminal === 'list' ? out : out[0] ?? null };
  };

  // migration 130 model: one fresh claim per (listing, buyer, mode) group, token-bound release
  let tokenSeq = 0;
  let heldLeft = init.claimHeldTimes ?? 0;
  const claimOf = new Map<string, string>();
  const claimLog: string[] = [];

  // migration 132 model: one durable record per (listing, buyer, mode) group, token-bound release
  const groupOf = new Map<string, string>();
  const groupLog: string[] = [];
  let groupHeldLeft = init.groupHeldTimes ?? 0;
  const gkey = (l: unknown, b: unknown, m: unknown) => `${String(l)}|${String(b)}|${String(m)}`;

  const rpc: RpcHandler = (name, params) => {
    if (name === 'check_rate_limit') return { data: true };
    if (name === 'claim_checkout_group' || name === 'release_checkout_group') {
      if ((init.groupRpc ?? 'present') === 'absent') return { data: null, error: { message: `Could not find the function public.${name}`, code: 'PGRST202' } };
      if (init.groupRpc === 'error') return { data: null, error: { message: 'connection reset', code: '08006' } };
      const k = gkey(params.p_listing_id, params.p_buyer_id, params.p_mode);
      if (name === 'claim_checkout_group') {
        if (groupHeldLeft > 0) { groupHeldLeft--; groupLog.push(`group-held:${String(params.p_mode)}`); timeline.push('db:group-held'); return { data: { claimed: false, claim_token: null, reason: 'claim_held' } }; }
        if (groupOf.has(k)) { groupLog.push(`group-held:${String(params.p_mode)}`); timeline.push('db:group-held'); return { data: { claimed: false, claim_token: null, reason: 'claim_held' } }; }
        const tok = `gtok_${++tokenSeq}`;
        groupOf.set(k, tok);
        groupLog.push(`group-claim:${String(params.p_mode)}`); timeline.push('db:group-claim');
        return { data: { claimed: true, claim_token: tok, reason: 'claimed' } };
      }
      const cur = groupOf.get(k);
      if (!cur) return { data: { released: false, reason: 'not_claimed' } };
      if (cur !== params.p_claim_token) return { data: { released: false, reason: 'token_mismatch' } };
      groupOf.delete(k);
      groupLog.push(`group-release:${String(params.p_mode)}`); timeline.push('db:group-release');
      return { data: { released: true, reason: 'released' } };
    }
    if (name === 'claim_stripe_webhook_event') return { data: completedEvents.has(String(params.p_event_id)) ? 'already_processed' : 'claimed' };
    if (name === 'complete_stripe_webhook_event') { completedEvents.add(String(params.p_event_id)); return { data: true }; }
    if (name === 'fail_stripe_webhook_event') return { data: true };
    if (name === 'claim_checkout_supersede' || name === 'release_checkout_supersede') {
      if ((init.claimRpc ?? 'present') === 'absent') return { data: null, error: { message: `Could not find the function public.${name}`, code: 'PGRST202' } };
      if (init.claimRpc === 'error') return { data: null, error: { message: 'connection reset', code: '08006' } };
    }
    if (name === 'claim_checkout_supersede') {
      const payRow = payments.find((p) => p.id === params.p_payment_id);
      if (!payRow) return { data: { claimed: false, claim_token: null, holder_payment_id: null, reason: 'unknown_payment' } };
      if (payRow.status !== 'pending') return { data: { claimed: false, claim_token: null, holder_payment_id: null, reason: 'not_pending' } };
      if (heldLeft > 0) { heldLeft--; claimLog.push(`held:${payRow.stripe_payment_intent_id}`); return { data: { claimed: false, claim_token: null, holder_payment_id: payRow.id, reason: 'claim_held' } }; }
      const holder = payments.find((p) => p.listing_id === payRow.listing_id && p.buyer_id === payRow.buyer_id && p.mode === payRow.mode
        && p.status === 'pending' && claimOf.has(p.id));
      if (holder) { claimLog.push(`held:${payRow.stripe_payment_intent_id}`); return { data: { claimed: false, claim_token: null, holder_payment_id: holder.id, reason: 'claim_held' } }; }
      const tok = `tok_${++tokenSeq}`;
      claimOf.set(payRow.id, tok);
      (payRow as unknown as Record<string, unknown>).supersede_claim_token = tok;
      claimLog.push(`claim:${payRow.stripe_payment_intent_id}`);
      return { data: { claimed: true, claim_token: tok, holder_payment_id: payRow.id, reason: 'claimed' } };
    }
    if (name === 'release_checkout_supersede') {
      const tok = claimOf.get(String(params.p_payment_id));
      if (!tok) return { data: { released: false, reason: 'not_claimed' } };
      if (tok !== params.p_claim_token) return { data: { released: false, reason: 'token_mismatch' } };
      claimOf.delete(String(params.p_payment_id));
      const relRow = payments.find((p) => p.id === params.p_payment_id);
      if (relRow) (relRow as unknown as Record<string, unknown>).supersede_claim_token = null;
      claimLog.push(`release:${payments.find((p) => p.id === params.p_payment_id)?.stripe_payment_intent_id}`);
      return { data: { released: true, reason: 'released' } };
    }
    if (name === 'release_reservation') {
      timeline.push(`rpc:release_reservation:${String(params.p_user_id)}`);
      if (listing.status === 'reserved' && listing.reserved_by === params.p_user_id) {
        listing.status = 'active'; listing.reserved_by = null; listing.reserved_until = null;
      }
      return { data: null };
    }
    if (name === 'release_reservation_for_payment') {
      timeline.push(`rpc:release_reservation_for_payment:${String(params.p_payment_id)}`);
      if (init.rpcAbsent) return { data: null, error: { message: 'Could not find the function public.release_reservation_for_payment', code: 'PGRST202' } };
      const pay = payments.find((p) => p.id === params.p_payment_id);
      if (!pay) return { data: { released: false, reason: 'unknown_payment' } };
      if (pay.listing_id !== params.p_listing_id || pay.buyer_id !== params.p_user_id) return { data: { released: false, reason: 'payment_not_for_listing_buyer' } };
      if (listing.status !== 'reserved' || listing.reserved_by !== params.p_user_id) return { data: { released: false, reason: 'not_held_by_buyer' } };
      const sibling = payments.some((p) => p.id !== pay.id && p.listing_id === pay.listing_id && p.buyer_id === pay.buyer_id
        && p.mode === 'buy_now' && (p.status === 'pending' || p.status === 'processing'));
      if (sibling) return { data: { released: false, reason: 'live_sibling_attempt' } };
      listing.status = 'active'; listing.reserved_by = null; listing.reserved_until = null;
      return { data: { released: true, reason: 'released' } };
    }
    return { data: null };
  };

  let insertFails = false;
  let fastWebhook = false;
  let cancelThrowsFor: string | null = null;
  let onCancel: ((id: string) => Promise<void>) | null = null;

  const webhookSb = mockSupabase({ rpc, tables: { payments: paymentsTable, listings: () => ({ data: { event_name: 'Fixture' } }) } });
  const webhook = async () => loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
    supabase: webhookSb,
    env: { STRIPE_WEBHOOK_SECRET: SECRET, STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
    provide: { stripeFetchRaw: async () => ({ ok: false, status: 500, data: {} }) },
  });
  let evtSeq = 0;
  const deliver = async (type: string, piId: string, eventId?: string) => {
    const edge = await webhook();
    const pi = pis.get(piId);
    const event = {
      id: eventId ?? `evt_${++evtSeq}_${type}_${piId}`, type,
      data: { object: {
        id: piId, object: 'payment_intent', status: pi?.status ?? 'canceled', amount: pi?.amount ?? 0, amount_received: 0,
        currency: 'usd', livemode: false, metadata: { mode: 'buy_now', listing_id: LISTING, buyer_id: HOLDER, seller_id: SELLER },
      } },
    };
    timeline.push(`webhook:${type}:${piId}`);
    const res = await edge.handler(signedStripeWebhookRequest(SECRET, event));
    return { res, body: await json(res), edge };
  };

  let stallUsed = false;
  const idemKeys = new Map<string, string>();
  let onCreate: (() => Promise<void>) | null = null;
  const stripe = mockStripe(async (c: StripeCall) => {
    if (init.stall && !stallUsed && init.stall.match.test(`${c.method} ${c.path}`)) {
      stallUsed = true;
      timeline.push(`stripe:stall:${c.method} ${c.path}`);
      await new Promise((r) => setTimeout(r, init.stall!.ms));
      timeline.push(`stripe:stall-end:${c.method} ${c.path}`);
    }
    if (c.method === 'GET' && c.path === `/customers/${CUSTOMER}`) return { ok: true, data: { id: CUSTOMER } };
    if (c.method === 'POST' && c.path === '/ephemeral_keys') return { ok: true, data: { secret: 'ek_test_secret' } };
    if (c.method === 'POST' && c.path === '/payment_intents') {
      if (onCreate) { const hook = onCreate; onCreate = null; await hook(); }
      if (init.idempotentStripe && c.idempotencyKey && idemKeys.has(c.idempotencyKey)) {
        const replay = pis.get(idemKeys.get(c.idempotencyKey)!)!;
        timeline.push(`stripe:replay:${replay.id}`);
        return { ok: true, data: { ...replay, livemode: false } };
      }
      const id = `pi_new${nextPi++}`;
      if (c.idempotencyKey) idemKeys.set(c.idempotencyKey, id);
      const body = c.body as Record<string, string>;
      const pi = { id, status: 'requires_payment_method', amount: Number(body.amount), currency: 'usd', client_secret: `${id}_secret` };
      pis.set(id, pi);
      timeline.push(`stripe:create:${id}`);
      return { ok: true, data: { ...pi, livemode: false } };
    }
    if (c.method === 'POST' && c.path.endsWith('/cancel')) {
      const id = c.path.split('/')[2];
      if (onCancel) { const hook = onCancel; onCancel = null; await hook(id); }
      const pi = pis.get(id);
      if (cancelThrowsFor === id) { timeline.push(`stripe:cancel-threw:${id}`); throw new Error('network'); }
      if (!pi || pi.status === 'processing' || pi.status === 'succeeded') {
        timeline.push(`stripe:cancel-refused:${id}`);
        return { ok: false, status: 400, data: { error: { code: 'payment_intent_unexpected_state', message: `This PaymentIntent cannot be canceled because it has a status of ${pi?.status ?? 'unknown'}.` } } };
      }
      pi.status = 'canceled';
      timeline.push(`stripe:cancel:${id}`);
      if (fastWebhook) await deliver('payment_intent.canceled', id);
      return { ok: true, data: { id, status: 'canceled' } };
    }
    if (c.method === 'GET' && c.path.startsWith('/payment_intents/')) {
      const pi = pis.get(c.path.split('/')[2]);
      return pi ? { ok: true, data: { ...pi } } : { ok: false, status: 404, data: { error: { message: 'no such pi' } } };
    }
    return { ok: false, status: 404, data: { error: { message: `unmocked ${c.method} ${c.path}` } } };
  });

  const checkoutSb = mockSupabase({
    user: { id: HOLDER, email: `${HOLDER}@example.test` },
    rpc,
    tables: {
      listings: (q) => (q.filters.some((f) => f[0] === 'eq' && f[1] === 'id' && f[2] === LISTING) ? { data: { ...listing } } : { data: null, error: { message: 'not found' } }),
      profiles: () => ({ data: { stripe_customer_id: CUSTOMER } }),
      payments: paymentsTable,
      checkout_group_claim: (q) => {
        const f = (col: string) => q.filters.find((x) => x[0] === 'eq' && x[1] === col)?.[2];
        const tok = groupOf.get(gkey(f('listing_id'), f('buyer_id'), f('mode')));
        return { data: tok ? { claim_token: tok } : null };
      },
    },
  });
  const checkout = async (body: Record<string, unknown>) => {
    const edge = await loadEdgeHandler('supabase/functions/create-payment-intent/index.ts', {
      supabase: checkoutSb,
      env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', ...(init.checkoutEnv ?? {}) },
      provide: { feeBreakdown, dollarsToCents, totalMismatch, stripeFetch: stripe.stripeFetch, stripeFetchRaw: stripe.stripeFetchRaw, STRIPE_MOBILE_API_VERSION: '2024-04-10' },
    });
    const res = await edge.handler(authedJsonRequest(body));
    return { res, body: await json(res), edge };
  };

  return {
    payments, pis, listing, timeline, stripe, webhookSb, deliver, checkout,
    set fastWebhook(v: boolean) { fastWebhook = v; },
    set insertFails(v: boolean) { insertFails = v; },
    set cancelThrowsFor(v: string | null) { cancelThrowsFor = v; },
    set onCancel(v: ((id: string) => Promise<void>) | null) { onCancel = v; },
    set onCreate(v: (() => Promise<void>) | null) { onCreate = v; },
    /** simulate the claim going stale and another request reclaiming the group */
    stealClaim: (piId: string) => {
      const row = payments.find((p) => p.stripe_payment_intent_id === piId)!;
      const tok = `tok_stolen_${++tokenSeq}`;
      claimOf.set(row.id, tok);
      (row as unknown as Record<string, unknown>).supersede_claim_token = tok;
      claimLog.push(`stolen:${piId}`);
    },
    claimsOutstanding: () => claimOf.size,
    claimLog,
    groupLog,
    groupClaimsOutstanding: () => groupOf.size,
    /** simulate the group claim going stale and another request reclaiming it */
    stealGroupClaim: (mode = 'buy_now') => { groupOf.set(gkey(LISTING, HOLDER, mode), `gtok_stolen_${++tokenSeq}`); groupLog.push('group-stolen'); },
    /** seed Stripe's idempotency cache: `key` replays intent `piId` */
    seedIdempotency: (key: string, piId: string) => { idemKeys.set(key, piId); },
    checkoutSb,
    holdIntact: () => listing.status === 'reserved' && listing.reserved_by === HOLDER,
    row: (pi: string) => payments.find((p) => p.stripe_payment_intent_id === pi),
    rpcCalls: (name: string) => webhookSb.rpcs.filter((r) => r.name === name),
  };
}

const pay = (pi: string, status: Status, over: Partial<PaymentRow> = {}): PaymentRow => ({
  id: `pay_${pi}`, stripe_payment_intent_id: pi, status, listing_id: LISTING, buyer_id: HOLDER, seller_id: SELLER,
  mode: 'buy_now', total: 22000, amount: 20000, created_at: new Date(Date.now() - 60_000).toISOString(), ...over,
});
const pi = (id: string, status = 'requires_payment_method', amount = 22000): Pi => ({ id, status, amount, currency: 'usd', client_secret: `${id}_secret` });
const logged = (edge: { logs: Array<{ args: unknown[] }> }) => edge.logs.map((l) => l.args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')).join('\n');

describe('L1 — stripe-webhook claims only live attempts and releases per payment', () => {
  it('W1: a canceled event for a row create-payment-intent already retired claims nothing and leaves the replacement\'s hold', async () => {
    const w = world({ payments: [pay('pi_old', 'failed'), pay('pi_p2', 'pending')], pis: [pi('pi_old', 'canceled'), pi('pi_p2')] });
    const { res } = await w.deliver('payment_intent.canceled', 'pi_old');
    expect(res.status).toBe(200);
    expect(w.holdIntact()).toBe(true);
    expect(w.rpcCalls('release_reservation')).toHaveLength(0);
    expect(w.rpcCalls('release_reservation_for_payment')).toHaveLength(0);
    expect(w.row('pi_old')?.status).toBe('failed');
  });

  it('W2: a claimable pending row releases through release_reservation_for_payment bound to THAT payment, never the buyer-scoped RPC', async () => {
    const w = world({ payments: [pay('pi_only', 'pending')], pis: [pi('pi_only')] });
    const { res, edge } = await w.deliver('payment_intent.payment_failed', 'pi_only');
    expect(res.status).toBe(200);
    expect(w.rpcCalls('release_reservation')).toHaveLength(0);
    const calls = w.rpcCalls('release_reservation_for_payment');
    expect(calls).toHaveLength(1);
    expect(calls[0].params).toEqual({ p_listing_id: LISTING, p_user_id: HOLDER, p_payment_id: 'pay_pi_only' });
    expect(w.listing.status).toBe('active');
    expect(logged(edge)).toMatch(/release_reservation_for_payment/);
    expect(logged(edge)).toMatch(/"released":true/);
  });

  it('W3: a failure on P1 while the buyer\'s P2 is still pending keeps the hold (live_sibling_attempt), logged, 200', async () => {
    const w = world({ payments: [pay('pi_old', 'pending'), pay('pi_p2', 'pending')], pis: [pi('pi_old'), pi('pi_p2')] });
    const { res, edge } = await w.deliver('payment_intent.payment_failed', 'pi_old');
    expect(res.status).toBe(200);
    expect(w.holdIntact()).toBe(true);
    expect(w.row('pi_old')?.status).toBe('failed');
    expect(logged(edge)).toMatch(/live_sibling_attempt/);
  });

  it('W4 (preservation): a late payment_failed after success claims nothing and releases nothing', async () => {
    const w = world({ payments: [pay('pi_paid', 'succeeded')], pis: [pi('pi_paid', 'succeeded')] });
    const { res } = await w.deliver('payment_intent.payment_failed', 'pi_paid');
    expect(res.status).toBe(200);
    expect(w.row('pi_paid')?.status).toBe('succeeded');
    expect(w.rpcCalls('release_reservation')).toHaveLength(0);
    expect(w.rpcCalls('release_reservation_for_payment')).toHaveLength(0);
    expect(w.holdIntact()).toBe(true);
  });

  it('W5 (preservation): the same event delivered twice releases at most once', async () => {
    const w = world({ payments: [pay('pi_dup', 'pending')], pis: [pi('pi_dup')] });
    await w.deliver('payment_intent.payment_failed', 'pi_dup', 'evt_same');
    const again = await w.deliver('payment_intent.payment_failed', 'pi_dup', 'evt_same');
    expect(again.res.status).toBe(200);
    expect([...w.rpcCalls('release_reservation'), ...w.rpcCalls('release_reservation_for_payment')]).toHaveLength(1);
  });

  it('W6: payment_failed then a DISTINCT canceled event for the same intent, with a replacement hold taken in between, frees nothing the second time', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old')] });
    await w.deliver('payment_intent.payment_failed', 'pi_old');
    // the buyer re-reserves and mints a replacement attempt
    w.listing.status = 'reserved'; w.listing.reserved_by = HOLDER; w.listing.reserved_until = inFuture();
    w.payments.push(pay('pi_p2', 'pending'));
    const second = await w.deliver('payment_intent.canceled', 'pi_old');
    expect(second.res.status).toBe(200);
    expect(w.holdIntact()).toBe(true);
  });

  it('W7: a database without 127 (RPC absent) is logged, stays 200, and never falls back to the buyer-scoped release', async () => {
    const w = world({ payments: [pay('pi_only', 'pending')], pis: [pi('pi_only')], rpcAbsent: true });
    const { res, edge } = await w.deliver('payment_intent.payment_failed', 'pi_only');
    expect(res.status).toBe(200);
    expect(w.rpcCalls('release_reservation')).toHaveLength(0);
    expect(w.rpcCalls('release_reservation_for_payment')).toHaveLength(1);
    expect(w.holdIntact()).toBe(true); // degraded: the sweep frees it at TTL
    expect(logged(edge)).toMatch(/PGRST202|release_reservation_for_payment/);
  });
});

describe('L1 — create-payment-intent mints the replacement before cancelling the superseded intent', () => {
  // The seller re-priced (22000 -> 33000) while the holder's P1 was pending: the reuse path supersedes P1.
  const repriced = () => world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300 });

  it('C1 (the race): Stripe delivers P1\'s cancel webhook before checkout\'s next statement — the hold survives and P2 is live', async () => {
    const w = repriced();
    w.fastWebhook = true;
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ total: 33000 });
    const p2 = String(body.paymentIntentId);
    expect(w.holdIntact()).toBe(true);
    expect(w.row(p2)?.status).toBe('pending');
    expect(w.row('pi_old')?.status).toBe('failed');
    expect(w.pis.get('pi_old')?.status).toBe('canceled');
  });

  it('C2: order of effects — P2 minted and its row inserted before P1 is cancelled', async () => {
    const w = repriced();
    const { body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    const p2 = String(body.paymentIntentId);
    const t = w.timeline;
    expect(t.indexOf(`stripe:create:${p2}`)).toBeGreaterThanOrEqual(0);
    expect(t.indexOf(`db:insert:${p2}`)).toBeGreaterThan(t.indexOf(`stripe:create:${p2}`));
    expect(t.indexOf('stripe:cancel:pi_old')).toBeGreaterThan(t.indexOf(`db:insert:${p2}`));
    expect(t.indexOf('db:update:pi_old->failed')).toBeGreaterThan(t.indexOf('stripe:cancel:pi_old'));
  });

  it('C3: Stripe refuses to cancel P1 (processing) — 409 price changed, no secret returned, P1 still pending, P2 cancelled and retired, hold untouched', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'processing', 22000)], price: 300 });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(String(body.error)).toMatch(/price changed/i);
    expect(body.server_total_cents).toBe(33000);
    expect(body.clientSecret).toBeUndefined();
    expect(w.row('pi_old')?.status).toBe('pending');
    const minted = w.payments.filter((p) => p.stripe_payment_intent_id !== 'pi_old');
    expect(minted).toHaveLength(1);
    for (const p of minted) {
      expect(p.status).toBe('failed');
      expect(w.pis.get(String(p.stripe_payment_intent_id))?.status).toBe('canceled');
    }
    expect(w.holdIntact()).toBe(true);
  });

  it('C4: refusal when P2\'s own cancel also fails — P2 is still retired locally, so a retry can never reuse its secret', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'processing', 22000)], price: 300 });
    w.cancelThrowsFor = 'pi_new1';
    const { res } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(w.row('pi_new1')?.status).toBe('failed');
    expect(w.row('pi_old')?.status).toBe('pending');
    // a retry must not hand back pi_new1
    const retry = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(retry.body.paymentIntentId).not.toBe('pi_new1');
  });

  it('C5: P2\'s row insert fails — P1 is not cancelled and stays reusable, P2 is cancelled, 500 unchanged', async () => {
    const w = repriced();
    w.insertFails = true;
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(500);
    expect(String(body.error)).toMatch(/Failed to record payment/);
    expect(w.pis.get('pi_old')?.status).toBe('requires_payment_method');
    expect(w.row('pi_old')?.status).toBe('pending');
    expect(w.pis.get('pi_new1')?.status).toBe('canceled');
    expect(w.holdIntact()).toBe(true);
  });

  it('C6 (preservation): a pending row whose intent Stripe already cancelled is retired locally with no new cancel call, and a fresh P2 is minted', async () => {
    const w = world({ payments: [pay('pi_dead', 'pending')], pis: [pi('pi_dead', 'canceled', 22000)] });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    expect(w.row('pi_dead')?.status).toBe('failed');
    expect(w.timeline.filter((e) => e.startsWith('stripe:cancel'))).toHaveLength(0);
    expect(w.row(String(body.paymentIntentId))?.status).toBe('pending');
  });
});

describe('L1 / 130 — every secret hand-out on a pending attempt holds the (listing, buyer, mode) claim', () => {
  const secretOf = (b: Record<string, unknown>) => (typeof b.clientSecret === 'string' ? b.clientSecret : null);

  it('C7 (the reported gap): a second request that would REUSE the replacement P2 while the first request\'s P1 cancel is refused gets no secret', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'processing', 22000)], price: 300, unorderedNewestFirst: true });
    let second: { res: Response; body: Record<string, unknown> } | null = null;
    w.onCancel = async (id) => { if (id === 'pi_old') second = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 }); };
    const first = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(first.res.status).toBe(409);
    expect(second).not.toBeNull();
    // P1 may still charge: no request may hold a live secret for another intent on this listing
    expect(secretOf(second!.body)).toBeNull();
    expect(secretOf(first.body)).toBeNull();
    expect(w.claimsOutstanding()).toBe(0);
  });

  it('C8: two concurrent supersedes of P1 — only ONE live secret is handed out', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300 });
    let second: { res: Response; body: Record<string, unknown> } | null = null;
    w.onCancel = async (id) => { if (id === 'pi_old') second = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 }); };
    const first = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    const secrets = [secretOf(first.body), secretOf(second!.body)].filter(Boolean);
    expect(secrets).toHaveLength(1);
    const live = [...w.pis.values()].filter((p) => p.id !== 'pi_old' && p.status === 'requires_payment_method'
      && w.row(p.id)?.status === 'pending');
    expect(live).toHaveLength(1);
    expect(w.claimsOutstanding()).toBe(0);
  });

  it('C9: the plain reuse path claims, returns the secret, and releases', async () => {
    const w = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)] });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    expect(body.paymentIntentId).toBe('pi_same');
    expect(w.claimLog).toEqual(['claim:pi_same', 'release:pi_same']);
    expect(w.claimsOutstanding()).toBe(0);
  });

  it('C10: the claim is released on every exit — success, refusal, insert failure, already-succeeded', async () => {
    const ok = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300 });
    expect((await ok.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 })).res.status).toBe(200);
    expect(ok.claimsOutstanding()).toBe(0);
    const refused = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'processing', 22000)], price: 300 });
    expect((await refused.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 })).res.status).toBe(409);
    expect(refused.claimsOutstanding()).toBe(0);
    const ins = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300 });
    ins.insertFails = true;
    expect((await ins.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 })).res.status).toBe(500);
    expect(ins.claimsOutstanding()).toBe(0);
    const paid = world({ payments: [pay('pi_paid_pending_row', 'pending')], pis: [pi('pi_paid_pending_row', 'succeeded', 22000)] });
    expect((await paid.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 })).res.status).toBe(400);
    expect(paid.claimsOutstanding()).toBe(0);
  });

  it('C11: migration 130 absent (PGRST202) degrades to the unclaimed #64 behaviour and reports it', async () => {
    const w = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)], claimRpc: 'absent' });
    const { res, body, edge } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    expect(body.paymentIntentId).toBe('pi_same');
    expect(edge.sentry.length + edge.logs.filter((l) => /claim_checkout_supersede/.test(l.args.map(String).join(' '))).length).toBeGreaterThan(0);
  });

  it('C12: any other claim error fails closed — 503, no secret, no mint, no cancel', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300, claimRpc: 'error' });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(503);
    expect(secretOf(body)).toBeNull();
    expect(w.timeline.filter((e) => e.startsWith('stripe:create') || e.startsWith('stripe:cancel'))).toHaveLength(0);
  });

  it('C13 (R-2): the pending attempt is chosen newest-first, never by heap order', async () => {
    const w = world({ payments: [pay('pi_old', 'pending'), pay('pi_newer', 'pending', { created_at: new Date(Date.now() - 1000).toISOString() })],
                      pis: [pi('pi_old', 'requires_payment_method', 22000), pi('pi_newer', 'requires_payment_method', 22000)] });
    const { body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(body.paymentIntentId).toBe('pi_newer');
  });

  it('C14: a claim held only briefly (a double tap mid-reuse) is waited out — the retry returns the secret instead of a 409', async () => {
    const w = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)], claimHeldTimes: 2 });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    expect(body.paymentIntentId).toBe('pi_same');
    expect(w.claimLog).toEqual(['held:pi_same', 'held:pi_same', 'claim:pi_same', 'release:pi_same']);
  });

});

describe('132 — no two concurrent requests of one (listing, buyer, mode) group can each mint (fresh-mint double charge)', () => {
  // Stripe replays an intent for a repeated idempotency key, so two requests only
  // mint twice when their keys diverge. D's disposition names three divergences;
  // each test drives one through the REAL handler with the second request running
  // while the first is inside Stripe's create. RED on the pin (aabe029): both
  // requests hand out a different live secret.
  const secretOf = (b: Record<string, unknown>) => (typeof b.clientSecret === 'string' ? b.clientSecret : null);
  const KEY0 = `pi_${LISTING}_${HOLDER}_buy_now_22000_c${CUSTOMER}`;
  type W = ReturnType<typeof world>;
  const confirmable = (w: W) => [...w.pis.values()].filter((p) => p.status === 'requires_payment_method' && w.row(p.id)?.status === 'pending').map((p) => p.id);
  const secretsHandedOut = (...bodies: Array<Record<string, unknown> | undefined>) => [...new Set(bodies.map((b) => (b ? secretOf(b) : null)).filter(Boolean))];

  it('F1 (re-price between the two reads): the second request is refused before it mints — one secret, one recorded live intent', async () => {
    const w = world({ payments: [], pis: [], idempotentStripe: true });
    let second: { res: Response; body: Record<string, unknown> } | null = null;
    w.onCreate = async () => { w.listing.buy_now_price = 300; second = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 }); };
    const first = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(second).not.toBeNull();
    expect(secretsHandedOut(first.body, second!.body)).toHaveLength(1);
    expect(confirmable(w)).toHaveLength(1);
    expect(second!.res.status).toBe(409);
    expect(w.groupClaimsOutstanding()).toBe(0);
  }, 15_000);

  it('F2 (failedAttempts flips between the two reads): one secret, one recorded live intent', async () => {
    const w = world({ payments: [pay('pi_f1', 'failed')], pis: [pi('pi_f1', 'canceled')], idempotentStripe: true });
    let second: { res: Response; body: Record<string, unknown> } | null = null;
    w.onCreate = async () => { w.payments.push(pay('pi_f2', 'failed')); second = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 }); };
    const first = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(secretsHandedOut(first.body, second!.body)).toHaveLength(1);
    expect(confirmable(w)).toHaveLength(1);
    expect(w.groupClaimsOutstanding()).toBe(0);
  }, 15_000);

  it('F3 (the canceled-replay `_u` retry): one secret, one recorded live intent', async () => {
    const w = world({ payments: [], pis: [pi('pi_dead', 'canceled')], idempotentStripe: true });
    w.seedIdempotency(KEY0, 'pi_dead');
    let second: { res: Response; body: Record<string, unknown> } | null = null;
    w.onCreate = async () => { second = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 }); };
    const first = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(secretsHandedOut(first.body, second!.body)).toHaveLength(1);
    expect(confirmable(w)).toHaveLength(1);
    expect(w.groupClaimsOutstanding()).toBe(0);
  }, 15_000);

  it('F4 (preservation): an identical double tap still ends with exactly one intent and at most one distinct secret', async () => {
    const w = world({ payments: [], pis: [], idempotentStripe: true });
    let second: { res: Response; body: Record<string, unknown> } | null = null;
    w.onCreate = async () => { second = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 }); };
    const first = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(first.res.status).toBe(200);
    expect(secretsHandedOut(first.body, second!.body)).toHaveLength(1);
    expect([...w.pis.keys()]).toHaveLength(1);
  }, 15_000);

  it('G1: the group record is taken before any Stripe create and released after the hand-out', async () => {
    const w = world({ payments: [], pis: [] });
    const { res } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    const claimAt = w.timeline.indexOf('db:group-claim');
    const createAt = w.timeline.findIndex((e) => e.startsWith('stripe:create'));
    expect(claimAt).toBeGreaterThanOrEqual(0);
    expect(claimAt).toBeLessThan(createAt);
    expect(w.timeline.indexOf('db:group-release')).toBeGreaterThan(w.timeline.findIndex((e) => e.startsWith('db:insert')));
    expect(w.groupLog).toEqual(['group-claim:buy_now', 'group-release:buy_now']);
  });

  it('G2: the group record is released on every exit — fresh mint, reuse, supersede refusal, 130 claim error, insert failure, already-succeeded', async () => {
    const cases: Array<[string, W, number, number]> = [];
    const fresh = world({ payments: [], pis: [] });
    cases.push(['fresh', fresh, 22000, 200]);
    const reuse = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)] });
    cases.push(['reuse', reuse, 22000, 200]);
    const refused = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'processing', 22000)], price: 300 });
    cases.push(['supersede-refused', refused, 33000, 409]);
    const claimErr = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], claimRpc: 'error' });
    cases.push(['130-claim-error', claimErr, 22000, 503]);
    const ins = world({ payments: [], pis: [] });
    ins.insertFails = true;
    cases.push(['insert-failure', ins, 22000, 500]);
    const paid = world({ payments: [pay('pi_paid_pending_row', 'pending')], pis: [pi('pi_paid_pending_row', 'succeeded', 22000)] });
    cases.push(['already-succeeded', paid, 22000, 400]);
    for (const [label, w, total, status] of cases) {
      const { res } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: total });
      expect([label, res.status]).toEqual([label, status]);
      expect([label, w.groupClaimsOutstanding()]).toEqual([label, 0]);
    }
  });

  it('G3: migration 132 absent (PGRST202) fails closed — 503, no Stripe create or cancel, no secret, reported', async () => {
    const w = world({ payments: [], pis: [], groupRpc: 'absent' });
    const { res, body, edge } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(503);
    expect(secretOf(body)).toBeNull();
    expect(w.timeline.filter((e) => e.startsWith('stripe:create') || e.startsWith('stripe:cancel'))).toHaveLength(0);
    expect(edge.sentry.some((s) => /claim_checkout_group/.test(String((s.error as Error)?.message ?? s.error)))).toBe(true);
  });

  it('G4: any other group claim error fails closed — 503, no mint', async () => {
    const w = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)], groupRpc: 'error' });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(503);
    expect(secretOf(body)).toBeNull();
    expect(w.timeline.filter((e) => e.startsWith('stripe:create'))).toHaveLength(0);
  });

  it('G5: a group record held only briefly is waited out — the retry mints once and returns the secret', async () => {
    const w = world({ payments: [], pis: [], groupHeldTimes: 2 });
    const { res } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(200);
    expect(w.groupLog).toEqual(['group-held:buy_now', 'group-held:buy_now', 'group-claim:buy_now', 'group-release:buy_now']);
  });

  it('G6: a group record that stays held answers 409 with no secret, no prior-payments read and no Stripe create', async () => {
    const w = world({ payments: [], pis: [], groupHeldTimes: 99 });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
    expect(body.error).toBe('Your checkout is being updated. Please try again.');
    expect(w.timeline.filter((e) => e.startsWith('stripe:create'))).toHaveLength(0);
    expect(w.checkoutSb.queries.filter((q) => q.table === 'payments' && q.op === 'select' && /stripe_payment_intent_id/.test(String(q.select)))).toHaveLength(0);
  }, 15_000);

  it('G7 (E-1): the group record is reclaimed while Stripe creates — no row, no secret, the minted intent withdrawn', async () => {
    const w = world({ payments: [], pis: [] });
    w.onCreate = async () => { w.stealGroupClaim(); };
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
    expect(w.payments.filter((p) => p.status === 'pending')).toHaveLength(0);
    expect(w.pis.get('pi_new1')?.status).toBe('canceled');
  });

  it('G8 (E-1): the group record is reclaimed while the superseded intent is being cancelled — no secret handed out', async () => {
    const w = world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300 });
    w.onCancel = async (id) => { if (id === 'pi_old') w.stealGroupClaim(); };
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
  });

  it('P1: a group attempt still processing blocks a fresh mint — 409, no Stripe create, no secret', async () => {
    const w = world({ payments: [pay('pi_proc', 'processing')], pis: [pi('pi_proc', 'processing', 22000)], idempotentStripe: true });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
    expect(w.timeline.filter((e) => e.startsWith('stripe:create'))).toHaveLength(0);
    expect(w.groupClaimsOutstanding()).toBe(0);
  });
});

describe('E-1 — the request holding the claim cannot act after it lost the claim or ran past its budget', () => {
  const secretOf = (b: Record<string, unknown>) => (typeof b.clientSecret === 'string' ? b.clientSecret : null);
  const repricedEnv = (over: Partial<Parameters<typeof world>[0]> = {}) =>
    world({ payments: [pay('pi_old', 'pending')], pis: [pi('pi_old', 'requires_payment_method', 22000)], price: 300, ...over });

  it('E1: the claim is reclaimed by another request while Stripe creates P2 — no P2 row, no secret, P1 untouched, the minted PI withdrawn', async () => {
    const w = repricedEnv();
    w.onCreate = async () => { w.stealClaim('pi_old'); };
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
    expect(w.payments.filter((p) => p.stripe_payment_intent_id !== 'pi_old')).toHaveLength(0);
    expect(w.pis.get('pi_old')?.status).toBe('requires_payment_method');
    expect(w.row('pi_old')?.status).toBe('pending');
    expect(w.pis.get('pi_new1')?.status).toBe('canceled');
  });

  it('E2: the claim is reclaimed while P1\'s cancel is in flight — no secret handed out', async () => {
    const w = repricedEnv();
    w.onCancel = async (id) => { if (id === 'pi_old') w.stealClaim('pi_old'); };
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
  });

  it('E3: a Stripe create that stalls past the per-call timeout gives up — no P2 row, no secret', async () => {
    const w = repricedEnv({ stall: { match: /^POST \/payment_intents$/, ms: 1500 }, checkoutEnv: { CHECKOUT_STRIPE_TIMEOUT_MS: '150', CHECKOUT_CLAIM_BUDGET_MS: '5000' } });
    const t0 = Date.now();
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(Date.now() - t0).toBeLessThan(1200);
    expect(res.status).toBeGreaterThanOrEqual(409);
    expect(secretOf(body)).toBeNull();
    expect(w.timeline.filter((e) => e.startsWith('db:insert'))).toHaveLength(0);
    expect(w.row('pi_old')?.status).toBe('pending');
  });

  it('E4: P1\'s cancel stalls past the timeout — treated as NOT cancelled: P2 withdrawn and retired, 409, no secret', async () => {
    const w = repricedEnv({ stall: { match: /^POST \/payment_intents\/pi_old\/cancel$/, ms: 1500 }, checkoutEnv: { CHECKOUT_STRIPE_TIMEOUT_MS: '150', CHECKOUT_CLAIM_BUDGET_MS: '5000' } });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
    expect(w.row('pi_new1')?.status).toBe('failed');
    expect(w.row('pi_old')?.status).toBe('pending');
  });

  it('E5: a stalled database write spends the section budget — the superseded intent is not touched, the replacement is withdrawn, no secret', async () => {
    const w = repricedEnv({ insertStallMs: 400, checkoutEnv: { CHECKOUT_STRIPE_TIMEOUT_MS: '2000', CHECKOUT_CLAIM_BUDGET_MS: '300' } });
    const { res, body } = await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 });
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
    expect(w.pis.get('pi_old')?.status).toBe('requires_payment_method');
    expect(w.row('pi_old')?.status).toBe('pending');
    expect(w.row('pi_new1')?.status).toBe('failed');
  });

  it('E6: plain reuse — a claim lost before the secret is returned answers 409 with no secret', async () => {
    const w = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)],
      stall: { match: /^GET \/payment_intents\/pi_same$/, ms: 50 } });
    // the GET stalls briefly; during it the claim is reclaimed
    const run = w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 });
    await new Promise((r) => setTimeout(r, 25));
    w.stealClaim('pi_same');
    const { res, body } = await run;
    expect(res.status).toBe(409);
    expect(secretOf(body)).toBeNull();
  });

  it('E7 (preservation): with the default budgets an unstalled supersede and a plain reuse still succeed', async () => {
    const w = repricedEnv();
    expect((await w.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 33000 })).res.status).toBe(200);
    const r = world({ payments: [pay('pi_same', 'pending')], pis: [pi('pi_same', 'requires_payment_method', 22000)] });
    expect((await r.checkout({ listing_id: LISTING, mode: 'buy_now', expected_total_cents: 22000 })).res.status).toBe(200);
  });
});
