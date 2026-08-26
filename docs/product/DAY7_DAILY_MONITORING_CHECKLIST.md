# Day 7 — Daily Monitoring & Incident Checklist

**Version:** 1.0
**Date:** 2026-04-02
**Audience:** Admin / Ops running SnatchIt private beta
**Tools Required:** Supabase SQL Editor, Stripe Dashboard, Sentry, Expo Push Dashboard
**Frequency:** Run every morning during beta (takes ~10 minutes)

---

## CHECK 1 — Orphaned Payments (Payment Exists, No Transfer)

**What:** Finds payments that succeeded but have no corresponding transfer row. This means a buyer was charged but the system doesn't know about the sale.

**Severity if found:** CRITICAL — buyer has been charged with no fulfillment path.

```sql
SELECT p.id AS payment_id,
       p.stripe_payment_intent_id,
       p.listing_id,
       p.buyer_id,
       p.amount,
       p.total,
       p.status AS payment_status,
       p.created_at AS payment_created
  FROM payments p
  LEFT JOIN transfers t ON t.payment_id = p.id
 WHERE p.status = 'succeeded'
   AND t.id IS NULL
 ORDER BY p.created_at DESC;
```

**Expected result:** 0 rows.

**If rows found:**
1. Check Stripe Dashboard for the `stripe_payment_intent_id` — confirm payment is real
2. Check if the webhook was received (Stripe → Developers → Webhooks → recent deliveries)
3. If webhook failed: manually create the transfer row using docs/operations/DAY5_ADMIN_SQL_PACK.sql
4. If webhook succeeded but transfer is missing: investigate edge function logs in Supabase

---

## CHECK 2 — Disputed Transfers (Pending Admin Action)

**What:** Finds all transfers in `disputed` status that need admin resolution.

**Severity if found:** HIGH — buyer and seller are waiting for resolution.

```sql
SELECT t.id AS transfer_id,
       t.listing_id,
       t.buyer_id,
       t.seller_id,
       t.status,
       t.disputed_at,
       t.payout_released_at,
       p.stripe_payment_intent_id,
       p.amount,
       p.total,
       l.event_name,
       EXTRACT(EPOCH FROM (now() - t.disputed_at)) / 3600 AS hours_since_dispute
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN listings l ON l.id = t.listing_id
 WHERE t.status = 'disputed'
 ORDER BY t.disputed_at ASC;
```

**Expected result:** 0 rows (all disputes resolved within 24h).

**If rows found:**
1. Follow docs/operations/DAY5_ADMIN_DISPUTE_SOP.md
2. Prioritize any dispute older than 24 hours (`hours_since_dispute > 24`)
3. Resolve via manual refund (buyer wins) or manual payout release (seller wins)

---

## CHECK 3 — Expired Transfers Without Refund

**What:** Finds transfers that expired (seller ghosted) but no Stripe refund was issued. Buyer should have been refunded automatically.

**Severity if found:** CRITICAL — buyer was charged and seller didn't deliver, but refund didn't happen.

```sql
SELECT t.id AS transfer_id,
       t.listing_id,
       t.buyer_id,
       t.expires_at,
       t.status,
       p.stripe_payment_intent_id,
       p.amount,
       p.status AS payment_status
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
 WHERE t.status = 'expired'
   AND p.status != 'refunded'
 ORDER BY t.expires_at ASC;
```

**Expected result:** 0 rows.

**If rows found:**
1. The `enforce-transfer-expiry` cron marked the transfer as expired but failed to refund
2. Issue manual refund via Stripe Dashboard (see docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md)
3. Update payment status: `UPDATE payments SET status = 'refunded' WHERE id = '<payment_id>';`
4. Investigate why the cron failed to refund (check edge function logs)

---

## CHECK 4 — Failed Payouts (Buyer Confirmed but Seller Not Paid)

**What:** Finds transfers where the buyer confirmed receipt but no Stripe Transfer was created to the seller. Seller should have been paid.

**Severity if found:** HIGH — seller fulfilled their obligation but hasn't been paid.

```sql
SELECT t.id AS transfer_id,
       t.listing_id,
       t.seller_id,
       t.buyer_confirmed_at,
       t.payout_released_at,
       t.stripe_transfer_id,
       t.status,
       p.stripe_payment_intent_id,
       p.amount,
       pr.stripe_connect_id AS seller_connect_id
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN profiles pr ON pr.id = t.seller_id
 WHERE t.status = 'buyer_confirmed'
   AND t.stripe_transfer_id IS NULL
 ORDER BY t.buyer_confirmed_at ASC;
```

**Expected result:** 0 rows.

**If rows found:**
1. Check if seller has a valid `stripe_connect_id` — if NULL, seller never onboarded
2. If seller has Connect account: manually create transfer via Stripe Dashboard or API
3. If seller has no Connect account: contact seller to complete Stripe onboarding, then retry
4. Update transfer: `UPDATE transfers SET stripe_transfer_id = 'tr_xxx', payout_released_at = now() WHERE id = '<transfer_id>';`

---

## CHECK 5 — Stuck "Sold" Listings Without Active Transfers

**What:** Finds listings marked as `sold` but with no transfer in a healthy state. Could indicate a failed webhook or data inconsistency.

**Severity if found:** MEDIUM — listing is locked as "sold" but no transaction is in progress.

