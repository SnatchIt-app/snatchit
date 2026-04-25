# Day 2 — Transfer Expiry + Auto-Refund: Implementation Audit

**Date:** 2026-03-31
**Status:** Audit complete — ready to implement

---

## SECTION 1 — Current Readiness for Day 2

### What Already Exists

| Component | Status | Details |
|-----------|--------|---------|
| `transfers.expires_at` column | ✅ EXISTS | `timestamptz NOT NULL`, set to `now() + 24h` at creation |
| `transfers.status = 'expired'` | ✅ EXISTS | Already in the CHECK constraint (`pending`, `seller_sent`, `buyer_confirmed`, `disputed`, **`expired`**) |
| `payments.status = 'refunded'` | ✅ EXISTS | Already in the CHECK constraint (`pending`, `processing`, `succeeded`, `failed`, **`refunded`**) |
| `payments.refunded_at` column | ✅ EXISTS | `timestamptz`, nullable, already in schema |
| `payments.stripe_payment_intent_id` | ✅ EXISTS | `text UNIQUE` — needed to call `stripe.refunds.create({ payment_intent: pi_xxx })` |
| `idx_transfers_status` index | ✅ EXISTS | Index on `transfers.status` — efficient for `WHERE status = 'pending' AND expires_at < now()` |
| `auto-finalize-auctions` edge function | ✅ EXISTS | Proven pattern: service-role-authenticated edge function calling a batch RPC |
| `send-push` edge function | ✅ EXISTS | Internal push notification sender via Expo Push API |
| Rate limiting infrastructure | ✅ EXISTS | `check_rate_limit()` RPC ready for new functions |

### Day 1 Baseline (DO NOT TOUCH)
- Buyer payment → transfer row created (pending, 24h expiry) ✅
- Seller marks sent → `mark_transfer_sent` RPC (pending → seller_sent) ✅
- Buyer confirms → `confirm-and-release` edge function (seller_sent → buyer_confirmed + Stripe Transfer) ✅
- Stripe Connect onboarding ✅
- Manage Payouts screen ✅

---

## SECTION 2 — Exact Missing Pieces

| # | Missing Component | Why It's Needed |
|---|-------------------|-----------------|
| 1 | **`enforce_transfer_expiry()` RPC** | Batch SQL function to find expired pending transfers, set status='expired', set payment status='refunded' |
| 2 | **`enforce-transfer-expiry` edge function** | Calls the RPC, then calls Stripe refund API for each expired transfer, sends push notifications |
| 3 | **`stripe_refund_id` column on payments** | Store the Stripe Refund object ID (`re_xxx`) for reconciliation/idempotency |
| 4 | **`expired_at` column on transfers** | Timestamp when the expiry was actually enforced (distinct from `expires_at` which is the deadline) |
| 5 | **Cron trigger** | Supabase `pg_cron` job or external scheduler to invoke the edge function periodically |
| 6 | **Push notifications** | Buyer: "Your refund has been processed" / Seller: "Transfer expired, buyer refunded" |

---

## SECTION 3 — Smallest Exact Implementation Plan

### Architecture Decision: Follow the `auto-finalize-auctions` Pattern

The existing `auto-finalize-auctions` flow is the proven pattern:
1. **Edge function** (service-role authenticated) calls a **batch RPC**
2. **RPC** does the DB work atomically with `FOR UPDATE SKIP LOCKED`
3. **Edge function** handles external API calls (Stripe) after getting results from RPC
4. **Cron** calls the edge function on a schedule

### Implementation Steps (ordered)

**Step 1: Migration 007** — Add `expired_at` to transfers + `stripe_refund_id` to payments

**Step 2: `enforce_transfer_expiry()` RPC** — Batch function that:
- Selects transfers WHERE `status = 'pending' AND expires_at < now()` with `FOR UPDATE SKIP LOCKED`
- Sets `status = 'expired'`, `expired_at = now()`
- Returns the expired transfer rows (with payment_id, buyer_id, seller_id, listing_id) so the edge function can process refunds

**Step 3: `enforce-transfer-expiry` edge function** — Service-role authenticated function that:
- Calls the RPC to get newly-expired transfers
- For each: calls Stripe `POST /v1/refunds` with the `payment_intent` ID
- Updates `payments.status = 'refunded'`, `payments.refunded_at = now()`, `payments.stripe_refund_id = re_xxx`
- Sends push notifications to buyer and seller
- Returns count of processed expirations

**Step 4: Cron schedule** — `pg_cron` job running every 5 minutes (or externally via Supabase Dashboard cron)

### Why This Is V1-Safe
- No new tables — only 2 new columns on existing tables
- Follows the exact same pattern as `auto-finalize-auctions`
- RPC does the DB state transition atomically (no partial updates)
- Edge function handles Stripe + notifications (external side effects)
- `SKIP LOCKED` prevents concurrent runs from double-processing
- Stripe refund is idempotent when we store + check `stripe_refund_id`

---

## SECTION 4 — Exact SQL / Edge Function / Scheduler Changes Needed

### 4A. Migration 007: `007_transfer_expiry.sql`

