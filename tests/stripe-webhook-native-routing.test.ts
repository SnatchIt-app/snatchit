/**
 * tests/stripe-webhook-native-routing.test.ts — the REAL stripe-webhook
 * handler (tests/helpers/edge-vm.ts), driven end to end for every NATIVE arm.
 *
 * WHY THIS FILE EXISTS
 *   stripe-webhook-native.test.ts / stripe-webhook-dispute.test.ts exercise the
 *   pure decision modules (native.ts, native-dispute.ts) and nothing else. Both
 *   stayed green from 2026-09-06 to 2026-10-27 while index.ts did not import
 *   either module at all (the converged RC, 733e114b, did not carry the native
 *   arm), so a paid native order reached settle_verified_payment, came back
 *   `not_external_rail`, and was ACKed with no order finalized and no ticket
 *   minted. Every test here loads index.ts itself, so removing a dispatch makes
 *   a test fail — the first test is the negative control for exactly that.
 *
 * WHAT IS PINNED
 *   • each native arm reaches its verb, on the right schema, with exact args:
 *     finalize_primary_order / cancel_pending_order (venue),
 *     sync_org_connect_state / record_dispute_native / mark_dispute_state /
 *     record_payout_reversal (kernel);
 *   • a native event that settles nothing is never ACKed silently: ACK + alert
 *     always writes a review row, and a review row that cannot be written turns
 *     the ACK into a retry;
 *   • marketplace success, refund, failure and seller account events take
 *     exactly their pre-restore path (RPC sequence, client set, response body).
 *
 * Nothing here talks to a network, a database, or a real Stripe key.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockSupabase, signedStripeWebhookRequest, type QueryCall, type RpcHandler } from './helpers/edge-vm';

const SECRET = 'whsec_test_only';
const ENV = { STRIPE_WEBHOOK_SECRET: SECRET, STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' };

const ORDER  = '00000000-0000-4000-8000-000000000101';
const BUYER  = '00000000-0000-4000-8000-000000000102';
const ORG    = '00000000-0000-4000-8000-000000000103';
const SESS   = '00000000-0000-4000-8000-000000000104';
const PAYOUT = '00000000-0000-4000-8000-000000000105';
const PAY    = '00000000-0000-4000-8000-000000000106';
const PI     = 'pi_native_1';
const ACCT   = 'acct_1OrgAbc';

/** Exactly what primary-checkout puts on a native PaymentIntent. */
const NATIVE_META = { rail: 'native_primary', mode: 'native_primary', order_id: ORDER, buyer_id: BUYER, org_id: ORG, session_id: SESS };
/** A native payments row (093 rail pairing: listing/seller NULL), as both SELECT projections see it. */
const NATIVE_ROW = { id: PAY, status: 'succeeded', mode: 'native_primary', listing_id: null, seller_id: null, buyer_id: BUYER, total: 5500, stripe_livemode: true };
const REVIEW_RPC_NAME = 'stripe-webhook:native';

type Reply = { data?: unknown; error?: { message: string; code?: string } | null };
type RpcScript = Record<string, (params: Record<string, unknown>, schema: string | null) => Reply>;

function harness(opts: {
  rpc?: RpcScript;
  payments?: (q: QueryCall) => Reply;
  profiles?: (q: QueryCall) => Reply;
  disputes?: (q: QueryCall) => Reply;
  reviewWriteFails?: boolean;
  fetch?: typeof fetch;
  /** Edge env override (default ENV). */
  env?: Record<string, string>;
  /** The secret the delivery is signed with (default SECRET). */
  signWith?: string;
} = {}) {
  const rpc: RpcHandler = (name, params, schema) => {
    const scripted = opts.rpc?.[name];
    if (scripted) return scripted(params, schema);
    if (name === 'claim_stripe_webhook_event') return { data: 'claimed' };
    if (name === 'complete_stripe_webhook_event' || name === 'fail_stripe_webhook_event') return { data: true };
    return { data: null };
  };
  const sb = mockSupabase({
    rpc,
    tables: {
      payments: opts.payments ?? (() => ({ data: { ...NATIVE_ROW } })),
      profiles: opts.profiles ?? (() => ({ data: [] })),
      disputes: opts.disputes ?? (() => ({ data: null })),
      transfers: () => ({ data: null }),
      listings: () => ({ data: { event_name: 'Fixture Event' } }),
      notification_preferences: () => ({ data: null }),
      webhook_retries: () => (opts.reviewWriteFails ? { error: { message: 'review insert refused' } } : { data: null }),
    },
  });
  const deliver = async (event: Record<string, unknown>) => {
    const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
      supabase: sb,
      env: opts.env ?? ENV,
      fetch: opts.fetch ?? ((async () => new Response('{}', { status: 200 })) as unknown as typeof fetch),
      provide: { stripeFetchRaw: async () => ({ ok: false, status: 500, data: {} }), AbortSignal },
    });
    const res = await edge.handler(signedStripeWebhookRequest(opts.signWith ?? SECRET, event));
    return { res, body: await json(res), edge };
  };
  const rpcNames = () => sb.rpcs.map((r) => r.name);
  const rpcOf = (name: string) => sb.rpcs.find((r) => r.name === name);
  const reviewRows = () => sb.queries.filter((q) => q.table === 'webhook_retries' && q.op === 'insert').map((q) => q.body as Record<string, unknown>);
  return { sb, deliver, rpcNames, rpcOf, reviewRows };
}

