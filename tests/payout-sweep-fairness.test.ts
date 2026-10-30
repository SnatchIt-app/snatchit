/**
 * tests/payout-sweep-fairness.test.ts — Phase 2b of enforce-transfer-expiry must not let
 * PERMANENTLY BLOCKED rows starve payable ones.
 *
 * THE DEFECT (independent review, owner item 1, 2026-09-19). Phase 2b (a)+(b) selects the
 * 20 OLDEST `auto_released` / `buyer_confirmed` transfers with no `stripe_transfer_id`,
 * and only then does the payout protocol reject the ones whose payment is not
 * `succeeded`. A refunded payment can never be paid (`claim_payout_attempt` refuses with
 * PAYMENT_NOT_SUCCEEDED, so no attempt row is even opened — these rows never leave the
 * set). Once 20 or more such rows exist, every sweep spends its whole batch on them and
 * no newer, payable transfer is ever retried: the seller's money stops moving, silently,
 * for as long as the blocked rows exist. Production reached this shape through
 * F-PAYOUT-PARTIAL-1 (a partial refund marks the payment `refunded` while the transfer is
 * released), so the blocked set only grows.
 *
 * WHAT THIS TEST PINS
 *   1. one sweep with 25 blocked rows OLDER than 3 payable ones attempts all 3 payable;
 *   2. repeated sweeps keep attempting payable work (no progress loss, no duplicate pay);
 *   3. recovery: a payable row that appears later is attempted on the next sweep;
 *   4. the blocked rows are never *paid* — the protocol still refuses them — and the
 *      per-row eligibility guard is untouched (defence in depth stays).
 *
 * It drives the REAL handler through the edge VM. `executePayoutAttempt` is provided, so
 * "attempted" means the row actually reached the payout protocol. The fixture applies the
 * query's own filters (including any embedded `payments.status` filter), so the test
 * measures selection, not a hand-written expectation of it.
 *
 * NEGATIVE CONTROL: with the fix reverted (the payments filter removed from the query),
 * cases 1-3 fail — the blocked rows take the whole batch.
 */
import { describe, expect, it } from 'vitest';
import { loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { isCrossModeStripeError, rowIsLiveActionable, allowTestModeMoney, classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry } from '../supabase/functions/_shared/payout-logic';
import { classifyPayout, DEFAULT_POLICY } from '../supabase/functions/_shared/payout-policy';

const CRON = 'cron-secret-test-0123456789';

interface TransferRow {
  id: string;
  payment_id: string;
  listing_id: string;
  seller_id: string;
  buyer_id: string;
  status: string;
  buyer_confirmed_at: string | null;
  stripe_transfer_id: string | null;
  payout_released_at: string | null;
  disputed_at: string | null;
  created_at: string;
}
interface PaymentRow { id: string; status: string; stripe_livemode: boolean }

/** The subset of PostgREST filtering Phase 2b uses, applied to the fixture. */
function applyFilters(rows: TransferRow[], q: QueryCall, payments: Map<string, PaymentRow>): TransferRow[] {
  let out = rows.slice();
  for (const [op, ...args] of q.filters) {
    const col = args[0] as string;
    if (op === 'in') {
      const set = new Set(args[1] as string[]);
      out = out.filter((r) => set.has(String((r as unknown as Record<string, unknown>)[col])));
    } else if (op === 'is') {
      out = out.filter((r) => (r as unknown as Record<string, unknown>)[col] === null);
    } else if (op === 'eq') {
      // embedded filter on the joined payments row, e.g. eq('payments.status','succeeded')
      if (col.startsWith('payments.')) {
        const f = col.slice('payments.'.length) as keyof PaymentRow;
        out = out.filter((r) => String(payments.get(r.payment_id)?.[f]) === String(args[1]));
      } else {
        out = out.filter((r) => String((r as unknown as Record<string, unknown>)[col]) === String(args[1]));
      }
    } else if (op === 'lt') {
      out = out.filter((r) => {
        const v = (r as unknown as Record<string, unknown>)[col];
        return v !== null && v !== undefined && String(v) < String(args[1]);
      });
    } else if (op === 'or') {
      // `status.eq.auto_released,and(status.eq.buyer_confirmed,buyer_confirmed_at.lt.<iso>)`
      const expr = String(args[0]);
      const staleMatch = expr.match(/buyer_confirmed_at\.lt\.([^),]+)/);
      const stale = staleMatch ? staleMatch[1] : null;
      out = out.filter((r) =>
        (expr.includes('status.eq.auto_released') && r.status === 'auto_released') ||
        (expr.includes('status.eq.buyer_confirmed') && r.status === 'buyer_confirmed' &&
          r.buyer_confirmed_at !== null && (stale === null || r.buyer_confirmed_at < stale)),
      );
    }
  }
  for (const [c, o] of q.order) {
    const asc = (o as { ascending?: boolean } | undefined)?.ascending !== false;
    out.sort((a, b) => {
      const x = String((a as unknown as Record<string, unknown>)[c] ?? '');
      const y = String((b as unknown as Record<string, unknown>)[c] ?? '');
      return asc ? x.localeCompare(y) : y.localeCompare(x);
    });
  }
  if (q.limit !== null && q.limit !== undefined) out = out.slice(0, q.limit);
  return out;
}

