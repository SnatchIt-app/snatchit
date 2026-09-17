/**
 * tests/notify-report-claim.test.ts — G22 (owner ruling 2026-09-17, keys ruled
 * by A): notify-report claims a delivery BEFORE it sends anything.
 *
 * WHY. notify-report is driven by database triggers through pg_net and answers
 * 200 even on failure so callers never retry-storm. Nothing recorded that an
 * event had already been announced, so a duplicate trigger fire or a replayed
 * post re-sent every push and every email.
 *
 * THE KEYS, and why the third one is not like the others:
 *   report_created          → report_id     (one-shot)
 *   dispute_opened          → transfer_id   (one-shot)
 *   signing_invariant_alert → the monitor RUN, as the UTC date — NEVER the
 *     alert text. That alert fires on a daily cron and repeats with the SAME
 *     codes while the trust root stays wrong, so a key of (event, summary)
 *     would announce a compromise once and silence every later warning.
 *
 * FAIL TOWARD DELIVERING. Only an explicit `false` — someone else already
 * announced this — suppresses a send. A claim that ERRORS sends anyway and
 * logs: a duplicate notification is a nuisance, a missing "your account is
 * under review" or a missing trust-root alarm is not.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockSupabase, type RpcHandler } from './helpers/edge-vm';

const SERVICE = 'service-role-test-key';
const ADMIN   = 'admin-0001';

function world(init: { claim?: boolean; claimError?: boolean; sends?: 'ok' | 'throw' | '500' | 'first-ok' } = {}) {
  const claims: Array<{ params: Record<string, unknown>; schema: string | null }> = [];
  const releases: Array<{ params: Record<string, unknown>; schema: string | null }> = [];
  const rpc: RpcHandler = (name, params, schema) => {
    if (name === 'claim_report_delivery') {
      claims.push({ params, schema });
      if (init.claimError) return { data: null, error: { message: 'boom', code: 'XX000' } };
      return { data: init.claim ?? true };
    }
    if (name === 'release_report_delivery') {
      releases.push({ params, schema });
      return { data: true };
    }
    return { data: null };
  };
  const sb = mockSupabase({
    rpc,
    tables: {
      admin_users: () => ({ data: [{ user_id: ADMIN }] }),
      listings: () => ({ data: { seller_id: 'seller-1' } }),
    },
  });
  const sent: Array<{ url: string; body: Record<string, unknown> }> = [];
  const call = async (payload: Record<string, unknown>, auth = `Bearer ${SERVICE}`) => {
    const edge = await loadEdgeHandler('supabase/functions/notify-report/index.ts', {
      supabase: sb,
      env: { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: SERVICE },
      fetch: (async (url: string | URL | Request, init2?: RequestInit) => {
        const n = sent.length;
        sent.push({ url: String(url), body: JSON.parse(String(init2?.body ?? '{}')) as Record<string, unknown> });
        if (init.sends === 'throw') throw new Error('socket hang up');
        if (init.sends === '500') return new Response('nope', { status: 500 });
        // 'first-ok': the first attempt lands, the rest fail — a PARTIAL success
        if (init.sends === 'first-ok' && n > 0) return new Response('nope', { status: 500 });
        return new Response('{}', { status: 200 });
      }) as unknown as typeof fetch,
      provide: { captureException: async () => {} },
    });
    const res = await edge.handler(new Request('https://edge.test/notify-report', {
      method: 'POST', headers: { authorization: auth, 'Content-Type': 'application/json' }, body: JSON.stringify(payload),
    }));
    return { res, body: await json(res), edge, sent, claims, releases };
  };
  return { call, sb };
}

const logsOf = (edge: { logs: Array<{ args: unknown[] }> }) =>
  edge.logs.map((l) => l.args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')).join('\n');
const today = () => new Date().toISOString().slice(0, 10);

describe('notify-report — a delivery is claimed before anything is sent (G22)', () => {
  it('G1: report_created claims on the report id, through the notify schema', async () => {
    const w = world();
    const { res, claims } = await w.call({ event: 'report_created', report_id: 'rep-1', reporter_id: 'u-1', target_type: 'user', target_id: 'u-2', reason: 'spam' });
    expect(res.status).toBe(200);
    expect(claims).toHaveLength(1);
    expect(claims[0].params).toEqual({ p_kind: 'report_created', p_key: 'rep-1' });
    expect(claims[0].schema).toBe('notify');
  });

  it('G2: a second delivery of the same report sends NOTHING and still answers 200', async () => {
    const w = world({ claim: false });
    const { res, sent } = await w.call({ event: 'report_created', report_id: 'rep-1', reporter_id: 'u-1', target_type: 'user', target_id: 'u-2', reason: 'spam' });
    expect(res.status).toBe(200);
    expect(sent).toHaveLength(0);
  });

  it('G3: dispute_opened claims on the transfer id', async () => {
    const w = world();
    const { claims } = await w.call({ event: 'dispute_opened', transfer_id: 'tr-9', buyer_id: 'b-1', seller_id: 's-1', reason: 'not_received' });
    expect(claims[0].params).toEqual({ p_kind: 'dispute_opened', p_key: 'tr-9' });
  });

  it('G4: a second delivery of the same dispute sends nothing', async () => {
    const w = world({ claim: false });
    const { sent } = await w.call({ event: 'dispute_opened', transfer_id: 'tr-9', buyer_id: 'b-1', seller_id: 's-1', reason: 'not_received' });
    expect(sent).toHaveLength(0);
  });

  it('G5: the signing alert is keyed on the RUN (today, UTC) and NEVER on the alert text', async () => {
    const w = world();
    const { claims, sent } = await w.call({ event: 'signing_invariant_alert', alerts: ['fingerprint=MISMATCH', 'total_keys=2'] });
    expect(claims[0].params).toEqual({ p_kind: 'signing_invariant_alert', p_key: today() });
    // the whole point: the key must not vary with the alert codes, or tomorrow's
    // identical alert about an unresolved compromise would look "already sent"
    expect(String(claims[0].params.p_key)).not.toContain('MISMATCH');
    expect(String(claims[0].params.p_key)).not.toContain('total_keys');
    expect(sent.length).toBeGreaterThan(0);
  });

  it('G6: a claim that ERRORS still sends — a missing alarm is worse than a duplicate', async () => {
    const w = world({ claimError: true });
    const { res, sent, edge } = await w.call({ event: 'signing_invariant_alert', alerts: ['fingerprint=MISMATCH'] });
    expect(res.status).toBe(200);
    expect(sent.length).toBeGreaterThan(0);
    expect(logsOf(edge).toLowerCase()).toContain('claim');
  });

  it('G7: the claim gates every channel — a duplicate signing alert sends no push at all', async () => {
    const w = world({ claim: false });
    const { sent } = await w.call({ event: 'signing_invariant_alert', alerts: ['fingerprint=MISMATCH'] });
    expect(sent).toHaveLength(0);
  });

  it('G10 (D review): when EVERY delivery attempt fails, the claim is given back — otherwise a one-shot notice is lost for good', async () => {
    // notify-report swallows send errors and answers 200. A claim taken before the
    // send and never released turns "at most once" into "sometimes zero":
    // report_created and dispute_opened have no next run, so the notice is gone.
    const w = world({ sends: '500' });
    const { res, releases } = await w.call({ event: 'report_created', report_id: 'rep-1', reporter_id: 'u-1', target_type: 'user', target_id: 'u-2', reason: 'spam' });
    expect(res.status).toBe(200);
    expect(releases).toHaveLength(1);
    expect(releases[0].params).toEqual({ p_kind: 'report_created', p_key: 'rep-1' });
    expect(releases[0].schema).toBe('notify');
  });

  it('G11 (D review): a send that THROWS is also a failed delivery, not a delivered one', async () => {
    const w = world({ sends: 'throw' });
    const { releases } = await w.call({ event: 'dispute_opened', transfer_id: 'tr-9', buyer_id: 'b-1', seller_id: 's-1', reason: 'not_received' });
    expect(releases).toHaveLength(1);
    expect(releases[0].params).toEqual({ p_kind: 'dispute_opened', p_key: 'tr-9' });
  });

  it('G12: a PARTIAL success keeps the claim — the normal path still cannot duplicate', async () => {
    const w = world({ sends: 'first-ok' });
    const { releases, sent } = await w.call({ event: 'report_created', report_id: 'rep-2', reporter_id: 'u-1', target_type: 'user', target_id: 'u-2', reason: 'spam' });
    expect(sent.length).toBeGreaterThan(1);
    expect(releases).toHaveLength(0);
  });

  it('G13: nothing is released when every delivery succeeded', async () => {
    const w = world();
    const { releases } = await w.call({ event: 'signing_invariant_alert', alerts: ['fingerprint=MISMATCH'] });
    expect(releases).toHaveLength(0);
  });

  it('G8: an unknown event claims nothing and sends nothing (unchanged)', async () => {
    const w = world();
    const { res, claims, sent } = await w.call({ event: 'something_else' });
    expect(res.status).toBe(200);
    expect(claims).toHaveLength(0);
    expect(sent).toHaveLength(0);
  });

  it('G9: an unauthorized caller is refused before any claim', async () => {
    const w = world();
    const { res, claims, sent } = await w.call({ event: 'report_created', report_id: 'rep-1' }, 'Bearer nope');
    expect(res.status).toBe(401);
    expect(claims).toHaveLength(0);
    expect(sent).toHaveLength(0);
  });
});
