import { supabase, supabaseUrl, supabaseAnonKey } from '@/src/lib/supabase';

type CreatePaymentIntentParams = {
  listingId: string;
  buyerId: string;
  mode: 'buy_now' | 'auction';
};

type PaymentIntentResult = {
  clientSecret: string;
  paymentIntentId: string;
  amount: number;
  serviceFee: number;
  total: number;
};

export async function createPaymentIntent(
  params: CreatePaymentIntentParams
): Promise<PaymentIntentResult> {
  // getUser() validates the token server-side and triggers a refresh if it is
  // close to expiry — more reliable than getSession() which returns a cached copy.
  const { data: { user: currentUser }, error: userErr } = await supabase.auth.getUser();

  if (userErr || !currentUser) {
    console.error('[payments] auth check failed:', userErr?.message);
    throw new Error('Not authenticated. Please sign in and try again.');
  }

  // After getUser() validates/refreshes, getSession() holds the fresh token.
  const { data: { session } } = await supabase.auth.getSession();

  if (!session?.access_token) {
    throw new Error('Not authenticated. Please sign in and try again.');
  }

  const url = `${supabaseUrl}/functions/v1/create-payment-intent`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
      'apikey': supabaseAnonKey!,
    },
    body: JSON.stringify({
      listing_id: params.listingId,
      mode: params.mode,
    }),
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    // Supabase gateway errors use { message } — function errors use { error }
    const reason = errorData.error ?? errorData.message ?? 'unknown';
    console.error('[payments] create-payment-intent failed:', response.status, reason, errorData);
    throw new Error(errorData.error || `Payment setup failed (${response.status}: ${reason})`);
  }

  const data = await response.json();
  return data as PaymentIntentResult;
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
  // Explicitly fetch the current session so we can attach the JWT
  const { data: { session } } = await supabase.auth.getSession();

  if (!session?.access_token) {
    console.error('[payments] No session for confirm-payment — skipping');
    return;
  }

  const url = `${supabaseUrl}/functions/v1/confirm-payment`;

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${session.access_token}`,
      'apikey': supabaseAnonKey!,
    },
    body: JSON.stringify({
      payment_intent_id: paymentIntentId,
    }),
  });

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    console.error('[payments] confirm-payment failed:', response.status, errorData.error ?? 'unknown');
    // Don't throw — payment already went through, this is just bookkeeping
    return;
  }
}
