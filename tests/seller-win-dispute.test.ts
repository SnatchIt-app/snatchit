/**
 * tests/seller-win-dispute.test.ts — F-DISPUTE-SELLERWIN-1 (A, 2026-09-24).
 *
 * THE DEFECT. `resolve_transfer_dispute` (065) with outcome seller_win sets
 * status 'buyer_confirmed', clears disputed_at, sets dispute_resolution
 * 'resolved_seller_paid' — and leaves buyer_confirmed_at NULL, because the buyer
 * never confirmed. Phase 2b of enforce-transfer-expiry selects 'buyer_confirmed'
 * rows only when buyer_confirmed_at is older than the quiet period, so a NULL
 * never matches: the seller of a won dispute is never paid. The console's
 * payout_release accepts only seller_sent. And the one path that DOES reach the
 * payout protocol — confirm-and-release, which reads the confirm RPC's
 * "cannot be confirmed from current status: buyer_confirmed" error as "already
 * confirmed" — pays immediately, ignoring any risk hold.
 *
 * THE FIX UNDER TEST.
 *   • Phase 2b gains a separate, additive selection (d) for seller-win rows,
 *     keyed on the OPERATOR'S decision (dispute_resolution, dispute_resolved_at),
 *     never on a manufactured confirmation timestamp. The existing a)+b) query is
 *     byte-identical.
 *   • An operator's decision is not the buyer's statement, so a seller-win does
 *     NOT inherit the buyer confirmation's override of risk holds: manual_review
 *     and a pending payout_hold_until block it — in the selection AND in
 *     claim_payout_attempt (the authority every caller uses; mirrored here by
 *     AttemptLedger.claim, tested against the same matrix in pgTAP 215).
 *   • Genuine buyer confirmations are unchanged, including the 15-minute quiet
 *     period and their override of holds.
 *
 * The hold states come from ONE enumeration, tests/fixtures/seller_win_hold_matrix.json,
 * which pgTAP 215 embeds; the last test here fails if the two copies differ.
 *
 * Money is observed at the Stripe seam: "paid" means POST /transfers was made with
 * the expected destination and amount, the attempt reached 'succeeded' and the
 * transfer row recorded the Stripe id.
 */
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { loadPayoutsModule } from './helpers/payouts-vm';
import { AttemptLedger, StripeTransfersMock, type PaymentRow, type TransferRow } from './helpers/payout-protocol';

type MatrixCase = { case: string; review: string | null; hold_offset_min: number | null; expect: string | null };
const MATRIX: { cases: MatrixCase[] } = JSON.parse(readFileSync('tests/fixtures/seller_win_hold_matrix.json', 'utf8'));

const MIN = 60_000;
const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
type Row = Record<string, unknown>;

