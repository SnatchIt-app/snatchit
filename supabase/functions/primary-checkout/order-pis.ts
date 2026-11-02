/**
 * supabase/functions/primary-checkout/order-pis.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * ONE ORDER → ITS PAYMENTINTENTS, and what to do with them once the order's
 * holds have lapsed. Registry 198, A's edge side (DESIGN-198-FINAL §4.2).
 *
 * TWO CALLERS, ONE SEARCH, so they can never disagree about which PaymentIntent
 * belongs to an order:
 *
 *   • primary-checkout        — `recoverReplayQuote` (§11, the replay path) and
 *                               the A-2 refusal of a lapsed replay (§4.2 A-2:
 *                               "a best-effort cancel of the order's live
 *                               PaymentIntent (the A-6 canceller)").
 *   • primary-lapse-canceller — the A-6 scheduled job (§4.2 A-6 steps 2-3).
 *
 * §4.2 A-6 step 2 says "find the PaymentIntent using recoverReplayQuote's
 * search". `searchOrderPaymentIntents` IS that search, moved here unchanged in
 * behaviour (same selector, same newest-first cap, same 404 / non-404 / throw
 * rules, same metadata authority) rather than copied, so a second copy cannot
 * drift from the first.
 *
 * IMPORT-FREE apart from `../stripe-webhook/native.ts`, which is itself
 * import-free: the supabase client and `stripeFetchRaw` are PASSED IN. That is
 * what lets vitest load the real module (tests/helpers/edge-vm.ts binds a
 * sibling `./x.ts` import from the real file) and lets `tsc` check it, while
 * both edges keep their https imports. No `Deno` global is read here.
 *
 * The cancel_pending_order command key and reason are IMPORTED from the
 * webhook's own module, never re-typed: the A-6 cancel of an already-canceled
 * PI must present the byte-identical key the webhook's `payment_intent.canceled`
 * branch presents (stripe-webhook/index.ts:1230-1234), so whichever arrives
 * second is a `noop_replay` under the same audit identity.
 */
import { buildCancelCommandKey, CANCEL_REASON_PAYMENT_FAILED } from '../stripe-webhook/native.ts';

export { CANCEL_REASON_PAYMENT_FAILED };

/** The wire token (primary-checkout/index.ts:306, :325; stripe-webhook/native.ts:35-39). */
export const NATIVE_PRIMARY = 'native_primary';

/** `_shared/stripe.ts`'s `stripeFetchRaw`, by shape. */
export type StripeRawFetch = (
  path: string,
  init?: { method?: 'GET' | 'POST' | 'DELETE'; body?: Record<string, string>; idempotencyKey?: string },
) => Promise<{ ok: boolean; status: number; data: unknown }>;

/**
 * The slice of a supabase-js client this module touches, by shape. Loose on
 * purpose: the real client's builder types live behind an https import this
 * module must not take.
 */
// deno-lint-ignore no-explicit-any
export type ServiceClient = { from: (table: string) => any };
// deno-lint-ignore no-explicit-any
export type RpcClient = { rpc: (fn: string, params: Record<string, unknown>) => any };

// ═══════════════════════════════════════════════════════════════════════════
// THE SEARCH
// ═══════════════════════════════════════════════════════════════════════════

export type CandidateRow = {
  amount: number; buyer_fee: number; total: number;
  status: string; stripe_payment_intent_id: string | null;
};

export type ConfirmedPi = {
  row: CandidateRow; piId: string; status: string; clientSecret: string | null; sessionId: string | null;
};

export type PiSearch = { kind: 'error'; detail: string } | { kind: 'looked'; confirmed: ConfirmedPi[] };

/**
 * The replay path's selector — UNCHANGED from recoverReplayQuote before the
 * extraction: a PI it can hand back, or report paid.
 */
export const REPLAY_CANDIDATE_STATUSES: readonly string[] = ['pending', 'processing', 'succeeded'];