const created = () => Math.floor(Date.now() / 1000);

function piEvent(id: string, type: string, metadata: Record<string, unknown>, over: Record<string, unknown> = {}) {
  return {
    id, type, created: created(), livemode: false,
    data: { object: {
      id: PI, object: 'payment_intent', status: type === 'payment_intent.succeeded' ? 'succeeded' : 'requires_payment_method',
      amount: 5500, amount_received: 5500, currency: 'usd', livemode: false, latest_charge: 'ch_native_1',
      payment_method_types: ['card'], metadata, ...over,
    } },
  };
}

const finalizeOk = { finalize_primary_order: () => ({ data: { status: 'ok', atom_ids: ['atom-1', 'atom-2'], order_status: 'paid' } }) };

describe('native payment_intent.succeeded reaches venue.finalize_primary_order (CONTRACTS C4)', () => {
  // NEGATIVE CONTROL TARGET: with the success dispatch removed from index.ts this test fails.
  it('routes a native success to finalize on the venue schema, never to settle_verified_payment', async () => {
    const h = harness({ rpc: finalizeOk });
    const { res, body } = await h.deliver(piEvent('evt_n1', 'payment_intent.succeeded', NATIVE_META));

    expect(res.status).toBe(200);
    expect(body).toMatchObject({ received: true, reason: 'native_primary_ok', order_id: ORDER, payment_id: PAY, atom_count: 2 });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'finalize_primary_order', 'complete_stripe_webhook_event']);
    expect(h.rpcOf('finalize_primary_order')).toEqual({
      name: 'finalize_primary_order',
      schema: 'venue',
      params: {
        p_order_id:               ORDER,
        p_payment_id:             PAY,
        p_command_key:            `wh_native_primary:${ORDER}:${PI}`,
        p_instrument_fingerprint: null,
      },
    });
    // The claim: the native-only refunded guard rides beside the succeeded guard.
    const claim = h.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(claim?.body).toMatchObject({ status: 'succeeded' });
    expect(claim?.filters).toEqual([
      ['eq', 'stripe_payment_intent_id', PI],
      ['neq', 'status', 'succeeded'],
      ['neq', 'status', 'refunded'],
    ]);
    expect(h.reviewRows()).toHaveLength(0);
  });

  it('a replay (row already succeeded) finalizes again under the SAME command key — the order lock dedupes', async () => {
    const h = harness({
      rpc: { finalize_primary_order: () => ({ data: { status: 'idempotency_replay', atom_ids: ['atom-1'] } }) },
      payments: (q) => (q.op === 'update' ? { data: null } : { data: { ...NATIVE_ROW } }),
    });
    const { res, body } = await h.deliver(piEvent('evt_n2', 'payment_intent.succeeded', NATIVE_META));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'native_primary_idempotency_replay' });
    expect(h.rpcOf('finalize_primary_order')?.params.p_command_key).toBe(`wh_native_primary:${ORDER}:${PI}`);
  });

  it('passes the instrument fingerprint read from latest_charge', async () => {
    const charge = { id: 'ch_native_1', payment_method_details: { type: 'card', card: { fingerprint: 'fp_test_only' } } };
    const h = harness({
      rpc: finalizeOk,
      fetch: (async () => new Response(JSON.stringify(charge), { status: 200 })) as unknown as typeof fetch,
    });
    await h.deliver(piEvent('evt_n3', 'payment_intent.succeeded', NATIVE_META));
    expect(h.rpcOf('finalize_primary_order')?.params.p_instrument_fingerprint).toBe('fp_test_only');
  });

  it('a fixable refusal (no active signing key) is NOT acknowledged: 500 + fail, Stripe retries', async () => {
    const h = harness({ rpc: { finalize_primary_order: () => ({ error: { message: 'no_active_signing_key', code: 'P0001' } }) } });
    const { res, body } = await h.deliver(piEvent('evt_n4', 'payment_intent.succeeded', NATIVE_META));
    expect(res.status).toBe(500);
    expect(body).toMatchObject({ reason: 'finalize_no_signing_key' });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'finalize_primary_order', 'fail_stripe_webhook_event']);
    expect(h.rpcNames()).not.toContain('complete_stripe_webhook_event');
    expect(h.reviewRows()).toHaveLength(0);
  });

  it('a terminal refusal is ACKed loudly: alert + a review row the refund sweep never selects', async () => {
    const h = harness({ rpc: { finalize_primary_order: () => ({ error: { message: 'only a pending order finalizes', code: 'P0001' } }) } });
    const { res, body, edge } = await h.deliver(piEvent('evt_n5', 'payment_intent.succeeded', NATIVE_META));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'finalize_order_not_pending' });
    expect(edge.sentry.map((s) => s.tag)).toEqual(['stripe-webhook:finalize_order_not_pending']);
    expect(h.reviewRows()).toEqual([{
      payment_id:    null,
      listing_id:    null,
      rpc_name:      REVIEW_RPC_NAME,
      error_message: `finalize_order_not_pending:payment_intent.succeeded:evt_n5:${ORDER}`,
      resolved:      false,
    }]);
    // complete only AFTER the review row exists.
    const order = h.sb.queries.findIndex((q) => q.table === 'webhook_retries');
    expect(order).toBeGreaterThanOrEqual(0);
    expect(h.rpcNames().at(-1)).toBe('complete_stripe_webhook_event');
  });

  it('when the review row cannot be written the event is NOT acknowledged', async () => {
    const h = harness({
      rpc: { finalize_primary_order: () => ({ error: { message: 'only a pending order finalizes', code: 'P0001' } }) },
      reviewWriteFails: true,
    });
    const { res } = await h.deliver(piEvent('evt_n6', 'payment_intent.succeeded', NATIVE_META));
    expect(res.status).toBe(500);
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'finalize_primary_order', 'fail_stripe_webhook_event']);
    expect(h.sb.queries.filter((q) => q.table === 'webhook_retries')).toHaveLength(1);
  });
});

