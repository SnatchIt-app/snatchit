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
//   Enforced mechanically since 2026-10-21 (CFT-703 catalogue CRE-404 /
//   CRE-500): once the confirmation is KNOWN to be recorded (below)
//   `confirmationRecorded` is set; from then on a failed transfer re-read
//   answers 200 processing, and ANY throw (e.g. a Stripe pre-flight fetch
//   inside _shared/payouts.ts createSellerPayout, which does not catch it)
//   answers 200 processing too. Nothing is retried here: a claimed attempt
//   stays open under its lease and the payout sweep (enforce-transfer-expiry
//   Phase 2b) remains the authority that reconciles and pays it.
//
// WHEN IS THE CONFIRMATION KNOWN? (2026-10-21 review: no false 200)
//   • confirm_transfer_received succeeded — it committed buyer_confirmed.
//   • It refused with migration 171's HINT TRANSFER_NOT_CONFIRMABLE and
//     DETAIL buyer_confirmed / auto_released — PROOF: the RPC read that
//     status FOR UPDATE and raised before writing (the retry case).
//   • It refused WITHOUT that HINT (production before 171) but its message
//     names buyer_confirmed / auto_released — only a CLAIM: another error
//     can carry those words after the RPC rolled back (e.g. a trigger error
//     naming buyer_confirmed_at). The §5 re-read must show the status before
//     anything answers 200; if that re-read fails the answer is 503
//     SERVICE_UNAVAILABLE (the retry re-runs both), never 200.
//
// ERROR BODIES: { error, code }. `error` text is unchanged for existing
// clients; `code` is the stable key (catalogue §7 P1).
//   • confirm_transfer_received refusal (400): `code` is the Postgres HINT
//     when it is a machine code (migration 171: TRANSFER_NOT_CONFIRMABLE,
//     DETAIL = status). Until 171 is applied the RPC raises without a HINT
//     and `code` is null — harmless; deploy order relative to 171 is free.
//   • Edge-originated: AUTH_REQUIRED 401 · RATE_LIMITED 429 ·
//     SERVICE_UNAVAILABLE 503 · TRANSFER_ID_REQUIRED 400 ·
//     ORDER_UNDER_REVIEW 409 · TRANSFER_STATE_CHANGED 400 ·
//     NOT_TRANSFER_BUYER 403 · INTERNAL 500 (only before the confirmation).
//
// NON-200 ANSWERS AFTER THE RPC, kept deliberately (2026-10-21 review):
//   • 403 NOT_TRANSFER_BUYER — unreachable: the RPC checks the buyer before
//     the status, so a non-buyer is refused there (400) and never gets here.
//   • 409 ORDER_UNDER_REVIEW (§5 and the claim's DISPUTED) — a `disputed`
//     row is refused by the RPC first (400); these answer only when a dispute
//     freezes the row between the RPC and the re-read / claim (race only).
//   • 400 TRANSFER_STATE_CHANGED — race only: the status left
//     buyer_confirmed / auto_released between the RPC and the re-read.
//
// F-5 DELETION-PENDING (owner ruling, A 2026-10-21): the guard can only run
// after the confirmation is recorded, so it is NOT an error. It answers 200
// { success:true, payout_status:'processing', notice:{ code:
// 'ACCOUNT_DELETION_PENDING', message } } — the former 403 text, now an
// advisory clients may surface or ignore — and withholds only this call's
// payout attempt; the sweep pays the buyer_confirmed row exactly as after
// the old 403. It sits just before the payout attempt, the only thing it
// still withholds: a row already paid answers already_released first, and a
// failed re-read answers 200 processing without probing. (Refusing the
// acquisition itself, the frozen F-5 intent, would need the guard BEFORE the
// RPC — an owner decision, not made here.)
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException, captureMessage } from '../_shared/sentry.ts';
import { executePayoutAttempt } from '../_shared/payouts.ts';

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

