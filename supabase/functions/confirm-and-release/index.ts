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
import {
  classifyPayoutStripeError,
  createSellerPayout,
  reasonCodeForErrorClass,
  shouldPageSentry,
} from '../_shared/payouts.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;

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
      // If already buyer_confirmed — or the cron already flipped it to
      // auto_released — that's fine: the buyer's goal is met, proceed to
      // the payout idempotency check (which returns already_released when
      // the money moved). The RPC error message names the current status.
      const alreadyConfirmed = rpcErr.message?.includes('buyer_confirmed') ||
        rpcErr.message?.includes('auto_released');

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
      .select('id, seller_id, buyer_id, payment_id, listing_id, status, payout_released_at, disputed_at, payout_risk_tier')
      .eq('id', transfer_id)
      .single();

    // ── F-5 live-rail acquisition guard (OR-17 release train; FR-9; DSM §3.2
    // F-5): a DELETION_PENDING buyer must not CONFIRM an inbound transfer that
    // was INITIATED AFTER their deletion request (accepting it is a custody
    // acquisition). A transfer initiated BEFORE the request is resolution of
    // existing business and stays allowed. Class A read (EA-1): the caller's
    // own kernel.identity_ext row via the caller's JWT — the owner SELECT
    // policy scopes it; before migration 077 the schema is absent and the
    // probe errs → not-pending (the DB sweep's BP wall is the enforcement).
    try {
      const callerAuth = req.headers.get('authorization')!;
      const callerKernel = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
        global: { headers: { Authorization: callerAuth } },
        auth: { autoRefreshToken: false, persistSession: false },
        db: { schema: 'kernel' },
      });
      const { data: ext } = await callerKernel
        .from('identity_ext')
        .select('deletion_state, deletion_requested_at')
        .eq('identity_id', buyerId)
        .maybeSingle();
      if (ext?.deletion_state === 'DELETION_PENDING' && ext.deletion_requested_at) {
        const { data: tCreated } = await supabase
          .from('transfers')
          .select('created_at')
          .eq('id', transfer_id)
          .maybeSingle();
        if (tCreated?.created_at && new Date(tCreated.created_at) > new Date(ext.deletion_requested_at)) {
          return new Response(
            JSON.stringify({
              error: 'Your account deletion request is pending. Withdraw it in Settings to accept new transfers.',
              code: 'account_deletion_pending',
            }),
            { status: 403, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
          );
        }
      }
    } catch {
      /* pre-077 world or transient probe failure — proceed; the DB wall holds */
    }

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

    // ── Dispute freeze (explicit, in addition to the status gate below) ──
    // A disputed transfer must NEVER pay out through any path, even if a
    // future refactor loosens the state machine. Frozen until an operator
    // resolves it.
    if (transfer.status === 'disputed' || transfer.disputed_at !== null) {
      return new Response(
        JSON.stringify({ error: 'This order is under review. Payout is frozen until the dispute is resolved.' }),
        { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
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

    // ─────────────────────────────────────────────────────────────────────
    // From this point on, the buyer's confirmation is ALREADY RECORDED
    // (status = buyer_confirmed). Nothing below may surface as an error to
    // the buyer: a payout that cannot release right now is an OPERATIONS
    // problem (recorded as a manual_review payout decision for admin
    // retry), never a buyer-facing failure. 2026-08-03 incident: a seller
    // with a test-mode Connect id made this endpoint 502 AFTER confirming,
    // so the buyer saw "Payout to seller failed" for a confirmation that
    // had in fact succeeded.
    // ─────────────────────────────────────────────────────────────────────

    // Record a payout problem for admin review (idempotently — one open
    // manual_review decision per transfer) and tell the buyer the truth:
    // their tickets are confirmed. `payout_status` lets newer clients
    // render a precise state; older clients just see success.
    const payoutDeferred = async (
      reasonCode: string,
      evidence: Record<string, unknown>,
      paymentId: string,
    ) => {
      const { data: existingDecision } = await supabase
        .from('payout_decisions')
        .select('id')
        .eq('transfer_id', transfer_id)
        .eq('decision', 'manual_review')
        .limit(1)
        .maybeSingle();
      if (!existingDecision) {
        const { error: decisionErr } = await supabase.from('payout_decisions').insert({
          transfer_id,
          payment_id: paymentId,
          seller_id:  transfer.seller_id,
          buyer_id:   transfer.buyer_id,
          risk_tier:  'low',
          decision:   'manual_review',
          reason_codes: ['BUYER_CONFIRMED', reasonCode],
          evidence,
          buyer_confirmed: true,
          dispute_open: false,
          actor: 'edge:confirm-and-release',
        });
        if (decisionErr) {
          console.error('confirm-and-release: payout_decisions insert failed:', decisionErr);
        }
      }
      console.warn('confirm-and-release: payout deferred to manual review:', {
        transfer_id,
        reason: reasonCode,
      });
      return new Response(
        JSON.stringify({ success: true, payout_status: 'pending_review' }),
        { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    };

    // ── 6. Look up payment amount + seller fee ──────────────────────────
    // 10/10 fee model: seller receives (amount − seller_fee).
    // Buyer fee + seller fee stay with the platform.
    const { data: payment, error: paymentErr } = await supabase
      .from('payments')
      .select('amount, seller_fee, status, stripe_payment_intent_id')
      .eq('id', transfer.payment_id)
      .single();

    if (paymentErr || !payment) {
      console.error('confirm-and-release: payment lookup failed:', {
        transfer_id,
        payment_id: transfer.payment_id,
        error:      paymentErr,
      });
      return await payoutDeferred('PAYMENT_LOOKUP_FAILED', {
        payment_id: transfer.payment_id,
        error:      paymentErr?.message ?? 'payment row not found',
      }, transfer.payment_id);
    }

    // Never pay out against money the platform no longer holds. A refunded
    // or failed payment can reach here only through operator action, but
    // this guard makes the invariant structural.
    if (payment.status !== 'succeeded') {
      return await payoutDeferred('PAYMENT_NOT_SUCCEEDED', {
        payment_id:     transfer.payment_id,
        payment_status: payment.status,
      }, transfer.payment_id);
    }

    // ── 7. Look up seller's Connect account ─────────────────────────────
    const { data: sellerProfile, error: profileErr } = await supabase
      .from('profiles')
      .select('stripe_connect_id')
      .eq('id', transfer.seller_id)
      .single();

    if (profileErr || !sellerProfile?.stripe_connect_id) {
      // Seller has no (live-mode) payout account yet — e.g. every pre-cutover
      // seller after migration 044 archived their test-mode Connect ids.
      // The seller re-onboards via payout setup; admin releases from the
      // manual_review queue once they have.
      return await payoutDeferred('SELLER_NOT_ONBOARDED', {
        seller_id: transfer.seller_id,
        error:     profileErr?.message ?? 'stripe_connect_id is null',
      }, transfer.payment_id);
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

    // ── 8a. Final dispute recheck, immediately before money moves ────────
    // A Stripe chargeback webhook can dispute this transfer between our
    // earlier read and now. Re-read the row; if anything about it is no
    // longer releasable, freeze instead of paying.
    {
      const { data: finalCheck } = await supabase
        .from('transfers')
        .select('status, disputed_at, payout_released_at')
        .eq('id', transfer_id)
        .single();
      if (
        !finalCheck ||
        finalCheck.disputed_at !== null ||
        finalCheck.status !== 'buyer_confirmed' ||
        finalCheck.payout_released_at !== null
      ) {
        if (finalCheck?.payout_released_at) {
          return new Response(
            JSON.stringify({ success: true, already_released: true }),
            { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
          );
        }
        if (!finalCheck) {
          // Transient read failure — NOT evidence of a dispute. The buyer's
          // confirmation already stands; skip the payout (never pay on a
          // blind read) and let the cron release it on a later sweep.
          console.warn('confirm-and-release: final recheck read failed — payout deferred:', { transfer_id });
          return new Response(
            JSON.stringify({ success: true, payout_status: 'pending_review' }),
            { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
          );
        }
        return new Response(
          JSON.stringify({ error: 'This order is under review. Payout is frozen until the dispute is resolved.' }),
          { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }
    }

    let stripeTransfer: { id: string };
    try {
      // Canonical payout (_shared/payouts.ts): capability pre-flight,
      // funding-charge verification, then a source_transaction transfer
      // keyed on (transfer id, destination) shared with the cron path. Any
      // race or retry replays ONE Stripe Transfer; the transfer is funded
      // by THIS payment's charge, so a same-day payout succeeds even while
      // the platform's available balance is still settling.
      const payoutRes = await createSellerPayout({
        transferId:      transfer_id,
        paymentId:       transfer.payment_id,
        sellerId:        transfer.seller_id,
        destination:     sellerProfile.stripe_connect_id,
        paymentIntentId: payment.stripe_payment_intent_id as string,
        sellerNetCents,
      });
      if (!payoutRes.ok) {
        // Expected operational deferrals — buyer confirmation stands, the
        // cron re-attempts once the blocking condition clears. Not Sentry.
        if (payoutRes.reason === 'destination_not_ready') {
          return await payoutDeferred('PAYOUT_DESTINATION_NOT_READY', {
            destination_suffix: sellerProfile.stripe_connect_id.slice(-4),
            seller_net_cents:   sellerNetCents,
            ...payoutRes.destination_state,
          }, transfer.payment_id);
        }
        return await payoutDeferred('PAYOUT_SOURCE_CHARGE_UNAVAILABLE', {
          destination_suffix: sellerProfile.stripe_connect_id.slice(-4),
          seller_net_cents:   sellerNetCents,
          ...payoutRes.source_state,
        }, transfer.payment_id);
      }
      stripeTransfer = payoutRes.transfer;
    } catch (stripeErr) {
      const detail = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      const errClass = classifyPayoutStripeError(detail);
      console.error('confirm-and-release: Stripe Transfer failed:', {
        transfer_id,
        seller_connect_id: sellerProfile.stripe_connect_id,
        seller_net:        sellerNetCents,
        error_class:       errClass,
        error:             detail,
      });
      // Only unexpected classes page Sentry — operational states (funds,
      // capability) are recorded as payout decisions, not exceptions.
      if (shouldPageSentry(errClass)) {
        await captureException(
          'confirm-and-release',
          new Error(`Stripe Transfer failed [${errClass}] for transfer ${transfer_id}: ${detail}`),
        );
      }
      // The buyer's confirmation stands; the payout goes to the admin
      // manual-review queue with Stripe's real error preserved as evidence.
      return await payoutDeferred(reasonCodeForErrorClass(errClass), {
        stripe_error:       detail,
        error_class:        errClass,
        destination_suffix: sellerProfile.stripe_connect_id.slice(-4),
        seller_net_cents:   sellerNetCents,
      }, transfer.payment_id);
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
    // record_transfer_payout (migration 056a) is SECURITY DEFINER and sets
    // app.bypass_transfer_guard, so it writes past guard_transfer_state_columns.
    // Its WHERE (payout_released_at IS NULL AND stripe_transfer_id IS NULL) is
    // the same single-writer guard, so the concurrency reasoning above is
    // unchanged. `false` is the old 0-rows-updated case, not an error.
    const { data: updated, error: updateErr } = await supabase
      .rpc('record_transfer_payout', {
        p_transfer_id:        transfer_id,
        p_stripe_transfer_id: stripeTransfer.id,
      });

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

    // ── 9b. Audit record: buyer-confirmed release ────────────────────────
    // Positive buyer confirmation is the strongest release signal; record it
    // in the same payout_decisions trail the risk engine writes to.
    {
      const { error: auditErr } = await supabase.from('payout_decisions').insert({
        transfer_id,
        payment_id: transfer.payment_id,
        seller_id: transfer.seller_id,
        buyer_id: transfer.buyer_id,
        risk_tier: 'low',
        decision: 'release',
        reason_codes: ['BUYER_CONFIRMED'],
        evidence: {
          base_cents: payment.amount,
          seller_fee_cents: payment.seller_fee,
          seller_net_cents: sellerNetCents,
          stripe_transfer_id: stripeTransfer.id,
        },
        buyer_confirmed: true,
        dispute_open: false,
        actor: 'edge:confirm-and-release',
      });
      if (auditErr) console.error('confirm-and-release: payout_decisions insert failed:', auditErr);
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