function world(transfers: TransferRow[], payments: Map<string, PaymentRow>) {
  const attempted: string[] = [];
  const paid: string[] = [];
  const sb = mockSupabase({
    rpc: () => ({ data: [] }),               // no expiries, no auto-release candidates
    tables: {
      transfers: (q) => {
        if (q.op !== 'select') return { data: [] };
        // Phase 1b selects expired transfers; Phase 2b selects released ones.
        if (q.filters.some(([op, col]) => op === 'eq' && col === 'status')) return { data: [] };
        return { data: applyFilters(transfers, q, payments) };
      },
      payout_attempts: () => ({ data: [] }),
      payments: () => ({ data: [] }),
      listings: () => ({ data: [{ event_name: 'Test Event' }] }),
      payout_decisions: () => ({ data: [] }),
      transfer_notifications: () => ({ data: [] }),
    },
  });
  const stripe = mockStripe((_c: StripeCall) => ({ ok: false, status: 404, data: { error: { message: 'unmocked' } } }));
  return { sb, stripe, attempted, paid };
}

async function sweep(transfers: TransferRow[], payments: Map<string, PaymentRow>) {
  const { sb, stripe, attempted, paid } = world(transfers, payments);
  const edge = await loadEdgeHandler('supabase/functions/enforce-transfer-expiry/index.ts', {
    supabase: sb,
    env: { STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'srv', INTERNAL_CRON_SECRET: CRON },
    fetch: (async () => new Response('{}', { status: 200 })) as unknown as typeof fetch,
    provide: {
      stripeFetch: stripe.stripeFetch,
      classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry,
      createSellerPayout: async () => ({ ok: false, reason: 'not under test' }),
      isCrossModeStripeError, rowIsLiveActionable, allowTestModeMoney,
      classifyPayout, DEFAULT_POLICY, PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
      // "attempted" = the row reached the payout protocol. The protocol's own eligibility
      // refusal is reproduced exactly: a payment that is not `succeeded` is not eligible,
      // and opens no attempt row (claim_payout_attempt refuses PAYMENT_NOT_SUCCEEDED).
      executePayoutAttempt: async (_db: unknown, args: { transferId: string; paymentId: string }) => {
        attempted.push(args.transferId);
        const p = payments.get(args.paymentId);
        if (!p || p.status !== 'succeeded') return { kind: 'not_eligible', reason: 'PAYMENT_NOT_SUCCEEDED' };
        paid.push(args.transferId);
        return {
          kind: 'succeeded', attemptId: `att_${args.transferId}`, attemptNo: 1,
          stripeTransferId: `tr_${args.transferId}`, destination: 'acct_1', sellerNetCents: 1000,
        };
      },
    },
  });
  const res = await edge.handler(new Request('https://edge.test/enforce-transfer-expiry', {
    method: 'POST', headers: { Authorization: `Bearer ${CRON}` },
  }));
  expect(res.status).toBe(200);
  return { attempted, paid };
}