```sql
-- =============================================================================
-- Migration 007: Transfer expiry support
-- =============================================================================
-- PURPOSE: Add columns needed for the enforce_transfer_expiry system.
--
-- COLUMNS ADDED:
--   transfers.expired_at       — when expiry was enforced (vs expires_at = deadline)
--   payments.stripe_refund_id  — Stripe Refund object ID (re_xxx) for idempotency
--
-- SAFETY:
--   - Purely additive (ADD COLUMN IF NOT EXISTS)
--   - Both columns nullable — no backfill needed
--   - No existing queries, RPCs, RLS policies, or constraints affected
-- =============================================================================

-- Track when expiry was actually enforced
alter table public.transfers
  add column if not exists expired_at timestamptz;

-- Track Stripe Refund ID for idempotency and reconciliation
alter table public.payments
  add column if not exists stripe_refund_id text;

-- Composite index for the expiry sweep query
-- Covers: WHERE status = 'pending' AND expires_at < now()
create index if not exists idx_transfers_pending_expires
  on public.transfers (expires_at)
  where status = 'pending';
```

### 4B. `enforce_transfer_expiry()` RPC

```sql
-- =============================================================================
-- enforce_transfer_expiry()
-- =============================================================================
-- Called by: enforce-transfer-expiry edge function (service role, cron)
-- Purpose:  Find all pending transfers past their expiry, mark them expired,
--           and return the rows so the edge function can issue Stripe refunds.
--
-- Pattern:  Identical to auto_finalize_expired_auctions — batch + SKIP LOCKED
-- =============================================================================
create or replace function public.enforce_transfer_expiry()
returns table (
  transfer_id         uuid,
  payment_id          uuid,
  listing_id          uuid,
  buyer_id            uuid,
  seller_id           uuid
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with expired as (
    select t.id, t.payment_id, t.listing_id, t.buyer_id, t.seller_id
      from public.transfers t
     where t.status = 'pending'
       and t.expires_at < now()
     for update skip locked
  )
  update public.transfers t
     set status     = 'expired',
         expired_at = now()
    from expired e
   where t.id = e.id
  returning t.id as transfer_id,
            t.payment_id,
            t.listing_id,
            t.buyer_id,
            t.seller_id;
end;
$$;
```

### 4C. `enforce-transfer-expiry` Edge Function

```typescript
// supabase/functions/enforce-transfer-expiry/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

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

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { 'Access-Control-Allow-Origin': '*' } });
  }

  // Auth: service-role only (same pattern as auto-finalize-auctions)
  const token = req.headers.get('Authorization')?.replace('Bearer ', '');
  if (token !== SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Step 1: Call RPC to atomically expire pending transfers
    const { data: expiredTransfers, error: rpcErr } = await supabase.rpc('enforce_transfer_expiry');

    if (rpcErr) {
      console.error('enforce_transfer_expiry RPC failed:', rpcErr);
      return new Response(JSON.stringify({ error: rpcErr.message }), { status: 500 });
    }

    if (!expiredTransfers || expiredTransfers.length === 0) {
      return new Response(
        JSON.stringify({ expired: 0, refunded: 0, timestamp: new Date().toISOString() }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      );
    }

    console.log(`enforce-transfer-expiry: found ${expiredTransfers.length} expired transfers`);

    let refundedCount = 0;

    // Step 2: For each expired transfer, issue Stripe refund
    for (const t of expiredTransfers) {
      try {
        // Look up the payment to get stripe_payment_intent_id
        const { data: payment, error: payErr } = await supabase
          .from('payments')
          .select('id, stripe_payment_intent_id, status, stripe_refund_id')
          .eq('id', t.payment_id)
          .single();

        if (payErr || !payment) {
          console.error('enforce-transfer-expiry: payment lookup failed:', {
            transfer_id: t.transfer_id,
            payment_id: t.payment_id,
            error: payErr,
          });
          continue;
        }

        // Idempotency: skip if already refunded
        if (payment.status === 'refunded' || payment.stripe_refund_id) {
          console.log('enforce-transfer-expiry: payment already refunded, skipping:', {
            transfer_id: t.transfer_id,
            payment_id: t.payment_id,
          });
          refundedCount++;
          continue;
        }

        if (!payment.stripe_payment_intent_id) {
          console.error('enforce-transfer-expiry: no stripe_payment_intent_id:', {
            transfer_id: t.transfer_id,
            payment_id: t.payment_id,
          });
          continue;
        }

        // Issue full refund via Stripe
        const refund = await stripePost('/refunds', {
          'payment_intent': payment.stripe_payment_intent_id,
          'metadata[transfer_id]': t.transfer_id,
          'metadata[reason]': 'transfer_expired',
        });

        // Update payment record
        const { error: updateErr } = await supabase
          .from('payments')
          .update({
            status: 'refunded',
            refunded_at: new Date().toISOString(),
            stripe_refund_id: refund.id,
          })
          .eq('id', t.payment_id);

        if (updateErr) {
          console.error('enforce-transfer-expiry: payment update failed:', {
            transfer_id: t.transfer_id,
            payment_id: t.payment_id,
            stripe_refund_id: refund.id,
            error: updateErr,
          });
        }

        refundedCount++;

        // Look up listing name for notification text
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

        console.log('enforce-transfer-expiry: refund issued:', {
          transfer_id: t.transfer_id,
          payment_id: t.payment_id,
          stripe_refund_id: refund.id,
        });

      } catch (err) {
        console.error('enforce-transfer-expiry: error processing transfer:', {
          transfer_id: t.transfer_id,
          error: err instanceof Error ? err.message : err,
        });
        // Continue to next transfer — don't let one failure block others
      }
    }

    return new Response(
      JSON.stringify({
        expired: expiredTransfers.length,
        refunded: refundedCount,
        timestamp: new Date().toISOString(),
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    console.error('enforce-transfer-expiry: unhandled error:', err);
    return new Response(JSON.stringify({ error: 'Internal server error' }), { status: 500 });
  }
});
```