function jsonResponse(
  req: Request,
  status: number,
  body: Record<string, unknown>,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(
    JSON.stringify(body),
    { status, headers: { 'Content-Type': 'application/json', ...extraHeaders, ...getResponseHeaders(req) } },
  );
}

/** Every error body: the unchanged `error` text plus a stable `code` (or null). */
function errorResponse(
  req: Request,
  status: number,
  error: string,
  code: string | null,
  extraHeaders: Record<string, string> = {},
): Response {
  return jsonResponse(req, status, { error, code }, extraHeaders);
}

// A Postgres HINT becomes `code` only when it is a machine code
// (UPPER_SNAKE). Prose hints — Postgres' own, or PostgREST's "Perhaps you
// meant …" — are not a contract and map to null.
const HINT_CODE_RE = /^[A-Z][A-Z0-9_]{2,63}$/;
function hintCode(err: { hint?: unknown } | null | undefined): string | null {
  const hint = err?.hint;
  return typeof hint === 'string' && HINT_CODE_RE.test(hint) ? hint : null;
}

// Is a confirm_transfer_received refusal the "already confirmed" one? (header,
// WHEN IS THE CONFIRMATION KNOWN?) 'proof' — 171's HINT with DETAIL = the
// status the RPC read FOR UPDATE. 'claim' — no such HINT; the message merely
// names a confirmed status, so the §5 re-read must show it. null — a real
// refusal. With the HINT present its DETAIL decides; the message is not read.
const ALREADY_CONFIRMED_STATUSES = ['buyer_confirmed', 'auto_released'];
function alreadyConfirmedEvidence(
  err: { message?: unknown; hint?: unknown; details?: unknown },
): 'proof' | 'claim' | null {
  if (err.hint === 'TRANSFER_NOT_CONFIRMABLE') {
    return typeof err.details === 'string' && ALREADY_CONFIRMED_STATUSES.includes(err.details) ? 'proof' : null;
  }
  const message = typeof err.message === 'string' ? err.message : '';
  return ALREADY_CONFIRMED_STATUSES.some((s) => message.includes(s)) ? 'claim' : null;
}

// F-5's former 403 text, byte-identical, now carried as an advisory notice.
const DELETION_PENDING_NOTICE = {
  code: 'ACCOUNT_DELETION_PENDING',
  message: 'Your account deletion request is pending. Withdraw it in Settings to accept new transfers.',
};

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
// create-connect-account, delete-account (only this function disambiguates
// FALSE below; the others still answer 429 for a limiter error).
type RateLimitResult = 'allowed' | 'over_limit' | 'error';

// Clock tolerance between the database's now() (window_start) and this
// isolate's Date.now() when deciding whether the window is still live.
const RATE_LIMIT_CLOCK_SLACK_MS = 30_000;

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
    if (data === true) return 'allowed';
    if (data !== false) {
      console.warn('Rate limit RPC returned a non-boolean (failing closed):', data);
      return 'error';
    }
    return await classifyRateLimitDenial(supabase, userId, action, maxRequests, windowSeconds);
  } catch (err) {
    console.warn('Rate limit check threw (failing closed):', err);
    return 'error';
  }
}

// check_rate_limit (021) returns FALSE both for a real over-limit and from its
// EXCEPTION WHEN OTHERS branch (an internal error, failing closed; the
// WARNING never reaches PostgREST). The counter tells them apart: a real
// over-limit has just committed counter > max inside a live window; the
// EXCEPTION branch rolled its upsert back, so the counter is at most what an
// allowed request would leave. Both outcomes still DENY — only the status
// differs (429 vs 503). A counter read that fails is itself a limiter fault:
// 503.
async function classifyRateLimitDenial(
  supabase: SupabaseClient,
  userId: string,
  action: string,
  maxRequests: number,
  windowSeconds: number,
): Promise<'over_limit' | 'error'> {
  const { data: row, error } = await supabase
    .from('rate_limits')
    .select('counter, window_start')
    .eq('user_id', userId)
    .eq('action', action)
    .maybeSingle();
  if (error) {
    console.warn('Rate limit denial unclassifiable — counter read failed (failing closed, 503):', error.message);
    return 'error';
  }
  const counter = typeof row?.counter === 'number' ? row.counter : null;
  const windowStart = row?.window_start ? Date.parse(row.window_start) : NaN;
  const windowLive = Number.isFinite(windowStart) &&
    windowStart >= Date.now() - windowSeconds * 1000 - RATE_LIMIT_CLOCK_SLACK_MS;
  if (counter !== null && counter > maxRequests && windowLive) return 'over_limit';
  console.warn('check_rate_limit returned false without an over-limit counter — internal limiter error (failing closed, 503):', {
    counter, window_live: windowLive,
  });
  return 'error';
}

