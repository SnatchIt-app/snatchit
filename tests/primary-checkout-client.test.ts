/**
 * Primary checkout client (CONTRACTS C3; edge `primary-checkout`, supabase/functions/primary-checkout/index.ts
 * in this tree; undeployed). Pure: the edge and the hold are injected. A payments surface — reviewed by A
 * before any merge.
 *
 * Pinned:
 *   - the edge body is exactly { session_id, items:[{ticket_type_id, quantity}], hold_ids, command_key }
 *     plus `expected_total_cents` ONLY once the buyer has been shown a total (C3 + `_shared/money.ts`
 *     totalMismatch: an absent value is never a mismatch; a present one must equal the server total);
 *   - a quote is admitted only with integer minor units, USD, a client secret, and total = amount + buyer_fee
 *     (the edge's own instruction to clients); anything else is "unavailable", never a price;
 *   - every documented refusal maps to a reason; raw server text is never shown;
 *   - the command key is stable for one purchase intent (retries and double taps replay, never duplicate);
 *   - the flow never reaches a success state: after the PaymentSheet it is "submitted", and the ticket
 *     screen says "Awaiting payment confirmation" until the webhook issues atoms.
 *
 * Negative controls (run by hand, each must FAIL): send `expected_total_cents` on the first quote (C1);
 * admit a quote where total ≠ amount + buyer_fee (Q2); mint a fresh command key per retry (K1).
 */
import { describe, expect, it } from 'vitest';

import {
  PRIMARY_CHECKOUT_COPY,
  attemptCommandKey,
  checkoutStep,
  parsePrimaryCheckoutResponse,
  requestPrimaryQuote,
  type CheckoutState,
  type PrimaryQuote,
} from '@/src/lib/primary/checkout';

const SESSION = '44444444-4444-4444-8444-444444444444';
const TT = '66666666-6666-4666-8666-666666666666';
const HOLD = '77777777-7777-4777-8777-777777777777';

const okBody = {
  order_id: '88888888-8888-4888-8888-888888888888', clientSecret: 'pi_123_secret_abc', paymentIntentId: 'pi_123',
  amount: 2000, buyer_fee: 200, seller_fee: 0, total: 2200, currency: 'usd', customerId: 'cus_1', customerEphemeralKeySecret: 'ek_test',
};

describe('requestPrimaryQuote — the edge body', () => {
  it('C1: the first quote sends no expected_total_cents; the body has exactly the contract keys', async () => {
    let sent: Record<string, unknown> | null = null;
    await requestPrimaryQuote(async (_n, body) => { sent = body as Record<string, unknown>; return { status: 200, body: okBody }; }, {
      sessionId: SESSION, items: [{ ticketTypeId: TT, quantity: 2 }], holdIds: [HOLD], commandKey: 'pc-k', shownTotalMinor: null,
    });
    expect(sent).toEqual({ session_id: SESSION, items: [{ ticket_type_id: TT, quantity: 2 }], hold_ids: [HOLD], command_key: 'pc-k' });
  });

  it('C2: once a total was shown, a retry carries it as expected_total_cents', async () => {
    let sent: Record<string, unknown> | null = null;
    await requestPrimaryQuote(async (_n, body) => { sent = body as Record<string, unknown>; return { status: 200, body: okBody }; }, {
      sessionId: SESSION, items: [{ ticketTypeId: TT, quantity: 2 }], holdIds: [HOLD], commandKey: 'pc-k', shownTotalMinor: 2200,
    });
    expect(sent).toMatchObject({ expected_total_cents: 2200 });
  });

  it('C3: malformed ids or quantities never reach the network', async () => {
    let called = 0;
    const inv = async () => { called++; return { status: 200, body: okBody }; };
    expect(await requestPrimaryQuote(inv, { sessionId: 'x', items: [{ ticketTypeId: TT, quantity: 1 }], holdIds: [HOLD], commandKey: 'k', shownTotalMinor: null })).toEqual({ ok: false, reason: 'unavailable' });
    expect(await requestPrimaryQuote(inv, { sessionId: SESSION, items: [{ ticketTypeId: TT, quantity: 0 }], holdIds: [HOLD], commandKey: 'k', shownTotalMinor: null })).toEqual({ ok: false, reason: 'unavailable' });
    expect(await requestPrimaryQuote(inv, { sessionId: SESSION, items: [{ ticketTypeId: TT, quantity: 1 }], holdIds: [], commandKey: 'k', shownTotalMinor: null })).toEqual({ ok: false, reason: 'unavailable' });
    expect(called).toBe(0);
  });

  it('C4: a thrown invoker is offline', async () => {
    expect(await requestPrimaryQuote(async () => { throw new Error('Network request failed'); }, {
      sessionId: SESSION, items: [{ ticketTypeId: TT, quantity: 1 }], holdIds: [HOLD], commandKey: 'k', shownTotalMinor: null,
    })).toEqual({ ok: false, reason: 'offline' });
  });
});

