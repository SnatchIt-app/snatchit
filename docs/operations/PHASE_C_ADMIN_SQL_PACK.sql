-- ============================================================
-- Phase C — Admin SQL Operations Pack
-- Date: 2026-04-06
-- ============================================================
--
-- WARNING: All operations are MANUAL.
-- No automatic flag insertion. No enforcement hooks.
--
-- WORKFLOW:
--   detect → inspect → flag → refresh → resolve → refresh
--
--   1. Run detection queries (PHASE_B_DETECTION_QUERIES.sql)
--   2. Deduplicate against existing open flags (Query 3)
--   3. Inspect seller context (Query 2)
--   4. Determine severity using the SEVERITY POLICY below
--   5. Insert flag manually (Query 1)
--   6. Refresh seller score (Query 6)
--   7. Decide resolution if immediate action warranted
--   8. Resolve flag (Query 5)
--   9. Refresh score again (Query 6)
--
-- ============================================================
-- SEVERITY POLICY — READ BEFORE EVERY FLAG INSERT
-- ============================================================
--
-- RULE 1: high_dispute_rate can NEVER be critical.
--         Max severity = warning. Only high_dispute_loss_rate
--         drives critical classification for dispute signals.
--         A high dispute rate alone means buyers are complaining,
--         but the seller may be winning those disputes.
--
-- RULE 2: rapid_send is informational only. Default = info.
--         Does NOT contribute to risk tier calculations.
--         Only escalate to warning if:
--           account_age_days < 3 AND rapid_send_count > 5
--
-- RULE 3: same_event_overload is only critical if:
--           listing_count > 6 AND account_age_days < 7
--         Established sellers (>= 7 days) cap at warning
--         regardless of listing count.
--
-- RULE 4: Trust stabilization.
--         If account_age_days > 30 AND dispute_loss_rate = 0,
--         risk tier cannot exceed 'medium'.
--         EXCEPTION: does NOT apply if seller has open
--         duplicate_proof or duplicate_evidence flags.
--
-- ============================================================


-- ============================================================
-- 1. MANUAL FLAG INSERT TEMPLATE
-- ============================================================
-- Use after running detection queries and inspecting seller context.
-- Fill in all <placeholder> values before running.
-- The details field is REQUIRED — explain what triggered this flag.
--
-- VALID flag_type VALUES:
--   same_event_overload
--   high_dispute_rate
--   high_dispute_loss_rate
--   duplicate_proof
--   duplicate_evidence
--   rapid_send
--   new_account_high_value
--   high_listing_velocity
--   missing_payout_setup
--   repeated_expiry
--
-- VALID severity VALUES:
--   info | warning | critical
--
-- SEVERITY GUIDE (apply before choosing severity):
--   • high_dispute_rate        → max severity = WARNING (never critical)
--   • rapid_send               → default = INFO; warning only if age < 3d AND count > 5
--   • same_event_overload      → critical only if > 6 listings AND age < 7d
--   • duplicate_proof          → always CRITICAL
--   • duplicate_evidence       → always CRITICAL
--   • high_dispute_loss_rate   → always CRITICAL (loss > 50%, min 2 disputes)
--   • missing_payout_setup     → always INFO
--   • Trust stabilization: if age > 30d AND loss_rate = 0 → tier cap = medium
-- ------------------------------------------------------------
--
-- !! STOP — BEFORE YOU INSERT !!
--
-- 1. ALWAYS run Query 3 (FETCH SELLER OPEN FLAGS) first.
-- 2. DO NOT insert a new flag if an unreviewed flag with the
--    same flag_type already exists for that seller.
-- 3. If a matching open flag exists, monitor the existing flag
--    instead of duplicating it. Add context to resolution_notes
--    when you eventually resolve the original flag.
--
-- ------------------------------------------------------------

INSERT INTO seller_flags (
  seller_id,
  flag_type,
  severity,
  details,
  listing_id,
  transfer_id
) VALUES (
  '<seller_uuid>',
  '<flag_type>',
  '<severity>',
  '<human readable explanation of why this flag was raised>',
  NULL,                    -- set to listing UUID if flag is listing-specific
  NULL                     -- set to transfer UUID if flag is transfer-specific
);


-- ============================================================
-- 2. SELLER CONTEXT INSPECTION
-- ============================================================
-- Run BEFORE creating a flag to understand the seller's full picture.
-- Provides account age, listing/transfer stats, dispute rates,
-- current risk tier, and open flag counts in a single row.
-- ------------------------------------------------------------

