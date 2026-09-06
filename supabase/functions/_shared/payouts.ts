/**
 * _shared/payouts.ts — the ONE way a seller payout reaches Stripe, and the
 * ONE implementation of the payout ATTEMPT protocol (migration
 * 20260906120000, PAYMENTS_RELIABILITY_2026-09 Package 3).
 *
 * Incident history (2026-08-03/04), each layer here exists for a proven
 * production failure:
 *   1. Two callers sent different metadata under one idempotency key →
 *      "Keys for idempotent requests can only be used with the same
 *      parameters..." — fixed by this single canonical request.
 *   2. A not-yet-onboarded destination burned the key for 24h → fixed by
 *      the capability PRE-FLIGHT (keys are only spent on requests that can
 *      succeed).
 *   3. A same-day charge left the platform's AVAILABLE balance at $0 →
 *      "Insufficient funds in Stripe account." even though the payment
 *      succeeded. Fixed by funding the transfer with `source_transaction`.
 *   4. (2026-09, F07/F08) A chargeback landing between the eligibility
 *      recheck and the DB record left a real Stripe transfer with no DB
 *      trace; a lost response + 24h key expiry (or a destination change)
 *      produced a SECOND real transfer. Fixed by the attempt ledger below:
 *      claim (frozen params + lease) → reconcile any open attempt by
 *      transfer_group BEFORE any new POST → pre-flights →
 *      mark_payout_requested → POST → record (a transfer Stripe reports is
 *      ALWAYS recorded; eligibility drift becomes reversal_required +
 *      manual review, never a dropped tr_ id).
 *
 * No DB transaction or lock is ever held across a network call: every RPC
 * here is a single short statement; Stripe calls happen between them.
 *
 * Pure decision logic (key format, error classification, amount ceiling,
 * POST-failure classification) lives in ./payout-logic.ts (vitest).
 */
import { stripeFetchRaw } from './stripe.ts';
import {
  buildPayoutIdempotencyKey,
  classifyPayoutPostFailure,
  classifyPayoutStripeError,
  maxTransferableCents,
  reasonCodeForErrorClass,
  shouldPageSentry,
  type PayoutErrorClass,
  type PayoutPostOutcome,
} from './payout-logic.ts';

export { classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry };
export type { PayoutErrorClass };

// ── Stripe side ──────────────────────────────────────────────────────────────

export interface SellerPayoutArgs {
  transferId:      string;
  paymentId:       string;
  sellerId:        string;
  /** The claimed attempt this request belongs to (payout_attempts.id). */
  attemptId:       string;
  attemptNo:       number;
  /** Frozen at claim time; MUST equal buildPayoutIdempotencyKey(transferId, attemptNo). */
  idempotencyKey:  string;
  /** Frozen destination (payout_attempts.destination). Never re-read from profiles. */
  destination:     string;
  /** The succeeded PaymentIntent funding this payout. */
  paymentIntentId: string;
  /** Frozen seller net in cents (payout_attempts.amount_cents). */
  sellerNetCents:  number;
  /** Frozen funding charge when the claim already knew it; else discovered in pre-flight. */
  sourceChargeId?: string | null;
}

/** Destination account state captured at attempt time (audit evidence). */
export interface PayoutDestinationState {
  transfers_capability: string | null;
  details_submitted:    boolean | null;
  payouts_enabled:      boolean | null;
  disabled_reason:      string | null;
  currently_due:        string[] | null;
  probe_error:          string | null;
}

/** Funding-charge state captured at attempt time (audit evidence). */
export interface PayoutSourceState {
  pi_status:        string | null;
  charge_id:        string | null;
  livemode:         boolean | null;
  charge_refunded:  boolean | null;
  amount_refunded:  number | null;
  max_transferable: number | null;
  probe_error:      string | null;
}

export type SellerPayoutResult =
  | { ok: true;  transfer: { id: string }; source_charge_id: string }
  | { ok: false; reason: 'destination_not_ready';     destination_state: PayoutDestinationState }
  | { ok: false; reason: 'source_charge_unavailable'; source_state: PayoutSourceState }
  /** the beforeTransfer hook refused — nothing was sent to Stripe */
  | { ok: false; reason: 'not_requested' }
  /** Stripe definitely did not create a transfer */
  | { ok: false; reason: 'transfer_rejected'; outcome: 'failed_not_created'; status: number; error: string; error_class: PayoutErrorClass }
  /** a transfer MAY exist (network / 5xx / in-flight) */
  | { ok: false; reason: 'transfer_unknown';  outcome: 'unknown'; status: number | null; error: string; error_class: PayoutErrorClass };

