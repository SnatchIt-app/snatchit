/**
 * tests/refund-dispute-webhook.test.ts — the REAL stripe-webhook handler,
 * Package 3 branches only: charge.refunded, charge.dispute.created,
 * charge.dispute.closed, transfer.created, transfer.reversed.
 *
 * Contract under test (migration 20260906120000 + F05 refund half):
 *   • refund facts go through record_payment_refund (one call per Stripe
 *     refund object; the charge is fetched with expand[]=refunds when the
 *     event omits them);
 *   • a LOST dispute is a chargeback: record_payment_refund(source
 *     'dispute_lost', dispute id, dispute amount) — never a stripe_refund_id —
 *     and a paid-out transfer is flagged reversal_required
 *     (DISPUTE_LOST_AFTER_PAYOUT);
 *   • a dispute.closed for a dispute we never recorded is UPSERTED from the
 *     event (reconciled), not dropped;
 *   • transfer.created records the attempt from metadata.attempt_id;
 *   • every DB failure in these branches answers non-2xx and releases the
 *     event lease (fail_stripe_webhook_event), so Stripe retries.
 */
import { describe, expect, it } from 'vitest';
import { loadEdgeHandler, mockStripe, mockSupabase, signedStripeWebhookRequest, type QueryCall, type StripeCall } from './helpers/edge-vm';

