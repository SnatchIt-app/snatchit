/**
 * src/lib/transfer/transferState.ts — the shared, tested core of the transfer
 * flow (buyer receive + seller send).
 *
 * Both screens key their entire UI off the transfer status and a couple of
 * derived gates. Those decisions live here so the countdown, the status label and
 * the "who needs to act" gates are proven once and identical on both sides. The
 * screens keep the rich, role-specific COPY (payout review sub-states, dispute
 * language); this owns the state vocabulary, not the prose.
 *
 * No effects, no Supabase, no theme. The transfer state machine itself is Core's
 * and is untouched.
 */

export type TransferStatus =
  | 'pending'
  | 'seller_sent'
  | 'buyer_confirmed'
  | 'auto_released'
  | 'disputed';

export type TransferTone = 'neutral' | 'success' | 'warning';

/**
 * A human "h m remaining" / "m remaining" countdown to `ts`, "Expired" once past,
 * or null when there is no timestamp. `now` is injectable for tests.
 */
export function formatCountdown(ts: string | null, now: number = Date.now()): string | null {
  if (!ts) return null;
  const diff = new Date(ts).getTime() - now;
  if (diff <= 0) return 'Expired';
  const h = Math.floor(diff / 3_600_000);
  const m = Math.floor((diff % 3_600_000) / 60_000);
  if (h > 0) return `${h}h ${m}m remaining`;
  return `${m}m remaining`;
}

/** The canonical badge label + tone for a status. Word carries the meaning. */
export function transferStatusMeta(status: string): { label: string; tone: TransferTone } {
  switch (status) {
    case 'pending':         return { label: 'Pending',  tone: 'neutral' };
    case 'seller_sent':     return { label: 'Sent',     tone: 'neutral' };
    case 'buyer_confirmed': return { label: 'Complete', tone: 'success' };
    case 'auto_released':   return { label: 'Released', tone: 'success' };
    case 'disputed':        return { label: 'Issue',    tone: 'warning' };
    default:                return { label: status.replace(/_/g, ' '), tone: 'neutral' };
  }
}

/** Seller side: the ticket is out the door (any state at/after sent). */
export function sellerAlreadySent(status: string): boolean {
  return status === 'seller_sent' || status === 'buyer_confirmed' || status === 'auto_released';
}

type DeliveryLike = { status: string; delivery_email: string | null; delivery_phone: string | null };

/**
 * Buyer side: the buyer must still provide delivery info. Only relevant while the
 * transfer is pending or the seller has sent — never gates a finished transfer.
 */
export function buyerNeedsDelivery(t: DeliveryLike): boolean {
  return (t.status === 'pending' || t.status === 'seller_sent')
    && !t.delivery_email && !t.delivery_phone;
}

/** Seller side: the buyer has not provided delivery info yet, so sending is blocked. */
export function sellerDeliveryMissing(t: Pick<DeliveryLike, 'delivery_email' | 'delivery_phone'>): boolean {
  return !t.delivery_email && !t.delivery_phone;
}
