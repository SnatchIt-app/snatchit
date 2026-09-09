/**
 * tests/delete-account.test.ts — the REAL converged delete-account handler
 * (deployed OR-17 tombstone body v19 + PRP-3 obligations surface):
 *   • empty body ⇒ action 'request' ⇒ kernel.request_account_deletion through a
 *     CALLER-JWT client (anon key + Authorization header, schema 'kernel'),
 *     never the service key; response keeps { success: true } (build 13);
 *   • the live-rail obligations (public.account_deletion_blockers) are read
 *     through the SERVICE client BEFORE the request and returned additively as
 *     pending_obligations — the request is still accepted (OR-17 always-accepts;
 *     enforcement is the sweep's BP-13, migration 20260906130000);
 *   • a failed obligations read does NOT block the request: obligations_check
 *     'unavailable' + Sentry, request proceeds (the terminal re-checks);
 *   • withdraw ⇒ kernel.withdraw_account_deletion, no obligations read;
 *   • kernel RPC error ⇒ 500 + Sentry; invalid action ⇒ 400; missing auth ⇒ 401;
 *     rate limit fail-closed (503 on RPC error, 429 over limit);
 *   • auth.admin.deleteUser and delete_account_cleanup are called by NOTHING.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockSupabase } from './helpers/edge-vm';

const ENV = {
  SUPABASE_URL: 'https://x.invalid',
  SUPABASE_SERVICE_ROLE_KEY: 'service-test',
  SUPABASE_ANON_KEY: 'anon-test',
};
const USER = 'user-1';

interface World {
  blockers?: Array<{ kind: string; ref_id: string }> | 'error' | 'throw';
  rateLimit?: 'allowed' | 'over_limit' | 'error';
  kernelError?: string;
  kernelStatus?: string;
}

async function load(w: World = {}) {
  const calls: string[] = [];
  const sentry: string[] = [];
  const sb = mockSupabase({
    user: { id: USER },
    rpc: async (name, params, schema) => {
      calls.push(`rpc:${schema ?? 'public'}.${name}`);
      if (name === 'check_rate_limit') {
        if (w.rateLimit === 'error') return { data: null, error: { message: 'rl down' } };
        return { data: w.rateLimit !== 'over_limit' };
      }
      if (name === 'account_deletion_blockers') {
        if (w.blockers === 'error') return { data: null, error: { message: 'connection reset' } };
        if (w.blockers === 'throw') throw new Error('socket hang up');
        return { data: w.blockers ?? [] };
      }
      if (name === 'request_account_deletion' || name === 'withdraw_account_deletion') {
        expect(schema).toBe('kernel');
        expect(typeof params.p_command_key).toBe('string');
        if (w.kernelError) return { data: null, error: { message: w.kernelError } };
        return { data: { status: w.kernelStatus ?? 'ok' } };
      }
      if (name === 'delete_account_cleanup') { calls.push('FORBIDDEN:delete_account_cleanup'); return { data: null }; }
      return { data: null };
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/delete-account/index.ts', {
    supabase: sb,
    env: ENV,
    provide: { captureException: async (scope: string, err: unknown) => { sentry.push(`${scope}:${err instanceof Error ? err.message : String(err)}`); } },
  });
  return { sb, edge, calls, sentry };
}

describe('delete-account (converged: OR-17 tombstone + PRP-3 obligations)', () => {
  it('empty body ⇒ request via the caller-JWT kernel client; success:true kept for build 13; no obligations ⇒ empty list', async () => {
    const { sb, edge, calls } = await load();
    const res = await edge.handler(new Request('https://x.invalid/delete-account', {
      method: 'POST', headers: { authorization: 'Bearer tok-1' }, // empty body, like the deployed mobile client
    }));
    const body = await json(res);
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ success: true, action: 'request', status: 'ok', deletion_state: 'DELETION_PENDING', pending_obligations: [], obligations_check: 'ok' });
    expect(calls).toEqual(['rpc:public.check_rate_limit', 'rpc:public.account_deletion_blockers', 'rpc:kernel.request_account_deletion']);
    // EA-1: the kernel call went through a client built from the ANON key + the caller's Authorization header
    const kernelClient = sb.clients.find((c) => c.schema === 'kernel');
    expect(kernelClient).toBeDefined();
    expect(kernelClient!.key).toBe('anon-test');
    expect(kernelClient!.authHeader).toBe('Bearer tok-1');
    // the obligations read and rate limit went through the SERVICE client
    expect(sb.clients.filter((c) => c.key === 'service-test').length).toBeGreaterThan(0);
    expect(calls.some((c) => c.includes('delete_account_cleanup'))).toBe(false);
  });

  it('live-rail obligations are surfaced but the request is still accepted (OR-17; enforcement = sweep BP-13)', async () => {
    const { edge, calls } = await load({ blockers: [
      { kind: 'paid_no_transfer', ref_id: 'p-1' },
      { kind: 'open_manual_review', ref_id: 't-9' },
    ] });
    const res = await edge.handler(authedJsonRequest({}));
    const body = await json(res) as { pending_obligations: unknown[]; obligations_check: string; success: boolean; deletion_state: string };
    expect(res.status).toBe(200);
    expect(body.success).toBe(true);
    expect(body.deletion_state).toBe('DELETION_PENDING');
    expect(body.obligations_check).toBe('ok');
    expect(body.pending_obligations).toEqual([
      { kind: 'paid_no_transfer', ref_id: 'p-1' },
      { kind: 'open_manual_review', ref_id: 't-9' },
    ]);
    expect(calls).toContain('rpc:kernel.request_account_deletion');
  });

  it('obligations read error ⇒ request still proceeds; obligations_check unavailable; Sentry captured', async () => {
    const { edge, calls, sentry } = await load({ blockers: 'error' });
    const res = await edge.handler(authedJsonRequest({}));
    const body = await json(res) as Record<string, unknown>;
    expect(res.status).toBe(200);
    expect(body.success).toBe(true);
    expect(body.obligations_check).toBe('unavailable');
    expect(body.pending_obligations).toBeNull();
    expect(calls).toContain('rpc:kernel.request_account_deletion');
    expect(sentry.some((s) => s.includes('account_deletion_blockers: connection reset'))).toBe(true);
  });

  it('obligations read THROWS ⇒ same behaviour (terminal re-checks)', async () => {
    const { edge, sentry } = await load({ blockers: 'throw' });
    const res = await edge.handler(authedJsonRequest({}));
    const body = await json(res) as Record<string, unknown>;
    expect(res.status).toBe(200);
    expect(body.obligations_check).toBe('unavailable');
    expect(sentry.length).toBe(1);
  });

  it('withdraw ⇒ kernel.withdraw_account_deletion; no obligations read; deletion_state ACTIVE; no obligation fields', async () => {
    const { edge, calls } = await load();
    const res = await edge.handler(authedJsonRequest({ action: 'withdraw' }));
    const body = await json(res) as Record<string, unknown>;
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ success: true, action: 'withdraw', status: 'ok', deletion_state: 'ACTIVE' });
    expect(body).not.toHaveProperty('pending_obligations');
    expect(calls).toEqual(['rpc:public.check_rate_limit', 'rpc:kernel.withdraw_account_deletion']);
  });

  it('kernel RPC status is passed through (noop_replay)', async () => {
    const { edge } = await load({ kernelStatus: 'noop_replay' });
    const body = await json(await edge.handler(authedJsonRequest({}))) as Record<string, unknown>;
    expect(body.status).toBe('noop_replay');
  });

  it('kernel RPC error ⇒ 500 + Sentry, generic message', async () => {
    const { edge, sentry } = await load({ kernelError: 'identity erased' });
    const res = await edge.handler(authedJsonRequest({}));
    expect(res.status).toBe(500);
    expect((await json(res) as { error: string }).error).toMatch(/Failed to submit your deletion request/);
    expect(sentry.some((s) => s.includes('request_account_deletion: identity erased'))).toBe(true);
  });

  it('invalid action ⇒ 400 before any kernel call', async () => {
    const { edge, calls } = await load();
    const res = await edge.handler(authedJsonRequest({ action: 'purge' }));
    expect(res.status).toBe(400);
    expect(calls.some((c) => c.startsWith('rpc:kernel.'))).toBe(false);
  });

  it('missing Authorization ⇒ 401, nothing called', async () => {
    const { edge, calls } = await load();
    const res = await edge.handler(new Request('https://x.invalid/delete-account', { method: 'POST', body: '{}' }));
    expect(res.status).toBe(401);
    expect(calls).toEqual([]);
  });

  it('rate limit: RPC error ⇒ 503 (fail closed); over limit ⇒ 429; nothing else runs', async () => {
    const a = await load({ rateLimit: 'error' });
    expect((await a.edge.handler(authedJsonRequest({}))).status).toBe(503);
    expect(a.calls).toEqual(['rpc:public.check_rate_limit']);
    const b = await load({ rateLimit: 'over_limit' });
    expect((await b.edge.handler(authedJsonRequest({}))).status).toBe(429);
    expect(b.calls).toEqual(['rpc:public.check_rate_limit']);
  });

  it('non-POST ⇒ 405; OPTIONS ⇒ 204 with CORS headers', async () => {
    const { edge } = await load();
    expect((await edge.handler(new Request('https://x.invalid/delete-account', { method: 'GET' }))).status).toBe(405);
    const opt = await edge.handler(new Request('https://x.invalid/delete-account', { method: 'OPTIONS' }));
    expect(opt.status).toBe(204);
    expect(opt.headers.get('Access-Control-Allow-Origin')).toBe('https://snatchitapp.com');
  });
});
