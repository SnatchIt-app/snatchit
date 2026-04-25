# Day 6 — End-to-End Testing Pack

**Version:** 1.0
**Date:** 2026-04-01
**Scope:** Private beta — 9 test scenarios
**Tools:** SnatchIt app (iOS TestFlight), Stripe Dashboard, Supabase SQL Editor
**Prerequisite:** Days 1–5 complete. All edge functions deployed. Cron jobs active.

---

## SECTION 1 — Master Test Matrix

| # | Scenario | Trigger | Expected Final Transfer Status | Expected Final Payment Status | Payout Created? | Refund Issued? | Push Notifications |
|---|----------|---------|-------------------------------|-------------------------------|-----------------|----------------|--------------------|
| 1 | Happy path | Buyer confirms receipt | `buyer_confirmed` | `succeeded` | Yes — via `confirm-and-release` | No | Buyer: "Tickets received", Seller: "Payout released" |
| 2 | Seller ghost (expiry) | Seller never marks sent; `expires_at` passes | `expired` | `refunded` | No | Yes — full refund | Buyer: "Refund processed", Seller: "Transfer expired" |
| 3 | Buyer ghost (auto-release) | Buyer never confirms; `auto_release_at` passes | `auto_released` | `succeeded` | Yes — via cron Phase 2 | No | Seller: "Payout released", Buyer: "Transfer auto-confirmed" |
| 4 | Buyer dispute | Buyer disputes after seller_sent | `disputed` | `succeeded` (frozen) | No — frozen | No — frozen | None (admin handles) |
| 5 | Double-sale prevention | Second buyer attempts purchase on same listing | N/A — blocked | N/A — blocked | N/A | N/A | None |
| 6 | Missing/late transfer visibility | Payment succeeds but transfer row missing on first load | `pending` (recovered) | `succeeded` | Not yet | No | None (recovery is silent) |
| 7 | Seller missing payout setup | Seller has no `stripe_connect_id` | `buyer_confirmed` (payout fails) | `succeeded` | No — fails gracefully | No | Error logged; admin alerted |
| 8 | confirm-payment soft-fail | Payment succeeded but `confirm-payment` edge function errors | `pending` (webhook fallback) | `succeeded` | Not yet | No | Standard purchase notifications |
| 9 | Duplicate webhook / race | Two `payment_intent.succeeded` events arrive | Single transfer row | `succeeded` (single row) | Not duplicated | No | Single notification set |

---

## SECTION 2 — Step-by-Step Test Scripts

---

### TEST 1: Happy Path

**Preconditions:**
- Seller account with valid `stripe_connect_id` (verify in Supabase: `profiles.stripe_connect_id IS NOT NULL`)
- Seller has an active listing (status = `reserved` for buy_now, or auction ended with winner)
- Buyer account with valid payment method on file
- Both users have push notification tokens registered

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 1.1 | Buyer | Open listing → tap "Buy Now" → complete PaymentSheet | Payment succeeds. App shows "Payment successful" screen. Listing screen updates. |
| 1.2 | — | Wait 5 seconds | `stripe-webhook` fires `payment_intent.succeeded`. Transfer row created with `status = 'pending'`, `expires_at = now() + 24h`. Listing status → `sold`. |
| 1.3 | Seller | Open app → navigate to sold listing → tap "Mark as Sent" | Transfer status → `seller_sent`. `seller_sent_at` set. `auto_release_at` set to `now() + 72h`. Buyer sees "Seller has sent your tickets". |
| 1.4 | Buyer | Open app → navigate to purchased listing → tap "Confirm Received" | App calls `confirm-and-release`. Transfer → `buyer_confirmed`. Stripe Transfer created to seller's Connect account. `payout_released_at` set. `stripe_transfer_id` populated. |
| 1.5 | — | Verify | Buyer sees confirmation. Seller sees "Payout released". |

**Expected DB State:**
- `transfers.status` = `buyer_confirmed`
- `transfers.seller_sent_at` IS NOT NULL
- `transfers.buyer_confirmed_at` IS NOT NULL
- `transfers.payout_released_at` IS NOT NULL
- `transfers.stripe_transfer_id` matches `tr_xxx` in Stripe
- `payments.status` = `succeeded`
- `listings.status` = `sold`