// ── Main handler ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  // Set once the confirmation is KNOWN to be recorded (header: the RPC
  // succeeded or proved it; a message-only claim after the re-read shows it).
  // From then on no answer may be an error (header).
  let confirmationRecorded = false;
  let transferIdForLog: unknown = null;

  try {
    // ── 1. Authenticate caller ──────────────────────────────────────────
    const buyerId = await getAuthenticatedUserId(req);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ── 2. Rate limit ───────────────────────────────────────────────────
    // 5 requests per 300 seconds (5 min). Fail-closed: a limiter failure
    // (RPC error, or check_rate_limit's internal-error FALSE) returns 503
    // instead of silently bypassing rate limiting; a real over-limit 429.
    const rl = await checkRateLimit(supabase, buyerId, 'confirm-and-release', 5, 300);
    if (rl === 'error') {
      return errorResponse(req, 503, 'Service temporarily unavailable. Please try again shortly.', 'SERVICE_UNAVAILABLE', { 'Retry-After': '30' });
    }
    if (rl === 'over_limit') {
      return errorResponse(req, 429, 'Too many requests. Please try again later.', 'RATE_LIMITED', { 'Retry-After': '300' });
    }

    // ── 3. Parse input ──────────────────────────────────────────────────
    const { transfer_id } = await req.json();
    transferIdForLog = transfer_id ?? null;

    if (!transfer_id) {
      return errorResponse(req, 400, 'Missing transfer_id', 'TRANSFER_ID_REQUIRED');
    }

    // ── 4. Call confirm_transfer_received RPC ────────────────────────────
    // Uses service role so auth.uid() is NULL — the RPC falls back to
    // p_user_id for caller identity. This is the documented behavior
    // (see 002_transfers.sql line 200).
    //
    // Possible outcomes:
    //   - Success: status transitions seller_sent → buyer_confirmed
    //   - Already confirmed: RPC raises "cannot be confirmed from current
    //     status: buyer_confirmed" (171 adds HINT TRANSFER_NOT_CONFIRMABLE,
    //     DETAIL = status) — we proceed to payout; a message-only claim is
    //     verified by the §5 re-read first (header)
    //   - Not the buyer: RPC raises "Only the buyer can confirm" — we
    //     propagate this error to the client
    //   - Wrong state (pending): RPC raises error — we propagate
    const { error: rpcErr } = await supabase.rpc('confirm_transfer_received', {
      p_transfer_id: transfer_id,
      p_user_id:     buyerId,
    });

    let confirmedBy: 'rpc' | 'proof' | 'claim' = 'rpc';
    if (rpcErr) {
      // If already buyer_confirmed — or the cron already flipped it to
      // auto_released — that's fine: the buyer's goal is met, proceed to
      // the payout idempotency check (which returns already_released when
      // the money moved).
      const alreadyConfirmed = alreadyConfirmedEvidence(rpcErr);

      if (!alreadyConfirmed) {
        // Real error — wrong user, wrong state, not found, etc.
        const code = hintCode(rpcErr);
        console.error('confirm-and-release: RPC failed:', {
          transfer_id,
          buyer_id: buyerId,
          error:    rpcErr.message,
          code,
        });
        return errorResponse(req, 400, rpcErr.message, code);
      }

      confirmedBy = alreadyConfirmed;
      console.log('confirm-and-release: transfer already confirmed, proceeding to payout check', {
        transfer_id,
        evidence: alreadyConfirmed,
      });
    }

    // The RPC committed the confirmation, or proved the row already
    // confirmed: nothing below may answer with an error status for a FAILURE
    // (see header). A message-only claim waits for the §5 re-read.
    if (confirmedBy !== 'claim') confirmationRecorded = true;

    // ── 5. Transfer state (buyer check, dispute freeze, status gate) ─────
    // The claim RPC below re-checks all of this under FOR UPDATE; this read
    // exists to answer the buyer precisely (403/409/400) before any attempt.
    const { data: transfer, error: transferErr } = await supabase
      .from('transfers')
      .select('id, seller_id, buyer_id, payment_id, listing_id, status, payout_released_at, disputed_at, payout_risk_tier, buyer_confirmed_at, dispute_resolution')
      .eq('id', transfer_id)
      .single();

    if (transferErr || !transfer) {
      if (confirmationRecorded) {
        // The RPC above found this row FOR UPDATE and recorded (or proved)
        // the confirmation, so a failed re-read is transient — never "not
        // found" to the buyer (was 404, CRE-404). No payout is attempted this
        // call; the sweep pays the buyer_confirmed row.
        console.error('confirm-and-release: transfer re-read failed after the confirmation was recorded (answering 200 processing):', {
          transfer_id,
          error: transferErr,
        });
        return jsonResponse(req, 200, { success: true, payout_status: 'processing' });
      }
      // The RPC only CLAIMED the row was already confirmed, and the read that
      // would show it failed: never a 200 (a double fault must not read as
      // "confirmed"). Transient — the retry re-runs the RPC and the re-read.
      console.error('confirm-and-release: transfer re-read failed and the confirmation is unverified (answering 503):', {
        transfer_id,
        error: transferErr,
      });
      return errorResponse(req, 503, 'Service temporarily unavailable. Please try again shortly.', 'SERVICE_UNAVAILABLE', { 'Retry-After': '30' });
    }

    // Verify caller is the buyer (defense-in-depth — RPC already checks this).
    // Unreachable: the RPC refuses a non-buyer before reading the status.
    if (transfer.buyer_id !== buyerId) {
      return errorResponse(req, 403, 'Only the buyer can release payout', 'NOT_TRANSFER_BUYER');
    }

    // ── Dispute freeze (explicit, in addition to the claim predicate) ────
    // Race only: the RPC refuses a `disputed` row first (400).
    if (transfer.status === 'disputed' || transfer.disputed_at !== null) {
      return errorResponse(req, 409, 'This order is under review. Payout is frozen until the dispute is resolved.', 'ORDER_UNDER_REVIEW');
    }

    // Verify transfer is in a releasable state (auto_released = the cron
    // already claimed the row; the buyer's confirmation is tolerated).
    // Race only: the status moved between the RPC and this read.
    if (transfer.status !== 'buyer_confirmed' && transfer.status !== 'auto_released') {
      return errorResponse(req, 400, `Transfer is in unexpected state: ${transfer.status}`, 'TRANSFER_STATE_CHANGED');
    }

    // Past the status gate the row itself is buyer_confirmed / auto_released:
    // a message-only claim is now verified (no-op for the other two cases).
    confirmationRecorded = true;

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

    // Audit basis — what actually happened on THIS row. payout_decisions'
    // buyer_confirmed and the BUYER_CONFIRMED code assert that the BUYER
    // confirmed receipt; only confirm_transfer_received records that act
    // (buyer_confirmed_at). The "already confirmed" path above also admits a
    // seller-win resolution (065: status buyer_confirmed, buyer_confirmed_at
    // NULL) and an auto-released row, so the status is never evidence of it
    // (F-CR-148-SHARED follow-up, writers a1/a2). ONE basis code, deliberately:
    // the buyer's own confirmation is the primary basis when it exists, so a
    // confirmed row later resolved seller-win reports BUYER_CONFIRMED; the
    // resolution stays on the transfer row. dispute_open stays a literal false
    // at both writes below: §5 has already answered 409 for any disputed_at.
    const buyerConfirmed = Boolean(transfer.buyer_confirmed_at);
    const basisCode = buyerConfirmed ? 'BUYER_CONFIRMED'
      : transfer.dispute_resolution === 'resolved_seller_paid' ? 'DISPUTE_RESOLVED_SELLER'
      : transfer.status === 'auto_released' ? 'AUTO_RELEASED'
      : 'NO_BUYER_CONFIRMATION';

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
          reason_codes: [basisCode, reasonCode],
          evidence,
          buyer_confirmed: buyerConfirmed,
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

    // ── F-5 live-rail acquisition guard (OR-17 release train; FR-9; DSM §3.2
    // F-5): a DELETION_PENDING buyer must not CONFIRM an inbound transfer that
    // was INITIATED AFTER their deletion request (accepting it is a custody
    // acquisition). A transfer initiated BEFORE the request is resolution of
    // existing business and stays allowed. Class A read (EA-1): the caller's
    // own kernel.identity_ext row via the caller's JWT — the owner SELECT
    // policy scopes it; before migration 077 the schema is absent and the
    // probe errs → not-pending (the DB sweep's BP wall is the enforcement).
    // Owner ruling (A, 2026-10-21; header): this runs after the confirmation
    // is recorded, so it answers 200 processing + `notice` and withholds only
    // this call's payout attempt — the sweep pays the row, as after the old 403.
    let deletionPendingAcquisition = false;
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
          deletionPendingAcquisition = true;
        }
      }
    } catch {
      /* pre-077 world or transient probe failure — proceed; the DB wall holds */
    }
    if (deletionPendingAcquisition) {
      await captureMessage(
        'confirm-and-release:deletion-pending-after-confirmation',
        'DELETION_PENDING buyer confirmed a transfer initiated after the deletion request; payout left to the sweep',
        'warning',
        { transfer_id },
      );
      return respond({ success: true, payout_status: 'processing', notice: DELETION_PENDING_NOTICE });
    }

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
          reason_codes: [basisCode],
          evidence: {
            base_cents: payment?.amount ?? null,
            seller_fee_cents: payment?.seller_fee ?? null,
            seller_net_cents: outcome.sellerNetCents,
            stripe_transfer_id: outcome.stripeTransferId,
            attempt_id: outcome.attemptId,
            attempt_no: outcome.attemptNo,
            destination_suffix: outcome.destination.slice(-4),
          },
          buyer_confirmed: buyerConfirmed,
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
          // Race only (a dispute froze the row after the §5 read).
          return errorResponse(req, 409, 'This order is under review. Payout is frozen until the dispute is resolved.', 'ORDER_UNDER_REVIEW');
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
    if (confirmationRecorded) {
      // The buyer's confirmation is committed; this throw (e.g. a Stripe
      // pre-flight fetch in createSellerPayout — was 500, CRE-500) is an
      // operations problem. A claimed attempt stays open under its lease and
      // the payout sweep reconciles it; nothing is retried here.
      console.error('confirm-and-release: error after the confirmation was recorded (answering 200 processing):', {
        transfer_id: transferIdForLog,
        error: message,
      });
      await captureException('confirm-and-release:after-confirmation', err, { transfer_id: transferIdForLog });
      return jsonResponse(req, 200, { success: true, payout_status: 'processing' });
    }
    const isAuthError = /authorization|token/i.test(message);
    if (isAuthError) {
      console.warn('confirm-and-release: auth error:', message);
    } else {
      await captureException('confirm-and-release', err);
    }
    return isAuthError
      ? errorResponse(req, 401, message, 'AUTH_REQUIRED')
      : errorResponse(req, 500, 'Internal server error', 'INTERNAL');
  }
});
