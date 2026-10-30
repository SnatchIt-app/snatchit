/**
 * tests/cron-auth-enforce-transfer-expiry.test.ts — the bearer check of the
 * cron-driven enforce-transfer-expiry edge (deployed --no-verify-jwt, so this
 * in-handler check is its ONLY authentication).
 *
 * WHY THIS TEST EXISTS. Migration 032's pg_cron job hard-codes the PRODUCTION
 * function URL, so every fresh database that replays the chain — including
 * GitHub CI's Supabase stack — POSTs production's enforce-transfer-expiry
 * every 2 minutes with an empty or absent bearer (no Vault secret there). D
 * observed the 401s in net._http_response on CI's own stack. That is harmless
 * only because this check refuses such a request before touching anything;
 * nothing under tests/ pinned it until now. The durable fix — a
 * configuration-driven URL and a cron that is a no-op when unset — is a later
 * numbered migration the owner places.
 *
 * WHAT IS ACCEPTED, AND WHY BOTH. The handler accepts a bearer equal to
 * INTERNAL_CRON_SECRET or to SUPABASE_SERVICE_ROLE_KEY (constant-time compare).
 * The service-role branch is NOT a leftover: production's cron (jobid 9,
 * every 2 min, 032) sends `Bearer <Vault secret 'service_role_key'>`; read-only
 * production check 2026-09-15T05:45Z: that Vault secret name exists, the job
 * is active, 60/60 runs succeeded and 58 HTTP responses were 200 in 2 h. The
 * in-code comment "pg_cron sends the service_role_key via app.settings" is
 * stale only about the mechanism (app.settings -> Vault since 032), not about
 * the key. Refusing the service-role key would stop production's sweep.
 *
 * CONTRACT PINNED:
 *   * absent header, `Bearer ` with an empty token, a non-Bearer scheme, a
 *     wrong token, a prefix of the real secret, and a token whose length
 *     matches but content differs each get 401 {error:'Unauthorized'} with
 *     ZERO Supabase clients, queries or RPCs, ZERO Stripe calls and ZERO
 *     outbound fetches before the response;
 *   * INTERNAL_CRON_SECRET and SUPABASE_SERVICE_ROLE_KEY are accepted (the
 *     handler proceeds past authentication and opens its service client);
 *   * an unset INTERNAL_CRON_SECRET never makes an empty bearer valid.
 * Negative control: with the check removed, every refusal case fails.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockStripe, mockSupabase, type StripeCall } from './helpers/edge-vm';
import { isCrossModeStripeError, rowIsLiveActionable, allowTestModeMoney, classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry } from '../supabase/functions/_shared/payout-logic';
import { classifyPayout, DEFAULT_POLICY } from '../supabase/functions/_shared/payout-policy';

const CRON = 'cron-secret-test-0123456789';
const SERVICE = 'service-role-test-abcdefghij';

async function harness(env: Record<string, string | undefined> = {}) {
  const sb = mockSupabase({ rpc: () => ({ data: [] }), tables: {} });
  const stripe = mockStripe((_c: StripeCall) => ({ ok: false, status: 404, data: { error: { message: 'unmocked' } } }));
  const fetches: string[] = [];
  const edge = await loadEdgeHandler('supabase/functions/enforce-transfer-expiry/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: SERVICE, INTERNAL_CRON_SECRET: CRON, ...env },
    fetch: (async (url: string | URL | Request) => { fetches.push(String(url)); return new Response('{}', { status: 200 }); }) as unknown as typeof fetch,
    provide: {
      stripeFetch: stripe.stripeFetch,
      classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry,
      createSellerPayout: async () => ({ ok: false, error: 'not under test' }),
      executePayoutAttempt: async () => ({ ok: false, outcome: 'not_under_test' }),
      isCrossModeStripeError, rowIsLiveActionable, allowTestModeMoney,
      classifyPayout, DEFAULT_POLICY, PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
    },
  });
  const call = async (headers: Record<string, string>) => {
    const res = await edge.handler(new Request('https://edge.test/enforce-transfer-expiry', { method: 'POST', headers }));
    return { res, body: await json(res) };
  };
  const untouched = () => sb.clients.length === 0 && sb.queries.length === 0 && sb.rpcs.length === 0 && stripe.calls.length === 0 && fetches.length === 0;
  return { sb, stripe, fetches, call, untouched };
}

describe('enforce-transfer-expiry — bearer check refuses before touching anything', () => {
  const refused: Array<[string, Record<string, string>]> = [
    ['no Authorization header (CI\'s cron without a Vault secret)', {}],
    ['"Bearer " with an empty token', { authorization: 'Bearer ' }],
    ['a non-Bearer scheme carrying the real secret', { authorization: `Basic ${CRON}` }],
    ['a wrong token', { authorization: 'Bearer not-the-secret' }],
    ['a prefix of the real cron secret', { authorization: `Bearer ${CRON.slice(0, -1)}` }],
    ['a same-length token with different content', { authorization: `Bearer ${'x'.repeat(CRON.length)}` }],
    ['the literal string "null"', { authorization: 'Bearer null' }],
  ];
  for (const [label, headers] of refused) {
    it(`401 with zero Supabase, Stripe and fetch calls: ${label}`, async () => {
      const h = await harness();
      const { res, body } = await h.call(headers);
      expect(res.status).toBe(401);
      expect(body).toEqual({ error: 'Unauthorized' });
      expect(h.untouched()).toBe(true);
    });
  }

  it('an unset INTERNAL_CRON_SECRET never makes an empty bearer valid', async () => {
    const h = await harness({ INTERNAL_CRON_SECRET: '' });
    const { res } = await h.call({ authorization: 'Bearer ' });
    expect(res.status).toBe(401);
    expect(h.untouched()).toBe(true);
  });
});

describe('enforce-transfer-expiry — the two accepted credentials proceed past authentication', () => {
  it('INTERNAL_CRON_SECRET is accepted (manual trigger)', async () => {
    const h = await harness();
    const { res } = await h.call({ authorization: `Bearer ${CRON}` });
    expect(res.status).not.toBe(401);
    expect(h.sb.clients.length).toBeGreaterThan(0);
  });

  it('SUPABASE_SERVICE_ROLE_KEY is accepted — production\'s pg_cron sends it from Vault (032); refusing it would stop the sweep', async () => {
    const h = await harness();
    const { res } = await h.call({ authorization: `Bearer ${SERVICE}` });
    expect(res.status).not.toBe(401);
    expect(h.sb.clients.length).toBeGreaterThan(0);
  });
});
