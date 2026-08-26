-- =============================================================================
-- Day 5 — Admin SQL Query Pack for SnatchIt Private Beta
-- Version: 1.0
-- Date: 2026-04-01
-- Usage: Copy-paste into Supabase SQL Editor
-- =============================================================================


-- =============================================
-- SECTION A: INSPECTION QUERIES
-- =============================================

-- A1. Inspect transfer by listing_id
SELECT t.id AS transfer_id, t.status, t.transfer_method,
       t.seller_sent_at, t.buyer_confirmed_at, t.disputed_at, t.expires_at,
       t.payout_released_at, t.stripe_transfer_id,
       t.buyer_id, t.seller_id, t.listing_id, t.payment_id,
       t.created_at
  FROM transfers t
 WHERE t.listing_id = '<listing_id>'
 ORDER BY t.created_at DESC;


-- A2. Inspect transfer by transfer_id
SELECT t.*, p.stripe_payment_intent_id, p.amount, p.total, p.status AS payment_status
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
 WHERE t.id = '<transfer_id>';


-- A3. Inspect payment by listing_id
SELECT p.id AS payment_id, p.status, p.amount, p.service_fee, p.total,
       p.stripe_payment_intent_id, p.payment_method, p.mode,
       p.paid_at, p.failed_at, p.refunded_at,
       p.buyer_id, p.seller_id, p.listing_id,
       p.created_at
  FROM payments p
 WHERE p.listing_id = '<listing_id>'
 ORDER BY p.created_at DESC;


-- A4. Inspect payment by payment_id
SELECT * FROM payments WHERE id = '<payment_id>';


-- A5. Inspect seller profile and stripe_connect_id
SELECT pr.id, pr.full_name, pr.display_name, pr.phone, pr.phone_number,
       pr.stripe_connect_id, pr.is_verified_seller, pr.is_verified_buyer,
       pr.wallet_balance, pr.created_at
  FROM profiles pr
 WHERE pr.id = '<seller_id>';


-- A6. Inspect dispute state for a transfer
SELECT t.id, t.status, t.disputed_at,
       t.seller_sent_at, t.buyer_confirmed_at, t.expires_at,
       t.payout_released_at, t.stripe_transfer_id,
       p.stripe_payment_intent_id, p.status AS payment_status, p.amount, p.total,
       l.event_name, l.venue, l.event_date,
       buyer.display_name AS buyer_name, buyer.phone_number AS buyer_phone,
       seller.display_name AS seller_name, seller.phone_number AS seller_phone,
       seller.stripe_connect_id
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN listings l ON l.id = t.listing_id
  JOIN profiles buyer ON buyer.id = t.buyer_id
  JOIN profiles seller ON seller.id = t.seller_id
 WHERE t.id = '<transfer_id>';


-- =============================================
-- SECTION B: DISPUTE RESOLUTION MUTATIONS
-- =============================================

-- B1. Mark transfer as disputed manually (admin override)
UPDATE transfers
   SET status      = 'disputed',
       disputed_at = now()
 WHERE id = '<transfer_id>'
   AND status IN ('seller_sent', 'pending')
 RETURNING id, status, disputed_at;


-- B2. Resolve dispute in buyer's favor (refund)
-- Run AFTER completing the Stripe refund in Dashboard
UPDATE payments
   SET status      = 'refunded',
       refunded_at = now()
 WHERE id = '<payment_id>'
   AND status = 'succeeded'
 RETURNING id, status, refunded_at;

UPDATE transfers
   SET status = 'expired'
 WHERE id = '<transfer_id>'
   AND status = 'disputed'
 RETURNING id, status;

UPDATE listings
   SET status         = 'active',
       reserved_by    = NULL,
       reserved_until = NULL,
       sold_at        = NULL
 WHERE id = '<listing_id>'
 RETURNING id, status;


-- B3. Resolve dispute in seller's favor (release payout)
-- Run AFTER creating the Stripe Transfer in Dashboard
UPDATE transfers
   SET status              = 'buyer_confirmed',
       payout_released_at  = now(),
       stripe_transfer_id  = '<tr_xxx>'
 WHERE id = '<transfer_id>'
   AND status = 'disputed'
   AND payout_released_at IS NULL
 RETURNING id, status, payout_released_at, stripe_transfer_id;


-- =============================================
-- SECTION C: PAYOUT & REFUND FIELD UPDATES
-- =============================================

