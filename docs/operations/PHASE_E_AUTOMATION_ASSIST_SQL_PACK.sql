-- ============================================================
-- Phase E — Automation-Assist SQL Pack
-- Date: 2026-04-06
-- ============================================================
--
-- WARNING: Automation-ASSIST only.
-- No automatic flag insertion. No automatic enforcement.
-- Human reviews every signal and decides every action.
--
-- SEVERITY POLICY:
--   RULE 1: high_dispute_rate max severity = WARNING (never critical)
--   RULE 2: rapid_send default = INFO; WARNING only if age < 3d AND count > 5
--   RULE 3: same_event_overload CRITICAL only if > 6 listings AND age < 7d
--   RULE 4: Trust stabilization: age > 30d AND loss_rate = 0 → tier cap = medium
--           (except with open duplicate_proof / duplicate_evidence flags)
--
-- OPERATOR WORKFLOW:
--   1. Run E6 (batch refresh stale scores)
--   2. Run E3 (unified review queue)
--   3. Work top-to-bottom using Phase C templates:
--      → Phase C Query 2 (inspect seller context)
--      → Phase C Query 1 (insert flag)
--      → Phase C Query 6 (refresh score)
--      → Phase C Query 5 (resolve flag)
--
-- ============================================================


-- ============================================================
-- E1: SELLERS NEEDING SCORE REFRESH
-- ============================================================
-- Surfaces sellers whose risk score is outdated relative to
-- their actual activity across transfers, listings, and flags.
-- Run before the review queue to ensure tiers are current.
-- After reviewing, use Phase C Query 6 for individuals or
-- E6 below to batch-refresh all stale sellers.
--
-- STALENESS RULES (from Phase E Section 3):
--   S1: transfer created_at, seller_sent_at, or dispute_resolved_at > score updated_at
--   S2: listing created_at > score updated_at
--   S3: transfer status-change timestamps > score updated_at
--   S4: seller_flags created_at or reviewed_at > score updated_at
--   S5: no seller_risk_scores row at all (unscored)
-- ------------------------------------------------------------

WITH seller_activity AS (
  SELECT
    s.seller_id,
    MAX(s.latest_transfer)  AS latest_transfer,
    MAX(s.latest_listing)   AS latest_listing,
    MAX(s.latest_flag)      AS latest_flag
  FROM (
    -- S1 + S3: most recent transfer (creation or status change)
    SELECT seller_id,
           GREATEST(MAX(created_at), MAX(COALESCE(seller_sent_at, '1970-01-01')),
                    MAX(COALESCE(dispute_resolved_at, '1970-01-01'))) AS latest_transfer,
           NULL::timestamptz AS latest_listing,
           NULL::timestamptz AS latest_flag
      FROM transfers WHERE seller_id IS NOT NULL
     GROUP BY seller_id
    UNION ALL
    -- S2: most recent listing
    SELECT seller_id,
           NULL::timestamptz,
           MAX(created_at),
           NULL::timestamptz
      FROM listings
     GROUP BY seller_id
    UNION ALL
    -- S4: most recent flag insert or resolution
    SELECT seller_id,
           NULL::timestamptz,
           NULL::timestamptz,
           GREATEST(MAX(created_at), MAX(COALESCE(reviewed_at, '1970-01-01')))
      FROM seller_flags
     GROUP BY seller_id
  ) s
  GROUP BY s.seller_id
)
SELECT
  sa.seller_id,
  p.display_name,
  rs.risk_tier                          AS current_tier,
  rs.updated_at                         AS score_updated_at,
  GREATEST(sa.latest_transfer, sa.latest_listing, sa.latest_flag)
                                        AS latest_activity,
  GREATEST(sa.latest_transfer, sa.latest_listing, sa.latest_flag) - rs.updated_at
                                        AS staleness_interval,
  rs.open_flags_count,
  rs.critical_flags_count,
  CASE
    WHEN rs.seller_id IS NULL THEN 'UNSCORED'
    WHEN rs.risk_tier IN ('high','critical') THEN 'CRITICAL_STALE'
    ELSE 'STANDARD_STALE'
  END                                   AS staleness_tier
FROM seller_activity sa
JOIN profiles p ON p.id = sa.seller_id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = sa.seller_id
WHERE rs.seller_id IS NULL                                            -- S5: never scored
   OR GREATEST(sa.latest_transfer, sa.latest_listing, sa.latest_flag)
      > rs.updated_at                                                 -- S1-S4: activity since last refresh
