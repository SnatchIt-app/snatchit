# Day 2 — Deployment + Manual Verification Guide

**Date:** 2026-03-31
**Prerequisite:** Day 1 fully working, Day 2 code files committed

---

## SECTION 1 — Deployment Order

```
Step 1: Pre-flight checks (read-only, zero risk)
Step 2: Run migration 007 (additive schema + RPC, zero risk)
Step 3: Verify migration landed (read-only queries)
Step 4: Deploy edge function (no cron yet — manual-only)
Step 5: Smoke test: auth rejection (wrong key)
Step 6: Smoke test: empty run (no expired transfers)
Step 7: Create synthetic test transfer with past expiry
Step 8: Manual trigger — verify full flow (expire + refund + push)
Step 9: Verify DB state matches expectations
Step 10: Verify Stripe Dashboard shows refund
Step 11: Idempotency test — call again, expect zero
Step 12: Day 1 regression — buy a ticket, confirm normal flow works
Step 13: ONLY AFTER ALL ABOVE PASS → enable cron
```

**Key principle:** Deploy in read-only mode first, test manually, enable cron last.

---

## SECTION 2 — Exact Commands

### Step 1: Pre-flight checks

Open **Supabase Dashboard → SQL Editor** and run:

```sql
-- Verify Day 1 baseline is intact
-- Should return: pending, seller_sent, buyer_confirmed, disputed, expired
SELECT unnest(string_to_array(
  (SELECT check_clause FROM information_schema.check_constraints
   WHERE constraint_name LIKE '%transfers_status_check%'
   LIMIT 1), ','
)) AS allowed_status;

-- Verify 'expired' is already in the CHECK constraint
-- If this returns rows, we're good
SELECT 1 WHERE EXISTS (
  SELECT 1 FROM information_schema.check_constraints
   WHERE constraint_name LIKE '%transfers_status_check%'
     AND check_clause LIKE '%expired%'
);

-- Verify payments already supports 'refunded'
SELECT 1 WHERE EXISTS (
  SELECT 1 FROM information_schema.check_constraints
   WHERE constraint_name LIKE '%payments_status_check%'
     AND check_clause LIKE '%refunded%'
);

-- Verify refunded_at column already exists
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'payments' AND column_name = 'refunded_at';

-- Verify expires_at column exists on transfers
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'transfers' AND column_name = 'expires_at';

-- Count current transfers by status (baseline snapshot)
SELECT status, count(*) FROM transfers GROUP BY status ORDER BY status;

-- Count current payments by status (baseline snapshot)
SELECT status, count(*) FROM payments GROUP BY status ORDER BY status;
```

**Expected:** All checks pass. Record the baseline counts.

---

### Step 2: Run migration 007

Copy the **entire contents** of `supabase/migrations/007_transfer_expiry.sql` into **SQL Editor** and execute.

**This is zero-risk because:**
- `ADD COLUMN IF NOT EXISTS` — no-ops if columns exist
- `CREATE INDEX IF NOT EXISTS` — no-op if index exists
- `CREATE OR REPLACE FUNCTION` — creates or updates RPC safely
- No existing data is modified
- No existing constraints, policies, or RPCs are touched

---

### Step 3: Verify migration landed

```sql
-- 3a. Verify expired_at column exists
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'transfers' AND column_name = 'expired_at';
-- Expected: expired_at | timestamp with time zone | YES

-- 3b. Verify stripe_refund_id column exists
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'payments' AND column_name = 'stripe_refund_id';
-- Expected: stripe_refund_id | text | YES

-- 3c. Verify partial index exists
SELECT indexname, indexdef
  FROM pg_indexes
 WHERE tablename = 'transfers' AND indexname = 'idx_transfers_pending_expires';
-- Expected: idx_transfers_pending_expires | CREATE INDEX ... ON ... (expires_at) WHERE status = 'pending'

-- 3d. Verify RPC exists and has correct signature
SELECT proname, pg_get_function_result(oid), pg_get_function_arguments(oid)
  FROM pg_proc
 WHERE proname = 'enforce_transfer_expiry'
   AND pronamespace = 'public'::regnamespace;
-- Expected: enforce_transfer_expiry | TABLE(transfer_id uuid, payment_id uuid, listing_id uuid, buyer_id uuid, seller_id uuid) | (no args)

-- 3e. Dry-run the RPC (should return 0 rows if no transfers are currently expired)
SELECT * FROM enforce_transfer_expiry();
-- Expected: 0 rows (or rows if you happen to have expired pending transfers already)
```

**STOP HERE if any check fails.** Do not proceed to edge function deployment.

---

### Step 4: Deploy edge function

```bash
# From the project root
supabase functions deploy enforce-transfer-expiry --no-verify-jwt
```

**Why `--no-verify-jwt`:** Auth is handled manually inside the function (service-role key check), identical to `auto-finalize-auctions`. Without this flag, Supabase's relay would reject the request before it reaches our code.

