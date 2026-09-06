// =============================================================================
// confirm-payment — Stripe-verified settlement after PaymentSheet succeeds
// =============================================================================
// PURPOSE: Client-triggered settlement after Stripe PaymentSheet succeeds.
//   1. Authenticates the buyer via JWT
//   2. Fetches the PaymentIntent from Stripe (latest_charge expanded) and
//      refuses (403) unless metadata.buyer_id is the caller
//   3. Settles through settle_verified_payment (Package 2 contract): the row
//      is promoted, the listing sold and the transfer created atomically in
//      the database — this function never writes payments/transfers itself
//
// CONTRACT (unchanged for shipped clients):
//   - Stripe says succeeded and the contract ran → 200 {success, stripe_verified:true,
//     outcome, transfer_id}
//   - Stripe not reachable / PI not succeeded → 200 {stripe_verified:false},
//     no DB write (webhook + reconciliation sweep are independent fallbacks)
//   - Contract error → 500 (client treats the purchase as unverified: "don't
//     pay again")
//   - Auth failures, missing input, foreign PaymentIntent → 401 / 400 / 403
//
// AUTH: Manual JWT verification via auth.getUser(token). Requires "Verify JWT"
// to be DISABLED in the Supabase Dashboard for this function.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

// ── Rate limiting ─────────────────────────────────────────────────────────────
// Fail-CLOSED.
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