/**
 * A-6's selector — DEVIATION D1 from §4.2 A-6 step 2 (A's, sent to D for
 * ratification; see `cancelLapsedOrderPaymentIntents`). Step 2 names "status
 * pending or failed"; this is that pair plus `succeeded` and `processing`.
 *
 * Why `succeeded`: the webhook claims the payments row as `succeeded` BEFORE it
 * calls finalize (stripe-webhook/index.ts:907-914). Step 3's `succeeded` arm is
 * reachable under the literal filter only in the window before that claim
 * lands; after it, the row drops out of a pending-or-failed read. A lapsed
 * order whose payment won and whose finalize raised `refund_required` stays
 * pending and stays in the lapse report (O13) — under the literal filter it
 * would read as `no_pi` and `lapsed_order_paid` would never be alerted, and a
 * live sibling PI would be cancelled (see D3).
 * Why `processing`: a superset that costs nothing — no native writer sets it
 * today (the PI's own status is what step 3 reads), but a row marked so can
 * never be mistaken for absence. Same set as the replay selector, plus failed.
 * `failed` is the design's: where a non-terminal decline and a canceled PI
 * leave the row (stripe-webhook/index.ts:1199-1204). The replay selector above
 * is deliberately left as it was.
 */
export const LAPSE_CANDIDATE_STATUSES: readonly string[] = ['pending', 'processing', 'succeeded', 'failed'];

/**
 * Find the PaymentIntents minted for ONE native primary order.
 *
 * HOW, GIVEN THERE IS NO `payments.order_id`. There is no such column and there
 * never will be (EDGE_FUNCTION_SPEC §9 recon #1), and `kernel.payment_native`
 * is not written until finalize, so no order→payment link exists before
 * payment. The lookup is therefore two-stage:
 *
 *   1. CANDIDATES — a narrow selector on facts known without that link:
 *      (buyer_id, mode='native_primary', amount=face, status ∈ `statuses`).
 *      This is a FILTER, NOT an identification: two pending orders for the same
 *      buyer at the same face total would both match.
 *   2. CONFIRMATION — each candidate's PaymentIntent is retrieved and its
 *      `metadata.order_id` must equal this order, and `metadata.rail` must be
 *      `native_primary`. **The PI metadata is the authority**; the DB selector
 *      only narrows the search. That is what makes this exact, not heuristic.
 *
 * Stripe's PaymentIntent *search* API was rejected: it is eventually consistent
 * (~a minute), and the dominant replay case is a double-tap seconds apart,
 * which search would miss.
 *
 * `ruledOut` carries PI ids a previous look in the SAME caller already showed
 * cannot be this order's (404, or metadata naming another order or rail).
 * Neither can change (we never edit metadata after the mint), so a re-read does
 * not spend a second Stripe GET on them.
 *
 * Both reads are grant-legal: `public.payments` is in `public`, where
 * service_role holds table privileges (RT-A-6), and Stripe is an external API.
 */
