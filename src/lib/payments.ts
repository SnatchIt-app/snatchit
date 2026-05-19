import { supabase } from '@/src/lib/supabase';

type CreatePaymentIntentParams = {
  listingId: string;
  buyerId: string;
  mode: 'buy_now' | 'auction';
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
const EXPECTED_ERROR_PATTERNS = [
  /cannot purchase your own/i,
  /listing.*unavailable/i,
  /listing.*not found/i,
  /not reserved for purchase/i,
  /reservation expired/i,
  /already sold/i,
  /already reserved/i,
  /auction.*not ended/i,
  /not the winner/i,
  /not authenticated/i,
];

export function isExpectedCheckoutError(message: string): boolean {
  return EXPECTED_ERROR_PATTERNS.some((re) => re.test(message));
}

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

/**
 * Confirm that a payment succeeded — updates the payments table record.
 * Calls the confirm-payment edge function which verifies with Stripe
 * that the PaymentIntent actually succeeded before updating status.
 *
 * Non-throwing: the Stripe charge already went through, so this is
 * best-effort bookkeeping. Failures are logged but not surfaced to the user.
 */
export async function confirmPaymentSuccess(
  paymentIntentId: string
): Promise<void> {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.access_token) {
    console.error('[payments] confirm-payment skipped — no session');
    return;
  }

  const { error: fnError } = await supabase.functions.invoke(
    'confirm-payment',
    {
      body: { payment_intent_id: paymentIntentId },
      headers: { Authorization: `Bearer ${session.access_token}` },
    }
  );

  if (fnError) {
    console.error('[payments] confirm-payment failed:', fnError.message);
    // Don't throw — payment already went through, this is just bookkeeping
  }
}
