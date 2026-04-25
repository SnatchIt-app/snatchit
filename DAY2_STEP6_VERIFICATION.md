# Day 2 — Step 6: Verification Plan

**Date:** 2026-03-30
**Status:** COMPLETE

---

## Prerequisites

Before starting, confirm these are deployed:

```
✅ Migration 006_payout_release.sql applied (run in Supabase SQL editor)
✅ Edge function confirm-and-release deployed (supabase functions deploy confirm-and-release)
✅ Client build includes updated handleConfirmReceived (EAS build or Expo dev client)
✅ Stripe is in TEST mode (sk_test_ key in edge function env)
✅ Seller test account has completed Stripe Connect onboarding (stripe_connect_id set in profiles)
```

### Quick pre-check (SQL editor — 30 seconds)

```sql
-- Confirm new columns exist on transfers table
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'transfers'
   AND column_name IN ('payout_released_at', 'stripe_transfer_id');
-- Expected: 2 rows, both timestamptz/text, both YES (nullable)

-- Confirm seller test account has Connect ID
SELECT id, username, stripe_connect_id
  FROM profiles
 WHERE id = '<SELLER_USER_ID>';
-- Expected: stripe_connect_id = 'acct_...' (not null)
```

---

## Test Execution (5 minutes)

### Phase 1 — Purchase (Buyer device, ~1 minute)

1. Log in as **Buyer** on the app
2. Find an active test listing from the Seller
3. Tap **Buy Now** → complete checkout with Stripe test card `4242 4242 4242 4242` (any future exp, any CVC, any ZIP)
4. Wait for success confirmation in the app

### Phase 2 — Verify payment + no early payout (~1 minute)

Run in **Supabase SQL editor**:

```sql
-- 2a. Listing is sold
SELECT id, status, sold_at
  FROM listings
 WHERE id = '<LISTING_ID>';
-- EXPECTED: status = 'sold', sold_at = recent timestamp

-- 2b. Payment succeeded
SELECT id, status, amount, service_fee, total, paid_at
  FROM payments
 WHERE listing_id = '<LISTING_ID>';
-- EXPECTED: status = 'succeeded', paid_at = recent timestamp

-- 2c. Transfer row exists, payout NOT released
SELECT id, status, seller_id, buyer_id,
       buyer_confirmed_at, payout_released_at, stripe_transfer_id
  FROM transfers
 WHERE listing_id = '<LISTING_ID>';
-- EXPECTED:
--   status = 'pending'
--   buyer_confirmed_at = NULL
--   payout_released_at = NULL
--   stripe_transfer_id = NULL
```

