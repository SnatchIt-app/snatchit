-- ============================================================
-- Phase B V1 — Detection Queries (READ-ONLY)
-- Usage: Run manually in Supabase SQL Editor to detect risk signals.
-- These queries SELECT only. They do NOT create flags automatically.
-- Admin reviews output and manually creates flags as needed.
-- ============================================================


-- ============================================================
-- THRESHOLD REFERENCE
-- ============================================================
-- Rule 1:  same_event_overload     — same event+date listings > 3 (warning), > 6 (critical)
-- Rule 2:  high_dispute_rate       — dispute rate > 20% (warning), > 40% (critical), min 3 completed
-- Rule 3:  high_dispute_loss_rate  — loss rate > 50% (critical), min 2 disputes
-- Rule 4:  duplicate_proof         — same proof path on 2+ active listings (critical)
-- Rule 5:  duplicate_evidence      — same evidence path on 2+ transfers (critical)
-- Rule 6:  rapid_send              — sent < 5min after creation, > 2 occurrences (warning)
-- Rule 7:  new_account_high_value  — age < 7d + listing > $200 (warning)
-- Rule 8:  high_listing_velocity   — > 5 listings in 24h (warning), > 10 (critical)
-- Rule 9:  missing_payout_setup    — active listings, no Stripe Connect (info)
-- Rule 10: repeated_expiry         — > 2 expired transfers (warning), > 4 (critical)
-- ============================================================


-- ------------------------------------------------------------
-- RULE 1: Same-Event Overload
-- Seller has > 3 active listings for the same event_name + event_date
-- ------------------------------------------------------------
SELECT
  l.seller_id,
  p.display_name,
  l.event_name,
  l.event_date,
  COUNT(*) as listing_count,
  array_agg(l.id) as listing_ids,
  CASE WHEN COUNT(*) > 6 THEN 'CRITICAL' ELSE 'WARNING' END as suggested_severity
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
GROUP BY l.seller_id, p.display_name, l.event_name, l.event_date
HAVING COUNT(*) > 3
ORDER BY listing_count DESC;


-- ------------------------------------------------------------
-- RULE 2: High Dispute Rate
-- Dispute rate > 20% with minimum 3 completed transfers
-- ------------------------------------------------------------
WITH seller_stats AS (
  SELECT
    seller_id,
    COUNT(*) FILTER (WHERE status IN ('buyer_confirmed','auto_released')) as completed,
    COUNT(*) FILTER (WHERE status = 'disputed' OR dispute_resolved_at IS NOT NULL) as disputes
  FROM transfers
  WHERE seller_id IS NOT NULL
  GROUP BY seller_id
)
SELECT
  ss.seller_id,
  p.display_name,
  ss.completed,
  ss.disputes,
  ROUND(ss.disputes::numeric / ss.completed, 2) as dispute_rate,
  CASE
    WHEN ss.disputes::numeric / ss.completed > 0.40 THEN 'CRITICAL'
    ELSE 'WARNING'
  END as suggested_severity
FROM seller_stats ss
JOIN profiles p ON p.id = ss.seller_id
WHERE ss.completed >= 3 AND ss.disputes::numeric / ss.completed > 0.20
ORDER BY dispute_rate DESC;


-- ------------------------------------------------------------
-- RULE 3: High Dispute Loss Rate
-- Lost > 50% of disputes with minimum 2 disputes
-- ------------------------------------------------------------
WITH seller_disputes AS (
  SELECT
    seller_id,
    COUNT(*) FILTER (WHERE status = 'disputed' OR dispute_resolved_at IS NOT NULL) as total_disputes,
    COUNT(*) FILTER (WHERE dispute_resolution = 'resolved_buyer_refunded') as losses
  FROM transfers
  WHERE seller_id IS NOT NULL
  GROUP BY seller_id
)
SELECT
  sd.seller_id,
  p.display_name,
  sd.total_disputes,
  sd.losses,
  ROUND(sd.losses::numeric / sd.total_disputes, 2) as loss_rate
FROM seller_disputes sd
JOIN profiles p ON p.id = sd.seller_id
WHERE sd.total_disputes >= 2 AND sd.losses::numeric / sd.total_disputes > 0.50
ORDER BY loss_rate DESC;


-- ------------------------------------------------------------
-- RULE 4: Duplicate Proof of Ownership
-- Same proof_of_ownership_path on multiple active listings
-- ------------------------------------------------------------
SELECT
  l.seller_id,
  p.display_name,
  l.proof_of_ownership_path,
  COUNT(*) as usage_count,
  array_agg(l.id) as listing_ids,
  array_agg(l.event_name) as events
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.status = 'active'
  AND l.proof_of_ownership_path IS NOT NULL