**Expected Stripe State:**
- PaymentIntent: `succeeded`
- Transfer: created, amount matches `payments.amount`
- Destination: seller's Connect account

**Expected Push Notifications:**
- Buyer receives: purchase confirmation, then "tickets received" confirmation
- Seller receives: sale notification, then "payout released" notification

---

### TEST 2: Seller Ghost (Expiry + Refund)

**Preconditions:**
- Same as Test 1 but seller will NOT act
- Cron job `enforce-transfer-expiry` running every 5 minutes
- For testing: optionally fast-forward `expires_at` via SQL

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 2.1 | Buyer | Complete purchase (same as 1.1–1.2) | Transfer created, `status = 'pending'`, `expires_at` = now + 24h |
| 2.2 | Admin | (Optional) Fast-forward expiry: `UPDATE transfers SET expires_at = now() - interval '1 minute' WHERE listing_id = '<id>';` | — |
| 2.3 | — | Wait for cron (up to 5 min) | `enforce_transfer_expiry()` RPC fires. Transfer → `expired`. `expired_at` set. |
| 2.4 | — | Cron Phase 1 continues | Stripe refund issued. `payments.status` → `refunded`. `payments.refunded_at` set. `payments.stripe_refund_id` populated. |
| 2.5 | Buyer | Open app | Sees "Refund processed" notification. Transfer shows expired state. |
| 2.6 | Seller | Open app | Sees "Transfer expired" notification. |

**Expected DB State:**
- `transfers.status` = `expired`
- `transfers.expired_at` IS NOT NULL
- `transfers.seller_sent_at` IS NULL
- `payments.status` = `refunded`
- `payments.refunded_at` IS NOT NULL
- `payments.stripe_refund_id` = `re_xxx`

**Expected Stripe State:**
- PaymentIntent: `succeeded` (original charge)
- Refund: created, full amount, `re_xxx` matches DB

**Expected Push Notifications:**
- Buyer: "Your refund has been processed"
- Seller: "Your transfer has expired"

---

### TEST 3: Buyer Ghost (Auto-Release)

**Preconditions:**
- Same as Test 1 through step 1.3 (seller has marked sent)
- Buyer will NOT confirm
- Cron job running every 5 min
- For testing: optionally fast-forward `auto_release_at`

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 3.1 | Buyer + Seller | Complete purchase + seller marks sent (steps 1.1–1.3) | Transfer = `seller_sent`, `auto_release_at` = now + 72h |
| 3.2 | Admin | (Optional) Fast-forward: `UPDATE transfers SET auto_release_at = now() - interval '1 minute' WHERE listing_id = '<id>';` | — |
| 3.3 | — | Wait for cron (up to 5 min) | `enforce_auto_release()` RPC fires. Transfer → `auto_released`. Stripe Transfer created. |
| 3.4 | Seller | Open app | Sees "Payout released" notification. |
| 3.5 | Buyer | Open app | Sees "Transfer auto-confirmed" notification. |

**Expected DB State:**
- `transfers.status` = `auto_released`
- `transfers.payout_released_at` IS NOT NULL
- `transfers.stripe_transfer_id` = `tr_xxx`
- `transfers.buyer_confirmed_at` IS NULL
- `payments.status` = `succeeded` (unchanged)

**Expected Stripe State:**
- Transfer: created to seller's Connect account
- Amount matches `payments.amount`

**Expected Push Notifications:**
- Seller: "Payout released"
- Buyer: "Transfer auto-confirmed"

---

### TEST 4: Buyer Dispute

**Preconditions:**
- Same as Test 1 through step 1.3 (seller has marked sent)
- Transfer is in `seller_sent` state

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 4.1 | Buyer + Seller | Complete purchase + seller marks sent (steps 1.1–1.3) | Transfer = `seller_sent` |
| 4.2 | Buyer | Open app → navigate to transfer → tap "Dispute" | App calls `buyer_dispute_transfer` RPC. Transfer → `disputed`. `disputed_at` set. |
| 4.3 | — | Verify cron does NOT auto-release | Cron skips this transfer because status ≠ `seller_sent`. |
| 4.4 | — | Verify buyer cannot confirm | `confirm-and-release` rejects because status ≠ `seller_sent`. |
| 4.5 | — | Verify seller cannot re-send | `mark_transfer_sent` rejects because status ≠ `pending`. |

