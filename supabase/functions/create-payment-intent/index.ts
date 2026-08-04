import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetch, stripeFetchRaw, STRIPE_MOBILE_API_VERSION } from '../_shared/stripe.ts';
import { feeBreakdown, dollarsToCents, totalMismatch } from '../_shared/money.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// ── Stage logging ────────────────────────────────────────────────────────────
// One structured line per pipeline stage so a production failure pinpoints
// its stage and cause from the edge logs alone (2026-08-03 incident: a 500
// here surfaced client-side as only "Failed to record payment"). Never log
// secret material — no keys, tokens, client_secrets, or emails.
function logStage(stage: string, detail: Record<string, unknown> = {}) {
  console.log(JSON.stringify({ tag: 'cpi-stage', stage, ...detail }));
}

// ── Marketplace fee model (10/10) ────────────────────────────────────────────
// Canonical math lives in _shared/money.ts (single source of truth):
// buyer pays base + 10%, seller receives base − 10%, both fees computed
// from the BASE price in integer cents, rounded half-up.

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
    logStage('auth', { ok: true, buyer_id: buyerId });

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

    const { listing_id, mode, expected_total_cents } = await req.json();

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

    logStage('listing-lookup', {
      listing_id,
      mode,
      found:          !!listing,
      status:         listing?.status ?? null,
      auction_status: listing?.auction_status ?? null,
      error:          listingErr?.message ?? null,
    });

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

    // Listing prices are stored in whole dollars. Convert once, then all fee
    // math is the canonical integer-cent model in _shared/money.ts:
    //   amountCents    = base listing price (what the seller listed)
    //   buyerFeeCents  = round(base × 10%) added ON TOP — buyer pays it
    //   sellerFeeCents = round(base × 10%) withheld at payout — from BASE,
    //                    never from the buyer's all-in total
    //   totalCents     = base + buyer fee = what Stripe charges the card
    const breakdown = feeBreakdown(dollarsToCents(amount));
    const amountCents    = breakdown.baseCents;
    const buyerFeeCents  = breakdown.buyerFeeCents;
    const sellerFeeCents = breakdown.sellerFeeCents;
    const totalCents     = breakdown.buyerTotalCents;

    // ── Server authority: reject a client whose displayed total disagrees ──
    // The client MAY send the all-in total it showed the buyer; if that claim
    // disagrees with the canonical calculation we refuse to charge (the buyer
    // would pay a number they never saw). Legacy clients that send nothing
    // (all pre-all-in builds, incl. 1.0 build 7) skip the check entirely —
    // the server charges its own calculation either way and never uses a
    // client-supplied amount.
    if (totalMismatch(expected_total_cents, totalCents)) {
      console.warn('create-payment-intent: client/server total mismatch:', {
        listing_id, mode, expected_total_cents, server_total_cents: totalCents,
      });
      return new Response(
        JSON.stringify({
          error: 'Price changed. Please review the updated total and try again.',
          server_total_cents: totalCents,
        }),
        { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // ── P1-03: Get-or-create Stripe Customer + ephemeral key (hoisted) ──
    // Hoisted above the existing-PI lookup so the response shape is
    // identical on every code path (new PI, retrieved-pending PI). A
    // fresh ephemeral key is created each call — short-lived per Stripe.
    const customerCtx = await ensureStripeCustomerAndEphemeralKey(
      supabase,
      buyerId,
      buyer.email,
    );
    logStage('stripe-customer', { customer_id: customerCtx.customerId });

    // Fetch EVERY prior payment row for this (listing, buyer, mode), terminal
    // ones included. Failed attempts don't block a retry, but they MUST salt
    // the Stripe idempotency key below: after a failed attempt this function
    // cancels the PaymentIntent, and Stripe's 24h idempotency replay would
    // otherwise hand back that same canceled PI on every retry — whose id
    // then collides with the failed row under payments' UNIQUE
    // (stripe_payment_intent_id). That exact chain 500'd every checkout
    // retry on 2026-08-03.
    const { data: allPayments, error: paymentsErr } = await supabase
      .from('payments')
      .select('id, stripe_payment_intent_id, status')
      .eq('listing_id', listing_id)
      .eq('buyer_id', buyerId)
      .eq('mode', mode);

    const existingPayments = (allPayments ?? []) as
      { id: string; stripe_payment_intent_id: string; status: string }[];
    logStage('payments-lookup', {
      count:    existingPayments.length,
      statuses: existingPayments.map((p) => p.status),
      error:    paymentsErr?.message ?? null,
    });

    if (existingPayments.some((p) => p.status === 'succeeded')) {
      return new Response(
        JSON.stringify({ error: 'Payment already completed for this listing' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    let failedAttempts = existingPayments.filter((p) => p.status === 'failed').length;

    const pendingPayment = existingPayments.find((p) => p.status === 'pending');
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

        if (existingPiData.status === 'canceled') {
          // The pending row points at a dead PI (canceled after an earlier
          // failure). A canceled PI can never be confirmed — returning its
          // client_secret would hard-fail the PaymentSheet. Retire the row
          // and fall through to mint a fresh PI for this attempt.
          logStage('pending-pi-canceled', { payment_row: pendingPayment.id, pi_id: existingPiData.id });
          const { error: retireErr } = await supabase
            .from('payments')
            .update({ status: 'failed' })
            .eq('id', pendingPayment.id)
            .eq('status', 'pending');
          if (retireErr) {
            console.warn('Failed to retire dead pending payment (continuing):', retireErr.message);
          }
          failedAttempts += 1;
        } else if (existingPiData.client_secret) {
          logStage('reuse-pending-pi', { pi_id: existingPiData.id, pi_status: existingPiData.status });
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

    // Create Stripe PaymentIntent
    // (customerCtx was created above, hoisted so both code paths share it)
    //
    // Idempotency: identical double-taps must replay the same PI, but a retry
    // AFTER a failed attempt must mint a fresh one — a canceled PI can never
    // be confirmed, and its id already occupies the failed row's UNIQUE slot.
    // Salting with the failed-attempt count gives both. First attempts keep
    // the historical key shape unchanged.
    const piIdempotencyKey =
      `pi_${listing_id}_${buyerId}_${mode}_${totalCents}` +
      (failedAttempts > 0 ? `_r${failedAttempts}` : '');
    const piBody = {
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
    };

    type PiResponse = { id: string; client_secret: string; status?: string; livemode?: boolean };
    let stripeData: PiResponse;
    try {
      stripeData = await stripeFetch<PiResponse>('/payment_intents', {
        method: 'POST',
        idempotencyKey: piIdempotencyKey,
        body: piBody,
      });
      if (stripeData.status === 'canceled') {
        // Idempotency replay still returned a dead PI (possible if a failed
        // row was removed out-of-band, shifting the salt back onto a spent
        // key). One uniquely-salted retry breaks out of the replay window.
        logStage('pi-replay-canceled', { pi_id: stripeData.id });
        stripeData = await stripeFetch<PiResponse>('/payment_intents', {
          method: 'POST',
          idempotencyKey: `${piIdempotencyKey}_u${crypto.randomUUID()}`,
          body: piBody,
        });
      }
    } catch (stripeErr) {
      const detail = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      logStage('pi-create-failed', { error: detail });
      console.error('Stripe error:', detail);
      return new Response(
        JSON.stringify({ error: 'Failed to create payment intent' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }
    logStage('pi-created', {
      pi_id:        stripeData.id,
      pi_status:    stripeData.status ?? null,
      livemode:     stripeData.livemode ?? null,
      amount_cents: totalCents,
      customer_id:  customerCtx.customerId,
    });

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
      const e = insertErr as { code?: string; message?: string; details?: string; hint?: string };
      logStage('db-insert-failed', {
        table:   'payments',
        op:      'insert',
        pi_id:   stripeData.id,
        code:    e.code ?? null,
        message: e.message ?? null,
        details: e.details ?? null,
        hint:    e.hint ?? null,
      });
      console.error('DB insert error:', insertErr);

      // 23505 on stripe_payment_intent_id ⇒ a concurrent identical request
      // (same idempotency key ⇒ same PI) inserted its row first. That row IS
      // this payment — return the shared client_secret instead of failing.
      if (e.code === '23505') {
        const { data: winner } = await supabase
          .from('payments')
          .select('listing_id, buyer_id, mode, status')
          .eq('stripe_payment_intent_id', stripeData.id)
          .maybeSingle();
        if (
          winner &&
          winner.listing_id === listing_id &&
          winner.buyer_id === buyerId &&
          winner.mode === mode &&
          winner.status === 'pending'
        ) {
          logStage('db-insert-race-recovered', { pi_id: stripeData.id });
          return new Response(
            JSON.stringify({
              clientSecret:               stripeData.client_secret,
              paymentIntentId:            stripeData.id,
              amount:                     amountCents,
              buyer_fee:                  buyerFeeCents,
              seller_fee:                 sellerFeeCents,
              total:                      totalCents,
              customerId:                 customerCtx.customerId,
              customerEphemeralKeySecret: customerCtx.ephemeralKeySecret,
            }),
            { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
          );
        }
      }

      // Real failure: surface the true cause to Sentry (the client only ever
      // sees the safe message), then cancel the orphaned PaymentIntent.
      // Cancel errors are non-fatal — the request already failed and the
      // caller will retry with a fresh salt.
      await captureException(
        'create-payment-intent',
        new Error(`payments insert failed: code=${e.code ?? '?'} ${e.message ?? ''} ${e.details ?? ''}`),
      );
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
    logStage('db-insert-ok', { pi_id: stripeData.id, status: 'pending' });

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
