# Day 1 — V1 Trust Architecture Audit Report

**Date:** 2026-03-30
**Goal:** Remove immediate seller payout from the payment-success path WITHOUT breaking checkout/auth
**Status:** ALREADY COMPLETE — No code changes needed for Day 1

---

## SECTION 1 — Current Payout Path Audit

### Key Finding: Immediate seller payout is ALREADY removed

The `stripe-webhook/index.ts` (lines 201-213) already contains a deferred-payout block:

```
// PAYOUT DEFERRED (V1 buyer-protection architecture)
// The Stripe Transfer to the seller's Connect account is NOT created
// here. Funds remain in the SnatchIt platform Stripe balance until
// the buyer confirms receipt (or auto-release conditions are met).
// The release-payout function (to be built) will call
// stripe.transfers.create() at that time.
```

There is **zero** `stripe.transfers.create()` or equivalent Stripe Transfer API call anywhere in the entire codebase. I searched all `.ts`, `.tsx`, and `.sql` files.

### What happens today on payment success (stripe-webhook handler, lines 94-230):

| Step | What happens | File | Lines | Status |
|------|-------------|------|-------|--------|
| 1 | Payment row updated to `succeeded` | `stripe-webhook/index.ts` | 100-106 | Working |
| 2 | Idempotency check (skip if already processed) | `stripe-webhook/index.ts` | 104, 116-124 | Working |
| 3 | RPC `mark_listing_sold` or `complete_auction_payment` called | `stripe-webhook/index.ts` | 129-166 | Working |
| 4 | Transfer row inserted (`status: 'pending'`) | `stripe-webhook/index.ts` | 173-199 | Working |
| 5 | **PAYOUT DEFERRED** — no Stripe Transfer created | `stripe-webhook/index.ts` | 201-213 | Already deferred |
| 6 | Push notifications sent to buyer + seller | `stripe-webhook/index.ts` | 216-230 | Working |

### What MUST NOT be touched (all working correctly):

- `create-payment-intent/index.ts` — Creates Stripe PaymentIntent, records payment row (status: pending)
- `confirm-payment/index.ts` — Client-side confirmation (best-effort bookkeeping)
- `app/checkout/[id].tsx` — Checkout UI, Stripe PaymentSheet, mark_listing_sold/complete_auction_payment RPCs
- `src/lib/payments.ts` — Client-side payment helpers
- `supabase/migrations/002_transfers.sql` — Transfers table, mark_transfer_sent, confirm_transfer_received RPCs
- `supabase/migrations/003_payment_integrity.sql` — Unique constraints on transfers

### Parallel payment confirmation paths (both safe):

1. **Webhook path** (`stripe-webhook`): Stripe fires `payment_intent.succeeded` → webhook handler does all post-payment work (mark sold, create transfer, push notifications)
2. **Client path** (`checkout/[id].tsx`): After PaymentSheet succeeds → calls `confirmPaymentSuccess()` (best-effort DB update) → calls `mark_listing_sold` RPC directly

Both paths update payment status to `succeeded`. The webhook's idempotency guard (`.neq('status', 'succeeded')`) prevents double-processing. Neither path creates a Stripe Transfer to the seller.

---

## SECTION 2 — Minimal Day 1 Change

### Answer: No change needed

The Day 1 goal — "remove immediate seller payout from the current payment-success path" — is **already achieved**. The codebase never had a `stripe.transfers.create()` call in the webhook or anywhere else that would immediately pay out the seller.

### What remains working (everything):

- Checkout flow (buy_now + auction) — unchanged
- Payment creation via Stripe PaymentIntent — unchanged
- Payment status updates — unchanged
- Listing marked as sold — unchanged
- Transfer row created — unchanged
- Push notifications — unchanged
- Seller Connect account onboarding — unchanged

### Temporary state assessment:

The **absence of a Stripe Transfer** is sufficient to represent "payout not yet released." There is no `stripe_transfer_id` column on transfers or payments, and none is needed for Day 1.

