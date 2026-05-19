import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetch, stripeFetchRaw, STRIPE_MOBILE_API_VERSION } from '../_shared/stripe.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── Marketplace fee model (10/10) ────────────────────────────────────────────
// Buyer pays listing × (1 + BUYER_FEE_RATE).
// Seller receives listing × (1 − SELLER_FEE_RATE) at payout release.
// Platform retains (BUYER_FEE_RATE + SELLER_FEE_RATE) × listing
// (before Stripe processing fees of ~2.9% + $0.30 per charge).
const BUYER_FEE_RATE  = 0.10;
const SELLER_FEE_RATE = 0.10;

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Fail-CLOSED: distinguish "allowed", "over_limit", and "error" so callers can
// return 429 vs 503 appropriately. The DB function (check_rate_limit) also
// returns FALSE on internal error after migration 021.
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  action: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<RateLimitResult> {
  try {
    const { data, error } = await supabase.rpc('check_rate_limit', {
      p_user_id:        userId,
      p_action:         action,
      p_max:            maxRequests,
      p_window_seconds: windowSeconds,
    });
    if (error) {
      console.warn('Rate limit RPC error (failing closed):', error.message);
      return 'error';
    }
    return data === true ? 'allowed' : 'over_limit';
  } catch (err) {
    console.warn('Rate limit check threw (failing closed):', err);
    return 'error';
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

// Returns BOTH the user id and the verified email, so we can attach the
// buyer's email to the Stripe Customer in one round-trip without a second
// auth.admin call.
async function getAuthenticatedUser(req: Request): Promise<{ id: string; email: string | null }> {
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

  return { id: user.id, email: user.email ?? null };
}

// `STRIPE_MOBILE_API_VERSION` is imported from `_shared/stripe.ts` and is
// only attached to the ephemeral_keys POST below. All other Stripe calls
// inherit STRIPE_API_VERSION (the server-side default pin) via stripeFetch.

// ── Stripe Customer get-or-create + ephemeral key ───────────────────────────
//
// 1. If `profiles.stripe_customer_id` is set AND that customer still exists
//    in Stripe, reuse it.
// 2. Otherwise, create a fresh Stripe Customer for this buyer and persist
//    the id back to `profiles.stripe_customer_id`.
// 3. Create a short-lived ephemeral key for the (now-known) customer id so
//    PaymentSheet can surface that customer's saved payment methods.
//
// The returned object is consumed by the JSON response below and by
// initPaymentSheet on the client (P1-03).
async function ensureStripeCustomerAndEphemeralKey(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  email: string | null,
): Promise<{ customerId: string; ephemeralKeySecret: string }> {
  // ── (a) Look up cached customer id on the profile ──────────────────────
  const { data: profile } = await supabase
    .from('profiles')
    .select('stripe_customer_id')
    .eq('id', userId)
    .single();

  let customerId = (profile?.stripe_customer_id as string | null) ?? null;

  // ── (b) Verify the cached id still exists in Stripe (test-mode wipes,
  //         account migrations, etc. can leave stale rows). ─────────────────
  if (customerId) {
    const probe = await stripeFetchRaw(`/customers/${customerId}`);
    if (!probe.ok) {
      console.warn('Stripe customer not found, will create a new one', { stale_id: customerId });
      customerId = null;
    }
  }

  // ── (c) Create a fresh customer if needed ──────────────────────────────
  if (!customerId) {
    const customerBody: Record<string, string> = { 'metadata[user_id]': userId };
    if (email) customerBody.email = email;

    const created = await stripeFetch<{ id: string }>('/customers', {
      method:         'POST',
      body:           customerBody,
      // Idempotent on (user_id) — even if two PI requests race, both
      // resolve to the same customer.
      idempotencyKey: `customer_${userId}`,
    });
    customerId = created.id;

    const { error: updErr } = await supabase
      .from('profiles')
      .update({ stripe_customer_id: customerId })
      .eq('id', userId);
    if (updErr) {
      // Non-fatal: the customer exists in Stripe. Worst case, next checkout
      // creates a second customer for this user. The Stripe-side idempotency
      // key (above) protects against that within a 24h window.
      console.warn('Failed to persist stripe_customer_id (continuing):', updErr.message);
    }
  }

  // ── (d) Create a short-lived ephemeral key for THIS customer ───────────
  // Stripe ephemeral keys expire after ~1 hour. A fresh one is created on
  // every PaymentIntent request so PaymentSheet always has a valid token.
  // MUST use STRIPE_MOBILE_API_VERSION (matching the mobile SDK) — that's
  // the only Stripe call in the codebase that overrides the server-side
  // default version pin.
  const ek = await stripeFetch<{ secret?: string }>('/ephemeral_keys', {
    method:        'POST',
    body:          { customer: customerId },
    stripeVersion: STRIPE_MOBILE_API_VERSION,
  });
  if (!ek?.secret) {
    throw new Error('Stripe ephemeral_keys returned no secret');
  }
  return { customerId, ephemeralKeySecret: ek.secret };
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  try {
    const buyer = await getAuthenticatedUser(req);
    const buyerId = buyer.id;

    // Rate limit: 5 requests per 60 seconds per user.
    // Use service-role client so the RPC can write to rate_limits.
    const rlClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const rl = await checkRateLimit(rlClient, buyerId, 'create-payment-intent', 5, 60);
    if (rl === 'error') {
      // Fail-closed on rate-limiter error — never silently disable abuse protection.
      return new Response(
        JSON.stringify({ error: 'Service temporarily unavailable. Please try again shortly.' }),
        {
          status: 503,
          headers: {
            'Content-Type': 'application/json',
            'Retry-After': '30',
            ...getResponseHeaders(req),
          },
        },
      );
    }
    if (rl === 'over_limit') {
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
    //
    // 10/10 fee model:
    //   amountCents      = listing price (what seller listed) in cents
    //   buyerFeeCents    = 10% added on top of listing — what buyer is charged
    //                      ABOVE the listing price
    //   sellerFeeCents   = 10% withheld from listing at payout release
    //   totalCents       = listing + buyer fee = what Stripe charges the card
    //   Seller net (computed at payout time): amountCents − sellerFeeCents
    //   Platform gross retained: buyerFeeCents + sellerFeeCents
    const amountCents     = Math.round(amount * 100);
    const buyerFeeCents   = Math.round(amountCents * BUYER_FEE_RATE);
    const sellerFeeCents  = Math.round(amountCents * SELLER_FEE_RATE);
    const totalCents      = amountCents + buyerFeeCents;

    // ── P1-03: Get-or-create Stripe Customer + ephemeral key (hoisted) ──
    // Hoisted above the existing-PI lookup so the response shape is
    // identical on every code path (new PI, retrieved-pending PI). A
    // fresh ephemeral key is created each call — short-lived per Stripe.
    const customerCtx = await ensureStripeCustomerAndEphemeralKey(
      supabase,
      buyerId,
      buyer.email,
    );

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
        const existingPi = await stripeFetchRaw(
          `/payment_intents/${pendingPayment.stripe_payment_intent_id}`,
        );
        const existingPiData = existingPi.data as { id?: string; status?: string; client_secret?: string };

        if (existingPi.ok) {
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
                clientSecret:               existingPiData.client_secret,
                paymentIntentId:            existingPiData.id,
                amount:                     amountCents,
                buyer_fee:                  buyerFeeCents,
                seller_fee:                 sellerFeeCents,
                total:                      totalCents,
                // P1-03 — fresh ephemeral key on every retrieval
                customerId:                 customerCtx.customerId,
                customerEphemeralKeySecret: customerCtx.ephemeralKeySecret,
              }),
              { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
            );
          }
        }
      }
    }

    // Create Stripe PaymentIntent
    // (customerCtx was created above, hoisted so both code paths share it)
    let stripeData: { id: string; client_secret: string };
    try {
      stripeData = await stripeFetch<{ id: string; client_secret: string }>('/payment_intents', {
        method: 'POST',
        idempotencyKey: `pi_${listing_id}_${buyerId}_${mode}_${totalCents}`,
        body: {
          'amount':                              String(totalCents),
          'currency':                            'usd',
          'automatic_payment_methods[enabled]':  'true',
          'customer':                            customerCtx.customerId,
          // 'on_session' = card details collected with user in front of phone.
          // This attaches the card to the customer after the charge succeeds,
          // so it appears as a saved card on the next checkout. 'off_session'
          // would be for future merchant-initiated charges, which we don't do.
          'setup_future_usage':                  'on_session',
          'metadata[listing_id]':                listing_id,
          'metadata[buyer_id]':                  buyerId,
          'metadata[seller_id]':                 listing.seller_id,
          'metadata[mode]':                      mode,
        },
      });
    } catch (stripeErr) {
      console.error('Stripe error:', stripeErr instanceof Error ? stripeErr.message : stripeErr);
      return new Response(
        JSON.stringify({ error: 'Failed to create payment intent' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // Record payment in database (10/10 fee model — see migration 022).
    //   amount     = listing price in cents (what seller listed)
    //   buyer_fee  = 10% added on top — what the buyer pays above amount
    //   seller_fee = 10% withheld at payout — seller will receive
    //                amount − seller_fee
    //   total      = amount + buyer_fee = card charge
    const { error: insertErr } = await supabase
      .from('payments')
      .insert({
        listing_id,
        buyer_id:   buyerId,
        seller_id:  listing.seller_id,
        amount:     amountCents,
        buyer_fee:  buyerFeeCents,
        seller_fee: sellerFeeCents,
        total:      totalCents,
        stripe_payment_intent_id: stripeData.id,
        status:     'pending',
        mode,
      });

    if (insertErr) {
      console.error('DB insert error:', insertErr);
      // Cancel the orphaned PaymentIntent. Errors here are non-fatal —
      // the original request already failed and the caller will retry.
      try {
        await stripeFetch(`/payment_intents/${stripeData.id}/cancel`, { method: 'POST' });
      } catch (cancelErr) {
        console.warn('PI cancel after DB-insert-fail:', cancelErr);
      }
      return new Response(
        JSON.stringify({ error: 'Failed to record payment. Please try again.' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    return new Response(
      JSON.stringify({
        clientSecret:               stripeData.client_secret,
        paymentIntentId:            stripeData.id,
        amount:                     amountCents,
        buyer_fee:                  buyerFeeCents,
        seller_fee:                 sellerFeeCents,
        total:                      totalCents,
        // P1-03: PaymentSheet needs both to surface saved cards.
        customerId:                 customerCtx.customerId,
        customerEphemeralKeySecret: customerCtx.ephemeralKeySecret,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    const isAuthError = /authorization|token/i.test(message);
    // Auth errors (expired/invalid tokens) are routine 401s — don't flood
    // Sentry quota. Every other path is a real bug or Stripe-side issue.
    if (isAuthError) {
      console.warn('create-payment-intent: auth error:', message);
    } else {
      await captureException('create-payment-intent', err);
    }
    return new Response(
      JSON.stringify({ error: isAuthError ? message : 'Internal server error' }),
      { status: isAuthError ? 401 : 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});
