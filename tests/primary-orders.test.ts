/**
 * Primary orders → what the ticket screen may say (CONTRACTS C5 + A's payment_state ruling, 2026-10-26).
 *
 * The schema limit (D's 182 header, A's ruling): a PENDING order reads `payment_state = none` until
 * `finalize_primary_order` writes the order↔payment link, so "unpaid" and "paid, awaiting the
 * webhook" look identical. The screen therefore says "Awaiting payment confirmation" — never
 * "unpaid", never a success state, never a code — until atoms exist.
 *
 * Negative controls (run by hand, each must FAIL): map (pending, none) to 'none' (H1);
 * let a paid order with issued atoms and no atoms on this account fall through to 'empty' (H4);
 * drop the refund line's "Refunded" word (L3).
 */
import { describe, expect, it } from 'vitest';

import {
  ORDER_COPY,
  issuanceHint,
  orderStatusLine,
  type PrimaryOrderRow,
} from '@/src/lib/tickets/primaryOrders';

const order = (over: Partial<PrimaryOrderRow> = {}): PrimaryOrderRow => ({
  order_id: '33333333-3333-4333-8333-333333333333',
  status: 'pending',
  total_minor: 2200,
  currency: 'USD',
  created_at: '2026-10-26T21:00:00Z',
  atoms_issued: 0,
  payment_state: 'none',
  ...over,
});

describe('issuanceHint — A’s C5 ruling, newest order first', () => {
  it('H1: (pending, none) is awaiting payment confirmation — the only state a pending order reads today', () => {
    expect(issuanceHint([order()])).toBe('awaiting_confirmation');
  });

  it('H2: pending with a readable payment state keeps its own words (for when PENDING-A C5-1 lands)', () => {
    expect(issuanceHint([order({ payment_state: 'processing' })])).toBe('payment_processing');
    expect(issuanceHint([order({ payment_state: 'succeeded' })])).toBe('paid_pending');
    expect(issuanceHint([order({ payment_state: 'failed' })])).toBe('payment_failed');
  });

  it('H3: no orders is none; a failed read is unknown, never none', () => {
    expect(issuanceHint([])).toBe('none');
    expect(issuanceHint(null)).toBe('unknown');
  });

  it('H4: a paid order whose atoms were issued means the tickets exist — if this account has none, they are elsewhere', () => {
    expect(issuanceHint([order({ status: 'paid', atoms_issued: 2, payment_state: 'succeeded' })])).toBe('issued');
  });

  it('H5: a pending order outranks an older settled one; cancelled/expired/refunded alone are none', () => {
    const older = order({ order_id: 'o-old', status: 'paid', atoms_issued: 1, payment_state: 'succeeded', created_at: '2026-10-20T00:00:00Z' });
    expect(issuanceHint([order(), older])).toBe('awaiting_confirmation');
    for (const status of ['cancelled', 'expired', 'refunded'] as const) {
      expect(issuanceHint([order({ status, payment_state: status === 'refunded' ? 'succeeded' : 'none' })]), status).toBe('none');
    }
  });

  it('H6: an order status the client does not know is unknown, not none', () => {
    expect(issuanceHint([order({ status: 'disputed' as never })])).toBe('unknown');
  });
});

describe('orderStatusLine — one honest line per order, in USD from integer minor units', () => {
  it('L1: pending + none says awaiting confirmation; the copy never says unpaid or failed', () => {
    const l = orderStatusLine(order({ charge_total_minor: 2200 }));
    expect(l.status).toBe('Awaiting payment confirmation');
    expect(l.amount).toBe('$22.00');
    expect(`${l.status} ${ORDER_COPY.awaiting.body}`.toLowerCase()).not.toMatch(/unpaid|not paid|failed|declined/);
  });

  it('L2: paid states the issued count from the server, singular and plural', () => {
    expect(orderStatusLine(order({ status: 'paid', atoms_issued: 1, payment_state: 'succeeded' })).status).toBe('Paid · 1 ticket issued');
    expect(orderStatusLine(order({ status: 'paid', atoms_issued: 3, payment_state: 'succeeded' })).status).toBe('Paid · 3 tickets issued');
    expect(orderStatusLine(order({ status: 'paid', atoms_issued: 0, payment_state: 'succeeded' })).status).toBe('Paid · tickets being issued');
  });

  it('L3: refunded, cancelled and expired say exactly that; cancelled/expired add "no tickets issued" only when the server count is 0', () => {
    expect(orderStatusLine(order({ status: 'refunded', payment_state: 'succeeded', atoms_issued: 2 })).status).toBe('Refunded');
    expect(orderStatusLine(order({ status: 'cancelled' })).status).toBe('Cancelled · no tickets issued');
    expect(orderStatusLine(order({ status: 'expired' })).status).toBe('Expired · no tickets issued');
    expect(orderStatusLine(order({ status: 'cancelled', atoms_issued: 1 })).status).toBe('Cancelled');
  });

  it('L4: a failed payment on a pending order says the payment did not go through, nothing about charges', () => {
    const l = orderStatusLine(order({ payment_state: 'failed' }));
    expect(l.status).toBe('Payment didn’t go through');
    expect(l.status.toLowerCase()).not.toMatch(/charge|refund/);
  });

  it('L5: the amount is the CHARGED total only — total_minor is face value and is never shown as what the buyer paid', () => {
    expect(orderStatusLine(order({ total_minor: 2000 })).amount).toBeNull();              // no charge total → no amount
    expect(orderStatusLine(order({ total_minor: 2000, charge_total_minor: 2200 })).amount).toBe('$22.00');
    expect(orderStatusLine(order({ currency: 'EUR', charge_total_minor: 2200 })).amount).toBeNull();
    expect(orderStatusLine(order({ charge_total_minor: -1 })).amount).toBeNull();
    expect(orderStatusLine(order({ charge_total_minor: 12.5 as never })).amount).toBeNull();
  });

  it('L6: an unknown status says the status is unavailable', () => {
    expect(orderStatusLine(order({ status: 'disputed' as never })).status).toBe('Status unavailable');
  });
});