ORDER BY
  CASE
    WHEN rs.seller_id IS NULL THEN 1                                  -- unscored first
    WHEN rs.risk_tier IN ('high','critical') THEN 2                   -- high-risk stale next
    ELSE 3
  END,
  GREATEST(sa.latest_transfer, sa.latest_listing, sa.latest_flag)
    - COALESCE(rs.updated_at, '1970-01-01') DESC;


-- ============================================================
-- E2: TOP RISKY SELLERS WITH NO OPEN FLAGS
-- ============================================================
-- Sellers at elevated risk tiers with zero unreviewed flags.
-- These are potential blind spots — detection queries may not
-- have been run recently, or signals were missed.
-- After reviewing, use Phase C Query 2 to inspect, then
-- Phase C Query 1 to insert flags where warranted.
-- ------------------------------------------------------------

SELECT
  rs.seller_id,
  p.display_name,
  rs.risk_tier,
  rs.account_age_days,
  rs.total_completed,
  rs.dispute_rate,
  rs.dispute_loss_rate,
  rs.duplicate_proof_count,
  rs.duplicate_evidence_count,
  rs.rapid_send_count,
  rs.expiry_rate,
  rs.updated_at                         AS score_updated_at
FROM seller_risk_scores rs
JOIN profiles p ON p.id = rs.seller_id
WHERE rs.risk_tier IN ('medium', 'high', 'critical')
  AND rs.open_flags_count = 0
ORDER BY
  CASE rs.risk_tier
    WHEN 'critical' THEN 1
    WHEN 'high'     THEN 2
    WHEN 'medium'   THEN 3
  END,
  rs.dispute_loss_rate DESC;


-- ============================================================
-- E3: UNIFIED REVIEW QUEUE
-- ============================================================
-- Merges all 10 detection rules into one prioritized result set.
-- Each row = one seller × one signal that currently fires.
-- Annotated with: existing flag state, score staleness, current tier.
--
-- SEVERITY POLICY ENCODED:
--   high_dispute_rate → max WARNING (never critical)
--   rapid_send → INFO default; WARNING only if age < 3 AND count > 5
--   same_event_overload → CRITICAL only if > 6 AND age < 7
--   Trust stabilization applied via risk_tier join
--
-- STALENESS LOGIC (full Section 3 rules):
--   Uses a per-seller CTE that computes the latest activity
--   across transfers (created_at, seller_sent_at, dispute_resolved_at),
--   listings (created_at), and flags (created_at, reviewed_at).
--   A seller is stale if: no score row exists (unscored), OR
--   any of those timestamps > seller_risk_scores.updated_at.
-- ------------------------------------------------------------

WITH
-- ── Staleness: per-seller latest activity across all sources ──
seller_latest_activity AS (
  SELECT
    sub.seller_id,
    MAX(sub.ts) AS latest_activity
  FROM (
    -- S1 + S3: transfer creation + status-change timestamps
    SELECT seller_id,
           GREATEST(
             MAX(created_at),
             MAX(COALESCE(seller_sent_at, '1970-01-01')),
             MAX(COALESCE(dispute_resolved_at, '1970-01-01'))
           ) AS ts
      FROM transfers WHERE seller_id IS NOT NULL
     GROUP BY seller_id
    UNION ALL
    -- S2: listing creation
    SELECT seller_id, MAX(created_at)
      FROM listings
     GROUP BY seller_id
    UNION ALL
    -- S4: flag insert + resolution
    SELECT seller_id,
           GREATEST(MAX(created_at), MAX(COALESCE(reviewed_at, '1970-01-01')))
      FROM seller_flags
     GROUP BY seller_id
  ) sub
  GROUP BY sub.seller_id
),

-- ── Detection rules ──────────────────────────────────────────

