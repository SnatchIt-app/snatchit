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
 *
 * PREMIUM BATCH 3 (CFT-402, item 30). The seller's claim and the buyer's
 * possession are different facts and are never given the same word:
 * `seller_sent` is "Marked sent" (the seller said so), `buyer_confirmed` is
 * "Received" (the buyer said so), `auto_released` is "Released" (the window
 * closed with no word from the buyer — payment moved, possession is unknown).
 * `transferStatusCopy` carries the role-specific sentence for the same states.
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

/**
 * F-XFER-1: what the send screen may say once the device clock passes `expires_at`.
 *
 * It may NOT say "expired". Nothing on the server enforces that word: `mark_transfer_sent` (140) gates on
 * status alone and never reads `expires_at`, so a send past the window still succeeds until the sweep moves
 * the row off `pending`. The old chip asserted an enforcement no layer performed, and it asserted it from
 * the device's own clock. This says only what is true from here: the window has passed, sending may still
 * work, and the system decides.
 *
 * Whether the window SHOULD be enforced server-side is the owner's, routed through A. This copy does not
 * anticipate that answer, and it must be revisited if enforcement arrives.
 */
export const TRANSFER_EXPIRY_COPY = {
  passed: 'Send window has passed — send now if you still can',
} as const;

/** The canonical badge label + tone for a status. Word carries the meaning. */
export function transferStatusMeta(status: string): { label: string; tone: TransferTone } {
  switch (status) {
    case 'pending':         return { label: 'Pending',     tone: 'neutral' };
    case 'seller_sent':     return { label: 'Marked sent', tone: 'neutral' };
    case 'buyer_confirmed': return { label: 'Received',    tone: 'success' };
    case 'auto_released':   return { label: 'Released',    tone: 'success' };
    case 'disputed':        return { label: 'Issue',       tone: 'warning' };
    default:                return { label: status.replace(/_/g, ' '), tone: 'neutral' };
  }
}

export type TransferRole = 'buyer' | 'seller';

/**
 * One sentence per state and role, with the claim/possession distinction kept:
 * "marked … as sent" is always the seller's statement; "received" is always the
 * buyer's. Auto-release says what happened to the money, not to the tickets.
 */
export function transferStatusCopy(status: string, role: TransferRole): { title: string; body: string } {
  const buyer = role === 'buyer';
  switch (status) {
    case 'pending':
      return buyer
        ? { title: 'Waiting for the seller', body: 'The seller has not marked the tickets as sent yet.' }
        : { title: 'Send the tickets', body: 'The buyer has paid. Payment is held until they confirm receipt.' };
    case 'seller_sent':
      return buyer
        ? { title: 'Seller marked as sent', body: "That is the seller's update, not a confirmation. Check your ticket account, then confirm receipt here." }
        : { title: 'Marked as sent', body: 'Waiting for the buyer to confirm they received the tickets.' };
    case 'buyer_confirmed':
      return buyer
        ? { title: 'Tickets received', body: 'You confirmed receipt. Enjoy the event.' }
        : { title: 'Tickets received', body: 'The buyer confirmed they received the tickets.' };
    case 'auto_released':
      return buyer
        ? { title: 'Payment released', body: 'The review window closed without a confirmation or a report from you, so payment went to the seller.' }
        : { title: 'Payout released', body: 'The buyer review window passed without a report. Your payout has been released.' };
    case 'disputed':
      return buyer
        ? { title: 'Issue reported', body: 'Our team typically reviews within 24 hours. Your payment stays on hold until this is resolved.' }
        : { title: 'Dispute in progress', body: 'The buyer has reported an issue with the transfer. Your payout is on hold pending review.' };
    default:
      return { title: status.replace(/_/g, ' '), body: '' };
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
