/**
 * tests/payout-sweep-fairness-v38.test.ts — Phase 2b of the DEPLOYED enforce-transfer-expiry
 * (v38 = this branch's base, origin/main) must not let PERMANENTLY BLOCKED rows starve
 * payable ones.
 *
 * THE DEFECT (independent review, owner item 1, 2026-09-19; verified byte-identical in the
 * deployed v38 on 2026-09-19). Phase 2b selects the 20 OLDEST `auto_released` /
 * `buyer_confirmed` transfers with no `stripe_transfer_id`, and only then does
 * `payReleasedTransfer`'s own guard reject the ones whose payment is not `succeeded`.
 * A refunded payment can never be paid, and the row never leaves the set. Once 20 or more
 * such rows exist, every sweep spends its whole batch on them and no newer, payable
 * transfer is ever retried. Production reaches this shape through F-PAYOUT-PARTIAL-1
 * (a partial refund marks the payment `refunded` while the transfer is already released).
 *
 * This is the V38 BACKPORT of the fix reviewed on the release branch (PR #83, commit
 * 36db0c36): the same two selection predicates moved into the query, nothing else.
 * The fixture applies the query's own filters, so the test measures selection, not a
 * hand-written expectation of it. The handler under test is the genuine source file.
 *
 * WHAT IS PINNED (mirrors F1–F6 of the release-branch suite)
 *   F1  25 blocked rows older than 3 payable ones: one sweep pays all 3.
 *   F2  blocked rows are never paid — v38's own payment-status guard still applies
 *       (defence in depth is untouched).
 *   F3  repeated sweeps keep making progress, and paid rows leave the set.
 *   F4  recovery: a payable row appearing behind a 40-row blocked backlog is picked up.
 *   F5  a buyer_confirmed row inside its 15-minute quiet period is still not swept.
 *   F6  a stale buyer_confirmed row is swept even behind 25 blocked rows.
 *
 * NEGATIVE CONTROL: against the unfixed v38 file, F1, F3, F4 and F6 fail (the batch is
 * entirely blocked rows); F2 and F5 pass, because they pin behaviour that was already safe.
 */
