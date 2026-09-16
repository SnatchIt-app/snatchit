/**
 * tests/send-push-challenge.test.ts — b2 item 5 (O-3 close-out): send-push's
 * `push_token_challenge` kind, the provider-side proof of possession delivery.
 *
 * WHY. A push binding becomes deliverable for an account only after the push
 * provider proves the registering device holds the token: the server issues a
 * one-time nonce, sends it TO THAT TOKEN, and the device echoes it back. This
 * edge is the send half. A plant-then-claim or delete-then-register from a
 * second device never activates, because the nonce goes to the victim's phone.
 *
 * CONTRACT (v3 draft, A). Request {kind:'push_token_challenge', challenge_id,
 * nonce, user_id}. The edge reads notify.push_token_challenges by id (token,
 * mode, expires_at, confirmed_at, attempts) and relays the nonce, which is
 * stored only as a hash and so must arrive in the request. Silent mode sends an
 * Expo `_contentAvailable` data push; visible mode an alert carrying a 6-digit
 * code and "never share this code".
 *
 * PINNED HERE:
 *   * service-role-only entry, as for every other send-push call;
 *   * a challenge that is missing, expired, already confirmed or out of attempts
 *     is refused and NOTHING is sent;
 *   * the rate limits are re-checked in the edge (the DB verb is the authority)
 *     and a refusal sends nothing;
 *   * the push goes to the challenge row's OWN token, never to the user's other
 *     tokens — that is the whole point of proof of possession;
 *   * the nonce never appears in any log line or error body (a mutant that logs
 *     it must fail).
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockSupabase, type QueryCall, type RpcHandler } from './helpers/edge-vm';

const SERVICE = 'service-role-test-key';
const USER = '11111111-1111-1111-1111-111111111111';
const CHALLENGE = '22222222-2222-2222-2222-222222222222';
const TOKEN = 'ExponentPushToken[victim-phone]';
const NONCE = '481624';

type Challenge = {
  id: string; token_id: string; token: string; requesting_user: string; mode: 'silent' | 'visible';
  expires_at: string; confirmed_at: string | null; attempts: number;
};
const challengeRow = (over: Partial<Challenge> = {}): Challenge => ({
  id: CHALLENGE, token_id: 'tok-1', token: TOKEN, requesting_user: USER, mode: 'silent',
  expires_at: new Date(Date.now() + 5 * 60_000).toISOString(), confirmed_at: null, attempts: 0, ...over,
});

function world(init: { challenge?: Challenge | null; rateLimit?: boolean | 'error'; provider?: 'ok' | 'rejected' | 'throws'; recordFails?: boolean } = {}) {
  const pushes: Array<Record<string, unknown>> = [];
  const recorded: Array<Record<string, unknown>> = [];
  const rpc: RpcHandler = (name, params) => {
    if (name === 'check_rate_limit') {
      if (init.rateLimit === 'error') return { data: null, error: { message: 'boom', code: 'XX000' } };
      return { data: init.rateLimit ?? true };
    }
    // 135 (A): the delivery outcome lands on the challenge row, never on notify.delivery
    if (name === 'record_push_token_challenge_delivery') {
      if (init.recordFails) return { data: null, error: { message: 'not applied yet', code: 'PGRST202' } };
      recorded.push(params);
      return { data: { ok: true } };
    }
    return { data: null };
  };
  const sb = mockSupabase({
    rpc,
    tables: {
      push_token_challenges: (q: QueryCall) => {
        const wanted = q.filters.find((f) => f[0] === 'eq' && f[1] === 'id')?.[2];
        const row = init.challenge === undefined ? challengeRow() : init.challenge;
        return { data: row && row.id === wanted ? row : null };
      },
      push_tokens: () => ({ data: [{ token: 'ExponentPushToken[attacker-phone]' }] }),
    },
  });
  const call = async (body: unknown, auth = `Bearer ${SERVICE}`) => {
    const edge = await loadEdgeHandler('supabase/functions/send-push/index.ts', {
      supabase: sb,
      env: { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: SERVICE, EXPO_PUSH_URL: 'https://push.invalid/send' },
      fetch: (async (_url: string | URL | Request, req?: { body?: string }) => {
        for (const m of JSON.parse(String(req?.body ?? '[]'))) pushes.push(m);
        if (init.provider === 'throws') throw new Error('socket hang up');
        if (init.provider === 'rejected') {
          return new Response(JSON.stringify({ data: [{ status: 'error', message: 'DeviceNotRegistered' }] }), { status: 200 });
        }
        return new Response(JSON.stringify({ data: [{ status: 'ok', id: 'receipt-1' }] }), { status: 200 });
      }) as unknown as typeof fetch,
    });
    const res = await edge.handler(new Request('https://edge.test/send-push', {
      method: 'POST', headers: { authorization: auth, 'Content-Type': 'application/json' }, body: JSON.stringify(body),
    }));
    return { res, body: await json(res), edge, pushes };
  };
  return { call, pushes, recorded, sb };
}

const challengeReq = (over: Record<string, unknown> = {}) =>
  ({ kind: 'push_token_challenge', challenge_id: CHALLENGE, nonce: NONCE, user_id: USER, ...over });
const logsOf = (edge: { logs: Array<{ args: unknown[] }> }) =>
  edge.logs.map((l) => l.args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')).join('\n');

describe('send-push — push_token_challenge delivery (b2, provider-side proof of possession)', () => {
  it('A1: a caller without the service-role key is refused and nothing is sent', async () => {
    const w = world();
    const { res } = await w.call(challengeReq(), 'Bearer anon-key');
    expect(res.status).toBe(401);
    expect(w.pushes).toHaveLength(0);
  });

  it('A2: silent mode sends ONE data push to the challenge row\'s own token, with no title or body', async () => {
    const w = world();
    const { res, body } = await w.call(challengeReq());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ sent: 1, mode: 'silent' });
    expect(w.pushes).toHaveLength(1);
    const m = w.pushes[0] as Record<string, unknown>;
    expect(m.to).toBe(TOKEN);
    expect(m._contentAvailable).toBe(true);
    expect(m.title).toBeUndefined();
    expect(m.body).toBeUndefined();
    expect(m.data).toEqual({ type: 'push_token_challenge', challenge_id: CHALLENGE, nonce: NONCE });
  });

  it('A3: visible mode sends the 6-digit code with the "never share this code" copy, and no nonce in data', async () => {
    const w = world({ challenge: challengeRow({ mode: 'visible' }) });
    const { res, body } = await w.call(challengeReq());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ sent: 1, mode: 'visible' });
    const m = w.pushes[0] as Record<string, unknown>;
    expect(m.to).toBe(TOKEN);
    expect(String(m.body)).toContain(NONCE);
    expect(String(m.body).toLowerCase()).toContain('never share this code');
    expect(JSON.stringify(m.data ?? {})).not.toContain(NONCE);
  });

  it('A4: the push never goes to the user\'s other tokens — only the challenge row\'s token', async () => {
    const w = world();
    await w.call(challengeReq());
    expect(w.pushes.map((m) => m.to)).toEqual([TOKEN]);
    expect(JSON.stringify(w.pushes)).not.toContain('attacker-phone');
  });

  const refusals: Array<[string, Challenge | null, number]> = [
    ['an unknown challenge id', null, 404],
    ['an expired challenge', challengeRow({ expires_at: new Date(Date.now() - 1000).toISOString() }), 410],
    ['a challenge already confirmed', challengeRow({ confirmed_at: new Date().toISOString() }), 409],
    ['a challenge out of attempts', challengeRow({ attempts: 5 }), 429],
  ];
  for (const [label, row, status] of refusals) {
    it(`A5: ${label} is refused (${status}) and nothing is sent`, async () => {
      const w = world({ challenge: row });
      const { res, body } = await w.call(challengeReq());
      expect(res.status).toBe(status);
      expect(w.pushes).toHaveLength(0);
      expect(JSON.stringify(body)).not.toContain(NONCE);
    });
  }

  it('A6: a challenge for a different user than the request is refused', async () => {
    const w = world({ challenge: challengeRow({ requesting_user: '33333333-3333-3333-3333-333333333333' }) });
    const { res } = await w.call(challengeReq());
    expect(res.status).toBe(409);
    expect(w.pushes).toHaveLength(0);
  });

  it('A7: the edge re-checks the rate limits — a refusal sends nothing (429)', async () => {
    const w = world({ rateLimit: false });
    const { res } = await w.call(challengeReq());
    expect(res.status).toBe(429);
    expect(w.pushes).toHaveLength(0);
  });

  it('A8: a rate-limiter error fails closed — 503, nothing sent', async () => {
    const w = world({ rateLimit: 'error' });
    const { res } = await w.call(challengeReq());
    expect(res.status).toBe(503);
    expect(w.pushes).toHaveLength(0);
  });

  it('A9: the rate limits are checked per user AND per token, in their own key namespace', async () => {
    const w = world();
    await w.call(challengeReq());
    const keys = w.sb.rpcs.filter((r) => r.name === 'check_rate_limit').map((r) => String(r.params.p_action ?? ''));
    expect(keys).toContain(`push_challenge_edge_user:${USER}`);
    // D's pin: the token limit is per (token, requesting user)
    expect(keys).toContain(`push_challenge_edge_token:tok-1:${USER}`);
  });

  it('A13: a successful send records the delivery outcome on the challenge row', async () => {
    const w = world();
    const { res } = await w.call(challengeReq());
    expect(res.status).toBe(200);
    expect(w.recorded).toHaveLength(1);
    expect(w.recorded[0]).toMatchObject({ p_challenge_id: CHALLENGE, p_outcome: 'sent', p_provider_message_id: 'receipt-1' });
    expect(JSON.stringify(w.recorded)).not.toContain(NONCE);
  });

  it('A14: a provider rejection answers 502 and records the outcome', async () => {
    const w = world({ provider: 'rejected' });
    const { res } = await w.call(challengeReq());
    expect(res.status).toBe(502);
    expect(w.recorded[0]).toMatchObject({ p_challenge_id: CHALLENGE, p_outcome: 'rejected' });
  });

  it('A15: a provider call that throws answers 502 and records the outcome, without the payload', async () => {
    const w = world({ provider: 'throws' });
    const { res, edge } = await w.call(challengeReq());
    expect(res.status).toBe(502);
    expect(w.recorded[0]).toMatchObject({ p_challenge_id: CHALLENGE, p_outcome: 'error' });
    expect(logsOf(edge)).not.toContain(NONCE);
  });

  it('A16: a recording failure (135 not applied yet) never changes the answer', async () => {
    const w = world({ recordFails: true });
    const { res, body } = await w.call(challengeReq());
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ sent: 1 });
  });

  it('A17 (D pin): the send is TOKEN-addressed — the row may belong to another account, and nothing identifies its owner', async () => {
    const other = '99999999-9999-9999-9999-999999999999';
    const w = world({ challenge: challengeRow({ requesting_user: USER, token: 'ExponentPushToken[someone-elses-phone]' }) });
    const { res, edge } = await w.call(challengeReq());
    expect(res.status).toBe(200);
    const wire = JSON.stringify(w.pushes);
    expect(wire).toContain('someone-elses-phone');
    // neither the requester nor any other account identifier travels to the device
    expect(wire).not.toContain(USER);
    expect(wire).not.toContain(other);
    expect(wire.toLowerCase()).not.toContain('@');
    expect(logsOf(edge)).not.toContain(USER);
  });

  it('A10: the nonce never reaches a log line, on success or on refusal', async () => {
    const ok = world();
    const okRes = await ok.call(challengeReq());
    expect(logsOf(okRes.edge)).not.toContain(NONCE);
    const bad = world({ challenge: null });
    const badRes = await bad.call(challengeReq());
    expect(logsOf(badRes.edge)).not.toContain(NONCE);
    expect(JSON.stringify(badRes.body)).not.toContain(NONCE);
  });

  it('A11: a missing nonce or challenge_id is refused before any read or send (400)', async () => {
    const w = world();
    expect((await w.call({ kind: 'push_token_challenge', user_id: USER })).res.status).toBe(400);
    expect((await w.call(challengeReq({ nonce: undefined }))).res.status).toBe(400);
    expect(w.pushes).toHaveLength(0);
  });

  it('A12 (preservation): the ordinary notification send is unchanged — user_id, title, body', async () => {
    const w = world();
    const { res, body } = await w.call({ user_id: USER, title: 'Outbid', body: 'Someone outbid you' });
    expect(res.status).toBe(200);
    expect(body).toMatchObject({ sent: 1 });
    const m = w.pushes[0] as Record<string, unknown>;
    expect(m.to).toBe('ExponentPushToken[attacker-phone]');
    expect(m.title).toBe('Outbid');
    expect(m._contentAvailable).toBeUndefined();
  });
});
