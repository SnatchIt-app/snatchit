/**
 * stripe-webhook/native.ts — pure, dependency-free decision logic for the
 * NATIVE PRIMARY rail branch and for the ORGANIZATION arm of `account.updated`.
 *
 * WHY THIS FILE EXISTS SEPARATELY
 *   `index.ts` imports over https (deno.land, esm.sh), which vitest cannot
 *   load. Every decision that decides whether tickets are minted, whether an
 *   order is cancelled, and whether Stripe retries lives HERE, import-free, so
 *   `tests/stripe-webhook-native.test.ts` can exercise it directly. Same split
 *   as `refund-execute/executor.ts` vs its `index.ts`, and
 *   `_shared/payout-logic.ts` vs `_shared/payouts.ts`.
 *
 * THE ONE RULE THAT ORGANISES EVERYTHING BELOW
 *   A non-2xx from this webhook means "Stripe, deliver this again". That is
 *   only ever the right answer when a REDELIVERY COULD PLAUSIBLY SUCCEED.
 *   Stripe's event payload is a SNAPSHOT: a redelivery carries byte-identical
 *   metadata. So a defect IN THE EVENT (missing order_id, rail/mode
 *   disagreement, a buyer who is erased, money that was already refunded) can
 *   never be fixed by redelivery — retrying it just hammers the endpoint for
 *   three days and buries the alert. Those are ACKed and ALERTED.
 *   A defect in OUR WORLD (a missing grant, an absent signing key, a
 *   serialization failure, a DB that is down) IS fixable inside the retry
 *   window, and those are retried — that is the whole reason Stripe retries.
 *
 *   Every classifier below returns `{ ack, alert, reason }` and nothing else.
 *   `ack:true`  → 200 + `complete_stripe_webhook_event` (terminal, never seen again)
 *   `ack:false` → non-2xx + `fail_stripe_webhook_event` (lease released, retried)
 *   `alert:true` → `captureException` regardless of which of the two it is.
 */

// ─────────────────────────────────────────────────────────────────────────────
// The frozen wire contract (primary-checkout/index.ts:176-278)
// ─────────────────────────────────────────────────────────────────────────────

/** THE dispatch token. `metadata.rail` and `metadata.mode` both carry it. */
export const RAIL_NATIVE_PRIMARY = 'native_primary';

/** The `public.payments.mode` member for this rail (093 widened CHECK). */
export const PAYMENTS_MODE_NATIVE_PRIMARY = 'native_primary';

/** `venue.cancel_pending_order` reason codes are a CLOSED SET OF ONE (082:§20.7.9). */
export const CANCEL_REASON_PAYMENT_FAILED = 'payment_failed';

/** `kernel.organization.connect_transfers_active` is `capabilities.transfers = 'active'`. */
export const TRANSFERS_CAPABILITY_ACTIVE = 'active';

/** connect-onboarding stamps this on every ORG Connect account (:551). */
export const PLANE_ORGANIZATION = 'organization';

export type StripeMetadata = Record<string, unknown> | null | undefined;

/**
 * The outcome of every decision in this module. Deliberately only two bits:
 * whether Stripe gets a 2xx, and whether a human is told.
 */
export interface Decision {
  /** true → 200 + complete (terminal). false → non-2xx + fail (Stripe retries). */
  ack: boolean;
  /** true → captureException. Independent of `ack`. */
  alert: boolean;
  /** Stable machine-readable token; goes in the log line and the response body. */
  reason: string;
}

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_RE.test(value);
}

/** `acct_…` — the same shape `kernel.sync_org_connect_state` enforces (093:1337). */
const ACCOUNT_REF_RE = /^acct_[A-Za-z0-9]+$/;

export function isConnectAccountRef(value: unknown): value is string {
  return typeof value === 'string' && ACCOUNT_REF_RE.test(value);
}