GROUP BY l.seller_id, p.display_name, l.proof_of_ownership_path
HAVING COUNT(*) > 1
ORDER BY usage_count DESC;


-- ------------------------------------------------------------
-- RULE 5: Duplicate Transfer Evidence
-- Same transfer_evidence_path on multiple transfers
-- ------------------------------------------------------------
SELECT
  t.seller_id,
  p.display_name,
  t.transfer_evidence_path,
  COUNT(*) as usage_count,
  array_agg(t.id) as transfer_ids,
  array_agg(t.listing_id) as listing_ids
FROM transfers t
JOIN profiles p ON p.id = t.seller_id
WHERE t.transfer_evidence_path IS NOT NULL
GROUP BY t.seller_id, p.display_name, t.transfer_evidence_path
HAVING COUNT(*) > 1
ORDER BY usage_count DESC;


-- ------------------------------------------------------------
-- RULE 6: Rapid Mark-as-Sent
-- Seller marked > 2 transfers as sent within 5 minutes of creation
-- ------------------------------------------------------------
SELECT
  t.seller_id,
  p.display_name,
  COUNT(*) as rapid_count,
  array_agg(t.id) as transfer_ids
FROM transfers t
JOIN profiles p ON p.id = t.seller_id
WHERE t.seller_sent_at IS NOT NULL
  AND t.seller_sent_at - t.created_at < interval '5 minutes'
GROUP BY t.seller_id, p.display_name
HAVING COUNT(*) > 2
ORDER BY rapid_count DESC;


-- ------------------------------------------------------------
-- RULE 7: New Account + High Value
-- Account < 7 days old with active listing > $200
-- ------------------------------------------------------------
SELECT
  l.seller_id,
  p.display_name,
  u.created_at as account_created,
  EXTRACT(DAY FROM now() - u.created_at)::int as age_days,
  l.id as listing_id,
  l.event_name,
  l.starting_bid,
  l.buy_now_price,
  GREATEST(l.starting_bid, COALESCE(l.buy_now_price, 0)) as max_price
FROM listings l
JOIN profiles p ON p.id = l.seller_id
JOIN auth.users u ON u.id = l.seller_id
WHERE l.status = 'active'
  AND EXTRACT(DAY FROM now() - u.created_at) < 7
  AND (l.starting_bid > 200 OR COALESCE(l.buy_now_price, 0) > 200)
ORDER BY age_days ASC, max_price DESC;


-- ------------------------------------------------------------
-- RULE 8: High Listing Velocity
-- Seller created > 5 listings in past 24 hours
-- ------------------------------------------------------------
SELECT
  l.seller_id,
  p.display_name,
  COUNT(*) as listings_24h,
  CASE WHEN COUNT(*) > 10 THEN 'CRITICAL' ELSE 'WARNING' END as suggested_severity
FROM listings l
JOIN profiles p ON p.id = l.seller_id
WHERE l.created_at > now() - interval '24 hours'
GROUP BY l.seller_id, p.display_name
HAVING COUNT(*) > 5
ORDER BY listings_24h DESC;


-- ------------------------------------------------------------
-- RULE 9: Missing Payout Setup
-- Seller has active listings but no stripe_connect_id
-- ------------------------------------------------------------
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


-- ------------------------------------------------------------
-- RULE 10: Repeated Transfer Expiry
-- Seller has > 2 expired transfers
-- ------------------------------------------------------------
SELECT
  t.seller_id,
  p.display_name,
  COUNT(*) as expired_count,
  CASE WHEN COUNT(*) > 4 THEN 'CRITICAL' ELSE 'WARNING' END as suggested_severity,
  array_agg(t.id) as transfer_ids
FROM transfers t
JOIN profiles p ON p.id = t.seller_id
WHERE t.status = 'expired'
GROUP BY t.seller_id, p.display_name
HAVING COUNT(*) > 2
ORDER BY expired_count DESC;


-- ============================================================
-- MANUAL FLAG INSERT TEMPLATE
-- After reviewing detection query output, use this to create a flag:
-- ============================================================
-- INSERT INTO seller_flags (seller_id, flag_type, severity, details, listing_id)
-- VALUES (
--   '<seller_uuid>',
--   '<flag_type>',        -- e.g. 'duplicate_proof'
--   '<severity>',         -- 'info', 'warning', or 'critical'
--   '<human readable details>',
--   '<listing_uuid or NULL>'
-- );
-- Then refresh the seller's score:
-- SELECT refresh_seller_risk_score('<seller_uuid>');
