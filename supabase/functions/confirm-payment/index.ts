// =============================================================================
// confirm-payment — Best-effort payment confirmation + transfer creation
// =============================================================================
// PURPOSE: Client-triggered bookkeeping after Stripe PaymentSheet succeeds.
//   1. Authenticates the buyer via JWT
//   2. Verifies payment status with Stripe API
//   3. Updates payment record to 'succeeded'
//   4. Creates transfer row (idempotent — UNIQUE constraints prevent duplicates)
//
// NON-FATAL: This function is best-effort. The checkout flow does NOT depend
// on it returning 200. ensure_transfer_exists (RPC) and stripe-webhook are
// independent fallbacks. Therefore:
//   - Already-processed payments → 200 (idempotent)
//   - Transfer already exists → 200 (idempotent)
//   - Stripe verification fails → 200 with warning (bookkeeping deferred to webhook)
//   - Only auth failures and missing input return non-2xx
//
// AUTH: Manual JWT verification via auth.getUser(token). Requires "Verify JWT"
// to be DISABLED in the Supabase Dashboard for this function.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
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
    // If Stripe verification fails for any reason, we still return 200.
    // This function is best-effort bookkeeping — the webhook and
    // ensure_transfer_exists RPC are independent fallbacks.
    let stripeVerified = false;
    let stripePaymentMethod: string = 'card';

    try {
      const stripeRes = await stripeFetchRaw(`/payment_intents/${payment_intent_id}`);

      if (stripeRes.ok) {
        const stripeData = stripeRes.data as { status?: string; payment_method_types?: string[] };

        if (stripeData.status === 'succeeded') {
          stripeVerified = true;
          stripePaymentMethod = stripeData.payment_method_types?.[0] ?? 'card';
        } else {
          // Payment not yet succeeded at Stripe. This can happen if:
          // - PaymentSheet returned success but Stripe API has a brief delay
          // - Payment is still 'processing' (e.g. bank transfers)
          // Log but don't fail — the webhook will handle it when it settles.
          console.warn('confirm-payment: Stripe PI not succeeded yet:', {
            payment_intent_id,
            stripe_status: stripeData.status,
          });
        }
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

    // ── Update payment record ───────────────────────────────────────────
    // Only update if Stripe verified the payment. If not, leave the
    // payment in 'pending' — the webhook or ensure_transfer_exists will
    // promote it later.
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    if (stripeVerified) {
      const { error: updateErr } = await supabase
        .from('payments')
        .update({
          status: 'succeeded',
          paid_at: new Date().toISOString(),
          payment_method: stripePaymentMethod,
        })
        .eq('stripe_payment_intent_id', payment_intent_id)
        .eq('buyer_id', buyerId);

      if (updateErr) {
        console.error('confirm-payment: payment update error:', updateErr);
      }
    }

    // ── Ensure transfer row exists ──────────────────────────────────────
    // Idempotent: UNIQUE constraints on transfers.payment_id and
    // transfers.listing_id (migration 003) prevent duplicates. A
    // constraint violation means the webhook or ensure_transfer_exists
    // already created the row — that's fine.
    //
    // GATED on a succeeded payment: a transfer row is the seller's
    // send-tickets obligation, so it must never exist for an unpaid order.
    // The status filter (not just this call's stripeVerified) also covers
    // the race where the webhook promoted the row first. Unverified
    // payments are left to the webhook path, which creates the transfer
    // row itself after promotion.
    try {
      const { data: claimedPayment } = await supabase
        .from('payments')
        .select('id, listing_id, seller_id, buyer_id')
        .eq('stripe_payment_intent_id', payment_intent_id)
        .eq('buyer_id', buyerId)
        .eq('status', 'succeeded')
        .single();

      if (claimedPayment) {
        const { data: listing } = await supabase
          .from('listings')
          .select('transfer_method')
          .eq('id', claimedPayment.listing_id)
          .maybeSingle();

        const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

        const { error: transferErr } = await supabase.from('transfers').insert({
          listing_id:      claimedPayment.listing_id,
          payment_id:      claimedPayment.id,
          seller_id:       claimedPayment.seller_id,
          buyer_id:        claimedPayment.buyer_id,
          transfer_method: listing?.transfer_method ?? 'mobile_transfer',
          status:          'pending',
          expires_at:      expiresAt,
        });

        if (transferErr) {
          // Unique constraint violation = another path already created the row — safe.
          console.log('confirm-payment: transfer insert skipped (likely already exists):', {
            payment_id: claimedPayment.id,
            listing_id: claimedPayment.listing_id,
            code:       transferErr.code,
          });
        } else {
          console.log('confirm-payment: transfer row created', {
            payment_id: claimedPayment.id,
            listing_id: claimedPayment.listing_id,
          });
        }
      }
    } catch (transferCreateErr) {
      // Non-fatal — the webhook and ensure_transfer_exists are fallbacks.
      console.warn('confirm-payment: transfer creation threw:', transferCreateErr);
    }

    // ── Always return 200 ───────────────────────────────────────────────
    // This function is best-effort bookkeeping. The checkout does not
    // depend on it. Returning 200 prevents noisy client-side error logs.
    return new Response(
      JSON.stringify({
        success: true,
        stripe_verified: stripeVerified,
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