// ── PostgREST filter emulation, applied to the ledger's rows ─────────────────
// SQL semantics that matter here: a comparison with NULL is never true (only
// `is.null` matches NULL), `or(...)`/`and(...)` nest, and `payments.*` filters
// apply to the joined payment row (payments!inner).
function splitTop(s: string): string[] {
  const out: string[] = []; let depth = 0; let cur = '';
  for (const ch of s) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ',' && depth === 0) { out.push(cur); cur = ''; } else cur += ch;
  }
  if (cur) out.push(cur);
  return out;
}
function evalTerm(row: Row, term: string): boolean {
  const t = term.trim();
  if (t.startsWith('and(') && t.endsWith(')')) return splitTop(t.slice(4, -1)).every((x) => evalTerm(row, x));
  if (t.startsWith('or(') && t.endsWith(')')) return splitTop(t.slice(3, -1)).some((x) => evalTerm(row, x));
  const [col, op, ...rest] = t.split('.');
  const val = rest.join('.');
  const v = row[col];
  if (op === 'is') return val === 'null' ? v === null || v === undefined : String(v) === val;
  if (v === null || v === undefined) return false;
  if (op === 'eq') return String(v) === val;
  if (op === 'lt') return String(v) < val;
  throw new Error(`emulator: unsupported or-term operator ${op}`);
}
function rowMatches(r: Row, q: QueryCall, payments: Map<string, PaymentRow>): boolean {
  return q.filters.every(([op, ...args]) => {
    if (op === 'or') return splitTop(String(args[0])).some((x) => evalTerm(r, x));
    const col = String(args[0]);
    const val = args[1];
    const v = col.startsWith('payments.')
      ? (payments.get(String(r.payment_id)) as unknown as Row | undefined)?.[col.slice('payments.'.length)]
      : r[col];
    if (op === 'in') return (val as unknown[]).map(String).includes(String(v));
    if (op === 'is') return val === null ? v === null || v === undefined : v === val;
    if (v === null || v === undefined) return false;
    if (op === 'eq') return String(v) === String(val);
    if (op === 'lt') return String(v) < String(val);
    throw new Error(`emulator: unsupported filter ${String(op)}`);
  });
}
function applyQuery(rows: Row[], q: QueryCall, payments: Map<string, PaymentRow>): Row[] {
  let out = rows.filter((r) => rowMatches(r, q, payments));
  for (const [c, o] of q.order) {
    const asc = (o as { ascending?: boolean } | undefined)?.ascending !== false;
    out = out.slice().sort((a, b) => {
      const x = String(a[c as string] ?? ''); const y = String(b[c as string] ?? '');
      return asc ? x.localeCompare(y) : y.localeCompare(x);
    });
  }
  if (q.limit !== null && q.limit !== undefined) out = out.slice(0, q.limit);
  return out;
}

// ── fixtures ────────────────────────────────────────────────────────────────
type Extra = { dispute_resolved_at?: string | null; payout_hold_until?: string | null; created_at?: string };
function seedPayment(ledger: AttemptLedger, id: string, live: boolean | null = true) {
  ledger.payments.set(`p_${id}`, { id: `p_${id}`, status: 'succeeded', stripe_livemode: live, stripe_payment_intent_id: `pi_${id}`, amount: 10000, seller_fee: 1000 });
  ledger.profiles.set('seller-1', { stripe_connect_id: 'acct_A' });
}
function baseRow(id: string): TransferRow & Extra {
  return {
    id, payment_id: `p_${id}`, listing_id: `l_${id}`, seller_id: 'seller-1', buyer_id: 'buyer-1',
    status: 'seller_sent', payout_released_at: null, stripe_transfer_id: null, disputed_at: null,
    dispute_resolution: null, buyer_confirmed_at: null, payout_review_status: null,
    dispute_resolved_at: null, payout_hold_until: null, created_at: iso(-3 * 24 * 60 * MIN),
  };
}
/** exactly what 065 leaves behind for an unpaid seller-win */
function seedSellerWin(ledger: AttemptLedger, id: string, o: { resolvedAgoMin: number; review?: string | null; holdOffsetMin?: number | null; live?: boolean | null }) {
  seedPayment(ledger, id, o.live === undefined ? true : o.live);
  const row = baseRow(id);
  Object.assign(row, {
    status: 'buyer_confirmed', dispute_resolution: 'resolved_seller_paid', buyer_confirmed_at: null, disputed_at: null,
    dispute_resolved_at: iso(-o.resolvedAgoMin * MIN), payout_review_status: o.review ?? null,
    payout_hold_until: o.holdOffsetMin === null || o.holdOffsetMin === undefined ? null : iso(o.holdOffsetMin * MIN),
  });
  ledger.transfers.set(id, row);
}
/** exactly what 0550 confirm_transfer_received leaves behind */
function seedGenuineConfirm(ledger: AttemptLedger, id: string, o: { confirmedAgoMin: number; review?: string | null; holdOffsetMin?: number | null }) {
  seedPayment(ledger, id);
  const row = baseRow(id);
  Object.assign(row, {
    status: 'buyer_confirmed', buyer_confirmed_at: iso(-o.confirmedAgoMin * MIN), payout_review_status: o.review ?? null,
    payout_hold_until: o.holdOffsetMin === null || o.holdOffsetMin === undefined ? null : iso(o.holdOffsetMin * MIN),
  });
  ledger.transfers.set(id, row);
}
function seedAutoReleased(ledger: AttemptLedger, id: string) {
  seedPayment(ledger, id);
  const row = baseRow(id);
  row.status = 'auto_released';
  ledger.transfers.set(id, row);
}

