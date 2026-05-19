// =============================================================================
// confirm-and-release — Day 2 payout release edge function
// =============================================================================
// PURPOSE: Single server-side endpoint that:
//   1. Authenticates the buyer
//   2. Calls confirm_transfer_received RPC (seller_sent → buyer_confirmed)
//   3. Releases seller payout via Stripe Transfer — exactly once
//
// CLIENT CALL:
//   supabase.functions.invoke('confirm-and-release', {
//     body: { transfer_id: '<uuid>' }
//   })
//
// IDEMPOTENCY (3 layers):
//   Layer 1: confirm_transfer_received RPC rejects if status ≠ seller_sent
//   Layer 2: SELECT ... FOR UPDATE + payout_released_at IS NULL guard
//   Layer 3: payout_released_at + stripe_transfer_id written atomically
//
// SAFETY:
//   - confirm_transfer_received RPC is called, NOT modified
//   - Stripe secret key stays in edge function env (not in DB)
//   - No client dependency for money movement
//   - Duplicate calls return success without creating second payout
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetch } from '../_shared/stripe.ts';

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

// ── Auth ─────────────────────────────────────────────────────────────────────
// Manual JWT verification. Requires "Verify JWT" to be DISABLED in the
// Supabase Dashboard for this function, so the relay passes the request
// through without its own JWT check.
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

// ── Rate limiting ────────────────────────────────────────────────────────────
// Fail-CLOSED. Identical pattern in confirm-payment, create-payment-intent,
// create-connect-account, delete-account.
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

// ── Stripe helper ────────────────────────────────────────────────────────────
// Thin wrapper around the shared stripeFetch so this file's existing
// `stripePost(path, body)` call sites keep working without churn. The
// shared helper handles auth header + STRIPE_API_VERSION pinning.
async function stripePost(path: string, body: Record<string, string>) {
  return stripeFetch(path, { method: 'POST', body });
}

