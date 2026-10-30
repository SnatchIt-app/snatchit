/**
 * src/lib/listing/reservationExit.ts — should leaving the listing release my hold?
 *
 * OWNER RULE: a Buy Now hold should survive Checkout -> Listing (the user is still
 * in the purchase funnel) but be released the moment the user explicitly leaves the
 * listing back to Home, so the ticket returns to other buyers instead of sitting
 * held for the rest of the 10 minutes.
 *
 * The EXIT SIGNAL is navigation removal of the listing screen (React Navigation's
 * `beforeRemove`), which fires when the listing is popped and NOT when Checkout is
 * pushed on top of it. Backgrounding, a phone call, the Stripe sheet, a modal, the
 * keyboard and transitions are not navigation removals, so none of them release.
 *
 * This decides only whether to ASK. The server (public.release_reservation) is
 * authoritative: it takes auth.uid(), locks the row, returns early when the listing
 * is sold, and only clears a reservation the caller owns — so it is idempotent and
 * can never release someone else's hold or one that a purchase already consumed.
 */

export interface ReservationExitInput {
  /** Last known listing status. */
  status: string | null | undefined;
  /** Last known holder of the reservation. */
  reservedBy: string | null | undefined;
  /** The signed-in user. */
  userId: string | null | undefined;
  /** This screen already fired a release (client-side idempotence). */
  alreadyReleased: boolean;
  /** A purchase completed for this listing; never release after that. */
  purchased: boolean;
}

export function shouldReleaseReservation(i: ReservationExitInput): boolean {
  if (i.alreadyReleased) return false;   // one release per screen instance
  if (i.purchased) return false;         // never after a completed purchase
  if (!i.userId) return false;           // signed out: nothing of ours to release
  // Anything not actively reserved (active / sold / already expired) is a no-op.
  if (i.status !== 'reserved') return false;
  return !!i.reservedBy && i.reservedBy === i.userId; // only ever our own hold
}
