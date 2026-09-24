/**
 * V3 order stage — the pure order-presentation module, tested as a truth table.
 *
 * The board (`midnight-order-clean` composition, `pkg7-order-after-*` copy, `pkg8-order-*`
 * tokens) draws a four-step PROGRESS track, an event summary and a "You paid" figure. The
 * rules that keep those truthful live in src/lib/orders/orderPresentation.ts and are pinned
 * here BEFORE any screen consumes them:
 *
 *  - payout wording is gated on `payout_released_at`, never on the status;
 *  - the confirmation step is the BUYER's fact (`buyer_confirmed_at`) — an operator's dispute
 *    decision never paints it done, and decided/closed statuses get no track at all;
 *  - "You paid" repeats only a succeeded, unrefunded payment row's recorded total, through the
 *    V3 money display module;
 *  - the deadline sub-line comes from the server's `auto_release_at` or is the word "pending";
 *  - no sentence here claims automatic release (O-1 is not approved and stays out).
 */
import { describe, expect, it } from 'vitest';

import {
  CONFIRMATION_PENDING,
  ORDER_PROGRESS_LABELS,
  orderProgress,
  orderProgressA11y,
  orderTicketsLine,
  orderWhenWhereLine,
  PAYOUT_NOT_RELEASED,
  PAYOUT_RELEASED,
  shortDeadline,
  youPaidAmount,
  YOU_PAID_LABEL,
} from '@/src/lib/orders/orderPresentation';
import type { RefundRead } from '@/src/lib/transfer/refundState';

const base = { buyerConfirmedAt: null, payoutReleasedAt: null, autoReleaseAt: null };

describe('orderProgress — which statuses get a track at all', () => {
  it('OP1: pending and seller_sent get the four steps; the closed and decided statuses do not', () => {
    expect(orderProgress({ ...base, status: 'pending' })).toHaveLength(4);
    expect(orderProgress({ ...base, status: 'seller_sent' })).toHaveLength(4);
    for (const status of ['disputed', 'expired', 'reversed', 'auto_released', '']) {
      expect(orderProgress({ ...base, status }), status).toBeNull();
    }
  });

  it('OP2: buyer_confirmed is a track ONLY with the buyer\'s own timestamp — an operator decision is not a confirmation', () => {
    expect(orderProgress({ ...base, status: 'buyer_confirmed' })).toBeNull();
    const steps = orderProgress({ ...base, status: 'buyer_confirmed', buyerConfirmedAt: '2026-10-20T12:00:00Z' });
    expect(steps).not.toBeNull();
    expect(steps!.find((s) => s.key === 'confirm')!.state).toBe('done');
  });

  it('OP3: step states move with the status, and only forward facts are marked done', () => {
    const pending = orderProgress({ ...base, status: 'pending' })!;
    expect(pending.map((s) => s.state)).toEqual(['done', 'current', 'todo', 'todo']);
    const sent = orderProgress({ ...base, status: 'seller_sent' })!;
    expect(sent.map((s) => s.state)).toEqual(['done', 'done', 'current', 'todo']);
  });

  it('OP4: the payout step speaks only from payout_released_at — in both directions', () => {
    const held = orderProgress({ ...base, status: 'seller_sent' })!;
    expect(held.find((s) => s.key === 'payout')!.sub).toBe(PAYOUT_NOT_RELEASED);
    expect(held.find((s) => s.key === 'payout')!.state).toBe('todo');
    // Even a buyer-confirmed order shows "not released" until the server wrote the release…
    const confirmed = orderProgress({ ...base, status: 'buyer_confirmed', buyerConfirmedAt: 'x2026-01-01' })!;
    expect(confirmed.find((s) => s.key === 'payout')!.sub).toBe(PAYOUT_NOT_RELEASED);
    // …and the released word appears only with the timestamp.
    const released = orderProgress({
      ...base, status: 'buyer_confirmed', buyerConfirmedAt: '2026-10-20T12:00:00Z', payoutReleasedAt: '2026-10-21T09:00:00Z',
    })!;
    expect(released.find((s) => s.key === 'payout')!.sub).toBe(PAYOUT_RELEASED);
    expect(released.find((s) => s.key === 'payout')!.state).toBe('done');
  });

  it('OP5: the confirmation sub-line is the server deadline or the word pending — never a device-made date', () => {
    const withDeadline = orderProgress({ ...base, status: 'seller_sent', autoReleaseAt: '2026-10-26T09:12:00Z' })!;
    const sub = withDeadline.find((s) => s.key === 'confirm')!.sub!;
    expect(sub.startsWith('by ')).toBe(true);
    const without = orderProgress({ ...base, status: 'seller_sent' })!;
    expect(without.find((s) => s.key === 'confirm')!.sub).toBe(CONFIRMATION_PENDING);
    // An unparseable server value degrades to the same honest word.
    const garbled = orderProgress({ ...base, status: 'seller_sent', autoReleaseAt: 'not-a-date' })!;
    expect(garbled.find((s) => s.key === 'confirm')!.sub).toBe(CONFIRMATION_PENDING);
  });

  it('OP6: no step ever invents a payment timestamp, and no wording claims automatic release (O-1)', () => {
    const steps = orderProgress({ ...base, status: 'seller_sent', autoReleaseAt: '2026-10-26T09:12:00Z' })!;
    expect(steps.find((s) => s.key === 'paid')!.sub).toBeNull();
    const everything = steps.map((s) => `${s.label} ${s.sub ?? ''}`).join(' ') + ' ' + orderProgressA11y(steps);
    expect(everything.toLowerCase()).not.toMatch(/automatic|released to the seller/);
    // The four board labels, verbatim.
    expect(steps.map((s) => s.label)).toEqual([
      ORDER_PROGRESS_LABELS.paid, ORDER_PROGRESS_LABELS.sent,
      ORDER_PROGRESS_LABELS.confirm, ORDER_PROGRESS_LABELS.payout,
    ]);
  });

  it('OP7: the a11y sentence carries every label, state and sub-line', () => {
    const steps = orderProgress({ ...base, status: 'seller_sent' })!;
    const line = orderProgressA11y(steps);
    for (const s of steps) expect(line).toContain(s.label);
    expect(line).toContain(PAYOUT_NOT_RELEASED);
    expect(line).toContain('current step');
  });
});