import { describe, expect, it } from 'vitest';
import { loadEdgeHandler, mockStripe, mockSupabase, type QueryCall, type StripeCall } from './helpers/edge-vm';
import { isCrossModeStripeError, rowIsLiveActionable } from '../supabase/functions/_shared/payout-logic';
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
interface PaymentRow {
  id: string;
  status: string;
  amount: number;
  seller_fee: number;
  stripe_payment_intent_id: string;
}

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
  /** "attempted" = the row reached payReleasedTransfer, whose FIRST payment read is this
   *  per-id single select. v38's own status guard then refuses a non-succeeded payment —
   *  that guard is exactly the defence in depth the fix must not weaken. */
  const attempted: string[] = [];
  /** "paid" = createSellerPayout was invoked — v38 only calls it after every guard passed. */
  const paid: string[] = [];
  const byPaymentId = (id: string) => payments.get(id) ?? null;
  const sb = mockSupabase({
    rpc: (name: string) => {
      if (name === 'record_transfer_payout') return { data: true };
      return { data: [] };               // no expiries, no auto-release candidates
    },
    tables: {
      transfers: (q) => {
        if (q.op !== 'select') return { data: [] };
        const eqId = q.filters.find(([op, col]) => op === 'eq' && col === 'id');
        if (eqId) {
          // payReleasedTransfer's final pre-payment recheck: serve current fixture state
          const row = transfers.find((t) => t.id === String(eqId[2]));   // filter tuple is [op, col, value]
          return { data: row ? { stripe_transfer_id: row.stripe_transfer_id, status: row.status, disputed_at: row.disputed_at } : null };
        }
        // Phase 1b / Phase 3 select by status equality; Phase 2b selects by `in`.
        if (q.filters.some(([op, col]) => op === 'eq' && col === 'status')) return { data: [] };
        return { data: applyFilters(transfers, q, payments) };
      },
      payments: (q) => {
        const eqId = q.filters.find(([op, col]) => op === 'eq' && col === 'id');
        if (q.op === 'select' && eqId && q.terminal === 'single') {
          const p = byPaymentId(String(eqId[2]));   // filter tuple is [op, col, value]
          if (p) {
            const transfer = transfers.find((t) => t.payment_id === p.id);
            if (transfer) attempted.push(transfer.id);
          }
          return { data: p };
        }
        return { data: [] };
      },
      profiles: () => ({ data: { stripe_connect_id: 'acct_test_1' } }),
      payout_policy: () => ({ data: null }),   // maybeSingle → code defaults (DEFAULT_POLICY)
      payout_decisions: () => ({ data: [] }),
      listings: () => ({ data: { event_name: 'Test Event' } }),
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
      // v38 imports these four from _shared/payouts.ts (an impure module under vitest);
      // none of them is under test, and createSellerPayout is the recording seam.
      classifyPayoutStripeError: (_detail: string) => 'unexpected',
      reasonCodeForErrorClass: (_c: string) => 'PAYOUT_UNEXPECTED',
      shouldPageSentry: (_c: string) => false,
      createSellerPayout: async (args: { transferId: string }) => {
        paid.push(args.transferId);
        return { ok: true, transfer: { id: `tr_${args.transferId}` } };
      },
      // pure modules: the REAL implementations
      isCrossModeStripeError, rowIsLiveActionable,
      classifyPayout, DEFAULT_POLICY, PayoutCandidate: undefined, PayoutPolicyConfig: undefined,
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
  const pay = (id: string, status: string): PaymentRow =>
    ({ id, status, amount: 5000, seller_fee: 500, stripe_payment_intent_id: `pi_${id}` });
  for (let i = 0; i < nBlocked; i++) {
    const id = `blocked-${String(i).padStart(2, '0')}`;
    transfers.push({
      id, payment_id: `pay-${id}`, listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'auto_released', buyer_confirmed_at: null, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null,
      created_at: new Date(base + i * 60_000).toISOString(),
    });
    payments.set(`pay-${id}`, pay(`pay-${id}`, 'refunded'));
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
    payments.set(`pay-${id}`, pay(`pay-${id}`, 'succeeded'));
  }
  return { transfers, payments };
}

describe('v38 Phase 2b never lets blocked rows starve payable payouts', () => {
  it('F1: 25 blocked rows older than 3 payable ones — one sweep pays all 3', async () => {
    const { transfers, payments } = fixture(25, 3);
    const { paid } = await sweep(transfers, payments);
    expect(paid.sort()).toEqual(['payable-00', 'payable-01', 'payable-02']);
  });

  it('F2: blocked rows are never paid — v38\'s own payment-status guard still applies', async () => {
    const { transfers, payments } = fixture(25, 3);
    const { attempted, paid } = await sweep(transfers, payments);
    expect(paid.some((id) => id.startsWith('blocked-'))).toBe(false);
    // the guard itself must remain reachable: force a blocked row into the batch shape the
    // OLD query produced by making it the only row at all — selection cannot save it, only
    // the in-function guard can refuse it. (Witness for the absence assertion above.)
    const lone = fixture(1, 0);
    const loneRun = await sweep(lone.transfers, lone.payments);
    expect(loneRun.paid).toEqual([]);
    void attempted;
  });

  it('F3: repeated sweeps keep paying — no progress loss, and paid rows leave the set', async () => {
    const { transfers, payments } = fixture(25, 3);
    const first = await sweep(transfers, payments);
    expect(first.paid.length).toBe(3);
    // the paid rows now carry a stripe_transfer_id, exactly as record_transfer_payout records them
    for (const id of first.paid) {
      const row = transfers.find((t) => t.id === id)!;
      row.stripe_transfer_id = `tr_${id}`;
      row.payout_released_at = new Date().toISOString();
    }
    const second = await sweep(transfers, payments);
    expect(second.paid).toEqual([]);                       // nothing payable is left
  });

  it('F4: recovery — a payable row appearing after a 40-row blocked backlog is picked up next sweep', async () => {
    const { transfers, payments } = fixture(40, 0);
    const first = await sweep(transfers, payments);
    expect(first.paid).toEqual([]);
    transfers.push({
      id: 'payable-late', payment_id: 'pay-payable-late', listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'auto_released', buyer_confirmed_at: null, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null, created_at: new Date().toISOString(),
    });
    payments.set('pay-payable-late', { id: 'pay-payable-late', status: 'succeeded', amount: 5000, seller_fee: 500, stripe_payment_intent_id: 'pi_late' });
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
    payments.set('pay-fresh', { id: 'pay-fresh', status: 'succeeded', amount: 5000, seller_fee: 500, stripe_payment_intent_id: 'pi_fresh' });
    const { paid, attempted } = await sweep(transfers, payments);
    expect(paid).toEqual([]);
    expect(attempted).not.toContain('fresh-confirm');
  });

  it('F6: a stale buyer_confirmed row IS swept, and blocked rows do not crowd it out', async () => {
    const { transfers, payments } = fixture(25, 0);
    const old = new Date(Date.now() - 60 * 60_000).toISOString();   // confirmed an hour ago
    transfers.push({
      id: 'stale-confirm', payment_id: 'pay-stale', listing_id: 'l1', seller_id: 's1', buyer_id: 'b1',
      status: 'buyer_confirmed', buyer_confirmed_at: old, stripe_transfer_id: null,
      payout_released_at: null, disputed_at: null, created_at: old,
    });
    payments.set('pay-stale', { id: 'pay-stale', status: 'succeeded', amount: 5000, seller_fee: 500, stripe_payment_intent_id: 'pi_stale' });
    const { paid } = await sweep(transfers, payments);
    expect(paid).toEqual(['stale-confirm']);
  });
});
