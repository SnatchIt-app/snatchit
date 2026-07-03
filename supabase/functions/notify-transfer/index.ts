/**
 * notify-transfer — transaction-progress notifications (migration 034)
 *
 * Invoked by DB triggers (pg_net + Vault service_role_key, same auth pattern as
 * notify-report / enforce-transfer-expiry) when:
 *   • a transfer row is inserted          → event 'transfer_created'
 *       - push SELLER: "Action needed: send the tickets"     (→ /transfer/send)
 *       - push BUYER (if no delivery info): "Add your transfer info…"
 *                                                            (→ /transfer/receive)
 *   • a transfer flips to 'seller_sent'    → event 'tickets_marked_sent'
 *       - push BUYER: "Tickets sent — confirm once received" (→ /transfer/receive)
 *
 * Idempotency: each (transfer_id, event_type) is logged in
 * public.transfer_notifications BEFORE sending; if the row already exists the
 * push is skipped. One notification per transfer per event type — never spams,
 * safe under trigger retries. Push-only (email stays the moderation channel).
 * All work is best-effort; failures are logged, never thrown to the caller, so
 * a notification problem can never block a buyer/seller action.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL              = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const INTERNAL_CRON_SECRET      = Deno.env.get('INTERNAL_CRON_SECRET') ?? '';

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
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
    console.error('notify-transfer: sendPush failed:', err);
  }
}

/**
 * Claim (transfer_id, event_type) in the idempotency log. Returns true only if
 * THIS call inserted the row (i.e. the notification has not been sent before).
 */
async function claim(
  supabase: ReturnType<typeof createClient>,
  transferId: string,
  eventType: string,
): Promise<boolean> {
  const { data, error } = await supabase
    .from('transfer_notifications')
    .upsert({ transfer_id: transferId, event_type: eventType }, { onConflict: 'transfer_id,event_type', ignoreDuplicates: true })
    .select();
  if (error) {
    console.error('notify-transfer: claim failed:', eventType, error);
    return false; // on error, do NOT send (avoids accidental spam)
  }
  return Array.isArray(data) && data.length > 0;
}

serve(async (req: Request) => {
  // ── Auth: INTERNAL_CRON_SECRET or runtime service-role key ────────────────
  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer /, '');
  const ok =
    (INTERNAL_CRON_SECRET.length > 0 && constantTimeEqual(token, INTERNAL_CRON_SECRET)) ||
    (SUPABASE_SERVICE_ROLE_KEY.length > 0 && constantTimeEqual(token, SUPABASE_SERVICE_ROLE_KEY));
  if (!ok) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401, headers: { 'Content-Type': 'application/json' },
    });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const payload = await req.json();
    const event: string = payload?.event ?? 'unknown';

    // ── bid_placed (migration 035): push seller on every new bid ────────────
    // One trigger fire per bid insert = exactly one push per valid bid, so no
    // idempotency row is needed. Never notify a seller about their own bid.
    if (event === 'bid_placed') {
      const listingId: string | undefined = payload?.listing_id;
      const bidderId: string | undefined = payload?.bidder_id;
      const amount: number = Number(payload?.amount ?? 0);
      if (listingId && bidderId) {
        const { data: l } = await supabase
          .from('listings')
          .select('seller_id, event_name')
          .eq('id', listingId)
          .single();
        const sellerId = (l as { seller_id?: string } | null)?.seller_id;
        if (sellerId && sellerId !== bidderId) {
          await sendPush(
            sellerId,
            'New bid on your listing',
            `"${(l as { event_name?: string } | null)?.event_name ?? 'Your listing'}" just got a $${amount.toLocaleString('en-US')} bid.`,
            { type: 'bid_received', listingId },
          );
        }
      }
      return new Response(JSON.stringify({ ok: true }), {
        status: 200, headers: { 'Content-Type': 'application/json' },
      });
    }

    const transferId: string | undefined = payload?.transfer_id;
    const buyerId: string | undefined = payload?.buyer_id;
    const sellerId: string | undefined = payload?.seller_id;

    if (!transferId || !buyerId || !sellerId) {
      return new Response(JSON.stringify({ ok: true, skipped: 'missing ids' }), {
        status: 200, headers: { 'Content-Type': 'application/json' },
      });
    }

    // Event name (for in-app context only)
    let eventName = 'your order';
    {
      const { data: t } = await supabase
        .from('transfers')
        .select('delivery_email, delivery_phone, listing:listings!listing_id(event_name)')
        .eq('id', transferId)
        .single();
      const ev = (t as { listing?: { event_name?: string } } | null)?.listing?.event_name;
      if (ev) eventName = ev;

      if (event === 'transfer_created') {
        // Seller: action required — send the tickets.
        if (await claim(supabase, transferId, 'seller_action_required')) {
          await sendPush(
            sellerId,
            'Action needed: send the tickets',
            `You sold "${eventName}". Send the tickets now to complete the sale.`,
            { type: 'seller_action', transferId },
          );
        }
        // Buyer: provide transfer info if none on file yet.
        const hasInfo = Boolean(
          (t as { delivery_email?: string | null; delivery_phone?: string | null } | null)?.delivery_email
          || (t as { delivery_phone?: string | null } | null)?.delivery_phone,
        );
        if (!hasInfo && await claim(supabase, transferId, 'buyer_transfer_info_needed')) {
          await sendPush(
            buyerId,
            'Add your transfer info',
            `Add your transfer info so the seller can send your "${eventName}" tickets.`,
            { type: 'buyer_info_needed', transferId },
          );
        }
      } else if (event === 'tickets_marked_sent') {
        // Buyer: confirm receipt.
        if (await claim(supabase, transferId, 'buyer_confirmation_needed')) {
          await sendPush(
            buyerId,
            'Tickets sent — confirm once received',
            `The seller sent your "${eventName}" tickets. Confirm once you've received them.`,
            { type: 'buyer_confirm', transferId },
          );
        }
      }
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('notify-transfer: error:', err);
    // 200 so pg_net callers never retry-storm; the trigger is fire-and-forget.
    return new Response(JSON.stringify({ ok: false }), {
      status: 200, headers: { 'Content-Type': 'application/json' },
    });
  }
});