Check **Stripe dashboard** (https://dashboard.stripe.com/test/payments):

```
→ Find the PaymentIntent for this purchase
→ Confirm status = "Succeeded"
→ Go to https://dashboard.stripe.com/test/transfers
→ Confirm NO transfer exists for this listing/amount
→ This proves: funds are held on platform, seller is NOT paid yet
```

### Phase 3 — Seller marks as sent (Seller device, ~30 seconds)

1. Log in as **Seller** on the app
2. Navigate to the sold listing
3. Tap **Mark as Sent**
4. Confirm success alert

Verify in SQL editor:

```sql
-- 3a. Transfer status advanced
SELECT id, status, seller_sent_at
  FROM transfers
 WHERE listing_id = '<LISTING_ID>';
-- EXPECTED: status = 'seller_sent', seller_sent_at = recent timestamp
--           payout_released_at still NULL
```

### Phase 4 — Buyer confirms receipt (Buyer device, ~1 minute)

1. Switch to **Buyer** device
2. Navigate to the sold listing
3. Tap **Confirm Received**
4. Wait for success alert: "Transfer complete. Enjoy the event! 🎉"

Verify in **SQL editor**:

```sql
-- 4a. Transfer fully confirmed + payout released
SELECT id, status, buyer_confirmed_at,
       payout_released_at, stripe_transfer_id
  FROM transfers
 WHERE listing_id = '<LISTING_ID>';
-- EXPECTED:
--   status = 'buyer_confirmed'
--   buyer_confirmed_at = recent timestamp
--   payout_released_at = recent timestamp (within seconds of buyer_confirmed_at)
--   stripe_transfer_id = 'tr_...' (Stripe Transfer ID, not null)
```

Check **Stripe dashboard**:

```
→ Go to https://dashboard.stripe.com/test/transfers
→ Find the Transfer with the ID from stripe_transfer_id above
→ Confirm:
    • Amount matches payments.amount (listing price, NOT total with service fee)
    • Destination = seller's Connect account (acct_...)
    • Status = "paid" or "pending" (depends on Connect account payout schedule)
    • Metadata contains transfer_id, payment_id, seller_id, source=confirm-and-release
```

### Phase 5 — Duplicate confirmation test (~30 seconds)

This proves re-confirmation does NOT create a second Stripe Transfer.

**Option A — via app (if button is still visible, e.g., after app restart):**
Navigate back to the listing, if the "Confirm Received" button somehow renders again, tap it. You should see the same success alert. No error.

**Option B — via curl (more reliable):**

```bash
# Get a fresh session token for the buyer
# Then call the edge function directly:

curl -X POST '<SUPABASE_URL>/functions/v1/confirm-and-release' \
  -H 'Authorization: Bearer <BUYER_ACCESS_TOKEN>' \
  -H 'Content-Type: application/json' \
  -d '{"transfer_id": "<TRANSFER_ID>"}'

# EXPECTED RESPONSE:
# {"success":true,"already_released":true}
#
# HTTP status: 200
```

Verify in **SQL editor**:

```sql
-- 5a. Only ONE Stripe Transfer ID exists (unchanged from Phase 4)
SELECT stripe_transfer_id, payout_released_at
  FROM transfers
 WHERE listing_id = '<LISTING_ID>';
-- EXPECTED: same stripe_transfer_id as before, same payout_released_at

-- 5b. Count payout releases — must be exactly 1
SELECT count(*)
  FROM transfers
 WHERE listing_id = '<LISTING_ID>'
   AND payout_released_at IS NOT NULL;
-- EXPECTED: 1
```

Check **Stripe dashboard**:

```
→ Go to https://dashboard.stripe.com/test/transfers
→ Confirm only ONE Transfer exists for this seller + amount combination
→ No duplicate Transfer was created by the re-confirmation
```

---

## Pass / Fail Criteria

| Check | Pass | Fail |
|---|---|---|
| Listing status = 'sold' after purchase | `status = 'sold'` | Any other status |
| Payment status = 'succeeded' | `status = 'succeeded'` | Any other status |
| Transfer row exists after purchase | Row present | No row |
| Transfer payout_released_at NULL before buyer confirms | `NULL` | Any timestamp |
| Transfer stripe_transfer_id NULL before buyer confirms | `NULL` | Any value |
| No Stripe Transfer before buyer confirms | 0 transfers for this amount/seller | Any transfer exists |
| Transfer status = 'buyer_confirmed' after confirm | `buyer_confirmed` | Any other status |
| payout_released_at set after confirm | Recent timestamp | NULL |
| stripe_transfer_id set after confirm | `tr_...` | NULL |
| Stripe Transfer exists in dashboard | Transfer found with matching ID | Not found |
| Stripe Transfer amount = payments.amount | Amounts match | Mismatch |
| Stripe Transfer destination = seller's Connect | Account matches | Mismatch |
| Re-confirmation returns success | `{"success":true,"already_released":true}` | Error |
| Re-confirmation does NOT create second Transfer | 1 Transfer in Stripe | 2+ Transfers |
| payout_released_at unchanged after re-confirm | Same timestamp | Different timestamp |

**All 15 checks must pass.**

---

## Edge Function Logs

If any step fails, check edge function logs:

```bash
supabase functions logs confirm-and-release --project-ref <PROJECT_REF>
```

Key log messages to look for:
- `confirm-and-release: creating Stripe Transfer` — payout being sent
- `confirm-and-release: payout released successfully` — happy path
- `confirm-and-release: payout already released, returning success` — idempotent retry
- `confirm-and-release: Stripe Transfer failed` — Stripe error (check seller Connect account status)
- `confirm-and-release: race condition` — duplicate detected (should not occur in manual testing)

---

## Cleanup / Rollback Notes

**Test data cleanup (optional — test mode only):**

```sql
-- Reset transfer for re-testing (TEST ENVIRONMENT ONLY)
UPDATE transfers
   SET status = 'seller_sent',
       buyer_confirmed_at = NULL,
       payout_released_at = NULL,
       stripe_transfer_id = NULL
 WHERE listing_id = '<LISTING_ID>';

-- NOTE: This does NOT reverse the Stripe Transfer.
-- In test mode, Stripe test transfers are harmless.
-- In production, NEVER run this — it would desync DB from Stripe.
```

**Rollback if Day 2 code must be reverted:**

1. Revert `ListingDetailScreen.tsx` → restore direct `supabase.rpc('confirm_transfer_received')` call
2. The migration columns (`payout_released_at`, `stripe_transfer_id`) are harmless to leave — they're nullable and unread by any other code
3. The `confirm-and-release` edge function can be left deployed (nothing calls it if client is reverted) or removed via `supabase functions delete confirm-and-release`
4. No other systems are affected — all existing code was untouched

---

STEP COMPLETE — DAY 2 COMPLETE