export async function searchOrderPaymentIntents(
  deps: { service: ServiceClient; stripeFetchRaw: StripeRawFetch },
  q: { orderId: string; faceMinor: number; buyerId: string; statuses: readonly string[] },
  ruledOut: Set<string> = new Set(),
): Promise<PiSearch> {
  let candidates: CandidateRow[];
  try {
    const { data, error } = await deps.service
      .from('payments')
      .select('amount, buyer_fee, total, status, stripe_payment_intent_id')
      .eq('buyer_id', q.buyerId)
      .eq('mode', NATIVE_PRIMARY)
      .eq('amount', q.faceMinor)
      .in('status', [...q.statuses])
      // NEWEST FIRST, BEFORE THE CAP (primary-checkout-4a). `succeeded` rows
      // accumulate for good, so a repeat buyer at one price point (a weekly
      // $25 GA ticket) can hold 10+ historic matches; with no ORDER BY the cap
      // could return only those and leave this order's row out, answering a
      // live PI 409 quote_unavailable. A replay is for a recent attempt, so
      // its row is among the newest.
      .order('created_at', { ascending: false })
      // Bounded: this drives one Stripe GET per candidate. A buyer with more
      // than a handful of concurrent same-priced native orders is pathological.
      .limit(10);
    if (error) return { kind: 'error', detail: (error as { message?: string }).message ?? String(error) };
    candidates = (data ?? []) as CandidateRow[];
  } catch (err) {
    return { kind: 'error', detail: err instanceof Error ? err.message : String(err) };
  }

  const confirmed: ConfirmedPi[] = [];

  for (const row of candidates) {
    const rowPiId = row.stripe_payment_intent_id;
    if (!rowPiId || ruledOut.has(rowPiId)) continue;
    // A probe that THROWS (network failure, timeout) is "could not look" too,
    // the same as a 5xx below. Uncaught, it escaped to the top-level catch: a
    // bare 500 'Internal server error' instead of the retryable 503
    // replay_recovery_failed + Retry-After that keeps the client on the SAME
    // key.
    let probe: Awaited<ReturnType<StripeRawFetch>>;
    try {
      probe = await deps.stripeFetchRaw(`/payment_intents/${rowPiId}`);
    } catch (err) {
      return {
        kind:   'error',
        detail: `stripe GET payment_intent ${rowPiId} threw: ${err instanceof Error ? err.message : String(err)}`,
      };
    }
    // 404: Stripe has no such PI, so it cannot confirm anything — skip it.
    // ANY OTHER failure (429, 5xx, auth) means "could not look", not "not
    // ours" (primary-checkout-4b). Skipping it would turn a transient Stripe
    // fault into `none` → 409 quote_unavailable, which sends the client to a
    // NEW command_key: a second order and a second PI on the same holds.
    if (probe.status === 404) { ruledOut.add(rowPiId); continue; }
    if (!probe.ok) {
      return { kind: 'error', detail: `stripe GET payment_intent ${rowPiId} answered ${probe.status}` };
    }
    const pi = probe.data as {
      id?: string; status?: string; client_secret?: string; metadata?: Record<string, string>;
    };
    // THE AUTHORITATIVE CHECK. Both must match: the order this PI was minted
    // for, and the rail that minted it.
    if (pi.metadata?.order_id !== q.orderId || pi.metadata?.rail !== NATIVE_PRIMARY || !pi.id) {
      ruledOut.add(rowPiId);
      continue;
    }
    confirmed.push({
      row, piId: pi.id, status: pi.status ?? 'unknown', clientSecret: pi.client_secret ?? null,
      sessionId: pi.metadata?.session_id ?? null,
    });
  }
  return { kind: 'looked', confirmed };
}

// ═══════════════════════════════════════════════════════════════════════════
// THE LAPSE CANCELLER (§4.2 A-6 steps 2-3; reused by A-2)
// ═══════════════════════════════════════════════════════════════════════════

/** One lapsed order, as `lapsed_orders[]` (§3.3) or a replay (A-2) names it. */
export type LapseTarget = {
  orderId:   string;
  buyerId:   string;
  /** `order.total_minor` — FACE, which is what `payments.amount` holds. */
  faceMinor: number;
  /**
   * The order's own session, from the lapse report. A-6 step 2 confirms
   * `metadata.session_id` against it. `null` skips that check: checkout's A-2
   * knows only the REQUEST's session, which a command_key replayed across
   * sessions (C16) makes differ from the order's, and the order id from the
   * RPC is already the authority.
   */
  sessionId: string | null;
};

export type LapseOutcome =
  /** ≥1 live PI was cancelled at Stripe; the webhook's `payment_intent.canceled` branch writes 'cancelled' (O11). */
  | { kind: 'cancel_requested'; piIds: string[] }
  /** every PI was already canceled and the order was still pending: cancel_pending_order was called. */
  | { kind: 'order_cancelled'; piId: string; status: string }
  /** ≥1 PI succeeded. finalize has decided; nothing is cancelled. */
  | { kind: 'paid'; piIds: string[] }
  /** ≥1 PI is processing. Nothing is cancelled; the next run decides. */
  | { kind: 'in_flight'; piIds: string[] }
  /** no PI confirms this order. A-4's rule: leave it (see `no_pi` below). */
  | { kind: 'no_pi' }
  /**
   * a state this rail never produces. Nothing is touched. `piId` names the PI
   * that showed it, so an alert can name both the order and the PI. Permanent:
   * a caller must not answer it with a retry-the-same-key 503 (A-2 R5).
   */
  | { kind: 'anomaly'; piId: string; detail: string }
  /** could not look, or a Stripe/DB write failed. Nothing more is attempted; the next run retries. */
  | { kind: 'error'; detail: string };