// ── the REAL enforce-transfer-expiry handler over the ledger ─────────────────
async function sweepWorld(ledger: AttemptLedger) {
  const stripeMock = new StripeTransfersMock();
  const stripe = mockStripe(async (c: StripeCall) => stripeMock.route(c));
  const payouts = loadPayoutsModule(stripe);
  const transferQueries: QueryCall[] = [];
  const claimsFor: string[] = [];
  const sb = mockSupabase({
    rpc: async (name: string, params: Record<string, unknown>) => {
      if (['enforce_transfer_expiry', 'get_auto_release_candidates', 'get_unsettled_payments'].includes(name)) return { data: [] };
      if (name === 'claim_payout_attempt') claimsFor.push(String(params.p_transfer_id));
      return ledger.rpc(name, params);
    },
    tables: {
      transfers: (q: QueryCall) => {
        if (q.op !== 'select') return { data: [] };
        // Phase 1b (expired) and the reminder queries (pending / seller_sent) are not under test.
        if (q.filters.some(([op, col, v]) => op === 'eq' && col === 'status' && ['expired', 'pending', 'seller_sent'].includes(String(v)))) return { data: [] };
        if (q.filters.some(([op, col]) => op === 'eq' && col === 'payment_id')) return { data: null };
        transferQueries.push(q);
        return { data: applyQuery([...ledger.transfers.values()] as unknown as Row[], q, ledger.payments).map((r) => ({ ...r })) };
      },
      payout_attempts: () => ({ data: [] }),
      payout_policy: () => ({ data: null }),
      payments: () => ({ data: [] }),
      listings: () => ({ data: { event_name: 'Fixture' } }),
      payout_decisions: () => ({ data: null }),
      webhook_retries: () => ({ data: [] }),
    },
  });
  const edge = await loadEdgeHandler('supabase/functions/enforce-transfer-expiry/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'srv', INTERNAL_CRON_SECRET: 'cron-secret' },
    fetch: (async () => new Response('{}', { status: 200 })) as unknown as typeof fetch,
    provide: {
      executePayoutAttempt: payouts.executePayoutAttempt, stripeFetch: stripe.stripeFetch,
      isCrossModeStripeError: () => false, rowIsLiveActionable: (v: unknown) => v === true, allowTestModeMoney: () => false,
      classifyPayout: () => ({ action: 'hold', tier: 'low', reasons: [], hold_until: null }), DEFAULT_POLICY: {},
      PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
    },
  });
  const run = async () => {
    const res = await edge.handler(new Request('https://edge.test/enforce', { method: 'POST', headers: { authorization: 'Bearer cron-secret' } }));
    expect(res.status).toBe(200);
  };
  const posts = () => stripe.calls.filter((c) => c.method === 'POST' && c.path === '/transfers');
  const postedFor = (transferId: string) => posts().filter((c) => (c.idempotencyKey ?? '').startsWith(`payout_${transferId}_a`));
  const claimed = (transferId: string) => claimsFor.filter((t) => t === transferId).length;
  return { run, posts, postedFor, transferQueries, stripeMock, claimed };
}

function paidOnce(w: Awaited<ReturnType<typeof sweepWorld>>, ledger: AttemptLedger, id: string) {
  const p = w.postedFor(id);
  expect(p, `exactly one Stripe transfer POST for ${id}`).toHaveLength(1);
  const body = p[0].body as Record<string, string>;
  expect(body.destination).toBe('acct_A');
  expect(Number(body.amount)).toBe(9000);                         // amount − seller_fee
  const att = ledger.attempts.filter((a) => a.transfer_id === id);
  expect(att.map((a) => a.state)).toEqual(['succeeded']);
  expect(ledger.transfers.get(id)!.stripe_transfer_id).toMatch(/^tr_/);
}
function notPaid(w: Awaited<ReturnType<typeof sweepWorld>>, ledger: AttemptLedger, id: string) {
  expect(w.postedFor(id), `no Stripe transfer POST for ${id}`).toHaveLength(0);
  expect(ledger.attempts.filter((a) => a.transfer_id === id), `no attempt row for ${id}`).toHaveLength(0);
  expect(ledger.transfers.get(id)!.stripe_transfer_id).toBeNull();
}

