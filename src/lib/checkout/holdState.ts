/**
 * src/lib/checkout/holdState.ts — what checkout says about a hold it no longer
 * has, and how it names the deadline it does have.
 *
 * WHAT WAS WRONG (D9-UX-1). Every not-held listing was reported as "Your
 * reservation has expired", including one released 8.6 minutes early after a
 * failed authentication, and the only control was a "Try again" that re-ran
 * the same check and could never re-reserve.
 *
 * WHAT THE CLIENT ACTUALLY KNOWS. The server cannot distinguish a hold that
 * ran out from one that was released (both leave the listing active with the
 * hold fields null). The screen knows two things the server does not:
 *   - whether ITS OWN release call succeeded (then "released" is true);
 *   - the deadline it was showing (if that has passed, "ran out" is true by
 *     the clock the buyer was watching).
 * Anything else is reported neutrally. No wording claims a reason it cannot
 * back, and the way forward is always the listing, never a retry.
 */

import { formatCents } from '../money';

export type NotHeldReason = 'released_by_us' | 'ran_out' | 'unknown';

export interface NotHeldCopy {
  reason: NotHeldReason;
  title: string;
  body: string;
}

export function notHeldReason(input: {
  /** This screen's own release_reservation call succeeded. */
  releasedByUs: boolean;
  /** The deadline the screen was showing, epoch ms; null when none was shown. */
  reservedUntilMs: number | null;
  nowMs: number;
}): NotHeldReason {
  if (input.releasedByUs) return 'released_by_us';
  if (input.reservedUntilMs != null && input.nowMs >= input.reservedUntilMs) return 'ran_out';
  return 'unknown';
}

export function notHeldCopy(reason: NotHeldReason): NotHeldCopy {
  switch (reason) {
    case 'released_by_us':
      return {
        reason,
        title: 'Your hold was released',
        body: 'Nothing was charged. Go back to the listing to reserve it again.',
      };
    case 'ran_out':
      return {
        reason,
        title: 'Your hold ran out',
        body: 'Nothing was charged. Go back to the listing to reserve it again if it is still available.',
      };
    default:
      return {
        reason,
        title: 'This listing is no longer held for you',
        body: 'Nothing was charged. Go back to the listing to check availability and reserve it again.',
      };
  }
}

/**
 * "Held for you until 9:14 PM" — the actual deadline, next to the countdown.
 * Uses the device locale; falls back to the countdown alone when the time
 * cannot be formatted.
 */
export function fmtHoldUntil(reservedUntilMs: number, locale?: string): string | null {
  try {
    return new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' }).format(new Date(reservedUntilMs));
  } catch {
    return null;
  }
}

/**
 * The hold could not be checked (setup's listing read, and — D's R2 — re-validation's). Says only that it couldn't be
 * checked: nothing about the hold being lost, released or expired, nothing about a charge, and no word inviting
 * payment. Owner (2026-09-19): both paths show this with "Check again" (statusUnknown), never Pay.
 */
export const RESERVATION_UNVERIFIABLE_COPY = "We couldn't check your reservation.";

/**
 * F-CHK-READERR (owner, 2026-09-18; wording 2026-09-19): the settled-payment lookup failed. Says only that it
 * couldn't be checked whether this was already paid — nothing about a charge, a refund, the hold or the listing. Payment stays withheld until a check succeeds.
 */
export const PAYMENT_STATUS_UNKNOWN_COPY = "We couldn't check whether this has already been paid.";

/**
 * The escrow line under checkout's payment state. It describes a payment state, so (owner, 2026-09-19) it is hidden
 * whenever the payment status is unknown: the settled-payment lookup failed (setup or re-validation), or a payment
 * result could not be confirmed (unreachable). A reservation-unknown state is not one: its payment lookup succeeded.
 */
export const ESCROW_NOTE_COPY = 'Payment is held until your ticket reaches you. Secured by Stripe.';

export function showEscrowNote(i: { paymentStatusUnknown: boolean; confirmUnreachable: boolean }): boolean {
  return !i.paymentStatusUnknown && !i.confirmUnreachable;
}

/**
 * The refund states this route can show (owner, 2026-09-18). Each says ONLY what
 * the recorded amounts establish: no claim that nothing was bought (a confirmed
 * full refund can follow a completed purchase), and nothing about processing,
 * cancellation, bank timing or the order's status. The only control is "Back to
 * home" (owner, 2026-09-18): Tickets lists only native tickets, so a marketplace
 * order is never there and its empty state would read as "you own nothing".
 * `refund_unconfirmed` is every production refund today: the amount is unknown.
 */
export const REFUND_COPY = {
  refund_unconfirmed: {
    kicker: 'Refund',
    title: 'Refund recorded',
    body: "A refund was recorded for this payment. We can't confirm the refunded amount here.",
  },
  partially_refunded: {
    kicker: 'Refund',
    title: 'Partial refund recorded',
    body: 'A partial refund of {amount} was recorded for this payment.',
  },
  refunded: {
    kicker: 'Refund',
    title: 'Full refund recorded',
    body: 'A full refund of {amount} was recorded for this payment.',
  },
} as const;

export type RefundCopyKind = keyof typeof REFUND_COPY;

export interface RefundViewModel {
  kicker: string;
  title: string;
  body: string;
  /** Always home: never the listing (it could invite another purchase), never Tickets, never a retry. */
  cta: { label: 'Back to home'; href: '/(tabs)/home' };
}

/**
 * What the refund screen renders, as a pure function so it is testable as
 * behaviour. The neutral kind never shows an amount, even if one is passed.
 */
export function refundViewModel(kind: RefundCopyKind, refundedCents: number | null): RefundViewModel {
  // A confirmed kind with no amount cannot reach here from refundStateFor; if one ever did, it is shown EXACTLY as
  // the neutral kind — never a "Full/Partial refund recorded" title above an amount nobody established.
  const shown: RefundCopyKind = kind !== 'refund_unconfirmed' && refundedCents != null ? kind : 'refund_unconfirmed';
  const copy = REFUND_COPY[shown];
  return {
    kicker: copy.kicker,
    title: copy.title,
    body: shown === 'refund_unconfirmed' ? copy.body : copy.body.replace('{amount}', formatCents(refundedCents as number)),
    cta: { label: 'Back to home', href: '/(tabs)/home' },
  };
}
