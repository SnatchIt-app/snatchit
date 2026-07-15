// =============================================================================
// enforce-transfer-expiry — Day 2 auto-expiry + Day 3 auto-release edge function
// =============================================================================
// PURPOSE: Cron-triggered function that runs TWO phases per invocation:
//
//   PHASE 1 — Expiry + Refund (Day 2):
//     1. Calls enforce_transfer_expiry() RPC to atomically expire pending
//        transfers past their 24h deadline
//     2. For each expired transfer, issues a full Stripe refund
//     3. Updates the payment record with refund details
//     4. Sends push notifications to buyer and seller
//
//   PHASE 2 — Risk-based payout decision (migration 039):
//     1. get_auto_release_candidates() returns due seller_sent transfers past
//        auto_release_at with all risk signals (risk scores refreshed inline)
//     2. _shared/payout-policy.ts classifies each: LOW → release,
//        MEDIUM → hold to a post-event safe point, HIGH → manual review
//     3. Releases claim the row via apply_auto_release() (guarded flip),
//        then create the Stripe Transfer (Idempotency-Key: payout_<id>)
//     4. Every decision is recorded in payout_decisions
//
//   PHASE 2b — Self-heal: pays auto_released rows whose Stripe Transfer never
//     completed (crashed run or admin release). Idempotency key makes retries safe.
//
// AUTH: Dedicated INTERNAL_CRON_SECRET (custom secret set via supabase secrets set).
//       The reserved SUPABASE_SERVICE_ROLE_KEY cannot be used for manual bearer-token
//       comparison because its runtime value (41 chars) differs from the JWT-format
//       key shown in the Dashboard (219 chars) under the newer signing-key system.
//
// IDEMPOTENCY — Phase 1 (3 layers):
//   Layer 1: RPC uses FOR UPDATE SKIP LOCKED — concurrent runs never
//            double-process the same row
//   Layer 2: Payment refund check — skip if status='refunded' or
//            stripe_refund_id IS NOT NULL
//   Layer 3: Stripe refund API — full refunds on the same payment_intent
//            return the existing refund (Stripe-level idempotency)
//
// IDEMPOTENCY — Phase 2 (3 layers):
//   Layer 1: RPC uses FOR UPDATE SKIP LOCKED + payout_released_at IS NULL
//   Layer 2: Edge function checks payout_released_at before Stripe call
//   Layer 3: Atomic UPDATE ... WHERE payout_released_at IS NULL after Stripe call
//
// ERROR HANDLING:
//   - One failed refund/payout does NOT block the batch
//   - Each transfer is processed independently with try/catch
//   - Phase 1 failure does NOT prevent Phase 2 from running
//   - All steps are logged for observability
//
// SCHEDULE: Called by pg_cron every 5 minutes
// =============================================================================

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetch } from '../_shared/stripe.ts';
import {
  classifyPayout,
  DEFAULT_POLICY,
  type PayoutCandidate,
  type PayoutPolicyConfig,
} from '../_shared/payout-policy.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const INTERNAL_CRON_SECRET = Deno.env.get('INTERNAL_CRON_SECRET')!;

// ── CORS origin whitelist ────────────────────────────────────────────────────
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

// ── Stripe helper ────────────────────────────────────────────────────────────
// Thin wrapper over shared stripeFetch (Stripe-Version pinned centrally).
async function stripePost(path: string, body: Record<string, string>) {
  return stripeFetch(path, { method: 'POST', body });
}