```sql
SELECT l.id AS listing_id,
       l.event_name,
       l.seller_id,
       l.status AS listing_status,
       t.id AS transfer_id,
       t.status AS transfer_status
  FROM listings l
  LEFT JOIN transfers t ON t.listing_id = l.id
 WHERE l.status = 'sold'
   AND (t.id IS NULL OR t.status IN ('expired', 'refunded'))
 ORDER BY l.updated_at DESC;
```

**Expected result:** 0 rows (every "sold" listing has an active transfer).

**If rows found:**
1. If transfer is `expired`/`refunded`: listing should be reverted to `active` so seller can relist
2. Run: `UPDATE listings SET status = 'active' WHERE id = '<listing_id>';`
3. If no transfer exists at all: check CHECK 1 for orphaned payment, or this may be a data bug

---

## CHECK 6 — Push Notification Failures

**What:** Checks for users who should have received push notifications but may not have.

**Severity if found:** LOW to MEDIUM — users miss updates but can still check in-app.

### 6a. Users without push tokens

```sql
SELECT id, email, created_at
  FROM profiles
 WHERE expo_push_token IS NULL
   AND created_at > now() - interval '7 days'
 ORDER BY created_at DESC;
```

### 6b. Recent transfers with state changes (spot-check delivery)

```sql
SELECT t.id, t.status, t.buyer_id, t.seller_id,
       pb.expo_push_token AS buyer_token,
       ps.expo_push_token AS seller_token
  FROM transfers t
  JOIN profiles pb ON pb.id = t.buyer_id
  JOIN profiles ps ON ps.id = t.seller_id
 WHERE t.updated_at > now() - interval '24 hours'
   AND (pb.expo_push_token IS NULL OR ps.expo_push_token IS NULL);
```

**If rows found:**
1. Users without tokens won't receive push notifications
2. Contact them via support channel and ask them to enable notifications
3. This is expected for some testers — not a blocker

---

## CHECK 7 — Cron Job Health

**What:** Verifies that both cron jobs ran successfully in the last execution window.

**Severity if not running:** CRITICAL — transfers won't expire and auto-release won't fire.

### How to check:

1. **Supabase Dashboard** → Edge Functions → `enforce-transfer-expiry` → Logs → confirm execution in last 10 minutes
2. **Supabase Dashboard** → Edge Functions → `auto-release-funds` → Logs → confirm execution in last 10 minutes
3. Look for any error logs (HTTP 500, timeout, uncaught exception)

### Backup verification — transfers that should have expired but haven't:

```sql
SELECT t.id, t.listing_id, t.status, t.expires_at,
       EXTRACT(EPOCH FROM (now() - t.expires_at)) / 3600 AS hours_overdue
  FROM transfers t
 WHERE t.status = 'pending'
   AND t.expires_at < now()
 ORDER BY t.expires_at ASC;
```

**Expected result:** 0 rows.

**If rows found:** Cron is not running. Manually invoke `enforce-transfer-expiry` via curl or Supabase Dashboard, then investigate why the cron schedule stopped.

### Backup verification — transfers that should have auto-released but haven't:

```sql
SELECT t.id, t.listing_id, t.status, t.auto_release_at,
       EXTRACT(EPOCH FROM (now() - t.auto_release_at)) / 3600 AS hours_overdue
  FROM transfers t
 WHERE t.status = 'seller_sent'
   AND t.auto_release_at < now()
 ORDER BY t.auto_release_at ASC;
```

**Expected result:** 0 rows.

**If rows found:** `auto-release-funds` cron is not running. Same recovery steps as above.

---

## CHECK 8 — Sentry Error Spike

**What:** Quick check for new or spiking errors in the app.

### How to check:

1. Open Sentry → Project: `snatchit` → Issues → sort by "Last Seen"
2. Look for any new issues in the last 24 hours
3. Check error count — anything over 10 occurrences warrants investigation
4. Prioritize crashes (`Fatal` level) and payment-related errors

---

## Daily Monitoring Log Template

Copy this into a daily log (Google Doc, Notion, or local file):

```
# SnatchIt Beta — Daily Monitoring Log
## Date: YYYY-MM-DD
## Admin: [Name]

| Check | Result | Action Taken |
|-------|--------|--------------|
| 1. Orphaned payments | 0 found / X found | |
| 2. Disputed transfers | 0 pending / X pending | |
| 3. Expired without refund | 0 found / X found | |
| 4. Failed payouts | 0 found / X found | |
| 5. Stuck sold listings | 0 found / X found | |
| 6. Push token gaps | 0 users / X users missing tokens | |
| 7. Cron health | Both running / Issue found | |
| 8. Sentry errors | 0 new / X new issues | |

## Notes:
[Any incidents, observations, or follow-ups]
```

---

## Incident Response Quick Reference

| Situation | Immediate Action | Playbook |
|-----------|-----------------|----------|
| Buyer charged, no transfer | Create transfer row via SQL | docs/operations/DAY5_ADMIN_SQL_PACK.sql |
| Expired transfer, no refund | Manual refund via Stripe Dashboard | docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md |
| Buyer confirmed, seller not paid | Manual Stripe Transfer creation | docs/operations/DAY5_MANUAL_REFUND_PLAYBOOK.md (Part 2) |
| Dispute pending >24h | Investigate and resolve | docs/operations/DAY5_ADMIN_DISPUTE_SOP.md |
| Cron not running | Manual curl invocation + investigate | Supabase Edge Function logs |
| Stripe webhook failing | Check Stripe webhook logs + retry | Stripe Dashboard → Webhooks |
| App crash spike | Check Sentry + hotfix | Sentry Dashboard |

---

*Run this checklist every morning during beta. If any CRITICAL check fails, resolve before end of day.*