describe('shortDeadline', () => {
  it('OD1: formats a real timestamp as "by …" and refuses anything else', () => {
    expect(shortDeadline('2026-10-26T09:12:00Z')!.startsWith('by ')).toBe(true);
    expect(shortDeadline(null)).toBeNull();
    expect(shortDeadline(undefined)).toBeNull();
    expect(shortDeadline('garbage')).toBeNull();
  });
});

describe('the summary lines — absent columns drop out, nothing prints blank', () => {
  it('OS1: when/where joins only what exists', () => {
    const full = orderWhenWhereLine('2026-10-24', '19:30:00', 'Lantern Room');
    expect(full).toContain('19:30');
    expect(full).toContain('Lantern Room');
    expect(full.split(' · ')).toHaveLength(3);
    expect(orderWhenWhereLine(null, null, 'Lantern Room')).toBe('Lantern Room');
    expect(orderWhenWhereLine(null, null, null)).toBe('');
    // The date is parsed as a LOCAL date: the 24th never shifts to the 23rd.
    expect(orderWhenWhereLine('2026-10-24', null, null)).toContain('24');
  });

  it('OS2: the tickets line composes quantity × type · method · provider', () => {
    expect(orderTicketsLine(2, 'GA', 'mobile_transfer', 'DICE')).toBe('2 × GA · Mobile transfer · DICE');
    expect(orderTicketsLine(1, 'VIP', 'email', null)).toBe('1 × VIP · Email');
    expect(orderTicketsLine(null, 'GA', null, null)).toBe('');
    expect(orderTicketsLine(0, 'GA', null, null)).toBe('');
  });
});

describe('youPaidAmount — repeats the payment row or says nothing', () => {
  const loaded = (facts: Record<string, unknown> | null): RefundRead =>
    ({ kind: 'loaded', facts } as RefundRead);

  it('OY1: a succeeded, unrefunded row with a total renders through the V3 money display', () => {
    expect(youPaidAmount(loaded({ status: 'succeeded', total: 9900, amount_refunded_cents: null, refunded_at: null })))
      .toBe('$99.00');
    expect(YOU_PAID_LABEL).toBe('You paid');
  });

  it('OY2: every state that has not earned the figure says nothing', () => {
    expect(youPaidAmount({ kind: 'idle' })).toBeNull();
    expect(youPaidAmount({ kind: 'loading' })).toBeNull();
    expect(youPaidAmount({ kind: 'error' })).toBeNull();
    expect(youPaidAmount(loaded(null))).toBeNull();
    // Never captured: a row that did not succeed asserts nothing about money paid.
    expect(youPaidAmount(loaded({ status: 'requires_action', total: 9900 }))).toBeNull();
    // No known total: no figure to repeat.
    expect(youPaidAmount(loaded({ status: 'succeeded', total: null }))).toBeNull();
    expect(youPaidAmount(loaded({ status: 'succeeded', total: 0 }))).toBeNull();
    // A refund on the row: the money story belongs to the refund lines, not a quiet price row.
    expect(youPaidAmount(loaded({ status: 'succeeded', total: 9900, refunded_at: '2026-10-01T00:00:00Z' }))).toBeNull();
    expect(youPaidAmount(loaded({ status: 'succeeded', total: 9900, amount_refunded_cents: 500 }))).toBeNull();
  });
});