-- Rule 1: same_event_overload
r1 AS (
  SELECT
    l.seller_id,
    'same_event_overload'::text AS flag_type,
    CASE
      WHEN COUNT(*) > 6 AND EXTRACT(DAY FROM now() - u.created_at) < 7 THEN 'critical'
      ELSE 'warning'
    END AS suggested_severity,
    'event="' || l.event_name || '" date=' || l.event_date::text || ' count=' || COUNT(*)::text AS signal_detail,
    array_agg(l.id) AS listing_ids,
    NULL::uuid[] AS transfer_ids
  FROM listings l
  JOIN auth.users u ON u.id = l.seller_id
  WHERE l.status = 'active'
  GROUP BY l.seller_id, l.event_name, l.event_date, u.created_at
  HAVING COUNT(*) > 3
),
-- Rule 2: high_dispute_rate (max severity = warning)
r2 AS (
  SELECT
    t.seller_id,
    'high_dispute_rate'::text,
    'warning'::text,
    'completed=' || COUNT(*) FILTER (WHERE t.status IN ('buyer_confirmed','auto_released'))::text
      || ' disputes=' || COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL)::text
      || ' rate=' || ROUND(
        COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL)::numeric
        / NULLIF(COUNT(*) FILTER (WHERE t.status IN ('buyer_confirmed','auto_released')), 0), 2)::text,
    NULL::uuid[],
    NULL::uuid[]
  FROM transfers t
  WHERE t.seller_id IS NOT NULL
  GROUP BY t.seller_id
  HAVING COUNT(*) FILTER (WHERE t.status IN ('buyer_confirmed','auto_released')) >= 3
     AND COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL)::numeric
         / NULLIF(COUNT(*) FILTER (WHERE t.status IN ('buyer_confirmed','auto_released')), 0) > 0.20
),
-- Rule 3: high_dispute_loss_rate
r3 AS (
  SELECT
    t.seller_id,
    'high_dispute_loss_rate'::text,
    'critical'::text,
    'disputes=' || COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL)::text
      || ' losses=' || COUNT(*) FILTER (WHERE t.dispute_resolution = 'resolved_buyer_refunded')::text,
    NULL::uuid[],
    NULL::uuid[]
  FROM transfers t
  WHERE t.seller_id IS NOT NULL
  GROUP BY t.seller_id
  HAVING COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL) >= 2
     AND COUNT(*) FILTER (WHERE t.dispute_resolution = 'resolved_buyer_refunded')::numeric
         / NULLIF(COUNT(*) FILTER (WHERE t.status = 'disputed' OR t.dispute_resolved_at IS NOT NULL), 0) > 0.50
),
-- Rule 4: duplicate_proof
r4 AS (
  SELECT
    l.seller_id,
    'duplicate_proof'::text,
    'critical'::text,
    'path="' || l.proof_of_ownership_path || '" used_on=' || COUNT(*)::text || ' active listings',
    array_agg(l.id),
    NULL::uuid[]
  FROM listings l
  WHERE l.status = 'active' AND l.proof_of_ownership_path IS NOT NULL
  GROUP BY l.seller_id, l.proof_of_ownership_path
  HAVING COUNT(*) > 1
),
-- Rule 5: duplicate_evidence
r5 AS (
  SELECT
    t.seller_id,
    'duplicate_evidence'::text,
    'critical'::text,
    'path="' || t.transfer_evidence_path || '" used_on=' || COUNT(*)::text || ' transfers',
    NULL::uuid[],
    array_agg(t.id)
  FROM transfers t
  WHERE t.transfer_evidence_path IS NOT NULL
  GROUP BY t.seller_id, t.transfer_evidence_path
  HAVING COUNT(*) > 1
),
-- Rule 6: rapid_send (info default; warning only if age < 3 AND count > 5)
r6 AS (
  SELECT
    t.seller_id,
    'rapid_send'::text,
    CASE
      WHEN EXTRACT(DAY FROM now() - u.created_at) < 3 AND COUNT(*) > 5 THEN 'warning'
      ELSE 'info'
    END,
    'rapid_sends=' || COUNT(*)::text || ' account_age=' || EXTRACT(DAY FROM now() - u.created_at)::int::text || 'd',
    NULL::uuid[],
    array_agg(t.id)
  FROM transfers t
  JOIN auth.users u ON u.id = t.seller_id
  WHERE t.seller_sent_at IS NOT NULL
    AND t.seller_sent_at - t.created_at < interval '5 minutes'
  GROUP BY t.seller_id, u.created_at
  HAVING COUNT(*) > 2
),
-- Rule 7: new_account_high_value
r7 AS (
  SELECT
    l.seller_id,
    'new_account_high_value'::text,
    'warning'::text,
    'age=' || EXTRACT(DAY FROM now() - u.created_at)::int::text || 'd max_price=$'
      || GREATEST(l.starting_bid, COALESCE(l.buy_now_price, 0))::text,
    ARRAY[l.id],
    NULL::uuid[]
  FROM listings l
  JOIN auth.users u ON u.id = l.seller_id
  WHERE l.status = 'active'
    AND EXTRACT(DAY FROM now() - u.created_at) < 7
    AND (l.starting_bid > 200 OR COALESCE(l.buy_now_price, 0) > 200)
),
-- Rule 8: high_listing_velocity
r8 AS (
  SELECT
    l.seller_id,
    'high_listing_velocity'::text,
    CASE WHEN COUNT(*) > 10 THEN 'critical' ELSE 'warning' END,
    'listings_24h=' || COUNT(*)::text,
    array_agg(l.id),
    NULL::uuid[]
  FROM listings l
  WHERE l.created_at > now() - interval '24 hours'
  GROUP BY l.seller_id
  HAVING COUNT(*) > 5
),
-- Rule 9: missing_payout_setup
r9 AS (
  SELECT
    l.seller_id,
    'missing_payout_setup'::text,
    'info'::text,
    'active_listings=' || COUNT(*)::text || ' stripe_connect=NULL',
    array_agg(l.id),
    NULL::uuid[]
  FROM listings l
  JOIN profiles p ON p.id = l.seller_id
  WHERE l.status = 'active'
    AND (p.stripe_connect_id IS NULL OR p.stripe_connect_id = '')
  GROUP BY l.seller_id
),
-- Rule 10: repeated_expiry
r10 AS (
  SELECT
    t.seller_id,
    'repeated_expiry'::text,
    CASE WHEN COUNT(*) > 4 THEN 'critical' ELSE 'warning' END,
    'expired_transfers=' || COUNT(*)::text,
    NULL::uuid[],
    array_agg(t.id)
  FROM transfers t
  WHERE t.status = 'expired'
  GROUP BY t.seller_id
  HAVING COUNT(*) > 2
),
-- Union all rules
all_signals AS (
  SELECT * FROM r1
  UNION ALL SELECT * FROM r2
  UNION ALL SELECT * FROM r3
  UNION ALL SELECT * FROM r4
  UNION ALL SELECT * FROM r5
  UNION ALL SELECT * FROM r6
  UNION ALL SELECT * FROM r7
  UNION ALL SELECT * FROM r8
  UNION ALL SELECT * FROM r9
  UNION ALL SELECT * FROM r10
)
SELECT
  ROW_NUMBER() OVER (
    ORDER BY
      -- Primary: severity
      CASE sig.suggested_severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 WHEN 'info' THEN 3 END,
      -- Secondary: no existing flag for this type = higher priority
      CASE WHEN existing.id IS NULL THEN 0 ELSE 1 END,
      -- Tertiary: stale score = higher priority
      CASE WHEN rs.seller_id IS NULL
                OR sla.latest_activity > rs.updated_at
           THEN 0 ELSE 1 END,
      -- Quaternary: current risk tier
      CASE COALESCE(rs.risk_tier, 'low')
           WHEN 'critical' THEN 1 WHEN 'high' THEN 2
           WHEN 'medium'   THEN 3 ELSE 4 END,
      -- Stable grouping
      sig.seller_id
  )                                     AS priority_rank,
  sig.seller_id,
  p.display_name,
  sig.flag_type,
  sig.suggested_severity,
  sig.signal_detail,
  COALESCE(rs.risk_tier, 'unscored')   AS current_risk_tier,
  COALESCE(rs.open_flags_count, 0)     AS open_flags_count,
  existing.id IS NOT NULL               AS has_open_flag_for_type,
  -- Full staleness: unscored OR any activity source newer than score
  (rs.seller_id IS NULL
   OR sla.latest_activity > rs.updated_at)
                                        AS score_is_stale,
  rs.updated_at                         AS score_last_updated,
  sig.listing_ids,
  sig.transfer_ids