// ── Push notification helper ─────────────────────────────────────────────────
// Identical to stripe-webhook sendPush.
async function sendPush(userId: string, title: string, body: string, data?: Record<string, string>) {
  try {
    await fetch(`${SUPABASE_URL}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ user_id: userId, title, body, data }),
    });
  } catch (err) {
    console.error('enforce-transfer-expiry: sendPush failed:', err);
  }
}

// ── Main handler ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  // ── Auth: Accept INTERNAL_CRON_SECRET or SUPABASE_SERVICE_ROLE_KEY ──────
  // pg_cron sends the service_role_key via app.settings; the dedicated
  // INTERNAL_CRON_SECRET is accepted as an alternative for manual triggers.
  const authHeader = req.headers.get('Authorization') ?? '';
  const token = authHeader.startsWith('Bearer ')
    ? authHeader.slice('Bearer '.length)
    : '';

  function constantTimeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
      diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return diff === 0;
  }

  const matchesCronSecret = INTERNAL_CRON_SECRET && INTERNAL_CRON_SECRET.length > 0
    && constantTimeEqual(token, INTERNAL_CRON_SECRET);
  const matchesServiceRole = SUPABASE_SERVICE_ROLE_KEY && SUPABASE_SERVICE_ROLE_KEY.length > 0
    && constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY);

  if (!matchesCronSecret && !matchesServiceRole) {
    return new Response(
      JSON.stringify({ error: 'Unauthorized' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    );
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Accumulate counts across both phases
    let expiredCount = 0;
    let refundedCount = 0;
    let autoReleasedCount = 0;
    let errorCount = 0;

    // =====================================================================
    // PHASE 1 — Expiry + Refund (Day 2)
    // =====================================================================

    // ── Step 1: Call RPC to atomically expire pending transfers ───────────
    // The RPC:
    //   - Selects transfers WHERE status='pending' AND expires_at < now()
    //   - Locks them with FOR UPDATE SKIP LOCKED
    //   - Updates status='expired', expired_at=now()
    //   - Returns the affected rows
    const { data: expiredTransfers, error: expiryRpcErr } = await supabase
      .rpc('enforce_transfer_expiry');

    if (expiryRpcErr) {
      console.error('enforce-transfer-expiry: Phase 1 RPC failed:', expiryRpcErr);
      // Do NOT return — Phase 2 should still run
      errorCount++;
    } else if (expiredTransfers && expiredTransfers.length > 0) {
      expiredCount = expiredTransfers.length;
      console.log(`enforce-transfer-expiry: Phase 1 found ${expiredCount} expired transfer(s)`);

      // ── Step 2: For each expired transfer, issue Stripe refund ────────
      for (const t of expiredTransfers) {
        try {
          // ── 2a. Look up the payment ────────────────────────────────────
          const { data: payment, error: payErr } = await supabase
            .from('payments')
            .select('id, stripe_payment_intent_id, status, stripe_refund_id')
            .eq('id', t.payment_id)
            .single();

          if (payErr || !payment) {
            console.error('enforce-transfer-expiry: payment lookup failed:', {
              transfer_id: t.transfer_id,
              payment_id:  t.payment_id,
              error:       payErr,
            });
            errorCount++;
            continue;
          }

          // ── 2b. Idempotency: skip if already refunded ──────────────────
          if (payment.status === 'refunded' || payment.stripe_refund_id) {
            console.log('enforce-transfer-expiry: payment already refunded, skipping:', {
              transfer_id:      t.transfer_id,
              payment_id:       t.payment_id,
              stripe_refund_id: payment.stripe_refund_id,
            });
            refundedCount++;
            continue;
          }

          // ── 2c. Validate stripe_payment_intent_id exists ───────────────
          if (!payment.stripe_payment_intent_id) {
            console.error('enforce-transfer-expiry: no stripe_payment_intent_id:', {
              transfer_id: t.transfer_id,
              payment_id:  t.payment_id,
            });
            errorCount++;
            continue;
          }

          // ── 2d. Issue full refund via Stripe ───────────────────────────
          // POST /v1/refunds with payment_intent (no amount = full refund).
          // Stripe's own idempotency: if a full refund already exists for this
          // payment_intent, Stripe returns the existing refund object.
          console.log('enforce-transfer-expiry: issuing Stripe refund:', {
            transfer_id:             t.transfer_id,
            payment_id:              t.payment_id,
            stripe_payment_intent_id: payment.stripe_payment_intent_id,
          });

          const refund = await stripePost('/refunds', {
            'payment_intent':          payment.stripe_payment_intent_id,
            'metadata[transfer_id]':   t.transfer_id,
            'metadata[reason]':        'transfer_expired',
            'metadata[source]':        'enforce-transfer-expiry',
          });

          // ── 2e. Update payment record ──────────────────────────────────
          const { error: updateErr } = await supabase
            .from('payments')
            .update({
              status:          'refunded',
              refunded_at:     new Date().toISOString(),
              stripe_refund_id: refund.id,
            })
            .eq('id', t.payment_id);

          if (updateErr) {
            // Refund was issued via Stripe but DB update failed.
            // Log the Stripe refund ID for manual reconciliation.
            console.error('enforce-transfer-expiry: payment update failed after Stripe refund:', {
              transfer_id:      t.transfer_id,
              payment_id:       t.payment_id,
              stripe_refund_id: refund.id,
              error:            updateErr,
            });
            // Still count as refunded — money has been returned to buyer
          }

          refundedCount++;

          // ── 2f. Send push notifications ────────────────────────────────
          // Look up listing name for human-readable notification text
          const { data: listing } = await supabase
            .from('listings')
            .select('event_name')
            .eq('id', t.listing_id)
            .maybeSingle();

          const listingTitle = listing?.event_name || 'your listing';

          // Notify buyer: refund processed
          sendPush(
            t.buyer_id,
            'Refund Processed',
            `The seller didn't send the ticket for ${listingTitle} in time. Your full refund has been issued.`,
            { listingId: t.listing_id, type: 'transfer_expired_refund' },
          );

          // Notify seller: transfer expired
          sendPush(
            t.seller_id,
            'Transfer Expired',
            `You didn't send the ticket for ${listingTitle} in time. The buyer has been refunded.`,
            { listingId: t.listing_id, type: 'transfer_expired_seller' },
          );

          console.log('enforce-transfer-expiry: refund complete:', {
            transfer_id:      t.transfer_id,
            payment_id:       t.payment_id,
            stripe_refund_id: refund.id,
            buyer_id:         t.buyer_id,
            seller_id:        t.seller_id,
          });

        } catch (err) {
          // ── Error isolation: one failure must NOT block the batch ───────
          // Phase 1 = expiry refund (real money). Capture every failure.
          await captureException('enforce-transfer-expiry:phase1-refund', err, {
            transfer_id: t.transfer_id,
            payment_id:  t.payment_id,
          });
          errorCount++;
          // Continue to next transfer
        }
      }
    } else {
      console.log('enforce-transfer-expiry: Phase 1 — no expired transfers found');
    }

    // =====================================================================
    // PHASE 2 — Risk-based payout decision (replaces the blanket 72h release)
    // =====================================================================
    // Buyer silence alone no longer releases every transaction. Each due
    // candidate (seller_sent, past auto_release_at, undisputed, not held,
    // not frozen for manual review) is classified by the deterministic
    // policy in _shared/payout-policy.ts:
    //   LOW    → apply_auto_release() claims the row, then the Stripe
    //            Transfer is created (same money path as before).
    //   MEDIUM → apply_payout_hold() parks it until a post-event safe point.
    //   HIGH   → apply_manual_review() freezes it for an operator.
    // Every decision is recorded in payout_decisions.
    //
    // Disputed transfers are excluded twice: the candidate query requires
    // status='seller_sent', and apply_auto_release() re-checks it under lock.
    // =====================================================================

    let heldCount = 0;
    let manualReviewCount = 0;

    // Load ops-tunable thresholds; fall back to code defaults if unreadable.
    let policy: PayoutPolicyConfig = DEFAULT_POLICY;
    {
      const { data: policyRow } = await supabase
        .from('payout_policy').select('*').eq('id', 1).maybeSingle();
      if (policyRow) policy = policyRow as unknown as PayoutPolicyConfig;
    }

    const logDecision = async (
      c: PayoutCandidate,
      decision: { action: string; tier: string; reasons: string[]; hold_until: string | null },
    ) => {
      const { error } = await supabase.from('payout_decisions').insert({
        transfer_id: c.transfer_id,
        payment_id: c.payment_id,
        seller_id: c.seller_id,
        buyer_id: c.buyer_id,
        risk_tier: decision.tier,
        decision: decision.action,
        reason_codes: decision.reasons,
        evidence: {
          base_cents: c.base_cents,
          has_evidence: c.has_evidence,
          buyer_viewed: c.buyer_viewed,
          ticket_platform: c.ticket_platform,
          proof_status: c.proof_status,
          risk_tier: c.risk_tier,
          account_age_days: c.account_age_days,
          total_completed: c.total_completed,
          total_disputes: c.total_disputes,
          total_dispute_losses: c.total_dispute_losses,
          stripe_onboarding_complete: c.stripe_onboarding_complete,
        },
        buyer_confirmed: false,
        dispute_open: false,
        event_date: c.event_date,
        hold_until: decision.hold_until,
        actor: 'cron:enforce-transfer-expiry',
      });
      if (error) console.error('enforce-transfer-expiry: payout_decisions insert failed:', error);
    };

    // Money mover shared by Phase 2 (fresh releases) and Phase 2b (stuck
    // auto_released rows). The Stripe Idempotency-Key is keyed on the
    // transfer id, so even a cron/direct race that reaches Stripe twice
    // yields ONE Stripe Transfer.
    const payReleasedTransfer = async (t: {
      transfer_id: string; payment_id: string; listing_id: string;
      seller_id: string; buyer_id: string;
    }): Promise<boolean> => {
      const { data: sellerProfile } = await supabase
        .from('profiles').select('stripe_connect_id').eq('id', t.seller_id).single();
      if (!sellerProfile?.stripe_connect_id) {
        console.error('enforce-transfer-expiry: seller has no Connect account:', t.transfer_id);
        return false;
      }

      const { data: payment } = await supabase
        .from('payments').select('amount, seller_fee').eq('id', t.payment_id).single();
      if (!payment) {
        console.error('enforce-transfer-expiry: payment lookup failed:', t.transfer_id);
        return false;
      }

      // Final pre-payment recheck, as close to the Stripe call as possible:
      //   • already paid (stripe_transfer_id set) → success, nothing to do
      //   • disputed/reversed since the claim (chargeback webhook can flip an
      //     unpaid auto_released row to 'disputed') → ABORT, payout frozen
      const { data: transferCheck } = await supabase
        .from('transfers')
        .select('stripe_transfer_id, status, disputed_at')
        .eq('id', t.transfer_id)
        .single();
      if (transferCheck?.stripe_transfer_id) return true;   // already paid
      if (
        !transferCheck ||
        transferCheck.disputed_at !== null ||
        !['auto_released', 'buyer_confirmed'].includes(transferCheck.status as string)
      ) {
        console.warn('enforce-transfer-expiry: payout aborted — transfer no longer releasable:', {
          transfer_id: t.transfer_id,
          status: transferCheck?.status,
          disputed_at: transferCheck?.disputed_at,
        });
        return false;
      }

      // 10/10 fee model: seller net = base amount − seller fee (both cents).
      const sellerNetCents = (payment.amount as number) - ((payment.seller_fee as number) ?? 0);

      const stripeTransfer = await stripeFetch<{ id: string }>('/transfers', {
        method: 'POST',
        idempotencyKey: `payout_${t.transfer_id}`,
        body: {
          'amount': String(sellerNetCents),
          'currency': 'usd',
          'destination': sellerProfile.stripe_connect_id,
          'metadata[transfer_id]': t.transfer_id,
          'metadata[payment_id]': t.payment_id,
          'metadata[seller_id]': t.seller_id,
          'metadata[source]': 'enforce-transfer-expiry-auto-release',
        },
      });

      // Atomic write AFTER money moved; WHERE stripe_transfer_id IS NULL
      // means overlapping runs record exactly one payout.
      const { data: updated } = await supabase
        .from('transfers')
        .update({
          payout_released_at: new Date().toISOString(),
          stripe_transfer_id: stripeTransfer.id,
        })
        .eq('id', t.transfer_id)
        .is('stripe_transfer_id', null)
        .select('id')
        .maybeSingle();
      if (!updated) {
        console.warn('enforce-transfer-expiry: payout raced (idempotency key prevented dupe):', t.transfer_id);
      }

      const { data: listing } = await supabase
        .from('listings').select('event_name').eq('id', t.listing_id).maybeSingle();
      const listingTitle = listing?.event_name || 'your listing';

      sendPush(
        t.seller_id,
        'Payout released',
        `Your payout for ${listingTitle} has been released.`,
        { listingId: t.listing_id, type: 'auto_release_seller' },
      );
      sendPush(
        t.buyer_id,
        'Order complete',
        `Your order for ${listingTitle} is complete. If anything is wrong with your tickets, contact support.`,
        { listingId: t.listing_id, type: 'auto_release_buyer' },
      );
      return true;
    };

    const { data: candidates, error: candidatesErr } = await supabase
      .rpc('get_auto_release_candidates');

    if (candidatesErr) {
      console.error('enforce-transfer-expiry: Phase 2 candidates RPC failed:', candidatesErr);
      errorCount++;
    } else if (candidates && candidates.length > 0) {
      console.log(`enforce-transfer-expiry: Phase 2 evaluating ${candidates.length} candidate(s)`);
      const nowIso = new Date().toISOString();

      for (const c of candidates as PayoutCandidate[]) {
        try {
          const decision = classifyPayout(c, policy, nowIso);

          if (decision.action === 'release') {
            // Claim first (guarded flip under lock), pay only if we won it.
            const { data: claimed, error: claimErr } = await supabase
              .rpc('apply_auto_release', { p_transfer_id: c.transfer_id });
            if (claimErr) { console.error('apply_auto_release failed:', claimErr); errorCount++; continue; }
            if (!claimed) continue;               // raced or state changed — skip
            await logDecision(c, decision);
            if (await payReleasedTransfer(c)) autoReleasedCount++;
            else errorCount++;
          } else if (decision.action === 'hold') {
            // Only log the first time this hold is set (idempotent update).
            const alreadyHeld = c.payout_hold_until !== null &&
              new Date(c.payout_hold_until).getTime() >= new Date(decision.hold_until!).getTime();
            const { data: heldOk } = await supabase.rpc('apply_payout_hold', {
              p_transfer_id: c.transfer_id,
              p_hold_until: decision.hold_until,
              p_tier: decision.tier,
              p_reasons: decision.reasons,
            });
            if (heldOk && !alreadyHeld) await logDecision(c, decision);
            heldCount++;
          } else {
            // manual_review — freeze; log only on the first transition.
            const { data: frozen } = await supabase.rpc('apply_manual_review', {
              p_transfer_id: c.transfer_id,
              p_tier: decision.tier,
              p_reasons: decision.reasons,
            });
            if (frozen) await logDecision(c, decision);
            manualReviewCount++;
          }
        } catch (err) {
          await captureException('enforce-transfer-expiry:phase2-decision', err, {
            transfer_id: c.transfer_id,
          });
          errorCount++;
        }
      }
    } else {
      console.log('enforce-transfer-expiry: Phase 2 — no payout candidates due');
    }

    // =====================================================================
    // PHASE 2b — Pay stuck releases (self-heal)
    // =====================================================================
    // Two stuck shapes, both safe to retry because the Stripe Idempotency-Key
    // (payout_<transfer_id>) makes the transfer call replay-safe:
    //   a) status='auto_released' rows (claimed by this function, an admin
    //      release, or a crashed earlier run) never paid.
    //   b) status='buyer_confirmed' rows where confirm-and-release created
    //      the Stripe Transfer or crashed before persisting it — swept only
    //      after a 15-minute quiet period so we never race the in-flight
    //      buyer request.
    try {
      const staleIso = new Date(Date.now() - 15 * 60_000).toISOString();
      const { data: stuck } = await supabase
        .from('transfers')
        .select('id, payment_id, listing_id, seller_id, buyer_id, status, buyer_confirmed_at')
        .in('status', ['auto_released', 'buyer_confirmed'])
        .is('stripe_transfer_id', null)
        .is('payout_released_at', null)
        .is('disputed_at', null)
        .limit(20)
        .then((res) => ({
          ...res,
          data: (res.data ?? []).filter((r: { status: string; buyer_confirmed_at: string | null }) =>
            r.status === 'auto_released' ||
            (r.buyer_confirmed_at !== null && r.buyer_confirmed_at < staleIso)),
        }));

      for (const s of stuck ?? []) {
        try {
          const ok = await payReleasedTransfer({
            transfer_id: s.id,
            payment_id: s.payment_id,
            listing_id: s.listing_id,
            seller_id: s.seller_id,
            buyer_id: s.buyer_id,
          });
          if (ok) autoReleasedCount++;
          else errorCount++;
        } catch (err) {
          await captureException('enforce-transfer-expiry:phase2b-stuck-payout', err, { transfer_id: s.id });
          errorCount++;
        }
      }
    } catch (err) {
      console.error('enforce-transfer-expiry: Phase 2b sweep failed (non-fatal):', err);
    }

    // =====================================================================
    // PHASE 3 — Progress reminders (idempotent, one per transfer per type)
    // =====================================================================
    // Additive and fully isolated: any failure here is swallowed so it can
    // never affect the expiry/auto-release phases above. No new sweep window
    // is introduced — both reminders fire inside the EXISTING expiry (24h) and
    // auto-release (72h) windows, so they cannot extend a transfer's lifetime.
    let remindedSeller = 0;
    let remindedBuyer = 0;
    try {
      const nowMs = Date.now();
      const in6h  = new Date(nowMs + 6 * 60 * 60 * 1000).toISOString();
      const in24h = new Date(nowMs + 24 * 60 * 60 * 1000).toISOString();
      const nowIso = new Date(nowMs).toISOString();

      // claim() inserts the idempotency row; returns true only if WE inserted it.
      const claim = async (transferId: string, eventType: string): Promise<boolean> => {
        const { data, error } = await supabase
          .from('transfer_notifications')
          .upsert({ transfer_id: transferId, event_type: eventType },
                  { onConflict: 'transfer_id,event_type', ignoreDuplicates: true })
          .select();
        if (error) { console.error('enforce-transfer-expiry: reminder claim failed:', eventType, error); return false; }
        return Array.isArray(data) && data.length > 0;
      };

      // Seller reminder — pending transfers approaching the 24h send deadline.
      const { data: sellerDue } = await supabase
        .from('transfers')
        .select('id, seller_id, listing:listings!listing_id(event_name)')
        .eq('status', 'pending')
        .gt('expires_at', nowIso)
        .lt('expires_at', in6h);
      for (const t of (sellerDue ?? []) as Array<{ id: string; seller_id: string; listing?: { event_name?: string } }>) {
        if (await claim(t.id, 'transfer_reminder_seller')) {
          await sendPush(
            t.seller_id,
            'Reminder: send the tickets to complete your sale',
            `Your sale of "${t.listing?.event_name ?? 'your order'}" is waiting — send the tickets before it expires.`,
            { type: 'seller_action', transferId: t.id },
          );
          remindedSeller++;
        }
      }

      // Buyer reminder — seller_sent transfers approaching the 72h auto-release.
      const { data: buyerDue } = await supabase
        .from('transfers')
        .select('id, buyer_id, listing:listings!listing_id(event_name)')
        .eq('status', 'seller_sent')
        .not('auto_release_at', 'is', null)
        .gt('auto_release_at', nowIso)
        .lt('auto_release_at', in24h);
      for (const t of (buyerDue ?? []) as Array<{ id: string; buyer_id: string; listing?: { event_name?: string } }>) {
        if (await claim(t.id, 'transfer_reminder_buyer')) {
          await sendPush(
            t.buyer_id,
            'Reminder: confirm your tickets',
            `Confirm your "${t.listing?.event_name ?? 'order'}" tickets — or open a dispute if something is wrong.`,
            { type: 'buyer_confirm', transferId: t.id },
          );
          remindedBuyer++;
        }
      }
    } catch (remErr) {
      console.error('enforce-transfer-expiry: Phase 3 reminders failed (non-fatal):', remErr);
    }

    // =====================================================================
    // COMBINED SUMMARY
    // =====================================================================
    const summary = {
      expired:       expiredCount,
      refunded:      refundedCount,
      auto_released: autoReleasedCount,
      held:          heldCount,
      manual_review: manualReviewCount,
      reminded_seller: remindedSeller,
      reminded_buyer:  remindedBuyer,
      errors:        errorCount,
      timestamp:     new Date().toISOString(),
    };

    console.log('enforce-transfer-expiry: run complete:', summary);

    return new Response(
      JSON.stringify(summary),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    await captureException('enforce-transfer-expiry', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
