/**
 * tests/confirm-and-release-hardening.test.ts — confirm-and-release answers
 * (A, 2026-10-21; source: sprint-control SERVER_REFUSAL_CATALOGUE_C_20261021.md
 * §5 and "Surprising" 5-7).
 *
 *   PC  After confirm_transfer_received has succeeded (or reported the row
 *       already confirmed), no later failure may surface as an error status:
 *       a Stripe pre-flight fetch that throws out of createSellerPayout (CRE-500)
 *       and a failed transfer re-read (CRE-404) both answer 200
 *       {success:true, payout_status:'processing'}; the attempt protocol and the
 *       payout sweep stay the authority.
 *   HC  Every error response carries a JSON `code`. A confirm RPC refusal maps
 *       its Postgres HINT (migration 171: TRANSFER_NOT_CONFIRMABLE) into it, or
 *       null while the RPC raises without one (production today). `error` text
 *       is unchanged.
 *   RL  check_rate_limit (021) returns FALSE from its EXCEPTION branch too; an
 *       internal limiter error answers 503, a real over-limit answers 429.
 *
 * Real handler (tests/helpers/edge-vm.ts) on the real _shared/payouts.ts
 * (tests/helpers/payouts-vm.ts), a stubbed supabase client and a stubbed Stripe
 * transport. No network, no database, no Stripe key.
 */