**No new env vars needed.** The function uses `STRIPE_SECRET_KEY`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY` — all already set for `confirm-and-release`.

---

### Step 5: Smoke test — auth rejection

```bash
# Should return 401 Unauthorized
curl -s -X POST \
  "https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer wrong_key_12345" \
  -H "Content-Type: application/json"
```

**Expected response:**
```json
{"error":"Unauthorized"}
```

---

### Step 6: Smoke test — empty run

```bash
# Should return 200 with zero counts
curl -s -X POST \
  "https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer <YOUR_SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json"
```

**Expected response:**
```json
{"expired":0,"refunded":0,"timestamp":"2026-03-31T..."}
```

**Also check:** Supabase Dashboard → Edge Functions → enforce-transfer-expiry → Logs. Should show:
```
enforce-transfer-expiry: no expired transfers found
```

---

### Step 7: Create synthetic test transfer

**IMPORTANT:** Use your Stripe **test mode** key. This creates a real-ish test scenario.

```sql
-- Find a succeeded payment to use as test data
-- (or use a specific one you know about from test mode)
SELECT p.id AS payment_id,
       p.stripe_payment_intent_id,
       p.listing_id,
       p.buyer_id,
       p.seller_id,
       p.status
  FROM payments p
 WHERE p.status = 'succeeded'
 ORDER BY p.created_at DESC
 LIMIT 5;
```

**If you have a succeeded test payment**, note its `payment_id`, `listing_id`, `buyer_id`, `seller_id`.

**If you DON'T have one** (fresh DB), you'll need to run through the Day 1 buy flow first to create one.

Then create the synthetic expired transfer:

```sql
-- Create a transfer that expired 1 hour ago
-- REPLACE the UUIDs below with real values from the query above
INSERT INTO transfers (
  listing_id, payment_id, seller_id, buyer_id,
  transfer_method, status, expires_at
) VALUES (
  '<LISTING_ID>',   -- from query above
  '<PAYMENT_ID>',   -- from query above
  '<SELLER_ID>',    -- from query above
  '<BUYER_ID>',     -- from query above
  'mobile_transfer',
  'pending',
  now() - interval '1 hour'   -- expired 1 hour ago
)
RETURNING id, status, expires_at;
```

**Record the returned transfer `id`** — you'll need it for verification.

**Note:** If there's a unique constraint on `listing_id` or `payment_id` in the transfers table, you'll need to use a listing/payment pair that doesn't already have a transfer. Check first:

```sql
SELECT t.id FROM transfers t WHERE t.payment_id = '<PAYMENT_ID>';
-- If this returns a row, that payment already has a transfer.
-- Either use a different payment, or delete the test transfer afterward.
```

---

### Step 8: Manual trigger — full flow test

```bash
curl -s -X POST \
  "https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/enforce-transfer-expiry" \
  -H "Authorization: Bearer <YOUR_SERVICE_ROLE_KEY>" \
  -H "Content-Type: application/json" | jq .
```

**Expected response:**
```json
{
  "expired": 1,
  "refunded": 1,
  "errors": 0,
  "timestamp": "2026-03-31T..."
}
```

**Check edge function logs** (Dashboard → Edge Functions → Logs):
```
enforce-transfer-expiry: found 1 expired transfer(s)
enforce-transfer-expiry: issuing Stripe refund: { transfer_id: "...", payment_id: "...", stripe_payment_intent_id: "pi_..." }
enforce-transfer-expiry: refund complete: { transfer_id: "...", payment_id: "...", stripe_refund_id: "re_...", buyer_id: "...", seller_id: "..." }
enforce-transfer-expiry: batch complete: { expired: 1, refunded: 1, errors: 0, timestamp: "..." }
```

---

## SECTION 3 — Manual Test Procedure (Post-Trigger Verification)

### DB Verification

After Step 8, run these queries in SQL Editor:

```sql
-- A. Transfer should be 'expired' with expired_at set
SELECT id, status, expires_at, expired_at, payout_released_at
  FROM transfers
 WHERE id = '<TRANSFER_ID_FROM_STEP_7>';
```

| Column | Expected |
|--------|----------|
| status | `expired` |
| expires_at | ~1 hour ago (the deadline) |
| expired_at | ~now (when enforcement ran) |
| payout_released_at | `NULL` (never paid out) |

```sql
-- B. Payment should be 'refunded' with stripe_refund_id set
SELECT id, status, refunded_at, stripe_refund_id, stripe_payment_intent_id
  FROM payments
 WHERE id = '<PAYMENT_ID_FROM_STEP_7>';
