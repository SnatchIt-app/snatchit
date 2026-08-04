/**
 * _shared/payouts.ts — the ONE way a seller payout reaches Stripe.
 *
 * Why this exists (2026-08-03 incident): confirm-and-release and the
 * enforce-transfer-expiry cron both created Stripe Transfers under the key
 * `payout_<transfer_id>` but with different `metadata[source]` values.
 * Stripe idempotency keys demand byte-identical parameters on every reuse,
 * so the second caller — and every retry after it for 24h — failed with
 *   "Keys for idempotent requests can only be used with the same
 *    parameters they were first used with."
 *
 * Key strategy (`payout_<transfer_id>_<destination>`):
 *   • Same logical payout (same transfer, same seller account) → same key,
 *     byte-identical body, no matter which path sends it or how often.
 *     Stripe replays one Transfer; money can never move twice.
 *   • Seller re-onboards (new destination account) → new key → a genuinely
 *     new attempt, instead of Stripe replaying a stale failure for 24h.
 *   • amount/currency derive from the immutable payments row, so they
 *     cannot diverge under one key.
 *
 * The requesting path is NOT part of the Stripe body — caller identity is
 * audit data and lives in payout_decisions.actor. Never add caller-varying
 * fields to this request.
 */
import { stripeFetch, stripeFetchRaw } from './stripe.ts';

export interface SellerPayoutArgs {
  transferId:     string;
  paymentId:      string;
  sellerId:       string;
  /** Seller's Stripe Connect account id (live mode). */
  destination:    string;
  /** Seller net in cents: payment.amount − payment.seller_fee. */
  sellerNetCents: number;
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

export type SellerPayoutResult =
  | { ok: true;  transfer: { id: string } }
  | { ok: false; reason: 'destination_not_ready'; destination_state: PayoutDestinationState };

/**
 * Capability PRE-FLIGHT, then transfer. The pre-flight is not an optimization:
 * Stripe stores an idempotency key's result — errors included — for 24h, so a
 * POST /transfers that fails (e.g. "needs the transfers capability enabled",
 * 2026-08-04) poisons the deterministic key until it expires, blocking the
 * payout for a day AFTER the seller fixes their account. Probing
 * capabilities.transfers first means the key is only ever spent on a request
 * that can succeed. The `_ready` suffix additionally separates this key
 * space from keys burned by pre-pre-flight code.
 */
export async function createSellerPayout(args: SellerPayoutArgs): Promise<SellerPayoutResult> {
  const probe = await stripeFetchRaw(`/accounts/${args.destination}`);
  const d    = probe.data as Record<string, unknown>;
  const caps = (d?.capabilities ?? {}) as Record<string, string>;
  const req  = (d?.requirements ?? {}) as Record<string, unknown>;
  const destinationState: PayoutDestinationState = {
    transfers_capability: caps.transfers ?? null,
    details_submitted:    (d?.details_submitted as boolean) ?? null,
    payouts_enabled:      (d?.payouts_enabled as boolean) ?? null,
    disabled_reason:      (req.disabled_reason as string) ?? null,
    currently_due:        (req.currently_due as string[]) ?? null,
    probe_error: probe.ok
      ? null
      : (probe.data as { error?: { message?: string } })?.error?.message ?? `HTTP ${probe.status}`,
  };

  if (!probe.ok || caps.transfers !== 'active') {
    return { ok: false, reason: 'destination_not_ready', destination_state: destinationState };
  }

  const transfer = await stripeFetch<{ id: string }>('/transfers', {
    method: 'POST',
    idempotencyKey: `payout_${args.transferId}_${args.destination}_ready`,
    body: {
      'amount':                String(args.sellerNetCents),
      'currency':              'usd',
      'destination':           args.destination,
      'metadata[transfer_id]': args.transferId,
      'metadata[payment_id]':  args.paymentId,
      'metadata[seller_id]':   args.sellerId,
    },
  });
  return { ok: true, transfer };
}
