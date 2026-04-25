# Day 5 — Admin Dispute Resolution SOP

**Version:** 1.0 — Private Beta
**Date:** 2026-04-01
**Tools:** Stripe Dashboard + Supabase SQL Editor

---

## 1. Trigger — Buyer Reports an Issue

A buyer taps "Dispute" in the app. The system calls `buyer_dispute_transfer()`, which sets `transfers.status = 'disputed'` and `disputed_at = now()`. The admin discovers new disputes by running:

```sql
SELECT t.id, t.listing_id, t.buyer_id, t.seller_id, t.status, t.disputed_at,
       p.stripe_payment_intent_id, p.amount, p.total
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
 WHERE t.status = 'disputed'
 ORDER BY t.disputed_at DESC;
```

---

## 2. Admin Inspects State

For every disputed transfer, inspect the following four objects in order.

### 2a. Transfer record

```sql
SELECT * FROM transfers WHERE id = '<transfer_id>';
```

Verify: `status = 'disputed'`, `disputed_at IS NOT NULL`, `payout_released_at IS NULL` (payout must NOT have been released yet).

### 2b. Payment record

```sql
SELECT * FROM payments WHERE id = '<payment_id>';
```

Verify: `status = 'succeeded'`, `stripe_payment_intent_id` is present.

### 2c. Listing record

```sql
SELECT id, event_name, venue, event_date, ticket_type, quantity, seller_id, status
  FROM listings WHERE id = '<listing_id>';
```

### 2d. Stripe state

Open Stripe Dashboard -> Payments -> search by `stripe_payment_intent_id`. Confirm the PaymentIntent status is `succeeded` and no refund exists yet.

---

## 3. Admin Contacts Seller

Send a message to the seller (use the contact method on file — phone or email from the profiles table):

```sql
SELECT id, full_name, display_name, phone, phone_number
  FROM profiles WHERE id = '<seller_id>';
```

**Message template:**

> Hi [seller name], a buyer has reported an issue with transfer [transfer_id] for [event_name] tickets. Please reply within 24 hours with evidence that the tickets were sent (screenshot of transfer confirmation, email forwarding receipt, etc.). If we don't hear back, we will resolve in the buyer's favor.

Record the timestamp you contacted the seller.

---

## 4. Seller Response Branches

### Branch A — Seller responds with evidence

Evidence must show the ticket was actually transferred to the buyer (transfer confirmation screenshot, platform email, etc.).

Proceed to **Step 6 — Seller-Win**.

### Branch B — Seller responds but evidence is weak or missing

Seller claims they sent but has no proof. Ask once more for evidence with a 12-hour deadline. If no proof arrives, proceed to **Step 5 — Buyer-Win**.

### Branch C — Seller does not respond within 24 hours

Proceed to **Step 5 — Buyer-Win**.

---

## 5. Buyer-Win Branch — Refund the Buyer

1. **Refund in Stripe:** Open the PaymentIntent in Stripe Dashboard -> click "Refund" -> full refund -> confirm. Copy the `re_xxx` refund ID.

2. **Update Supabase — payment:**

```sql
UPDATE payments
   SET status      = 'refunded',
       refunded_at = now()
 WHERE id = '<payment_id>'
   AND status = 'succeeded';
```

3. **Update Supabase — transfer:**

```sql
UPDATE transfers
   SET status = 'expired'
 WHERE id = '<transfer_id>'
   AND status = 'disputed';
```

4. **Update Supabase — listing (re-activate if appropriate):**

```sql
UPDATE listings
   SET status = 'active',
       reserved_by = NULL,
       reserved_until = NULL,
       sold_at = NULL
 WHERE id = '<listing_id>';
```

5. **Verify:** Re-query payment (`status = 'refunded'`, `refunded_at IS NOT NULL`) and check Stripe shows refund `succeeded`.

---

## 6. Seller-Win Branch — Release Payout

1. **Pre-check:** Confirm `transfers.payout_released_at IS NULL` (no double-pay).

2. **Get seller's Connect account:**

```sql
SELECT stripe_connect_id FROM profiles WHERE id = '<seller_id>';
```

3. **Create Stripe Transfer:** In Stripe Dashboard or via API, create a Transfer to the seller's Connect account for the listing amount (excluding service fee). Record the `tr_xxx` ID.

4. **Update Supabase — transfer:**

```sql
UPDATE transfers
   SET status              = 'buyer_confirmed',
       payout_released_at  = now(),
       stripe_transfer_id  = 'tr_xxx'
 WHERE id = '<transfer_id>'
   AND status = 'disputed';
```

5. **Verify:** Re-query transfer (`payout_released_at IS NOT NULL`, `stripe_transfer_id` populated) and confirm Stripe Transfer status is `paid`.

---

## 7. Post-Resolution Checklist

- [ ] Payment record status matches outcome (refunded / succeeded)
- [ ] Transfer record status matches outcome (expired / buyer_confirmed)
- [ ] Stripe state matches DB (refund exists or transfer exists)
- [ ] Listing status updated if needed
- [ ] Seller contacted with outcome
- [ ] If seller is a repeat offender (2+ buyer-win disputes), consider ban (see SQL pack)

---

## Operator Decision Tree

```
DISPUTE RECEIVED
      |
      v
Did the seller mark "sent" (status = seller_sent)?
      |
  NO -+-> Buyer-Win (refund)
      |
  YES
      |
      v
Did the seller respond to admin contact within 24h?
      |
  NO -+-> Buyer-Win (refund)
      |
  YES
      |
      v
Did the seller provide valid transfer evidence?
      |
  NO -+-> Buyer-Win (refund)
      |
  YES
      |
      v
Does the buyer have counter-evidence (e.g. screenshot showing
tickets never arrived in their account)?
      |
  YES +-> Buyer-Win (refund) — evidence conflict defaults to buyer in beta
      |
  NO -+-> Seller-Win (release payout)
```

**Beta default:** When in doubt, rule in the buyer's favor. Seller trust is earned over time.

---

STEP COMPLETE — WAITING FOR NEXT RUN