describe('parsePrimaryCheckoutResponse', () => {
  it('Q1: the documented 200 becomes a quote in integer cents', () => {
    expect(parsePrimaryCheckoutResponse(200, okBody)).toEqual({
      ok: true,
      quote: {
        orderId: okBody.order_id, clientSecret: 'pi_123_secret_abc', paymentIntentId: 'pi_123',
        faceMinor: 2000, buyerFeeMinor: 200, totalMinor: 2200, customerId: 'cus_1', ephemeralKeySecret: 'ek_test',
      },
    });
  });

  it('Q2: a 200 whose total is not amount + buyer_fee, or not integer USD, or without a secret is unavailable', () => {
    expect(parsePrimaryCheckoutResponse(200, { ...okBody, total: 2100 })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parsePrimaryCheckoutResponse(200, { ...okBody, currency: 'eur' })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parsePrimaryCheckoutResponse(200, { ...okBody, amount: 20.5, total: 220.5 })).toEqual({ ok: false, reason: 'unavailable' });
    expect(parsePrimaryCheckoutResponse(200, { ...okBody, clientSecret: '' })).toEqual({ ok: false, reason: 'unavailable' });
  });

  it('Q3: every documented refusal has its own reason', () => {
    const r = (status: number, code: string, extra: Record<string, unknown> = {}) => parsePrimaryCheckoutResponse(status, { error: 'server text', code, ...extra });
    expect(r(409, 'not_on_sale')).toEqual({ ok: false, reason: 'not_on_sale' });
    expect(r(409, 'session_terminal')).toEqual({ ok: false, reason: 'ended' });
    expect(r(409, 'hold_invalid')).toEqual({ ok: false, reason: 'hold_expired' });
    expect(r(409, 'total_mismatch', { server_total_cents: 2400 })).toEqual({ ok: false, reason: 'price_changed', serverTotalMinor: 2400 });
    expect(r(503, 'service_fee_unset')).toEqual({ ok: false, reason: 'sales_unavailable' });
    expect(r(503, 'service_fee_out_of_range')).toEqual({ ok: false, reason: 'sales_unavailable' });
    expect(r(409, 'org_not_eligible')).toEqual({ ok: false, reason: 'sales_unavailable' });
    expect(r(404, 'not_found')).toEqual({ ok: false, reason: 'not_found' });
    expect(r(403, 'identity_erased')).toEqual({ ok: false, reason: 'account_blocked' });
    expect(r(403, 'deletion_pending')).toEqual({ ok: false, reason: 'account_blocked' });
    expect(r(409, 'precondition_failed')).toEqual({ ok: false, reason: 'refused' });
    expect(parsePrimaryCheckoutResponse(401, { error: 'x' })).toEqual({ ok: false, reason: 'signed_out' });
    expect(parsePrimaryCheckoutResponse(429, { error: 'x' })).toEqual({ ok: false, reason: 'rate_limited' });
    expect(parsePrimaryCheckoutResponse(null, undefined)).toEqual({ ok: false, reason: 'offline' });
    expect(parsePrimaryCheckoutResponse(500, { error: 'x' })).toEqual({ ok: false, reason: 'unavailable' });
  });

  it('Q4: a total_mismatch without a usable server total is still price_changed, with no number to show', () => {
    expect(parsePrimaryCheckoutResponse(409, { code: 'total_mismatch' })).toEqual({ ok: false, reason: 'price_changed', serverTotalMinor: null });
  });

  it('Q5: refusal copy never repeats server text and never claims a charge or a ticket', () => {
    for (const v of Object.values(PRIMARY_CHECKOUT_COPY.refusal)) {
      expect(v).not.toContain('server text');
      expect(v.toLowerCase()).not.toMatch(/charged|your ticket is|tickets are confirmed|success/);
    }
  });
});