// ── P1 / P2: a legitimate seller-win is selected and paid, with no manufactured timestamp ──
describe('seller-win payout eligibility (payout correctness)', () => {
  it('SW-P1: a seller-win resolved an hour ago is paid once, end to end at the Stripe seam', async () => {
    const ledger = new AttemptLedger();
    seedSellerWin(ledger, 'sw1', { resolvedAgoMin: 60 });
    const w = await sweepWorld(ledger);
    await w.run();
    paidOnce(w, ledger, 'sw1');
    expect(ledger.transfers.get('sw1')!.buyer_confirmed_at).toBeNull();      // P2: never manufactured
    await w.run();                                                           // P5: a second sweep is a no-op
    expect(w.postedFor('sw1')).toHaveLength(1);
    expect(w.claimed('sw1'), 'P5: a paid seller-win is not even re-selected (one claim across two sweeps)').toBe(1);
  });

  it('SW-QUIET: a seller-win resolved one minute ago is not swept yet (quiet period on the resolution time)', async () => {
    const ledger = new AttemptLedger();
    seedSellerWin(ledger, 'sw-fresh', { resolvedAgoMin: 1 });
    const w = await sweepWorld(ledger);
    await w.run();
    notPaid(w, ledger, 'sw-fresh');
  });

  it('SW-TESTMODE (P8): a seller-win on a test-mode payment is never paid', async () => {
    const ledger = new AttemptLedger();
    seedSellerWin(ledger, 'sw-test', { resolvedAgoMin: 60, live: false });
    const w = await sweepWorld(ledger);
    await w.run();
    notPaid(w, ledger, 'sw-test');
  });

  for (const c of MATRIX.cases) {
    it(`SW-HOLD[${c.case}] (P7): the sweep ${c.expect ? 'does NOT pay' : 'pays'} a seller-win with review=${c.review} hold=${c.hold_offset_min}`, async () => {
      const ledger = new AttemptLedger();
      seedSellerWin(ledger, `sw-${c.case}`, { resolvedAgoMin: 60, review: c.review, holdOffsetMin: c.hold_offset_min });
      const w = await sweepWorld(ledger);
      await w.run();
      if (c.expect) {
        notPaid(w, ledger, `sw-${c.case}`);
        expect(w.claimed(`sw-${c.case}`), 'skipped before any claim: manual_review by the query filter, the hold cases by the Phase 2b loop').toBe(0);
      } else paidOnce(w, ledger, `sw-${c.case}`);
    });
  }
});

describe('seller-win selection boundaries', () => {
  it('LEGACY-B3: a seller-win paid by hand through the old runbook (DAY5 B3: status buyer_confirmed, payout recorded, disputed_at kept, no resolution) is never re-selected', async () => {
    const ledger = new AttemptLedger();
    seedPayment(ledger, 'legacy');
    const row = baseRow('legacy');
    Object.assign(row, { status: 'buyer_confirmed', buyer_confirmed_at: null, dispute_resolution: null, dispute_resolved_at: null,
      disputed_at: iso(-3 * 24 * 60 * MIN), payout_released_at: iso(-2 * 24 * 60 * MIN), stripe_transfer_id: 'tr_manual' });
    ledger.transfers.set('legacy', row);
    const w = await sweepWorld(ledger);
    await w.run();
    expect(w.claimed('legacy')).toBe(0);
    expect(w.postedFor('legacy')).toHaveLength(0);
  });

  it('REFUNDED: a seller-win whose payment was refunded is not selected at all (it can never be paid)', async () => {
    const ledger = new AttemptLedger();
    seedSellerWin(ledger, 'sw-refunded', { resolvedAgoMin: 60 });
    ledger.payments.get('p_sw-refunded')!.status = 'refunded';
    const w = await sweepWorld(ledger);
    await w.run();
    notPaid(w, ledger, 'sw-refunded');
    expect(w.claimed('sw-refunded')).toBe(0);
  });

  it('FAIRNESS: 25 seller-wins parked in manual_review, resolved earlier, do not starve an eligible seller-win', async () => {
    const ledger = new AttemptLedger();
    for (let i = 0; i < 25; i++) seedSellerWin(ledger, `mr-${String(i).padStart(2, '0')}`, { resolvedAgoMin: 600 - i, review: 'manual_review' });
    seedSellerWin(ledger, 'sw-late', { resolvedAgoMin: 60 });
    const w = await sweepWorld(ledger);
    await w.run();
    paidOnce(w, ledger, 'sw-late');
    for (let i = 0; i < 25; i++) expect(w.claimed(`mr-${String(i).padStart(2, '0')}`)).toBe(0);
  });
});

