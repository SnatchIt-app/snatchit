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
 * PREMIUM BATCH 1 (A-03, CFT-308). A `refunded` payment used to count as
 * settled and reached the success screen. It now has its own kinds:
 *   refunded        — a CONFIRMED refund: `refunded_at` set and the refunded
 *                     amount covers the total. "Payment refunded" is allowed.
 *   refund_pending  — status says refunded but the refund is not confirmed
 *                     complete (no `refunded_at`, or a partial amount). Says a
 *                     refund is in progress; promises nothing about the bank.
 * Neither creates or presents an intent, and neither is a purchase success.
 * `already_settled` now means `succeeded` ONLY, and succeeded is checked
 * before refunded so a buyer holding both rows is never told the wrong one.
 *
 * F8 (A's review of this batch). The server's single refund writer
 * (`record_payment_refund`, 20260906120000 :518-522) flips status to
 * `refunded` and stamps `refunded_at` only when the refunded amount reaches
 * the total. A PARTIAL refund therefore leaves a `succeeded` row carrying
 * `amount_refunded_cents > 0` and no date — which used to reach the success
 * screen with no sign that money came back. That row is `partially_refunded`
 * here: the order stands, and the screen says what was returned. Because of
 * the same writer, a `refunded` row is always dated and full today, so
 * `refund_pending` is defensive: kept as insurance against a diverging writer.
 *
 * PREMIUM BATCH 1 (CFT-301, D9-UX-1). `reservation_expired` is renamed
 * `not_held`: the server cannot tell a hold that ran out from one that was
 * released early (both leave the listing active with the hold fields null),
 * so the decision no longer claims to know. The screen chooses the wording
 * from what it does know.
 *
 * RE-ENTRY. Two rapid mounts for the same listing share one in-flight setup, so
 * at most one intent is created no matter how many times the route re-enters.
 */

export type CheckoutMode = 'buy_now' | 'auction';

export interface SettledPayment {
  status: string;
  /** Set only when the refund is confirmed complete on our side. */
  refunded_at?: string | null;
  amount_refunded_cents?: number | null;
  total?: number | null;
}

export interface ListingHold {
  status: string;
  reserved_by: string | null;
  reserved_until: string | null;
}

export interface SetupDeps<Intent> {
  /**
   * The buyer's own settled-status payment rows for this listing (RLS: own
   * rows only). May return several; `pickSettled` chooses. Returning a single
   * row or null is still accepted.
   */
  fetchSettledPayment(listingId: string, buyerId: string): Promise<SettledPayment | SettledPayment[] | null>;
  /** Fresh listing hold state. Buy Now only. */
  fetchListing(listingId: string): Promise<ListingHold | null>;
  /** The edge call that creates (or reuses) the PaymentIntent. */
  createIntent(): Promise<Intent>;
  /** Injected for tests; defaults to wall clock. */
  now?: () => Date;
}

export type SetupDecision<Intent> =
  | { kind: 'already_settled' }
  | { kind: 'partially_refunded'; refundedCents: number }
  | { kind: 'refunded' }
  | { kind: 'refund_pending' }
  | { kind: 'reservation_unverifiable' }
  | { kind: 'not_held' }
  | { kind: 'ready'; intent: Intent };

/**
 * Payment statuses this route must never create or present an intent for.
 * `refunded` stays here on purpose: whether a refunded buyer may buy a
 * relisted listing again is a product question, and blocking is the safe
 * default until it is decided.
 */
export const SETTLED_STATUSES = ['succeeded', 'refunded'] as const;

export function isSettled(p: SettledPayment | null | undefined): boolean {
  return !!p && (SETTLED_STATUSES as readonly string[]).includes(p.status);
}

/** A refund is confirmed only when it is dated and covers the total. */
export function isRefundConfirmed(p: SettledPayment): boolean {
  if (p.status !== 'refunded') return false;
  if (!p.refunded_at) return false;
  if (p.total != null && p.amount_refunded_cents != null) return p.amount_refunded_cents >= p.total;
  return true;
}

/**
 * Succeeded outranks refunded. The old lookup took `limit(1)` with no order,
 * so a buyer with both rows got whichever the database returned first.
 */
export function pickSettled(rows: SettledPayment | SettledPayment[] | null | undefined): SettledPayment | null {
  const list = rows == null ? [] : Array.isArray(rows) ? rows : [rows];
  const settled = list.filter(isSettled);
  return settled.find((p) => p.status === 'succeeded') ?? settled.find((p) => p.status === 'refunded') ?? null;
}

/** Cents returned on a succeeded row, i.e. a partial refund; 0 when none. */
export function partialRefundCents(p: SettledPayment | null | undefined): number {
  if (!p || p.status !== 'succeeded') return 0;
  const c = p.amount_refunded_cents ?? 0;
  return c > 0 ? c : 0;
}

export type SettledKind = 'already_settled' | 'partially_refunded' | 'refunded' | 'refund_pending';

export function settledKind(p: SettledPayment | null): SettledKind | null {
  if (!p) return null;
  if (p.status === 'succeeded') return partialRefundCents(p) > 0 ? 'partially_refunded' : 'already_settled';
  if (p.status === 'refunded') return isRefundConfirmed(p) ? 'refunded' : 'refund_pending';
  return null;
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

    // 1. Already paid, or refunded? Then nothing here may create, init or
    //    present anything. Succeeded is preferred over refunded.
    const settled = pickSettled(await deps.fetchSettledPayment(input.listingId, input.buyerId));
    const kind = settledKind(settled);
    if (kind === 'partially_refunded') return { kind, refundedCents: partialRefundCents(settled) };
    if (kind) return { kind };

    // 2. Buy Now must still hold the listing. (Only reachable when NOT paid.)
    if (input.mode === 'buy_now') {
      const listing = await deps.fetchListing(input.listingId);
      if (!listing) return { kind: 'reservation_unverifiable' };
      if (!holdIsMine(listing, input.buyerId, now)) return { kind: 'not_held' };
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