describe('a native row the router cannot classify is never ACKed silently', () => {
  const unrouted = {
    settle_verified_payment: () => ({ data: [{ payment_id: PAY, payment_status: 'pending', listing_status: null, transfer_id: null, outcome: 'not_external_rail' }] }),
  };

  it('PI metadata without rail/mode → settle answers not_external_rail → alert + review row, then ACK', async () => {
    const h = harness({ rpc: unrouted });
    const { res, body, edge } = await h.deliver(piEvent('evt_u1', 'payment_intent.succeeded', { order_id: ORDER, buyer_id: BUYER }));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'native_row_unrouted', payment_id: PAY });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'complete_stripe_webhook_event']);
    expect(edge.sentry.map((s) => s.tag)).toEqual(['stripe-webhook:native_row_unrouted']);
    expect(h.reviewRows()).toHaveLength(1);
    expect(h.reviewRows()[0]).toMatchObject({ rpc_name: REVIEW_RPC_NAME, payment_id: null, error_message: `native_row_unrouted:payment_intent.succeeded:evt_u1:${PI}` });
  });

  it('…and when that review row cannot be written: 500 + fail', async () => {
    const h = harness({ rpc: unrouted, reviewWriteFails: true });
    const { res } = await h.deliver(piEvent('evt_u2', 'payment_intent.succeeded', { order_id: ORDER, buyer_id: BUYER }));
    expect(res.status).toBe(500);
    expect(h.rpcNames()).not.toContain('complete_stripe_webhook_event');
  });

  it('rail/mode disagreement: no money path at all, alert + review row, ACK', async () => {
    const h = harness();
    const { res, body } = await h.deliver(piEvent('evt_u3', 'payment_intent.succeeded', { ...NATIVE_META, mode: 'buy_now' }));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'rail_mode_mismatch' });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
    expect(h.reviewRows()).toHaveLength(1);
  });

  it('a rail we do not implement is retried (500), never run down a resale path', async () => {
    const h = harness();
    const { res } = await h.deliver(piEvent('evt_u4', 'payment_intent.succeeded', { ...NATIVE_META, rail: 'native_resale', mode: 'native_resale' }));
    expect(res.status).toBe(500);
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'fail_stripe_webhook_event']);
    expect(h.reviewRows()).toHaveLength(0);
  });
});

