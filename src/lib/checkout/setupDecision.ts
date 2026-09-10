/**
 * src/lib/checkout/setupDecision.ts — what checkout does when it mounts.
 *
 * Pure orchestration with injected dependencies, so the rule can be tested as
 * behaviour rather than as source text. CheckoutNative supplies the real
 * supabase / edge-function calls and renders the result.
 *
 * THE RULE THIS ADDS (D5 review, blocking item 1). The 3-D Secure return URL
 * now lands on `checkout/[id]`, and that screen can remount after the charge
 * has already succeeded. The old sequence was reservation pre-check first,
 * which bails into "Your reservation has expired" for a listing that is sold
 * BECAUSE THIS BUYER PAID — a false failure after a true success. So the first
 * question is now: has this buyer's purchase of this listing already landed?
 * If yes, show the completed settlement and create nothing. Auction mode had no
 * pre-check at all and would have created a second intent; the same guard now
 * covers it.
 *
 * RE-ENTRY. Two rapid mounts for the same listing share one in-flight setup, so
 * at most one intent is created no matter how many times the route re-enters.
 */

export type CheckoutMode = 'buy_now' | 'auction';

export interface SettledPayment {
  status: string;
}

export interface ListingHold {
  status: string;
  reserved_by: string | null;
  reserved_until: string | null;
}

export interface SetupDeps<Intent> {
  /** The buyer's own payment row for this listing, if any (RLS: own rows only). */
  fetchSettledPayment(listingId: string, buyerId: string): Promise<SettledPayment | null>;
  /** Fresh listing hold state. Buy Now only. */
  fetchListing(listingId: string): Promise<ListingHold | null>;
  /** The edge call that creates (or reuses) the PaymentIntent. */
  createIntent(): Promise<Intent>;
  /** Injected for tests; defaults to wall clock. */
  now?: () => Date;
}

export type SetupDecision<Intent> =
  | { kind: 'already_settled' }
  | { kind: 'reservation_unverifiable' }
  | { kind: 'reservation_expired' }
  | { kind: 'ready'; intent: Intent };

/** Payment statuses that mean the purchase has landed and must not be retried. */
export const SETTLED_STATUSES = ['succeeded', 'refunded'] as const;

export function isSettled(p: SettledPayment | null | undefined): boolean {
  return !!p && (SETTLED_STATUSES as readonly string[]).includes(p.status);
}

export function holdIsMine(l: ListingHold | null, buyerId: string, now: Date): boolean {
  if (!l) return false;
  const until = l.reserved_until ? new Date(l.reserved_until) : null;
  return l.status === 'reserved' && l.reserved_by === buyerId && until != null && until > now;
}

// One in-flight setup per listing. A second mount while the first is still
// deciding awaits the same promise instead of starting its own intent.
const inFlight = new Map<string, Promise<SetupDecision<unknown>>>();

export async function decideCheckoutSetup<Intent>(
  input: { listingId: string; buyerId: string; mode: CheckoutMode },
  deps: SetupDeps<Intent>,
): Promise<SetupDecision<Intent>> {
  const key = `${input.listingId}:${input.buyerId}`;
  const existing = inFlight.get(key);
  if (existing) return existing as Promise<SetupDecision<Intent>>;

  const run = (async (): Promise<SetupDecision<Intent>> => {
    const now = deps.now?.() ?? new Date();

    // 1. Already paid? Then nothing here may create, init or present anything.
    const settled = await deps.fetchSettledPayment(input.listingId, input.buyerId);
    if (isSettled(settled)) return { kind: 'already_settled' };

    // 2. Buy Now must still hold the listing. (Only reachable when NOT paid.)
    if (input.mode === 'buy_now') {
      const listing = await deps.fetchListing(input.listingId);
      if (!listing) return { kind: 'reservation_unverifiable' };
      if (!holdIsMine(listing, input.buyerId, now)) return { kind: 'reservation_expired' };
    }

    // 3. Create (or server-side reuse) the intent — once.
    const intent = await deps.createIntent();
    return { kind: 'ready', intent };
  })();

  inFlight.set(key, run as Promise<SetupDecision<unknown>>);
  try {
    return await run;
  } finally {
    inFlight.delete(key);
  }
}

/** Test seam: forget any in-flight setup. */
export function _resetSetupInFlight(): void {
  inFlight.clear();
}
