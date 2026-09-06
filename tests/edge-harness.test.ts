/**
 * Smoke test for tests/helpers/edge-vm.ts: the REAL stripe-webhook handler
 * loads, verifies a signature, claims the event through the lease RPC, and
 * every I/O it performs is recorded. Behavioral reproductions live in the
 * package test files; this file only proves the harness itself.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, signedStripeWebhookRequest } from './helpers/edge-vm';

const SECRET = 'whsec_test_only';

describe('edge-vm harness', () => {
  it('loads the real stripe-webhook handler and rejects a bad signature with 400', async () => {
    const sb = mockSupabase();
    const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
      supabase: sb,
      env: { STRIPE_WEBHOOK_SECRET: SECRET, SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
    });
    const bad = new Request('https://edge.test/stripe-webhook', { method: 'POST', body: '{}', headers: { 'stripe-signature': 't=1,v1=00' } });
    const res = await edge.handler(bad);
    expect(res.status).toBe(400);
    expect(sb.rpcs).toHaveLength(0);
  });

  it('a correctly signed unhandled event is claimed via the lease RPC and acknowledged', async () => {
    const sb = mockSupabase({ rpc: (name) => (name === 'claim_stripe_webhook_event' ? { data: 'claimed' } : { data: true }) });
    const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
      supabase: sb,
      env: { STRIPE_WEBHOOK_SECRET: SECRET, SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
    });
    const res = await edge.handler(signedStripeWebhookRequest(SECRET, { id: 'evt_1', type: 'some.unhandled.event', data: { object: {} } }));
    expect(res.status).toBe(200);
    expect(sb.rpcs.map((r) => r.name)).toEqual(['claim_stripe_webhook_event', 'complete_stripe_webhook_event']);
  });

  it('loads confirm-payment with a mocked Stripe transport and records the query it makes', async () => {
    const sb = mockSupabase({ user: { id: 'buyer-1' }, rpc: () => ({ data: true }), tables: { payments: () => ({ data: null }) } });
    const stripe = mockStripe(() => ({ ok: true, data: { status: 'requires_payment_method', metadata: { buyer_id: 'buyer-1' } } }));
    const edge = await loadEdgeHandler('supabase/functions/confirm-payment/index.ts', {
      supabase: sb,
      env: { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', SUPABASE_ANON_KEY: 'anon' },
      provide: { stripeFetchRaw: stripe.stripeFetchRaw },
    });
    const res = await edge.handler(authedJsonRequest({ payment_intent_id: 'pi_test' }));
    const body = await json(res);
    expect(res.status).toBe(200);
    expect(stripe.calls[0]?.path).toBe('/payment_intents/pi_test?expand[]=latest_charge');
    expect(body).toBeTruthy();
  });
});