**Expected DB State:**
- `transfers.status` = `disputed`
- `transfers.disputed_at` IS NOT NULL
- `transfers.payout_released_at` IS NULL
- `transfers.stripe_transfer_id` IS NULL
- `payments.status` = `succeeded` (frozen — no refund, no payout)

**Expected Stripe State:**
- PaymentIntent: `succeeded` (funds held)
- No Transfer created
- No Refund created

**Expected Push Notifications:**
- None automatically. Admin handles dispute via Day 5 SOP.

---

### TEST 5: Double-Sale Prevention

**Preconditions:**
- One active listing (buy_now, status = `reserved`)
- Two buyer accounts (Buyer A and Buyer B)

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 5.1 | Buyer A | Complete purchase → payment succeeds | Listing → `sold`. Payment → `succeeded`. Transfer created. |
| 5.2 | Buyer B | Attempt to open listing and purchase | `create-payment-intent` rejects: listing status ≠ `reserved`. Error shown to Buyer B. |
| 5.3 | — | Verify via SQL | Only ONE payment with `status = 'succeeded'` for this `listing_id`. Only ONE transfer row. UNIQUE constraint on `transfers.listing_id` enforced. |

**Expected DB State:**
- Exactly 1 row in `payments` with `status = 'succeeded'` for the listing
- Exactly 1 row in `transfers` for the listing
- UNIQUE index on `payments(listing_id) WHERE status = 'succeeded'` holds

**Expected Stripe State:**
- Only one PaymentIntent created and succeeded for this listing

**Expected Push Notifications:**
- Buyer A: purchase confirmation
- Buyer B: none (blocked before payment)

---

### TEST 6: Missing/Late Transfer Visibility Recovery

