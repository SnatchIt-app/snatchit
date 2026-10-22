/**
 * The shared badge selector keeps the facts the two screens used to pass themselves (A's condition on
 * the #133 pin retarget, 2026-10-22): the role, the buyer_confirmed timestamp and the dispute decision.
 * Behavioural, on the real functions: a transfer whose buyer_confirmed row carries NO timestamp (an
 * operator decision) never yields the confirmed badge; the seller and buyer roles still read `reversed`
 * differently; a disputed row takes the dispute-decision path. No label is hard-coded here, so a copy
 * change can't pass or fail this file by accident; what it pins is that the facts reach the badge.
 */
import { describe, expect, it } from 'vitest';

import { orderBadgeMeta } from '@/src/lib/transfer/orderBadge';
import { transferStatusMeta } from '@/src/lib/transfer/transferState';

const confirmedMeta = (role: 'buyer' | 'seller') => transferStatusMeta('buyer_confirmed', role, { buyerConfirmed: true });
const decidedMeta = (role: 'buyer' | 'seller') => transferStatusMeta('buyer_confirmed', role, { buyerConfirmed: false });

describe('orderBadgeMeta carries the facts to the badge', () => {
  it('OB1: buyer_confirmed WITH a timestamp is the confirmed badge; WITHOUT one (an operator decision) it is not', () => {
    expect(confirmedMeta('buyer')).not.toEqual(decidedMeta('buyer'));   // the fact changes the badge at all
    expect(orderBadgeMeta({ status: 'buyer_confirmed', buyer_confirmed_at: '2026-10-19T16:05:48Z' }, 'buyer')).toEqual(confirmedMeta('buyer'));
    expect(orderBadgeMeta({ status: 'buyer_confirmed', buyer_confirmed_at: null }, 'buyer')).toEqual(decidedMeta('buyer'));
    expect(orderBadgeMeta({ status: 'buyer_confirmed', buyer_confirmed_at: null }, 'buyer')).not.toEqual(confirmedMeta('buyer'));
    expect(orderBadgeMeta({ status: 'buyer_confirmed' }, 'seller')).toEqual(decidedMeta('seller'));
  });

  it('OB2: the role still decides what `reversed` says', () => {
    const seller = orderBadgeMeta({ status: 'reversed' }, 'seller');
    const buyer = orderBadgeMeta({ status: 'reversed' }, 'buyer');
    expect(seller).toEqual(transferStatusMeta('reversed', 'seller', { buyerConfirmed: false }));
    expect(buyer).toEqual(transferStatusMeta('reversed', 'buyer', { buyerConfirmed: false }));
    expect(seller.label).not.toBe(buyer.label);
  });

  it('OB3: a disputed row takes the dispute-decision path, not the plain status meta', () => {
    const open = orderBadgeMeta({ status: 'disputed', dispute_resolution: null, dispute_resolved_at: null }, 'buyer');
    const decided = orderBadgeMeta({ status: 'disputed', dispute_resolution: 'seller_win', dispute_resolved_at: '2026-10-20T00:00:00Z' }, 'buyer');
    expect(open).not.toEqual(decided);
    expect(typeof open.label).toBe('string');
  });
});