async function checkRateLimit(
  supabase: SupabaseClient,
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

// ── Auth ─────────────────────────────────────────────────────────────────────
// Matches confirm-and-release pattern: clean service-role client, pass user
// JWT explicitly to auth.getUser(). Does NOT set global Authorization header
// on the client (that overrides all subsequent requests and can confuse the
// auth service).
async function getAuthenticatedUserId(req: Request): Promise<string> {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    throw new Error('Missing or invalid Authorization header');
  }

  const token = authHeader.replace('Bearer ', '');

  // Use service-role client but pass the user's JWT to auth.getUser()
  // to validate the token server-side against Supabase Auth.
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
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

    // Rate limit: 10 requests per 60 seconds per user. Fail-closed.
    const rlClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const rl = await checkRateLimit(rlClient, buyerId, 'confirm-payment', 10, 60);
    if (rl === 'error') {
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

    const { payment_intent_id } = await req.json();

    if (!payment_intent_id) {
      return new Response(
        JSON.stringify({ error: 'Missing payment_intent_id' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    // ── Verify with Stripe that payment succeeded ───────────────────────
    // If the Stripe look-up fails for any reason we still return 200 with
    // stripe_verified:false and write NOTHING: the webhook and the
    // reconciliation sweep are independent, Stripe-verified fallbacks.
    // latest_charge is expanded so refund facts travel with the status.
    type StripeCharge = { id?: string; amount_refunded?: number; refunds?: { data?: Array<{ id?: string }> } };
    type StripePI = {
      id?: string; status?: string; amount_received?: number; currency?: string; livemode?: boolean;
      payment_method_types?: string[]; metadata?: Record<string, string>;
      latest_charge?: StripeCharge | string | null;
    };
    let stripePI: StripePI | null = null;

    try {
      const stripeRes = await stripeFetchRaw(`/payment_intents/${payment_intent_id}?expand[]=latest_charge`);
      if (stripeRes.ok) {
        stripePI = stripeRes.data as StripePI;
      } else {
        console.warn('confirm-payment: Stripe API returned non-OK:', {
          payment_intent_id,
          http_status: stripeRes.status,
        });
      }
    } catch (stripeFetchErr) {
      console.warn('confirm-payment: Stripe API fetch failed:', {
        payment_intent_id,
        error: stripeFetchErr instanceof Error ? stripeFetchErr.message : stripeFetchErr,
      });
    }

    const unverified = () => new Response(
      JSON.stringify({ success: true, stripe_verified: false }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
    );

    if (!stripePI) return unverified();

    // ── Ownership: only the PaymentIntent's buyer may confirm it ─────────
    // create-payment-intent stamps metadata.buyer_id on every PaymentIntent
    // (Package 1 binds it to the live reservation holder). A caller who is
    // not that buyer gets nothing — not even a look at the outcome — so a
    // buyer cannot settle (or probe) another buyer's purchase (A §4 item 3).
    if (!stripePI.metadata?.buyer_id || stripePI.metadata.buyer_id !== buyerId) {
      console.warn('confirm-payment: PaymentIntent does not belong to the caller', {
        payment_intent_id, caller: buyerId, pi_buyer: stripePI.metadata?.buyer_id ?? null,
      });
      return new Response(
        JSON.stringify({ error: 'This payment does not belong to you.' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    if (stripePI.status !== 'succeeded') {
      // Payment not yet succeeded at Stripe. This can happen if:
      // - PaymentSheet returned success but Stripe API has a brief delay
      // - Payment is still 'processing' (e.g. bank transfers)
      // Log but don't fail — the webhook / sweep will settle it later.
      console.warn('confirm-payment: Stripe PI not succeeded yet:', {
        payment_intent_id,
        stripe_status: stripePI.status,
      });
      return unverified();
    }

    // ── Settle through the ONE verified-settlement contract ─────────────
    // settle_verified_payment (migration 20260906110000) replaces the direct
    // payments UPDATE and transfers INSERT this function used to make: it
    // verifies amount / currency / livemode / metadata against the row,
    // refuses to promote a refunded row (F05), promotes only on succeeded,
    // and settles the listing + transfer through the Package 1 core. The
    // shipped clients' follow-up RPCs (mark_listing_sold /
    // complete_auction_payment / ensure_transfer_exists) then no-op.
    const charge = (stripePI.latest_charge && typeof stripePI.latest_charge === 'object') ? stripePI.latest_charge : null;
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data: settleRows, error: settleErr } = await supabase.rpc('settle_verified_payment', {
      p_payment_intent_id: payment_intent_id,
      p_stripe_status:     stripePI.status,
      p_amount_received:   typeof stripePI.amount_received === 'number' ? stripePI.amount_received : null,
      p_currency:          stripePI.currency ?? null,
      p_livemode:          typeof stripePI.livemode === 'boolean' ? stripePI.livemode : null,
      p_amount_refunded:   typeof charge?.amount_refunded === 'number' ? charge.amount_refunded : 0,
      p_stripe_refund_id:  charge?.refunds?.data?.[0]?.id ?? null,
      p_payment_method:    stripePI.payment_method_types?.[0] ?? 'card',
      p_metadata:          stripePI.metadata ?? {},
      p_source:            'confirm-payment',
    });

    if (settleErr) {
      // Stripe says succeeded but we could not record it. A non-2xx tells the
      // client the purchase is unverified (it already handles that: "don't
      // pay again"); the webhook / sweep settle it independently.
      console.error('confirm-payment: settle_verified_payment failed:', { payment_intent_id, error: settleErr });
      await captureException('confirm-payment:settle', new Error(`settle_verified_payment: ${settleErr.message}`), { payment_intent_id });
      return new Response(
        JSON.stringify({ error: 'Payment could not be recorded. Please do not pay again; contact support if the purchase does not appear.' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    const settled = (Array.isArray(settleRows) ? settleRows[0] : settleRows) as
      | { payment_id: string | null; payment_status: string | null; listing_status: string | null; transfer_id: string | null; outcome: string }
      | null
      | undefined;
    console.log('confirm-payment: settlement outcome', {
      payment_intent_id, outcome: settled?.outcome ?? null, payment_id: settled?.payment_id ?? null,
      listing_status: settled?.listing_status ?? null, transfer_id: settled?.transfer_id ?? null,
    });

    // ── Response ────────────────────────────────────────────────────────
    // `stripe_verified` is what the web client reads (finalizePurchase);
    // outcome / transfer_id are additive.
    return new Response(
      JSON.stringify({
        success:         true,
        stripe_verified: true,
        outcome:         settled?.outcome ?? null,
        transfer_id:     settled?.transfer_id ?? null,
      }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    const isAuthError = /authorization|token/i.test(message);
    if (isAuthError) {
      console.warn('confirm-payment: auth error:', message);
    } else {
      await captureException('confirm-payment', err);
    }
    return new Response(
      JSON.stringify({ error: isAuthError ? message : 'Internal server error' }),
      { status: isAuthError ? 401 : 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});