SELECT
  u.id                                          AS seller_id,
  p.display_name,
  u.created_at                                  AS account_created,
  EXTRACT(DAY FROM now() - u.created_at)::int   AS account_age_days,
  (SELECT COUNT(*)
     FROM listings WHERE seller_id = u.id)      AS total_listings,
  (SELECT COUNT(*)
     FROM listings
    WHERE seller_id = u.id
      AND status = 'active')                    AS active_listings,
  (SELECT COUNT(*)
     FROM transfers
    WHERE seller_id = u.id
      AND status IN ('buyer_confirmed','auto_released'))
                                                AS completed_transfers,
  (SELECT COUNT(*)
     FROM transfers
    WHERE seller_id = u.id
      AND (status = 'disputed' OR dispute_resolved_at IS NOT NULL))
                                                AS total_disputes,
  (SELECT COUNT(*)
     FROM transfers
    WHERE seller_id = u.id
      AND dispute_resolution = 'resolved_buyer_refunded')
                                                AS dispute_losses,
  (SELECT COUNT(*)
     FROM transfers
    WHERE seller_id = u.id
      AND status = 'expired')                   AS expired_transfers,
  p.stripe_connect_id,
  rs.risk_tier,
  rs.open_flags_count,
  rs.critical_flags_count,
  rs.dispute_rate,
  rs.dispute_loss_rate,
  rs.updated_at                                 AS score_last_updated
FROM auth.users u
JOIN profiles p ON p.id = u.id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = u.id
WHERE u.id = '<seller_uuid>';


-- ============================================================
-- 3. FETCH SELLER OPEN FLAGS
-- ============================================================
-- Check for existing unreviewed flags BEFORE inserting a new one.
-- If a matching flag_type already exists and is unreviewed, skip —
-- do not create a duplicate.
-- Ordered: critical first, then warning, then info; newest first.
-- ------------------------------------------------------------

SELECT
  id,
  created_at,
  flag_type,
  severity,
  details,
  listing_id,
  transfer_id
FROM seller_flags
WHERE seller_id = '<seller_uuid>'
  AND reviewed_at IS NULL
ORDER BY
  CASE severity
    WHEN 'critical' THEN 1
    WHEN 'warning'  THEN 2
    WHEN 'info'     THEN 3
  END,
  created_at DESC;


-- ============================================================
-- 4. FETCH SELLER RISK SUMMARY
-- ============================================================
-- Full risk score row plus live flag counts.
-- Use to verify score after refresh or to review overall posture.
-- ------------------------------------------------------------

SELECT
  rs.*,
  (SELECT COUNT(*)
     FROM seller_flags
    WHERE seller_id = rs.seller_id
      AND reviewed_at IS NULL)                  AS current_open_flags,
  (SELECT COUNT(*)
     FROM seller_flags
    WHERE seller_id = rs.seller_id
      AND reviewed_at IS NOT NULL)              AS resolved_flags,
  (SELECT COUNT(*)
     FROM seller_flags
    WHERE seller_id = rs.seller_id
      AND severity = 'critical'
      AND reviewed_at IS NULL)                  AS current_critical_flags
FROM seller_risk_scores rs
WHERE rs.seller_id = '<seller_uuid>';


-- ============================================================
-- 5. RESOLVE FLAG TEMPLATE
-- ============================================================
-- Use when the admin has reviewed a flag and made a decision.
-- resolution_notes is MANDATORY — explain the decision.
--
-- VALID resolution VALUES:
--   dismissed        — false positive or explained away
--   warned           — real signal, seller contacted, monitoring
--   listing_blocked  — seller's listing ability restricted (enforce manually)
--   seller_suspended — full suspension (enforce manually)
--   escalated        — needs second opinion or executive review
--
-- Safety guard: WHERE reviewed_at IS NULL prevents double-resolution.
-- Always run Query 6 (refresh score) after resolving.
-- ------------------------------------------------------------

UPDATE seller_flags
SET
  reviewed_at      = now(),
  reviewed_by      = '<admin_user_uuid>',
  resolution       = '<resolution>',
  resolution_notes = '<explain why this resolution was chosen>'
WHERE id = '<flag_uuid>'
  AND reviewed_at IS NULL;


-- ============================================================
-- 6. REFRESH ONE SELLER SCORE
-- ============================================================
-- Run immediately after inserting or resolving a flag.
-- The function recomputes risk tier, flag counts, and all stats.
--
-- NOTE: The scoring function enforces these Phase C rules:
--   • rapid_send does NOT affect risk tier
--   • Trust stabilization caps tier at 'medium' for
--     accounts > 30 days old with zero dispute losses
--     (unless duplicate_proof/duplicate_evidence present)
-- ------------------------------------------------------------