const SECRET = 'whsec_test_only';
const ENV = { STRIPE_WEBHOOK_SECRET: SECRET, SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', STRIPE_SECRET_KEY: 'sk_test_x' };

interface World {
  rpcFail?: Record<string, string>;
  disputeRow?: { id: string; payment_id: string | null; transfer_id: string | null } | null;
  disputeUpsertError?: string;
  transferPaidOut?: boolean;
  stripe?: (c: StripeCall) => { ok: boolean; status?: number; data: unknown };
}

async function load(w: World = {}) {
  const stripe = mockStripe(w.stripe ?? (() => ({ ok: false, status: 404, data: {} })));
  const sb = mockSupabase({
    rpc: async (name, params) => {
      if (w.rpcFail?.[name]) return { data: null, error: { message: w.rpcFail[name] } };
      if (name === 'claim_stripe_webhook_event') return { data: 'claimed' };
      if (name === 'record_payment_refund') return { data: { payment_id: 'p1', status: (params.p_amount_cents as number) >= 11000 ? 'refunded' : 'succeeded', amount_refunded_cents: params.p_amount_cents, recorded: true } };
      if (name === 'flag_payout_reversal_required') return { data: { paid_out: true, flagged: true } };
      if (name === 'record_payout_attempt_result') return { data: { state: 'succeeded', recorded: true } };
      if (name === 'freeze_transfer_for_dispute') return { data: true };
      if (name === 'mark_transfer_reversed') return { data: true };
      return { data: true };
    },
    tables: {
      disputes: (q: QueryCall) => {
        if (q.op === 'upsert') return w.disputeUpsertError ? { data: null, error: { message: w.disputeUpsertError } } : { data: null };
        if (q.op === 'update') return { data: w.disputeRow === undefined ? { id: 'd1', payment_id: 'p1', transfer_id: 't1' } : w.disputeRow };
        return { data: null };
      },
      payments: () => ({ data: { id: 'p1', stripe_payment_intent_id: 'pi_1', total: 11000 } }),
      transfers: () => ({ data: { id: 't1', status: w.transferPaidOut ? 'buyer_confirmed' : 'seller_sent', payout_released_at: w.transferPaidOut ? '2026-09-01T00:00:00Z' : null, stripe_transfer_id: w.transferPaidOut ? 'tr_1' : null } }),
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', { supabase: sb, env: ENV, provide: { stripeFetchRaw: stripe.stripeFetchRaw } });
  const send = (type: string, object: Record<string, unknown>, id = 'evt_1') => edge.handler(signedStripeWebhookRequest(SECRET, { id, type, data: { object } }));
  const rpcNames = () => sb.rpcs.map((r) => r.name);
  const rpc = (name: string) => sb.rpcs.filter((r) => r.name === name);
  return { sb, stripe, edge, send, rpcNames, rpc };
}

describe('charge.refunded', () => {
  it('records every refund object through record_payment_refund and acknowledges', async () => {
    const h = await load();
    const res = await h.send('charge.refunded', {
      id: 'ch_1', payment_intent: 'pi_1', refunded: true, amount_refunded: 11000,
      refunds: { data: [{ id: 're_1', amount: 5000 }, { id: 're_2', amount: 6000, metadata: { source: 'enforce-transfer-expiry' } }] },
    });
    expect(res.status).toBe(200);
    const calls = h.rpc('record_payment_refund').map((r) => r.params);
    expect(calls).toEqual([
      { p_payment_intent_id: 'pi_1', p_stripe_refund_id: 're_1', p_stripe_dispute_id: null, p_amount_cents: 5000, p_source: 'dashboard' },
      { p_payment_intent_id: 'pi_1', p_stripe_refund_id: 're_2', p_stripe_dispute_id: null, p_amount_cents: 6000, p_source: 'expiry' },
    ]);
    expect(h.rpcNames().at(-1)).toBe('complete_stripe_webhook_event');
    expect(h.sb.queries.filter((q) => q.table === 'payments' && q.op === 'update')).toHaveLength(0); // no direct status write
  });

  it('fetches the charge with expand[]=refunds when the event omits them', async () => {
    const h = await load({ stripe: (c) => c.path.startsWith('/charges/ch_1') ? { ok: true, data: { id: 'ch_1', refunded: false, amount_refunded: 500, refunds: { data: [{ id: 're_9', amount: 500 }] } } } : { ok: false, status: 404, data: {} } });
    const res = await h.send('charge.refunded', { id: 'ch_1', payment_intent: 'pi_1', refunded: false, amount_refunded: 500 });
    expect(res.status).toBe(200);
    expect(h.stripe.calls[0].path).toContain('/charges/ch_1');
    expect(h.stripe.calls[0].path).toContain('expand[]=refunds');
    expect(h.rpc('record_payment_refund')[0].params).toMatchObject({ p_stripe_refund_id: 're_9', p_amount_cents: 500 });
  });

  it('DB failure ⇒ non-2xx and the lease is released (Stripe retries)', async () => {
    const h = await load({ rpcFail: { record_payment_refund: 'connection reset' } });
    const res = await h.send('charge.refunded', { id: 'ch_1', payment_intent: 'pi_1', refunded: true, refunds: { data: [{ id: 're_1', amount: 11000 }] } });
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
    expect(h.rpcNames()).not.toContain('complete_stripe_webhook_event');
  });

  it('charge fetch failure when refunds are absent ⇒ non-2xx (never acknowledge a refund we could not read)', async () => {
    const h = await load({ stripe: () => ({ ok: false, status: 500, data: { error: { message: 'stripe down' } } }) });
    const res = await h.send('charge.refunded', { id: 'ch_1', payment_intent: 'pi_1', refunded: true });
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.rpc('record_payment_refund')).toHaveLength(0);
  });
});

describe('charge.dispute.closed', () => {
  const lost = { id: 'dp_1', charge: 'ch_1', payment_intent: 'pi_1', amount: 11000, currency: 'usd', reason: 'fraudulent', status: 'lost' };

  it('lost ⇒ chargeback recorded with the dispute id (never a refund id); paid-out transfer flagged DISPUTE_LOST_AFTER_PAYOUT', async () => {
    const h = await load({ transferPaidOut: true });
    const res = await h.send('charge.dispute.closed', lost);
    expect(res.status).toBe(200);
    expect(h.rpc('record_payment_refund')[0].params).toEqual({
      p_payment_intent_id: 'pi_1', p_stripe_refund_id: null, p_stripe_dispute_id: 'dp_1', p_amount_cents: 11000, p_source: 'dispute_lost',
    });
    expect(h.rpc('flag_payout_reversal_required')[0].params).toMatchObject({ p_transfer_id: 't1', p_reason_code: 'DISPUTE_LOST_AFTER_PAYOUT' });
    expect(h.sb.queries.filter((q) => q.table === 'payments' && q.op === 'update')).toHaveLength(0);
  });

  it('lost on an UNPAID transfer ⇒ refund recorded, no reversal flag', async () => {
    const h = await load({ transferPaidOut: false });
    await h.send('charge.dispute.closed', lost);
    expect(h.rpc('record_payment_refund')).toHaveLength(1);
    expect(h.rpc('flag_payout_reversal_required')).toHaveLength(0);
  });

  it('won ⇒ status synced, no money facts written', async () => {
    const h = await load();
    const res = await h.send('charge.dispute.closed', { ...lost, status: 'won' });
    expect(res.status).toBe(200);
    expect(h.rpc('record_payment_refund')).toHaveLength(0);
  });

  it('unknown dispute id ⇒ upserted from the event (reconciled), then handled', async () => {
    const h = await load({ disputeRow: null, transferPaidOut: true });
    const res = await h.send('charge.dispute.closed', lost);
    expect(res.status).toBe(200);
    const upsert = h.sb.queries.find((q) => q.table === 'disputes' && q.op === 'upsert');
    expect(upsert?.body).toMatchObject({ stripe_dispute_id: 'dp_1', stripe_charge_id: 'ch_1', stripe_pi_id: 'pi_1', amount: 11000, status: 'lost', payment_id: 'p1', transfer_id: 't1' });
    expect(h.rpc('record_payment_refund')).toHaveLength(1);
  });

  it('DB failure recording the chargeback ⇒ non-2xx, lease released', async () => {
    const h = await load({ rpcFail: { record_payment_refund: 'connection reset' } });
    const res = await h.send('charge.dispute.closed', lost);
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
  });
});

describe('charge.dispute.created / transfer.created / transfer.reversed', () => {
  it('dispute.created upsert failure ⇒ non-2xx', async () => {
    const h = await load({ disputeUpsertError: 'disk full' });
    const res = await h.send('charge.dispute.created', { id: 'dp_1', charge: 'ch_1', payment_intent: 'pi_1', amount: 11000, currency: 'usd', reason: 'fraudulent', status: 'needs_response' });
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.rpcNames()).toContain('freeze_transfer_for_dispute');
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
  });

  it('transfer.created with metadata.attempt_id ⇒ record_payout_attempt_result (idempotent); without ⇒ log only', async () => {
    const h = await load();
    const res = await h.send('transfer.created', { id: 'tr_1', amount: 9000, destination: 'acct_A', metadata: { attempt_id: 'att_1', transfer_id: 't1' } });
    expect(res.status).toBe(200);
    expect(h.rpc('record_payout_attempt_result')[0].params).toMatchObject({ p_attempt_id: 'att_1', p_stripe_transfer_id: 'tr_1', p_outcome: 'succeeded' });
    const h2 = await load();
    await h2.send('transfer.created', { id: 'tr_legacy', amount: 9000, metadata: { transfer_id: 't1' } });
    expect(h2.rpc('record_payout_attempt_result')).toHaveLength(0);
  });

  it('transfer.created record failure ⇒ non-2xx', async () => {
    const h = await load({ rpcFail: { record_payout_attempt_result: 'connection reset' } });
    const res = await h.send('transfer.created', { id: 'tr_1', amount: 9000, metadata: { attempt_id: 'att_1' } });
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
  });

  it('transfer.reversed mark failure ⇒ non-2xx', async () => {
    const h = await load({ rpcFail: { mark_transfer_reversed: 'connection reset' } });
    const res = await h.send('transfer.reversed', { id: 'tr_1', amount_reversed: 9000 });
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(h.rpcNames()).toContain('fail_stripe_webhook_event');
  });
});