-- C1. Update payout_released_at and stripe_transfer_id
-- Use when manually recording a payout that was created outside the normal flow
UPDATE transfers
   SET payout_released_at = now(),
       stripe_transfer_id = '<tr_xxx>'
 WHERE id = '<transfer_id>'
   AND payout_released_at IS NULL
 RETURNING id, payout_released_at, stripe_transfer_id;


-- C2. Update payment refunded_at (record a refund that happened in Stripe)
UPDATE payments
   SET status      = 'refunded',
       refunded_at = now()
 WHERE id = '<payment_id>'
   AND status = 'succeeded'
 RETURNING id, status, refunded_at;


-- =============================================
-- SECTION D: OPERATIONAL DASHBOARDS
-- =============================================

-- D1. List all open disputes
SELECT t.id AS transfer_id, t.listing_id, t.disputed_at,
       l.event_name, l.event_date,
       buyer.display_name AS buyer_name,
       seller.display_name AS seller_name,
       p.amount, p.total, p.stripe_payment_intent_id,
       t.payout_released_at
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN listings l ON l.id = t.listing_id
  JOIN profiles buyer ON buyer.id = t.buyer_id
  JOIN profiles seller ON seller.id = t.seller_id
 WHERE t.status = 'disputed'
 ORDER BY t.disputed_at ASC;


-- D2. List stuck succeeded payments without transfers
-- These are payments that succeeded but no transfer was ever created
SELECT p.id AS payment_id, p.listing_id, p.buyer_id, p.seller_id,
       p.amount, p.total, p.stripe_payment_intent_id,
       p.status, p.paid_at, p.created_at,
       l.event_name
  FROM payments p
  LEFT JOIN transfers t ON t.payment_id = p.id
  JOIN listings l ON l.id = p.listing_id
 WHERE p.status = 'succeeded'
   AND t.id IS NULL
 ORDER BY p.paid_at DESC;


-- D3. List all transfers expiring in the next 6 hours (proactive monitoring)
SELECT t.id, t.listing_id, t.status, t.expires_at,
       l.event_name, seller.display_name AS seller_name
  FROM transfers t
  JOIN listings l ON l.id = t.listing_id
  JOIN profiles seller ON seller.id = t.seller_id
 WHERE t.status = 'pending'
   AND t.expires_at <= now() + interval '6 hours'
 ORDER BY t.expires_at ASC;


-- D4. Daily summary: counts by transfer status
SELECT status, count(*) AS cnt
  FROM transfers
 GROUP BY status
 ORDER BY cnt DESC;


-- D5. Daily summary: counts by payment status
SELECT status, count(*) AS cnt
  FROM payments
 GROUP BY status
 ORDER BY cnt DESC;


-- =============================================
-- SECTION E: SELLER MANAGEMENT (BETA OPS)
-- =============================================

-- E1. Ban a seller: deactivate all their active listings
-- Step 1: Deactivate listings
UPDATE listings
   SET status = 'sold',
       sold_at = now()
 WHERE seller_id = '<seller_id>'
   AND status = 'active'
 RETURNING id, event_name, status;

-- Step 2: Mark seller as unverified (soft ban)
UPDATE profiles
   SET is_verified_seller = false
 WHERE id = '<seller_id>'
 RETURNING id, display_name, is_verified_seller;


-- E2. Find repeat offenders (sellers with 2+ buyer-win disputes)
SELECT t.seller_id, pr.display_name, pr.stripe_connect_id,
       count(*) AS dispute_losses
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN profiles pr ON pr.id = t.seller_id
 WHERE p.status = 'refunded'
   AND t.disputed_at IS NOT NULL
 GROUP BY t.seller_id, pr.display_name, pr.stripe_connect_id
HAVING count(*) >= 2
 ORDER BY dispute_losses DESC;


-- E3. Full seller history for a specific seller
SELECT t.id AS transfer_id, t.status, t.created_at, t.disputed_at,
       t.payout_released_at,
       p.status AS payment_status, p.amount,
       l.event_name, l.event_date,
       buyer.display_name AS buyer_name
  FROM transfers t
  JOIN payments p ON p.id = t.payment_id
  JOIN listings l ON l.id = t.listing_id
  JOIN profiles buyer ON buyer.id = t.buyer_id
 WHERE t.seller_id = '<seller_id>'
 ORDER BY t.created_at DESC;


-- =============================================================================
-- END OF ORIGINAL ADMIN SQL PACK
-- =============================================================================


-- ============================================================
-- PHASE B: RISK & FRAUD DASHBOARD QUERIES
-- Added: 2026-04-06
-- Usage: Run in Supabase SQL Editor for risk monitoring
-- Prerequisite: Migration 012_seller_risk.sql must be applied
-- ============================================================


