-- =============================================================================
-- Day 6 — SQL Verification Pack for E2E Testing
-- Version: 1.0
-- Date: 2026-04-01
-- Usage: Copy-paste into Supabase SQL Editor. Replace <placeholders> with real IDs.
-- =============================================================================


-- =============================================
-- HELPER: Fast-Forward Timers (for testing)
-- =============================================

-- Fast-forward transfer expiry (for Test 2: Seller Ghost)
-- Makes the pending transfer appear expired so cron picks it up on next run
UPDATE transfers
   SET expires_at = now() - interval '1 minute'
 WHERE listing_id = '<listing_id>'
   AND status = 'pending';

-- Fast-forward auto-release (for Test 3: Buyer Ghost)
-- Makes the seller_sent transfer appear past the 72h window
UPDATE transfers
   SET auto_release_at = now() - interval '1 minute'
 WHERE listing_id = '<listing_id>'
   AND status = 'seller_sent';


-- =============================================
-- TEST 1: Happy Path Verification
-- =============================================

-- T1-V1: Verify transfer final state
SELECT t.id AS transfer_id,
       t.status,
       t.seller_sent_at    IS NOT NULL AS seller_sent_ok,
       t.buyer_confirmed_at IS NOT NULL AS buyer_confirmed_ok,
       t.payout_released_at IS NOT NULL AS payout_released_ok,
       t.stripe_transfer_id IS NOT NULL AS stripe_transfer_ok,
       t.stripe_transfer_id
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: status = 'buyer_confirmed', all _ok columns = true

-- T1-V2: Verify payment state
SELECT p.id, p.status, p.amount, p.total, p.service_fee,
       p.stripe_payment_intent_id,
       p.refunded_at IS NULL AS not_refunded
  FROM payments p
 WHERE p.listing_id = '<listing_id>';
-- EXPECT: status = 'succeeded', not_refunded = true

-- T1-V3: Verify listing state
SELECT l.id, l.status, l.sold_at IS NOT NULL AS sold_ok
  FROM listings l
 WHERE l.id = '<listing_id>';
-- EXPECT: status = 'sold', sold_ok = true

-- T1-V4: Verify Stripe Transfer amount matches payment amount
SELECT t.stripe_transfer_id, p.amount AS expected_payout_amount
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: Cross-reference stripe_transfer_id amount in Stripe Dashboard


-- =============================================
-- TEST 2: Seller Ghost (Expiry + Refund)
-- =============================================

-- T2-V1: Verify transfer expired
SELECT t.id AS transfer_id,
       t.status,
       t.expired_at   IS NOT NULL AS expired_ok,
       t.seller_sent_at IS NULL   AS never_sent_ok,
       t.payout_released_at IS NULL AS no_payout_ok,
       t.stripe_transfer_id IS NULL AS no_transfer_ok
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: status = 'expired', all _ok = true

-- T2-V2: Verify refund issued
SELECT p.id, p.status,
       p.refunded_at IS NOT NULL    AS refunded_ok,
       p.stripe_refund_id IS NOT NULL AS refund_id_ok,
       p.stripe_refund_id,
       p.amount AS refund_expected_amount
  FROM payments p
 WHERE p.listing_id = '<listing_id>';
-- EXPECT: status = 'refunded', refunded_ok = true, refund_id_ok = true

-- T2-V3: Confirm no Stripe Transfer exists
SELECT COUNT(*) AS transfer_count
  FROM transfers t
 WHERE t.listing_id = '<listing_id>'
   AND t.stripe_transfer_id IS NOT NULL;
-- EXPECT: 0


-- =============================================
-- TEST 3: Buyer Ghost (Auto-Release)
-- =============================================

-- T3-V1: Verify auto-release state
SELECT t.id AS transfer_id,
       t.status,
       t.seller_sent_at     IS NOT NULL AS sent_ok,
       t.buyer_confirmed_at IS NULL     AS buyer_never_confirmed,
       t.payout_released_at IS NOT NULL AS payout_ok,
       t.stripe_transfer_id IS NOT NULL AS stripe_transfer_ok,
       t.stripe_transfer_id
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: status = 'auto_released', sent_ok = true, buyer_never_confirmed = true, payout_ok = true

-- T3-V2: Verify payment NOT refunded
SELECT p.id, p.status,
       p.refunded_at IS NULL AS not_refunded
  FROM payments p
 WHERE p.listing_id = '<listing_id>';
-- EXPECT: status = 'succeeded', not_refunded = true


-- =============================================
-- TEST 4: Buyer Dispute
-- =============================================

-- T4-V1: Verify dispute state
SELECT t.id AS transfer_id,
       t.status,
       t.disputed_at        IS NOT NULL AS disputed_ok,
       t.payout_released_at IS NULL     AS no_payout_ok,
       t.stripe_transfer_id IS NULL     AS no_transfer_ok
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: status = 'disputed', all _ok = true

-- T4-V2: Verify payment frozen (succeeded, not refunded)
SELECT p.id, p.status,
       p.refunded_at IS NULL AS not_refunded
  FROM payments p
 WHERE p.listing_id = '<listing_id>';
-- EXPECT: status = 'succeeded', not_refunded = true

-- T4-V3: Verify cron WILL NOT auto-release this transfer
-- (Run after cron cycle — status should still be 'disputed')
SELECT t.status, t.auto_release_at
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: status still = 'disputed' (cron only targets 'seller_sent')


-- =============================================
-- TEST 5: Double-Sale Prevention
-- =============================================

-- T5-V1: Count succeeded payments for listing
SELECT COUNT(*) AS succeeded_payments
  FROM payments p
 WHERE p.listing_id = '<listing_id>'
   AND p.status = 'succeeded';
