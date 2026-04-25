# Day 2 — Confirm-and-Release Recovery Plan

**Date:** 2026-03-31
**Status:** READY TO EXECUTE

---

## SECTION 1 — Confirmed Root Cause

Two missing prerequisites are blocking confirm-and-release:

**Blocker 1: Missing schema columns.** The production `transfers` table does not have `payout_released_at` or `stripe_transfer_id` columns. Migration 006 was never applied. The edge function SELECTs `payout_released_at` at step 5 (line 202) — PostgREST returns an error for the unknown column, the function hits the error path at line 206, and returns a 404 to the client.

**Blocker 2: Seller has no Stripe Connect account.** `profiles.stripe_connect_id` is NULL for the seller. Even if Blocker 1 is fixed, step 6 (line 252) would fail with "Seller payout account not set up." The seller must complete Stripe Connect onboarding before any payout can be routed to them.

Both blockers must be resolved. Neither is a code bug — migration 006 was written correctly, and the Connect onboarding flow exists. They simply haven't been executed against production.

---

## SECTION 2 — Exact Order of Operations

### Step 1 — Apply migration 006 (payout columns)

Run in **Supabase Dashboard → SQL Editor:**

```sql
alter table public.transfers
  add column if not exists payout_released_at  timestamptz,
  add column if not exists stripe_transfer_id  text;
```

Takes milliseconds. Zero downtime. `IF NOT EXISTS` makes it safe to run multiple times.

### Step 2 — Verify columns exist

Run in SQL Editor:

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'transfers'
  AND column_name IN ('payout_released_at', 'stripe_transfer_id');
```

**Must return exactly 2 rows:**

| column_name | data_type | is_nullable |
|---|---|---|
| payout_released_at | timestamp with time zone | YES |
| stripe_transfer_id | text | YES |

If 0 rows → Step 1 failed. Re-run it and check for errors.

### Step 3 — Complete seller Stripe Connect onboarding

1. Log in as the **seller** on the app
2. Navigate to **Settings → Payouts** (or wherever the "Set up payouts" button is)
3. Tap **Set up payouts** — this calls the `create-connect-account` edge function
4. Complete the Stripe Connect Express onboarding flow in the browser
5. Return to the app after onboarding completes

This creates a Stripe Express account (acct_xxx) and writes it to `profiles.stripe_connect_id`.

### Step 4 — Verify stripe_connect_id exists

Run in SQL Editor:

```sql
SELECT id, stripe_connect_id
FROM public.profiles
WHERE id = (
  SELECT seller_id FROM public.transfers
  WHERE id = '7141d7bc-19a3-4849-a481-fa1ee9139fdb'
);
```

**Must return:**

| id | stripe_connect_id |
|---|---|
| (seller uuid) | acct_... |

If `stripe_connect_id` is still NULL → onboarding didn't complete. Repeat Step 3.

### Step 5 — Retest confirm-and-release

1. Log in as the **buyer** on the app
2. Navigate to the listing (accff86d-4037-4a65-a6bd-c4c1f1a8315b)
3. Tap **Confirm Received**
4. Expected: success alert "Transfer complete. Enjoy the event!"

---

## SECTION 3 — SQL Verification for Each Step

### After Step 1+2 (columns exist):
```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'transfers'
  AND column_name IN ('payout_released_at', 'stripe_transfer_id');
-- MUST: 2 rows
```

### After Step 3+4 (Connect account set up):
```sql
SELECT id, stripe_connect_id
FROM public.profiles
WHERE id = (
  SELECT seller_id FROM public.transfers
  WHERE id = '7141d7bc-19a3-4849-a481-fa1ee9139fdb'
);
-- MUST: stripe_connect_id = 'acct_...'
```

### After Step 5 (confirmation + payout):
```sql
SELECT
  status,
  buyer_confirmed_at,
  payout_released_at,
  stripe_transfer_id
FROM public.transfers
WHERE id = '7141d7bc-19a3-4849-a481-fa1ee9139fdb';
-- MUST:
--   status = 'buyer_confirmed'
--   buyer_confirmed_at = recent timestamp
--   payout_released_at = recent timestamp
--   stripe_transfer_id = 'tr_...'
```

### Cross-check in Stripe Dashboard:
```
→ https://dashboard.stripe.com/test/transfers
→ Find the Transfer matching stripe_transfer_id from the query above
→ Verify:
    • Amount = payments.amount for this transfer's payment_id
    • Destination = seller's acct_... from Step 4
    • Status = paid or pending
```

---

## SECTION 4 — Exact Expected Result After Retest

| Check | Expected |
|---|---|
| Alert shown to buyer | "Transfer complete. Enjoy the event!" |
| transfers.status | buyer_confirmed |
| transfers.buyer_confirmed_at | Recent timestamp |
| transfers.payout_released_at | Recent timestamp (within seconds of buyer_confirmed_at) |
| transfers.stripe_transfer_id | tr_... (Stripe Transfer ID) |
| Stripe Dashboard: Transfer exists | Yes, matching ID |
| Stripe Dashboard: Transfer amount | Matches payments.amount (listing price in cents) |
| Stripe Dashboard: Transfer destination | Matches seller's acct_... |
| Re-tapping "Confirm Received" | Either button gone (state updated) or same success alert |
| Re-calling via curl | {"success":true,"already_released":true} |
| Second Stripe Transfer created | No — only one Transfer for this payment |

---

## SECTION 5 — Code Changes Needed Right Now

**None.** The code for migration 006 and the confirm-and-release edge function is already written and correct. The issue is purely operational — the migration hasn't been applied to production, and the seller hasn't completed Connect onboarding. No code changes are required.