-- PB-1. Unreviewed flags (priority dashboard — run daily)
SELECT
  sf.id as flag_id,
  sf.created_at,
  sf.severity,
  sf.flag_type,
  sf.details,
  sf.seller_id,
  p.display_name as seller_name,
  p.phone_number as seller_phone,
  sf.listing_id,
  sf.transfer_id
FROM seller_flags sf
LEFT JOIN profiles p ON p.id = sf.seller_id
WHERE sf.reviewed_at IS NULL
ORDER BY
  CASE sf.severity
    WHEN 'critical' THEN 1
    WHEN 'warning' THEN 2
    WHEN 'info' THEN 3
  END,
  sf.created_at DESC;


-- PB-2. Repeat dispute losers
SELECT
  t.seller_id,
  p.display_name,
  COUNT(*) FILTER (WHERE t.dispute_resolution = 'resolved_buyer_refunded') as disputes_lost,
  COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL) as total_disputes,
  COUNT(*) FILTER (WHERE t.status IN ('buyer_confirmed','auto_released')) as completed
FROM transfers t
JOIN profiles p ON p.id = t.seller_id
WHERE t.seller_id IS NOT NULL
GROUP BY t.seller_id, p.display_name
HAVING COUNT(*) FILTER (WHERE t.dispute_resolution = 'resolved_buyer_refunded') >= 2
ORDER BY disputes_lost DESC;


-- PB-3. Duplicate proof usage
SELECT
  l.seller_id,
  p.display_name,
  l.proof_of_ownership_path,
  COUNT(*) as listing_count,
  array_agg(l.id) as listing_ids,
  array_agg(l.event_name) as events
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND l.proof_of_ownership_path IS NOT NULL
GROUP BY l.seller_id, p.display_name, l.proof_of_ownership_path
HAVING COUNT(*) > 1
ORDER BY listing_count DESC;


-- PB-4. Same-event overload
SELECT
  l.seller_id,
  p.display_name,
  l.event_name,
  l.event_date,
  COUNT(*) as listing_count,
  array_agg(l.id) as listing_ids
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
GROUP BY l.seller_id, p.display_name, l.event_name, l.event_date
HAVING COUNT(*) > 3
ORDER BY listing_count DESC;


-- PB-5. High-risk new sellers (accounts < 7 days with active listings)
SELECT
  l.seller_id,
  p.display_name,
  u.created_at as account_created,
  EXTRACT(DAY FROM now() - u.created_at)::int as age_days,
  COUNT(*) as active_listings,
  MAX(GREATEST(l.starting_bid, COALESCE(l.buy_now_price, 0))) as max_price
FROM listings l
JOIN profiles p ON p.id = l.seller_id
JOIN auth.users u ON u.id = l.seller_id
WHERE l.status = 'active'
  AND u.created_at > now() - interval '7 days'
GROUP BY l.seller_id, p.display_name, u.created_at
ORDER BY age_days ASC, max_price DESC;


-- PB-6. Sellers with payout issues (no Stripe Connect)
SELECT
  l.seller_id,
  p.display_name,
  p.stripe_connect_id,
  COUNT(*) as active_listings,
  SUM(CASE WHEN l.buy_now_price IS NOT NULL THEN l.buy_now_price ELSE l.starting_bid END) as total_value
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND (p.stripe_connect_id IS NULL OR p.stripe_connect_id = '')
GROUP BY l.seller_id, p.display_name, p.stripe_connect_id
ORDER BY total_value DESC;


-- PB-7. Risk score summary (run after refresh_all_seller_risk_scores())
SELECT
  srs.risk_tier,
  srs.seller_id,
  p.display_name,
  srs.active_listings,
  srs.total_completed,
  srs.dispute_rate,
  srs.dispute_loss_rate,
  srs.open_flags_count,
  srs.critical_flags_count,
  srs.is_listing_blocked,
  srs.updated_at
FROM seller_risk_scores srs
JOIN profiles p ON p.id = srs.seller_id
ORDER BY
  CASE srs.risk_tier
    WHEN 'critical' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  srs.open_flags_count DESC;


-- PB-8. Resolve a flag (template — replace placeholders)
-- UPDATE seller_flags
-- SET
--   reviewed_at = now(),
--   reviewed_by = '<admin_user_id>',
--   resolution = 'warned',
--   resolution_notes = 'Contacted seller via phone. Warning issued.'
-- WHERE id = '<flag_id>';
-- SELECT refresh_seller_risk_score('<seller_id>');
