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
import { stripeFetch } from './stripe.ts';

export interface SellerPayoutArgs {
  transferId:     string;
  paymentId:      string;
  sellerId:       string;
  /** Seller's Stripe Connect account id (live mode). */
  destination:    string;
  /** Seller net in cents: payment.amount − payment.seller_fee. */
  sellerNetCents: number;
}

export async function createSellerPayout(args: SellerPayoutArgs): Promise<{ id: string }> {
  return await stripeFetch<{ id: string }>('/transfers', {
    method: 'POST',
    idempotencyKey: `payout_${args.transferId}_${args.destination}`,
    body: {
      'amount':                String(args.sellerNetCents),
      'currency':              'usd',
      'destination':           args.destination,
      'metadata[transfer_id]': args.transferId,
      'metadata[payment_id]':  args.paymentId,
      'metadata[seller_id]':   args.sellerId,
    },
  });
}