describe('native payment_failed / canceled', () => {
  it('a per-attempt decline records the failure and cancels NOTHING (the buyer may retry the same sheet)', async () => {
    const h = harness();
    const { res, body } = await h.deliver(piEvent('evt_f1', 'payment_intent.payment_failed', NATIVE_META));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'native_attempt_failed_order_pending' });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
    const mark = h.sb.queries.find((q) => q.table === 'payments' && q.op === 'update');
    expect(mark?.body).toEqual({ status: 'failed' });
    expect(mark?.filters).toEqual([['eq', 'stripe_payment_intent_id', PI], ['neq', 'status', 'succeeded'], ['neq', 'status', 'refunded']]);
    expect(h.reviewRows()).toHaveLength(0);
  });

  it('a terminal (canceled) PaymentIntent cancels the pending order on the venue schema; the L1 resale claim never runs', async () => {
    const h = harness({ rpc: { cancel_pending_order: () => ({ data: { status: 'cancelled' } }) } });
    const { res, body } = await h.deliver(piEvent('evt_f2', 'payment_intent.canceled', NATIVE_META, { status: 'canceled' }));
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'native_order_cancelled' });
    expect(h.rpcOf('cancel_pending_order')).toEqual({
      name: 'cancel_pending_order',
      schema: 'venue',
      params: { p_order_id: ORDER, p_reason_code: 'payment_failed', p_command_key: `wh_native_cancel:${ORDER}:${PI}` },
    });
    expect(h.rpcNames()).not.toContain('release_reservation_for_payment');
    expect(h.sb.queries.some((q) => q.filters.some((f) => f[0] === 'in'))).toBe(false);
  });
});

describe('account.updated — the organization arm', () => {
  const orgAccount = (over: Record<string, unknown> = {}) => ({
    id: 'evt_a1', type: 'account.updated', created: 1_800_000_000, livemode: false,
    data: { object: {
      id: ACCT, object: 'account', details_submitted: true, charges_enabled: false, payouts_enabled: true,
      capabilities: { transfers: 'active' }, metadata: { snatchit_plane: 'organization', org_id: ORG }, ...over,
    } },
  });

  it('syncs capabilities.transfers through kernel.sync_org_connect_state at the EVENT instant', async () => {
    const h = harness({ rpc: { sync_org_connect_state: () => ({ data: { status: 'ok', org_id: ORG } }) } });
    const { res, body } = await h.deliver(orgAccount());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'org_ok', matched: 'organization', transfers_active: true });
    expect(h.rpcOf('sync_org_connect_state')).toEqual({
      name: 'sync_org_connect_state',
      schema: 'kernel',
      params: {
        p_org_id:              ORG,
        p_connect_account_ref: ACCT,
        p_transfers_active:    true,
        p_observed_at:         new Date(1_800_000_000 * 1000).toISOString(),
        p_command_key:         'wh_account_updated:evt_a1',
      },
    });
    // The individual-seller write still runs first, unchanged (it matches no profile here).
    const profileWrite = h.sb.queries.find((q) => q.table === 'profiles');
    expect(profileWrite?.op).toBe('update');
    expect(profileWrite?.filters).toEqual([['eq', 'stripe_connect_id', ACCT]]);
    expect(h.reviewRows()).toHaveLength(0);
  });

  it('coexists with connect-onboarding: an observation no newer than onboarding\'s own sync is a quiet noop_replay', async () => {
    const h = harness({ rpc: { sync_org_connect_state: () => ({ data: { status: 'noop_replay', org_id: ORG } }) } });
    const { res, body, edge } = await h.deliver(orgAccount());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'org_noop_replay' });
    expect(edge.sentry).toHaveLength(0);
    expect(h.reviewRows()).toHaveLength(0);
  });

  it('an event that beats the bind (org exists, no bound ref yet) is retried until the bind lands', async () => {
    const h = harness({
      rpc: { sync_org_connect_state: () => ({ error: { message: 'precondition_failed: org_not_bound — capability state may not be written for an organization with no bound payout destination', code: 'P0001' } }) },
    });
    const { res } = await h.deliver(orgAccount());
    expect(res.status).toBe(500);
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
  });

  it('a seller account (no organization marker) takes the individual arm only, exactly as before', async () => {
    const h = harness({ profiles: () => ({ data: [{ id: 'profile-1' }] }) });
    const { res, body } = await h.deliver(orgAccount({ metadata: { user_id: 'user-1' }, capabilities: undefined }));
    expect(res.status).toBe(200);
    expect(body).toEqual({ received: true });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
    expect(h.sb.clients).toHaveLength(1);
  });
});