**Preconditions:**
- Simulate: payment succeeds but transfer row is missing (e.g., `confirm-payment` failed and webhook hasn't fired yet, or manually delete transfer row for testing)

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 6.1 | Buyer | Complete purchase | Payment succeeds in Stripe |
| 6.2 | Admin | Delete transfer row: `DELETE FROM transfers WHERE listing_id = '<id>';` (simulates missing row) | — |
| 6.3 | Buyer | Navigate to purchased listing in app | App calls `ensure_transfer_exists` RPC. Transfer row re-created with `status = 'pending'`. Listing shows correct transfer state. |
| 6.4 | — | Verify | Transfer row exists. Payment linked. Listing displays correctly. |

**Expected DB State:**
- `transfers` row re-created with correct `listing_id`, `payment_id`, `buyer_id`, `seller_id`
- `transfers.status` = `pending`
- `payments.status` = `succeeded`

**Expected Stripe State:**
- No change — PaymentIntent still `succeeded`

**Expected Push Notifications:**
- None (recovery is silent)

---

### TEST 7: Seller With Missing Payout Setup

**Preconditions:**
- Seller account with `stripe_connect_id = NULL` in profiles
- Listing exists, buyer completes purchase, seller marks sent

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 7.1 | Setup | Ensure seller has `stripe_connect_id = NULL` | — |
| 7.2 | Buyer | Complete purchase → Seller marks sent → Buyer confirms received | `confirm-and-release` attempts Stripe Transfer |
| 7.3 | — | Edge function looks up seller's Connect account | `stripe_connect_id` is NULL. Edge function logs error. Transfer marked `buyer_confirmed` but payout NOT released. |
| 7.4 | Admin | Check logs / DB | `transfers.payout_released_at` IS NULL. `transfers.stripe_transfer_id` IS NULL. Transfer status = `buyer_confirmed`. |
| 7.5 | Admin | Fix seller's Connect account, then manually trigger payout per Day 5 SOP | Payout created manually via Stripe Dashboard or admin SQL. |

**Expected DB State:**
- `transfers.status` = `buyer_confirmed`
- `transfers.payout_released_at` IS NULL
- `transfers.stripe_transfer_id` IS NULL
- `payments.status` = `succeeded`

**Expected Stripe State:**
- PaymentIntent: `succeeded`
- No Transfer created (seller has no Connect account)

**Expected Push Notifications:**
- Standard buyer/seller notifications up to confirmation
- No "payout released" notification (payout failed)

---

### TEST 8: Payment Succeeded but confirm-payment Soft-Fails

**Preconditions:**
- Working payment flow
- Simulate `confirm-payment` failure (e.g., temporarily break the endpoint, or test natural race condition)

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 8.1 | Admin | Temporarily disable `confirm-payment` edge function (or add artificial failure) | — |
| 8.2 | Buyer | Complete PaymentSheet checkout | Payment succeeds in Stripe. `confirm-payment` returns 200 but does NOT create transfer (simulated failure). |
| 8.3 | — | Wait for Stripe webhook | `stripe-webhook` receives `payment_intent.succeeded`. Webhook handler detects payment already processed OR processes it. Transfer row created as fallback. |
| 8.4 | — | Verify | Transfer row exists. `status = 'pending'`. No duplicate rows. |
| 8.5 | Admin | Re-enable `confirm-payment` | — |

**Expected DB State:**
- Exactly 1 transfer row (created by webhook fallback)
- `payments.status` = `succeeded`
- `transfers.status` = `pending`

**Expected Stripe State:**
- Single PaymentIntent, `succeeded`

**Expected Push Notifications:**
- Standard purchase notifications (from webhook path)

---

### TEST 9: Duplicate Webhook / Race Condition

**Preconditions:**
- Working payment flow
- Stripe test mode: can replay webhooks from Stripe Dashboard

**Steps:**

| Step | Actor | Action | Expected App Behavior |
|------|-------|--------|-----------------------|
| 9.1 | Buyer | Complete purchase normally | Payment succeeds. Transfer created. |
| 9.2 | Admin | In Stripe Dashboard → Webhooks → find the `payment_intent.succeeded` event → click "Resend" | Duplicate webhook fires. |
| 9.3 | — | Verify | Webhook handler detects payment already `succeeded` (`.neq('status', 'succeeded')` guard). No duplicate payment update. Transfer UNIQUE constraint prevents duplicate row. |
| 9.4 | — | Check DB | Still exactly 1 payment row with `status = 'succeeded'`. Still exactly 1 transfer row. No duplicate notifications. |

**Expected DB State:**
- 1 payment row, `status = 'succeeded'`
- 1 transfer row (UNIQUE on `listing_id` and `payment_id`)

**Expected Stripe State:**
- Single PaymentIntent (unchanged by replay)

**Expected Push Notifications:**
- Only original set — no duplicates from replay

---

## SECTION 3 — SQL Verification Pack

> See separate file: `DAY6_SQL_VERIFICATION_PACK.sql`

---

## SECTION 4 — Pass/Fail Checklist

### Test 1: Happy Path
- [ ] Payment succeeds and `payments.status = 'succeeded'`
- [ ] Listing status → `sold`
- [ ] Transfer created with `status = 'pending'`
- [ ] Seller marks sent → `status = 'seller_sent'`, `seller_sent_at` set, `auto_release_at` set
- [ ] Buyer confirms → `status = 'buyer_confirmed'`, `buyer_confirmed_at` set
- [ ] Stripe Transfer created → `stripe_transfer_id` populated, `payout_released_at` set
- [ ] Stripe Transfer amount matches `payments.amount`
- [ ] Buyer push notification: purchase confirmed
- [ ] Seller push notification: payout released

### Test 2: Seller Ghost (Expiry + Refund)
- [ ] Transfer created with `status = 'pending'`
- [ ] After expiry: `status = 'expired'`, `expired_at` set
- [ ] Refund issued: `payments.status = 'refunded'`, `refunded_at` set
- [ ] `stripe_refund_id` populated and matches Stripe Dashboard
- [ ] Refund amount matches original charge
- [ ] Buyer push: "Refund processed"
- [ ] Seller push: "Transfer expired"
- [ ] No Stripe Transfer created

### Test 3: Buyer Ghost (Auto-Release)
- [ ] Transfer in `seller_sent` state with `auto_release_at` set
- [ ] After auto-release: `status = 'auto_released'`
- [ ] Stripe Transfer created → `stripe_transfer_id` populated, `payout_released_at` set
- [ ] `buyer_confirmed_at` IS NULL (buyer never confirmed)
- [ ] Seller push: "Payout released"
- [ ] Buyer push: "Transfer auto-confirmed"
- [ ] No refund issued

### Test 4: Buyer Dispute
- [ ] Transfer in `seller_sent` → `disputed` after buyer action
- [ ] `disputed_at` IS NOT NULL
- [ ] `payout_released_at` IS NULL (frozen)
- [ ] `stripe_transfer_id` IS NULL (no payout)
- [ ] Cron does NOT auto-release this transfer
- [ ] Buyer cannot confirm after dispute
- [ ] Seller cannot re-send after dispute
- [ ] `payments.status` remains `succeeded` (funds held)

### Test 5: Double-Sale Prevention
- [ ] First buyer: payment succeeds, transfer created
- [ ] Second buyer: `create-payment-intent` rejects (listing not in `reserved` state)
- [ ] Only 1 succeeded payment row for listing
- [ ] Only 1 transfer row for listing
- [ ] UNIQUE constraints hold

### Test 6: Missing Transfer Recovery
- [ ] After deleting transfer row, buyer navigates to listing
- [ ] `ensure_transfer_exists` re-creates transfer row
- [ ] Transfer linked to correct payment, buyer, seller
- [ ] No duplicate rows created
- [ ] App displays correctly

### Test 7: Seller Missing Payout Setup
- [ ] Buyer confirms receipt successfully
- [ ] `confirm-and-release` fails on Stripe Transfer (no Connect account)
- [ ] `transfers.status = 'buyer_confirmed'`
- [ ] `payout_released_at` IS NULL
- [ ] `stripe_transfer_id` IS NULL
- [ ] Error logged in edge function logs
- [ ] Admin can manually fix and pay out per Day 5 SOP

### Test 8: confirm-payment Soft-Fail
- [ ] Payment succeeds in Stripe
- [ ] `confirm-payment` endpoint fails/errors
- [ ] `stripe-webhook` creates transfer as fallback
- [ ] Exactly 1 transfer row (no duplicates)
- [ ] `payments.status = 'succeeded'`
- [ ] App behaves normally after webhook recovery

### Test 9: Duplicate Webhook / Race
- [ ] First webhook: processes normally
- [ ] Replayed webhook: no duplicate payment update
- [ ] Still exactly 1 transfer row
- [ ] No duplicate push notifications
- [ ] `.neq('status', 'succeeded')` guard works
- [ ] UNIQUE constraints prevent duplicate inserts

---

## SECTION 5 — Bug Logging Template

> See separate file: `DAY6_BUG_LOG_TEMPLATE.md`

---

## SECTION 6 — Recommended Test Execution Order

1. **Test 1** (Happy Path) — establishes baseline
2. **Test 5** (Double-Sale) — run immediately after Test 1 using same listing
3. **Test 2** (Seller Ghost) — needs fresh listing
4. **Test 3** (Buyer Ghost) — needs fresh listing
5. **Test 4** (Dispute) — needs fresh listing
6. **Test 8** (confirm-payment soft-fail) — needs endpoint manipulation
7. **Test 9** (Duplicate webhook) — uses Stripe Dashboard replay
8. **Test 6** (Missing transfer recovery) — destructive DB test, run on isolated listing
9. **Test 7** (Missing payout setup) — needs seller account modification

**Estimated time:** 2–3 hours for full suite (including cron wait times).

**Tip:** For Tests 2 and 3, use the SQL fast-forward commands to avoid waiting 24h / 72h. Cron runs every 5 minutes, so max wait after fast-forward is 5 minutes.
