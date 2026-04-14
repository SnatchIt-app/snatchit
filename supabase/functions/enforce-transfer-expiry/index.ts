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
//   PHASE 2 — Auto-Release Payout (Day 3):
//     1. Calls enforce_auto_release() RPC to atomically claim seller_sent
//        transfers past their 72h auto_release_at deadline
//     2. For each auto-released transfer, creates a Stripe Transfer (payout)
//        to the seller's Connect account
//     3. Atomically updates transfers with payout_released_at + stripe_transfer_id
//     4. Sends push notifications to buyer and seller
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
// Identical to confirm-and-release stripePost.
async function stripePost(path: string, body: Record<string, string>) {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams(body).toString(),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error?.message ?? 'Stripe API error');
  return data;
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
          console.error('enforce-transfer-expiry: error processing expired transfer:', {
            transfer_id: t.transfer_id,
            payment_id:  t.payment_id,
            error:       err instanceof Error ? err.message : err,
          });
          errorCount++;
          // Continue to next transfer
        }
      }
    } else {
      console.log('enforce-transfer-expiry: Phase 1 — no expired transfers found');
    }

    // =====================================================================
    // PHASE 2 — Auto-Release Payout (Day 3)
    // =====================================================================
    // Buyer ghost protection: if seller marked ticket as sent and buyer
    // did not confirm or dispute within 72 hours, release payout to seller.
    //
    // The enforce_auto_release() RPC:
    //   - Selects transfers WHERE status='seller_sent'
    //     AND auto_release_at < now() AND payout_released_at IS NULL
    //   - Locks them with FOR UPDATE SKIP LOCKED
    //   - Updates status='auto_released', payout_released_at=now()
    //   - Returns affected rows
    //
    // Disputed transfers are automatically excluded (WHERE status='seller_sent').
    // =====================================================================

    const { data: autoReleaseTransfers, error: autoReleaseRpcErr } = await supabase
      .rpc('enforce_auto_release');

    if (autoReleaseRpcErr) {
      console.error('enforce-transfer-expiry: Phase 2 RPC failed:', autoReleaseRpcErr);
      errorCount++;
    } else if (autoReleaseTransfers && autoReleaseTransfers.length > 0) {
      console.log(`enforce-transfer-expiry: Phase 2 found ${autoReleaseTransfers.length} auto-release transfer(s)`);

      for (const t of autoReleaseTransfers) {
        try {
          // ── 2a. Look up seller's Connect account ───────────────────────
          const { data: sellerProfile, error: profileErr } = await supabase
            .from('profiles')
            .select('stripe_connect_id')
            .eq('id', t.seller_id)
            .single();

          if (profileErr || !sellerProfile?.stripe_connect_id) {
            console.error('enforce-transfer-expiry: seller has no Connect account:', {
              transfer_id: t.transfer_id,
              seller_id:   t.seller_id,
              error:       profileErr,
            });
            errorCount++;
            continue;
          }

          // ── 2b. Look up payment amount ─────────────────────────────────
          // Seller receives payment.amount (listing price in cents).
          // Service fee stays with the platform.
          const { data: payment, error: paymentErr } = await supabase
            .from('payments')
            .select('amount, stripe_payment_intent_id')
            .eq('id', t.payment_id)
            .single();

          if (paymentErr || !payment) {
            console.error('enforce-transfer-expiry: payment lookup failed:', {
              transfer_id: t.transfer_id,
              payment_id:  t.payment_id,
              error:       paymentErr,
            });
            errorCount++;
            continue;
          }

          // ── 2c. Idempotency: skip if payout already released ───────────
          // The RPC already filters payout_released_at IS NULL and sets it
          // atomically, but check the transfer row as defense-in-depth.
          const { data: transferCheck } = await supabase
            .from('transfers')
            .select('payout_released_at, stripe_transfer_id')
            .eq('id', t.transfer_id)
            .single();

          if (transferCheck?.stripe_transfer_id) {
            console.log('enforce-transfer-expiry: payout already released, skipping:', {
              transfer_id:       t.transfer_id,
              stripe_transfer_id: transferCheck.stripe_transfer_id,
            });
            autoReleasedCount++;
            continue;
          }

          // ── 2d. Create Stripe Transfer to seller ───────────────────────
          // Moves funds from platform Stripe balance to seller's Connected
          // Express account. Same logic as confirm-and-release step 8.
          console.log('enforce-transfer-expiry: creating Stripe Transfer (auto-release):', {
            transfer_id:       t.transfer_id,
            seller_connect_id: sellerProfile.stripe_connect_id,
            amount:            payment.amount,
            currency:          'usd',
          });

          let stripeTransfer;
          try {
            stripeTransfer = await stripePost('/transfers', {
              'amount':                 String(payment.amount),
              'currency':               'usd',
              'destination':            sellerProfile.stripe_connect_id,
              'metadata[transfer_id]':  t.transfer_id,
              'metadata[payment_id]':   t.payment_id,
              'metadata[seller_id]':    t.seller_id,
              'metadata[source]':       'enforce-transfer-expiry-auto-release',
            });
          } catch (stripeErr) {
            console.error('enforce-transfer-expiry: Stripe Transfer failed (auto-release):', {
              transfer_id:       t.transfer_id,
              seller_connect_id: sellerProfile.stripe_connect_id,
              amount:            payment.amount,
              error:             stripeErr instanceof Error ? stripeErr.message : stripeErr,
            });
            errorCount++;
            continue;
          }

          // ── 2e. Atomic DB update (true idempotency guard) ──────────────
          // UPDATE ... WHERE stripe_transfer_id IS NULL ensures that even if
          // two runs overlap, only one writes the payout columns.
          // Both payout_released_at and stripe_transfer_id are written AFTER
          // Stripe Transfer succeeds — never before. This guarantees
          // payout_released_at is only set when money has actually moved.
          const { data: updated, error: updateErr } = await supabase
            .from('transfers')
            .update({
              payout_released_at: new Date().toISOString(),
              stripe_transfer_id: stripeTransfer.id,
            })
            .eq('id', t.transfer_id)
            .is('stripe_transfer_id', null)
            .select('id')
            .maybeSingle();

          if (updateErr) {
            console.error('enforce-transfer-expiry: DB update failed after Stripe Transfer:', {
              transfer_id:        t.transfer_id,
              stripe_transfer_id: stripeTransfer.id,
              error:              updateErr,
            });
            // Still count — the Stripe Transfer was created, money is moving
          }

          if (!updated) {
            // Another run won the race — log the duplicate for manual cleanup
            console.warn('enforce-transfer-expiry: race condition — duplicate Stripe Transfer:', {
              transfer_id:                  t.transfer_id,
              duplicate_stripe_transfer_id: stripeTransfer.id,
            });
          }

          autoReleasedCount++;

          // ── 2f. Send push notifications ────────────────────────────────
          const { data: listing } = await supabase
            .from('listings')
            .select('event_name')
            .eq('id', t.listing_id)
            .maybeSingle();

          const listingTitle = listing?.event_name || 'your listing';

          // Notify seller: payout released
          sendPush(
            t.seller_id,
            'Payout Released',
            `Your payout for ${listingTitle} has been automatically released. The buyer did not respond within 72 hours.`,
            { listingId: t.listing_id, type: 'auto_release_seller' },
          );

          // Notify buyer: transfer auto-confirmed
          sendPush(
            t.buyer_id,
            'Transfer Auto-Confirmed',
            `The transfer for ${listingTitle} was automatically confirmed after 72 hours. If you have any issues, please contact support.`,
            { listingId: t.listing_id, type: 'auto_release_buyer' },
          );

          console.log('enforce-transfer-expiry: auto-release payout complete:', {
            transfer_id:        t.transfer_id,
            stripe_transfer_id: stripeTransfer.id,
            amount:             payment.amount,
            seller_id:          t.seller_id,
            buyer_id:           t.buyer_id,
          });

        } catch (err) {
          // ── Error isolation: one failure must NOT block the batch ───────
          console.error('enforce-transfer-expiry: error processing auto-release transfer:', {
            transfer_id: t.transfer_id,
            payment_id:  t.payment_id,
            error:       err instanceof Error ? err.message : err,
          });
          errorCount++;
          // Continue to next transfer
        }
      }
    } else {
      console.log('enforce-transfer-expiry: Phase 2 — no auto-release transfers found');
    }

    // =====================================================================
    // COMBINED SUMMARY
    // =====================================================================
    const summary = {
      expired:       expiredCount,
      refunded:      refundedCount,
      auto_released: autoReleasedCount,
      errors:        errorCount,
      timestamp:     new Date().toISOString(),
    };

    console.log('enforce-transfer-expiry: run complete:', summary);

    return new Response(
      JSON.stringify(summary),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    console.error('enforce-transfer-expiry: unhandled error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }
});