/** n blocked rows (payment refunded — can never be paid), oldest first. */
function fixture(nBlocked: number, nPayable: number) {
  const transfers: TransferRow[] = [];
  const payments = new Map<string, PaymentRow>();
  const base = Date.parse('2026-09-01T00:00:00Z');
  for (let i = 0; i < nBlocked; i++) {
    const id = `blocked-${String(i).padStart(2, '0')}`;
    transfers.push({
      id, payment_id: `pay-${id}`, listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'auto_released', buyer_confirmed_at: null, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null,
      created_at: new Date(base + i * 60_000).toISOString(),
    });
    payments.set(`pay-${id}`, { id: `pay-${id}`, status: 'refunded', stripe_livemode: true });
  }
  const payableBase = base + 365 * 24 * 3600_000; // strictly newer than every blocked row
  for (let i = 0; i < nPayable; i++) {
    const id = `payable-${String(i).padStart(2, '0')}`;
    transfers.push({
      id, payment_id: `pay-${id}`, listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'auto_released', buyer_confirmed_at: null, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null,
      created_at: new Date(payableBase + i * 60_000).toISOString(),
    });
    payments.set(`pay-${id}`, { id: `pay-${id}`, status: 'succeeded', stripe_livemode: true });
  }
  return { transfers, payments };
}

describe('Phase 2b never lets blocked rows starve payable payouts', () => {
  it('F1: 25 blocked rows older than 3 payable ones — one sweep attempts and pays all 3', async () => {
    const { transfers, payments } = fixture(25, 3);
    const { attempted, paid } = await sweep(transfers, payments);
    expect(paid.sort()).toEqual(['payable-00', 'payable-01', 'payable-02']);
    expect(attempted.filter((id) => id.startsWith('payable-')).length).toBe(3);
  });

  it('F2: blocked rows are never paid, and the eligibility refusal still applies', async () => {
    const { transfers, payments } = fixture(25, 3);
    const { paid } = await sweep(transfers, payments);
    expect(paid.some((id) => id.startsWith('blocked-'))).toBe(false);
  });

  it('F3: repeated sweeps keep paying — no progress loss, and paid rows leave the set', async () => {
    const { transfers, payments } = fixture(25, 3);
    const first = await sweep(transfers, payments);
    expect(first.paid.length).toBe(3);
    // the paid rows now carry a stripe_transfer_id, exactly as the protocol records them
    for (const id of first.paid) {
      const row = transfers.find((t) => t.id === id)!;
      row.stripe_transfer_id = `tr_${id}`;
      row.payout_released_at = new Date().toISOString();
    }
    const second = await sweep(transfers, payments);
    expect(second.paid).toEqual([]);                       // nothing payable is left
    expect(second.attempted.some((id) => id.startsWith('payable-'))).toBe(false);
  });

  it('F4: recovery — a payable row appearing after the blocked backlog is picked up next sweep', async () => {
    const { transfers, payments } = fixture(40, 0);
    const first = await sweep(transfers, payments);
    expect(first.paid).toEqual([]);
    transfers.push({
      id: 'payable-late', payment_id: 'pay-payable-late', listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'auto_released', buyer_confirmed_at: null, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null, created_at: new Date().toISOString(),
    });
    payments.set('pay-payable-late', { id: 'pay-payable-late', status: 'succeeded', stripe_livemode: true });
    const second = await sweep(transfers, payments);
    expect(second.paid).toEqual(['payable-late']);
  });

  it('F5: a buyer_confirmed row inside its 15-minute quiet period is still not swept', async () => {
    const { transfers, payments } = fixture(0, 0);
    const fresh = new Date(Date.now() - 60_000).toISOString();      // confirmed a minute ago
    transfers.push({
      id: 'fresh-confirm', payment_id: 'pay-fresh', listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'buyer_confirmed', buyer_confirmed_at: fresh, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null, created_at: fresh,
    });
    payments.set('pay-fresh', { id: 'pay-fresh', status: 'succeeded', stripe_livemode: true });
    const { attempted } = await sweep(transfers, payments);
    expect(attempted).not.toContain('fresh-confirm');
  });

  it('F6: a buyer_confirmed row past the quiet period IS swept, and blocked rows do not crowd it out', async () => {
    const { transfers, payments } = fixture(25, 0);
    const old = new Date(Date.now() - 60 * 60_000).toISOString();   // confirmed an hour ago
    transfers.push({
      id: 'stale-confirm', payment_id: 'pay-stale', listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'buyer_confirmed', buyer_confirmed_at: old, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null, created_at: old,
    });
    payments.set('pay-stale', { id: 'pay-stale', status: 'succeeded', stripe_livemode: true });
    const { paid } = await sweep(transfers, payments);
    expect(paid).toEqual(['stale-confirm']);
  });
});