export interface SellerPayoutHooks {
  /**
   * Runs after the pre-flights and immediately before the POST. Return false
   * to abort without sending (used to mark the attempt `requested` so a lost
   * response is known to possibly exist on Stripe).
   */
  beforeTransfer?: () => Promise<boolean>;
}

/**
 * Capability pre-flight → funding-charge verification → hook →
 * source_transaction transfer under the attempt's frozen parameters.
 */
export async function createSellerPayout(
  args: SellerPayoutArgs,
  hooks: SellerPayoutHooks = {},
): Promise<SellerPayoutResult> {
  if (args.idempotencyKey !== buildPayoutIdempotencyKey(args.transferId, args.attemptNo)) {
    throw new Error(`createSellerPayout: idempotency key does not match attempt ${args.attemptNo} of ${args.transferId}`);
  }

  // ── 1. Destination must be able to receive transfers ────────────────────
  const acct = await stripeFetchRaw(`/accounts/${args.destination}`);
  const a    = acct.data as Record<string, unknown>;
  const caps = (a?.capabilities ?? {}) as Record<string, string>;
  const req  = (a?.requirements ?? {}) as Record<string, unknown>;
  const destinationState: PayoutDestinationState = {
    transfers_capability: caps.transfers ?? null,
    details_submitted:    (a?.details_submitted as boolean) ?? null,
    payouts_enabled:      (a?.payouts_enabled as boolean) ?? null,
    disabled_reason:      (req.disabled_reason as string) ?? null,
    currently_due:        (req.currently_due as string[]) ?? null,
    probe_error: acct.ok
      ? null
      : (acct.data as { error?: { message?: string } })?.error?.message ?? `HTTP ${acct.status}`,
  };
  if (!acct.ok || caps.transfers !== 'active') {
    return { ok: false, reason: 'destination_not_ready', destination_state: destinationState };
  }

  // ── 2. The funding charge must exist, be live, and not be refunded ──────
  const piProbe = await stripeFetchRaw(
    `/payment_intents/${args.paymentIntentId}?expand[]=latest_charge`,
  );
  const pi = piProbe.data as Record<string, unknown>;
  const ch = (pi?.latest_charge ?? null) as Record<string, unknown> | null;
  const sourceState: PayoutSourceState = {
    pi_status:        (pi?.status as string) ?? null,
    charge_id:        (ch?.id as string) ?? null,
    livemode:         (pi?.livemode as boolean) ?? null,
    charge_refunded:  (ch?.refunded as boolean) ?? null,
    amount_refunded:  (ch?.amount_refunded as number) ?? null,
    max_transferable: ch
      ? maxTransferableCents((ch.amount as number) ?? 0, (ch.amount_refunded as number) ?? 0)
      : null,
    probe_error: piProbe.ok
      ? null
      : (piProbe.data as { error?: { message?: string } })?.error?.message ?? `HTTP ${piProbe.status}`,
  };
  const fundable =
    piProbe.ok &&
    pi?.status === 'succeeded' &&
    pi?.livemode === true &&
    !!ch?.id &&
    ch?.refunded !== true &&
    (!args.sourceChargeId || args.sourceChargeId === ch?.id) &&
    args.sellerNetCents <= (sourceState.max_transferable ?? 0);
  if (!fundable) {
    return { ok: false, reason: 'source_charge_unavailable', source_state: sourceState };
  }
  const sourceChargeId = sourceState.charge_id as string;

  // ── 3. Mark the attempt requested BEFORE the money can move ─────────────
  if (hooks.beforeTransfer && !(await hooks.beforeTransfer())) {
    return { ok: false, reason: 'not_requested' };
  }

  // ── 4. The transfer, funded by THIS charge, under the attempt's key ─────
  let res: { ok: boolean; status: number; data: unknown };
  try {
    res = await stripeFetchRaw('/transfers', {
      method: 'POST',
      idempotencyKey: args.idempotencyKey,
      body: {
        'amount':                String(args.sellerNetCents),
        'currency':              'usd',
        'destination':           args.destination,
        'source_transaction':    sourceChargeId,
        'transfer_group':        args.transferId,
        'metadata[transfer_id]': args.transferId,
        'metadata[payment_id]':  args.paymentId,
        'metadata[seller_id]':   args.sellerId,
        'metadata[attempt_id]':  args.attemptId,
        'metadata[attempt_no]':  String(args.attemptNo),
      },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, reason: 'transfer_unknown', outcome: 'unknown', status: null, error: message,
             error_class: classifyPayoutStripeError(message) };
  }
  if (res.ok) {
    const tr = res.data as { id?: string };
    if (!tr?.id) {
      return { ok: false, reason: 'transfer_unknown', outcome: 'unknown', status: res.status,
               error: 'Stripe 2xx without a transfer id', error_class: 'unexpected' };
    }
    return { ok: true, transfer: { id: tr.id }, source_charge_id: sourceChargeId };
  }
  const stripeErr = (res.data as { error?: { type?: string; code?: string; message?: string } })?.error ?? null;
  const message   = stripeErr?.message ?? `Stripe POST /transfers → ${res.status}`;
  const outcome: PayoutPostOutcome = classifyPayoutPostFailure(res.status, stripeErr);
  const errorClass = classifyPayoutStripeError(message);
  if (outcome === 'failed_not_created') {
    return { ok: false, reason: 'transfer_rejected', outcome, status: res.status, error: message, error_class: errorClass };
  }
  return { ok: false, reason: 'transfer_unknown', outcome, status: res.status, error: message, error_class: errorClass };
}

export type FindTransferResult =
  | { ok: true;  transfer: { id: string } | null; /** transfers in the group that carry no/other attempt id */ unmatched: string[] }
  | { ok: false; error: string };

/**
 * Recovery search: every transfer this package creates carries
 * `transfer_group = <transfer_id>` and `metadata[attempt_id]`. Listing the
 * group is how an attempt whose response was lost is reconciled BEFORE any
 * new POST — the durable replacement for the 24h idempotency-key window.
 */
export async function findTransferByAttempt(transferId: string, attemptId: string): Promise<FindTransferResult> {
  let res: { ok: boolean; status: number; data: unknown };
  try {
    res = await stripeFetchRaw(`/transfers?transfer_group=${encodeURIComponent(transferId)}&limit=100`);
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) };
  }
  if (!res.ok) {
    const e = (res.data as { error?: { message?: string } })?.error?.message;
    return { ok: false, error: e ?? `HTTP ${res.status}` };
  }
  const list = ((res.data as { data?: Array<{ id: string; metadata?: Record<string, string> }> })?.data ?? []);
  const unmatched: string[] = [];
  let found: { id: string } | null = null;
  for (const tr of list) {
    if (tr?.metadata?.attempt_id === attemptId) found = { id: tr.id };
    else if (tr?.id) unmatched.push(tr.id);
  }
  return { ok: true, transfer: found, unmatched };
}

