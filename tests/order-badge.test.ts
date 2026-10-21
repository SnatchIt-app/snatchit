/**
 * The order badge from ONE selector (E, D-2.5 finding 1): src/lib/transfer/orderBadge.ts.
 *
 * Both order screens and the order-support email call orderBadgeMeta, so the badge word and the email word cannot
 * drift. The oracle below is the exact inline expression the two screens used before (receive/[id].tsx and
 * send/[id].tsx at e46fc203): the selector must return the same badge for every status, role, confirmation flag and
 * dispute ruling.
 */
import { describe, expect, it } from 'vitest';

import { orderBadgeMeta } from '@/src/lib/transfer/orderBadge';
import { orderSupportStatusWord } from '@/src/lib/support/orderSupport';
import { disputeDecision, disputedStateMeta } from '@/src/lib/transfer/disputeOutcome';
import { transferStatusMeta } from '@/src/lib/transfer/transferState';

type Row = { status: string; dispute_resolution: string | null; dispute_resolved_at: string | null; buyer_confirmed_at: string | null };

/** The screens' former inline expression, verbatim in shape. */
const inlineScreenBadge = (transfer: Row, role: 'buyer' | 'seller') =>
  transfer.status === 'disputed'
    ? disputedStateMeta(disputeDecision(transfer), role)
    : transferStatusMeta(transfer.status, role, { buyerConfirmed: transfer.buyer_confirmed_at != null });

const STATUSES = ['pending', 'seller_sent', 'buyer_confirmed', 'auto_released', 'disputed', 'expired', 'reversed', 'some_new_status', ''];
const RESOLUTIONS = [null, 'resolved_buyer_refunded', 'resolved_partial_refund', 'resolved_seller_paid', 'an_unknown_ruling'];
const CONFIRMED = [null, '2026-10-20T10:00:00Z'];
const RESOLVED_AT = [null, '2026-10-20T11:00:00Z'];

describe('orderBadgeMeta', () => {
  it('OB1: equals the screens\' former inline badge for every status × role × confirmation × ruling × resolved_at', () => {
    let n = 0;
    for (const status of STATUSES) for (const dispute_resolution of RESOLUTIONS) for (const buyer_confirmed_at of CONFIRMED)
      for (const dispute_resolved_at of RESOLVED_AT) for (const role of ['buyer', 'seller'] as const) {
        const row: Row = { status, dispute_resolution, dispute_resolved_at, buyer_confirmed_at };
        expect(orderBadgeMeta(row, role), JSON.stringify({ row, role })).toEqual(inlineScreenBadge(row, role));
        n++;
      }
    expect(n).toBe(STATUSES.length * RESOLUTIONS.length * CONFIRMED.length * RESOLVED_AT.length * 2);
  });

  it('OB2: the email word IS the badge label (flattened), for every combination', () => {
    for (const status of STATUSES) for (const dispute_resolution of RESOLUTIONS) for (const buyer_confirmed_at of CONFIRMED)
      for (const role of ['buyer', 'seller'] as const) {
        const row = { status, dispute_resolution, buyer_confirmed_at };
        expect(orderSupportStatusWord(row, role)).toBe(orderBadgeMeta(row, role).label.replace(/\s+/g, ' ').trim());
      }
  });

  it('OB3: a missing status is the badge for "" (not a crash)', () => {
    expect(orderBadgeMeta({ status: null }, 'buyer')).toEqual(transferStatusMeta('', 'buyer', { buyerConfirmed: false }));
    expect(orderBadgeMeta({ status: undefined }, 'seller')).toEqual(transferStatusMeta('', 'seller', { buyerConfirmed: false }));
  });
});