import { describe, expect, it } from 'vitest';
import { authedJsonRequest, json, loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { loadPayoutsModule } from './helpers/payouts-vm';
import { AttemptLedger, LEASE_MS, StripeTransfersMock, type TransferRow } from './helpers/payout-protocol';

const FN = 'supabase/functions/confirm-and-release/index.ts';
const ENV = { SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test', SUPABASE_ANON_KEY: 'anon-test', STRIPE_SECRET_KEY: 'sk_test_x' };
const CNF1 = (status: string) => `Transfer cannot be confirmed from current status: ${status}.`;

type RpcResult = { data?: unknown; error?: Record<string, unknown> | null };
interface WorldOpts {
  /** row status before the call (default seller_sent) */
  status?: TransferRow['status'];
  /** the check_rate_limit reply (default allowed) */
  rateLimit?: () => RpcResult;
  /** the rate_limits counter read (only reached when check_rate_limit says false) */
  rateRow?: () => { data?: unknown; error?: { message: string } | null };
  /** replace the confirm RPC; default mirrors production 0550 (no HINT) */
  confirm?: (t: TransferRow) => RpcResult | Promise<RpcResult>;
  /** replace the §5 transfers re-read */
  transfersRead?: (q: QueryCall, row: TransferRow | undefined) => { data?: unknown; error?: { message: string } | null };
  /** wrap the Stripe model */
  stripe?: (c: StripeCall, base: StripeTransfersMock['route']) => ReturnType<StripeTransfersMock['route']>;
  /** kernel.identity_ext row for the F-5 guard */
  identityExt?: Record<string, unknown> | null;
}

async function world(o: WorldOpts = {}) {
  const ledger = new AttemptLedger();
  const row = ledger.seedReleasable({ status: o.status ?? 'seller_sent' });
  const stripeMock = new StripeTransfersMock();
  const stripe = mockStripe(async (c) => (o.stripe ? o.stripe(c, stripeMock.route) : stripeMock.route(c)));
  const payouts = loadPayoutsModule(stripe);
  const sb = mockSupabase({
    user: { id: 'buyer-1' },
    rpc: async (name, params) => {
      if (name === 'check_rate_limit') return (o.rateLimit ?? (() => ({ data: true })))() as never;
      if (name === 'confirm_transfer_received') {
        const t = ledger.transfers.get(params.p_transfer_id as string)!;
        if (o.confirm) return (await o.confirm(t)) as never;
        // production 0550 body (a_sprint_prod_template, 2026-10-21): identity, then status; no HINT
        if (t.buyer_id !== params.p_user_id) return { error: { message: 'Only the buyer can confirm transfer receipt.', code: 'P0001', hint: null, details: null } } as never;
        if (t.status !== 'seller_sent') return { error: { message: CNF1(t.status), code: 'P0001', hint: null, details: null } } as never;
        t.status = 'buyer_confirmed'; t.buyer_confirmed_at = new Date().toISOString();
        return { data: null };
      }
      return ledger.rpc(name, params);
    },
    tables: {
      rate_limits: () => (o.rateRow ?? (() => ({ data: null })))(),
      identity_ext: () => ({ data: o.identityExt ?? null }),
      transfers: (q: QueryCall) => {
        const id = q.filters.find((f) => f[0] === 'eq' && f[1] === 'id')?.[2] as string;
        const t = ledger.transfers.get(id);
        if (o.transfersRead && q.select?.includes('payout_released_at')) return o.transfersRead(q, t);
        return { data: t ? { ...t, created_at: new Date().toISOString() } : null };
      },
      payout_decisions: () => ({ data: null }),
      payments: () => ({ data: { amount: 10000, seller_fee: 1000 } }),
    },
  });
  const edge = await loadEdgeHandler(FN, {
    supabase: sb, env: ENV,
    provide: { executePayoutAttempt: payouts.executePayoutAttempt },
  });
  const call = async (req: Request = authedJsonRequest({ transfer_id: 't1' })) => {
    const res = await edge.handler(req);
    return { status: res.status, headers: res.headers, body: await json(res) };
  };
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/transfers');
  const rpcNames = () => sb.rpcs.map((r) => r.name);
  return { ledger, row, stripeMock, stripe, sb, edge, call, posts, rpcNames };
}

const PROCESSING = { success: true, payout_status: 'processing' };

// ── PC: nothing after the confirmation is an error ──────────────────────────

describe('PC — after the confirmation is recorded, every answer is 200', () => {
  it('PC-1 Stripe account pre-flight THROWS inside createSellerPayout ⇒ 200 processing (was CRE-500)', async () => {
    const w = await world({ stripe: (c, base) => { if (c.path.startsWith('/accounts/')) throw new Error('fetch failed: connect ECONNRESET'); return base(c); } });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual(PROCESSING);
    expect(w.ledger.transfers.get('t1')!.status, 'the confirmation committed before the throw').toBe('buyer_confirmed');
    expect(w.posts(), 'nothing was sent').toHaveLength(0);
    // the claimed attempt stays open under its lease: the sweep / next claim reconciles it
    expect(w.ledger.attempts.map((a) => a.state)).toEqual(['claimed']);
    expect(w.edge.sentry.map((s) => s.tag)).toContain('confirm-and-release:after-confirmation');
  });

  it('PC-2 Stripe payment-intent pre-flight THROWS ⇒ 200 processing', async () => {
    const w = await world({ stripe: (c, base) => { if (c.path.startsWith('/payment_intents/')) throw new Error('network timeout'); return base(c); } });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual(PROCESSING);
    expect(w.posts()).toHaveLength(0);
  });

  it('PC-3 the protocol continues after a pre-flight throw: lease expiry ⇒ reconciled absent, then ONE POST', async () => {
    let fail = true;
    const w = await world({ stripe: (c, base) => { if (fail && c.path.startsWith('/accounts/')) throw new Error('network'); return base(c); } });
    expect((await w.call()).body).toEqual(PROCESSING);
    fail = false;
    expect((await w.call()).body, 'lease still live').toEqual(PROCESSING);
    w.ledger.advance(LEASE_MS + 1);
    expect((await w.call()).body, 'open attempt reconciled: nothing on Stripe').toEqual(PROCESSING);
    expect((await w.call()).body).toMatchObject({ success: true, stripe_transfer_id: 'tr_1' });
    expect(w.posts()).toHaveLength(1);
    expect(w.ledger.attempts.map((a) => a.state)).toEqual(['failed', 'succeeded']);
  });

  it('PC-4 the transfer re-read ERRORS after the RPC confirmed ⇒ 200 processing (was CRE-404), no payout attempted', async () => {
    const w = await world({ transfersRead: () => ({ data: null, error: { message: 'upstream request timeout' } }) });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual(PROCESSING);
    expect(w.ledger.transfers.get('t1')!.status).toBe('buyer_confirmed');
    expect(w.rpcNames()).toEqual(['check_rate_limit', 'confirm_transfer_received']);
    expect(w.edge.logs.some((l) => l.level === 'error')).toBe(true);
  });

  it('PC-5 the re-read returns no row (no error) after the RPC confirmed ⇒ 200 processing', async () => {
    const w = await world({ transfersRead: () => ({ data: null }) });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual(PROCESSING);
  });

  it('PC-6 the already-confirmed bypass is a recorded confirmation too: a re-read failure there is 200', async () => {
    const w = await world({ status: 'buyer_confirmed', transfersRead: () => ({ data: null, error: { message: 'timeout' } }) });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual(PROCESSING);
  });

  it('PC-7 control: a throw BEFORE the confirmation is still an error (500 INTERNAL), never a false "confirmed"', async () => {
    const w = await world({ confirm: () => { throw new Error('socket hang up'); } });
    const r = await w.call();
    expect(r.status).toBe(500);
    expect(r.body).toEqual({ error: 'Internal server error', code: 'INTERNAL' });
    expect(w.ledger.transfers.get('t1')!.status).toBe('seller_sent');
  });

  it('PC-8 control: the happy path is unchanged', async () => {
    const w = await world();
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ success: true, stripe_transfer_id: 'tr_1' });
    expect(w.posts()).toHaveLength(1);
  });
});

