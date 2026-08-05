// READY TO DEPLOY
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
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

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  let result = 0;
  for (let i = 0; i < aBytes.length; i++) {
    result |= aBytes[i] ^ bBytes[i];
  }
  return result === 0;
}

// Replay-attack window for Stripe webhooks. Matches the default tolerance
// used by Stripe's official server-side libraries. If `t` in the signature
// header is older than this many seconds vs. our wall clock, we reject.
const STRIPE_WEBHOOK_TOLERANCE_SECONDS = 300;

async function verifyStripeSignature(rawBody: string, sigHeader: string): Promise<boolean> {
  // Collect EVERY v1 entry: during a signing-secret rotation Stripe signs
  // with both old and new secrets and sends multiple v1= values. Keeping
  // only one (the old reduce-into-a-map bug) rejected valid deliveries for
  // the whole rotation window. Accept if ANY v1 matches.
  const parts: Record<string, string> = {};
  const v1Signatures: string[] = [];
  for (const part of sigHeader.split(',')) {
    const [key, val] = part.split('=');
    if (key === 'v1' && val) v1Signatures.push(val);
    else if (key && val) parts[key] = val;
  }

  const timestamp = parts['t'];
  if (!timestamp || v1Signatures.length === 0) return false;

  // ── Replay protection ──────────────────────────────────────────────────
  // Stripe sends `t` as a Unix epoch in seconds. Reject anything older than
  // our tolerance, OR anything skewed too far into the future (clock issues
  // / forged timestamps).
  const tsSeconds = parseInt(timestamp, 10);
  if (!Number.isFinite(tsSeconds)) return false;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const delta      = Math.abs(nowSeconds - tsSeconds);
  if (delta > STRIPE_WEBHOOK_TOLERANCE_SECONDS) {
    console.warn('Webhook: signature timestamp outside tolerance', {
      delta_seconds: delta,
      tolerance:     STRIPE_WEBHOOK_TOLERANCE_SECONDS,
    });
    return false;
  }

  const payload = `${timestamp}.${rawBody}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(STRIPE_WEBHOOK_SECRET),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, encoder.encode(payload));
  const expected = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return v1Signatures.some((candidate) => timingSafeEqual(expected, candidate));
}

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
    console.error('Webhook: sendPush failed:', err);
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...getResponseHeaders(req) } });
  }

  try {
    const rawBody = await req.text();
    const sigHeader = req.headers.get('stripe-signature');

    if (!sigHeader || !(await verifyStripeSignature(rawBody, sigHeader))) {
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
      );
    }

    const event = JSON.parse(rawBody);
    const paymentIntent = event.data.object;
    const piId = paymentIntent.id;
    const metadata = paymentIntent.metadata ?? {};

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ─── Idempotency gate (migration 025) ────────────────────────────────
    // INSERT-with-ON-CONFLICT against stripe_webhook_events. If the
    // event_id is already present, we short-circuit with HTTP 200 and
    // skip every side effect. This is the SINGLE source of truth for
    // dedup; per-event logic below no longer needs its own replay guards
    // (the existing .neq('status','succeeded') claim semantics in
    // payment_intent.succeeded remain as defense in depth).
    {
      const { error: dedupErr } = await supabase
        .from('stripe_webhook_events')
        .insert({ event_id: event.id, event_type: event.type });
      if (dedupErr) {
        // 23505 = unique_violation = we've already processed this event
        if (dedupErr.code === '23505') {
          console.log('Webhook: duplicate event, skipping', {
            event_id: event.id, event_type: event.type,
          });
          return new Response(
            JSON.stringify({ received: true, duplicate: true }),
            { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
          );
        }
        // Any other DB error: log and CONTINUE. Failing-closed at the
        // dedup gate would force Stripe to retry until they give up.
        // Better to risk a duplicate (the per-event handlers below are
        // also idempotent at the row level) than to leak retries.
        console.error('Webhook: dedup insert failed (continuing):', dedupErr);
      }
    }

    // Helper to mark this event processed at end-of-handler (or to record
    // a partial-failure last_error for ops to investigate).
    async function markProcessed(opts: { error?: string } = {}) {
      const { error: markErr } = await supabase
        .from('stripe_webhook_events')
        .update({
          processed:    !opts.error,
          processed_at: new Date().toISOString(),
          last_error:   opts.error ?? null,
        })
        .eq('event_id', event.id);
      if (markErr) console.warn('Webhook: markProcessed failed:', markErr.message);
    }

    if (event.type === 'payment_intent.succeeded') {
      // FIX: Use .neq('status', 'succeeded') so this UPDATE is a "claim" operation.
      // If the payment is already 'succeeded' (replay or race with confirm-payment),
      // the UPDATE matches 0 rows and maybeSingle() returns null. We exit early,
      // skipping the RPC call, transfer insert, Stripe payout, and push notifications.
      // This makes the entire handler idempotent at the DB level.
      const { data: payment, error: lookupErr } = await supabase
        .from('payments')
        .update({ status: 'succeeded', paid_at: new Date().toISOString() })
        .eq('stripe_payment_intent_id', piId)
        .neq('status', 'succeeded')          // FIX: only claim if not yet processed
        .select('id, listing_id, amount, buyer_fee, seller_fee')
        .maybeSingle();                        // FIX: was .single() — returns null instead of error when 0 rows

      if (lookupErr) {
        console.error('Webhook: payment update error', piId, lookupErr);
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        });
      }

      if (!payment) {
        // Payment already processed (confirm-payment won the race) or not found.
        // The listing RPC and push notifications were already handled by the
        // checkout flow, so we skip those. BUT we must still ensure a transfer
        // row exists — the checkout flow does not create one.
        console.log('Webhook: payment already processed, checking transfer row', piId);

        // Look up the existing payment row to get its id for the transfer insert.
        const { data: existingPayment } = await supabase
          .from('payments')
          .select('id')
          .eq('stripe_payment_intent_id', piId)
          .maybeSingle();

        if (!existingPayment) {
          // Payment truly not found — nothing to do.
          console.log('Webhook: payment not found at all, skipping', piId);
          return new Response(JSON.stringify({ received: true }), {
            status: 200,
            headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
          });
        }

        // Check whether a transfer row already exists for this payment.
        const { data: existingTransfer } = await supabase
          .from('transfers')
          .select('id')
          .eq('payment_id', existingPayment.id)
          .maybeSingle();

        if (existingTransfer) {
          // Transfer already exists — fully idempotent exit.
          console.log('Webhook: transfer already exists, nothing to do', {
            payment_id: existingPayment.id,
            transfer_id: existingTransfer.id,
          });
          return new Response(JSON.stringify({ received: true }), {
            status: 200,
            headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
          });
        }

        // Transfer row is missing — create it now.
        // The listing is already sold (checkout called mark_listing_sold /
        // complete_auction_payment directly). We only need the transfer row.
        const { data: fallbackListing } = await supabase
          .from('listings')
          .select('transfer_method')
          .eq('id', metadata.listing_id)
          .maybeSingle();

        const fallbackExpiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

        const { error: fallbackTransferErr } = await supabase.from('transfers').insert({
          listing_id:       metadata.listing_id,
          payment_id:       existingPayment.id,
          seller_id:        metadata.seller_id,
          buyer_id:         metadata.buyer_id,
          transfer_method:  fallbackListing?.transfer_method ?? 'mobile_transfer',
          status:           'pending',
          expires_at:       fallbackExpiresAt,
        });

        if (fallbackTransferErr) {
          // Unique constraint violation = another webhook replay already created it.
          // Any other error is worth logging for investigation.
          console.error('Webhook: fallback transfer insert failed:', {
            payment_id:  existingPayment.id,
            listing_id:  metadata.listing_id,
            error:       fallbackTransferErr,
          });
        } else {
          console.log('Webhook: fallback transfer row created', {
            payment_id: existingPayment.id,
            listing_id: metadata.listing_id,
            seller_id:  metadata.seller_id,
            buyer_id:   metadata.buyer_id,
          });
        }

        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        });
      }

      let rpcName: string;
      let rpcParams: Record<string, string>;

      if (metadata.mode === 'buy_now') {
        rpcName = 'mark_listing_sold';
        rpcParams = {
          p_listing_id: metadata.listing_id,
          p_user_id:    metadata.buyer_id,
        };
      } else if (metadata.mode === 'auction') {
        rpcName = 'complete_auction_payment';
        rpcParams = {
          p_listing_id: metadata.listing_id,
          p_user_id:    metadata.buyer_id,
        };
      } else {
        console.error('Webhook: unknown mode in metadata', metadata.mode, piId);
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        });
      }

      console.log('Webhook: calling RPC', {
        rpc_name:   rpcName,
        listing_id: metadata.listing_id,
        buyer_id:   metadata.buyer_id,
        payment_id: payment.id,
      });

      const { error: rpcErr } = await supabase.rpc(rpcName, rpcParams);
      if (rpcErr) {
        console.error('Webhook RPC failed:', {
          listing_id: metadata.listing_id,
          payment_id: payment.id,
          rpc_name:   rpcName,
          error:      rpcErr,
        });
      } else {
        console.log('Webhook RPC succeeded:', { rpc_name: rpcName, listing_id: metadata.listing_id });
      }

      // Create transfer record.
      // FIX: The UNIQUE constraints on transfers.payment_id and transfers.listing_id
      // (added in migration 003) will reject any duplicate insert at the DB level.
      // The existing error handler logs and continues, which is correct — a constraint
      // violation on replay is expected behavior, not an application error.
      const { data: listing } = await supabase
        .from('listings')
        .select('event_name, transfer_method')
        .eq('id', metadata.listing_id)
        .single();

      const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

      const { data: newTransfer, error: transferErr } = await supabase.from('transfers').insert({
        listing_id:       metadata.listing_id,
        payment_id:       payment.id,
        seller_id:        metadata.seller_id,
        buyer_id:         metadata.buyer_id,
        transfer_method:  listing?.transfer_method ?? 'mobile_transfer',
        status:           'pending',
        expires_at:       expiresAt,
      }).select('id').single();

      if (transferErr) {
        // On replay: this will be a unique-constraint violation — expected and safe.
        // On first run: any other error is worth investigating.
        console.error('Webhook: transfer insert failed:', {
          listing_id: metadata.listing_id,
          payment_id: payment.id,
          error:      transferErr,
        });
      }

      // ──────────────────────────────────────────────────────────────────
      // PAYOUT DEFERRED (V1 buyer-protection architecture)
      // The Stripe Transfer to the seller's Connect account is NOT created
      // here. Funds remain in the SnatchIt platform Stripe balance until
      // the buyer confirms receipt (or auto-release conditions are met).
      // The release-payout function (to be built) will call
      // stripe.transfers.create() at that time.
      // ──────────────────────────────────────────────────────────────────
      console.log('Webhook: payout deferred — no Stripe Transfer created', {
        listing_id: metadata.listing_id,
        payment_id: payment.id,
        seller_id:  metadata.seller_id,
      });

      // Send push notifications. transferId (when the insert succeeded) lets
      // the tap deep-link straight to the send/receive screens; listingId
      // remains the fallback route.
      const listingTitle = listing?.event_name || 'your listing';
      const transferIdData = newTransfer?.id ? { transferId: String(newTransfer.id) } : {};

      sendPush(
        metadata.buyer_id,
        'Payment Confirmed!',
        `Your payment for ${listingTitle} was successful. Waiting for seller to transfer the ticket.`,
        { listingId: metadata.listing_id, type: 'payment_succeeded', ...transferIdData },
      );

      sendPush(
        metadata.seller_id,
        'Your ticket sold!',
        `Send the transfer now for ${listingTitle}.`,
        { listingId: metadata.listing_id, type: 'ticket_sold', ...transferIdData },
      );

      // Mark processed for ops visibility. Pure telemetry — no behavioral
      // change to the P0 payment-intent flow.
      await markProcessed();

    } else if (event.type === 'payment_intent.payment_failed') {
      // Claim guard: Stripe does NOT guarantee event ordering, and one PI
      // legitimately goes failed→succeeded when the buyer retries in the
      // same PaymentSheet. A late-arriving payment_failed must never
      // overwrite a payment that already succeeded (which would freeze its
      // payout and release the reservation on a sold listing) or one
      // already refunded.
      const { data: payment, error: lookupErr } = await supabase
        .from('payments')
        .update({ status: 'failed' })
        .eq('stripe_payment_intent_id', piId)
        .neq('status', 'succeeded')
        .neq('status', 'refunded')
        .select('id, listing_id')
        .maybeSingle();

      if (lookupErr) {
        console.error('Webhook: payment failed-update errored', piId, lookupErr);
        await markProcessed({ error: `failed-update: ${lookupErr.message}` });
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        });
      }
      if (!payment) {
        // No claimable row — unknown PI, or the payment already
        // succeeded/refunded (out-of-order delivery). Benign no-op.
        console.log('Webhook: payment_failed ignored (no claimable row)', { pi_id: piId });
        await markProcessed();
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        });
      }

      if (metadata.mode === 'buy_now') {
        const { error: rpcErr } = await supabase.rpc('release_reservation', {
          p_listing_id: metadata.listing_id,
          p_user_id:    metadata.buyer_id,
        });
        if (rpcErr) {
          console.error('Webhook RPC failed:', {
            listing_id: metadata.listing_id,
            payment_id: payment.id,
            rpc_name:   'release_reservation',
            error:      rpcErr,
          });
        } else {
          console.log('Webhook: release_reservation succeeded', { listing_id: metadata.listing_id });
        }
      }
      await markProcessed();

    // ─────────────────────────────────────────────────────────────────────
    // P1-02 — Full event coverage with dedup at the top of the handler.
    //   • Dispute handlers freeze the related transfer so auto-release
    //     and confirm-and-release cannot fire while the case is pending.
    //   • Refund / payout / transfer events sync DB state for the
    //     admin SQL-pack ops queries (DAY8_P1_02_ADMIN_SQL_PACK.sql).
    //   • Every branch awaits markProcessed() so the
    //     public.stripe_webhook_events row reflects the actual outcome.
    // ─────────────────────────────────────────────────────────────────────

    } else if (event.type === 'charge.dispute.created') {
      // ── P1-02: real dispute handling + transfer freeze ────────────────
      // event.data.object is a Stripe Dispute, NOT a PaymentIntent.
      const dispute = event.data.object as {
        id:               string;
        charge:           string;
        payment_intent?:  string | null;
        amount:           number;
        currency:         string;
        reason:           string;
        status:           string;
        evidence_details?: { due_by?: number };
      };

      // 1. Find the related payment + transfer (best-effort; PI id may be
      //    missing on some Stripe API versions).
      let paymentId:  string | null = null;
      let transferId: string | null = null;
      if (dispute.payment_intent) {
        const { data: payment } = await supabase
          .from('payments')
          .select('id')
          .eq('stripe_payment_intent_id', dispute.payment_intent)
          .maybeSingle();
        paymentId = payment?.id ?? null;
        if (paymentId) {
          const { data: transfer } = await supabase
            .from('transfers')
            .select('id, status, payout_released_at')
            .eq('payment_id', paymentId)
            .maybeSingle();
          transferId = transfer?.id ?? null;

          // 2. Freeze the transfer so auto-release / confirm-and-release
          //    cannot fire while the dispute is open. Skip if already paid
          //    out — at that point we can only attempt a transfer reversal
          //    when the dispute is lost (handled in dispute.closed).
          if (transferId && !transfer!.payout_released_at && transfer!.status !== 'disputed') {
            // freeze_transfer_for_dispute (migration 056a) re-checks
            // payout_released_at IS NULL AND status <> 'disputed' inside the
            // statement, closing the read-then-write window the direct UPDATE
            // had, and bypasses guard_transfer_state_columns as SECURITY DEFINER.
            const { data: frozen, error: freezeErr } = await supabase
              .rpc('freeze_transfer_for_dispute', { p_transfer_id: transferId });
            if (freezeErr) {
              console.error('Webhook: dispute transfer freeze failed:', {
                transfer_id: transferId, dispute_id: dispute.id, error: freezeErr,
              });
            } else if (!frozen) {
              // Not an error: the row was paid out or already frozen between
              // our read above and this call.
              console.log('Webhook: transfer freeze skipped — already frozen or already paid out', {
                transfer_id: transferId, dispute_id: dispute.id,
              });
            } else {
              console.log('Webhook: transfer frozen due to dispute', { transfer_id: transferId });
            }
          }
        }
      }

      // 3. Upsert disputes row (idempotent on stripe_dispute_id).
      const evidenceDueIso = dispute.evidence_details?.due_by
        ? new Date(dispute.evidence_details.due_by * 1000).toISOString()
        : null;
      const { error: upsertErr } = await supabase.from('disputes').upsert({
        stripe_dispute_id: dispute.id,
        stripe_charge_id:  dispute.charge,
        stripe_pi_id:      dispute.payment_intent ?? null,
        payment_id:        paymentId,
        transfer_id:       transferId,
        amount:            dispute.amount,
        currency:          dispute.currency ?? 'usd',
        reason:            dispute.reason,
        status:            dispute.status,
        evidence_due_by:   evidenceDueIso,
      }, { onConflict: 'stripe_dispute_id' });
      if (upsertErr) {
        // High-signal inner capture: a dispute event was received but we
        // failed to record it. Ops needs to know immediately so the
        // 7-day Stripe evidence window doesn't quietly close against us.
        await captureException(
          'stripe-webhook:charge.dispute.created',
          new Error(`dispute upsert failed: ${upsertErr.message}`),
          { dispute_id: dispute.id, charge_id: dispute.charge, payment_id: paymentId, transfer_id: transferId },
        );
        await markProcessed({ error: `dispute upsert: ${upsertErr.message}` });
      } else {
        console.log('Webhook: dispute recorded', {
          dispute_id: dispute.id, charge_id: dispute.charge, amount: dispute.amount,
          reason: dispute.reason, status: dispute.status,
          evidence_due_by: evidenceDueIso,
          payment_id: paymentId, transfer_id: transferId,
        });
        await markProcessed();
      }

    } else if (event.type === 'charge.dispute.closed') {
      // ── P1-02: dispute outcome sync ───────────────────────────────────
      const dispute = event.data.object as {
        id:     string;
        charge: string;
        payment_intent?: string | null;
        status: string; // 'won' | 'lost' | 'warning_closed' | 'charge_refunded'
      };

      // Update our disputes row's status.
      const { data: ourDispute, error: lookupErr } = await supabase
        .from('disputes')
        .update({ status: dispute.status })
        .eq('stripe_dispute_id', dispute.id)
        .select('id, payment_id, transfer_id')
        .maybeSingle();
      if (lookupErr) {
        console.error('Webhook: dispute status update failed:', lookupErr);
        await markProcessed({ error: `dispute close update: ${lookupErr.message}` });
      } else if (!ourDispute) {
        console.warn('Webhook: dispute.closed for unknown dispute_id', { dispute_id: dispute.id });
        await markProcessed();
      } else {
        // Won (rare under marketplace rules) → resume payout path.
        // Lost (most common) → ops decides between transfer-reversal (if
        // already paid out) or simply mark the payment refunded.
        // Don't make autonomous money moves here. Just sync state.
        if (dispute.status === 'lost' && ourDispute.payment_id) {
          const { error: payErr } = await supabase
            .from('payments')
            .update({ status: 'refunded', refunded_at: new Date().toISOString() })
            .eq('id', ourDispute.payment_id)
            .neq('status', 'refunded');
          if (payErr) console.error('Webhook: payment refund mark failed:', payErr);
        }
        console.log('Webhook: dispute closed', {
          dispute_id: dispute.id, status: dispute.status,
          payment_id: ourDispute.payment_id, transfer_id: ourDispute.transfer_id,
        });
        await markProcessed();
      }

    } else if (event.type === 'charge.refunded') {
      // ── P1-02: refund sync (e.g. manual Dashboard refund) ─────────────
      const charge = event.data.object as {
        payment_intent?: string | null;
        refunds?: { data?: Array<{ id?: string }> };
      };
      if (charge.payment_intent) {
        // Persist the Stripe refund id when the event payload carries it
        // (audit trail: ties the DB row to the re_ object). Recent API
        // versions omit charge.refunds by default, so this is best-effort.
        const refundId = charge.refunds?.data?.[0]?.id ?? null;
        const { error: refErr } = await supabase
          .from('payments')
          .update({
            status: 'refunded',
            refunded_at: new Date().toISOString(),
            ...(refundId ? { stripe_refund_id: refundId } : {}),
          })
          .eq('stripe_payment_intent_id', charge.payment_intent)
          .neq('status', 'refunded');
        if (refErr) {
          console.error('Webhook: refund sync failed:', refErr);
          await markProcessed({ error: `refund sync: ${refErr.message}` });
        } else {
          console.log('Webhook: payment marked refunded', { pi_id: charge.payment_intent });
          await markProcessed();
        }
      } else {
        console.warn('Webhook: charge.refunded with no payment_intent', { event_id: event.id });
        await markProcessed();
      }

    } else if (event.type === 'transfer.created') {
      // ── P1-02: ops observability for seller-net Transfer creation ─────
      // confirm-and-release / enforce-transfer-expiry already wrote
      // stripe_transfer_id on our transfers row before Stripe fires this
      // event. We just log for ops; no state change needed.
      const tr = event.data.object as { id: string; amount: number; destination?: string };
      console.log('Webhook: stripe Transfer created', {
        stripe_transfer_id: tr.id, amount: tr.amount, destination: tr.destination,
      });
      await markProcessed();

    } else if (event.type === 'transfer.reversed') {
      // ── P1-02: mark our transfer 'reversed' when Stripe reverses ──────
      const tr = event.data.object as { id: string; amount_reversed?: number };
      // mark_transfer_reversed (migration 056a) carries the same
      // WHERE stripe_transfer_id = $1 AND status <> 'reversed' and bypasses
      // guard_transfer_state_columns as SECURITY DEFINER. `false` = zero rows
      // (unknown tr_ id, or already reversed) — the old no-op, not an error.
      const { data: reversed, error: revErr } = await supabase
        .rpc('mark_transfer_reversed', { p_stripe_transfer_id: tr.id });
      if (revErr) {
        console.error('Webhook: transfer.reversed mark failed:', revErr);
        await markProcessed({ error: `transfer reverse: ${revErr.message}` });
      } else if (!reversed) {
        console.log('Webhook: transfer.reversed no-op (unknown transfer id or already reversed)', {
          stripe_transfer_id: tr.id,
        });
        await markProcessed();
      } else {
        console.log('Webhook: transfer marked reversed', {
          stripe_transfer_id: tr.id, amount_reversed: tr.amount_reversed,
        });
        await markProcessed();
      }

    } else if (event.type === 'payout.paid') {
      // ── P1-02: log Stripe payout to seller's bank cleared ─────────────
      // Fires on the Connect account, not the platform. Use it for the
      // seller payout timeline in the admin view (DAY8 SQL pack).
      const po = event.data.object as { id: string; amount: number; arrival_date?: number };
      console.log('Webhook: stripe payout.paid', {
        payout_id: po.id, amount: po.amount, arrival_date: po.arrival_date,
        connect_account: (event as { account?: string }).account ?? null,
      });
      await markProcessed();

    } else if (event.type === 'payout.failed') {
      // ── P1-02: payout.failed — seller's bank rejected ─────────────────
      // Stripe will retry automatically; ops should reach out so the
      // seller updates their bank info via the in-app onboarding flow.
      const po = event.data.object as { id: string; amount: number; failure_message?: string; failure_code?: string };
      console.error('Webhook: stripe payout.FAILED', {
        payout_id: po.id, amount: po.amount,
        failure_code: po.failure_code, failure_message: po.failure_message,
        connect_account: (event as { account?: string }).account ?? null,
      });
      await markProcessed();

    } else if (event.type === 'account.updated') {
      // event.data.object is a Stripe Account (Connect Express seller).
      // Per Stripe docs, `details_submitted` flips true after onboarding
      // form submission; `charges_enabled` and `payouts_enabled` flip true
      // only after Stripe finishes verification. We gate listing creation
      // on the AND of all three to avoid sellers listing tickets before
      // Stripe is actually willing to accept funds for them.
      const account = event.data.object as {
        id?:                 string;
        details_submitted?:  boolean;
        charges_enabled?:    boolean;
        payouts_enabled?:    boolean;
      };
      const accountId = account.id;

      if (!accountId) {
        console.warn('Webhook: account.updated received with no id', { event_id: event.id });
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        });
      }

      const onboardingComplete =
        account.details_submitted === true &&
        account.charges_enabled   === true &&
        account.payouts_enabled   === true;

      const { data: updatedProfiles, error: profileErr } = await supabase
        .from('profiles')
        .update({ stripe_onboarding_complete: onboardingComplete })
        .eq('stripe_connect_id', accountId)
        .select('id');

      if (profileErr) {
        // Log + ACK; Stripe will not retry account.updated and we don't
        // want to surface 5xx for transient DB errors on a non-critical
        // sync path.
        console.error('Webhook: account.updated profile update failed', {
          account_id: accountId,
          error:      profileErr.message,
        });
        await markProcessed({ error: `account.updated profile update: ${profileErr.message}` });
      } else {
        console.log('Webhook: account.updated synced', {
          account_id:           accountId,
          onboarding_complete:  onboardingComplete,
          details_submitted:    account.details_submitted ?? false,
          charges_enabled:      account.charges_enabled ?? false,
          payouts_enabled:      account.payouts_enabled ?? false,
          matched_profiles:     updatedProfiles?.length ?? 0,
        });
        await markProcessed();
      }

    } else {
      // Unknown / unhandled event type. Mark processed so ops doesn't
      // see it as a stuck-pending entry. (Stripe Dashboard configuration
      // determines which events even reach this endpoint.)
      console.log('Webhook: unhandled event type (ack only)', { event_type: event.type });
      await markProcessed();
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
    });
  } catch (err) {
    await captureException('stripe-webhook', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});