/** §4.2 A-6 step 3: the statuses a cancel is issued for. */
const CANCELLABLE = new Set(['requires_payment_method', 'requires_confirmation', 'requires_action']);

/** §4.2 A-6 step 3: "Idempotency-Key `pi_lapse_cancel_{pi}`". */
export function lapseCancelIdempotencyKey(piId: string): string {
  return `pi_lapse_cancel_${piId}`;
}

/** §4.2 A-3: "p_command_key:'edge_abort:'+order_id". */
export function edgeAbortCommandKey(orderId: string): string {
  return `edge_abort:${orderId}`;
}

/**
 * §4.2 A-6 steps 2-3 for ONE lapsed order.
 *
 * ── DEVIATIONS FROM §4.2 A-6 STEPS 2-3 (A's; sent to D for ratification as an
 * amendment to DESIGN-198-FINAL §4.2 A-6; each is pinned in
 * tests/primary-lapse-canceller.test.ts) ──────────────────────────────────────
 *   D1. CANDIDATE STATUSES WIDENED. Step 2's "pending or failed" becomes
 *       pending, processing, succeeded, failed (`LAPSE_CANDIDATE_STATUSES`).
 *       Reason: the webhook marks the row `succeeded` before finalize, so the
 *       literal filter loses a PAID lapsed order once that claim lands — an O13
 *       refund_required order would read as no_pi, never alert, and its live
 *       sibling would be cancelled (D3).
 *   D2. ORDER-LEVEL PRECEDENCE. Step 3 is written per PaymentIntent; here ONE
 *       precedence (below) decides for the whole order. Reason: an order can
 *       have more than one PI (the salted re-mint after a canceled idempotent
 *       replay, primary-checkout §11; a Stripe Customer re-created mid-window),
 *       and per-PI rules applied independently undo each other.
 *   D3. NEVER CANCEL A SIBLING OF A SUCCEEDED OR PROCESSING PI. Reason: the
 *       sibling's cancel fires `payment_intent.canceled`, whose branch calls
 *       cancel_pending_order on this still-pending order, and the payment that
 *       won (or is about to) lands on a cancelled order — charged, no ticket
 *       (§10 risk 13).
 *
 * The ORDER-level precedence (D2) that keeps the per-PI rules from undoing
 * each other:
 *
 *   1. a PI naming another session (when the report gave one) → `anomaly`.
 *      Identity is in doubt, so nothing is acted on.
 *   2. any `succeeded` (PI, or its payments row) → `paid`, and NOTHING is
 *      cancelled — not even a sibling PI still awaiting a method. Cancelling
 *      the sibling would fire `payment_intent.canceled`, whose branch calls
 *      cancel_pending_order on this still-pending order, and the payment that
 *      won would land on a cancelled order (§10 risk 13). "succeeded: do
 *      nothing. finalize has already decided."
 *   3. any status this rail never produces (e.g. requires_capture — every PI
 *      here is automatic-capture) → `anomaly`, nothing touched.
 *   4. any `processing` → `in_flight`: "skip and retry on the next run". Its
 *      siblings are left alone for the same reason as 2.
 *   5. any requires_payment_method / requires_confirmation / requires_action →
 *      POST /payment_intents/{id}/cancel, cancellation_reason=abandoned,
 *      Idempotency-Key pi_lapse_cancel_{id}, for EACH such PI. The webhook's
 *      `payment_intent.canceled` branch then calls cancel_pending_order (O11).
 *      A refused cancel (the buyer's confirm won the race, R9) is `error`; the
 *      next run sees the PI's new status.
 *   6. every PI `canceled` while the order is still pending → cancel_pending_
 *      order('payment_failed', buildCancelCommandKey(order, pi)) with the
 *      newest PI — the key the webhook would have used for it.
 *   7. none → `no_pi`. A-4's DEFAULT, not its option: the order is left as it
 *      is. Absence of a PI here is absence of EVIDENCE (the candidate read is a
 *      capped filter, and the authoritative Stripe search A-4's option needs
 *      was rejected above), and §10 risk 6 calls cancel-after-proof unsafe
 *      without one. Its holds have already lapsed, so it pins no capacity.
 */
