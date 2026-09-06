// =============================================================================
// confirm-and-release — Day 2 payout release edge function
// =============================================================================
// PURPOSE: Single server-side endpoint that:
//   1. Authenticates the buyer
//   2. Calls confirm_transfer_received RPC (seller_sent → buyer_confirmed)
//   3. Releases seller payout via Stripe Transfer — exactly once, through the
//      payout ATTEMPT protocol (migration 20260906120000, _shared/payouts.ts)
//
// CLIENT CALL:
//   supabase.functions.invoke('confirm-and-release', {
//     body: { transfer_id: '<uuid>' }
//   })
//
// IDEMPOTENCY / SAFETY (PAYMENTS_RELIABILITY_2026-09 Package 3):
//   Layer 1: confirm_transfer_received RPC rejects if status ≠ seller_sent
//   Layer 2: claim_payout_attempt — FOR UPDATE eligibility check that freezes
//            destination/amount and hands out a 10-minute lease; one open
//            attempt per transfer; a second caller gets "in progress"
//   Layer 3: an open attempt is reconciled against Stripe (list by
//            transfer_group) BEFORE any new POST — never a blind replay
//   Layer 4: record_payout_attempt_result ALWAYS writes the tr_ id, even when
//            a chargeback landed mid-flight (→ reversal_required + review),
//            so money that moved is never invisible to the DB (F07/F08)
//
//   Responses after the buyer's confirmation is recorded are NEVER errors
//   (2026-08-03 incident): payout_status 'processing' while an attempt is
//   open/being reconciled, 'pending_review' when an operator must act,
//   already_released only when a succeeded attempt exists.
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { executePayoutAttempt } from '../_shared/payouts.ts';

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

    // ── 5. Transfer state (buyer check, dispute freeze, status gate) ─────
    // The claim RPC below re-checks all of this under FOR UPDATE; this read
    // exists to answer the buyer precisely (403/409/400) before any attempt.
    const { data: transfer, error: transferErr } = await supabase
      .from('transfers')
      .select('id, seller_id, buyer_id, payment_id, listing_id, status, payout_released_at, disputed_at, payout_risk_tier')
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

    // ── Dispute freeze (explicit, in addition to the claim predicate) ────
    if (transfer.status === 'disputed' || transfer.disputed_at !== null) {
      return new Response(
        JSON.stringify({ error: 'This order is under review. Payout is frozen until the dispute is resolved.' }),
        { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
      );
    }

    // Verify transfer is in a releasable state (auto_released = the cron
    // already claimed the row; the buyer's confirmation is tolerated).
    if (transfer.status !== 'buyer_confirmed' && transfer.status !== 'auto_released') {
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

    const respond = (body: Record<string, unknown>) => new Response(
      JSON.stringify(body),
      { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
    );

    // Record a payout problem for admin review (idempotently — one open
    // manual_review decision per transfer) and tell the buyer the truth:
    // their tickets are confirmed. `payout_status` lets newer clients
    // render a precise state; older clients just see success.
    const payoutDeferred = async (
      reasonCode: string,
      evidence: Record<string, unknown>,
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
          payment_id: transfer.payment_id,
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
      return respond({ success: true, payout_status: 'pending_review' });
    };

    // ── 6. Payout attempt protocol (_shared/payouts.ts) ─────────────────
    // claim (short RPC; freezes destination + amount, 10-min lease)
    //   → open attempt? search Stripe by transfer_group, reconcile, STOP
    //   → Stripe pre-flights → mark_payout_requested → POST → record.
    // The seller profile is read ONCE, inside the claim; never re-read.
    const outcome = await executePayoutAttempt(supabase, {
      transferId: transfer_id,
      paymentId:  transfer.payment_id,
      sellerId:   transfer.seller_id,
      actor:      'edge:confirm-and-release',
    });

    switch (outcome.kind) {
      case 'succeeded': {
        // ── 6b. Audit record: buyer-confirmed release ────────────────────
        const { data: payment } = await supabase
          .from('payments')
          .select('amount, seller_fee')
          .eq('id', transfer.payment_id)
          .maybeSingle();
        const { error: auditErr } = await supabase.from('payout_decisions').insert({
          transfer_id,
          payment_id: transfer.payment_id,
          seller_id: transfer.seller_id,
          buyer_id: transfer.buyer_id,
          risk_tier: 'low',
          decision: 'release',
          reason_codes: ['BUYER_CONFIRMED'],
          evidence: {
            base_cents: payment?.amount ?? null,
            seller_fee_cents: payment?.seller_fee ?? null,
            seller_net_cents: outcome.sellerNetCents,
            stripe_transfer_id: outcome.stripeTransferId,
            attempt_id: outcome.attemptId,
            attempt_no: outcome.attemptNo,
            destination_suffix: outcome.destination.slice(-4),
          },
          buyer_confirmed: true,
          dispute_open: false,
          actor: 'edge:confirm-and-release',
        });
        if (auditErr) console.error('confirm-and-release: payout_decisions insert failed:', auditErr);

        console.log('confirm-and-release: payout released successfully', {
          transfer_id,
          stripe_transfer_id: outcome.stripeTransferId,
          attempt_no:         outcome.attemptNo,
          seller_net:         outcome.sellerNetCents,
          seller_id:          transfer.seller_id,
        });
        return respond({ success: true, stripe_transfer_id: outcome.stripeTransferId });
      }

      case 'reversal_required': {
        // A chargeback landed between the claim and the record. The money
        // moved and IS recorded (record_payout_attempt_result wrote the tr_
        // id and a PAID_DURING_DISPUTE review row). Ops reverses it.
        console.error('confirm-and-release: payout recorded during a dispute — reversal required:', {
          transfer_id, stripe_transfer_id: outcome.stripeTransferId, attempt_id: outcome.attemptId,
        });
        await captureException(
          'confirm-and-release:paid-during-dispute',
          new Error(`transfer ${transfer_id} paid (${outcome.stripeTransferId}) while disputed`),
          { transfer_id, stripe_transfer_id: outcome.stripeTransferId },
        );
        return respond({ success: true, payout_status: 'pending_review' });
      }

      case 'already_released':
        return respond({ success: true, already_released: true });

      case 'reconciled':
        if (outcome.found) {
          console.log('confirm-and-release: open attempt reconciled — transfer found on Stripe', {
            transfer_id, attempt_id: outcome.attemptId, stripe_transfer_id: outcome.stripeTransferId, state: outcome.state,
          });
          return respond({ success: true, already_released: true, stripe_transfer_id: outcome.stripeTransferId });
        }
        // Previous attempt proven absent on Stripe and closed; the next call
        // or the cron sweep opens a fresh attempt. No POST this run.
        console.warn('confirm-and-release: open attempt reconciled — nothing on Stripe, attempt closed', {
          transfer_id, attempt_id: outcome.attemptId,
        });
        return respond({ success: true, payout_status: 'processing' });

      case 'in_progress':
      case 'reconcile_pending':
        console.log('confirm-and-release: payout attempt in progress / awaiting reconciliation', {
          transfer_id, kind: outcome.kind,
        });
        return respond({ success: true, payout_status: 'processing' });

      case 'unknown':
        // POST outcome unknown (network / 5xx / in-flight). Recorded as
        // 'unknown' under the lease; the sweep reconciles by transfer_group.
        console.warn('confirm-and-release: Stripe transfer outcome unknown — will reconcile:', {
          transfer_id, attempt_id: outcome.attemptId, error: outcome.error,
        });
        return respond({ success: true, payout_status: 'processing' });

      case 'not_eligible':
        if (outcome.reason === 'DISPUTED') {
          return new Response(
            JSON.stringify({ error: 'This order is under review. Payout is frozen until the dispute is resolved.' }),
            { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
          );
        }
        // SELLER_NOT_ONBOARDED / PAYMENT_NOT_SUCCEEDED / PAYMENT_NOT_LIVE /
        // TRANSFER_NOT_RELEASABLE: operator conditions, buyer stays confirmed.
        return await payoutDeferred(outcome.reason, { payment_id: transfer.payment_id, seller_id: transfer.seller_id });

      case 'deferred':
        if (outcome.page) {
          await captureException(
            'confirm-and-release',
            new Error(`Stripe Transfer failed [${outcome.reasonCode}] for transfer ${transfer_id}: ${outcome.error ?? ''}`),
          );
        }
        return await payoutDeferred(outcome.reasonCode, outcome.evidence);

      case 'db_error':
        if (outcome.stage === 'record' && outcome.stripeTransferId) {
          // Money HAS moved but the DB write failed. Never silent: the
          // attempt is still open under its lease, so the sweep reconciles it
          // by transfer_group and records the same tr_ id.
          console.error('confirm-and-release: DB record failed after Stripe Transfer succeeded:', {
            transfer_id, stripe_transfer_id: outcome.stripeTransferId, attempt_id: outcome.attemptId, error: outcome.error,
          });
          await captureException(
            'confirm-and-release:record-payout-failed',
            new Error(`record_payout_attempt_result failed for transfer ${transfer_id} (stripe ${outcome.stripeTransferId}): ${outcome.error}`),
            { transfer_id, stripe_transfer_id: outcome.stripeTransferId },
          );
        } else {
          console.error('confirm-and-release: payout attempt DB error:', {
            transfer_id, stage: outcome.stage, error: outcome.error,
          });
        }
        return respond({ success: true, payout_status: 'processing' });
    }

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
