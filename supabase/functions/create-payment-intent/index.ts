import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const SERVICE_FEE_RATE = 0.05;

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Returns true if the request is within limits (or if the DB check fails —
// fail-open so a DB hiccup never blocks a real payment).
async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<boolean> {
  try {
    const { data, error } = await supabase.rpc('check_rate_limit', {
      p_user_id:        userId,
      p_action:         action,
      p_max:            maxRequests,
      p_window_seconds: windowSeconds,
    });
    if (error) {
      console.warn('Rate limit RPC error (failing open):', error.message);
      return true;
    }
    return data === true;
  } catch (err) {
    console.warn('Rate limit check threw (failing open):', err);
    return true;
  }
}

// ── CORS origin whitelist ────────────────────────────────────────────────────
// React Native apps don't send an Origin header, so CORS only affects
// browser-based requests. Restrict to known web domains.
const ALLOWED_ORIGINS = [
  'https://snatchitapp.com',
  'https://www.snatchitapp.com',
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') ?? '';
  const allowedOrigin = ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  };
}

function getSecurityHeaders(): Record<string, string> {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'X-DNS-Prefetch-Control': 'off',
    'X-Download-Options': 'noopen',
    'X-Permitted-Cross-Domain-Policies': 'none',
    'Strict-Transport-Security': 'max-age=63072000; includeSubDomains; preload',
  };
}

function getResponseHeaders(req: Request): Record<string, string> {
  return {
    ...getCorsHeaders(req),
    ...getSecurityHeaders(),
  };
}

