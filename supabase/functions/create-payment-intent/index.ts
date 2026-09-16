import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
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
  supabase: SupabaseClient,
  userId: string,
  email: string | null,
): Promise<{ customerId: string; ephemeralKeySecret: string }> {
  // ── (a) Look up cached customer id on the profile ──────────────────────
  const { data: profile } = await supabase
    .from('profiles')
    .select('stripe_customer_id')
    .eq('id', userId)
    .single();

  let customerId = ((profile as { stripe_customer_id?: string | null } | null)?.stripe_customer_id as string | null) ?? null;

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
    // The create body must be byte-stable under the fixed key: email is
    // attached in a SEPARATE update call, because an email that changed
    // between two attempts inside the 24h idempotency window would make
    // the same key carry different parameters — Stripe rejects that and
    // checkout 500s until the key expires.
    const created = await stripeFetch<{ id: string }>('/customers', {
      method:         'POST',
      body:           { 'metadata[user_id]': userId },
      // Idempotent on (user_id) — even if two PI requests race, both
      // resolve to the same customer.
      idempotencyKey: `customer_${userId}`,
    });
    customerId = created.id;

    if (email) {
      try {
        await stripeFetch(`/customers/${customerId}`, { method: 'POST', body: { email } });
      } catch (emailErr) {
        // Cosmetic — the customer works without an email on file.
        console.warn('Failed to set customer email (continuing):', emailErr);
      }
    }

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

// ── Explicit expired / superseded handling (Package 1, decision 3) ──────────
// A `pending` PaymentIntent is a live, confirmable client_secret — a Stripe
// PaymentIntent never expires on its own. Two situations make one stale:
//   * scope 'buyer': THIS buyer is refused for a listing they can no longer
//     buy (reservation lapsed, another buyer holds it, the listing sold). Any
//     pending PI this function minted for the same (listing, buyer, mode) is
//     bound to inventory the buyer no longer has a claim on.
//   * scope 'other-buyers' (review round 1, MAJOR-3): this buyer is the LIVE
//     holder / entitled winner and is about to receive a secret. Every OTHER
//     buyer's pending PI on the listing (any mode) is a secret its owner could
//     still confirm without ever calling this function again — a capture that
//     would then collide with the entitled buyer's.
// Cancel at Stripe, and mark the row `failed` ONLY when the cancel provably
// succeeded (a PI that already succeeded / is processing must stay `pending`
// for the webhook / confirm-payment to settle or compensate). Best-effort:
// failures are logged and never change the caller's response.
type RetireScope = { kind: 'buyer'; mode: string } | { kind: 'other-buyers' };

// Returns true only when every matching row was provably retired (132, D review
// F-132-2): the 'other-buyers' caller refuses to hand out a secret otherwise. The
// 'buyer' scope runs on a refusal, so its result is ignored there.
async function retirePendingIntents(
  supabase: SupabaseClient,
  listingId: string,
  buyerId: string,
  scope: RetireScope,
  reason: string,
  bound: <T>(p: Promise<T>, label: string) => Promise<T> = (p) => p,
): Promise<boolean> {
  let q = supabase
    .from('payments')
    .select('id, stripe_payment_intent_id, buyer_id, status')
    .eq('listing_id', listingId);
  q = scope.kind === 'buyer'
    ? q.eq('buyer_id', buyerId).eq('mode', scope.mode).eq('status', 'pending')
    // another buyer's `processing` row may still capture: it must be provably dead too
    : q.neq('buyer_id', buyerId).in('status', ['pending', 'processing']);
  const { data, error } = await q;
  const tag = scope.kind === 'buyer' ? 'retire-stale-pending' : 'retire-other-pending';
  if (error) {
    console.warn(`${tag}: lookup failed:`, error.message);
    return false;
  }
  const rows = (data ?? []) as unknown as { id: string; stripe_payment_intent_id: string | null; buyer_id: string; status: string }[];
  let allRetired = true;
  for (const row of rows) {
    const canceled = await cancelPaymentIntentBestEffort(row.stripe_payment_intent_id, tag, bound);
    if (!canceled) { allRetired = false; continue; }
    const retire = supabase.from('payments').update({ status: 'failed' }).eq('id', row.id);
    const { error: retireErr } = scope.kind === 'buyer'
      ? await retire.eq('status', 'pending')
      : await retire.in('status', ['pending', 'processing']);
    if (retireErr) {
      console.warn(`${tag}: row update failed:`, retireErr.message);
      allRetired = false;
    }
    logStage(scope.kind === 'buyer' ? 'stale-pending-retired' : 'other-buyer-pending-retired', {
      payment_row: row.id, pi_id: row.stripe_payment_intent_id, reason,
      ...(scope.kind === 'other-buyers' ? { other_buyer_id: row.buyer_id } : {}),
    });
  }
  return allRetired;
}

// Cancel a PaymentIntent at Stripe. Returns true only when Stripe confirms the
// cancel (or it was already canceled); anything else — succeeded, processing,
// network error — returns false so the caller leaves the row `pending`.
async function cancelPaymentIntentBestEffort(
  piId: string | null, tag: string, bound: <T>(p: Promise<T>, label: string) => Promise<T> = (p) => p,
): Promise<boolean> {
  if (!piId) return true;
  try {
    // A timed-out cancel is NOT a cancel: the caller treats the intent as still live.
    const res = await bound(stripeFetchRaw(`/payment_intents/${piId}/cancel`, { method: 'POST' }), `cancel ${piId}`);
    const err = (res.data as { error?: { code?: string; message?: string } } | null)?.error;
    const canceled = res.ok || /status of canceled|already.*cancel/i.test(err?.message ?? '');
    if (!canceled) {
      console.warn(`${tag}: PI cancel refused (row left pending):`, { pi_id: piId, code: err?.code ?? null });
    }
    return canceled;
  } catch (cancelErr) {
    console.warn(`${tag}: PI cancel threw (row left pending):`, cancelErr);
    return false;
  }
}

// ── Migration 130: per-(listing, buyer, mode) secret hand-out claim ─────────
// A request that is about to reuse or supersede a pending PaymentIntent must
// hold the group claim, so two concurrent requests by the same buyer can never
// both hand out a live secret (the L1 concurrency residual). claim_held is
// retried briefly (a reuse claim lasts milliseconds; a supersede, one Stripe
// round trip); anything still held answers 409 without a secret or a mint.
type CheckoutClaim =
  | { kind: 'held'; paymentId: string; token: string }
  | { kind: 'degraded' }                               // 130 not applied (PGRST202): #64 behaviour
  | { kind: 'refused'; reason: string }
  | { kind: 'error'; message: string };

const CLAIM_RETRY_ATTEMPTS = 10;
const CLAIM_RETRY_DELAY_MS = 200;

async function claimCheckout(
  supabase: SupabaseClient, listingId: string, buyerId: string, paymentId: string,
): Promise<CheckoutClaim> {
  for (let attempt = 0; attempt < CLAIM_RETRY_ATTEMPTS; attempt++) {
    const { data, error } = await supabase.rpc('claim_checkout_supersede', {
      p_listing_id: listingId, p_buyer_id: buyerId, p_payment_id: paymentId,
    });
    if (error) {
      const e = error as { code?: string; message?: string };
      if (e.code === 'PGRST202') {
        await captureException('create-payment-intent', new Error(`claim_checkout_supersede unavailable (migration 130 not applied): ${e.message ?? ''}`));
        return { kind: 'degraded' };
      }
      return { kind: 'error', message: `${e.code ?? '?'} ${e.message ?? ''}` };
    }
    const r = (data ?? null) as { claimed?: boolean; claim_token?: string | null; reason?: string } | null;
    if (!r || typeof r.claimed !== 'boolean') return { kind: 'error', message: 'claim_checkout_supersede returned no result' };
    if (r.claimed && r.claim_token) return { kind: 'held', paymentId, token: r.claim_token };
    if (r.reason !== 'claim_held') return { kind: 'refused', reason: r.reason ?? 'unknown' };
    if (attempt < CLAIM_RETRY_ATTEMPTS - 1) await new Promise((res) => setTimeout(res, CLAIM_RETRY_DELAY_MS));
  }
  return { kind: 'refused', reason: 'claim_held' };
}

async function releaseCheckout(supabase: SupabaseClient, claim: CheckoutClaim | null): Promise<void> {
  if (!claim || claim.kind !== 'held') return;
  const { data, error } = await supabase.rpc('release_checkout_supersede', {
    p_payment_id: claim.paymentId, p_claim_token: claim.token,
  });
  const r = (data ?? null) as { released?: boolean; reason?: string } | null;
  if (error || !r?.released) {
    // Not fatal: an unreleased claim lapses after 120 s. Surfaced so it is visible.
    console.warn('release_checkout_supersede did not release:', { payment_id: claim.paymentId, reason: r?.reason ?? null, error: error?.message ?? null });
  }
}

// ── Migration 132: pre-mint checkout group record ─────────────────────────────
// 130's claim lives on a pending payment row, so two concurrent requests that
// both find NO pending row both mint; when their idempotency keys diverge (the
// `_u` replay retry, a re-price between reads, a failedAttempts flip) that is two
// intents, two secrets and two captured charges. Every request therefore takes
// the (listing, buyer, mode) group record BEFORE it reads prior payments and
// holds it through every mint and hand-out. claim_held is retried briefly and
// then answered 409 without a mint or a secret. There is no degraded mode: if
// 132 is absent (PGRST202) or the claim errors, the request fails closed (503),
// so migration 132 must be applied before this edge ships.
type GroupClaim = { listingId: string; buyerId: string; mode: string; token: string };
type GroupClaimResult =
  | { kind: 'held'; claim: GroupClaim }
  | { kind: 'refused'; reason: string }
  | { kind: 'error'; message: string };

async function claimCheckoutGroup(
  supabase: SupabaseClient, listingId: string, buyerId: string, mode: string,
): Promise<GroupClaimResult> {
  for (let attempt = 0; attempt < CLAIM_RETRY_ATTEMPTS; attempt++) {
    const { data, error } = await supabase.rpc('claim_checkout_group', {
      p_listing_id: listingId, p_buyer_id: buyerId, p_mode: mode,
    });
    if (error) {
      const e = error as { code?: string; message?: string };
      if (e.code === 'PGRST202') {
        await captureException('create-payment-intent', new Error(`claim_checkout_group unavailable (migration 132 not applied): ${e.message ?? ''}`));
      }
      return { kind: 'error', message: `${e.code ?? '?'} ${e.message ?? ''}` };
    }
    const r = (data ?? null) as { claimed?: boolean; claim_token?: string | null; reason?: string } | null;
    if (!r || typeof r.claimed !== 'boolean') return { kind: 'error', message: 'claim_checkout_group returned no result' };
    if (r.claimed && r.claim_token) return { kind: 'held', claim: { listingId, buyerId, mode, token: r.claim_token } };
    if (r.reason !== 'claim_held') return { kind: 'refused', reason: r.reason ?? 'unknown' };
    if (attempt < CLAIM_RETRY_ATTEMPTS - 1) await new Promise((res) => setTimeout(res, CLAIM_RETRY_DELAY_MS));
  }
  return { kind: 'refused', reason: 'claim_held' };
}

async function releaseCheckoutGroup(supabase: SupabaseClient, claim: GroupClaim): Promise<void> {
  const { data, error } = await supabase.rpc('release_checkout_group', {
    p_listing_id: claim.listingId, p_buyer_id: claim.buyerId, p_mode: claim.mode, p_claim_token: claim.token,
  });
  const r = (data ?? null) as { released?: boolean; reason?: string } | null;
  if (error || !r?.released) {
    // Not fatal: an unreleased group record lapses after 120 s. Surfaced so it is visible.
    console.warn('release_checkout_group did not release:', { mode: claim.mode, reason: r?.reason ?? null, error: error?.message ?? null });
  }
}

// 132 (D review, reuse-order): the pending row is recorded ONLY while this
// request still holds the group claim. A plain INSERT is not bound to the claim:
// a request stalled in transit could commit its row after a reclaimer had minted
// and handed out its own secret, and the stalled row — newest by created_at —
// would then be reused, giving two live secrets. record_checkout_attempt takes
// the group row FOR SHARE on the token, so a reclaim waits for this insert and
// reuses it, and an abandoned holder records nothing.
type RecordedAttempt =
  | { kind: 'recorded' }
  | { kind: 'claim_lost' }
  | { kind: 'error'; error: { code?: string; message?: string; details?: string; hint?: string } };

async function recordCheckoutAttempt(
  supabase: SupabaseClient, claim: GroupClaim,
  row: { sellerId: string | null; amount: number; buyerFee: number; sellerFee: number; total: number; intentId: string; livemode: boolean | null },
): Promise<RecordedAttempt> {
  const { data, error } = await supabase.rpc('record_checkout_attempt', {
    p_listing_id: claim.listingId, p_buyer_id: claim.buyerId, p_mode: claim.mode, p_claim_token: claim.token,
    p_seller_id: row.sellerId, p_amount: row.amount, p_buyer_fee: row.buyerFee, p_seller_fee: row.sellerFee,
    p_total: row.total, p_payment_intent_id: row.intentId, p_livemode: row.livemode,
  });
  if (error) return { kind: 'error', error: error as { code?: string; message?: string } };
  const r = (data ?? null) as { inserted?: boolean; reason?: string } | null;
  if (r?.inserted === true) return { kind: 'recorded' };
  if (r?.reason === 'claim_lost') return { kind: 'claim_lost' };
  return { kind: 'error', error: { code: 'PGRST-noresult', message: `record_checkout_attempt returned ${JSON.stringify(r)}` } };
}

// ── E-1: the 120 s stale window must bind the request that HOLDS the claim ────
// claim_checkout_supersede treats a claim older than 120 s as abandoned, so a
// holder that is still running past that point could act after another request
// legitimately reclaimed the group. The RPC cannot stop that; this edge does:
//   * every Stripe call inside the claimed section is bounded (per call, and
//     never beyond what is left of the section budget, default 90 s < 120 s);
//   * immediately before inserting a replacement, cancelling the superseded
//     intent, and handing out any secret, the holder re-reads its claim token
//     and checks its budget. A lost claim or a spent budget answers 409 without
//     a secret; a failed read answers 503.
const DEFAULT_STRIPE_CALL_TIMEOUT_MS = 20_000;
const DEFAULT_CLAIM_BUDGET_MS = 90_000;

function positiveMsFromEnv(name: string, fallback: number): number {
  const v = Number(Deno.env.get(name));
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

class ClaimedSectionTimeout extends Error {}

type ClaimGuard = {
  bound: <T>(p: Promise<T>, label: string) => Promise<T>;
  /** checks the 132 group record, then 130's row claim when one is in force (reuse / supersede). */
  check: () => Promise<'held' | 'lost' | 'expired' | 'error'>;
};

function makeClaimGuard(
  supabase: SupabaseClient, group: GroupClaim, getClaim: () => CheckoutClaim | null, startedMs: number,
): ClaimGuard {
  const callMs = positiveMsFromEnv('CHECKOUT_STRIPE_TIMEOUT_MS', DEFAULT_STRIPE_CALL_TIMEOUT_MS);
  const budgetMs = positiveMsFromEnv('CHECKOUT_CLAIM_BUDGET_MS', DEFAULT_CLAIM_BUDGET_MS);
  const remaining = () => budgetMs - (Date.now() - startedMs);
  return {
    bound: <T>(p: Promise<T>, label: string): Promise<T> => {
      const ms = Math.max(1, Math.min(callMs, remaining()));
      let timer: ReturnType<typeof setTimeout> | undefined;
      const timeout = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new ClaimedSectionTimeout(`stripe call timed out after ${ms}ms: ${label}`)), ms);
      });
      return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
    },
    check: async () => {
      if (remaining() <= 0) return 'expired';
      const { data: g, error: gErr } = await supabase
        .from('checkout_group_claim')
        .select('claim_token')
        .eq('listing_id', group.listingId)
        .eq('buyer_id', group.buyerId)
        .eq('mode', group.mode)
        .maybeSingle();
      if (gErr) return 'error';
      if ((g as { claim_token?: string | null } | null)?.claim_token !== group.token) return 'lost';
      const claim = getClaim();
      if (!claim || claim.kind !== 'held') return 'held';
      const { data, error } = await supabase
        .from('payments')
        .select('supersede_claim_token')
        .eq('id', claim.paymentId)
        .maybeSingle();
      if (error) return 'error';
      return (data as { supersede_claim_token?: string | null } | null)?.supersede_claim_token === claim.token ? 'held' : 'lost';
    },
  };
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

    // ── F-5 live-rail acquisition guard (OR-17 release train; FR-9;
    // DELETION_STATE_MACHINE_SPEC §3.2 F-5) ─────────────────────────────
    // A caller whose account deletion is pending must not ACQUIRE on the live
    // rail (buy-now reservation/purchase, live bid funding). Disposal verbs
    // stay allowed and do not run through this function. The predicate is
    // kernel.is_deletion_pending (EXEC: service_role; STABLE definer — RPC
    // §20.17.3), reached through the service client. Before migration 077 is
    // applied the kernel schema does not exist: the probe then errs and the
    // guard treats the caller as not-pending (fail-open by design here — the
    // hard wall is the DB sweep's BP re-check at the terminal; this edge layer
    // is the UX courtesy the machine names, not the enforcement).
    try {
      const kernelClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
        db: { schema: 'kernel' },
      });
      const { data: pending, error: pendErr } = await kernelClient.rpc('is_deletion_pending', {
        p_identity: buyerId,
      });
      if (!pendErr && pending === true) {
        return new Response(
          JSON.stringify({
            error: 'Your account deletion request is pending. Withdraw it in Settings to make new purchases.',
            code: 'account_deletion_pending',
          }),
          { status: 403, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }
    } catch {
      /* pre-077 world or transient probe failure — proceed; the DB wall holds */
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
      .select('id, seller_id, current_bid, buy_now_price, buy_now_enabled, status, auction_status, winner_user_id, winning_bid_amount, reserved_by, reserved_until, ends_at')
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

    // Reservation authority (Package 1, decisions 2-3). The PaymentIntent
    // binds to the LIVE reservation holder — nobody else can mint a
    // confirmable client_secret for reserved inventory, and a holder whose
    // window lapsed must reserve again. Messages match the regexes in
    // src/lib/payments.ts so shipped builds render them.
    const nowMs = Date.now();
    const reservedUntilMs = listing.reserved_until ? new Date(listing.reserved_until as string).getTime() : NaN;
    const reservationLive = listing.status === 'reserved' && !!listing.reserved_by && reservedUntilMs > nowMs;
    // EVERY refusal of this buyer goes through refuse() so the buyer's stale
    // pending PaymentIntent is retired (review round 1, MAJOR-2: the most
    // common lapsed path — cron sweep flipped the hold to 'active' — used to
    // return before retirement). Status/message are preserved per path for
    // shipped clients.
    const refuse = async (status: number, error: string, reason: string) => {
      logStage('checkout-refused', { listing_id, mode, reason, status: listing.status, reserved_by_is_buyer: listing.reserved_by === buyerId });
      await retirePendingIntents(supabase, listing_id, buyerId, { kind: 'buyer', mode }, reason);
      return new Response(
        JSON.stringify({ error }),
        { status, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    };

    // Sold in fact (review round 1, MAJOR-1c): a succeeded payment by ANOTHER
    // buyer means the listing is sold whether or not the webhook / client has
    // settled it yet (money wins — incl. over an ended auction with a
    // different unpaid winner, NOTE-7). Nobody else may mint against it.
    // The buyer's OWN succeeded payment is handled below ('already completed').
    if (mode === 'buy_now' || mode === 'auction') {
      const { data: succeededRows, error: succeededErr } = await supabase
        .from('payments')
        .select('id, buyer_id')
        .eq('listing_id', listing_id)
        .eq('status', 'succeeded');
      if (succeededErr) {
        // Fail closed: without this answer we cannot prove the listing is not
        // already someone else's.
        logStage('sold-check-failed', { listing_id, error: succeededErr.message });
        return new Response(
          JSON.stringify({ error: 'Service temporarily unavailable. Please try again shortly.' }),
          { status: 503, headers: { 'Content-Type': 'application/json', 'Retry-After': '10', ...getResponseHeaders(req) } }
        );
      }
      const soldToAnother = ((succeededRows ?? []) as { id: string; buyer_id: string }[])
        .some((p) => p.buyer_id !== buyerId);
      if (soldToAnother) {
        return refuse(409, 'This listing is already sold.', 'sold-to-another-buyer');
      }
    }

    if (mode === 'buy_now') {
      if (listing.status === 'sold') {
        return refuse(409, 'This listing is already sold.', 'listing-sold');
      }
      if (listing.status !== 'reserved') {
        // Same 400 + text as before Package 1 (shipped clients match
        // /not reserved for purchase/), now via refuse() so the lapsed
        // holder's pending PI is retired after the cron sweep too.
        return refuse(400, 'Listing is not reserved for purchase', 'not-reserved');
      }
      if (listing.reserved_by !== buyerId) {
        return refuse(409, 'This listing is already reserved by another buyer.', 'reserved-by-another');
      }
      if (!reservationLive) {
        return refuse(409, 'Your reservation expired. Please reserve the listing again.', 'reservation-expired');
      }
      if (!listing.buy_now_enabled || !listing.buy_now_price) {
        return new Response(
          JSON.stringify({ error: 'Buy Now is not available for this listing' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      amount = listing.buy_now_price;
    } else if (mode === 'auction') {
      if (listing.status === 'sold') {
        return refuse(409, 'This listing is already sold.', 'listing-sold');
      }
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
      // A Buy-Now hold has priority over the auction win while it is live
      // (decision 3); complete_auction_payment enforces the same rule.
      if (reservationLive && listing.reserved_by !== buyerId) {
        return refuse(409, 'This listing is already reserved by another buyer.', 'reserved-by-another');
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

    // 132: the group record precedes the prior-payments read and every mint.
    const groupClaim = await claimCheckoutGroup(supabase, listing_id, buyerId, mode);
    if (groupClaim.kind === 'error') {
      logStage('checkout-group-claim-error', { listing_id, mode, error: groupClaim.message });
      return new Response(
        JSON.stringify({ error: 'Service temporarily unavailable. Please try again shortly.' }),
        { status: 503, headers: { 'Content-Type': 'application/json', 'Retry-After': '5', ...getResponseHeaders(req) } }
      );
    }
    if (groupClaim.kind === 'refused') {
      logStage('checkout-group-claim-refused', { listing_id, mode, reason: groupClaim.reason });
      return new Response(
        JSON.stringify({ error: 'Your checkout is being updated. Please try again.', server_total_cents: totalCents }),
        { status: 409, headers: { 'Content-Type': 'application/json', 'Retry-After': '2', ...getResponseHeaders(req) } }
      );
    }
    // E-1: the section budget starts when the group record is taken.
    const sectionStartedMs = Date.now();
    // 130: the row claim is taken below, before reusing or superseding an attempt.
    let checkoutClaim: CheckoutClaim | null = null;
    const claimGuard = makeClaimGuard(supabase, groupClaim.claim, () => checkoutClaim, sectionStartedMs);
    try {

    // Fetch EVERY prior payment row for this (listing, buyer, mode), terminal
    // ones included. Failed attempts don't block a retry, but they MUST salt
    // the Stripe idempotency key below: after a failed attempt this function
    // cancels the PaymentIntent, and Stripe's 24h idempotency replay would
    // otherwise hand back that same canceled PI on every retry — whose id
    // then collides with the failed row under payments' UNIQUE
    // (stripe_payment_intent_id). That exact chain 500'd every checkout
    // retry on 2026-08-03.
    //
    // 132 (D review F-132-1): the read spans BOTH modes. One buyer can be entitled
    // to Buy Now and to the auction on the same listing at once, and the
    // succeeded / processing / live-attempt decisions below must see both.
    const { data: allPayments, error: paymentsErr } = await supabase
      .from('payments')
      .select('id, stripe_payment_intent_id, status, mode')
      .eq('listing_id', listing_id)
      .eq('buyer_id', buyerId)
      // newest first, so "the pending attempt" is deterministic (R-2)
      .order('created_at', { ascending: false });

    const existingPayments = (allPayments ?? []) as
      { id: string; stripe_payment_intent_id: string; status: string; mode: string }[];
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

    // 132 (D review F-132-3): before ANY hand-out, every other live attempt of this
    // buyer on this listing must be provably dead. Two same-mode pending rows can
    // outlive one request — the supersede path inserts the replacement and then
    // cancels the superseded intent, and a crash between the two leaves both — and
    // the next request would hand out the newest while the older secret is still
    // confirmable. The read is FRESH (not the snapshot) so it also covers a writer
    // this request never saw. Same fail-closed rule as the other-buyer retire.
    const otherLiveAttemptsCleared = async (keepIntentId: string, stage: string): Promise<boolean> => {
      const { data, error } = await supabase
        .from('payments')
        .select('id, stripe_payment_intent_id, status')
        .eq('listing_id', listing_id)
        .eq('buyer_id', buyerId)
        .in('status', ['pending', 'processing']);
      if (error) {
        logStage('other-attempt-sweep-failed', { stage, error: error.message });
        return false;
      }
      let clear = true;
      for (const row of (data ?? []) as { id: string; stripe_payment_intent_id: string | null; status: string }[]) {
        if (row.stripe_payment_intent_id === keepIntentId) continue;
        const canceled = await cancelPaymentIntentBestEffort(row.stripe_payment_intent_id, 'retire-other-attempt', claimGuard.bound);
        if (!canceled) { clear = false; continue; }
        const { error: retireErr } = await supabase
          .from('payments')
          .update({ status: 'failed' })
          .eq('id', row.id)
          .in('status', ['pending', 'processing']);
        if (retireErr) { clear = false; continue; }
        logStage('other-attempt-retired', { stage, payment_row: row.id, pi_id: row.stripe_payment_intent_id });
      }
      return clear;
    };

    // Withdrawing an intent this request minted is safe ONLY while no payments row
    // references it. Stripe replays one intent for a repeated idempotency key, so a
    // concurrent request of the same group can hold the SAME intent and may already
    // have recorded and handed it out; cancelling it then kills a live checkout.
    const withdrawUnrecordedIntent = async (intentId: string, tag: string): Promise<void> => {
      const { data, error } = await supabase
        .from('payments')
        .select('id')
        .eq('stripe_payment_intent_id', intentId)
        .maybeSingle();
      if (error) {
        logStage('withdraw-skipped-unknown', { tag, pi_id: intentId, error: error.message });
        return;
      }
      if (data) {
        logStage('withdraw-skipped-recorded-elsewhere', { tag, pi_id: intentId });
        return;
      }
      await cancelPaymentIntentBestEffort(intentId, tag, claimGuard.bound);
    };

    const checkoutBusy = (stage: string, detail: Record<string, unknown> = {}): Response => {
      logStage(stage, { listing_id, mode, ...detail });
      return new Response(
        JSON.stringify({ error: 'Your checkout is being updated. Please try again.', server_total_cents: totalCents }),
        { status: 409, headers: { 'Content-Type': 'application/json', 'Retry-After': '5', ...getResponseHeaders(req) } }
      );
    };

    // 132 (P1): an attempt of this buyer on this listing (either mode) that is
    // still `processing` may yet capture. Minting, reusing or superseding another
    // attempt now would hand out a second confirmable secret whose capture
    // collides with it. Nothing sweeps `processing` rows (get_unsettled_payments
    // has no such arm), so the refusal asks Stripe instead of waiting for the
    // webhook: a canceled intent is retired and no longer blocks; a succeeded one
    // is the completed payment; anything else, or no answer, refuses without a secret.
    for (const proc of existingPayments.filter((p) => p.status === 'processing')) {
      let piStatus: string | null = null;
      try {
        const got = await claimGuard.bound(stripeFetchRaw(`/payment_intents/${proc.stripe_payment_intent_id}`), 'retrieve processing intent');
        piStatus = got.ok ? ((got.data as { status?: string } | null)?.status ?? null) : null;
      } catch { piStatus = null; }
      if (piStatus === 'succeeded') {
        return new Response(
          JSON.stringify({ error: 'Payment already completed for this listing' }),
          { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      if (piStatus !== 'canceled') {
        return checkoutBusy('checkout-refused-processing', { payment_row: proc.id, pi_status: piStatus });
      }
      const { error: retireErr } = await supabase
        .from('payments')
        .update({ status: 'failed' })
        .eq('id', proc.id)
        .eq('status', 'processing');
      if (retireErr) return checkoutBusy('checkout-refused-processing-retire-failed', { payment_row: proc.id });
      proc.status = 'failed';
      logStage('processing-row-retired-canceled-at-stripe', { payment_row: proc.id });
    }

    // 132 (D review F-132-1): a live attempt of this buyer in the OTHER mode is a
    // confirmable secret for a different amount. Neither reuse nor supersede is
    // defined across modes, so refuse without a secret or a Stripe call; the
    // attempt resolves through its own mode (paid, failed, or retired with its hold).
    const otherModeLive = existingPayments.find((p) => p.mode !== mode && p.status === 'pending');
    if (otherModeLive) {
      return checkoutBusy('checkout-refused-other-mode-live', { payment_row: otherModeLive.id, other_mode: otherModeLive.mode });
    }

    let failedAttempts = existingPayments.filter((p) => p.status === 'failed' && p.mode === mode).length;
    // L1: a pending attempt this request supersedes (amount/currency changed).
    // It is cancelled only AFTER the replacement's row exists — see below.
    let superseded: { id: string; stripe_payment_intent_id: string } | null = null;

    // This buyer is entitled and is about to receive a confirmable secret
    // (reused or freshly minted). Retire every OTHER buyer's live PaymentIntent
    // on the listing first (review round 1, MAJOR-3): a lapsed holder who never
    // calls back still owns a live secret otherwise.
    // 132 (D review F-132-2): this FAILS CLOSED. An intent that is not provably
    // cancelled (Stripe refuses because it is processing or succeeded, the cancel
    // errors or times out) or a row already `processing` may still capture; handing
    // this buyer a second secret would collide. Refuse without a secret or a mint.
    const othersClear = await retirePendingIntents(
      supabase, listing_id, buyerId, { kind: 'other-buyers' }, 'entitled-buyer-checkout', claimGuard.bound,
    );
    if (!othersClear) {
      return checkoutBusy('checkout-refused-other-buyer-live');
    }

    const pendingPayment = existingPayments.find((p) => p.status === 'pending' && p.mode === mode);
    // E-1: a guard verdict other than 'held' never hands out a secret.
    const claimLost = (verdict: 'lost' | 'expired' | 'error', stage: string): Response => {
      logStage('checkout-claim-lost', { stage, verdict });
      return verdict === 'error'
        ? new Response(
            JSON.stringify({ error: 'Service temporarily unavailable. Please try again shortly.' }),
            { status: 503, headers: { 'Content-Type': 'application/json', 'Retry-After': '5', ...getResponseHeaders(req) } })
        : new Response(
            JSON.stringify({ error: 'Your checkout is being updated. Please try again.', server_total_cents: totalCents }),
            { status: 409, headers: { 'Content-Type': 'application/json', 'Retry-After': '2', ...getResponseHeaders(req) } });
    };
    if (pendingPayment) {
      checkoutClaim = await claimCheckout(supabase, listing_id, buyerId, pendingPayment.id);
      if (checkoutClaim.kind === 'error') {
        logStage('checkout-claim-error', { payment_row: pendingPayment.id, error: checkoutClaim.message });
        return new Response(
          JSON.stringify({ error: 'Service temporarily unavailable. Please try again shortly.' }),
          { status: 503, headers: { 'Content-Type': 'application/json', 'Retry-After': '5', ...getResponseHeaders(req) } }
        );
      }
      if (checkoutClaim.kind === 'refused') {
        logStage('checkout-claim-refused', { payment_row: pendingPayment.id, reason: checkoutClaim.reason });
        return new Response(
          JSON.stringify({ error: 'Your checkout is being updated. Please try again.', server_total_cents: totalCents }),
          { status: 409, headers: { 'Content-Type': 'application/json', 'Retry-After': '2', ...getResponseHeaders(req) } }
        );
      }
    }
    try {
    if (pendingPayment) {
      // Retrieve existing PaymentIntent from Stripe
      const existingPi = await claimGuard.bound(stripeFetchRaw(
        `/payment_intents/${pendingPayment.stripe_payment_intent_id}`,
      ), 'retrieve pending intent');
      const existingPiData = existingPi.data as { id?: string; status?: string; client_secret?: string; amount?: number; currency?: string };

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
        } else if (existingPiData.amount !== totalCents || existingPiData.currency !== 'usd') {
          // I1 amount binding on the REUSE path (review round 1, MINOR-4): the
          // seller can re-price on UPDATE (072). Handing back a PI minted at
          // the old amount would charge the buyer a number the UI no longer
          // shows. Supersede it with a fresh PI at today's total.
          //
          // L1 ORDER: the replacement's `pending` row is inserted BEFORE the old
          // intent is cancelled. Cancelling first makes Stripe emit
          // payment_intent.canceled while no sibling attempt exists, so a fast
          // webhook's release_reservation_for_payment finds no live sibling and
          // frees the hold this buyer is about to pay against. The old PI is
          // therefore cancelled after the insert below; the salt counts it now
          // so the replacement never replays the old idempotency key.
          logStage('reuse-rejected-amount-mismatch', {
            pi_id: existingPiData.id, pi_amount: existingPiData.amount ?? null, pi_currency: existingPiData.currency ?? null,
            server_total_cents: totalCents,
          });
          superseded = { id: pendingPayment.id, stripe_payment_intent_id: pendingPayment.stripe_payment_intent_id };
          failedAttempts += 1;
        } else if (existingPiData.client_secret) {
          const verdict = await claimGuard.check();
          if (verdict !== 'held') return claimLost(verdict, 'before-reuse-secret');
          if (!await otherLiveAttemptsCleared(existingPiData.id ?? '', 'before-reuse-secret')) {
            return checkoutBusy('checkout-refused-other-attempt', { stage: 'before-reuse-secret' });
          }
          logStage('reuse-pending-pi', { pi_id: existingPiData.id, pi_status: existingPiData.status, amount_cents: existingPiData.amount });
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
    // The customer id is part of the key because it is part of the BODY:
    // if the Stripe customer is ever re-created mid-window (stale-id probe
    // or a failed profile persist), an unchanged key with a changed
    // customer param would hit Stripe's idempotency-parameters error and
    // brick this listing's checkout for 24h. Same class of bug — and same
    // fix — as the payout destination salting in _shared/payouts.ts.
    const piIdempotencyKey =
      `pi_${listing_id}_${buyerId}_${mode}_${totalCents}_c${customerCtx.customerId}` +
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
      // Forensics only (Package 1): which reservation window this intent was
      // minted against. Buy-Now only — the auction path has no window.
      ...(mode === 'buy_now' && listing.reserved_until
        ? { 'metadata[reserved_until]': String(listing.reserved_until) }
        : {}),
    };

    type PiResponse = { id: string; client_secret: string; status?: string; livemode?: boolean };
    let stripeData: PiResponse;
    try {
      stripeData = await claimGuard.bound(stripeFetch<PiResponse>('/payment_intents', {
        method: 'POST',
        idempotencyKey: piIdempotencyKey,
        body: piBody,
      }), 'create intent');
      if (stripeData.status === 'canceled') {
        // Idempotency replay still returned a dead PI (possible if a failed
        // row was removed out-of-band, shifting the salt back onto a spent
        // key). One uniquely-salted retry breaks out of the replay window.
        logStage('pi-replay-canceled', { pi_id: stripeData.id });
        stripeData = await claimGuard.bound(stripeFetch<PiResponse>('/payment_intents', {
          method: 'POST',
          idempotencyKey: `${piIdempotencyKey}_u${crypto.randomUUID()}`,
          body: piBody,
        }), 'create intent (replay retry)');
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
    {
      // E-1: never record (and so never later expose) a replacement once the claim is gone.
      const verdict = await claimGuard.check();
      if (verdict !== 'held') {
        await withdrawUnrecordedIntent(stripeData.id, 'claim-lost-before-insert');
        return claimLost(verdict, 'before-insert');
      }
    }
    // Mode boundary (migration 045): stripe_livemode is recorded from Stripe's OWN
    // livemode field, never inferred. Financial automation only acts on live rows.
    const recorded = await recordCheckoutAttempt(supabase, groupClaim.claim, {
      sellerId: listing.seller_id, amount: amountCents, buyerFee: buyerFeeCents, sellerFee: sellerFeeCents,
      total: totalCents, intentId: stripeData.id, livemode: stripeData.livemode ?? null,
    });
    if (recorded.kind === 'claim_lost') {
      // The claim was reclaimed while this request was recording: the row was not
      // written and this secret was never exposed. Withdraw the intent and refuse.
      await withdrawUnrecordedIntent(stripeData.id, 'claim-lost-at-record');
      logStage('checkout-record-refused', { pi_id: stripeData.id, reason: 'claim_lost' });
      return claimLost('lost', 'at-record');
    }
    const insertErr = recorded.kind === 'error' ? recorded.error : null;

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
          const verdict = await claimGuard.check();
          if (verdict !== 'held') return claimLost(verdict, 'before-race-recovered-secret');
          if (!await otherLiveAttemptsCleared(stripeData.id, 'before-race-recovered-secret')) {
            return checkoutBusy('checkout-refused-other-attempt', { stage: 'before-race-recovered-secret' });
          }
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
        await claimGuard.bound(stripeFetch(`/payment_intents/${stripeData.id}/cancel`, { method: 'POST' }), 'cancel after insert failure');
      } catch (cancelErr) {
        console.warn('PI cancel after DB-insert-fail:', cancelErr);
      }
      return new Response(
        JSON.stringify({ error: 'Failed to record payment. Please try again.' }),
        { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }
    logStage('db-insert-ok', { pi_id: stripeData.id, status: 'pending' });

    if (superseded) {
      // L1: the replacement row exists, so the cancel event Stripe emits now
      // sees a live sibling attempt. The replacement's secret is returned only
      // once the old intent is provably cancelled.
      // E-1: the claim must still be ours before touching the superseded intent;
      // otherwise withdraw the (never exposed) replacement exactly as on a refusal.
      const beforeCancel = await claimGuard.check();
      const oldCanceled = beforeCancel === 'held'
        && await cancelPaymentIntentBestEffort(superseded.stripe_payment_intent_id, 'reuse-rejected-amount-mismatch', claimGuard.bound);
      if (!oldCanceled) {
        // The old PI could not be cancelled (e.g. already processing) and may
        // still charge. Withdraw the replacement — its secret was never
        // returned — and ALWAYS retire its row, even if Stripe's cancel of it
        // fails: an unexposed secret can confirm nothing, but a `pending` row
        // would be reused (and its secret handed out) on the next request.
        await cancelPaymentIntentBestEffort(stripeData.id, 'withdraw-replacement', claimGuard.bound);
        const { error: withdrawErr } = await supabase
          .from('payments')
          .update({ status: 'failed' })
          .eq('stripe_payment_intent_id', stripeData.id)
          .eq('status', 'pending');
        if (withdrawErr) {
          await captureException(
            'create-payment-intent',
            new Error(`withdraw-replacement: row retire failed for ${stripeData.id}: ${withdrawErr.message}`),
          );
        }
        logStage('replacement-withdrawn', { pi_id: stripeData.id, superseded_pi: superseded.stripe_payment_intent_id, claim: beforeCancel });
        if (beforeCancel !== 'held') return claimLost(beforeCancel, 'before-cancel-superseded');
        return new Response(
          JSON.stringify({
            error: 'Price changed. Please review the updated total and try again.',
            server_total_cents: totalCents,
          }),
          { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
        );
      }
      const { error: retireErr } = await supabase
        .from('payments')
        .update({ status: 'failed' })
        .eq('id', superseded.id)
        .eq('status', 'pending');
      if (retireErr) {
        console.warn('Failed to retire amount-mismatched pending payment (continuing):', retireErr.message);
      }
    }

    {
      // E-1: the last word before a secret leaves this request. If the claim was
      // lost after the superseded intent was cancelled, the replacement is the
      // group's only live attempt and stays as it is; this request just does not
      // hand it out.
      const verdict = await claimGuard.check();
      if (verdict !== 'held') return claimLost(verdict, 'before-secret');
      if (!await otherLiveAttemptsCleared(stripeData.id, 'before-secret')) {
        return checkoutBusy('checkout-refused-other-attempt', { stage: 'before-secret' });
      }
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
    } finally {
      // 130: every exit after the claim — success, 400/409/500, or a throw — releases it.
      await releaseCheckout(supabase, checkoutClaim);
    }
    } finally {
      // 132: every exit after the group record — including the 130 claim's own refusals — releases it.
      await releaseCheckoutGroup(supabase, groupClaim.claim);
    }
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