// ── HC: HINT → code ─────────────────────────────────────────────────────────

describe('HC — confirm RPC refusals carry the Postgres HINT as `code`', () => {
  it('HC-1 with migration 171 (HINT TRANSFER_NOT_CONFIRMABLE, DETAIL status) ⇒ 400, error text unchanged, code = hint', async () => {
    const w = await world({
      status: 'pending',
      confirm: (t) => ({ error: { message: CNF1(t.status), code: 'P0001', hint: 'TRANSFER_NOT_CONFIRMABLE', details: t.status } }),
    });
    const r = await w.call();
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ error: CNF1('pending'), code: 'TRANSFER_NOT_CONFIRMABLE' });
  });

  it('HC-2 production today (no HINT) ⇒ 400, same error text, code null', async () => {
    const w = await world({ status: 'disputed' });
    const r = await w.call();
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ error: CNF1('disputed'), code: null });
  });

  it('HC-3 a free-text hint (PostgREST / Postgres prose) is not a code ⇒ code null', async () => {
    const w = await world({ confirm: () => ({ error: { message: 'Could not find the function public.confirm_transfer_received', code: 'PGRST202', hint: 'Perhaps you meant to call the function public.confirm_transfer_receipt', details: null } }) });
    const r = await w.call();
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ error: 'Could not find the function public.confirm_transfer_received', code: null });
  });

  it('HC-4 with 171 the already-confirmed bypass still proceeds (the hint does not turn it into a refusal)', async () => {
    const w = await world({
      status: 'buyer_confirmed',
      confirm: (t) => ({ error: { message: CNF1(t.status), code: 'P0001', hint: 'TRANSFER_NOT_CONFIRMABLE', details: t.status } }),
    });
    const r = await w.call();
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ success: true, stripe_transfer_id: 'tr_1' });
  });
});

// ── RL: limiter internal error is 503, over-limit is 429 ────────────────────

describe('RL — check_rate_limit FALSE is disambiguated by the counter', () => {
  const now = () => new Date().toISOString();
  const UNAVAILABLE = { error: 'Service temporarily unavailable. Please try again shortly.', code: 'SERVICE_UNAVAILABLE' };
  const TOO_MANY = { error: 'Too many requests. Please try again later.', code: 'RATE_LIMITED' };

  it('RL-1 FALSE from the EXCEPTION branch (counter within the limit) ⇒ 503, Retry-After 30, nothing confirmed', async () => {
    const w = await world({ rateLimit: () => ({ data: false }), rateRow: () => ({ data: { counter: 2, window_start: now() } }) });
    const r = await w.call();
    expect(r.status).toBe(503);
    expect(r.headers.get('Retry-After')).toBe('30');
    expect(r.body).toEqual(UNAVAILABLE);
    expect(w.rpcNames()).toEqual(['check_rate_limit']);
    expect(w.ledger.transfers.get('t1')!.status).toBe('seller_sent');
  });

  it('RL-2 FALSE with no counter row (first call\'s insert rolled back by the EXCEPTION branch) ⇒ 503', async () => {
    const w = await world({ rateLimit: () => ({ data: false }), rateRow: () => ({ data: null }) });
    expect((await w.call()).status).toBe(503);
  });

  it('RL-3 FALSE with a counter over the limit only in an EXPIRED window ⇒ 503 (the RPC would have reset it)', async () => {
    const w = await world({ rateLimit: () => ({ data: false }), rateRow: () => ({ data: { counter: 9, window_start: new Date(Date.now() - 20 * 60_000).toISOString() } }) });
    expect((await w.call()).status).toBe(503);
  });

  it('RL-4 FALSE and the counter read fails ⇒ 503 (unclassifiable limiter state, still fail-closed)', async () => {
    const w = await world({ rateLimit: () => ({ data: false }), rateRow: () => ({ error: { message: 'timeout' } }) });
    const r = await w.call();
    expect(r.status).toBe(503);
    expect(r.body).toEqual(UNAVAILABLE);
  });

  it('RL-5 control: a real over-limit (counter 6 > 5 in the live window) ⇒ 429, Retry-After 300', async () => {
    const w = await world({ rateLimit: () => ({ data: false }), rateRow: () => ({ data: { counter: 6, window_start: now() } }) });
    const r = await w.call();
    expect(r.status).toBe(429);
    expect(r.headers.get('Retry-After')).toBe('300');
    expect(r.body).toEqual(TOO_MANY);
    const read = w.sb.queries.find((q) => q.table === 'rate_limits')!;
    expect(read.filters).toEqual([['eq', 'user_id', 'buyer-1'], ['eq', 'action', 'confirm-and-release']]);
  });

  it('RL-6 the RPC itself errors (transport) ⇒ 503 as before', async () => {
    const w = await world({ rateLimit: () => ({ error: { message: 'FetchError: connect ECONNREFUSED' } }) });
    const r = await w.call();
    expect(r.status).toBe(503);
    expect(r.body).toEqual(UNAVAILABLE);
  });

  it('RL-7 a non-boolean reply (NULL) is a limiter error, not an over-limit ⇒ 503', async () => {
    const w = await world({ rateLimit: () => ({ data: null }) });
    expect((await w.call()).status).toBe(503);
  });
});

