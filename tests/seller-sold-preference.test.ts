/**
 * tests/seller-sold-preference.test.ts — notification batch 1 (owner ruling
 * 2026-09-17): the settlement webhook honours the seller's EXISTING
 * "Listing sold" toggle before the A9 seller push.
 *
 * WHY. `public.notification_preferences.notify_listing_sold` has shipped since
 * the baseline schema (000, `not null default true`) and the app has always
 * offered the switch — but nothing ever read it, so a seller who turned it off
 * still got "Your ticket sold!". This closes that gap and nothing else.
 *
 * PINNED HERE:
 *   * the BUYER's "Payment Confirmed!" is mandatory and ungated — it is never
 *     read from preferences and never suppressed;
 *   * the preference is read for the SELLER's user id, never the buyer's;
 *   * an ABSENT row means true (the column's own default; rows are auto-created
 *     on profile insert, so absence means "older account", not "opted out");
 *   * a FAILED read also means true, deliberately: this push tells the seller
 *     to send the transfer, so losing it stalls a paid sale. A preference is a
 *     convenience; the transfer prompt is money. Fail toward delivering, and log.
 *   * nothing is read at all unless the sale actually settled.
 *
 * No SQL change: the column, its default and the client screen already exist.
 */
import { describe, expect, it } from 'vitest';
import { json, loadEdgeHandler, mockSupabase, signedStripeWebhookRequest, type RpcHandler } from './helpers/edge-vm';

const SECRET  = 'whsec_test_only';
const LISTING = 'listing-0001';
const BUYER   = 'buyer-0001';
const SELLER  = 'seller-0001';
const PI      = 'pi_pref_1';

type Pref = { notify_listing_sold: boolean } | null;

function piEvent(id: string, over: Record<string, unknown> = {}) {
  return {
    id, type: 'payment_intent.succeeded',
    data: { object: {
      id: PI, object: 'payment_intent', status: 'succeeded', amount: 22000, amount_received: 22000, currency: 'usd', livemode: true,
      latest_charge: 'ch_1', payment_method_types: ['card'],
      metadata: { mode: 'buy_now', listing_id: LISTING, buyer_id: BUYER, seller_id: SELLER },
      ...over,
    } },
  };
}

/** `pref: undefined` = row present and true; `null` = no row; `prefError` = the read fails. */
function harness(opts: { pref?: Pref; prefError?: boolean; outcome?: string } = {}) {
  const prefQueries: Array<{ filters: Array<[string, ...unknown[]]>; select: string | null }> = [];
  const rpc: RpcHandler = (name) => {
    if (name === 'claim_stripe_webhook_event') return { data: 'claimed' };
    if (name === 'complete_stripe_webhook_event') return { data: true };
    if (name === 'fail_stripe_webhook_event') return { data: true };
    if (name === 'settle_verified_payment') {
      return { data: [{ payment_id: 'pay_1', payment_status: 'succeeded', listing_status: 'sold', transfer_id: 'tr_row_1', outcome: opts.outcome ?? 'settled' }] };
    }
    return { data: null };
  };
  const sb = mockSupabase({
    rpc,
    tables: {
      listings: () => ({ data: { event_name: 'Fixture Event', transfer_method: 'mobile_transfer' } }),
      payments: () => ({ data: { id: 'pay_1', listing_id: LISTING } }),
      notification_preferences: (q) => {
        prefQueries.push({ filters: q.filters, select: q.select });
        if (opts.prefError) return { data: null, error: { message: 'boom', code: 'XX000' } };
        return { data: opts.pref === undefined ? { notify_listing_sold: true } : opts.pref };
      },
    },
  });
  const pushes: Array<Record<string, unknown>> = [];
  const fetchMock = (async (_url: string | URL | Request, init?: RequestInit) => {
    pushes.push(JSON.parse(String(init?.body ?? '{}')) as Record<string, unknown>);
    return new Response('{}', { status: 200 });
  }) as unknown as typeof fetch;
  const deliver = async (event: Record<string, unknown>) => {
    const edge = await loadEdgeHandler('supabase/functions/stripe-webhook/index.ts', {
      supabase: sb,
      env: { STRIPE_WEBHOOK_SECRET: SECRET, STRIPE_SECRET_KEY: 'sk_test_only', SUPABASE_URL: 'https://x.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service-test' },
      fetch: fetchMock,
      provide: { stripeFetchRaw: async () => ({ ok: false, status: 500, data: {} }) },
    });
    const res = await edge.handler(signedStripeWebhookRequest(SECRET, event));
    return { res, body: await json(res), edge };
  };
  return { sb, pushes, deliver, prefQueries };
}

const titles = (pushes: Array<Record<string, unknown>>) => pushes.map((p) => String(p.title));
const logsOf = (edge: { logs: Array<{ args: unknown[] }> }) =>
  edge.logs.map((l) => l.args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')).join('\n');

describe('stripe-webhook — the seller\'s "Listing sold" preference is honoured (notification batch 1)', () => {
  it('P1: a seller who turned the toggle OFF gets no sold push — and the buyer is still told', async () => {
    const h = harness({ pref: { notify_listing_sold: false } });
    const { res } = await h.deliver(piEvent('evt_p1'));
    expect(res.status).toBe(200);
    expect(titles(h.pushes)).toEqual(['Payment Confirmed!']);
    expect(h.pushes.every((p) => p.user_id !== SELLER)).toBe(true);
  });

  it('P2: a seller who left it ON gets both pushes, unchanged', async () => {
    const h = harness();
    await h.deliver(piEvent('evt_p2'));
    expect(titles(h.pushes)).toEqual(['Payment Confirmed!', 'Your ticket sold!']);
    expect(h.pushes[1]).toMatchObject({ user_id: SELLER, data: { type: 'ticket_sold' } });
  });

  it('P3: no preferences row means TRUE — an older account is not silently opted out', async () => {
    const h = harness({ pref: null });
    await h.deliver(piEvent('evt_p3'));
    expect(titles(h.pushes)).toEqual(['Payment Confirmed!', 'Your ticket sold!']);
  });

  it('P4: a FAILED preference read also means true — the transfer prompt is money, the preference is a convenience', async () => {
    const h = harness({ prefError: true });
    const { edge } = await h.deliver(piEvent('evt_p4'));
    expect(titles(h.pushes)).toEqual(['Payment Confirmed!', 'Your ticket sold!']);
    expect(logsOf(edge).toLowerCase()).toContain('preference');
  });

  it('P5: the preference is read for the SELLER, selecting only that column', async () => {
    const h = harness();
    await h.deliver(piEvent('evt_p5'));
    expect(h.prefQueries).toHaveLength(1);
    const f = h.prefQueries[0].filters.find((x) => x[0] === 'eq' && x[1] === 'user_id');
    expect(f?.[2]).toBe(SELLER);
    expect(f?.[2]).not.toBe(BUYER);
    expect(String(h.prefQueries[0].select)).toContain('notify_listing_sold');
  });

  it('P6: nothing is read when the sale did not settle', async () => {
    const h = harness({ outcome: 'already_settled' });
    await h.deliver(piEvent('evt_p6'));
    expect(h.prefQueries).toHaveLength(0);
    expect(h.pushes).toHaveLength(0);
  });
});