describe('native disputes and reversals (R-40: the dispute substrate before any issuance flag)', () => {
  const dispute = (over: Record<string, unknown> = {}) => ({
    id: 'dp_1', object: 'dispute', charge: 'ch_native_1', payment_intent: PI, amount: 5500, currency: 'usd',
    reason: 'fraudulent', status: 'needs_response', evidence_details: { due_by: 1_900_000_000 }, ...over,
  });
  const disputeEvent = (id: string, type: string, over: Record<string, unknown> = {}) => ({ id, type, created: created(), livemode: true, data: { object: dispute(over) } });

  it('charge.dispute.created on a native row: record_dispute_native (kernel), then the legacy disputes upsert', async () => {
    const h = harness({ rpc: { record_dispute_native: () => ({ data: { status: 'ok', dispute_id: 'dn-1', linked: true } }) } });
    const { res } = await h.deliver(disputeEvent('evt_d1', 'charge.dispute.created'));
    expect(res.status).toBe(200);
    expect(h.rpcOf('record_dispute_native')).toEqual({
      name: 'record_dispute_native',
      schema: 'kernel',
      params: {
        p_stripe_dispute_ref: 'dp_1', p_stripe_charge_ref: 'ch_native_1', p_stripe_pi_ref: PI, p_amount_minor: 5500,
        p_currency: 'usd', p_reason: 'fraudulent', p_status: 'needs_response',
        p_evidence_due_at: new Date(1_900_000_000 * 1000).toISOString(), p_command_key: 'wh_dispute_created:evt_d1',
      },
    });
    expect(h.sb.queries.some((q) => q.table === 'disputes' && q.op === 'upsert')).toBe(true);
    expect(h.rpcNames().at(-1)).toBe('complete_stripe_webhook_event');
  });

  it('when the rail discriminator read fails, the delivery is retried before EITHER arm runs', async () => {
    // The one change on the resale dispute path, pinned on purpose. Before the
    // restore, a failed payments read was ignored: the dispute was recorded
    // with payment_id/transfer_id NULL, the transfer was NOT frozen, and the
    // event was ACKed. Now the rail is unknown, so nothing is written and Stripe
    // redelivers; the redelivery records the dispute linked and frozen.
    const h = harness({ payments: () => ({ error: { message: 'read failed' } }) });
    const { res, body } = await h.deliver(disputeEvent('evt_d0', 'charge.dispute.created'));
    expect(res.status).toBe(500);
    expect(body).toMatchObject({ reason: 'native_dispute_payment_read_error' });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'fail_stripe_webhook_event']);
    expect(h.sb.queries.some((q) => q.table === 'disputes')).toBe(false);
  });

  it('charge.dispute.updated: mark_dispute_state on a native row; a resale row stays ack-only', async () => {
    const native = harness({ rpc: { mark_dispute_state: () => ({ data: { status: 'ok', dispute_id: 'dn-1' } }) } });
    const n = await native.deliver(disputeEvent('evt_d2', 'charge.dispute.updated', { status: 'under_review' }));
    expect(n.res.status).toBe(200);
    expect(n.body).toMatchObject({ reason: 'native_dispute_state_synced' });
    expect(native.rpcOf('mark_dispute_state')).toEqual({
      name: 'mark_dispute_state', schema: 'kernel',
      params: { p_stripe_dispute_ref: 'dp_1', p_new_status: 'under_review', p_command_key: 'wh_dispute_updated:evt_d2' },
    });

    const resale = harness({ payments: () => ({ data: { id: 'pay-resale', mode: 'buy_now', stripe_livemode: true, status: 'succeeded' } }) });
    const r = await resale.deliver(disputeEvent('evt_d2r', 'charge.dispute.updated', { status: 'under_review' }));
    expect(r.res.status).toBe(200);
    expect(r.body).toEqual({ received: true });
    expect(resale.rpcNames()).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
  });

  it('charge.dispute.closed lost on a native row: mark → alert + review row, then the legacy chargeback record still runs', async () => {
    const h = harness({
      rpc: { mark_dispute_state: () => ({ data: { status: 'ok', dispute_id: 'dn-1', dispute_status: 'lost' } }) },
      disputes: () => ({ data: { id: 'd-1', payment_id: PAY, transfer_id: null } }),
    });
    const { res, edge } = await h.deliver(disputeEvent('evt_d3', 'charge.dispute.closed', { status: 'lost' }));
    expect(res.status).toBe(200);
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'mark_dispute_state', 'record_payment_refund', 'complete_stripe_webhook_event']);
    expect(edge.sentry.map((s) => s.tag)).toEqual(['stripe-webhook:native_dispute_lost']);
    expect(h.reviewRows()).toHaveLength(1);
    expect(String(h.reviewRows()[0].error_message)).toMatch(/^native_dispute_lost:charge\.dispute\.closed:evt_d3:/);
  });

  it('transfer.reversed of a native payout: one record_payout_reversal per reversal (kernel), then the legacy arm', async () => {
    const h = harness({
      rpc: {
        record_payout_reversal: () => ({ data: { status: 'ok', fully_reversed: true } }),
        mark_transfer_reversed: () => ({ data: false }),
      },
    });
    const { res } = await h.deliver({
      id: 'evt_r1', type: 'transfer.reversed', created: created(), livemode: true,
      data: { object: {
        id: 'tr_N1', object: 'transfer', amount: 4000, currency: 'usd', reversed: true, amount_reversed: 4000,
        transfer_group: `payout_${PAYOUT}`, metadata: { source: 'payout-execute', payout_id: PAYOUT },
        reversals: { data: [{ id: 'trr_A1', amount: 4000 }], has_more: false },
      } },
    });
    expect(res.status).toBe(200);
    expect(h.rpcOf('record_payout_reversal')).toEqual({
      name: 'record_payout_reversal', schema: 'kernel',
      params: {
        p_payout_id: PAYOUT, p_stripe_transfer_ref: 'tr_N1', p_stripe_reversal_ref: 'trr_A1', p_amount_minor: 4000,
        p_observed: { transfer_amount_minor: 4000, amount_reversed: 4000, reversed: true, event_id: 'evt_r1' },
        p_command_key: 'wh_transfer_reversed:evt_r1:trr_A1',
      },
    });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'record_payout_reversal', 'mark_transfer_reversed', 'complete_stripe_webhook_event']);
  });

  it('transfer.reversed of a legacy transfer, or one with no rail marker at all: legacy arm only, no alert, no review row', async () => {
    for (const object of [
      { id: 'tr_L1', amount: 4000, amount_reversed: 4000, transfer_group: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', metadata: { transfer_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', attempt_id: 'x' } },
      { id: 'tr_L2', amount: 4000, amount_reversed: 4000, metadata: {} },
    ]) {
      const h = harness({ rpc: { mark_transfer_reversed: () => ({ data: true }) } });
      const { res, body, edge } = await h.deliver({ id: `evt_${object.id}`, type: 'transfer.reversed', created: created(), data: { object } });
      expect(res.status).toBe(200);
      expect(body).toEqual({ received: true });
      expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'mark_transfer_reversed', 'complete_stripe_webhook_event']);
      expect(h.sb.clients).toHaveLength(1);
      expect(edge.sentry).toHaveLength(0);
      expect(h.reviewRows()).toHaveLength(0);
    }
  });
});

