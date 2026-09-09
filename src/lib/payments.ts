import { supabase } from '@/src/lib/supabase';

type CreatePaymentIntentParams = {
  listingId: string;
  buyerId: string;
  mode: 'buy_now' | 'auction';
  /** All-in total (cents) the buyer was shown — server rejects a mismatch. */
  expectedTotalCents?: number;
};

type PaymentIntentResult = {
  clientSecret:    string;
  paymentIntentId: string;
  /** Listing price in cents (what the seller listed). */
  amount:          number;
  /** Buyer fee in cents (10% of amount). Added on top of amount. */
  buyer_fee:       number;
  /** Seller fee in cents (10% of amount). Withheld at payout release. */
  seller_fee:      number;
  /** Card charge total in cents = amount + buyer_fee. */
  total:           number;
  /** Stripe Customer id for this buyer (P1-03). PaymentSheet uses this to
   *  surface saved cards on the next checkout. */
  customerId:                 string;
  /** Short-lived ephemeral key tied to customerId (P1-03). PaymentSheet
   *  uses this to read the customer's saved payment methods. Single-use:
   *  the server issues a fresh key on every request. */
  customerEphemeralKeySecret: string;
};

// Expected business-rule errors that should show in the UI without
// polluting logs. These are normal user-facing outcomes, not system failures.
//
// Callers: createPaymentIntent (below, log suppression),
// CheckoutNative.tsx setupPayment (:244, verbatim passthrough) and
// classifySettlement (below, terminal-refusal recognition).
const EXPECTED_ERROR_PATTERNS = [
  /cannot purchase your own/i,
  /listing.*unavailable/i,
  /listing.*not found/i,
  /not reserved for purchase/i,
  /reservation expired/i,
  // Two wordings for one fact: the edge functions say 'This listing is already
  // sold.' (create-payment-intent/index.ts :451, :457, :480) while the SQL
  // raises 'This listing has already been sold.' (migration
  // 20260906100000_checkout_reservation_authority.sql :207, :254, :309). The
  // bare /already sold/ never matched the SQL wording.
  /already (been )?sold/i,
  /already reserved/i,
  /auction.*not ended/i,
  /not the winner/i,
  /not authenticated/i,
];

export function isExpectedCheckoutError(message: string): boolean {
  return EXPECTED_ERROR_PATTERNS.some((re) => re.test(message));
}

// ── Post-charge settlement ──────────────────────────────────────────────────
// Everything below runs AFTER the Stripe PaymentSheet returned success, i.e.
// after the buyer's card may already be charged. The three outcomes are not
// interchangeable and must never be collapsed:
//
//   completed — the sale is recorded. Success UI.
//   pending   — nothing is wrong and nothing is lost: the charge is captured
//               or still settling at Stripe, and the webhook / reconciliation
//               sweep settle it independently. Calm state, NEVER an alert.
//   failed    — we hold the buyer's money and cannot fulfil the order. The
//               only outcome allowed to say "contact support".
export type SettlementOutcome = 'completed' | 'pending' | 'failed';

// Settlement refusals that mean "not yet", not "never".
//
// Deliberately NOT the same list as EXPECTED_ERROR_PATTERNS above. That list
// describes PRE-payment checkout refusals, where /already sold/i means
// "someone bought it before you paid" — benign, nothing was taken. AFTER the
// charge the same words mean the opposite: mark_listing_sold /
// complete_auction_payment raise 'This listing has already been sold.' only
// when settle_listing_for_payment returns 'unfulfillable', i.e. the listing is
// bound to a DIFFERENT payment (migration
// 20260906100000_checkout_reservation_authority.sql :205-210 / :249-254;
// pgTAP supabase/tests/120_reservation_lifecycle.sql F2). Filtering that away
// would show "Purchase complete!" for an order that can never be fulfilled.
// isExpectedCheckoutError therefore keeps its two existing callers unchanged
// (createPaymentIntent below; CheckoutNative.tsx setupPayment) and is reused
// in classifySettlement to recognise TERMINAL refusals — not benign ones.
const SETTLEMENT_PENDING_PATTERNS = [
  // mark_listing_sold / complete_auction_payment before a Stripe-verified
  // writer promoted the payments row to `succeeded` (migration
  // 20260906100000 :193 / :237). The single most common false alarm.
  /no verified payment found/i,
  /must be confirmed before/i,
  // settle_listing_for_payment core, same window (migration :112-114).
  /payment has not succeeded/i,
  // The RPC never reached the server — we know nothing, so we claim nothing.
  /network request failed/i,
  /failed to fetch/i,
  /fetch failed/i,
  /timed out/i,
  /timeout/i,
];

