/**
 * _shared/payouts.ts — the ONE way a seller payout reaches Stripe.
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
 *      succeeded (its balance transaction was still `pending`,
 *      available_on ≈ 7 days out). Fixed by funding the transfer with
 *      `source_transaction`: Stripe accepts the transfer immediately and
 *      settles it against THAT charge as it becomes available — the payout
 *      never draws unrelated platform balance.
 *
 * Pure decision logic (key format, eligibility, error classification,
 * amount ceiling) lives in ./payout-logic.ts and is unit-tested by vitest.
 */
import { stripeFetch, stripeFetchRaw } from './stripe.ts';
import {
  buildPayoutIdempotencyKey,
  classifyPayoutStripeError,
  maxTransferableCents,
  reasonCodeForErrorClass,
  shouldPageSentry,
  type PayoutErrorClass,
} from './payout-logic.ts';

export { classifyPayoutStripeError, reasonCodeForErrorClass, shouldPageSentry };
export type { PayoutErrorClass };

export interface SellerPayoutArgs {
  transferId:      string;
  paymentId:       string;
  sellerId:        string;
  /** Seller's Stripe Connect account id (live mode). */
  destination:     string;
  /** The succeeded PaymentIntent funding this payout. */
  paymentIntentId: string;
  /** Seller net in cents: payment.amount − payment.seller_fee. */
  sellerNetCents:  number;
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
  | { ok: true;  transfer: { id: string } }
  | { ok: false; reason: 'destination_not_ready'; destination_state: PayoutDestinationState }
  | { ok: false; reason: 'source_charge_unavailable'; source_state: PayoutSourceState };

/**
 * Capability pre-flight → funding-charge verification → source_transaction
 * transfer. Both payout paths (confirm-and-release, enforce-transfer-expiry)
 * call this and nothing else; the request body is byte-identical wherever it
 * originates, under the deterministic key from buildPayoutIdempotencyKey.
 */
export async function createSellerPayout(args: SellerPayoutArgs): Promise<SellerPayoutResult> {
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
  // Stripe is the source of truth here — a DB refund flag can lag, a charge
  // cannot. Also yields the charge id for source_transaction.
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
    args.sellerNetCents <= (sourceState.max_transferable ?? 0);
  if (!fundable) {
    return { ok: false, reason: 'source_charge_unavailable', source_state: sourceState };
  }

  // ── 3. The transfer, funded by THIS charge ──────────────────────────────
  const transfer = await stripeFetch<{ id: string }>('/transfers', {
    method: 'POST',
    idempotencyKey: buildPayoutIdempotencyKey(args.transferId, args.destination),
    body: {
      'amount':                String(args.sellerNetCents),
      'currency':              'usd',
      'destination':           args.destination,
      'source_transaction':    sourceState.charge_id as string,
      'metadata[transfer_id]': args.transferId,
      'metadata[payment_id]':  args.paymentId,
      'metadata[seller_id]':   args.sellerId,
    },
  });
  return { ok: true, transfer };
}