FROM all_signals sig
JOIN profiles p ON p.id = sig.seller_id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = sig.seller_id
LEFT JOIN seller_latest_activity sla ON sla.seller_id = sig.seller_id
LEFT JOIN LATERAL (
  SELECT sf.id FROM seller_flags sf
   WHERE sf.seller_id = sig.seller_id
     AND sf.flag_type  = sig.flag_type
     AND sf.reviewed_at IS NULL
   LIMIT 1
) existing ON true
ORDER BY priority_rank;


-- ============================================================
-- E4: TRUST STABILIZATION — STALE CANDIDATES
-- ============================================================
-- Sellers who qualify for trust stabilization (age > 30d,
-- loss_rate = 0) but still sit at high/critical tier because
-- their score hasn't been refreshed since the Phase C rule change.
-- After reviewing, use Phase C Query 6 to refresh each seller
-- so the trust stabilization cap (medium) takes effect.
-- ------------------------------------------------------------

SELECT
  rs.seller_id,
  p.display_name,
  rs.risk_tier                          AS current_tier,
  rs.account_age_days,
  rs.dispute_loss_rate,
  rs.open_flags_count,
  rs.updated_at                         AS score_last_updated,
  GREATEST(
    (SELECT MAX(GREATEST(created_at,
            COALESCE(seller_sent_at, '1970-01-01'),
            COALESCE(dispute_resolved_at, '1970-01-01')))
       FROM transfers WHERE seller_id = rs.seller_id),
    (SELECT MAX(created_at) FROM listings WHERE seller_id = rs.seller_id)
  )                                     AS latest_activity
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