// ── the claim authority's mirror, over the same matrix ───────────────────────
describe('claim_payout_attempt rule for seller-win (JS mirror of the SQL authority; pgTAP 215 tests the SQL)', () => {
  for (const c of MATRIX.cases) {
    it(`CLAIM[${c.case}]: ${c.expect ?? 'admitted'}`, () => {
      const ledger = new AttemptLedger();
      seedSellerWin(ledger, 't1', { resolvedAgoMin: 60, review: c.review, holdOffsetMin: c.hold_offset_min });
      if (c.expect) expect(() => ledger.claim('t1', 'test')).toThrow(c.expect);
      else expect(ledger.claim('t1', 'test').attempt_no).toBe(1);
    });
  }

  it('CLAIM-BYPASS: the losing buyer\'s confirm-and-release path (executePayoutAttempt) no longer pays a held seller-win', async () => {
    const ledger = new AttemptLedger();
    seedSellerWin(ledger, 't1', { resolvedAgoMin: 60, review: 'held', holdOffsetMin: 4320 });
    const stripeMock = new StripeTransfersMock();
    const stripe = mockStripe(async (c: StripeCall) => stripeMock.route(c));
    const payouts = loadPayoutsModule(stripe);
    const db = { rpc: (name: string, params: Record<string, unknown>) => ledger.rpc(name, params) };
    const out = await payouts.executePayoutAttempt(db, { transferId: 't1', paymentId: 'p_t1', sellerId: 'seller-1', actor: 'edge:confirm-and-release' });
    expect(out).toMatchObject({ kind: 'not_eligible', reason: 'PAYOUT_HELD' });
    expect(stripe.calls.filter((c) => c.method === 'POST')).toHaveLength(0);
  });

  it('GENUINE-OVERRIDE (P6): a genuine buyer confirmation still overrides a pending hold and manual_review (unchanged)', () => {
    for (const review of ['held', 'manual_review']) {
      const ledger = new AttemptLedger();
      seedGenuineConfirm(ledger, 't1', { confirmedAgoMin: 60, review, holdOffsetMin: review === 'held' ? 4320 : null });
      expect(ledger.claim('t1', 'test').attempt_no).toBe(1);
    }
  });
});

