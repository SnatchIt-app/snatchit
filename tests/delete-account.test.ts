/**
 * tests/delete-account.test.ts — the REAL delete-account handler fails
 * closed (F10, migration 20260906120000):
 *   • account_deletion_blockers lookup error ⇒ 503, nothing deleted;
 *   • any blocker ⇒ 409 with the blocker kinds, nothing deleted;
 *   • clean ⇒ the account_deletions ledger advances gate → archived →
 *     cleaned → storage → done, the Connect id is recorded BEFORE cleanup,
 *     cleanup / storage / auth delete run once;
 *   • a retry resumes from the recorded phase and never re-runs the gate
 *     after 'cleaned'; 'done' is idempotent;
 *   • rate limiting stays fail-closed (503 on RPC error).
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockSupabase, type QueryCall } from './helpers/edge-vm';

const ENV = { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' };
const USER = 'user-1';

interface World {
  blockers?: Array<{ kind: string; ref_id: string }> | 'error';
  rateLimit?: 'allowed' | 'error';
  existingPhase?: string | null;
  connectId?: string | null;
  cleanupError?: string;
}

async function load(w: World = {}) {
  const ledgerWrites: Array<{ op: string; body: Record<string, unknown> }> = [];
  const calls: string[] = [];
  const sb = mockSupabase({
    user: { id: USER },
    rpc: async (name) => {
      calls.push(`rpc:${name}`);
      if (name === 'check_rate_limit') return w.rateLimit === 'error' ? { data: null, error: { message: 'rl down' } } : { data: true };
      if (name === 'account_deletion_blockers') return w.blockers === 'error' ? { data: null, error: { message: 'connection reset' } } : { data: w.blockers ?? [] };
      if (name === 'delete_account_cleanup') return w.cleanupError ? { data: null, error: { message: w.cleanupError } } : { data: null };
      return { data: null };
    },
    tables: {
      account_deletions: (q: QueryCall) => {
        calls.push(`account_deletions:${q.op}`);
        if (q.op === 'select') return { data: w.existingPhase ? { user_id: USER, phase: w.existingPhase, connect_id: w.connectId ?? null } : null };
        ledgerWrites.push({ op: q.op, body: q.body as Record<string, unknown> });
        return { data: null };
      },
      profiles: () => { calls.push('profiles:select'); return { data: { stripe_connect_id: w.connectId === undefined ? 'acct_live_1' : w.connectId } }; },
      bids: (q: QueryCall) => { calls.push(`bids:${q.op}`); return { data: null }; },
      transfers: () => { calls.push('transfers:select'); return { data: [] }; },
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/delete-account/index.ts', { supabase: sb, env: ENV });
  const call = () => edge.handler(authedJsonRequest({}));
  const phases = () => ledgerWrites.map((x) => x.body.phase);
  return { sb, edge, call, calls, ledgerWrites, phases };
}

describe('delete-account gate', () => {
  it('blocker lookup error ⇒ 503 and NOTHING is deleted', async () => {
    const h = await load({ blockers: 'error' });
    const res = await h.call();
    expect(res.status).toBe(503);
    expect(h.calls).not.toContain('rpc:delete_account_cleanup');
    expect(h.phases()).toEqual([]);
  });

  it('open obligations ⇒ 409 with the blocker kinds; nothing deleted', async () => {
    const h = await load({ blockers: [{ kind: 'unpaid_seller_obligation', ref_id: 't1' }, { kind: 'open_dispute', ref_id: 't2' }, { kind: 'open_dispute', ref_id: 't3' }] });
    const res = await h.call();
    expect(res.status).toBe(409);
    const body = await json(res);
    expect(body.blockers).toEqual(['unpaid_seller_obligation', 'open_dispute']);
    expect(h.calls).not.toContain('rpc:delete_account_cleanup');
    expect(h.phases()).toEqual([]);
  });

  it('the old status-only check is gone: the gate is the RPC, not a transfers query', async () => {
    const h = await load({ blockers: [] });
    await h.call();
    expect(h.calls).toContain('rpc:account_deletion_blockers');
    expect(h.calls).not.toContain('transfers:select');
  });

  it('rate-limit RPC error ⇒ 503 (fail closed) before any lookup', async () => {
    const h = await load({ rateLimit: 'error' });
    expect((await h.call()).status).toBe(503);
    expect(h.calls).not.toContain('rpc:account_deletion_blockers');
  });
});

describe('delete-account ledger', () => {
  it('clean user ⇒ phases advance gate → archived → cleaned → storage → done; Connect id captured before cleanup', async () => {
    const h = await load({ blockers: [] });
    const res = await h.call();
    expect(res.status).toBe(200);
    expect(await json(res)).toMatchObject({ success: true });
    expect(h.phases()).toEqual(['gate', 'archived', 'cleaned', 'storage', 'done']);
    const archived = h.ledgerWrites.find((x) => x.body.phase === 'archived')!;
    expect(archived.body.connect_id).toBe('acct_live_1');
    const order = h.calls.filter((c) => ['rpc:account_deletion_blockers', 'profiles:select', 'rpc:delete_account_cleanup', 'bids:delete'].includes(c));
    expect(order).toEqual(['rpc:account_deletion_blockers', 'profiles:select', 'rpc:delete_account_cleanup', 'bids:delete']);
    expect(h.calls.filter((c) => c === 'rpc:delete_account_cleanup')).toHaveLength(1);
  });

  it('cleanup failure ⇒ 500, ledger stays at archived (retryable)', async () => {
    const h = await load({ blockers: [], cleanupError: 'boom' });
    expect((await h.call()).status).toBe(500);
    expect(h.phases()).toEqual(['gate', 'archived']);
  });

  it('retry from phase cleaned ⇒ gate NOT re-run, cleanup NOT re-run, continues storage → done', async () => {
    const h = await load({ existingPhase: 'cleaned', blockers: 'error' });   // a gate re-run would 503
    const res = await h.call();
    expect(res.status).toBe(200);
    expect(h.calls).not.toContain('rpc:account_deletion_blockers');
    expect(h.calls).not.toContain('rpc:delete_account_cleanup');
    expect(h.phases()).toEqual(['storage', 'done']);
  });

  it('retry from phase archived ⇒ gate re-runs (still allowed), archive step skipped', async () => {
    const h = await load({ existingPhase: 'archived', blockers: [], connectId: 'acct_prev' });
    const res = await h.call();
    expect(res.status).toBe(200);
    expect(h.calls).toContain('rpc:account_deletion_blockers');
    expect(h.calls).not.toContain('profiles:select');
    expect(h.phases()).toEqual(['cleaned', 'storage', 'done']);
  });

  it('phase done ⇒ 200 idempotent, no further work', async () => {
    const h = await load({ existingPhase: 'done', blockers: 'error' });
    const res = await h.call();
    expect(res.status).toBe(200);
    expect(h.calls.filter((c) => c.startsWith('rpc:') && c !== 'rpc:check_rate_limit')).toEqual([]);
    expect(h.phases()).toEqual([]);
  });
});