SELECT refresh_seller_risk_score('<seller_uuid>');

-- Verify the refreshed result:
SELECT
  seller_id,
  risk_tier,
  open_flags_count,
  critical_flags_count,
  dispute_rate,
  dispute_loss_rate,
  updated_at
FROM seller_risk_scores
WHERE seller_id = '<seller_uuid>';


-- ============================================================
-- 7. REFRESH ALL SCORES (BATCH)
-- ============================================================
-- Use during periodic review sweeps (e.g., weekly).
-- Returns the count of sellers processed.
-- ------------------------------------------------------------

SELECT refresh_all_seller_risk_scores();


-- ============================================================
-- 8. DASHBOARD: ALL OPEN FLAGS
-- ============================================================
-- Admin overview of every unreviewed flag across all sellers.
-- Ordered: critical severity first, then oldest flags first
-- (so the most urgent and longest-waiting flags appear at top).
-- ------------------------------------------------------------

SELECT
  sf.id                     AS flag_id,
  sf.created_at,
  sf.seller_id,
  p.display_name            AS seller_name,
  sf.flag_type,
  sf.severity,
  sf.details,
  rs.risk_tier              AS current_risk_tier,
  rs.open_flags_count,
  sf.listing_id,
  sf.transfer_id
FROM seller_flags sf
JOIN profiles p ON p.id = sf.seller_id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = sf.seller_id
WHERE sf.reviewed_at IS NULL
ORDER BY
  CASE sf.severity
    WHEN 'critical' THEN 1
    WHEN 'warning'  THEN 2
    WHEN 'info'     THEN 3
  END,
  sf.created_at ASC;


-- ============================================================
-- 9. AUDIT TRAIL: RECENTLY RESOLVED FLAGS
-- ============================================================
-- Shows all flags resolved in the last 30 days.
-- Includes reviewer name for accountability.
-- Use for periodic audit review and pattern analysis.
-- ------------------------------------------------------------

SELECT
  sf.id                         AS flag_id,
  sf.seller_id,
  p.display_name                AS seller_name,
  sf.flag_type,
  sf.severity,
  sf.resolution,
  sf.resolution_notes,
  sf.reviewed_at,
  sf.reviewed_by,
  admin_p.display_name          AS reviewed_by_name
FROM seller_flags sf
JOIN profiles p ON p.id = sf.seller_id
LEFT JOIN profiles admin_p ON admin_p.id = sf.reviewed_by
WHERE sf.reviewed_at IS NOT NULL
  AND sf.reviewed_at > now() - interval '30 days'
ORDER BY sf.reviewed_at DESC;


-- ============================================================
-- 10. TRUST STABILIZATION CHECK
-- ============================================================
-- Identifies sellers who qualify for trust stabilization but
-- currently have a risk tier of 'high' or 'critical'.
--
-- Trust stabilization criteria:
--   account_age_days > 30 AND dispute_loss_rate = 0
--   AND no open duplicate_proof or duplicate_evidence flags
--
-- If a seller appears here, their tier should be capped at 'medium'.
-- The refresh_seller_risk_score() function applies this automatically,
-- but run this query to catch any stale scores that haven't been
-- refreshed since the Phase C rule change.
-- ------------------------------------------------------------

SELECT
  rs.seller_id,
  p.display_name,
  rs.risk_tier                  AS current_tier,
  rs.account_age_days,
  rs.dispute_loss_rate,
  rs.open_flags_count,
  rs.critical_flags_count,
  rs.updated_at                 AS score_last_updated,
  (SELECT COUNT(*)
     FROM seller_flags
    WHERE seller_id = rs.seller_id
      AND reviewed_at IS NULL
      AND flag_type IN ('duplicate_proof', 'duplicate_evidence'))
                                AS open_dup_flags
FROM seller_risk_scores rs
JOIN profiles p ON p.id = rs.seller_id
WHERE rs.risk_tier IN ('high', 'critical')
  AND rs.account_age_days > 30
  AND rs.dispute_loss_rate = 0
  AND NOT EXISTS (
    SELECT 1 FROM seller_flags
     WHERE seller_id = rs.seller_id
       AND reviewed_at IS NULL
       AND flag_type IN ('duplicate_proof', 'duplicate_evidence')
  )
ORDER BY rs.risk_tier DESC, rs.account_age_days DESC;
