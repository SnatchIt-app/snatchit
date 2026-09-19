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
 * settled and reached the success screen. It now has its own kinds, decided
 * ONLY by what the row establishes (owner, 2026-09-18, remedy (i)):
 *   refunded           — a CONFIRMED FULL refund: status `refunded`, dated, and
 *                        a recorded amount covering a known total.
 *   partially_refunded — a recorded amount above zero and below a known total.
 *   refund_unconfirmed — a refund is recorded but its amount is not established
 *                        (null/zero amount, unknown total, an undated full
 *                        amount, or a succeeded row carrying the full amount).
 *                        This is where EVERY production refund lands today: the
 *                        deployed webhook (a16a16dc) sets `refunded` +
 *                        `refunded_at` on any charge.refunded and writes no
 *                        amount. It replaced `refund_pending`, whose claims
 *                        ("being processed", "No purchase was made") no
 *                        reachable row supports.
 * None creates or presents an intent, and none is a purchase success.
 * `already_settled` now means `succeeded` ONLY, and succeeded is checked
 * before refunded so a buyer holding both rows is never told the wrong one.
 *
 * F8 (A's review of this batch). The payments RC's refund writer (not yet in
 * production) (`record_payment_refund`, 20260906120000 :518-522) flips status to
 * `refunded` and stamps `refunded_at` only when the refunded amount reaches
 * the total. A PARTIAL refund therefore leaves a `succeeded` row carrying
 * `amount_refunded_cents > 0` and no date — which used to reach the success
 * screen with no sign that money came back. That row is `partially_refunded`
 * here, and the screen says only the amount recorded.
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

/**
 * The settled-payment read's result (F-CHK-READERR): rows, or an error that must never be read as "no payment".
 * Produced by readSettledPayments (settledRead.ts).
 */
export type SettledRead = { rows: SettledPayment[] } | { error: { code: string | null; message: string } };

/**
 * The re-validation listing read's result (D's R2): the row, a successful read with no row (`listing: null`), or an
 * error that must never be read as "no row". Produced by readListingHold (settledRead.ts).
 */
export type ListingRead = { listing: ListingHold | null } | { error: { code: string | null; message: string } };

export type SetupDecision<Intent> =
  | { kind: 'payment_status_unknown'; detail: string }
  | { kind: 'already_settled' }
  | RefundState
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

/**
 * A FULL refund is confirmed only when it is dated AND a recorded amount covers a
 * known total. An unknown amount or total establishes nothing about the size of
 * the refund — the production row shape — so it is not confirmed.
 */
export function isRefundConfirmed(p: SettledPayment): boolean {
  if (p.status !== 'refunded') return false;
  if (!p.refunded_at) return false;
  if (p.total != null && p.amount_refunded_cents != null) return p.amount_refunded_cents >= p.total;
  return false;
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

/** The recorded refunded amount when it is a positive number; null when absent or zero. */
export function recordedRefundCents(p: SettledPayment | null | undefined): number | null {
  const c = p?.amount_refunded_cents;
  return typeof c === 'number' && c > 0 ? c : null;
}

export type RefundKind = 'partially_refunded' | 'refunded' | 'refund_unconfirmed';
export type SettledKind = 'already_settled' | RefundKind;

/** What the refund screen shows. The neutral kind never carries an amount. */
export type RefundState =
  | { kind: 'partially_refunded'; refundedCents: number }
  | { kind: 'refunded'; refundedCents: number }
  | { kind: 'refund_unconfirmed'; refundedCents: null };

export function settledKind(p: SettledPayment | null): SettledKind | null {
  if (!p) return null;
  const cents = recordedRefundCents(p);
  const total = p.total ?? null;
  if (p.status === 'succeeded') {
    if (cents == null) return 'already_settled';
    if (total != null && cents < total) return 'partially_refunded';
    // The full amount on a succeeded row, or an amount with no known total: "part of this payment" is not
    // established, and neither is a full refund.
    return 'refund_unconfirmed';
  }
  if (p.status === 'refunded') {
    if (isRefundConfirmed(p)) return 'refunded';
    if (cents != null && total != null && cents < total) return 'partially_refunded';
    return 'refund_unconfirmed';
  }
  return null;
}

/** The refund screen's state for a settled row, or null when there is no refund to show. */
export function refundStateFor(p: SettledPayment | null): RefundState | null {
  const kind = settledKind(p);
  if (!kind || kind === 'already_settled') return null;
  const cents = recordedRefundCents(p);
  // A confirmed kind always has an amount (settledKind requires one); the null check only satisfies the type and,
  // if it were ever reached, degrades to the neutral kind rather than presenting a missing amount.
  if (kind === 'refund_unconfirmed' || cents == null) return { kind: 'refund_unconfirmed', refundedCents: null };
  return { kind, refundedCents: cents };
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
    //    F-CHK-READERR (owner, 2026-09-18): a failed read is NOT "no payment". Stop here — before the hold and
    //    before any intent — and say only that the status couldn't be checked.
    let rows: Awaited<ReturnType<SetupDeps<Intent>['fetchSettledPayment']>>;
    try {
      rows = await deps.fetchSettledPayment(input.listingId, input.buyerId);
    } catch (e) {
      return { kind: 'payment_status_unknown', detail: e instanceof Error ? e.message : String(e) };
    }
    const settled = pickSettled(rows);
    if (settledKind(settled) === 'already_settled') return { kind: 'already_settled' };
    const refund = refundStateFor(settled);
    if (refund) return refund;

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

export type RevalidationOutcome =
  | { kind: 'payment_status_unknown'; detail: string }
  | { kind: 'already_settled' }
  | RefundState
  | { kind: 'reservation_unverifiable'; detail: string }
  | { kind: 'held'; reservedUntilMs: number | null }
  | { kind: 'lost' };

/**
 * The server re-validation (A-04): settled first, then the hold. Pure, with injected reads, so both checkout entry
 * paths can be driven by tests and by A's end-to-end rehearsal. F-CHK-READERR: a failed settled read stops here —
 * the listing is never read, so an error can never become "held" (Pay re-armed) or "lost" ("Nothing was charged").
 * D's R2 (owner, 2026-09-19): a failed LISTING read — returned or thrown — is `reservation_unverifiable`, never
 * "lost" and never "held"; only a successful read decides the hold.
 */
export async function decideRevalidation(
  input: { buyerId: string; isBuyNow: boolean; now: Date },
  deps: { readSettled: () => Promise<SettledRead>; readListing: () => Promise<ListingRead> },
): Promise<RevalidationOutcome> {
  let read: SettledRead;
  try {
    read = await deps.readSettled();
  } catch (e) {
    read = { error: { code: null, message: e instanceof Error ? e.message : String(e) } };
  }
  if ('error' in read) return { kind: 'payment_status_unknown', detail: `${read.error.code ?? 'no-code'}: ${read.error.message}` };
  const settled = pickSettled(read.rows);
  if (settledKind(settled) === 'already_settled') return { kind: 'already_settled' };
  const refund = refundStateFor(settled);
  if (refund) return refund;
  if (!input.isBuyNow) return { kind: 'held', reservedUntilMs: null }; // an auction winner holds no reservation
  let lread: ListingRead;
  try {
    lread = await deps.readListing();
  } catch (e) {
    lread = { error: { code: null, message: e instanceof Error ? e.message : String(e) } };
  }
  if ('error' in lread) return { kind: 'reservation_unverifiable', detail: `${lread.error.code ?? 'no-code'}: ${lread.error.message}` };
  const listing = lread.listing;
  if (listing && holdIsMine(listing, input.buyerId, input.now)) {
    return { kind: 'held', reservedUntilMs: new Date(listing.reserved_until as string).getTime() };
  }
  return { kind: 'lost' };
}

/** Test seam: forget any in-flight setup. */
export function _resetSetupInFlight(): void {
  inFlight.clear();
}