describe('marketplace (P2P) paths take exactly their pre-restore path through the shared webhook', () => {
  const RESALE_META = { mode: 'buy_now', listing_id: 'listing-0001', buyer_id: 'buyer-0001', seller_id: 'seller-0001' };

  it('payment_intent.succeeded: claim → settle_verified_payment → complete, one client, no native write', async () => {
    const h = harness({
      rpc: { settle_verified_payment: () => ({ data: [{ payment_id: 'pay_1', payment_status: 'succeeded', listing_status: 'sold', transfer_id: 'tr_row_1', outcome: 'settled' }] }) },
    });
    const { res, body } = await h.deliver(piEvent('evt_m1', 'payment_intent.succeeded', RESALE_META, { livemode: true }));
    expect(res.status).toBe(200);
    expect(body).toEqual({ received: true, outcome: 'settled', payment_id: 'pay_1', transfer_id: 'tr_row_1' });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'settle_verified_payment', 'complete_stripe_webhook_event']);
    expect(h.sb.clients).toEqual([{ key: 'service-test', schema: null, authHeader: null }]);
    expect(h.sb.queries.map((q) => q.table)).toEqual(['listings', 'notification_preferences']);
    expect(h.reviewRows()).toHaveLength(0);
  });

  it('charge.refunded: one record_refund_state per refund, one client, body unchanged', async () => {
    const h = harness({ rpc: { record_refund_state: () => ({ data: { recorded: true } }) } });
    const { res, body } = await h.deliver({
      id: 'evt_m2', type: 'charge.refunded', created: created(),
      data: { object: {
        id: 'ch_m2', object: 'charge', payment_intent: 'pi_m2', refunded: true, amount_refunded: 22000,
        refunds: { data: [{ id: 're_m2', status: 'succeeded', amount: 22000, payment_intent: 'pi_m2' }] },
      } },
    });
    expect(res.status).toBe(200);
    expect(body).toEqual({ received: true });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'record_refund_state', 'complete_stripe_webhook_event']);
    expect(h.rpcOf('record_refund_state')?.params).toEqual({
      p_payment_intent_id: 'pi_m2', p_stripe_refund_id: 're_m2', p_status: 'succeeded', p_amount_cents: 22000,
      p_failure_reason: null, p_source: 'dashboard', p_observed_via: 'webhook',
    });
    expect(h.sb.clients).toHaveLength(1);
    expect(h.sb.queries).toHaveLength(0);
  });

  it('payment_intent.payment_failed (buy_now): the L1 claim and the per-payment release, unchanged', async () => {
    const h = harness({
      payments: () => ({ data: { id: 'pay_m3', listing_id: 'listing-0001' } }),
      rpc: { release_reservation_for_payment: () => ({ data: { released: true, reason: 'released' } }) },
    });
    const { res, body } = await h.deliver(piEvent('evt_m3', 'payment_intent.payment_failed', RESALE_META));
    expect(res.status).toBe(200);
    expect(body).toEqual({ received: true, path: 'payment_failed', payment_id: 'pay_m3' });
    expect(h.rpcNames()).toEqual(['claim_stripe_webhook_event', 'release_reservation_for_payment', 'complete_stripe_webhook_event']);
    expect(h.sb.queries).toHaveLength(1);
    expect(h.sb.queries[0].filters).toEqual([['eq', 'stripe_payment_intent_id', PI], ['in', 'status', ['pending', 'processing']]]);
    expect(h.sb.clients).toHaveLength(1);
  });
});

