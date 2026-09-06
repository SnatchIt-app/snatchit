// READY TO DEPLOY
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { captureException } from '../_shared/sentry.ts';
import { stripeFetchRaw } from '../_shared/stripe.ts';

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

/**
 * How long one delivery may hold an event before another may steal the lease
 * (migration 064). Only matters when a handler dies without reaching either
 * complete or fail — a torn-down isolate. Comfortably above the observed
 * worst-case handler time of ~5.6s, and low enough that a stuck event
 * self-heals on Stripe's retry schedule rather than needing an operator.
 */
const LEASE_SECONDS = 300;

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

  // Hoisted so the catch can release the lease for whatever event we were
  // working on. Stays null if we threw before parsing, in which case there is
  // no claim to release.
  let parsedEventId: string | null = null;

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
    parsedEventId = typeof event?.id === 'string' ? event.id : null;
    const paymentIntent = event.data.object;
    const piId = paymentIntent.id;
    const metadata = paymentIntent.metadata ?? {};

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // ─── Idempotency gate: claim/complete/fail lease (migration 064) ─────
    //
    // The old gate inserted a row here and treated "row exists" as "already
    // done". It never looked at `processed`. So an event that claimed the
    // payment row and then threw would return 500, Stripe would retry, the
    // retry hit 23505, and we answered 200 having done nothing — leaving the
    // buyer charged with no transfer, no mark_listing_sold, and the listing
    // still reserved, permanently and with no retry path.
    //
    // Now a claim is a lease. Only 'claimed' does work:
    //   already_processed -> 200, genuinely nothing to do
    //   in_flight         -> 409, another delivery holds a live lease, so let
    //                        Stripe retry rather than double-process
    // The claim is one atomic statement, so concurrent deliveries of the same
    // event cannot both win it.
    {
      const { data: claim, error: claimErr } = await supabase
        .rpc('claim_stripe_webhook_event', {
          p_event_id: event.id,
          p_event_type: event.type,
          p_lease_seconds: LEASE_SECONDS,
        });

      if (claimErr) {
        // Deliberately fail CLOSED, unlike the old gate which logged and
        // carried on without a dedup row — that let two concurrent deliveries
        // run every side effect during a database hiccup. A 500 costs us a
        // Stripe retry; failing open costs a double charge or double transfer.
        console.error('Webhook: claim failed, refusing to process:', {
          event_id: event.id, event_type: event.type, error: claimErr,
        });
        await captureException('stripe-webhook', claimErr);
        return new Response(
          JSON.stringify({ error: 'Could not claim event' }),
          { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }

      if (claim === 'already_processed') {
        console.log('Webhook: event already processed, skipping', {
          event_id: event.id, event_type: event.type,
        });
        return new Response(
          JSON.stringify({ received: true, duplicate: true }),
          { status: 200, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }

      if (claim === 'in_flight') {
        console.warn('Webhook: event already in flight, asking Stripe to retry', {
          event_id: event.id, event_type: event.type,
        });
        return new Response(
          JSON.stringify({ error: 'Event already in flight' }),
          { status: 409, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } },
        );
      }
    }

    // Terminal success for this event. After this the event can never be
    // reprocessed, so it must only be called once the authoritative work is
    // genuinely done — including the benign no-op paths, which ARE complete.
    async function markProcessed(opts: { error?: string } = {}) {
      if (opts.error) {
        // Records the error and RELEASES the lease, so the next Stripe
        // delivery re-claims and reprocesses instead of being swallowed.
        const { error: failErr } = await supabase
          .rpc('fail_stripe_webhook_event', { p_event_id: event.id, p_error: opts.error });
        if (failErr) console.warn('Webhook: fail_stripe_webhook_event failed:', failErr.message);
        return;
      }
      const { error: doneErr } = await supabase
        .rpc('complete_stripe_webhook_event', { p_event_id: event.id });
      if (doneErr) console.warn('Webhook: complete_stripe_webhook_event failed:', doneErr.message);
    }

    /**
     * Ends the request. `ok: false` means the authoritative work did NOT
     * finish, so we answer non-2xx and Stripe retries — the event stays
     * reclaimable. Previously every one of these paths returned 200.
     */
    async function finish(
      ok: boolean,
      body: Record<string, unknown>,
      error?: string,
    ): Promise<Response> {
      await markProcessed(ok ? {} : { error: error ?? 'incomplete' });
      return new Response(
        JSON.stringify(ok ? { received: true, ...body } : { error: error ?? 'incomplete', ...body }),
        {
          status: ok ? 200 : 500,
          headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) },
        },
      );
    }

    if (event.type === 'payment_intent.succeeded') {
      // ── Package 2: ONE call to the verified-settlement contract ─────────
      // settle_verified_payment (migration 20260906110000) verifies the
      // PaymentIntent's facts against the stored row (amount / currency /
      // livemode / metadata), enforces refund monotonicity, promotes only on
      // Stripe `succeeded`, settles the listing + transfer through the
      // Package 1 core, and records every non-settling outcome once in
      // webhook_retries. It replaces the old claim-UPDATE + client RPC +
      // transfer INSERT sequence AND the "already processed" fallback branch
      // (investigation F02: the retry used to skip the sale RPC forever).
      //
      // Acknowledgment: any RPC ERROR is NOT terminal — 500 + fail, so Stripe
      // redelivers and the retry calls the contract AGAIN (it is guarded by
      // current state, not by "did I run before"). Every RPC OUTCOME is
      // terminal — 200 + complete — because the contract already recorded
      // unknown_payment / binding_mismatch / unfulfillable for the sweep and
      // for ops; retrying a terminal outcome for three days helps nobody.
      // Refund facts arrive via charge.refunded (Package 3's branch), so this
      // event passes amount_refunded 0 / refund id NULL: the contract still
      // refuses to promote a row that is already refunded.
      const pi = paymentIntent as {
        status?: string; amount_received?: number; currency?: string; livemode?: boolean;
        payment_method_types?: string[]; metadata?: Record<string, string>;
      };
      const { data: settleRows, error: settleErr } = await supabase.rpc('settle_verified_payment', {
        p_payment_intent_id: piId,
        p_stripe_status:     pi.status ?? 'succeeded',
        p_amount_received:   typeof pi.amount_received === 'number' ? pi.amount_received : null,
        p_currency:          pi.currency ?? null,
        p_livemode:          typeof pi.livemode === 'boolean' ? pi.livemode : null,
        p_amount_refunded:   0,
        p_stripe_refund_id:  null,
        p_payment_method:    pi.payment_method_types?.[0] ?? 'card',
        p_metadata:          metadata,
        p_source:            `webhook:${event.id}`,
      });

      if (settleErr) {
        console.error('Webhook: settle_verified_payment failed', { pi_id: piId, event_id: event.id, error: settleErr });
        return await finish(false, { stage: 'settle_verified_payment' }, `settle_verified_payment: ${settleErr.message}`);
      }

      const settled = (Array.isArray(settleRows) ? settleRows[0] : settleRows) as
        | { payment_id: string | null; payment_status: string | null; listing_status: string | null; transfer_id: string | null; outcome: string }
        | null
        | undefined;
      if (!settled?.outcome) {
        // The contract always returns exactly one row; no row means the call
        // did not run to completion (PostgREST hiccup) — not terminal.
        console.error('Webhook: settle_verified_payment returned no row', { pi_id: piId, event_id: event.id });
        return await finish(false, { stage: 'settle_verified_payment' }, 'settle_verified_payment: no row');
      }

      const outcomeLog = {
        pi_id: piId, event_id: event.id, outcome: settled.outcome,
        payment_id: settled.payment_id, payment_status: settled.payment_status,
        listing_status: settled.listing_status, transfer_id: settled.transfer_id,
      };
      if (settled.outcome === 'settled' || settled.outcome === 'already_settled') {
        console.log('Webhook: settlement outcome', outcomeLog);
      } else {
        // unfulfillable / binding_mismatch / unknown_payment are in the
        // webhook_retries review queue (the sweep refunds unfulfillable);
        // refunded / not_succeeded / canceled are benign state facts.
        console.warn('Webhook: non-settling outcome (terminal, recorded by the contract)', outcomeLog);
      }

      if (settled.outcome === 'settled' && metadata.buyer_id && metadata.seller_id) {
        // First and only time this sale settled: notify both parties. The
        // transfer id (from the contract) deep-links to the send/receive
        // screens; listingId remains the fallback route.
        const { data: listing } = await supabase
          .from('listings')
          .select('event_name')
          .eq('id', metadata.listing_id)
          .maybeSingle();
        const listingTitle = listing?.event_name || 'your listing';
        const transferIdData = settled.transfer_id ? { transferId: String(settled.transfer_id) } : {};

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
      }

      return await finish(true, {
        outcome:     settled.outcome,
        payment_id:  settled.payment_id,
        transfer_id: settled.transfer_id,
      });

    } else if (event.type === 'payment_intent.payment_failed' || event.type === 'payment_intent.canceled') {
      // Claim guard: Stripe does NOT guarantee event ordering, and one PI
      // legitimately goes failed→succeeded when the buyer retries in the
      // same PaymentSheet. A late-arriving payment_failed / canceled must
      // never overwrite a payment that already succeeded (which would freeze
      // its payout and release the reservation on a sold listing) or one
      // already refunded. One predicate, `status NOT IN (succeeded, refunded)`,
      // so Package 3's transition guard (refunded is terminal) never fires.
      const { data: payment, error: lookupErr } = await supabase
        .from('payments')
        .update({ status: 'failed' })
        .eq('stripe_payment_intent_id', piId)
        .not('status', 'in', '("succeeded","refunded")')
        .select('id, listing_id')
        .maybeSingle();

      if (lookupErr) {
        // The authoritative write did not happen; we do not know the row's
        // state. Non-terminal — Stripe redelivers (used to be ACKed with 200).
        console.error('Webhook: payment failed/canceled update errored', { pi_id: piId, event_type: event.type, error: lookupErr });
        return await finish(false, { stage: 'payment_failed_update' }, `${event.type}: ${lookupErr.message}`);
      }
      if (!payment) {
        // No claimable row — unknown PI, or the payment already
        // succeeded/refunded/failed (out-of-order or duplicate delivery).
        // Benign no-op: genuinely nothing left to do.
        console.log('Webhook: payment_failed/canceled ignored (no claimable row)', { pi_id: piId, event_type: event.type });
        return await finish(true, { skipped: 'no_claimable_row' });
      }

      if (metadata.mode === 'buy_now') {
        // Free the Buy-Now hold so the listing is purchasable again. Best
        // effort with a bounded backstop: the reservation is server-owned
        // (10-minute TTL, Package 1) and cleanup_expired_reservations frees
        // it when it lapses, so a failure here is logged, not retried — a
        // retry could not redo the failed-write above (already claimed) and
        // release_reservation is a no-op once the hold is gone.
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
      return await finish(true, { path: event.type === 'payment_intent.canceled' ? 'canceled' : 'payment_failed', payment_id: payment.id });

    // ─────────────────────────────────────────────────────────────────────
    // P1-02 — Full event coverage with dedup at the top of the handler.
    //   • Dispute handlers freeze the related transfer so auto-release
    //     and confirm-and-release cannot fire while the case is pending.
    //   • Refund / payout / transfer events sync DB state for the
    //     admin SQL-pack ops queries (DAY8_P1_02_ADMIN_SQL_PACK.sql).
    //   • Every branch reaches markProcessed()/finish() so the
    //     public.stripe_webhook_events row reflects the actual outcome:
    //     success sets processed_at (terminal, never reprocessed), failure
    //     releases the lease so Stripe's retry reprocesses (migration 064).
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
        // Package 3: a dispute we failed to record is NOT done — answer
        // non-2xx so Stripe redelivers (the lease is released by finish).
        return await finish(false, { dispute_id: dispute.id }, `dispute upsert: ${upsertErr.message}`);
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
      // ── Package 3 (20260906120000): dispute outcome sync ───────────────
      // A LOST dispute is a chargeback: recorded through record_payment_refund
      // with the DISPUTE id (never as stripe_refund_id), monotonic amount, and
      // if the seller was already paid the attempt is flagged
      // reversal_required + manual_review DISPUTE_LOST_AFTER_PAYOUT for ops.
      // A dispute we never recorded (missed .created) is reconciled from this
      // event, not dropped. Every DB failure answers non-2xx (Stripe retries).
      const dispute = event.data.object as {
        id:     string;
        charge: string;
        payment_intent?: string | null;
        amount?: number;
        currency?: string;
        reason?: string;
        status: string; // 'won' | 'lost' | 'warning_closed' | 'charge_refunded'
      };

      let ourDispute: { id: string; payment_id: string | null; transfer_id: string | null } | null = null;
      {
        const { data, error: lookupErr } = await supabase
          .from('disputes')
          .update({ status: dispute.status })
          .eq('stripe_dispute_id', dispute.id)
          .select('id, payment_id, transfer_id')
          .maybeSingle();
        if (lookupErr) {
          console.error('Webhook: dispute status update failed:', lookupErr);
          return await finish(false, { dispute_id: dispute.id }, `dispute close update: ${lookupErr.message}`);
        }
        ourDispute = data ?? null;
      }

      if (!ourDispute) {
        // Unknown dispute: reconcile it from the event so the ledger is complete.
        console.warn('Webhook: dispute.closed for unknown dispute_id — upserting from event', { dispute_id: dispute.id });
        let paymentId: string | null = null;
        let transferId: string | null = null;
        if (dispute.payment_intent) {
          const { data: payment, error: payLookupErr } = await supabase
            .from('payments').select('id').eq('stripe_payment_intent_id', dispute.payment_intent).maybeSingle();
          if (payLookupErr) {
            return await finish(false, { dispute_id: dispute.id }, `dispute close payment lookup: ${payLookupErr.message}`);
          }
          paymentId = payment?.id ?? null;
          if (paymentId) {
            const { data: transfer, error: trLookupErr } = await supabase
              .from('transfers').select('id').eq('payment_id', paymentId).maybeSingle();
            if (trLookupErr) {
              return await finish(false, { dispute_id: dispute.id }, `dispute close transfer lookup: ${trLookupErr.message}`);
            }
            transferId = transfer?.id ?? null;
          }
        }
        const { error: upsertErr } = await supabase.from('disputes').upsert({
          stripe_dispute_id: dispute.id,
          stripe_charge_id:  dispute.charge,
          stripe_pi_id:      dispute.payment_intent ?? null,
          payment_id:        paymentId,
          transfer_id:       transferId,
          amount:            dispute.amount ?? 0,
          currency:          dispute.currency ?? 'usd',
          reason:            dispute.reason ?? 'unknown',
          status:            dispute.status,
        }, { onConflict: 'stripe_dispute_id' });
        if (upsertErr) {
          console.error('Webhook: dispute.closed upsert failed:', upsertErr);
          return await finish(false, { dispute_id: dispute.id }, `dispute close upsert: ${upsertErr.message}`);
        }
        ourDispute = { id: dispute.id, payment_id: paymentId, transfer_id: transferId };
      }

      if (dispute.status === 'lost' && ourDispute.payment_id) {
        // Resolve the PI id (event first, our payments row as fallback).
        let piId: string | null = dispute.payment_intent ?? null;
        if (!piId) {
          const { data: pay, error: piErr } = await supabase
            .from('payments').select('stripe_payment_intent_id').eq('id', ourDispute.payment_id).maybeSingle();
          if (piErr) return await finish(false, { dispute_id: dispute.id }, `dispute lost payment lookup: ${piErr.message}`);
          piId = pay?.stripe_payment_intent_id ?? null;
        }
        if (!piId) {
          return await finish(false, { dispute_id: dispute.id }, 'dispute lost: payment has no payment_intent id');
        }
        const { data: refundRes, error: refundErr } = await supabase.rpc('record_payment_refund', {
          p_payment_intent_id: piId,
          p_stripe_refund_id:  null,
          p_stripe_dispute_id: dispute.id,
          p_amount_cents:      typeof dispute.amount === 'number' ? dispute.amount : null,
          p_source:            'dispute_lost',
        });
        if (refundErr) {
          console.error('Webhook: dispute lost — record_payment_refund failed:', refundErr);
          return await finish(false, { dispute_id: dispute.id }, `dispute lost refund record: ${refundErr.message}`);
        }
        console.log('Webhook: dispute lost — chargeback recorded', { dispute_id: dispute.id, result: refundRes });

        // Seller already paid? The transfer must be reversed by an operator.
        if (ourDispute.transfer_id) {
          const { data: tr, error: trErr } = await supabase
            .from('transfers').select('id, payout_released_at, stripe_transfer_id')
            .eq('id', ourDispute.transfer_id).maybeSingle();
          if (trErr) return await finish(false, { dispute_id: dispute.id }, `dispute lost transfer lookup: ${trErr.message}`);
          if (tr && (tr.payout_released_at || tr.stripe_transfer_id)) {
            const { data: flagged, error: flagErr } = await supabase.rpc('flag_payout_reversal_required', {
              p_transfer_id: ourDispute.transfer_id,
              p_reason_code: 'DISPUTE_LOST_AFTER_PAYOUT',
              p_evidence:    { dispute_id: dispute.id, dispute_amount: dispute.amount ?? null },
            });
            if (flagErr) {
              console.error('Webhook: dispute lost — flag_payout_reversal_required failed:', flagErr);
              return await finish(false, { dispute_id: dispute.id }, `dispute lost reversal flag: ${flagErr.message}`);
            }
            console.error('Webhook: dispute LOST after payout — reversal required', {
              dispute_id: dispute.id, transfer_id: ourDispute.transfer_id, flagged,
            });
          }
        }
      }
      console.log('Webhook: dispute closed', {
        dispute_id: dispute.id, status: dispute.status,
        payment_id: ourDispute.payment_id, transfer_id: ourDispute.transfer_id,
      });
      await markProcessed();

    } else if (event.type === 'charge.refunded') {
      // ── Package 3 (20260906120000): refund sync ───────────────────────
      // Fires for partial AND full refunds. Each Stripe refund object is
      // recorded through record_payment_refund (idempotent on re_ id, monotonic
      // amount_refunded_cents); the payment becomes 'refunded' only when the
      // refunded amount reaches its total — i.e. when charge.refunded is true.
      // Recent API versions omit charge.refunds: fetch the charge with
      // expand[]=refunds rather than guessing. DB/Stripe failures → non-2xx.
      const charge = event.data.object as {
        id: string;
        payment_intent?: string | null;
        refunded?: boolean;
        amount_refunded?: number;
        refunds?: { data?: Array<{ id?: string; amount?: number; metadata?: Record<string, string> }> };
      };
      if (!charge.payment_intent) {
        console.warn('Webhook: charge.refunded with no payment_intent', { event_id: event.id });
        await markProcessed();
      } else {
        let refunds = charge.refunds?.data;
        if (!refunds) {
          const probe = await stripeFetchRaw(`/charges/${charge.id}?expand[]=refunds`);
          if (!probe.ok) {
            const msg = (probe.data as { error?: { message?: string } })?.error?.message ?? `HTTP ${probe.status}`;
            console.error('Webhook: charge.refunded — charge fetch failed:', { charge_id: charge.id, error: msg });
            return await finish(false, { charge_id: charge.id }, `refund sync charge fetch: ${msg}`);
          }
          refunds = (probe.data as typeof charge).refunds?.data ?? [];
        }
        const results: unknown[] = [];
        for (const r of refunds) {
          if (!r?.id) continue;
          const source = r.metadata?.source?.startsWith('enforce-transfer-expiry') ? 'expiry' : 'dashboard';
          const { data: res, error: refErr } = await supabase.rpc('record_payment_refund', {
            p_payment_intent_id: charge.payment_intent,
            p_stripe_refund_id:  r.id,
            p_stripe_dispute_id: null,
            p_amount_cents:      typeof r.amount === 'number' ? r.amount : null,
            p_source:            source,
          });
          if (refErr) {
            console.error('Webhook: refund sync failed:', { refund_id: r.id, error: refErr });
            return await finish(false, { charge_id: charge.id, refund_id: r.id }, `refund sync: ${refErr.message}`);
          }
          results.push(res);
        }
        const last = results.at(-1) as { status?: string; payment_id?: string | null } | undefined;
        if (charge.refunded === true && last?.payment_id && last.status !== 'refunded') {
          console.warn('Webhook: charge fully refunded on Stripe but the recorded amount is below total', {
            pi_id: charge.payment_intent, amount_refunded: charge.amount_refunded, result: last,
          });
        }
        console.log('Webhook: refunds recorded', { pi_id: charge.payment_intent, count: results.length, refunded: charge.refunded === true });
        await markProcessed();
      }

    } else if (event.type === 'transfer.created') {
      // ── Package 3 (20260906120000): record the attempt from Stripe's side ─
      // Every payout this package creates carries metadata[attempt_id]. If the
      // edge crashed between the POST and record_payout_attempt_result, this
      // event records it (idempotent: unique stripe_transfer_id, same-id replay
      // is a no-op). Legacy transfers without an attempt id are logged only.
      const tr = event.data.object as { id: string; amount: number; destination?: string; metadata?: Record<string, string> };
      const attemptId = tr.metadata?.attempt_id ?? null;
      if (!attemptId) {
        console.log('Webhook: stripe Transfer created (no attempt id — legacy)', {
          stripe_transfer_id: tr.id, amount: tr.amount, destination: tr.destination,
        });
        await markProcessed();
      } else {
        const { data: recorded, error: recErr } = await supabase.rpc('record_payout_attempt_result', {
          p_attempt_id:         attemptId,
          p_stripe_transfer_id: tr.id,
          p_outcome:            'succeeded',
          p_error:              { source: 'webhook:transfer.created', event_id: event.id },
        });
        if (recErr) {
          console.error('Webhook: transfer.created — record_payout_attempt_result failed:', recErr);
          return await finish(false, { stripe_transfer_id: tr.id, attempt_id: attemptId }, `transfer created record: ${recErr.message}`);
        }
        console.log('Webhook: stripe Transfer created — attempt recorded', {
          stripe_transfer_id: tr.id, attempt_id: attemptId, amount: tr.amount, destination: tr.destination, result: recorded,
        });
        await markProcessed();
      }

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
        return await finish(false, { stripe_transfer_id: tr.id }, `transfer reverse: ${revErr.message}`);
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
        // Malformed but correctly signed. Retrying cannot fix it — terminal.
        console.warn('Webhook: account.updated received with no id', { event_id: event.id });
        return await finish(true, { skipped: 'account_without_id' });
      }

      const onboardingComplete =
        account.details_submitted === true &&
        account.charges_enabled   === true &&
        account.payouts_enabled   === true;

      // Persist the capability flags too, not just the derived AND. They were
      // previously written by NOTHING anywhere in the codebase, so every
      // profile sat at the column default (false / 'not_started') no matter
      // what Stripe reported — this handler already had both values in hand
      // and discarded them. stripe_onboarding_complete keeps its existing
      // semantics (the AND of all three), since listing creation gates on it.
      const { data: updatedProfiles, error: profileErr } = await supabase
        .from('profiles')
        .update({
          stripe_onboarding_complete: onboardingComplete,
          stripe_charges_enabled:     account.charges_enabled === true,
          stripe_payouts_enabled:     account.payouts_enabled === true,
          stripe_connect_status:      account.details_submitted === true
            ? 'connected'
            : 'onboarding_required',
        })
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

    // THE fix for the original bug. A throw here used to return 500 with the
    // dedup row still sitting there claimed, so Stripe's retry hit 23505 and
    // was answered 200 having done nothing. Release the lease so the retry
    // genuinely reprocesses.
    //
    // Best-effort and defensive: if this itself throws, or the throw happened
    // before the claim, we still return 500. An unreleased lease is recovered
    // by the LEASE_SECONDS timeout on a later delivery.
    try {
      const eventId = (parsedEventId ?? '') as string;
      if (eventId) {
        const supabaseFail = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
        await supabaseFail.rpc('fail_stripe_webhook_event', {
          p_event_id: eventId,
          p_error: err instanceof Error ? `${err.name}: ${err.message}` : String(err),
        });
      }
    } catch (releaseErr) {
      console.error('Webhook: could not release lease after throw:', releaseErr);
    }

    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json', ...getResponseHeaders(req) } }
    );
  }
});
