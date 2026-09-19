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
 * The refund states this route can show (owner, 2026-09-18). Each says ONLY what
 * the recorded amounts establish: no claim that nothing was bought (a confirmed
 * full refund can follow a completed purchase), and nothing about processing,
 * cancellation, bank timing or the order's status — the order's status is
 * established elsewhere (Tickets), so the screen points there instead.
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

/** An instruction, not a claim: the order's status is established on Tickets. */
export const REFUND_POINTER = "Check Tickets for this order's current status.";

export interface RefundViewModel {
  kicker: string;
  title: string;
  body: string;
  pointer: string;
  /** Always Tickets: never the listing (it could invite another purchase) and never a retry. */
  cta: { label: string; href: '/(tabs)/tickets' };
}

/**
 * What the refund screen renders, as a pure function so it is testable as
 * behaviour. The neutral kind never shows an amount, even if one is passed.
 */
export function refundViewModel(kind: RefundCopyKind, refundedCents: number | null): RefundViewModel {
  const copy = REFUND_COPY[kind];
  const amount = kind !== 'refund_unconfirmed' && refundedCents != null ? formatCents(refundedCents) : null;
  return {
    kicker: copy.kicker,
    title: copy.title,
    // A confirmed kind with no amount cannot reach here from refundStateFor; if one ever did, it falls back to the
    // neutral body rather than printing a placeholder.
    body: amount ? copy.body.replace('{amount}', amount) : REFUND_COPY.refund_unconfirmed.body,
    pointer: REFUND_POINTER,
    cta: { label: 'Go to Tickets', href: '/(tabs)/tickets' },
  };
}