describe('Connect endpoint signing secret — connected-account events reach this function', () => {
  // Stripe delivers an organization account's account.updated ONLY on a
  // Connect-type endpoint, and every endpoint signs with its own secret.
  const CONNECT_SECRET = 'whsec_connect_test_only';
  const orgUpdate = {
    id: 'evt_c1', type: 'account.updated', created: 1_800_000_000, livemode: false,
    data: { object: {
      id: ACCT, object: 'account', details_submitted: true, charges_enabled: false, payouts_enabled: true,
      capabilities: { transfers: 'active' }, metadata: { snatchit_plane: 'organization', org_id: ORG },
    } },
  };
  const syncOk = { sync_org_connect_state: () => ({ data: { status: 'ok', org_id: ORG } }) };

  it('a delivery signed with the Connect endpoint secret is accepted when that secret is configured', async () => {
    const h = harness({ env: { ...ENV, STRIPE_CONNECT_WEBHOOK_SECRET: CONNECT_SECRET }, signWith: CONNECT_SECRET, rpc: syncOk });
    const { res, body } = await h.deliver(orgUpdate);
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'org_ok' });
    expect(h.rpcNames()).toContain('sync_org_connect_state');
  });

  it('the platform secret still verifies when the Connect secret is configured', async () => {
    const h = harness({ env: { ...ENV, STRIPE_CONNECT_WEBHOOK_SECRET: CONNECT_SECRET }, rpc: syncOk });
    const { res } = await h.deliver(orgUpdate);
    expect(res.status).toBe(200);
  });

  it('without the Connect secret configured, a Connect-signed delivery is rejected and nothing runs', async () => {
    const h = harness({ signWith: CONNECT_SECRET });
    const { res } = await h.deliver(orgUpdate);
    expect(res.status).toBe(400);
    expect(h.rpcNames()).toEqual([]);
  });

  it('a delivery signed with neither secret is rejected even when both are configured', async () => {
    const h = harness({ env: { ...ENV, STRIPE_CONNECT_WEBHOOK_SECRET: CONNECT_SECRET }, signWith: 'whsec_not_ours' });
    const { res } = await h.deliver(orgUpdate);
    expect(res.status).toBe(400);
    expect(h.rpcNames()).toEqual([]);
  });

  it('an empty Connect secret is never used as a key (an empty-key signature does not verify)', async () => {
    const h = harness({ env: { ...ENV, STRIPE_CONNECT_WEBHOOK_SECRET: '' }, signWith: '' });
    const { res } = await h.deliver(orgUpdate);
    expect(res.status).toBe(400);
    expect(h.rpcNames()).toEqual([]);
  });
});

