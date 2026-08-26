# Day 5 — Manual Refund & Manual Payout Release Playbook

**Version:** 1.0 — Private Beta
**Date:** 2026-04-01
**Tools:** Stripe Dashboard + Supabase SQL Editor

---

## PART 1 — Manual Refund Playbook (Buyer-Win)

Use this when admin rules in the buyer's favor and the buyer needs their money back.

### Prerequisites

- Transfer is in `disputed` or `expired` status
- Payment is in `succeeded` status
- `payout_released_at IS NULL` on the transfer (payout has NOT been sent to seller)

### Step 1 — Locate the Stripe PaymentIntent

Run in Supabase SQL Editor:

```sql
SELECT p.stripe_payment_intent_id, p.amount, p.service_fee, p.total, p.status,
       t.id AS transfer_id, t.status AS transfer_status, t.payout_released_at
  FROM payments p
  JOIN transfers t ON t.payment_id = p.id
 WHERE t.id = '<transfer_id>';
```

**Safety check:** Confirm `payout_released_at IS NULL`. If the payout was already released, you cannot do a simple refund — you must claw back the Connect transfer first (see Emergency section below).

Copy the `stripe_payment_intent_id` (starts with `pi_`).

### Step 2 — Refund in Stripe Dashboard

1. Go to **Stripe Dashboard** -> **Payments**
2. Search for the `pi_xxx` PaymentIntent ID
3. Click the payment -> click **Refund**
4. Select **Full refund**
5. Reason: select "Requested by customer" or "Fraudulent" as appropriate
6. Click **Refund**
7. Wait for status to show **Refunded**
8. Copy the Refund ID (starts with `re_`)

### Step 3 — Update Supabase Records

Run these in order:

```sql
-- 3a. Mark payment as refunded
UPDATE payments
   SET status      = 'refunded',
       refunded_at = now()
 WHERE stripe_payment_intent_id = 'pi_xxx'
   AND status = 'succeeded'
 RETURNING id, status, refunded_at;

-- 3b. Close out the transfer
UPDATE transfers
   SET status = 'expired'
 WHERE id = '<transfer_id>'
   AND status IN ('disputed', 'seller_sent', 'pending')
 RETURNING id, status;

-- 3c. Re-activate the listing so it can be relisted
UPDATE listings
   SET status         = 'active',
       reserved_by    = NULL,
       reserved_until = NULL,
       sold_at        = NULL
 WHERE id = '<listing_id>'
 RETURNING id, status;
```

### Step 4 — Verify the Refund

Run verification query:

```sql
SELECT p.id AS payment_id, p.status AS payment_status, p.refunded_at,
       t.id AS transfer_id, t.status AS transfer_status, t.payout_released_at
  FROM payments p
  JOIN transfers t ON t.payment_id = p.id
 WHERE t.id = '<transfer_id>';
```

**Expected result:**
- `payment_status = 'refunded'`
- `refunded_at IS NOT NULL`
- `transfer_status = 'expired'`
- `payout_released_at IS NULL`

Also confirm in Stripe Dashboard that the refund shows status `succeeded`.

---

## PART 2 — Manual Payout Release Playbook (Seller-Win)

Use this when admin rules in the seller's favor and the seller needs to get paid.

### Prerequisites

- Transfer is in `disputed` status (or `buyer_confirmed` if auto-release failed)
- Payment is in `succeeded` status
- `payout_released_at IS NULL` (payout not yet sent)
- Seller has a valid `stripe_connect_id`

### Step 1 — Gather Required Data

```sql
SELECT t.id AS transfer_id, t.status AS transfer_status, t.seller_id,
       t.payout_released_at,
       p.stripe_payment_intent_id, p.amount, p.service_fee, p.total, p.status AS payment_status,
       pr.stripe_connect_id, pr.display_name AS seller_name
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN profiles pr ON pr.id = t.seller_id
 WHERE t.id = '<transfer_id>';
```

**Safety checks:**
- `payment_status = 'succeeded'`
- `payout_released_at IS NULL`
- `stripe_connect_id` is present (starts with `acct_`)

The payout amount is `p.amount` (the listing price, excluding the service fee that SnatchIt keeps).

### Step 2 — Create the Stripe Transfer

**Option A — Stripe Dashboard:**

1. Go to **Stripe Dashboard** -> **Connect** -> **Transfers**
2. Click **Create transfer**
3. Destination: paste the seller's `acct_xxx` Connect account ID
4. Amount: enter the `amount` value from Step 1 (in cents, convert to dollars for the UI)
5. Source transaction: paste the `pi_xxx` PaymentIntent ID
6. Click **Create**
7. Copy the Transfer ID (starts with `tr_`)

**Option B — Stripe CLI (if you have API access):**

```bash
stripe transfers create \
  --amount <amount_in_cents> \
  --currency usd \
  --destination <acct_xxx> \
  --source-transaction <pi_xxx>
```

### Step 3 — Update Supabase Records

```sql
-- 3a. Record the payout on the transfer
UPDATE transfers
   SET status              = 'buyer_confirmed',
       payout_released_at  = now(),
       stripe_transfer_id  = 'tr_xxx'
 WHERE id = '<transfer_id>'
   AND payout_released_at IS NULL
 RETURNING id, status, payout_released_at, stripe_transfer_id;
```

Note: We set status to `buyer_confirmed` because that is the terminal "seller gets paid" state in the current schema. The dispute is resolved by virtue of the payout being released.

### Step 4 — Verify the Payout

```sql
SELECT t.id, t.status, t.payout_released_at, t.stripe_transfer_id,
       p.status AS payment_status
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
 WHERE t.id = '<transfer_id>';
```

**Expected result:**
- `status = 'buyer_confirmed'`
- `payout_released_at IS NOT NULL`
- `stripe_transfer_id = 'tr_xxx'`
- `payment_status = 'succeeded'`

Also confirm in Stripe Dashboard: **Connect** -> **Transfers** -> search for `tr_xxx` -> status should be `paid`.

---

## EMERGENCY — Refund After Payout Already Released

If `payout_released_at IS NOT NULL` but you still need to refund the buyer:

1. **Reverse the Stripe Transfer first:** In Stripe Dashboard -> Connect -> Transfers -> find the `tr_xxx` -> click **Reverse transfer** (this claws back funds from the seller's Connect account)
2. **Then refund the PaymentIntent** as described in Part 1
3. **Update DB:**

```sql
UPDATE transfers
   SET status              = 'expired',
       payout_released_at  = NULL,
       stripe_transfer_id  = NULL
 WHERE id = '<transfer_id>';

UPDATE payments
   SET status      = 'refunded',
       refunded_at = now()
 WHERE id = '<payment_id>';
```

This is a rare edge case. Document it in your incident log if it happens.

---

## Quick Reference — Status Transitions

| Scenario | Transfer Status | Payment Status | Payout |
|----------|----------------|----------------|--------|
| Buyer-win refund | `expired` | `refunded` | NULL |
| Seller-win payout | `buyer_confirmed` | `succeeded` | `tr_xxx` |
| Emergency reversal | `expired` | `refunded` | cleared |

---

STEP COMPLETE — WAITING FOR NEXT RUN