export function isSettlementPendingError(message: string): boolean {
  return SETTLEMENT_PENDING_PATTERNS.some((re) => re.test(message));
}

/** One source of truth for what the buyer is told after the charge. */
export const SETTLEMENT_COPY: Record<
  SettlementOutcome,
  { alert: boolean; title: string; body: string }
> = {
  completed: {
    alert: false,
    title: 'Purchase complete!',
    body:  'Your tickets are confirmed. Check your email for transfer instructions.',
  },
  pending: {
    alert: false,
    title: 'Payment received',
    body:
      "You're all set. We're finalizing your order — it will appear in your " +
      "purchases within a few minutes. Your payment is safe; please don't pay again.",
  },
  failed: {
    alert: true,
    title: 'Payment received',
    body:
      "Your payment went through, but we couldn't complete this order. Please " +
      "don't pay again — contact support and we'll sort it out right away.",
  },
};

export async function createPaymentIntent(
  params: CreatePaymentIntentParams
): Promise<PaymentIntentResult> {
  // Explicitly read the session and inject the access token as a header so
  // fetchWithAuth never falls back to the sb_publishable_* anon key.
  // (_getAccessToken() returns supabaseKey when getSession() resolves null,
  // which happens during stale-token sign-out races; the gateway then rejects
  // with 401 "Invalid JWT" because sb_publishable_* is not a JWT.)
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    throw new Error('Not authenticated. Please sign in and try again.');
  }

  const { data, error: fnError } = await supabase.functions.invoke<PaymentIntentResult>(
    'create-payment-intent',
    {
      body: {
        listing_id: params.listingId,
        mode: params.mode,
        // Server authority: send the all-in total the buyer was shown; the
        // server 409s if its canonical calculation disagrees.
        expected_total_cents: params.expectedTotalCents,
      },
      headers: { Authorization: `Bearer ${session.access_token}` },
    }
  );

  if (fnError || !data) {
    // FunctionsHttpError stores the raw Response in .context — read it once
    // to surface the function's own { error } / { message } body when present.
    let reason = fnError?.message ?? 'Payment setup failed';
    try {
      const ctx = (fnError as any)?.context;
      if (ctx && typeof ctx.json === 'function') {
        const body = await ctx.json();
        reason = body.error ?? body.message ?? reason;
      }
    } catch {}

    // Only log unexpected/system errors — business-rule rejections are normal
    if (!isExpectedCheckoutError(reason)) {
      console.error('[payments] create-payment-intent failed:', reason);
    }
    throw new Error(reason);
  }

  return data;
}

/** What confirm-payment told us. Previously discarded — see below. */
export type ConfirmPaymentResult = {
  /** The call itself completed (no transport / function error). */
  reachable: boolean;
  /** confirm-payment fetched the PaymentIntent and Stripe said `succeeded`.
   *  `false` with reachable=true means Stripe has NOT succeeded it yet and the
   *  function wrote nothing — genuinely uncertain, not a failure. */
  verified: boolean;
  /** settle_verified_payment's outcome: settled | already_settled | refunded |
   *  not_succeeded | canceled | unfulfillable | unknown_payment |
   *  binding_mismatch (confirm-payment/index.ts:315-323). */
  outcome: string | null;
  transferId: string | null;
};

/**
 * Confirm that a payment succeeded — settles it through the verified-settlement
 * contract. Calls the confirm-payment edge function, which verifies with Stripe
 * that the PaymentIntent actually succeeded before writing anything.
 *
 * Non-throwing: the Stripe charge already went through, so a failure here is
 * never surfaced as a payment failure.
 *
 * The response body used to be discarded, which is why the screen could not
 * tell "settled" from "Stripe hasn't succeeded it yet" and treated both as a
 * problem. It is now returned so finalizePurchase can distinguish them.
 */