describe('account.application.deauthorized — a disconnected payout destination stops being payable', () => {
  // event.account names the account; data.object is the APPLICATION (no metadata, no org id).
  const deauth = (over: Record<string, unknown> = {}) => ({
    id: 'evt_d1', type: 'account.application.deauthorized', created: 1_800_000_100, livemode: false, account: ACCT,
    data: { object: { id: 'ca_app_test_only', object: 'application', name: 'Snatch It' } },
    ...over,
  });

  it('writes transfers_active=false through kernel.sync_org_connect_state, resolved by the account ref alone', async () => {
    const h = harness({ rpc: { sync_org_connect_state: () => ({ data: { status: 'ok', org_id: ORG } }) } });
    const { res, body } = await h.deliver(deauth());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'org_deauthorized', org_id: ORG, status: 'ok' });
    expect(h.rpcOf('sync_org_connect_state')).toEqual({
      name: 'sync_org_connect_state',
      schema: 'kernel',
      params: {
        p_org_id:              null,
        p_connect_account_ref: ACCT,
        p_transfers_active:    false,
        p_observed_at:         new Date(1_800_000_100 * 1000).toISOString(),
        p_command_key:         'wh_account_deauthorized:evt_d1',
      },
    });
    // Always loud: an operator must re-onboard or unbind.
    expect(h.reviewRows()).toHaveLength(1);
    // The seller plane is never written by this branch.
    expect(h.sb.queries.filter((q) => q.table === 'profiles')).toHaveLength(0);
  });

  it('when the out-of-order guard declines to apply it (noop_replay) it is still ACKed LOUDLY, never silently', async () => {
    const h = harness({ rpc: { sync_org_connect_state: () => ({ data: { status: 'noop_replay', org_id: ORG } }) } });
    const { res, body } = await h.deliver(deauth());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'org_deauthorized_not_applied', status: 'noop_replay' });
    expect(h.reviewRows()).toHaveLength(1);
  });

  it('an account no organization holds (a seller or never-bound account) is ACKed with an alert, nothing written', async () => {
    const h = harness({
      rpc: { sync_org_connect_state: () => ({ error: { message: `not_found: organization for ${ACCT}`, code: 'P0002' } }) },
    });
    const { res, body } = await h.deliver(deauth());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ reason: 'deauth_no_bound_organization' });
    expect(h.reviewRows()).toHaveLength(1);
    expect(h.sb.queries.filter((q) => q.table === 'profiles')).toHaveLength(0);
  });

  it('a transient database failure is retried (500), never dropped', async () => {
    const h = harness({ rpc: { sync_org_connect_state: () => ({ error: { message: 'could not serialize access', code: '40001' } }) } });
    const { res } = await h.deliver(deauth());
    expect(res.status).toBe(500);
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
  });

  it('a missing or malformed account is ACKed with an alert and never reaches the RPC', async () => {
    for (const account of [undefined, 'not_an_account', '']) {
      const h = harness();
      const { res, body } = await h.deliver(deauth({ account }));
      expect(res.status).toBe(200);
      expect(body).toMatchObject({ reason: 'deauth_malformed_account_ref' });
      expect(h.rpcNames()).not.toContain('sync_org_connect_state');
    }
  });
});
