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
import { REFUND_DUE_POLICY, REFUND_PENDING_LINE, refundLine, type PaymentRefundFacts } from './transferState';

/** In flight, failed, or read — and if read, what the row said. */
export type RefundRead =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'error' }
  | { kind: 'loaded'; facts: PaymentRefundFacts | null };

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
  if (!withRefund) return { kind: 'loaded', facts: null };
  return {
    kind: 'loaded',
    facts: {
      status: withRefund.status ?? null,
      amount_refunded_cents: withRefund.amount_refunded_cents ?? null,
      refunded_at: withRefund.refunded_at ?? null,
      total: withRefund.total ?? null,
    },
  };
}

/**
 * The one line the closed-order block renders, per state. `expired` and `reversed` differ only in
 * what a SUCCESSFUL read with no refund means: an expired order is owed one, a reversed order may or
 * may not be.
 */
export function refundStateLine(state: RefundRead, status: 'expired' | 'reversed'): string {
  switch (state.kind) {
    case 'loading':
    case 'idle':
      return REFUND_CHECKING_LINE;
    case 'error':
      return REFUND_UNREADABLE_LINE;
    case 'loaded':
      return refundLine(state.facts) ?? (status === 'expired' ? REFUND_DUE_POLICY : REFUND_PENDING_LINE);
  }
}