The transfers table already has a `status` state machine: `pending → seller_sent → buyer_confirmed`. The payout release (Day 2+) will trigger on `buyer_confirmed` status or timeout logic.

---

## SECTION 3 — Exact Implementation Plan

**No implementation needed for Day 1.**

The codebase is already in the correct Day 1 state:

- No schema change needed
- No edge function change needed
- No client change needed
- No webhook redeploy needed

---

## SECTION 4 — What to Build Next (Day 2+)

Since Day 1 is done, here's what the next steps look like (DO NOT build these yet):

1. **`release-payout` edge function** — Called when buyer confirms receipt (`buyer_confirmed`) or auto-release timeout fires. This function will call `stripe.transfers.create()` to move funds from platform balance to seller's Connect account.

2. **`payout_status` tracking** — Either a new column on `transfers` or `payments` table, or a separate `payouts` table to track: `pending_release → released → failed`.

3. **Auto-release logic** — Cron or scheduled function that releases payout if buyer doesn't confirm within N days and no dispute is raised.

4. **Dispute flow** — Allow buyer or seller to raise a dispute, pausing payout release.

---

## SECTION 5 — Verification Steps (5-minute test)

Even though no code change is needed, here's how to verify the current state is correct:

### 1. Code verification (2 minutes)

```bash
# Verify NO stripe.transfers.create() exists anywhere
grep -r "stripe.transfers.create\|transfers/create\|/v1/transfers" supabase/functions/

# Verify the deferred payout comment exists in webhook
grep -A5 "PAYOUT DEFERRED" supabase/functions/stripe-webhook/index.ts

# Verify no destination/transfer_data on PaymentIntent creation
grep -n "destination\|transfer_data\|transfer_group" supabase/functions/create-payment-intent/index.ts
```

Expected: First grep returns nothing. Second grep shows the deferral comment. Third grep returns nothing (no automatic Stripe Connect destination routing).

### 2. Stripe Dashboard verification (2 minutes)

After a test purchase:

- Go to Stripe Dashboard → Payments → find the PaymentIntent
- Confirm: `status: succeeded`
- Confirm: **No associated Transfer** object (no "Transfer" line in the payment detail)
- Go to Connect → find seller's Express account → Confirm: **$0 balance / no pending payout**

### 3. Database verification (1 minute)

```sql
-- Payment succeeded
SELECT id, status, paid_at FROM payments WHERE stripe_payment_intent_id = '<PI_ID>';
-- Expected: status = 'succeeded', paid_at = timestamp

-- Listing sold
SELECT id, status FROM listings WHERE id = '<LISTING_ID>';
-- Expected: status = 'sold'

-- Transfer row created
SELECT id, status, seller_id, buyer_id FROM transfers WHERE listing_id = '<LISTING_ID>';
-- Expected: status = 'pending', correct seller/buyer IDs

-- NO payout/transfer to seller (nothing to check in DB — absence is the proof)
```

---

## Day 1 Execution Checklist

- [x] **Step 1: Audit current payout path** — COMPLETE. No immediate payout exists in the codebase.
- [x] **Step 2: Apply minimal code change** — NO CHANGE NEEDED. Already in correct state.
- [x] **Step 3: Deploy/redeploy** — NOTHING TO DEPLOY.
- [ ] **Step 4: Run verification test** — Run the verification commands above against a test purchase to confirm.

---

## Summary

The SnatchIt codebase is already in the correct Day 1 state for the V1 trust architecture. Funds are collected via Stripe PaymentIntent but no Stripe Transfer is created to move funds to the seller's Connect account. The money sits in the platform's Stripe balance until a `release-payout` function (to be built in Day 2+) explicitly creates the transfer.

**Next action:** Proceed to Day 2 planning — build the `release-payout` edge function that triggers on `buyer_confirmed` transfer status.