function str(metadata: StripeMetadata, key: string): string {
  const v = metadata?.[key];
  return typeof v === 'string' ? v.trim() : '';
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. RAIL DISPATCH — the third branch
// ─────────────────────────────────────────────────────────────────────────────

export type RailRoute =
  /** `rail === mode === 'native_primary'`. Take the native branch. */
  | { route: 'native_primary' }
  /** No `rail` key and no native claim. The legacy resale selector owns it. */
  | { route: 'legacy_resale' }
  /** One of rail/mode claims native and the other disagrees. Never dispatch. */
  | { route: 'rail_mode_mismatch'; rail: string; mode: string }
  /** A non-empty rail we do not implement (e.g. a future `native_resale`). */
  | { route: 'unknown_rail'; rail: string };

/**
 * The CLOSED, ORDERED selection pinned by primary-checkout:176-247.
 *
 *   1. rail === 'native_primary'  → native (assert mode === rail first).
 *   2. rail absent / ''           → legacy resale, which runs its own
 *                                   {buy_now, auction} selection.
 *   3. rail anything else         → UNKNOWN. NEVER fall through to resale;
 *                                   a future rail must not run a resale money
 *                                   path just because we have not shipped it.
 *
 * The one addition to that rule: `rail` absent while `mode === 'native_primary'`.
 * The pinned rule sends that to the legacy selector, whose third branch is an
 * explicit error return — i.e. it fails closed, which is correct, but it fails
 * closed by returning NON-2XX FOREVER. It is the same event every redelivery,
 * so it can never resolve. We classify it as a mismatch and ACK-with-alert
 * instead, which fails equally closed (no money path is taken) and stops the
 * three-day retry storm.
 */
export function resolveRail(metadata: StripeMetadata): RailRoute {
  const rail = str(metadata, 'rail');
  const mode = str(metadata, 'mode');

  if (rail === RAIL_NATIVE_PRIMARY) {
    // "THE TWO MUST NEVER DISAGREE. A PI where rail !== mode was not written
    // by this function; treat that as tampering or corruption and fail closed."
    return mode === RAIL_NATIVE_PRIMARY ? { route: 'native_primary' } : { route: 'rail_mode_mismatch', rail, mode };
  }

  if (rail === '') {
    // A `mode` that claims the direct rail with no `rail` key was not written
    // by primary-checkout, which always writes both.
    if (mode === RAIL_NATIVE_PRIMARY) return { route: 'rail_mode_mismatch', rail, mode };
    return { route: 'legacy_resale' };
  }

  return { route: 'unknown_rail', rail };
}

/**
 * What to do with a route that is neither native nor legacy.
 *
 * `unknown_rail` RETRIES on purpose: the pinned rule says a future rail must
 * "fail closed, alert, and leave the event for replay", and a rail we have not
 * deployed yet is exactly the case a retry window exists for. It is unreachable
 * today — no function mints a PI with any other rail value.
 *
 * `rail_mode_mismatch` ACKs on purpose: no deploy can change what that event
 * says, so a retry is pure noise on top of an incident that already needs a
 * human.
 */
export function dispositionForRoute(route: RailRoute): Decision {
  switch (route.route) {
    case 'rail_mode_mismatch':
      return { ack: true, alert: true, reason: 'rail_mode_mismatch' };
    case 'unknown_rail':
      return { ack: false, alert: true, reason: 'unknown_rail' };
    default:
      return { ack: true, alert: false, reason: route.route };
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. NATIVE METADATA — what the branch is allowed to know
// ─────────────────────────────────────────────────────────────────────────────

export interface NativeOrderRef {
  orderId: string;
  buyerId: string;
  /** Present on every primary-checkout PI; carried for logging only. */
  orgId: string | null;
  sessionId: string | null;
}

export type NativeMetadataResult =
  | { ok: true; ref: NativeOrderRef }
  | { ok: false; reason: 'missing_order_id' | 'missing_buyer_id' };

/**
 * `order_id` and `buyer_id` are LOAD-BEARING: the first names the subject of
 * `finalize_primary_order`, the second is cross-checked against the payments
 * row before we hand either to the database. Both are validated as uuids here
 * so a malformed value is an ACKed incident rather than a Postgres 22P02 that
 * would be classified as an unknown error and retried.
 */
export function readNativeMetadata(metadata: StripeMetadata): NativeMetadataResult {
  const orderId = str(metadata, 'order_id');
  const buyerId = str(metadata, 'buyer_id');
  if (!isUuid(orderId)) return { ok: false, reason: 'missing_order_id' };
  if (!isUuid(buyerId)) return { ok: false, reason: 'missing_buyer_id' };
  const orgId = str(metadata, 'org_id');
  const sessionId = str(metadata, 'session_id');
  return {
    ok: true,
    ref: {
      orderId,
      buyerId,
      orgId: isUuid(orgId) ? orgId : null,
      sessionId: isUuid(sessionId) ? sessionId : null,
    },
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. COMMAND KEYS — the domain-level exact-once anchor
// ─────────────────────────────────────────────────────────────────────────────

/**
 * DERIVED FROM THE ORDER AND THE PAYMENTINTENT — NEVER FROM `event.id`.
 *
 * This is the load-bearing choice of the whole branch. `finalize_primary_order`
 * forwards this key to `kernel.issue_ticket_atoms` as
 * `p_command_key || ':' || order_item.id` (085:2046-2052), and that key lands in
 * `kernel.ticket_ownership_log.command_idempotency_key` under
 * `ownership_log_command_uq unique (ticket_atom_id, command_idempotency_key)`
 * (079:101).
 *
 * If the key were keyed on `event.id`, TWO DISTINCT STRIPE EVENTS naming the
 * same PaymentIntent would present two distinct keys, and the mint's own replay
 * short-circuit (083:511) would not recognise the second as a replay. Keying on
 * (order, PI) makes the key an invariant of the ECONOMIC FACT rather than of the
 * delivery, so every delivery of every event about this payment presents the
 * same key. Duplicate delivery, redelivery after a lease steal, and a
 * second-event-id replay all converge on the same short-circuit.
 */
export function buildFinalizeCommandKey(orderId: string, paymentIntentId: string): string {
  return `wh_native_primary:${orderId}:${paymentIntentId}`;
}

/** Same invariance argument, for the terminal-failure writer. */
export function buildCancelCommandKey(orderId: string, paymentIntentId: string): string {
  return `wh_native_cancel:${orderId}:${paymentIntentId}`;
}

/**
 * `kernel.sync_org_connect_state` takes a command key but does not dedupe on
 * it (093:1300-1404 — its replay guard is the `connect_state_synced_at`
 * comparison, not the key). Keyed on the event so the audit trail names the
 * delivery that caused the transition.
 */
export function buildOrgSyncCommandKey(eventId: string): string {
  return `wh_account_updated:${eventId}`;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. THE PAYMENTS ROW — one PaymentIntent, one payment, one order
// ─────────────────────────────────────────────────────────────────────────────

export interface PaymentRow {
  id: string;
  status: string;
  mode: string | null;
  listing_id: string | null;
  seller_id: string | null;
  buyer_id: string | null;
  total: number | null;
}

export type PaymentRowVerdict =
  | { ok: true }
  | {
      ok: false;
      decision: Decision;
    };

/**
 * Refuses to hand `finalize_primary_order` a payments row that is not a direct-rail
 * row for THIS buyer.
 *
 * The 093 rail-pairing CHECK already makes `(native_primary, listing_id null,
 * seller_id null)` the only legal shape at rest, so this is a defensive twin —
 * but it is the twin that matters, because it is the one thing standing between
 * "the PI metadata says order X" and "we minted tickets against a resale
 * payment". Every failure here is ACKed: none of them can change on redelivery.
 */
export function verifyNativePaymentRow(row: PaymentRow, ref: NativeOrderRef): PaymentRowVerdict {
  if (row.mode !== PAYMENTS_MODE_NATIVE_PRIMARY) {
    return { ok: false, decision: { ack: true, alert: true, reason: 'payment_row_wrong_rail' } };
  }
  if (row.listing_id !== null || row.seller_id !== null) {
    // Structurally impossible under the 093 CHECK. If it ever happens the CHECK
    // is gone, and that is a migration incident, not a payment incident.
    return { ok: false, decision: { ack: true, alert: true, reason: 'payment_row_rail_pairing_violated' } };
  }
  if (row.buyer_id !== ref.buyerId) {
    // C35 in the edge, before the RPC re-asserts it against the ORDER's buyer.
    return { ok: false, decision: { ack: true, alert: true, reason: 'payment_row_buyer_mismatch' } };
  }
  return { ok: true };
}

export type ClaimOutcome =
  /** The UPDATE matched: this delivery owns the transition to succeeded. */
  | { kind: 'claimed'; row: PaymentRow }
  /** Already succeeded — a replay. Finalize anyway; it is idempotent. */
  | { kind: 'already_succeeded'; row: PaymentRow }
  /** OUT OF ORDER: money was refunded before we saw it arrive. Never mint. */
  | { kind: 'refunded'; row: PaymentRow }
  /** A status we do not have a rule for. */
  | { kind: 'unexpected_status'; row: PaymentRow }
  /** No `public.payments` row for this PaymentIntent at all. */
  | { kind: 'absent' };

/**
 * Interprets the result of the claim UPDATE plus (when the claim matched zero
 * rows) the follow-up SELECT.
 *
 * The claim on this rail carries `.neq('status','refunded')` IN ADDITION to the
 * legacy `.neq('status','succeeded')`. Without it a `charge.refunded` that beat
 * the `payment_intent.succeeded` would be overwritten back to `succeeded` — the
 * refund fact erased from `public.payments` — and only
 * `finalize_primary_order`'s `kernel.refund` probe (085:1936-1938) would stand
 * between that and a minted ticket for refunded money. This is native-only: the
 * legacy claim is untouched.
 */
export function interpretPaymentClaim(claimed: PaymentRow | null, existing: PaymentRow | null): ClaimOutcome {
  if (claimed) return { kind: 'claimed', row: claimed };
  if (!existing) return { kind: 'absent' };
  if (existing.status === 'succeeded') return { kind: 'already_succeeded', row: existing };
  if (existing.status === 'refunded') return { kind: 'refunded', row: existing };
  return { kind: 'unexpected_status', row: existing };
}

/**
 * How long a `payment_intent.succeeded` may arrive AHEAD of the `public.payments`
 * row that primary-checkout writes.
 *
 * primary-checkout creates the PI, then inserts the payments row, THEN returns
 * the clientSecret (:1040-1110). A succeeded PI therefore implies a delivered
 * clientSecret implies the row exists — so absence is an anomaly, not a race.
 * But a read against a lagging replica, or a redelivery that overtakes an
 * in-flight insert, is cheap to absorb and expensive to get wrong: the cost of
 * ACKing too early is a paid buyer with no tickets and no retry left.
 *
 * So: retry while the event is young, ACK-and-alert once it is old. Stripe's
 * schedule fits several attempts inside this window.
 */
export const PAYMENT_ROW_GRACE_SECONDS = 900;

export function decideAbsentPaymentRow(eventAgeSeconds: number): Decision {
  // Note the shape: only a FINITE age inside the window retries. An age that is
  // Infinity (an event we could not date) or NaN falls to the terminal side,
  // because an undateable event could already be days old and retrying it would
  // be an unbounded loop with no alert. Conservative direction, deliberately.
  if (Number.isFinite(eventAgeSeconds) && eventAgeSeconds < PAYMENT_ROW_GRACE_SECONDS) {
    return { ack: false, alert: false, reason: 'payment_row_absent_retrying' };
  }
  return { ack: true, alert: true, reason: 'payment_row_absent_terminal' };
}

export function decideClaimOutcome(outcome: ClaimOutcome, eventAgeSeconds: number): Decision {
  switch (outcome.kind) {
    case 'claimed':
    case 'already_succeeded':
      return { ack: true, alert: false, reason: 'proceed_to_finalize' };
    case 'refunded':
      // R6 P2: a delayed webhook must not mint tickets for money that was
      // refunded. finalize would refuse anyway; refusing here keeps the refusal
      // legible and avoids an alarming-looking RPC error.
      return { ack: true, alert: true, reason: 'out_of_order_refund_precedes_success' };
    case 'unexpected_status':
      return { ack: true, alert: true, reason: 'payment_row_unexpected_status' };
    case 'absent':
      return decideAbsentPaymentRow(eventAgeSeconds);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. ERROR CLASSIFICATION
// ─────────────────────────────────────────────────────────────────────────────

export interface PgErrorLike {
  message?: string | null;
  code?: string | null;
}

/**
 * Postgres classes whose members are, by definition, "try again": connection
 * failures, serialization/deadlock, resource exhaustion, operator intervention.
 * Retrying these is the entire reason Stripe has a retry schedule.
 */
function isTransientPgCode(code: string): boolean {
  if (code.startsWith('08')) return true; // connection exception
  if (code.startsWith('53')) return true; // insufficient resources
  if (code.startsWith('57')) return true; // operator intervention / query canceled
  if (code.startsWith('58')) return true; // system error
  return code === '40001' || code === '40P01' || code === '55P03' || code === 'XX000';
}

/** `insufficient_privilege` — a missing GRANT. Ops-fixable inside the window. */
function isPrivilegeCode(code: string, message: string): boolean {
  return code === '42501' || message.includes('insufficient_privilege') || message.includes('permission denied');
}

/**
 * `venue.finalize_primary_order` (085:1881-2082).
 *
 * TERMINAL (ack) — the event can never succeed, no matter how many times it is
 * delivered, because the refusal is about facts the event itself carries:
 *   payment_unverified:*  — wrong buyer, insufficient cover, or an existing refund
 *   buyer identity is erased — OR-17 tombstone; the acquisition is refused forever
 *   only a pending order finalizes — the order is already cancelled/refunded
 *   oversell_rejected     — the batch has no headroom; minting is not the fix
 *   no reservation names a batch — the checkout invariant is already broken
 *   not_found / P0002     — the order does not exist
 *   invalid_input         — a malformed argument we built; a redeploy fixes it, not a retry
 *
 * RETRYABLE (non-2xx) — the refusal is about OUR world and a redelivery lands
 * after someone fixes it:
 *   no_active_signing_key — provision a key and the very next delivery mints
 *   42501                 — PFA-15/PFA-21 grant gap; grant it and the retry works
 *   transient PG classes  — the reason retries exist
 *   anything unrecognised — fail toward not losing the money event
 */
export function classifyFinalizeError(err: PgErrorLike | null | undefined): Decision {
  const message = (err?.message ?? '').toLowerCase();
  const code = (err?.code ?? '').trim();

  if (code && isTransientPgCode(code)) {
    return { ack: false, alert: true, reason: 'finalize_transient' };
  }
  if (isPrivilegeCode(code, message)) {
    return { ack: false, alert: true, reason: 'finalize_not_granted' };
  }
  if (message.includes('no_active_signing_key')) {
    return { ack: false, alert: true, reason: 'finalize_no_signing_key' };
  }
  if (message.includes('payment_unverified')) {
    return { ack: true, alert: true, reason: 'finalize_payment_unverified' };
  }
  if (message.includes('identity is erased')) {
    return { ack: true, alert: true, reason: 'finalize_buyer_erased' };
  }
  if (message.includes('only a pending order finalizes')) {
    return { ack: true, alert: true, reason: 'finalize_order_not_pending' };
  }
  if (message.includes('oversell_rejected')) {
    return { ack: true, alert: true, reason: 'finalize_oversell' };
  }
  if (message.includes('no reservation names a batch')) {
    return { ack: true, alert: true, reason: 'finalize_no_reservation' };
  }
  if (code === 'P0002' || message.includes('not_found')) {
    return { ack: true, alert: true, reason: 'finalize_order_not_found' };
  }
  if (message.includes('invalid_input')) {
    return { ack: true, alert: true, reason: 'finalize_invalid_input' };
  }
  return { ack: false, alert: true, reason: 'finalize_unclassified' };
}

/**
 * `venue.cancel_pending_order` (082:478-525). Returns `noop_replay` rather than
 * raising for the already-cancelled case, so the only reachable raises are
 * not_found, order_not_pending (the order was PAID — money won, nothing to
 * cancel) and invalid_input. None of them improve with a retry.
 */
export function classifyCancelError(err: PgErrorLike | null | undefined): Decision {
  const message = (err?.message ?? '').toLowerCase();
  const code = (err?.code ?? '').trim();

  if (code && isTransientPgCode(code)) {
    return { ack: false, alert: true, reason: 'cancel_transient' };
  }
  if (isPrivilegeCode(code, message)) {
    return { ack: false, alert: true, reason: 'cancel_not_granted' };
  }
  if (message.includes('order_not_pending')) {
    // The order is paid. A terminal PI event arriving after issuance is an
    // ordering artefact, not a failure — but it is worth seeing.
    return { ack: true, alert: true, reason: 'cancel_order_not_pending' };
  }
  if (code === 'P0002' || message.includes('not_found')) {
    return { ack: true, alert: true, reason: 'cancel_order_not_found' };
  }
  if (message.includes('invalid_input')) {
    return { ack: true, alert: true, reason: 'cancel_invalid_input' };
  }
  return { ack: false, alert: true, reason: 'cancel_unclassified' };
}

/**
 * `kernel.sync_org_connect_state` (093:1300-1404).
 *
 *   not_found       — the org has no bound account YET. Expected during
 *                     onboarding: Stripe fires account.updated while the
 *                     account is being created, before `set_org_connect_ref`
 *                     lands. ACK. Safe to drop because the gate operand
 *                     DEFAULTS FALSE, so a lost "gained" observation only
 *                     under-permits; and a lost "lost" observation is
 *                     impossible here, since losing a capability requires the
 *                     org to already be bound, in which case not_found cannot
 *                     be raised.
 *   conflict_locked — G-4/A9: the event names an account that is not this org's
 *                     bound destination. The refusal IS the correct outcome.
 *   malformed_account_ref / invalid_input — our argument construction. ACK+alert.
 */
export function classifyOrgSyncError(err: PgErrorLike | null | undefined): Decision {
  const message = (err?.message ?? '').toLowerCase();
  const code = (err?.code ?? '').trim();

  if (code && isTransientPgCode(code)) {
    return { ack: false, alert: true, reason: 'org_sync_transient' };
  }
  if (isPrivilegeCode(code, message)) {
    return { ack: false, alert: true, reason: 'org_sync_not_granted' };
  }
  if (code === 'P0002' || message.includes('not_found')) {
    return { ack: true, alert: false, reason: 'org_sync_org_not_bound' };
  }
  if (message.includes('conflict_locked')) {
    return { ack: true, alert: true, reason: 'org_sync_account_not_bound_destination' };
  }
  if (message.includes('malformed_account_ref')) {
    return { ack: true, alert: true, reason: 'org_sync_malformed_account_ref' };
  }
  if (message.includes('invalid_input')) {
    return { ack: true, alert: true, reason: 'org_sync_invalid_input' };
  }
  return { ack: false, alert: true, reason: 'org_sync_unclassified' };
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. PAYMENTINTENT TERMINALITY
// ─────────────────────────────────────────────────────────────────────────────

export interface PaymentIntentLike {
  id?: unknown;
  status?: unknown;
  latest_charge?: unknown;
  metadata?: StripeMetadata;
}

/**
 * SPEC §4: cancel the pending order "ONLY on a TERMINAL PaymentIntent".
 *
 * `payment_intent.payment_failed` fires PER ATTEMPT. After a decline the PI
 * returns to `requires_payment_method` and the SAME PaymentSheet can be retried
 * — §3.1's retry contract depends on it. Cancelling the order on a per-attempt
 * decline would destroy an order the buyer is still paying for. `canceled` is
 * the only PaymentIntent status from which no confirmation is possible.
 *
 * Capacity is NOT released here on a non-terminal failure: 082's checkout
 * persists no order→hold linkage, so there is nothing to release directly.
 * Capacity returns via the §20.3.3 hold-TTL sweep.
 */
export function isTerminalPaymentIntent(pi: PaymentIntentLike | null | undefined): boolean {
  return pi?.status === 'canceled';
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. INSTRUMENT FINGERPRINT (the promoter self-deal detector's only input)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * The pinned post-2022 Stripe API version delivers `latest_charge` as an ID,
 * not an expanded object — but an expanded object is accepted here so a webhook
 * configured with expansion, or a test, needs no network call at all.
 */
export function latestChargeId(pi: PaymentIntentLike | null | undefined): string | null {
  const lc = pi?.latest_charge;
  if (typeof lc === 'string' && lc.length > 0) return lc;
  if (lc && typeof lc === 'object') {
    const id = (lc as { id?: unknown }).id;
    if (typeof id === 'string' && id.length > 0) return id;
  }
  return null;
}

/**
 * `payment_method_details` is keyed by the instrument type; the fingerprint
 * lives on the type-named sub-object. NEVER LOGGED, never returned to a client,
 * never validated — NULL is a legitimate "no signal" (PROMO §1.8), and per RPC
 * §17.14 no attribution input may delay or fail issuance.
 */
export function extractInstrumentFingerprint(charge: unknown): string | null {
  if (!charge || typeof charge !== 'object') return null;
  const details = (charge as { payment_method_details?: unknown }).payment_method_details;
  if (!details || typeof details !== 'object') return null;
  const type = (details as { type?: unknown }).type;
  if (typeof type !== 'string' || type.length === 0) return null;
  const sub = (details as Record<string, unknown>)[type];
  if (!sub || typeof sub !== 'object') return null;
  const fp = (sub as { fingerprint?: unknown }).fingerprint;
  return typeof fp === 'string' && fp.length > 0 ? fp : null;
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. `account.updated` — PLANE SELECTION
// ─────────────────────────────────────────────────────────────────────────────

/**
 * RULING A8 GATES ON `transfers`, NOT ON charges/payouts.
 *
 * This is not a stylistic preference. `connect-onboarding` requests
 * `capabilities[transfers]` and DELIBERATELY NOT `card_payments` (:544, and the
 * reasoning at :515-522), because requesting card_payments would make the venue
 * the merchant of record and couple the two capabilities. Consequently
 * `charges_enabled` is FALSE FOREVER on a correctly-provisioned org account, and
 * a gate derived from it would keep every venue dark permanently. `payouts_enabled`
 * is ruled explicitly NOT a sale gate (F §3.5): transfers-active with payouts
 * disabled still sells and still receives transfers.
 *
 * The predicate mirrors the shipped payout probe exactly
 * (`_shared/payouts.ts:96-98`: `caps.transfers !== 'active'` ⇒ not ready).
 */
export interface ConnectAccountLike {
  id?: unknown;
  capabilities?: Record<string, unknown> | null;
  details_submitted?: unknown;
  charges_enabled?: unknown;
  payouts_enabled?: unknown;
  metadata?: StripeMetadata;
}

export function deriveTransfersActive(account: ConnectAccountLike | null | undefined): boolean {
  return account?.capabilities?.transfers === TRANSFERS_CAPABILITY_ACTIVE;
}

export interface PlaneSelection {
  /** Run the organization arm for this account. */
  organization: boolean;
  /** `metadata.org_id`, validated. May be null even when `organization` is true. */
  orgId: string | null;
  /** connect-onboarding's explicit discriminator was present. */
  explicitOrgTag: boolean;
}

/**
 * The org arm runs when the account SAYS it is an org account — never by
 * inferring the plane from "profiles matched zero rows", which is exactly the
 * inference connect-onboarding added `metadata[snatchit_plane]` to make
 * unnecessary (:549-551).
 *
 * `org_id` alone is enough (accounts created before the discriminator existed
 * carry it), and the discriminator alone is enough (the RPC accepts the account
 * ref as its primary selector and only needs org_id as a fallback).
 */
export function selectAccountPlane(metadata: StripeMetadata): PlaneSelection {
  const tag = str(metadata, 'snatchit_plane');
  const rawOrgId = str(metadata, 'org_id');
  const orgId = isUuid(rawOrgId) ? rawOrgId : null;
  const explicitOrgTag = tag === PLANE_ORGANIZATION;
  return { organization: explicitOrgTag || orgId !== null, orgId, explicitOrgTag };
}

/**
 * The observation instant handed to `kernel.sync_org_connect_state` as
 * `p_observed_at`, which is what makes its out-of-order guard work
 * (093:1352-1360: an observation no newer than the recorded one is a
 * `noop_replay`).
 *
 * `event.created` — NOT `now()`. `now()` would make every redelivery look
 * fresher than the observation it is redelivering, so a redelivered STALE event
 * would overwrite a newer state. Passing the event's own instant means a
 * redelivery of an older event is correctly recognised as older and changes
 * nothing.
 */
export function observedAtIso(eventCreatedSeconds: unknown): string | null {
  if (typeof eventCreatedSeconds !== 'number' || !Number.isFinite(eventCreatedSeconds)) return null;
  if (eventCreatedSeconds <= 0) return null;
  return new Date(eventCreatedSeconds * 1000).toISOString();
}

export type OrgArmOutcome =
  | 'skipped'
  | 'ok'
  | 'noop_replay'
  | 'org_not_bound'
  | 'refused'
  | 'failed';

export interface AccountUpdatedOutcome {
  /** For the log line and the response body: which plane(s) actually matched. */
  matched: 'individual' | 'organization' | 'both' | 'none';
  /** true → captureException. A zero match on BOTH planes is never silent. */
  alert: boolean;
  reason: string;
}

/**
 * THE FIX FOR `matched_profiles: 0` BEING REPORTED AS PLAIN SUCCESS.
 *
 * Today an org Connect account matches no profile and the handler logs a
 * cheerful "account.updated synced … matched_profiles: 0" and ACKs. That is how
 * an organization account gets created and then never monitored again. The ACK
 * contract is preserved — Stripe must get a 2xx or it retries forever — but a
 * zero match on BOTH planes is now an alert, not a success line.
 *
 * `both` is its own outcome and it ALERTS: an account that is simultaneously an
 * org destination and a seller profile's connect id is the cross-plane reuse
 * A7/A9 forbid.
 */
export function decideAccountUpdatedOutcome(
  profileMatches: number,
  orgArm: OrgArmOutcome,
): AccountUpdatedOutcome {
  const individual = profileMatches > 0;
  const organization = orgArm === 'ok' || orgArm === 'noop_replay';

  if (individual && organization) {
    return { matched: 'both', alert: true, reason: 'cross_plane_account_reuse' };
  }
  if (organization) {
    return { matched: 'organization', alert: false, reason: `org_${orgArm}` };
  }
  if (individual) {
    return { matched: 'individual', alert: false, reason: 'individual_synced' };
  }
  // Zero on both planes. Previously indistinguishable from success.
  if (orgArm === 'refused' || orgArm === 'failed') {
    return { matched: 'none', alert: true, reason: `org_${orgArm}` };
  }
  if (orgArm === 'org_not_bound') {
    return { matched: 'none', alert: true, reason: 'org_account_not_bound_to_any_org' };
  }
  return { matched: 'none', alert: true, reason: 'account_unmatched_on_both_planes' };
}

/**
 * Seconds between the event's own timestamp and now. Used only to bound the
 * payments-row grace window. A missing/garbage `created` yields `Infinity`, which
 * makes `decideAbsentPaymentRow` choose the TERMINAL side — the conservative
 * choice for an event we cannot date, because an undated event could be days old.
 */
export function eventAgeSeconds(eventCreatedSeconds: unknown, nowMs: number): number {
  if (typeof eventCreatedSeconds !== 'number' || !Number.isFinite(eventCreatedSeconds) || eventCreatedSeconds <= 0) {
    return Number.POSITIVE_INFINITY;
  }
  return Math.max(0, Math.floor(nowMs / 1000) - eventCreatedSeconds);
}
