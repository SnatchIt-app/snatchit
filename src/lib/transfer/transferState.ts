import { formatCents } from '@/src/lib/money';
import { rowWhenLabel } from '@/src/lib/listing/feedRowState';
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
 *
 * Seller (owner, 2026-09-19): "Remove 'send now if you still can.' A phone-clock deadline alone must not encourage
 * sending tickets or assert that a refund occurred." In production the expiry cron can expire the order and refund the
 * buyer at any moment after the deadline (A, from main's edge source), so the seller is told only that the status is
 * being checked, then what the last read said, never that sending is safe.
 */
export const TRANSFER_EXPIRY_COPY = {
  /** The seller's screen, device clock past the deadline, no server read since: neutral. */
  seller: "Send window has passed — checking this order's status",
  /** The seller's screen, still pending on a read taken after the deadline: no guarantee against a later expiry. */
  sellerLastCheckedOpen: 'Send window has passed — this order was still open when last checked, but it can close at any time',
  /**
   * The buyer's screen. F-XFER-2-A: batch 1b gave both screens the seller's string, so the buyer was told to
   * "send now if you still can" — an action they cannot take and that is not theirs. The buyer's true
   * statement is what the server will still allow, said about the other party.
   */
  buyer: 'Send window has passed — the seller may still send',
} as const;

/**
 * Server-confirmed closure (owner, 2026-09-19): "Where the server confirms cancellation, expiry or refund, clearly tell
 * the seller not to transfer tickets for that order." Here only the transfer row's `expired` status (the expiry job only
 * expires a pending transfer, so it was never marked sent). Never inferred from the device clock, and nothing is
 * inferred from payment status: a recorded refund is held separately until the payment lifecycle is resolved (owner).
 */
export const SELLER_ORDER_CLOSED_COPY = {
  expired: { title: 'Order expired', body: "This order expired before it was marked as sent. Don't transfer the tickets for this order." },
} as const;

export type SellerWindowView =
  | { kind: 'none' }
  | { kind: 'countdown'; line: string }
  | { kind: 'checking'; line: string }
  | { kind: 'last_checked_open'; line: string }
  | { kind: 'closed'; title: string; body: string };

/**
 * What the seller's Send Transfer screen may say about the send window. The server fact first: an `expired` transfer
 * closes the order whatever the device clock says. Otherwise the device clock only chooses between the countdown and
 * neutral wording, and `checkedSincePassed` (a server read taken after the device deadline) chooses between
 * "checking" and "still open when last checked". States past sending keep their own blocks.
 */
export function sellerWindowView(i: {
  status: string;
  countdown: string | null;
  checkedSincePassed: boolean;
}): SellerWindowView {
  if (i.status === 'expired') return { kind: 'closed', ...SELLER_ORDER_CLOSED_COPY.expired };
  if (i.status !== 'pending') return { kind: 'none' };
  if (i.countdown == null) return { kind: 'none' };
  if (i.countdown !== 'Expired') return { kind: 'countdown', line: `${i.countdown} to send` };
  return i.checkedSincePassed
    ? { kind: 'last_checked_open', line: TRANSFER_EXPIRY_COPY.sellerLastCheckedOpen }
    : { kind: 'checking', line: TRANSFER_EXPIRY_COPY.seller };
}

/**
 * What a transfer read may be CALLED when it does not return the row (owner, 2026-09-19): a failed read must not become
 * a claim that the order does not exist. Only PostgREST's no-row answer (or a row-less success) supports "not found";
 * every other failure is `unavailable`, which the screens show as the app's neutral error state.
 */
export type TransferReadOutcome = 'ok' | 'offline' | 'not_found' | 'unavailable';

export function transferReadOutcome(i: {
  isNetwork: boolean;
  code?: string | null;
  hasRow: boolean;
  /** True when the read returned an error at all; a row-less success is still "no row". */
  failed?: boolean;
}): TransferReadOutcome {
  if (i.isNetwork) return 'offline';
  if (i.hasRow) return 'ok';
  if (i.code === 'PGRST116') return 'not_found';
  if (i.failed || (i.code != null && i.code !== '')) return 'unavailable';
  return 'not_found';
}

/** The canonical badge label + tone for a status. Word carries the meaning. */
export function transferStatusMeta(
  status: string,
  role: TransferRole = 'buyer',
  /** See `transferStatusCopy`: a NULL `buyer_confirmed_at` on `buyer_confirmed` is an operator's
   *  dispute decision, not a confirmation. Defaults to true so existing callers are unchanged. */
  opts: { buyerConfirmed?: boolean } = {},
): { label: string; tone: TransferTone } {
  // The badge must not assert receipt to someone who reported non-receipt and lost, and it is not a
  // success for them either.
  if (status === 'buyer_confirmed' && opts.buyerConfirmed === false) {
    return { label: 'Resolved', tone: 'neutral' };
  }
  switch (status) {
    case 'pending':         return { label: 'Pending',     tone: 'neutral' };
    case 'seller_sent':     return { label: 'Marked sent', tone: 'neutral' };
    case 'buyer_confirmed': return { label: 'Received',    tone: 'success' };
    case 'auto_released':   return { label: 'Released',    tone: 'success' };
    case 'disputed':        return { label: 'Issue',       tone: 'warning' };
    // A's table (2026-09-24): `expired` is the one server fact that permits the word.
    case 'expired':         return { label: 'Expired',     tone: 'neutral' };
    // `reversed` is the SELLER's payout event (Stripe transfer.reversed → mark_transfer_reversed).
    // It is never a buyer-facing money fact, so the buyer's word is neutral.
    case 'reversed':        return role === 'seller'
      ? { label: 'Payout reversed', tone: 'warning' }
      : { label: 'Closed',          tone: 'neutral' };
    default:                return { label: status.replace(/_/g, ' '), tone: 'neutral' };
  }
}

export type TransferRole = 'buyer' | 'seller';

/**
 * One sentence per state and role, with the claim/possession distinction kept:
 * "marked … as sent" is always the seller's statement; "received" is always the
 * buyer's. Auto-release says what happened to the money, not to the tickets.
 */
export function transferStatusCopy(
  status: string,
  role: TransferRole,
  /**
   * `buyer_confirmed` is reached two ways: the buyer confirms, or an operator resolves a dispute for
   * the seller. Only the buyer's own `confirm_transfer_received` writes `buyer_confirmed_at`
   * (0550:191-205); `resolve_transfer_dispute` (065:119-152) never touches it and a guard blocks
   * direct writes — so a NULL timestamp on that status means the buyer did NOT confirm. Defaults to
   * true so every existing caller keeps the sentence it had.
   */
  opts: { buyerConfirmed?: boolean } = {},
): { title: string; body: string } {
  const buyer = role === 'buyer';
  const buyerConfirmed = opts.buyerConfirmed ?? true;
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
      if (!buyerConfirmed) {
        // An operator decided this, so neither sentence may credit the buyer with confirming. The
        // buyer's line says what happened without hinting at a refund; the seller's matches the
        // server's own notice and leaves every payout statement to the payout fields.
        return buyer
          ? { title: 'Dispute resolved', body: 'Support reviewed the dispute on this transfer and decided it in the seller\'s favour. Contact support if you have questions.' }
          : { title: 'Dispute resolved in your favour', body: 'Support reviewed this transfer and decided it in your favour.' };
      }
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

/**
 * The buyer's auto-release block (owner, 2026-09-19; A's review). `auto_released` is the release DECISION;
 * `payout_released_at` is written only by `record_transfer_payout`, after the Stripe transfer succeeded. Without that
 * field the screen says the window closed and the order is complete, and claims nothing about money reaching the
 * seller. With it, the existing sentence stands.
 */
export function buyerAutoReleasedCopy(payoutReleasedAt: string | null | undefined): { title: string; body: string } {
  if (payoutReleasedAt) return transferStatusCopy('auto_released', 'buyer');
  return {
    title: 'Review window closed',
    body: 'The review window closed without a confirmation or a report from you. This order is complete.',
  };
}

/** Seller side: the ticket is out the door (any state at/after sent). */
export function sellerAlreadySent(status: string): boolean {
  return status === 'seller_sent' || status === 'buyer_confirmed' || status === 'auto_released';
}

/**
 * Owner's decision 2 (2026-09-18): "I got my tickets" asks first. The dialog says plainly what confirming does —
 * the same claim the screen's release warning already makes — and only its explicit action sends anything.
 * Cancel sends nothing. What the action sends, and every server rule behind it, are unchanged.
 */
export const CONFIRM_RECEIPT_DIALOG = {
  title: 'Confirm you received the tickets?',
  body: 'Confirming receipt releases payment to the seller. Only confirm if you can see the tickets in your ticket account.',
  cancel: 'Cancel',
  confirm: 'Confirm and release payment',
} as const;

/**
 * V3 O-3 (owner 2026-09-22): what "Report a problem" may say when the SEND fails on the network.
 * A dropped connection is a submitted-action-with-unknown-result, never proof the report was not
 * received — the request can still land after the client gives up. The screen re-reads first; only
 * if the server still shows no report does it say this. "Reporting again is safe" is server truth:
 * buyer_dispute_transfer returns success on an already-disputed transfer (0550, idempotent branch).
 */
export const REPORT_PROBLEM_UNCONFIRMED = {
  title: "We couldn't confirm your report was received",
  body: 'Your connection dropped while it was being sent. If this order is not marked as reported after a refresh, report it again — sending it twice is safe.',
} as const;

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

// ─── The order/transfer cells (A's PAYMENT_STATE_WORDING_TABLE_20260924 @ fbbe0440) ────────────
//
// Three facts, three columns, never derived from one another: ORDER = transfers.status; RECORDED
// REFUND = payments.{amount_refunded_cents, refunded_at, status}; CONFIRMED PAYOUT =
// transfers.payout_released_at. Precedence: reversed > payout_released_at; disputed > any deadline;
// a NULL amount > the word "refunded"; a server timestamp > the device clock.

/** What the ORDER status alone establishes for the buyer — nothing about money. */
export const BUYER_ORDER_CLOSED_COPY = {
  expired: { title: 'Order expired', body: "The seller didn't send the tickets in time." },
  reversed: { title: 'Order closed', body: 'This order is closed.' },
} as const;

/** A stated policy on `expired`, not an asserted fact: the refund shows when the payment row does. */
export const REFUND_DUE_POLICY = "A refund is due; it will show here once it's confirmed.";
/** The transfer row is readable but the payment row carries no refund yet. */
export const REFUND_PENDING_LINE = "If a refund is issued, it will show here.";

export const SELLER_REVERSED_COPY = {
  title: 'Payout reversed',
  body: "This order's payout was reversed after a dispute or operator review.",
} as const;
/** No payout ever moved for an expired order (Phase 1 runs on pending rows). */
export const SELLER_NO_PAYOUT_LINE = 'No payout for this order.';

export interface PaymentRefundFacts {
  status: string | null;
  amount_refunded_cents: number | null;
  refunded_at: string | null;
  total: number | null;
}

/**
 * The recorded refund, from the payment row alone. "Refunded $X" only when the amount is known AND
 * equals the total; a partial states both figures; a date or status without an amount is "Refund
 * recorded" — never "in full", never a figure; nothing recorded is null (the caller decides between
 * the policy line and the pending line).
 */
export function refundLine(p: PaymentRefundFacts | null | undefined): string | null {
  if (!p) return null;
  const amount = p.amount_refunded_cents;
  const total = p.total;
  const recorded = p.status === 'refunded' || p.refunded_at != null;
  if (amount != null && amount > 0) {
    if (total != null && total > 0 && amount === total) return `Refunded ${formatCents(amount)}`;
    if (total != null && total > 0 && amount < total) return `Partly refunded ${formatCents(amount)} of ${formatCents(total)}`;
    return 'Refund recorded';
  }
  return recorded ? 'Refund recorded' : null;
}

/** A server timestamp in the shared row format, local time; null when unparseable. */
function localDateTime(iso: string): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const pad = (n: number) => String(n).padStart(2, '0');
  return rowWhenLabel(
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    `${pad(d.getHours())}:${pad(d.getMinutes())}`,
  );
}

/** The buyer's review window, from the server's auto_release_at — or nothing. Never a payout claim. */
export function buyerReviewDeadlineLine(autoReleaseAt: string | null | undefined): string | null {
  if (!autoReleaseAt) return null;
  const when = localDateTime(autoReleaseAt);
  return when ? `Confirm you received the tickets, or report a problem, before ${when}.` : null;
}

/** The seller's line names the release DECISION time (039 decides at auto_release_at) — not a payout. */
export function sellerReleaseLine(autoReleaseAt: string | null | undefined): string | null {
  if (!autoReleaseAt) return null;
  const when = localDateTime(autoReleaseAt);
  return when ? `Release decision at ${when}.` : null;
}

/**
 * The seller's hold line (A, 2026-09-24): only when payout_review_status === 'held' AND the server's
 * payout_hold_until is present — never derived from auto_release_at + policy days. A hold, not a
 * payout: after that time the release DECISION runs; the money fact is still payout_released_at.
 */
export function sellerHoldLine(reviewStatus: string | null | undefined, holdUntil: string | null | undefined): string | null {
  if (reviewStatus !== 'held' || !holdUntil) return null;
  const when = localDateTime(holdUntil);
  return when ? `Payout held until ${when}.` : null;
}