-- ============================================================
-- E5: REPEATED WARNING PATTERNS
-- ============================================================
-- Sellers warned 2+ times for the same flag_type.
-- These are candidates for enforcement escalation
-- (listing_blocked or seller_suspended).
-- After reviewing, use Phase C Query 2 to inspect the seller,
-- then Phase C Query 1 to insert an escalated flag if warranted.
-- ------------------------------------------------------------

SELECT
  sf.seller_id,
  p.display_name,
  sf.flag_type,
  COUNT(*)                              AS times_warned,
  MIN(sf.created_at)                    AS first_warned,
  MAX(sf.reviewed_at)                   AS last_warned,
  rs.risk_tier                          AS current_tier,
  rs.open_flags_count,
  EXISTS (
    SELECT 1 FROM seller_flags sf2
     WHERE sf2.seller_id = sf.seller_id
       AND sf2.flag_type  = sf.flag_type
       AND sf2.reviewed_at IS NULL
  )                                     AS has_current_open_flag
FROM seller_flags sf
JOIN profiles p ON p.id = sf.seller_id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = sf.seller_id
WHERE sf.resolution = 'warned'
GROUP BY sf.seller_id, p.display_name, sf.flag_type,
         rs.risk_tier, rs.open_flags_count
HAVING COUNT(*) >= 2
ORDER BY COUNT(*) DESC, sf.flag_type;


-- ============================================================
-- E6: MANUAL BATCH REFRESH — STALE SELLERS ONLY
-- ============================================================
-- Refreshes scores only for sellers whose scores are stale,
-- using the same full staleness logic as E1 (rules S1-S5).
-- More targeted than refresh_all_seller_risk_scores().
--
-- Run this BEFORE E3 (review queue) to ensure tiers are current.
--
-- This is a DO $$ anonymous block, NOT a stored function.
-- No schema changes.
-- ------------------------------------------------------------

DO $$
DECLARE
  v_seller_id uuid;
  v_count int := 0;
BEGIN
  FOR v_seller_id IN
    SELECT DISTINCT sub.seller_id
    FROM (
      -- S1 + S3: transfer creation + status-change timestamps
      SELECT t.seller_id,
             GREATEST(MAX(t.created_at),
                      MAX(COALESCE(t.seller_sent_at, '1970-01-01')),
                      MAX(COALESCE(t.dispute_resolved_at, '1970-01-01'))) AS latest
        FROM transfers t WHERE t.seller_id IS NOT NULL
       GROUP BY t.seller_id
      UNION ALL
      -- S2: listing creation
      SELECT l.seller_id, MAX(l.created_at)
        FROM listings l GROUP BY l.seller_id
      UNION ALL
      -- S4: flag insert or resolution
      SELECT sf.seller_id,
             GREATEST(MAX(sf.created_at),
                      MAX(COALESCE(sf.reviewed_at, '1970-01-01')))
        FROM seller_flags sf GROUP BY sf.seller_id
    ) sub
    LEFT JOIN seller_risk_scores rs ON rs.seller_id = sub.seller_id
    WHERE rs.seller_id IS NULL               -- S5: never scored
       OR sub.latest > rs.updated_at         -- S1-S4: activity since last refresh
  LOOP
    PERFORM refresh_seller_risk_score(v_seller_id);
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE 'Refreshed % stale seller scores.', v_count;
END;
$$;

-- Verify: show all sellers whose scores were refreshed in this session.
-- Uses a 1-minute window so the operator has time to review.
SELECT
  seller_id,
  risk_tier,
  open_flags_count,
  critical_flags_count,
  updated_at
FROM seller_risk_scores
WHERE updated_at > now() - interval '1 minute'
ORDER BY
  CASE risk_tier
    WHEN 'critical' THEN 1
    WHEN 'high'     THEN 2
    WHEN 'medium'   THEN 3
    ELSE 4
  END,
  updated_at DESC;
