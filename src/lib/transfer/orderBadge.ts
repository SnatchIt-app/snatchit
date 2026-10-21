import { disputeDecision, disputedStateMeta } from '@/src/lib/transfer/disputeOutcome';
import { transferStatusMeta, type TransferRole } from '@/src/lib/transfer/transferState';

/**
 * src/lib/transfer/orderBadge.ts — the order's badge, from ONE selector.
 *
 * Both order screens (buyer receive, seller send) and the order-support email (src/lib/support/orderSupport.ts)
 * call this, so the word on the badge and the word in the email cannot drift apart (E, D-2.5 finding 1). It is
 * exactly the expression the screens used inline: a disputed row through the dispute decision (open → "Issue",
 * decided → "Resolved"), every other status through transferStatusMeta with the buyer-confirmed flag (a NULL
 * buyer_confirmed_at on buyer_confirmed is an operator's decision, never "Received").
 */
export interface OrderBadgeRow {
  status: string | null | undefined;
  dispute_resolution?: string | null;
  dispute_resolved_at?: string | null;
  buyer_confirmed_at?: string | null;
}

export function orderBadgeMeta(row: OrderBadgeRow, role: TransferRole): ReturnType<typeof transferStatusMeta> {
  const status = row.status ?? '';
  return status === 'disputed'
    ? disputedStateMeta(
      disputeDecision({ status, dispute_resolution: row.dispute_resolution ?? null, dispute_resolved_at: row.dispute_resolved_at ?? null }),
      role,
    )
    : transferStatusMeta(status, role, { buyerConfirmed: row.buyer_confirmed_at != null });
}
