/**
 * src/lib/checkout/paymentGuard.ts — a synchronous single-flight latch.
 *
 * WHY: the Stripe payment sheet must be presented exactly once per attempt.
 * React state (`confirming`/`disabled`) does not update before a second tap's
 * event handler runs in the same frame, so a rapid double-tap on Pay would call
 * `presentPaymentSheet()` twice and the native module then throws
 * "StripeSdk.presentPaymentSheet(): Tried to resolve a promise more than once".
 *
 * `begin()` returns true for the first caller only and flips the latch
 * synchronously; every re-entrant caller gets false until `end()` releases it.
 * The checkout screen holds one of these in a ref and guards both pay handlers
 * with it, releasing in `finally` so a cancel or error cleanly allows a retry.
 */

export interface SingleFlight {
  /** Acquire the latch. True exactly once until end(); false while in flight. */
  begin(): boolean;
  /** Release the latch so a later attempt (retry after cancel/error) can begin. */
  end(): void;
  /** Whether an attempt is currently in flight. */
  readonly active: boolean;
}

export function createSingleFlight(): SingleFlight {
  let inFlight = false;
  return {
    begin(): boolean {
      if (inFlight) return false;
      inFlight = true;
      return true;
    },
    end(): void {
      inFlight = false;
    },
    get active(): boolean {
      return inFlight;
    },
  };
}
