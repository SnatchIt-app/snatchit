/**
 * src/lib/transfer/disputeOutcome.ts — what an operator's dispute ruling may say, and no more.
 *
 * THE FOURTH GATED READ (A approved the selects and restated the conditions verbatim,
 * 2026-09-24). The columns are `transfers.dispute_resolution` and `dispute_resolved_at`,
 * appended to the two transfer screens' existing one-row reads. The separations this module
 * exists to keep — the owner's 16:51Z refinement, which governs:
 *
 *   DECISION   — `dispute_resolution` non-null. An operator's ruling, nothing else. (a) keys
 *                every state here; `dispute_resolved_at` is display only, and a timestamp
 *                without a ruling decides nothing.
 *   OBLIGATION — "A refund is due" lives in `refundState.ts`, and needs BOTH a source (expired,
 *                or a buyer-win/partial ruling) AND a captured, unrefunded payment.
 *   EXECUTION  — "Refunded …" comes only from the payment row (`refundLine`). (b) the VALUE'S
 *                NAME never maps to money copy: `'resolved_buyer_refunded'` is a decision that a
 *                refund SHOULD happen, written by an operator whose refund executor is disabled.
 *
 * Payout wording is deliberately NOT produced here: released comes only from
 * `payout_released_at`, holds from `payout_review_status`/`payout_hold_until`, and otherwise a
 * pending state — the screens already own those lines and this module must not duplicate them.
 */

import { transferStatusCopy, transferStatusMeta } from './transferState';

type BadgeMeta = ReturnType<typeof transferStatusMeta>;

/** The rulings the server writes today. Anything else renders conservatively as `unknown`. */
export type KnownResolution = 'resolved_buyer_refunded' | 'resolved_partial_refund' | 'resolved_seller_paid';

export type DisputeDecision =
  | { kind: 'none' }
  | { kind: 'open' }
  | { kind: 'decided'; resolution: KnownResolution | 'unknown'; raw: string; resolvedAt: string | null };

const KNOWN: ReadonlySet<string> = new Set<KnownResolution>([
  'resolved_buyer_refunded',
  'resolved_partial_refund',
  'resolved_seller_paid',
]);

export function disputeDecision(row: {
  status: string;
  dispute_resolution: string | null | undefined;
  dispute_resolved_at?: string | null;
}): DisputeDecision {
  const raw = row.dispute_resolution ?? null;
  if (raw != null) {
    return {
      kind: 'decided',
      resolution: KNOWN.has(raw) ? (raw as KnownResolution) : 'unknown',
      raw,
      resolvedAt: row.dispute_resolved_at ?? null,
    };
  }
  // (a): only the ruling column decides. A stray resolved_at is a server anomaly, still OPEN.
  return row.status === 'disputed' ? { kind: 'open' } : { kind: 'none' };
}

export type Role = 'buyer' | 'seller';

/**
 * The state-block sentence for a disputed transfer. Open delegates to the existing copy
 * untouched; decided says what was decided and NOTHING about money moving in either direction.
 */
export function disputedStateCopy(d: DisputeDecision, role: Role): { title: string; body: string } {
  if (d.kind !== 'decided') return transferStatusCopy('disputed', role);
  switch (d.resolution) {
    case 'resolved_seller_paid':
      return role === 'buyer'
        ? {
            title: 'Dispute resolved',
            body: "Support reviewed the dispute on this transfer and decided it in the seller's favour. Contact support if you have questions.",
          }
        : { title: 'Dispute resolved in your favour', body: 'Support reviewed this transfer and decided it in your favour.' };
    case 'resolved_buyer_refunded':
      return role === 'buyer'
        ? { title: 'Dispute resolved in your favour', body: 'Support reviewed this transfer and decided it in your favour.' }
        : {
            title: 'Dispute resolved',
            body: "Support reviewed the dispute on this transfer and decided it in the buyer's favour. Contact support if you have questions.",
          };
    case 'resolved_partial_refund':
      return role === 'buyer'
        ? { title: 'Dispute resolved', body: 'Support reviewed this transfer and decided it partly in your favour.' }
        : { title: 'Dispute resolved', body: "Support reviewed the dispute on this transfer and decided it partly in the buyer's favour." };
    case 'unknown':
      // Forward-compatible refusal: a ruling the client does not recognise is stated as a
      // recorded decision and nothing more — no direction, no money, no favour.
      return { title: 'Dispute resolved', body: 'Support has recorded a decision on this dispute. Contact support for the details.' };
  }
}

/** The badge beside the block: a decision is a neutral fact, not a success and not a warning. */
export function disputedStateMeta(d: DisputeDecision, role: Role): BadgeMeta {
  if (d.kind !== 'decided') return transferStatusMeta('disputed', role);
  return { label: 'Resolved', tone: 'neutral' };
}

/**
 * Which refund-line context a decided dispute supplies to `refundStateLine` — and null when the
 * ruling supports no obligation wording at all (seller win, unknown, open, none).
 */
export function refundDueContext(d: DisputeDecision): 'buyer_win' | 'partial' | null {
  if (d.kind !== 'decided') return null;
  if (d.resolution === 'resolved_buyer_refunded') return 'buyer_win';
  if (d.resolution === 'resolved_partial_refund') return 'partial';
  return null;
}