// ── the two selections together (D's points 1–3) ─────────────────────────────
describe('Phase 2b selections combined', () => {
  it('COMBINED: auto_released, a stale genuine confirmation and an eligible seller-win are each paid exactly once; a fresh genuine confirmation and a held seller-win are not', async () => {
    const ledger = new AttemptLedger();
    seedAutoReleased(ledger, 'auto');
    seedGenuineConfirm(ledger, 'gc-stale', { confirmedAgoMin: 60 });
    seedGenuineConfirm(ledger, 'gc-fresh', { confirmedAgoMin: 1 });
    seedSellerWin(ledger, 'sw-ok', { resolvedAgoMin: 60 });
    seedSellerWin(ledger, 'sw-held', { resolvedAgoMin: 60, review: 'held', holdOffsetMin: 4320 });
    const w = await sweepWorld(ledger);
    await w.run();
    for (const id of ['auto', 'gc-stale', 'sw-ok']) paidOnce(w, ledger, id);
    for (const id of ['gc-fresh', 'sw-held']) notPaid(w, ledger, id);
    expect(w.posts()).toHaveLength(3);
  });

  it('NO-OVERLAP: a seller-win row matches exactly one Phase 2b selection, and a genuine confirmation exactly the other', async () => {
    const ledger = new AttemptLedger();
    seedSellerWin(ledger, 'sw', { resolvedAgoMin: 60 });
    seedGenuineConfirm(ledger, 'gc', { confirmedAgoMin: 60 });
    seedAutoReleased(ledger, 'auto');
    // evaluate the selections against the rows AS THEY WERE when selected: after the
    // sweep pays them they (correctly) leave every selection
    const before = new Map([...ledger.transfers].map(([k, v]) => [k, { ...v } as unknown as Row]));
    const w = await sweepWorld(ledger);
    await w.run();
    // the payout selections are the transfer queries that exclude already-paid rows
    // identified by WHAT they select (the payout columns joined to payments), not by any guard under test
    const selections = w.transferQueries.filter((q) => String(q.select ?? '').includes('payments!inner(status)'));
    expect(selections.length, 'Phase 2b issues two payout selections').toBe(2);
    const hits = (id: string) => selections.filter((q) => rowMatches(before.get(id)!, q, ledger.payments)).length;
    expect(hits('sw')).toBe(1);
    expect(hits('gc')).toBe(1);
    expect(hits('auto')).toBe(1);
    const [ab, sw] = selections;
    expect(rowMatches(before.get('sw')!, ab, ledger.payments), 'the a)+b) query never selects a seller-win').toBe(false);
    expect(rowMatches(before.get('gc')!, sw, ledger.payments), 'the seller-win query never selects a genuine confirmation').toBe(false);
    expect(rowMatches(before.get('sw')!, sw, ledger.payments), 'the seller-win query does select the seller-win').toBe(true);
  });

  it('UNRESOLVED (P3/P4): an open dispute, a buyer-win and a partial-refund outcome are never selected', async () => {
    const ledger = new AttemptLedger();
    for (const [id, resolution] of [['open', null], ['bwin', 'resolved_buyer_refunded'], ['partial', 'resolved_partial_refund']] as const) {
      seedPayment(ledger, id);
      const row = baseRow(id);
      Object.assign(row, { status: 'disputed', disputed_at: iso(-120 * MIN), dispute_resolution: resolution,
        dispute_resolved_at: resolution ? iso(-60 * MIN) : null });
      ledger.transfers.set(id, row);
    }
    const w = await sweepWorld(ledger);
    await w.run();
    for (const id of ['open', 'bwin', 'partial']) notPaid(w, ledger, id);
  });
});

// ── the shared matrix is the one pgTAP 215 uses ───────────────────────────────
describe('one hold matrix for both suites', () => {
  it('MATRIX-PIN: the copy embedded in pgTAP 215 equals tests/fixtures/seller_win_hold_matrix.json', () => {
    const sql = readFileSync('supabase/tests/215_seller_win_dispute_payout_and_notice.sql', 'utf8');
    const m = sql.match(/-- MATRIX-BEGIN\n([\s\S]*?)-- MATRIX-END/);
    expect(m, 'pgTAP 215 carries a MATRIX-BEGIN/MATRIX-END block').not.toBeNull();
    const rows = [...m![1].matchAll(/\('([a-z_]+)',\s*(NULL|'[a-z_]+'),\s*(NULL|-?\d+),\s*(NULL|'[A-Z_]+')\)/g)].map((r) => ({
      case: r[1],
      review: r[2] === 'NULL' ? null : r[2].slice(1, -1),
      hold_offset_min: r[3] === 'NULL' ? null : Number(r[3]),
      expect: r[4] === 'NULL' ? null : r[4].slice(1, -1),
    }));
    expect(rows).toEqual(MATRIX.cases);
  });
});
