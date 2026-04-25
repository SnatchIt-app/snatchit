# Day 2 — Transfer Expiry + Auto-Refund: Implementation Complete

**Date:** 2026-03-31
**Status:** IMPLEMENTED — ready to deploy

---

## SECTION 1 — Files Created

| # | File | Type | Lines | Purpose |
|---|------|------|-------|---------|
| 1 | `supabase/migrations/007_transfer_expiry.sql` | SQL Migration | 95 | Adds `expired_at` column to transfers, `stripe_refund_id` column to payments, partial index, and `enforce_transfer_expiry()` RPC |
| 2 | `supabase/functions/enforce-transfer-expiry/index.ts` | Edge Function | 215 | Cron-triggered: calls RPC → Stripe refund → DB update → push notifications |

### Existing Files Modified

**NONE.** Zero changes to any Day 1 code. Verified via `git status`.

```
Untouched Day 1 files:
  ✅ stripe-webhook/index.ts
  ✅ confirm-and-release/index.ts
  ✅ auto-finalize-auctions/index.ts
  ✅ 002_transfers.sql
  ✅ 006_payout_release.sql
  ✅ All existing RPCs
```

---

## SECTION 2 — Key Logic Summary

### Migration 007

**Schema additions (purely additive):**

| Table | Column | Type | Purpose |
|-------|--------|------|---------|
| `transfers` | `expired_at` | `timestamptz` (nullable) | When the expiry was enforced (distinct from `expires_at` deadline) |
| `payments` | `stripe_refund_id` | `text` (nullable) | Stripe Refund object ID (`re_xxx`) for idempotency/reconciliation |

**Index:** `idx_transfers_pending_expires` — partial index on `transfers(expires_at) WHERE status = 'pending'`

**RPC: `enforce_transfer_expiry()`**

- SECURITY DEFINER, `search_path = public`
- CTE selects `WHERE status = 'pending' AND expires_at < now()` with `FOR UPDATE SKIP LOCKED`
- Updates: `status = 'expired'`, `expired_at = now()`
- Returns: `(transfer_id, payment_id, listing_id, buyer_id, seller_id)` as table
- Concurrent-safe: `SKIP LOCKED` prevents parallel cron runs from double-processing

### Edge Function: `enforce-transfer-expiry`

**Auth:** Service-role key check (identical pattern to `auto-finalize-auctions`)

**Flow per expired transfer:**

```
1. Look up payments.stripe_payment_intent_id
2. Skip if payments.status = 'refunded' OR stripe_refund_id IS NOT NULL (idempotent)
3. POST /v1/refunds { payment_intent: pi_xxx } (full refund, no amount param)
4. UPDATE payments SET status='refunded', refunded_at=now(), stripe_refund_id=re_xxx
5. Push → buyer: "Refund Processed — seller didn't send in time"
6. Push → seller: "Transfer Expired — buyer has been refunded"
```

**Error isolation:** Each transfer in try/catch. One failure does NOT block the batch.

**Response:** `{ expired: N, refunded: N, errors: N, timestamp: ISO }`

**Idempotency (3 layers):**

| Layer | Mechanism | Prevents |
|-------|-----------|----------|
| 1 | RPC `FOR UPDATE SKIP LOCKED` | Concurrent cron runs double-processing |
| 2 | `stripe_refund_id` / `status='refunded'` check | Re-refunding already-processed payments |
| 3 | Stripe API (full refund on same PI) | Duplicate Stripe refunds |

---

## SECTION 3 — Deployment Steps

### Step 1: Run Migration

Open Supabase Dashboard → SQL Editor → New Query. Copy and run entire contents of `007_transfer_expiry.sql`.

**Verify:**
```sql
-- Columns exist
SELECT column_name FROM information_schema.columns
 WHERE table_name = 'transfers' AND column_name = 'expired_at';

SELECT column_name FROM information_schema.columns
 WHERE table_name = 'payments' AND column_name = 'stripe_refund_id';

-- Index exists
SELECT indexname FROM pg_indexes
 WHERE tablename = 'transfers' AND indexname = 'idx_transfers_pending_expires';

-- RPC exists
SELECT proname FROM pg_proc
 WHERE proname = 'enforce_transfer_expiry' AND pronamespace = 'public'::regnamespace;
```