describe('attemptCommandKey — one key per purchase intent', () => {
  it('K1: the same attempt id gives the same key; a new attempt gives a new key', () => {
    const a = attemptCommandKey(SESSION, 'a1b2c3');
    expect(attemptCommandKey(SESSION, 'a1b2c3')).toBe(a);
    expect(attemptCommandKey(SESSION, 'd4e5f6')).not.toBe(a);
  });

  it('K2: the key fits the edge limit and carries no clock', () => {
    const k = attemptCommandKey(SESSION, 'f'.repeat(64));
    expect(k.length).toBeLessThanOrEqual(200);
    expect(k).not.toMatch(/\d{13}/);   // no epoch milliseconds
  });
});

describe('checkoutStep — never a success state', () => {
  const quote: PrimaryQuote = {
    orderId: 'o', clientSecret: 's', paymentIntentId: 'pi', faceMinor: 2000, buyerFeeMinor: 200, totalMinor: 2200, customerId: 'c', ephemeralKeySecret: 'e',
  };
  const quoted: CheckoutState = { kind: 'quoted', quote };

  it('F1: a quote is shown (all-in total first) before any payment step', () => {
    expect(checkoutStep({ kind: 'quoting' }, { type: 'quote', result: { ok: true, quote } })).toEqual(quoted);
  });

  it('F2: a price change goes back to a re-confirm of the new total, not to payment', () => {
    expect(checkoutStep(quoted, { type: 'quote', result: { ok: false, reason: 'price_changed', serverTotalMinor: 2400 } }))
      .toEqual({ kind: 'price_changed', serverTotalMinor: 2400 });
  });

  it('F3: an expired hold returns to selection with its message; sales unavailable is terminal for this screen', () => {
    expect(checkoutStep({ kind: 'quoting' }, { type: 'quote', result: { ok: false, reason: 'hold_expired' } })).toEqual({ kind: 'refused', reason: 'hold_expired' });
    expect(checkoutStep({ kind: 'quoting' }, { type: 'quote', result: { ok: false, reason: 'sales_unavailable' } })).toEqual({ kind: 'refused', reason: 'sales_unavailable' });
  });

  it('F4: the sheet completing is "submitted" — the ticket screen then waits for the webhook; a cancelled sheet keeps the quote', () => {
    expect(checkoutStep({ kind: 'paying', quote }, { type: 'sheet', outcome: 'completed' })).toEqual({ kind: 'submitted', orderId: 'o' });
    expect(checkoutStep({ kind: 'paying', quote }, { type: 'sheet', outcome: 'canceled' })).toEqual(quoted);
    expect(checkoutStep({ kind: 'paying', quote }, { type: 'sheet', outcome: 'failed' })).toEqual({ kind: 'payment_failed', quote });
  });

  it('F5: no state is named success, paid or confirmed', () => {
    expect(JSON.stringify(PRIMARY_CHECKOUT_COPY).toLowerCase()).not.toMatch(/payment successful|you're in|tickets confirmed/);
    expect(PRIMARY_CHECKOUT_COPY.submitted.body).toMatch(/confirm/i);
  });
});
