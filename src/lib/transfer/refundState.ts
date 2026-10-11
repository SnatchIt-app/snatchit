/**
 * src/lib/transfer/refundState.ts — the four outcomes of the buyer's refund read.
 *
 * The refund shown on a closed order is a fact on the buyer's own payment row, read through the one
 * settled-payments read. That read can be in flight, it can fail, it can succeed and find no refund,
 * or it can succeed and find one — and those are four different things to say. The screen previously
 * held `PaymentRefundFacts | null` and returned early when the read failed, so the first three
 * collapsed into `null` and rendered a line that describes the PAYMENT ROW ("if a refund is issued,
 * it will show here"). After a failed read nothing is known about the payment row, so that line is a
 * claim the app has not earned.
 *
 * The rule this module exists to keep: a line about a refund may only be rendered from a payment row
 * that was actually read.
 */
import { REFUND_DUE_POLICY, REFUND_PARTIAL_DUE_POLICY, REFUND_PENDING_LINE, refundLine, type PaymentRefundFacts } from './transferState';

/** In flight, failed, or read — and if read, what the row said. */
export type RefundRead =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'error' }
  /**
   * `rowCount` is how many settled rows the read returned, BEFORE the reduction to one row of
   * facts. "You paid <total>" needs exactly one (A, 2026-09-24): with two settled rows the select
   * carries no payment id to match transfers.payment_id, so the figure would be a guess. Optional
   * so hand-built states (the gallery's fixtures) still typecheck — an absent count is treated as
   * unproven, never as one.
   */
  | { kind: 'loaded'; facts: PaymentRefundFacts | null; rowCount?: number };

/** Shown while the read is in flight: a description of what the app is doing, not of the payment. */
export const REFUND_CHECKING_LINE = 'Checking for a refund…';
/**
 * Shown when the read failed. It says only that the check failed — not that a refund exists, and not
 * that none does. Either would be an assertion about a row the app could not read.
 */
export const REFUND_UNREADABLE_LINE = "We couldn't check this order's refund just now.";

type SettledRead =
  | { rows: { status?: string | null; amount_refunded_cents?: number | null; refunded_at?: string | null; total?: number | null }[] }
  | { error: unknown };

/**
 * Turn one settled-payments read into a state. A read WITHOUT `rows` is an error — never a
 * successful read of nothing, which is what the early return used to make it.
 */
export function refundReadState(read: SettledRead): RefundRead {
  if (!read || !('rows' in read)) return { kind: 'error' };
  const rows = read.rows ?? [];
  // The row that carries a refund if any does, else the first row, else nothing was found.
  const withRefund = rows.find((r) => r.refunded_at != null || (r.amount_refunded_cents ?? 0) > 0) ?? rows[0] ?? null;
  if (!withRefund) return { kind: 'loaded', facts: null, rowCount: 0 };
  return {
    kind: 'loaded',
    rowCount: rows.length,
    facts: {
      status: withRefund.status ?? null,
      amount_refunded_cents: withRefund.amount_refunded_cents ?? null,
      refunded_at: withRefund.refunded_at ?? null,
      total: withRefund.total ?? null,
    },
  };
}

/**
 * The one line the closed-order block renders, per state and context.
 *
 * The contexts that may say "due" — `expired`, and the two rulings `buyer_win` / `partial` — are
 * the owner's SOURCES (16:51Z (i)). But a source alone is not the obligation: (ii) requires the
 * payment to have been CAPTURED (`status === 'succeeded'`) with no refund recorded. So a read
 * that found no payment row, or a row that never succeeded, renders the neutral pending line —
 * an obligation claim without the capture behind it would rest on nothing the client read.
 * `reversed` is the seller's payout event and never supports "due".
 */
export type RefundLineContext = 'expired' | 'reversed' | 'buyer_win' | 'partial';

export function refundStateLine(state: RefundRead, context: RefundLineContext): string {
  switch (state.kind) {
    case 'loading':
    case 'idle':
      return REFUND_CHECKING_LINE;
    case 'error':
      return REFUND_UNREADABLE_LINE;
    case 'loaded': {
      const recorded = refundLine(state.facts);
      if (recorded) return recorded; // EXECUTION: the payment row speaks for itself.
      const source = context === 'expired' || context === 'buyer_win' || context === 'partial';
      const captured = state.facts?.status === 'succeeded';
      if (source && captured) return context === 'partial' ? REFUND_PARTIAL_DUE_POLICY : REFUND_DUE_POLICY;
      return REFUND_PENDING_LINE;
    }
  }
}