### Step 2: Deploy Edge Function

```bash
supabase functions deploy enforce-transfer-expiry --no-verify-jwt
```

`--no-verify-jwt` required because auth is manual service-role key check.

**Verify:**
```bash
curl -X POST "${SUPABASE_URL}/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json"
# Expected: { "expired": 0, "refunded": 0, "errors": 0, "timestamp": "..." }
```

### Step 3: Set Up Cron (every 5 minutes)

**Option A — pg_cron + pg_net:**
```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'enforce-transfer-expiry',
  '*/5 * * * *',
  $$
  select net.http_post(
    url    := '<your-supabase-url>/functions/v1/enforce-transfer-expiry',
    headers := jsonb_build_object(
      'Authorization', 'Bearer <your-service-role-key>',
      'Content-Type', 'application/json'
    ),
    body   := '{}'::jsonb
  );
  $$
);
```

**Option B — Supabase Dashboard:** Edge Functions → enforce-transfer-expiry → Schedule → `*/5 * * * *`

**Option C — External cron:** Any service that POSTs to the edge function URL with service-role key.

---

## SECTION 4 — Test Instructions

### 4A. RPC Unit Test (SQL Editor)

```sql
-- 1. Insert test transfer with expires_at in the past
INSERT INTO transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
VALUES ('<listing_id>', '<payment_id>', '<seller_id>', '<buyer_id>', 'mobile_transfer', 'pending', now() - interval '1 hour');

-- 2. Run RPC
SELECT * FROM enforce_transfer_expiry();
-- Expected: returns 1 row with the test transfer details

-- 3. Verify state
SELECT status, expired_at FROM transfers WHERE payment_id = '<payment_id>';
-- Expected: status='expired', expired_at IS NOT NULL

-- 4. Run again (idempotency)
SELECT * FROM enforce_transfer_expiry();
-- Expected: returns 0 rows
```

### 4B. Edge Function Integration Test

```bash
# 1. Set up test data: transfer with expires_at in the past, status='pending'
# 2. Call edge function
curl -X POST "${SUPABASE_URL}/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}"

# Expected: { "expired": 1, "refunded": 1, "errors": 0 }
# Verify in DB: transfer.status='expired', payment.status='refunded', payment.stripe_refund_id starts with 're_'
# Verify in Stripe Dashboard: refund appears on the original payment
# Verify push notifications sent

# 3. Call again
# Expected: { "expired": 0, "refunded": 0, "errors": 0 }
```

### 4C. Negative / Auth Tests

```bash
# Wrong auth → 401
curl -X POST "${SUPABASE_URL}/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer wrong_key"

# No expired transfers → clean zero response
```

### 4D. Day 1 Regression Check

After deploying, verify Day 1 happy path unchanged:

1. Buy listing → transfer created (pending, expires_at = now+24h) ✅
2. Seller taps "Mark as Sent" → status = seller_sent ✅
3. Buyer taps "Confirm Received" → status = buyer_confirmed + Stripe Transfer ✅
4. Verify: enforce-transfer-expiry does NOT touch seller_sent or buyer_confirmed transfers (only pending + past expires_at)

---

## Architecture Diagram

```
              ┌────────────────────────┐
              │       pg_cron          │
              │    every 5 minutes     │
              └──────────┬─────────────┘
                         │ POST
                         ▼
              ┌────────────────────────┐
              │ enforce-transfer-expiry│
              │    (edge function)     │
              └──────────┬─────────────┘
                         │ supabase.rpc()
                         ▼
              ┌────────────────────────┐
              │enforce_transfer_expiry │
              │   (PL/pgSQL RPC)       │
              │                        │
              │ WHERE status='pending' │
              │   AND expires_at<now() │
              │ FOR UPDATE SKIP LOCKED │
              │                        │
              │ SET status='expired'   │
              │     expired_at=now()   │
              │ RETURN affected rows   │
              └──────────┬─────────────┘
                         │ returns rows
                         ▼
              ┌────────────────────────┐
              │  For each expired:     │
              │  1. Lookup payment PI  │
              │  2. Skip if refunded   │
              │  3. Stripe /refunds    │
              │  4. Update payments DB │
              │  5. Push → buyer       │
              │  6. Push → seller      │
              └────────────────────────┘
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
