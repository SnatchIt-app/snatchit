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

/** The refund states this route can show. Neither is a purchase success. */
export const REFUND_COPY = {
  refunded: {
    kicker: 'Payment refunded',
    title: 'This payment was refunded',
    body:
      'The refund has been issued to your original payment method. When it appears ' +
      'depends on your bank or card provider. No purchase was made.',
  },
  refund_pending: {
    kicker: 'Refund in progress',
    title: 'A refund is being processed',
    body:
      "This payment is being refunded. No purchase was made and there is nothing you " +
      "need to do. We'll update this order once the refund is complete.",
  },
} as const;
