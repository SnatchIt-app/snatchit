import { rowWhenLabel } from '@/src/lib/listing/feedRowState';
import { ATTACH_COPY } from '@/src/lib/transfer/markSent';
import { SELLER_ORDER_CLOSED_COPY, transferStatusCopy } from '@/src/lib/transfer/transferState';

/**
 * src/lib/seller/nextAction.ts — the seller's ONE next action for a My Listings row (checklist
 * item 39 / CFT-408: "Give sellers one clear next action … with the relevant deadline. Don't make
 * sellers infer the task from a generic status badge.").
 *
 * Input is what the row already knows from the server — the listing status and the transfer's
 * {status, expires_at, transfer_evidence_path} — plus the device clock. Output is one line or
 * nothing:
 *
 *   transfer status   condition                          line
 *   ───────────────   ─────────────────────────────────  ──────────────────────────────────────────
 *   expired           (server fact, any clock)           SELLER_ORDER_CLOSED_COPY.expired.body
 *   pending           expires_at missing / unparseable   "Send the tickets" — no time is invented
 *   pending           device clock before expires_at     "Send by <local time from expires_at>"
 *   pending           device clock at/after expires_at   neutral `windowPassed` (below)
 *   seller_sent       no transfer_evidence_path          "Add proof" — no deadline: none exists
 *   anything else     reversed, disputed, buyer_confirmed, auto_released, a proofed seller_sent,
 *                     an unknown status, no transfer, or a listing that is not sold → nothing
 *
 * WHY THE PAST-DEADLINE LINE IS ITS OWN SENTENCE. `expires_at` is a display deadline only; the
 * server's expiry sweep (the enforce-transfer-expiry job → public.enforce_transfer_expiry) is the authority, and
 * `mark_transfer_sent` never reads `expires_at`. So once the device clock passes it, the row may not
 * say "expired" (only the server's `expired` status permits that word), may not encourage sending
 * (owner, 2026-09-19: "A phone-clock deadline alone must not encourage sending tickets or assert
 * that a refund occurred."), and may not reuse the send screen's TRANSFER_EXPIRY_COPY.seller —
 * that string says a status check is running, and My Listings runs none. It points at the order
 * screen instead, which DOES re-read the transfer and shows the server's answer.
 *
 * Payout setup is deliberately NOT an action here (owner decision pending): every listing that can
 * sell was published by a connected account (listings INSERT RLS + the publish gate), so it would
 * only ever apply to an account restricted later, which needs the status_only probe.
 *
 * Pure: no effects, no Supabase, no theme. The clock is a parameter so the rule is testable.
 */

export type SellerNextActionKind = 'send_by' | 'send' | 'window_passed' | 'add_proof' | 'do_not_send';

/** `warning` = the row's action colour (amber, as the old send line); `neutral` = secondary ink. */
export type SellerNextActionTone = 'warning' | 'neutral';

export interface SellerNextAction {
  kind: SellerNextActionKind;
  line: string;
  tone: SellerNextActionTone;
}

/** The transfer columns this rule reads. Anything else on the row is ignored on purpose. */
export interface SellerTransferFacts {
  status: string;
  expires_at?: string | null;
  transfer_evidence_path?: string | null;
}

export interface SellerNextActionInput {
  listingStatus: string;
  transfer: SellerTransferFacts | null | undefined;
}

export const SELLER_NEXT_ACTION_COPY = {
  /** The seller's existing pending title — used when the deadline cannot be read. */
  send: transferStatusCopy('pending', 'seller').title,
  /**
   * Device clock past expires_at. Says only what is true from here: the window has passed, and the
   * order screen will show the current status. No "expired", no "checking", no "send".
   */
  windowPassed: 'Send window has passed — open this order to see its current status',
  /** The send screen's own button word for the same action (markSent.ts). */
  addProof: ATTACH_COPY.cta,
  /** Server `expired`: the existing do-not-send sentence, verbatim. */
  doNotSend: SELLER_ORDER_CLOSED_COPY.expired.body,
} as const;

/** "Wed 21 Oct · 21:14" — expires_at in the device zone, in the shared row format; null when unparseable. */
function localDeadline(iso: string): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const pad = (n: number) => String(n).padStart(2, '0');
  const label = rowWhenLabel(
    `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`,
    `${pad(d.getHours())}:${pad(d.getMinutes())}`,
  );
  return label || null;
}

export function sellerNextAction(input: SellerNextActionInput, nowMs: number): SellerNextAction | null {
  const t = input.transfer;
  if (input.listingStatus !== 'sold' || !t) return null;

  // The server's word first: an expired order is closed whatever the device clock says.
  if (t.status === 'expired') return { kind: 'do_not_send', line: SELLER_NEXT_ACTION_COPY.doNotSend, tone: 'warning' };

  if (t.status === 'pending') {
    const deadlineMs = t.expires_at ? new Date(t.expires_at).getTime() : NaN;
    const when = t.expires_at ? localDeadline(t.expires_at) : null;
    if (!Number.isFinite(deadlineMs) || !when) return { kind: 'send', line: SELLER_NEXT_ACTION_COPY.send, tone: 'warning' };
    // Same boundary as the send screen's countdown (formatCountdown: diff <= 0 is past).
    if (deadlineMs - nowMs > 0) return { kind: 'send_by', line: `Send by ${when}`, tone: 'warning' };
    return { kind: 'window_passed', line: SELLER_NEXT_ACTION_COPY.windowPassed, tone: 'neutral' };
  }

  if (t.status === 'seller_sent' && !t.transfer_evidence_path) {
    return { kind: 'add_proof', line: SELLER_NEXT_ACTION_COPY.addProof, tone: 'warning' };
  }

  return null;
}

/** The send and proof actions are taken on the order screen; the closed line and "nothing" are not. */
export function sellerActionOpensOrder(action: SellerNextAction | null | undefined): boolean {
  return action != null && action.kind !== 'do_not_send';
}
