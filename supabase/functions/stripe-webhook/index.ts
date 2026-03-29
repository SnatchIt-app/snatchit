// READY TO DEPLOY
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
};

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

async function verifyStripeSignature(rawBody: string, sigHeader: string): Promise<boolean> {
  const parts = sigHeader.split(',').reduce((acc: Record<string, string>, part) => {
    const [key, val] = part.split('=');
    acc[key] = val;
    return acc;
  }, {});

  const timestamp = parts['t'];
  const signature = parts['v1'];
  if (!timestamp || !signature) return false;

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

  return timingSafeEqual(expected, signature);
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
    return new Response('ok', { headers: { ...corsHeaders } });
  }

  try {
    const rawBody = await req.text();
    const sigHeader = req.headers.get('stripe-signature');

    if (!sigHeader || !(await verifyStripeSignature(rawBody, sigHeader))) {
      return new Response(
        JSON.stringify({ error: 'Invalid signature' }),
        { status: 400, headers: { 'Content-Type': 'application/json', ...corsHeaders } }
      );
    }

    const event = JSON.parse(rawBody);
    const paymentIntent = event.data.object;
    const piId = paymentIntent.id;
    const metadata = paymentIntent.metadata ?? {};

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

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
        .select('id, listing_id, amount, service_fee')
        .maybeSingle();                        // FIX: was .single() — returns null instead of error when 0 rows

      if (lookupErr) {
        console.error('Webhook: payment update error', piId, lookupErr);
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }

      if (!payment) {
        // Payment not found OR already processed (status was already 'succeeded').
        // Either way, this is an idempotent exit — no duplicate work.
        console.log('Webhook: payment already processed or not found, skipping', piId);
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
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
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
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

      const { error: transferErr } = await supabase.from('transfers').insert({
        listing_id:       metadata.listing_id,
        payment_id:       payment.id,
        seller_id:        metadata.seller_id,
        buyer_id:         metadata.buyer_id,
        transfer_method:  listing?.transfer_method ?? 'mobile_transfer',
        status:           'pending',
        expires_at:       expiresAt,
      });

      if (transferErr) {
        // On replay: this will be a unique-constraint violation — expected and safe.
        // On first run: any other error is worth investigating.
        console.error('Webhook: transfer insert failed:', {
          listing_id: metadata.listing_id,
          payment_id: payment.id,
          error:      transferErr,
        });
      }

      // Auto-payout to seller via Stripe Connect
      const { data: sellerProfile } = await supabase
        .from('profiles')
        .select('stripe_connect_id')
        .eq('id', metadata.seller_id)
        .single();

      if (sellerProfile?.stripe_connect_id) {
        const payoutAmount = payment.amount; // exclude service_fee — platform keeps it
        try {
          const transferRes = await fetch('https://api.stripe.com/v1/transfers', {
            method: 'POST',
            headers: {
              'Authorization':  `Bearer ${STRIPE_SECRET_KEY}`,
              'Content-Type':   'application/x-www-form-urlencoded',
              'Idempotency-Key': `transfer_${payment.id}`, // prevents duplicate payouts on Stripe retry
            },
            body: new URLSearchParams({
              'amount':                String(payoutAmount),
              'currency':              'usd',
              'destination':           sellerProfile.stripe_connect_id,
              'transfer_group':        metadata.listing_id,
              'metadata[listing_id]':  metadata.listing_id,
              'metadata[payment_id]':  payment.id,
            }).toString(),
          });
          if (!transferRes.ok) {
            const errData = await transferRes.json();
            console.error('Webhook: Stripe Transfer failed:', {
              listing_id: metadata.listing_id,
              payment_id: payment.id,
              error:      errData,
            });
          } else {
            console.log('Webhook: Stripe Transfer succeeded', {
              listing_id: metadata.listing_id,
              payment_id: payment.id,
            });
          }
        } catch (stripeErr) {
          console.error('Webhook: Stripe Transfer error:', {
            listing_id: metadata.listing_id,
            payment_id: payment.id,
            error:      stripeErr,
          });
        }
      } else {
        console.log('Webhook: seller has no stripe_connect_id, skipping payout', metadata.seller_id);
      }

      // Send push notifications
      const listingTitle = listing?.event_name || 'your listing';

      sendPush(
        metadata.buyer_id,
        'Payment Confirmed!',
        `Your payment for ${listingTitle} was successful. Waiting for seller to transfer the ticket.`,
        { listingId: metadata.listing_id, type: 'payment_succeeded' },
      );

      sendPush(
        metadata.seller_id,
        'Your ticket sold!',
        `Send the transfer now for ${listingTitle}.`,
        { listingId: metadata.listing_id, type: 'ticket_sold' },
      );

    } else if (event.type === 'payment_intent.payment_failed') {
      const { data: payment, error: lookupErr } = await supabase
        .from('payments')
        .update({ status: 'failed' })
        .eq('stripe_payment_intent_id', piId)
        .select('id, listing_id')
        .single();

      if (lookupErr || !payment) {
        console.error('Webhook: payment lookup/update failed', piId, lookupErr);
        return new Response(JSON.stringify({ received: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
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
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  } catch (err) {
    console.error('Webhook error:', err);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json', ...corsHeaders } }
    );
  }
});