export async function confirmPaymentSuccess(
  paymentIntentId: string
): Promise<ConfirmPaymentResult> {
  const unreachable: ConfirmPaymentResult = {
    reachable: false, verified: false, outcome: null, transferId: null,
  };

  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    console.error('[payments] confirm-payment skipped — no session');
    return unreachable;
  }

  const { data, error: fnError } = await supabase.functions.invoke<{
    success?: boolean; stripe_verified?: boolean;
    outcome?: string | null; transfer_id?: string | null;
  }>(
    'confirm-payment',
    {
      body: { payment_intent_id: paymentIntentId },
      headers: { Authorization: `Bearer ${session.access_token}` },
    }
  );

  if (fnError) {
    console.error('[payments] confirm-payment failed:', fnError.message);
    // Don't throw — payment already went through, this is just bookkeeping
    return unreachable;
  }

  return {
    reachable:  true,
    verified:   data?.stripe_verified === true,
    outcome:    data?.outcome ?? null,
    transferId: data?.transfer_id ?? null,
  };
}

/**
 * Decide what the buyer is told after the charge, from the two server verdicts
 * we have: confirm-payment's (Stripe-verified, service_role) and the shipped
 * settlement RPC's.
 *
 * Order matters — the first match wins:
 *   1. the RPC succeeded                      → completed
 *   2. confirm-payment already settled the sale → completed (it holds
 *      service_role and just wrote through settle_verified_payment, so its
 *      outcome outranks a follow-up refusal from the legacy RPC)
 *   3. a known "not yet" refusal              → pending
 *   4. a TERMINAL business refusal            → failed (this is where
 *      /already sold/i lands after the charge: the listing is bound to another
 *      payment and this buyer cannot be served)
 *   5. Stripe has not succeeded the charge    → pending (nothing to settle yet)
 *   6. anything else                          → failed
 */
export function classifySettlement(input: {
  confirm: ConfirmPaymentResult;
  rpcErrorMessage: string | null;
}): SettlementOutcome {
  const { confirm, rpcErrorMessage } = input;
  if (!rpcErrorMessage) return 'completed';
  if (confirm.outcome === 'settled' || confirm.outcome === 'already_settled') return 'completed';
  if (isSettlementPendingError(rpcErrorMessage)) return 'pending';
  if (isExpectedCheckoutError(rpcErrorMessage)) return 'failed';
  if (confirm.reachable && !confirm.verified) return 'pending';
  return 'failed';
}

export type FinalizePurchaseResult = {
  outcome: SettlementOutcome;
  transferId: string | null;
  /** Operator-facing detail for logs / Sentry. Never shown to the buyer. */
  detail: string | null;
};

/**
 * The whole post-PaymentSheet sequence, in one place for Buy Now and auctions.
 * Callers render SETTLEMENT_COPY[outcome] and alert only when it says to.
 */
export async function finalizePurchase(params: {
  listingId: string;
  userId: string;
  paymentIntentId: string | null;
  mode: 'buy_now' | 'auction';
}): Promise<FinalizePurchaseResult> {
  const confirm = params.paymentIntentId
    ? await confirmPaymentSuccess(params.paymentIntentId)
    : { reachable: false, verified: false, outcome: null, transferId: null };

  const settleRpc = params.mode === 'auction' ? 'complete_auction_payment' : 'mark_listing_sold';
  const { error: rpcError } = await supabase.rpc(settleRpc, {
    p_listing_id: params.listingId,
    p_user_id:    params.userId,
  });

  const rpcErrorMessage = rpcError?.message ?? null;
  const outcome = classifySettlement({ confirm, rpcErrorMessage });
  const detail = rpcErrorMessage
    ? `${settleRpc}: ${rpcErrorMessage}${rpcError?.code ? ` (${rpcError.code})` : ''}`
    : null;

  if (outcome === 'failed') {
    console.error(`[checkout] settlement failed after payment — ${detail}`);
  } else if (outcome === 'pending') {
    // Expected race, not a system failure: the webhook / sweep settle it.
    console.warn(`[checkout] settlement pending after payment — ${detail}`);
  }

  // Only chase the transfer once the sale is actually recorded:
  // ensure_transfer_exists demands a succeeded payment (migration 061) and
  // would just fail noisily while the outcome is still uncertain.
  let transferId = confirm.transferId;
  if (outcome === 'completed') {
    const { error: transferErr } = await supabase.rpc('ensure_transfer_exists', {
      p_listing_id: params.listingId,
    });
    if (transferErr) {
      console.warn('[checkout] ensure_transfer_exists error:', transferErr.message);
    }

    const { data: transferRow } = await supabase
      .from('transfers')
      .select('id')
      .eq('listing_id', params.listingId)
      .maybeSingle();
    if (transferRow?.id) transferId = transferRow.id;
  }

  return { outcome, transferId, detail };
}