export async function cancelLapsedOrderPaymentIntents(
  deps: { service: ServiceClient; venueService: () => RpcClient; stripeFetchRaw: StripeRawFetch },
  t: LapseTarget,
): Promise<LapseOutcome> {
  const found = await searchOrderPaymentIntents(
    deps,
    { orderId: t.orderId, faceMinor: t.faceMinor, buyerId: t.buyerId, statuses: LAPSE_CANDIDATE_STATUSES },
  );
  if (found.kind === 'error') return found;
  const pis = found.confirmed;
  if (pis.length === 0) return { kind: 'no_pi' };

  if (t.sessionId !== null) {
    const off = pis.find((c) => c.sessionId !== t.sessionId);
    if (off) return { kind: 'anomaly', piId: off.piId, detail: `pi ${off.piId} names session ${off.sessionId ?? '<none>'}, not the order's` };
  }

  const isPaid = (c: ConfirmedPi) => c.status === 'succeeded' || c.row.status === 'succeeded';
  const paid = pis.filter(isPaid);
  if (paid.length > 0) return { kind: 'paid', piIds: paid.map((c) => c.piId) };

  const unknown = pis.find((c) => c.status !== 'processing' && c.status !== 'canceled' && !CANCELLABLE.has(c.status));
  if (unknown) return { kind: 'anomaly', piId: unknown.piId, detail: `pi ${unknown.piId} has status ${unknown.status}` };

  const inFlight = pis.filter((c) => c.status === 'processing');
  if (inFlight.length > 0) return { kind: 'in_flight', piIds: inFlight.map((c) => c.piId) };

  const live = pis.filter((c) => CANCELLABLE.has(c.status));
  if (live.length > 0) {
    for (const c of live) {
      let res: Awaited<ReturnType<StripeRawFetch>>;
      try {
        res = await deps.stripeFetchRaw(`/payment_intents/${c.piId}/cancel`, {
          method:         'POST',
          body:           { cancellation_reason: 'abandoned' },
          idempotencyKey: lapseCancelIdempotencyKey(c.piId),
        });
      } catch (err) {
        return { kind: 'error', detail: `stripe cancel ${c.piId} threw: ${err instanceof Error ? err.message : String(err)}` };
      }
      if (!res.ok) return { kind: 'error', detail: `stripe cancel ${c.piId} answered ${res.status}` };
    }
    return { kind: 'cancel_requested', piIds: live.map((c) => c.piId) };
  }

  // Every confirmed PI is canceled and the order is still pending (it is in the
  // lapse report, or the replay said so): the webhook's cancel either has not
  // landed or failed. Newest first (the candidate read's order), so pis[0].
  const dead = pis[0];
  try {
    const { data, error } = await deps.venueService().rpc('cancel_pending_order', {
      p_order_id:    t.orderId,
      p_reason_code: CANCEL_REASON_PAYMENT_FAILED,
      p_command_key: buildCancelCommandKey(t.orderId, dead.piId),
    });
    if (error) return { kind: 'error', detail: `cancel_pending_order: ${(error as { message?: string }).message ?? String(error)}` };
    return { kind: 'order_cancelled', piId: dead.piId, status: (data as { status?: string } | null)?.status ?? 'cancelled' };
  } catch (err) {
    return { kind: 'error', detail: `cancel_pending_order threw: ${err instanceof Error ? err.message : String(err)}` };
  }
}