// ── Attempt protocol (DB side) ───────────────────────────────────────────────

/** The slice of supabase-js the protocol needs. */
export interface PayoutDb {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<{ data: unknown; error: { message: string } | null }>;
}

export interface ClaimedAttempt {
  attempt_id:        string;
  attempt_no:        number;
  idempotency_key:   string;
  destination:       string;
  amount_cents:      number;
  source_charge_id:  string | null;
  payment_intent_id: string;
  needs_reconcile:   boolean;
}

/** claim_payout_attempt refusals that are expected operational states. */
export const PAYOUT_NOT_ELIGIBLE_REASONS = [
  'TRANSFER_NOT_FOUND', 'TRANSFER_NOT_RELEASABLE', 'DISPUTED', 'PAYMENT_NOT_SUCCEEDED',
  'PAYMENT_NOT_LIVE', 'SELLER_NOT_ONBOARDED', 'PAYOUT_AMOUNT_INVALID',
] as const;

export type PayoutAttemptOutcome =
  | { kind: 'succeeded';         attemptId: string; attemptNo: number; stripeTransferId: string; destination: string; sellerNetCents: number; sourceChargeId: string }
  | { kind: 'reversal_required'; attemptId: string; attemptNo: number; stripeTransferId: string; destination: string; sellerNetCents: number }
  | { kind: 'already_released' }
  | { kind: 'in_progress' }
  | { kind: 'reconciled';        attemptId: string; state: string; stripeTransferId: string | null; found: boolean }
  | { kind: 'reconcile_pending'; attemptId: string; error: string; unmatched: string[] }
  | { kind: 'not_eligible';      reason: string }
  | { kind: 'deferred';          attemptId: string; reasonCode: string; evidence: Record<string, unknown>; page: boolean; error?: string }
  | { kind: 'unknown';           attemptId: string; error: string }
  | { kind: 'db_error';          stage: 'claim' | 'mark' | 'record' | 'reconcile'; error: string; attemptId?: string; stripeTransferId?: string };