async function getAuthenticatedUserId(req: Request): Promise<string> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    throw new Error('Missing or invalid Authorization header');
  }

  const token = authHeader.replace('Bearer ', '');

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });

  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    throw new Error('Invalid or expired token');
  }

  return user.id;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  try {
    const buyerId = await getAuthenticatedUserId(req);

    // Rate limit: 5 requests per 60 seconds per user.
    // Use service-role client so the RPC can write to rate_limits.
    const rlClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const allowed = await checkRateLimit(rlClient, buyerId, 'create-payment-intent', 5, 60);
    if (!allowed) {
      return new Response(
        JSON.stringify({ error: 'Too many requests. Please try again later.' }),
        {
          status: 429,
          headers: {
            'Content-Type': 'application/json',
            'Retry-After': '60',
            ...getResponseHeaders(req),
          },
        },
      );
    }

    const { listing_id, mode } = await req.json();

    if (!listing_id || !mode) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: listing_id, mode' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Use service role to bypass RLS
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Fetch listing
    const { data: listing, error: listingErr } = await supabase
      .from('listings')
      .select('id, seller_id, current_bid, buy_now_price, buy_now_enabled, status, auction_status, winner_user_id, winning_bid_amount')
      .eq('id', listing_id)
      .single();

    if (listingErr || !listing) {
      return new Response(
        JSON.stringify({ error: 'Listing not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Buyer cannot purchase their own listing
    if (listing.seller_id === buyerId) {
      return new Response(
        JSON.stringify({ error: 'You cannot purchase your own listing' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Validate based on mode
    let amount: number;

    if (mode === 'buy_now') {
      if (listing.status !== 'reserved') {
        return new Response(
          JSON.stringify({ error: 'Listing is not reserved for purchase' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      if (!listing.buy_now_enabled || !listing.buy_now_price) {
        return new Response(
          JSON.stringify({ error: 'Buy Now is not available for this listing' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      amount = listing.buy_now_price;
    } else if (mode === 'auction') {
      if (listing.auction_status !== 'ended') {
        return new Response(
          JSON.stringify({ error: 'Auction has not ended yet' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      if (listing.winner_user_id !== buyerId) {
        return new Response(
          JSON.stringify({ error: 'You are not the auction winner' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      amount = listing.winning_bid_amount ?? listing.current_bid;
    } else {
      return new Response(
        JSON.stringify({ error: 'Invalid mode. Must be buy_now or auction' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Listing prices are stored in dollars. Convert to cents for Stripe
    // (Stripe requires smallest currency unit: $50 → 5000).
    const amountCents     = Math.round(amount * 100);
    const serviceFeeCents = Math.round(amountCents * SERVICE_FEE_RATE);
    const totalCents      = amountCents + serviceFeeCents;

    // Check for existing payment (idempotency)
    const { data: existingPayments } = await supabase
      .from('payments')
      .select('id, stripe_payment_intent_id, status')
      .eq('listing_id', listing_id)
      .eq('buyer_id', buyerId)
      .eq('mode', mode)
      .in('status', ['pending', 'succeeded']);

    if (existingPayments && existingPayments.length > 0) {
      const succeededPayment = existingPayments.find((p: { status: string }) => p.status === 'succeeded');
      if (succeededPayment) {
        return new Response(
          JSON.stringify({ error: 'Payment already completed for this listing' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }

      const pendingPayment = existingPayments.find((p: { status: string }) => p.status === 'pending');
      if (pendingPayment) {
        // Retrieve existing PaymentIntent from Stripe
        const existingPiRes = await fetch(
          `https://api.stripe.com/v1/payment_intents/${pendingPayment.stripe_payment_intent_id}`,
          {
            method: 'GET',
            headers: {
              'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
            },
          }
        );
        const existingPiData = await existingPiRes.json();

        if (existingPiRes.ok) {
          // If the PI already succeeded on Stripe's side, the payment is done —
          // block re-entry rather than returning a spent client_secret to the
          // PaymentSheet (which would cause an "unexpected error" on the client).
          if (existingPiData.status === 'succeeded') {
            return new Response(
              JSON.stringify({ error: 'Payment already completed for this listing' }),
              { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
            );
          }

          if (existingPiData.client_secret) {
            return new Response(
              JSON.stringify({
                clientSecret: existingPiData.client_secret,
                paymentIntentId: existingPiData.id,
                amount: amountCents,
                serviceFee: serviceFeeCents,
                total: totalCents,
              }),
              { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
            );
          }
        }
      }
    }

    // Create Stripe PaymentIntent
    const stripeRes = await fetch('https://api.stripe.com/v1/payment_intents', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Idempotency-Key': `pi_${listing_id}_${buyerId}_${mode}_${totalCents}`,
      },
      body: new URLSearchParams({
        'amount': String(totalCents),
        'currency': 'usd',
        'automatic_payment_methods[enabled]': 'true',
        'metadata[listing_id]': listing_id,
        'metadata[buyer_id]': buyerId,
        'metadata[seller_id]': listing.seller_id,
        'metadata[mode]': mode,
      }).toString(),
    });

    const stripeData = await stripeRes.json();

    if (!stripeRes.ok) {
      console.error('Stripe error:', stripeData.error?.type, stripeData.error?.code, stripeData.error?.message);
      return new Response(
        JSON.stringify({ error: 'Failed to create payment intent' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Record payment in database
    const { error: insertErr } = await supabase
      .from('payments')
      .insert({
        listing_id,
        buyer_id: buyerId,
        seller_id: listing.seller_id,
        amount: amountCents,
        service_fee: serviceFeeCents,
        total: totalCents,
        stripe_payment_intent_id: stripeData.id,
        status: 'pending',
        mode,
      });

    if (insertErr) {
      console.error('DB insert error:', insertErr);
      // Cancel the orphaned PaymentIntent
      await fetch(`https://api.stripe.com/v1/payment_intents/${stripeData.id}/cancel`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
        },
      });
      return new Response(
        JSON.stringify({ error: 'Failed to record payment. Please try again.' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    return new Response(
      JSON.stringify({
        clientSecret: stripeData.client_secret,
        paymentIntentId: stripeData.id,
        amount: amountCents,
        serviceFee: serviceFeeCents,
        total: totalCents,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  } catch (err) {
    console.error('Edge function error:', err);
    const message = err instanceof Error ? err.message : '';
    const isAuthError = /authorization|token/i.test(message);
    return new Response(
      JSON.stringify({ error: isAuthError ? message : 'Internal server error' }),
      { status: isAuthError ? 401 : 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});