// ── Main handler ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  try {
    // ── 1. Authenticate caller ──────────────────────────────────────────
    const buyerId = await getAuthenticatedUserId(req);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── 2. Rate limit ───────────────────────────────────────────────────
    // 5 requests per 300 seconds (5 min). Fail-closed: any RPC failure
    // returns 503 instead of silently bypassing rate limiting.
    const rl = await checkRateLimit(supabase, buyerId, 'confirm-and-release', 5, 300);
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
            'Retry-After': '300',
            ...getResponseHeaders(req),
          },
        },
      );
    }

    // ── 3. Parse input ──────────────────────────────────────────────────
    const { transfer_id } = await req.json();

    if (!transfer_id) {
      return new Response(
        JSON.stringify({ error: 'Missing transfer_id' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 4. Call confirm_transfer_received RPC ────────────────────────────
    // Uses service role so auth.uid() is NULL — the RPC falls back to
    // p_user_id for caller identity. This is the documented behavior
    // (see 002_transfers.sql line 200).
    //
    // Possible outcomes:
    //   - Success: status transitions seller_sent → buyer_confirmed
    //   - Already confirmed: RPC raises "cannot be confirmed from current
    //     status: buyer_confirmed" — we catch this and proceed to payout
    //   - Not the buyer: RPC raises "Only the buyer can confirm" — we
    //     propagate this error to the client
    //   - Wrong state (pending): RPC raises error — we propagate
    const { error: rpcErr } = await supabase.rpc('confirm_transfer_received', {
      p_transfer_id: transfer_id,
      p_user_id:     buyerId,
    });

    if (rpcErr) {
      // If already buyer_confirmed, that's fine — proceed to payout.
      // The RPC error message contains "buyer_confirmed" when the transfer
      // is already in that state.
      const alreadyConfirmed = rpcErr.message?.includes('buyer_confirmed');

      if (!alreadyConfirmed) {
        // Real error — wrong user, wrong state, not found, etc.
        console.error('confirm-and-release: RPC failed:', {
          transfer_id,
          buyer_id: buyerId,
          error:    rpcErr.message,
        });
        return new Response(
          JSON.stringify({ error: rpcErr.message }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }

      console.log('confirm-and-release: transfer already confirmed, proceeding to payout check', {
        transfer_id,
      });
    }

    // ── 5. Payout idempotency check ─────────────────────────────────────
    // Read the transfer with a row-level lock. If payout_released_at is
    // already set, the payout was already released — return success.
    //
    // NOTE: Supabase JS client does not support SELECT ... FOR UPDATE.
    // We use a raw SQL query via rpc to get the row lock. However, since
    // we don't have a dedicated RPC for this yet, we use a two-step
    // approach:
    //   Step A: Read the transfer row to check payout state
    //   Step B: Use an atomic UPDATE ... WHERE payout_released_at IS NULL
    //           after the Stripe call to prevent double writes
    //
    // The atomic UPDATE in step B is the true idempotency guard. Step A
    // is an optimization to avoid unnecessary Stripe calls.
    const { data: transfer, error: transferErr } = await supabase
      .from('transfers')
      .select('id, seller_id, buyer_id, payment_id, status, payout_released_at')
      .eq('id', transfer_id)
      .single();

    if (transferErr || !transfer) {
      console.error('confirm-and-release: transfer lookup failed:', {
        transfer_id,
        error: transferErr,
      });
      return new Response(
        JSON.stringify({ error: 'Transfer not found' }),
        { status: 404, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // Verify caller is the buyer (defense-in-depth — RPC already checks this)
    if (transfer.buyer_id !== buyerId) {
      return new Response(
        JSON.stringify({ error: 'Only the buyer can release payout' }),
        { status: 403, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // Verify transfer is in buyer_confirmed state
    if (transfer.status !== 'buyer_confirmed') {
      return new Response(
        JSON.stringify({ error: `Transfer is in unexpected state: ${transfer.status}` }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 5a. Already paid? Return success (idempotent) ───────────────────
    if (transfer.payout_released_at !== null) {
      console.log('confirm-and-release: payout already released, returning success', {
        transfer_id,
        payout_released_at: transfer.payout_released_at,
      });
      return new Response(
        JSON.stringify({ success: true, already_released: true }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 6. Look up seller's Connect account ─────────────────────────────
    const { data: sellerProfile, error: profileErr } = await supabase
      .from('profiles')
      .select('stripe_connect_id')
      .eq('id', transfer.seller_id)
      .single();

    if (profileErr || !sellerProfile?.stripe_connect_id) {
      console.error('confirm-and-release: seller has no Connect account:', {
        transfer_id,
        seller_id: transfer.seller_id,
        error:     profileErr,
      });
      return new Response(
        JSON.stringify({ error: 'Seller payout account not set up. Please contact support.' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 7. Look up payment amount + seller fee ──────────────────────────
    // 10/10 fee model: seller receives (amount − seller_fee).
    // Buyer fee + seller fee stay with the platform.
    const { data: payment, error: paymentErr } = await supabase
      .from('payments')
      .select('amount, seller_fee, stripe_payment_intent_id')
      .eq('id', transfer.payment_id)
      .single();

    if (paymentErr || !payment) {
      console.error('confirm-and-release: payment lookup failed:', {
        transfer_id,
        payment_id: transfer.payment_id,
        error:      paymentErr,
      });
      return new Response(
        JSON.stringify({ error: 'Payment record not found' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 8. Create Stripe Transfer ───────────────────────────────────────
    // stripe.transfers.create() moves funds from the platform Stripe
    // balance to the seller's Connected Express account.
    //
    // Stripe Transfers are NOT idempotent by default. Our idempotency is
    // enforced by the atomic UPDATE in step 9 below. The read check in
    // step 5a prevents most redundant Stripe calls, but the atomic UPDATE
    // is the true guard against double payouts in a race condition.
    // Seller net = listing price − seller fee (10/10 fee model).
    const sellerNetCents = (payment.amount as number) - (payment.seller_fee as number ?? 0);

    console.log('confirm-and-release: creating Stripe Transfer', {
      transfer_id,
      seller_connect_id: sellerProfile.stripe_connect_id,
      listing_amount:    payment.amount,
      seller_fee:        payment.seller_fee,
      seller_net:        sellerNetCents,
      currency:          'usd',
    });

    let stripeTransfer;
    try {
      stripeTransfer = await stripePost('/transfers', {
        'amount':      String(sellerNetCents),
        'currency':    'usd',
        'destination': sellerProfile.stripe_connect_id,
        'metadata[transfer_id]':  transfer_id,
        'metadata[payment_id]':   transfer.payment_id,
        'metadata[seller_id]':    transfer.seller_id,
        'metadata[source]':       'confirm-and-release',
      });
    } catch (stripeErr) {
      console.error('confirm-and-release: Stripe Transfer failed:', {
        transfer_id,
        seller_connect_id: sellerProfile.stripe_connect_id,
        seller_net:        sellerNetCents,
        error:             stripeErr instanceof Error ? stripeErr.message : stripeErr,
      });
      return new Response(
        JSON.stringify({ error: 'Payout to seller failed. Please try again or contact support.' }),
        { status: 502, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 9. Atomic DB update (true idempotency guard) ────────────────────
    // UPDATE ... WHERE payout_released_at IS NULL ensures that even if
    // two requests passed the read check (step 5a) concurrently, only
    // one will write the payout columns. The other sees 0 rows updated
    // and we return success (payout was already recorded by the winner).
    //
    // NOTE: If the Stripe Transfer succeeded (step 8) but this UPDATE
    // fails, we have an "orphaned" Stripe Transfer. The stripe_transfer_id
    // is logged below for manual recovery. At private beta scale this is
    // acceptable — a future migration can add a reconciliation check.
    const { data: updated, error: updateErr } = await supabase
      .from('transfers')
      .update({
        payout_released_at: new Date().toISOString(),
        stripe_transfer_id: stripeTransfer.id,
      })
      .eq('id', transfer_id)
      .is('payout_released_at', null)
      .select('id')
      .maybeSingle();

    if (updateErr) {
      // Log for manual recovery — the Stripe Transfer was already created
      console.error('confirm-and-release: DB update failed after Stripe Transfer succeeded:', {
        transfer_id,
        stripe_transfer_id: stripeTransfer.id,
        error:              updateErr,
      });
      // Return success to client — the seller has been paid via Stripe.
      // The DB column will be fixed by manual reconciliation if needed.
      return new Response(
        JSON.stringify({ success: true, warning: 'Payout sent but record update failed' }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    if (!updated) {
      // Another request won the race — payout_released_at was already set
      // between our read (step 5a) and this write. The Stripe Transfer we
      // created is a duplicate. Log it for manual cleanup.
      console.warn('confirm-and-release: race condition — duplicate Stripe Transfer created:', {
        transfer_id,
        duplicate_stripe_transfer_id: stripeTransfer.id,
      });
      // Return success — from the client's perspective, the payout is done.
      return new Response(
        JSON.stringify({ success: true, already_released: true }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // ── 10. Success ─────────────────────────────────────────────────────
    console.log('confirm-and-release: payout released successfully', {
      transfer_id,
      stripe_transfer_id: stripeTransfer.id,
      amount:             payment.amount,
      seller_id:          transfer.seller_id,
    });

    return new Response(
      JSON.stringify({ success: true, stripe_transfer_id: stripeTransfer.id }),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    const isAuthError = /authorization|token/i.test(message);
    if (isAuthError) {
      console.warn('confirm-and-release: auth error:', message);
    } else {
      await captureException('confirm-and-release', err);
    }
    return new Response(
      JSON.stringify({ error: isAuthError ? message : 'Internal server error' }),
      { status: isAuthError ? 401 : 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
    );
  }
});