```

| Column | Expected |
|--------|----------|
| status | `refunded` |
| refunded_at | ~now |
| stripe_refund_id | starts with `re_` |
| stripe_payment_intent_id | starts with `pi_` (unchanged) |

```sql
-- C. No other transfers/payments were affected
-- Compare to baseline from Step 1
SELECT status, count(*) FROM transfers GROUP BY status ORDER BY status;
SELECT status, count(*) FROM payments GROUP BY status ORDER BY status;
```

**Expected:** Only 1 more `expired` transfer and 1 more `refunded` payment compared to baseline.

### Stripe Dashboard Verification

1. Go to **Stripe Dashboard → Payments** (make sure you're in test mode)
2. Find the payment with the `pi_` ID from the payment record
3. **Expected:** Shows "Refunded" status with a refund of the full amount
4. Click into the refund — metadata should show:
   - `transfer_id`: matches your test transfer
   - `reason`: `transfer_expired`
   - `source`: `enforce-transfer-expiry`

### Push Notification Verification

Check **Supabase Dashboard → Edge Functions → send-push → Logs** for two calls:
1. To buyer: "Refund Processed"
2. To seller: "Transfer Expired"

(If no push tokens exist for the test users, the send-push function will log that and return — this is fine.)

---

## SECTION 4 — Expected DB Results Summary

### After Step 6 (empty run):

| Table | Change | Expected |
|-------|--------|----------|
| transfers | No changes | All statuses unchanged |
| payments | No changes | All statuses unchanged |

### After Step 8 (with test transfer):

| Table | Row | Column | Before | After |
|-------|-----|--------|--------|-------|
| transfers | test row | status | `pending` | `expired` |
| transfers | test row | expired_at | `NULL` | `2026-03-31T...` |
| payments | test row | status | `succeeded` | `refunded` |
| payments | test row | refunded_at | `NULL` | `2026-03-31T...` |
| payments | test row | stripe_refund_id | `NULL` | `re_...` |

### After Step 11 (idempotency re-run):

```bash
curl -s -X POST ... | jq .
```
```json
{
  "expired": 0,
  "refunded": 0,
  "errors": 0,
  "timestamp": "2026-03-31T..."
}
```

No DB changes. No Stripe calls. Clean zero.

---

## SECTION 5 — When To Enable Cron

### Prerequisites checklist (ALL must pass):

```
[ ] Step 3 — Migration verified (columns, index, RPC exist)
[ ] Step 5 — Auth rejection works (401 on bad key)
[ ] Step 6 — Empty run returns clean zero
[ ] Step 8 — Manual trigger expires + refunds correctly
[ ] Step 9 — DB state matches expected results
[ ] Step 10 — Stripe Dashboard shows refund
[ ] Step 11 — Idempotency re-run returns zero
[ ] Step 12 — Day 1 regression (buy flow still works end-to-end)
```

### Enable cron ONLY after all boxes are checked

**Recommended schedule:** Every 5 minutes (`*/5 * * * *`)

**Safest option — Supabase Dashboard cron:**

Dashboard → Database → Extensions → Ensure `pg_cron` is enabled.

Then in SQL Editor:

```sql
-- Enable pg_net if not already (needed for HTTP calls from pg_cron)
create extension if not exists pg_net schema extensions;

-- Schedule the sweep every 5 minutes
select cron.schedule(
  'enforce-transfer-expiry',     -- job name
  '*/5 * * * *',                 -- every 5 minutes
  $$
  select net.http_post(
    url    := '<YOUR_SUPABASE_URL>/functions/v1/enforce-transfer-expiry',
    headers := '{"Authorization": "Bearer <YOUR_SERVICE_ROLE_KEY>", "Content-Type": "application/json"}'::jsonb,
    body   := '{}'::jsonb
  );
  $$
);
```

**Verify cron is registered:**
```sql
SELECT jobid, schedule, command FROM cron.job WHERE jobname = 'enforce-transfer-expiry';
```

**Monitor first few runs:**
```sql
-- Check cron execution history
SELECT jobid, runid, job_pid, status, return_message, start_time, end_time
  FROM cron.job_run_details
 WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'enforce-transfer-expiry')
 ORDER BY start_time DESC
 LIMIT 10;
```

Also monitor via Dashboard → Edge Functions → enforce-transfer-expiry → Logs.

### Emergency stop (if something goes wrong):

```sql
-- Disable the cron job immediately
select cron.unschedule('enforce-transfer-expiry');
```

This is instant and does not affect any in-flight processing (the edge function will complete its current run if one is active).

---

## Cleanup After Testing

If you created a synthetic test transfer in Step 7, clean it up:

```sql
-- Remove test transfer (only if you want to clean up)
-- DELETE FROM transfers WHERE id = '<TRANSFER_ID_FROM_STEP_7>';

-- Reset test payment back to 'succeeded' (only if this was a real test payment you want to reuse)
-- UPDATE payments SET status = 'succeeded', refunded_at = NULL, stripe_refund_id = NULL WHERE id = '<PAYMENT_ID>';
-- NOTE: The Stripe refund is permanent — the DB reset only affects your local state
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
