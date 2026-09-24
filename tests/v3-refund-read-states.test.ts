/**
 * The refund read has four outcomes and the screen collapsed them into one
 * (owner 2026-09-24: "preserve loading/error/success distinctions in the refund read. A failed read
 * must not become 'no refund recorded,' and stale facts must not leak between orders").
 *
 * What it did: `refundFacts` was `PaymentRefundFacts | null`, and the effect returned early on a
 * failed read — `if (!alive || !('rows' in read)) return;` — leaving the state at whatever it held.
 * So a read that never answered, a read that FAILED, and a read that succeeded and found no refund
 * all arrived at the block as `null`, which renders the "if a refund is issued, it will show here"
 * policy line. That line is a statement about the payment row. After a failed read nothing is known
 * about the payment row at all.
 *
 * And because the state was not reset when the key changed, a second order's block rendered the
 * FIRST order's refund figure until the new read resolved.
 *
 * Four states now, with a line each, and the block asserts nothing it has not read.
 */
import { describe, expect, it } from 'vitest';

import { refundReadState, refundStateLine, type RefundRead } from '@/src/lib/transfer/refundState';
import { REFUND_DUE_POLICY, REFUND_PENDING_LINE } from '@/src/lib/transfer/transferState';

const FACTS = { status: 'refunded', amount_refunded_cents: 11000, refunded_at: '2026-09-20T00:00:00Z', total: 11000 };

describe('the refund read keeps its four outcomes apart', () => {
  it('RR1: a read in flight is "checking", not "no refund"', () => {
    const st: RefundRead = { kind: 'loading' };
    expect(refundStateLine(st, 'expired')).toMatch(/checking/i);
    expect(refundStateLine(st, 'expired')).not.toBe(REFUND_DUE_POLICY);
    expect(refundStateLine(st, 'reversed')).not.toBe(REFUND_PENDING_LINE);
  });

  it('RR2: a FAILED read says the check failed and claims nothing about the payment', () => {
    const st: RefundRead = { kind: 'error' };
    const line = refundStateLine(st, 'expired');
    expect(line).toMatch(/could ?n.t|unable/i);
    // It must not imply a refund exists, nor that none does.
    expect(line).not.toMatch(/refunded|no refund|will show here/i);
    expect(refundStateLine(st, 'reversed')).toBe(line);
  });

  it('RR3: a successful read with no refund is where the policy lines belong', () => {
    const st: RefundRead = { kind: 'loaded', facts: null };
    expect(refundStateLine(st, 'expired')).toBe(REFUND_DUE_POLICY);
    expect(refundStateLine(st, 'reversed')).toBe(REFUND_PENDING_LINE);
  });

  it('RR4: a successful read with a refund states the figure', () => {
    const st: RefundRead = { kind: 'loaded', facts: FACTS };
    // `formatCents` drops the cents on a whole-dollar amount, which is the app's existing
    // convention and what TR2 already pins. (The approved V3 boards show 2dp throughout — that is a
    // separate, deliberate formatting change, recorded with the visual corrections.)
    expect(refundStateLine(st, 'reversed')).toBe('Refunded $110');
  });

  it('RR5: the reducer maps a failed read to error, not to loaded-with-nothing', () => {
    expect(refundReadState({ error: 'nope' } as never)).toEqual({ kind: 'error' });
    expect(refundReadState({ rows: [] })).toEqual({ kind: 'loaded', facts: null });
    const withRefund = refundReadState({ rows: [{ status: 'refunded', amount_refunded_cents: 11000, refunded_at: 'x', total: 11000 }] as never });
    expect(withRefund.kind).toBe('loaded');
    expect(withRefund.kind === 'loaded' && withRefund.facts?.amount_refunded_cents).toBe(11000);
  });

  it('RR6: a row that carries no refund still loads as "no refund", not as an error', () => {
    const st = refundReadState({ rows: [{ status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 11000 }] as never });
    expect(st).toEqual({ kind: 'loaded', facts: { status: 'succeeded', amount_refunded_cents: null, refunded_at: null, total: 11000 } });
    // …and its line is the policy line, because the payment row WAS read.
    expect(refundStateLine(st, 'expired')).toBe(REFUND_DUE_POLICY);
  });

  it('RR7: the screen resets to loading when the order changes, so no figure leaks between orders', async () => {
    const { readFileSync } = await import('node:fs');
    const src = readFileSync('app/transfer/receive/[id].tsx', 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
    // The effect must set loading before awaiting, and must not early-return on a failed read.
    expect(src).toMatch(/setRefundRead\(\{ kind: 'loading' \}\)/);
    expect(src).toMatch(/setRefundRead\(refundReadState\(read\)\)/);
    expect(src).not.toMatch(/!\('rows' in read\)\) return/);
  });
});