export interface ExecutePayoutArgs {
  transferId: string;
  paymentId:  string;
  sellerId:   string;
  /** 'edge:confirm-and-release' | 'cron:enforce-transfer-expiry' | … */
  actor:      string;
}

function rpcReason(message: string): string | null {
  for (const r of ['ALREADY_RELEASED', 'PAYOUT_ATTEMPT_IN_PROGRESS', ...PAYOUT_NOT_ELIGIBLE_REASONS]) {
    if (message.includes(r)) return r;
  }
  return null;
}

/**
 * The whole protocol for one transfer, for both callers:
 *   claim → (open attempt? search Stripe by transfer_group → reconcile → STOP)
 *   → pre-flights → mark_payout_requested → POST → record.
 * Never re-reads the seller profile after the claim; never POSTs while an
 * attempt is open; never returns without the DB knowing what happened to
 * money that moved (a record failure surfaces as db_error WITH the tr_ id).
 */
export async function executePayoutAttempt(db: PayoutDb, args: ExecutePayoutArgs): Promise<PayoutAttemptOutcome> {
  // ── 1. Claim (one short statement; FOR UPDATE released at return) ───────
  const claim = await db.rpc('claim_payout_attempt', { p_transfer_id: args.transferId, p_actor: args.actor });
  if (claim.error) {
    const reason = rpcReason(claim.error.message ?? '');
    if (reason === 'ALREADY_RELEASED')           return { kind: 'already_released' };
    if (reason === 'PAYOUT_ATTEMPT_IN_PROGRESS') return { kind: 'in_progress' };
    if (reason)                                  return { kind: 'not_eligible', reason };
    return { kind: 'db_error', stage: 'claim', error: claim.error.message };
  }
  const rows = (Array.isArray(claim.data) ? claim.data : claim.data ? [claim.data] : []) as ClaimedAttempt[];
  const att = rows[0];
  if (!att?.attempt_id) {
    return { kind: 'db_error', stage: 'claim', error: 'claim_payout_attempt returned no row' };
  }

  // ── 2. Open attempt → reconcile against Stripe, never POST this run ─────
  if (att.needs_reconcile) {
    const search = await findTransferByAttempt(args.transferId, att.attempt_id);
    if (!search.ok) {
      await db.rpc('record_payout_attempt_result', {
        p_attempt_id: att.attempt_id, p_stripe_transfer_id: null, p_outcome: 'unknown',
        p_error: { reconcile: 'search_failed', error: search.error },
      });
      return { kind: 'reconcile_pending', attemptId: att.attempt_id, error: search.error, unmatched: [] };
    }
    if (!search.transfer && search.unmatched.length > 0) {
      // Transfers exist in this group that this attempt cannot claim. Not
      // "none exists" — leave the attempt open for an operator.
      await db.rpc('record_payout_attempt_result', {
        p_attempt_id: att.attempt_id, p_stripe_transfer_id: null, p_outcome: 'unknown',
        p_error: { reconcile: 'unmatched_transfers', unmatched: search.unmatched },
      });
      return { kind: 'reconcile_pending', attemptId: att.attempt_id, error: 'unmatched transfers in transfer_group', unmatched: search.unmatched };
    }
    const rec = await db.rpc('reconcile_payout_attempt', {
      p_attempt_id: att.attempt_id, p_found_transfer_id: search.transfer?.id ?? null,
    });
    if (rec.error) {
      return { kind: 'db_error', stage: 'reconcile', error: rec.error.message, attemptId: att.attempt_id,
               stripeTransferId: search.transfer?.id };
    }
    const r = (rec.data ?? {}) as { state?: string; stripe_transfer_id?: string | null };
    return { kind: 'reconciled', attemptId: att.attempt_id, state: r.state ?? 'unknown',
             stripeTransferId: r.stripe_transfer_id ?? search.transfer?.id ?? null, found: !!search.transfer };
  }

  // ── 3. Pre-flights → mark requested → POST ──────────────────────────────
  let markError: string | null = null;
  const payout = await createSellerPayout({
    transferId:      args.transferId,
    paymentId:       args.paymentId,
    sellerId:        args.sellerId,
    attemptId:       att.attempt_id,
    attemptNo:       att.attempt_no,
    idempotencyKey:  att.idempotency_key,
    destination:     att.destination,
    paymentIntentId: att.payment_intent_id,
    sellerNetCents:  att.amount_cents,
    sourceChargeId:  att.source_charge_id,
  }, {
    beforeTransfer: async () => {
      const m = await db.rpc('mark_payout_requested', { p_attempt_id: att.attempt_id });
      if (m.error) { markError = m.error.message; return false; }
      if (m.data !== true) { markError = 'mark_payout_requested returned false'; return false; }
      return true;
    },
  });

  // ── 4. Record ───────────────────────────────────────────────────────────
  if (payout.ok) {
    const rec = await db.rpc('record_payout_attempt_result', {
      p_attempt_id: att.attempt_id, p_stripe_transfer_id: payout.transfer.id, p_outcome: 'succeeded',
      p_error: null,
    });
    if (rec.error) {
      return { kind: 'db_error', stage: 'record', error: rec.error.message, attemptId: att.attempt_id,
               stripeTransferId: payout.transfer.id };
    }
    const r = (rec.data ?? {}) as { state?: string };
    if (r.state === 'reversal_required') {
      return { kind: 'reversal_required', attemptId: att.attempt_id, attemptNo: att.attempt_no,
               stripeTransferId: payout.transfer.id, destination: att.destination, sellerNetCents: att.amount_cents };
    }
    return { kind: 'succeeded', attemptId: att.attempt_id, attemptNo: att.attempt_no,
             stripeTransferId: payout.transfer.id, destination: att.destination,
             sellerNetCents: att.amount_cents, sourceChargeId: payout.source_charge_id };
  }

  if (payout.reason === 'not_requested') {
    // Nothing was sent; the attempt stays claimed under its lease and is
    // reconciled (→ failed) by the next sweep.
    return { kind: 'db_error', stage: 'mark', error: markError ?? 'not requested', attemptId: att.attempt_id };
  }

  if (payout.reason === 'transfer_unknown') {
    await db.rpc('record_payout_attempt_result', {
      p_attempt_id: att.attempt_id, p_stripe_transfer_id: null, p_outcome: 'unknown',
      p_error: { status: payout.status, error: payout.error, error_class: payout.error_class },
    });
    return { kind: 'unknown', attemptId: att.attempt_id, error: payout.error };
  }

  // Definite non-creation: pre-flight refusal or a Stripe 4xx. Close the
  // attempt so a later attempt can open once the condition clears.
  let reasonCode: string;
  let evidence: Record<string, unknown>;
  let page = false;
  let error: string | undefined;
  if (payout.reason === 'destination_not_ready') {
    reasonCode = 'PAYOUT_DESTINATION_NOT_READY';
    evidence   = { destination_suffix: att.destination.slice(-4), seller_net_cents: att.amount_cents, ...payout.destination_state };
  } else if (payout.reason === 'source_charge_unavailable') {
    reasonCode = 'PAYOUT_SOURCE_CHARGE_UNAVAILABLE';
    evidence   = { destination_suffix: att.destination.slice(-4), seller_net_cents: att.amount_cents, ...payout.source_state };
  } else {
    reasonCode = reasonCodeForErrorClass(payout.error_class);
    evidence   = { stripe_error: payout.error, stripe_status: payout.status, error_class: payout.error_class,
                   destination_suffix: att.destination.slice(-4), seller_net_cents: att.amount_cents };
    page       = shouldPageSentry(payout.error_class);
    error      = payout.error;
  }
  const rec = await db.rpc('record_payout_attempt_result', {
    p_attempt_id: att.attempt_id, p_stripe_transfer_id: null, p_outcome: 'failed_not_created',
    p_error: { reason_code: reasonCode, ...evidence },
  });
  if (rec.error) {
    return { kind: 'db_error', stage: 'record', error: rec.error.message, attemptId: att.attempt_id };
  }
  return { kind: 'deferred', attemptId: att.attempt_id, reasonCode, evidence, page, error };
}