-- EXPECT: exactly 1

-- T5-V2: Count transfer rows for listing
SELECT COUNT(*) AS transfer_rows
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: exactly 1

-- T5-V3: Verify UNIQUE constraints exist
SELECT conname, contype
  FROM pg_constraint
 WHERE conrelid = 'transfers'::regclass
   AND contype = 'u';
-- EXPECT: unique constraints on listing_id and payment_id


-- =============================================
-- TEST 6: Missing Transfer Recovery
-- =============================================

-- T6-SETUP: Delete transfer to simulate missing row (DESTRUCTIVE — test only!)
-- DELETE FROM transfers WHERE listing_id = '<listing_id>';

-- T6-V1: After app calls ensure_transfer_exists — verify recovery
SELECT t.id AS transfer_id,
       t.status,
       t.listing_id,
       t.payment_id IS NOT NULL AS payment_linked,
       t.buyer_id,
       t.seller_id
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: 1 row, status = 'pending', payment_linked = true

-- T6-V2: Verify no duplicates
SELECT COUNT(*) AS row_count
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: exactly 1


-- =============================================
-- TEST 7: Seller Missing Payout Setup
-- =============================================

-- T7-SETUP: Verify seller has no Connect account
SELECT pr.id, pr.display_name, pr.stripe_connect_id
  FROM profiles pr
 WHERE pr.id = '<seller_id>';
-- EXPECT: stripe_connect_id IS NULL

-- T7-V1: After buyer confirms — verify transfer state (payout should fail)
SELECT t.id AS transfer_id,
       t.status,
       t.buyer_confirmed_at IS NOT NULL AS confirmed_ok,
       t.payout_released_at IS NULL     AS payout_failed_ok,
       t.stripe_transfer_id IS NULL     AS no_transfer_ok
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: status = 'buyer_confirmed', payout_failed_ok = true, no_transfer_ok = true

-- T7-FIX: After admin fixes Connect account, verify payout can be created manually
-- (Use Day 5 Admin SQL Pack for manual payout)


-- =============================================
-- TEST 8: confirm-payment Soft-Fail (Webhook Fallback)
-- =============================================

-- T8-V1: Verify transfer exists (created by webhook, not confirm-payment)
SELECT t.id AS transfer_id,
       t.status,
       t.created_at
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: 1 row, status = 'pending'

-- T8-V2: Verify payment status
SELECT p.id, p.status, p.stripe_payment_intent_id
  FROM payments p
 WHERE p.listing_id = '<listing_id>';
-- EXPECT: status = 'succeeded'

-- T8-V3: Verify no duplicate transfers
SELECT COUNT(*) AS transfer_count
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: exactly 1


-- =============================================
-- TEST 9: Duplicate Webhook / Race Condition
-- =============================================

-- T9-V1: Verify single payment row (no duplicate updates)
SELECT COUNT(*) AS payment_count
  FROM payments p
 WHERE p.listing_id = '<listing_id>'
   AND p.status = 'succeeded';
-- EXPECT: exactly 1

-- T9-V2: Verify single transfer row
SELECT COUNT(*) AS transfer_count
  FROM transfers t
 WHERE t.listing_id = '<listing_id>';
-- EXPECT: exactly 1

-- T9-V3: Verify idempotency — payment was only updated once
-- (Check updated_at vs created_at if column exists, or rely on count)
SELECT p.id, p.status, p.created_at, p.paid_at
  FROM payments p
 WHERE p.listing_id = '<listing_id>';
-- EXPECT: single row, timestamps consistent


-- =============================================
-- BONUS: Global Health Checks
-- =============================================

-- HC-1: Any orphaned payments (succeeded but no transfer)?
SELECT p.id AS orphaned_payment_id, p.listing_id, p.status, p.created_at
  FROM payments p
  LEFT JOIN transfers t ON t.payment_id = p.id
 WHERE p.status = 'succeeded'
   AND t.id IS NULL;
-- EXPECT: 0 rows (every succeeded payment should have a transfer)

-- HC-2: Any transfers with payout but no stripe_transfer_id?
SELECT t.id AS suspicious_transfer, t.status, t.payout_released_at, t.stripe_transfer_id
  FROM transfers t
 WHERE t.payout_released_at IS NOT NULL
   AND t.stripe_transfer_id IS NULL;
-- EXPECT: 0 rows

-- HC-3: Any double-sold listings?
SELECT listing_id, COUNT(*) AS cnt
  FROM payments
 WHERE status = 'succeeded'
 GROUP BY listing_id
HAVING COUNT(*) > 1;
-- EXPECT: 0 rows

-- HC-4: Any duplicate transfers per listing?
SELECT listing_id, COUNT(*) AS cnt
  FROM transfers
 GROUP BY listing_id
HAVING COUNT(*) > 1;
-- EXPECT: 0 rows

-- HC-5: Disputed transfers that somehow got a payout?
SELECT t.id, t.status, t.stripe_transfer_id, t.payout_released_at
  FROM transfers t
 WHERE t.status = 'disputed'
   AND (t.stripe_transfer_id IS NOT NULL OR t.payout_released_at IS NOT NULL);
-- EXPECT: 0 rows

-- HC-6: Expired transfers that somehow got a payout?
SELECT t.id, t.status, t.stripe_transfer_id, t.payout_released_at
  FROM transfers t
 WHERE t.status = 'expired'
   AND (t.stripe_transfer_id IS NOT NULL OR t.payout_released_at IS NOT NULL);
-- EXPECT: 0 rows