// ── every error response has a code ─────────────────────────────────────────

describe('EC — every error response carries `code`; error texts unchanged', () => {
  it('EC-1 no Authorization ⇒ 401 AUTH_REQUIRED', async () => {
    const w = await world();
    const r = await w.call(new Request('https://edge.test/fn', { method: 'POST', body: '{}' }));
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ error: 'Missing or invalid Authorization header', code: 'AUTH_REQUIRED' });
  });

  it('EC-2 missing transfer_id ⇒ 400 TRANSFER_ID_REQUIRED', async () => {
    const w = await world();
    const r = await w.call(authedJsonRequest({}));
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ error: 'Missing transfer_id', code: 'TRANSFER_ID_REQUIRED' });
  });

  it('EC-3 (race only) a dispute frozen between the RPC and the re-read ⇒ 409 ORDER_UNDER_REVIEW', async () => {
    const w = await world({ confirm: (t) => { t.status = 'disputed'; t.disputed_at = 'now'; return { data: null }; } });
    const r = await w.call();
    expect(r.status).toBe(409);
    expect(r.body).toEqual({ error: 'This order is under review. Payout is frozen until the dispute is resolved.', code: 'ORDER_UNDER_REVIEW' });
  });

  it('EC-4 (race only) the claim reports DISPUTED ⇒ 409 ORDER_UNDER_REVIEW', async () => {
    const w = await world();
    w.ledger.failNext.set('claim_payout_attempt', 'DISPUTED');
    const r = await w.call();
    expect(r.status).toBe(409);
    expect(r.body).toEqual({ error: 'This order is under review. Payout is frozen until the dispute is resolved.', code: 'ORDER_UNDER_REVIEW' });
  });

  it('EC-5 (race only) the status moved off buyer_confirmed between the RPC and the re-read ⇒ 400 TRANSFER_STATE_CHANGED', async () => {
    const w = await world({ confirm: (t) => { t.status = 'reversed'; return { data: null }; } });
    const r = await w.call();
    expect(r.status).toBe(400);
    expect(r.body).toEqual({ error: 'Transfer is in unexpected state: reversed', code: 'TRANSFER_STATE_CHANGED' });
  });

  it('EC-6 (unreachable in production: the RPC refuses a non-buyer first) buyer mismatch ⇒ 403 NOT_TRANSFER_BUYER', async () => {
    const w = await world({ confirm: (t) => { t.buyer_id = 'someone-else'; return { data: null }; } });
    const r = await w.call();
    expect(r.status).toBe(403);
    expect(r.body).toEqual({ error: 'Only the buyer can release payout', code: 'NOT_TRANSFER_BUYER' });
  });

  it('EC-7 F-5 deletion-pending wall keeps its existing code (and, open owner decision, still answers after the RPC ran)', async () => {
    const w = await world({ identityExt: { deletion_state: 'DELETION_PENDING', deletion_requested_at: new Date(Date.now() - 60_000).toISOString() } });
    const r = await w.call();
    expect(r.status).toBe(403);
    expect(r.body).toEqual({ error: 'Your account deletion request is pending. Withdraw it in Settings to accept new transfers.', code: 'account_deletion_pending' });
    expect(w.rpcNames()).toEqual(['check_rate_limit', 'confirm_transfer_received']);
  });
});