### 4D. Cron Schedule

**Option A — Supabase Dashboard Cron (recommended for V1):**
In Supabase Dashboard → Database → Extensions → enable `pg_cron`, then:

```sql
-- Run every 5 minutes
select cron.schedule(
  'enforce-transfer-expiry',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/enforce-transfer-expiry',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

**Option B — External cron (if pg_cron + pg_net not available):**
Use the Supabase Dashboard "Edge Function Schedules" or any external cron service to `POST` to the edge function URL with the service-role key every 5 minutes.

---

## SECTION 5 — Exact Implementation Prompt

```
ROLE: Senior Supabase + Stripe engineer implementing Day 2 auto-expiry for SnatchIt.

CONTEXT:
- Day 1 is COMPLETE and WORKING. Do NOT modify any existing RPCs, edge functions, or schema.
- The transfers table already has: expires_at (timestamptz NOT NULL), status CHECK includes 'expired'
- The payments table already has: stripe_payment_intent_id, status CHECK includes 'refunded', refunded_at column

TASK: Implement transfer auto-expiry + auto-refund. Create these files:

1. supabase/migrations/007_transfer_expiry.sql
   - Add expired_at (timestamptz) to transfers
   - Add stripe_refund_id (text) to payments
   - Add partial index idx_transfers_pending_expires on transfers(expires_at) WHERE status = 'pending'
   - Create enforce_transfer_expiry() RPC that:
     - SELECTs transfers WHERE status='pending' AND expires_at < now() FOR UPDATE SKIP LOCKED
     - UPDATEs them to status='expired', expired_at=now()
     - RETURNs (transfer_id, payment_id, listing_id, buyer_id, seller_id)

2. supabase/functions/enforce-transfer-expiry/index.ts
   - Auth: service-role key check (same as auto-finalize-auctions)
   - Call enforce_transfer_expiry() RPC
   - For each returned row:
     a. Look up payments.stripe_payment_intent_id
     b. Skip if payments.status='refunded' or stripe_refund_id IS NOT NULL (idempotent)
     c. POST /v1/refunds with payment_intent
     d. UPDATE payments SET status='refunded', refunded_at=now(), stripe_refund_id=re_xxx
     e. Send push to buyer: "Refund Processed" — seller didn't send in time
     f. Send push to seller: "Transfer Expired" — buyer has been refunded
   - Return JSON: { expired: N, refunded: N, timestamp: ISO }
   - Log every step for observability

3. pg_cron schedule: */5 * * * * calling the edge function

CONSTRAINTS:
- Do NOT modify 002_transfers.sql, 006_payout_release.sql, stripe-webhook, confirm-and-release, or any existing RPC
- Follow exact same patterns as auto-finalize-auctions (edge function) and confirm-and-release (Stripe calls)
- Use stripePost() helper identical to confirm-and-release
- Use sendPush() helper identical to stripe-webhook
- Stripe refund: POST /v1/refunds with payment_intent (full refund, no amount param)
- Error handling: log and continue — one failed refund must not block others
- Idempotency: check stripe_refund_id before calling Stripe; SKIP LOCKED in RPC

TEST PLAN:
1. Create a transfer with expires_at in the past, status='pending'
2. Call the edge function manually
3. Verify: transfer.status='expired', transfer.expired_at IS NOT NULL
4. Verify: payment.status='refunded', payment.refunded_at IS NOT NULL, payment.stripe_refund_id starts with 're_'
5. Verify: push notifications sent to buyer and seller
6. Call again — verify idempotent (0 expired, 0 refunded)
```

---

## Summary

The codebase is **very well prepared** for Day 2. The schema already has `expires_at`, the `'expired'` status value, the `'refunded'` payment status, and the `refunded_at` timestamp. The proven `auto-finalize-auctions` pattern provides an exact template to follow. The implementation requires:

- **1 migration** (2 columns + 1 index)
- **1 RPC** (~25 lines of PL/pgSQL)
- **1 edge function** (~150 lines of TypeScript)
- **1 cron entry**

Zero changes to any existing Day 1 code.

---

STEP COMPLETE — WAITING FOR NEXT RUN
