# Phase E — Automation-Assist Layer

**Date:** 2026-04-06
**Status:** Design Complete — Ready for Implementation
**Prerequisites:** Phase B (detection + scoring), Phase C (manual review + SQL pack), Phase D (soft enforcement via `can_create_listing`) all complete and verified.

---

## SECTION 1 — Phase E Scope

### What Phase E Includes

Phase E replaces the operator's current workflow of running 10 separate detection queries, manually cross-referencing results, and hunting for stale scores. It consolidates everything into a single SQL operations pack that surfaces the right sellers in the right order — without making any enforcement decisions automatically.

1. A unified review queue query that merges all 10 detection rules into one prioritized result set, annotated with existing flag state so the operator never creates duplicate flags.
2. Score staleness detection queries that identify sellers whose `seller_risk_scores` row is outdated relative to their actual activity.
3. Pattern escalation queries that surface sellers with repeated warning-level flags (potential candidates for enforcement upgrades).
4. Trust stabilization staleness queries that find established clean sellers stuck at an artificially high tier.
5. Manual batch refresh helpers that let the operator refresh a targeted subset of stale sellers in one operation.

### What Phase E Excludes

- No automatic flag insertion. Detection results are surfaced; the human decides whether to flag.
- No automatic enforcement. No bans, no suspensions, no listing blocks applied by code.
- No schema changes. All queries run against existing Phase B tables (`seller_flags`, `seller_risk_scores`, `listings`, `transfers`, `profiles`, `auth.users`).
- No new database functions. All logic lives in SELECT queries the operator runs manually.
- No background jobs, cron tasks, triggers, or scheduled functions.
- No buyer-facing or seller-facing UI changes. No app screen modifications.
- No changes to payout, refund, or dispute resolution logic.
- No changes to `can_create_listing()` or any Phase D code.
- No email, notification, or alerting systems.

### Design Principle

Phase E is a lens, not an engine. It makes the operator faster and more accurate by pre-computing what they'd otherwise calculate by hand. Every action remains a deliberate manual step using the Phase C SQL pack templates.

---

## SECTION 2 — Review Queue Design

### Problem

Today the operator runs 10 detection queries sequentially, copies results to a spreadsheet, deduplicates against open flags manually, then decides who to investigate first. This is slow, error-prone, and doesn't scale past ~20 active sellers.

### Unified Review Queue

A single query that:

1. Runs all 10 detection rules as CTEs (Common Table Expressions).
2. UNIONs the results into a normalized shape: `seller_id`, `display_name`, `flag_type`, `suggested_severity`, `signal_detail`, `listing_ids`, `transfer_ids`.
3. LEFT JOINs against `seller_flags` to annotate each row with whether an open (unreviewed) flag already exists for that `seller_id + flag_type` pair.
4. LEFT JOINs against `seller_risk_scores` to include current `risk_tier`, `open_flags_count`, and `score_last_updated`.
5. Applies a composite priority sort.

### Priority Sort Logic

The queue is sorted by a composite priority that considers three dimensions:

**Dimension 1 — Suggested severity (weight: primary)**
- critical → 1
- warning → 2
- info → 3

**Dimension 2 — Existing flag state (weight: secondary)**
- No existing open flag for this signal → 0 (needs new flag — higher priority)
- Open flag already exists → 1 (already tracked — lower priority)

**Dimension 3 — Score staleness (weight: tertiary)**
- Score is stale (activity newer than `updated_at`) → 0 (stale — higher priority)
- Score is fresh → 1

**Dimension 4 — Seller risk tier (weight: quaternary)**
- critical → 1
- high → 2
- medium → 3
- low / null → 4

Within equal priority, rows are ordered by `seller_id` for stable grouping (so all signals for one seller appear together).

### Queue Output Columns

| Column | Description |
|--------|-------------|
| `priority_rank` | Computed composite rank for sorting |
| `seller_id` | UUID |
| `display_name` | From profiles |
| `flag_type` | Which of the 10 rules matched |
| `suggested_severity` | Per Phase C severity policy |
| `signal_detail` | Human-readable summary (e.g., "7 listings for Ultra Music Fest 2026-03-28") |
| `current_risk_tier` | From seller_risk_scores (NULL if no row) |
| `open_flags_count` | Current open flags for this seller |
| `has_open_flag_for_type` | Boolean: does an unreviewed flag with this flag_type already exist? |
| `score_is_stale` | Boolean: has the seller had activity since last score refresh? |
| `score_last_updated` | Timestamp from seller_risk_scores |
| `listing_ids` | Array of relevant listing UUIDs (where applicable) |
| `transfer_ids` | Array of relevant transfer UUIDs (where applicable) |

### Operator Workflow with Queue

1. Run the unified review queue query.
2. Work top-to-bottom. For each row where `has_open_flag_for_type = false`:
   a. Inspect seller context (Phase C Query 2).
   b. Determine severity (Phase C Section 4 rules).
   c. Insert flag (Phase C Query 1).
   d. Refresh score (Phase C Query 6).
3. Skip rows where `has_open_flag_for_type = true` (already tracked).
4. If `score_is_stale = true`, refresh the seller's score first — the tier may change and affect priority.

---

## SECTION 3 — Score Staleness Logic

### Definition

A seller's risk score is **stale** when activity has occurred that could change their risk tier but the score has not been refreshed since that activity.

### Staleness Rules

**Rule S1 — New transfer activity**
The seller has a transfer with `created_at > seller_risk_scores.updated_at`. This could affect: `total_completed`, `total_disputes`, `total_expired`, `rapid_send_count`, `dispute_rate`, `dispute_loss_rate`, `expiry_rate`.

**Rule S2 — New listing activity**
The seller has a listing with `created_at > seller_risk_scores.updated_at`. This could affect: `total_listings`, `active_listings`, `duplicate_proof_count`.

**Rule S3 — Transfer status change**
The seller has a transfer where any of `seller_sent_at`, `dispute_resolved_at`, or status transition timestamps are more recent than `seller_risk_scores.updated_at`. This catches mid-lifecycle events like disputes resolving or transfers expiring.

**Rule S4 — Flag activity**
The seller has a `seller_flags` row with `created_at > seller_risk_scores.updated_at` OR `reviewed_at > seller_risk_scores.updated_at`. This means flags were inserted or resolved but the score wasn't refreshed afterward (operator forgot Step 6/9 of the Phase C workflow).

**Rule S5 — No score row at all**
The seller has listings or transfers but no row in `seller_risk_scores`. This seller has never been scored.

### Staleness Tiers

- **Critical staleness:** Score is stale AND the seller currently has `risk_tier IN ('high', 'critical')` or has open critical flags. These sellers are high-risk and their score may be wrong.
- **Standard staleness:** Score is stale AND the seller has `risk_tier IN ('low', 'medium')` or is unscored. Lower urgency but should still be refreshed during review sweeps.

---

## SECTION 4 — SQL Pack

The Phase E SQL pack contains 6 query blocks. All are SELECT-only except the batch refresh helper (which calls existing Phase B functions).

### Query E1 — Sellers Needing Score Refresh

Identifies all sellers with stale scores, ordered by staleness urgency.

```sql
-- E1: SELLERS NEEDING SCORE REFRESH
-- Surfaces sellers whose risk score is outdated.
-- Run before the review queue to ensure tiers are current.
-- After reviewing results, use Phase C Query 6 to refresh individuals
-- or Query E6 to batch-refresh the full list.

WITH seller_activity AS (
  SELECT
    s.seller_id,
    MAX(s.latest_transfer)  AS latest_transfer,
    MAX(s.latest_listing)   AS latest_listing,
    MAX(s.latest_flag)      AS latest_flag
  FROM (
    -- Most recent transfer (creation or status change)
    SELECT seller_id,
           GREATEST(MAX(created_at), MAX(COALESCE(seller_sent_at, '1970-01-01')),
                    MAX(COALESCE(dispute_resolved_at, '1970-01-01'))) AS latest_transfer,
           NULL::timestamptz AS latest_listing,
           NULL::timestamptz AS latest_flag
      FROM transfers WHERE seller_id IS NOT NULL
     GROUP BY seller_id
    UNION ALL
    -- Most recent listing
    SELECT seller_id,
           NULL::timestamptz,
           MAX(created_at),
           NULL::timestamptz
      FROM listings
     GROUP BY seller_id
    UNION ALL
    -- Most recent flag insert or resolution
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
WHERE rs.seller_id IS NULL                                            -- never scored
   OR GREATEST(sa.latest_transfer, sa.latest_listing, sa.latest_flag)
      > rs.updated_at                                                 -- activity since last refresh
ORDER BY
  CASE
    WHEN rs.seller_id IS NULL THEN 1                                  -- unscored first
    WHEN rs.risk_tier IN ('high','critical') THEN 2                   -- high-risk stale next
    ELSE 3
  END,
  GREATEST(sa.latest_transfer, sa.latest_listing, sa.latest_flag) - COALESCE(rs.updated_at, '1970-01-01') DESC;
```

### Query E2 — Top Risky Sellers With No Open Flags

Surfaces sellers at elevated risk tiers who have zero unreviewed flags — potential blind spots the operator should investigate.

```sql
-- E2: TOP RISKY SELLERS WITH NO OPEN FLAGS
-- These sellers have risk scores indicating concern, but no flags
-- have been raised. This may mean detection queries haven't been
-- run recently, or signals were missed during a previous sweep.

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
```

### Query E3 — Unified Review Queue

The core Phase E query. Consolidates all 10 detection rules into a single prioritized list.

```sql
-- E3: UNIFIED REVIEW QUEUE
-- Merges all 10 detection rules into one prioritized result set.
-- Each row = one seller × one signal that currently fires.
-- Annotated with: existing flag state, score staleness, current tier.
--
-- SEVERITY POLICY ENCODED:
--   high_dispute_rate → max WARNING (never critical)
--   rapid_send → INFO default; WARNING only if age < 3 AND count > 5
--   same_event_overload → CRITICAL only if > 6 AND age < 7
--   Trust stabilization applied via risk_tier join

WITH
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
      CASE WHEN rs.updated_at IS NULL
                OR rs.updated_at < COALESCE(
                     (SELECT MAX(created_at) FROM transfers WHERE seller_id = sig.seller_id),
                     (SELECT MAX(created_at) FROM listings  WHERE seller_id = sig.seller_id),
                     rs.updated_at)
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
  (rs.updated_at IS NULL
   OR rs.updated_at < COALESCE(
        (SELECT MAX(created_at) FROM transfers WHERE seller_id = sig.seller_id),
        (SELECT MAX(created_at) FROM listings  WHERE seller_id = sig.seller_id),
        rs.updated_at))                 AS score_is_stale,
  rs.updated_at                         AS score_last_updated,
  sig.listing_ids,
  sig.transfer_ids
FROM all_signals sig
JOIN profiles p ON p.id = sig.seller_id
LEFT JOIN seller_risk_scores rs ON rs.seller_id = sig.seller_id
LEFT JOIN LATERAL (
  SELECT sf.id FROM seller_flags sf
   WHERE sf.seller_id = sig.seller_id
     AND sf.flag_type  = sig.flag_type
     AND sf.reviewed_at IS NULL
   LIMIT 1
) existing ON true
ORDER BY priority_rank;
```

### Query E4 — Trust Stabilization: Stale Candidates

Sellers who qualify for trust stabilization but have a stale score that hasn't applied it yet.

```sql
-- E4: TRUST STABILIZATION — STALE CANDIDATES
-- Sellers with age > 30d, loss_rate = 0, tier = high/critical,
-- and no open duplicate_proof/duplicate_evidence flags.
-- These sellers should have their scores refreshed so the
-- trust stabilization cap (medium) takes effect.

SELECT
  rs.seller_id,
  p.display_name,
  rs.risk_tier                          AS current_tier,
  rs.account_age_days,
  rs.dispute_loss_rate,
  rs.open_flags_count,
  rs.updated_at                         AS score_last_updated,
  GREATEST(
    (SELECT MAX(created_at) FROM transfers WHERE seller_id = rs.seller_id),
    (SELECT MAX(created_at) FROM listings  WHERE seller_id = rs.seller_id)
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
```

### Query E5 — Sellers With Repeated Warning Patterns

Surfaces sellers who have been warned multiple times for the same flag type, suggesting the behavior is persistent and may warrant escalation to `listing_blocked` or `seller_suspended`.

```sql
-- E5: REPEATED WARNING PATTERNS
-- Sellers with 2+ resolved flags of the same flag_type where
-- the resolution was 'warned' (not dismissed or escalated).
-- These are candidates for enforcement escalation.

SELECT
  sf.seller_id,
  p.display_name,
  sf.flag_type,
  COUNT(*)                              AS times_warned,
  MIN(sf.created_at)                    AS first_warned,
  MAX(sf.reviewed_at)                   AS last_warned,
  rs.risk_tier                          AS current_tier,
  rs.open_flags_count,
  -- Does an open flag for this type currently exist?
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
```

### Query E6 — Manual Batch Refresh Helper

Refreshes scores for all sellers identified as stale. Uses the existing `refresh_seller_risk_score()` function. This is the only non-SELECT query in the Phase E pack.

```sql
-- E6: MANUAL BATCH REFRESH — STALE SELLERS ONLY
-- Refreshes scores only for sellers whose scores are stale.
-- More targeted than refresh_all_seller_risk_scores() which
-- processes every seller regardless of staleness.
--
-- Returns the count of sellers refreshed and their new tiers.
-- Run this BEFORE the unified review queue (E3) to ensure
-- the queue reflects current risk tiers.

DO $$
DECLARE
  v_seller_id uuid;
  v_count int := 0;
BEGIN
  FOR v_seller_id IN
    -- Sellers with activity newer than their score
    SELECT DISTINCT sub.seller_id
    FROM (
      SELECT t.seller_id, MAX(GREATEST(t.created_at,
             COALESCE(t.seller_sent_at, '1970-01-01'),
             COALESCE(t.dispute_resolved_at, '1970-01-01'))) AS latest
        FROM transfers t WHERE t.seller_id IS NOT NULL
       GROUP BY t.seller_id
      UNION ALL
      SELECT l.seller_id, MAX(l.created_at)
        FROM listings l GROUP BY l.seller_id
      UNION ALL
      SELECT sf.seller_id, MAX(GREATEST(sf.created_at,
             COALESCE(sf.reviewed_at, '1970-01-01')))
        FROM seller_flags sf GROUP BY sf.seller_id
    ) sub
    LEFT JOIN seller_risk_scores rs ON rs.seller_id = sub.seller_id
    WHERE rs.seller_id IS NULL               -- never scored
       OR sub.latest > rs.updated_at         -- activity since last refresh
  LOOP
    PERFORM refresh_seller_risk_score(v_seller_id);
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE 'Refreshed % stale seller scores.', v_count;
END;
$$;

-- Verify: show all sellers whose scores were just refreshed (updated in last 5 seconds)
SELECT seller_id, risk_tier, open_flags_count, critical_flags_count, updated_at
  FROM seller_risk_scores
 WHERE updated_at > now() - interval '5 seconds'
 ORDER BY risk_tier DESC;
```

---

## SECTION 5 — Automation Boundary

### What Remains Fully Manual

| Action | Why |
|--------|-----|
| Flag insertion | Human decides severity and writes details. Phase C Query 1. |
| Flag resolution | Human chooses resolution and writes notes. Phase C Query 5. |
| Enforcement decisions | `listing_blocked`, `seller_suspended`, `escalated` require human judgment. |
| Contacting sellers | Manual email/message outside the system. |
| `is_listing_blocked` toggle | Admin sets manually in Supabase. |
| Score refresh after flag operations | Human runs Phase C Query 6 after each flag insert/resolve. |

### What Becomes Automation-Assisted

| Action | How it helps | Still requires |
|--------|-------------|----------------|
| Detection sweep | Unified review queue (E3) replaces running 10 queries | Human reviews each row and decides whether to flag |
| Deduplication | `has_open_flag_for_type` column shows if a flag already exists | Human confirms before skipping |
| Staleness identification | E1 surfaces stale scores; E3 annotates staleness per row | Human decides when to refresh |
| Batch score refresh | E6 refreshes only stale sellers in one operation | Human runs it explicitly |
| Pattern escalation | E5 surfaces repeated warnings | Human decides whether to escalate |
| Trust stabilization review | E4 finds over-penalized clean sellers | Human decides whether to refresh and confirm |
| Prioritization | Composite sort puts critical/new/stale items first | Human works top-to-bottom |

### The Bright Line

The system never inserts a flag, never changes a resolution, never modifies `is_listing_blocked`, never changes `risk_tier` directly, and never contacts a seller. It only reads data, computes priority, and presents it. The human pulls every trigger.

---

## SECTION 6 — Files To Produce

Phase E requires exactly **one new file** and **zero schema changes**.

| # | File | Type | Description |
|---|------|------|-------------|
| 1 | `PHASE_E_AUTOMATION_ASSIST_SQL_PACK.sql` | New | 6 queries: stale score detection (E1), risky sellers with no flags (E2), unified review queue (E3), trust stabilization stale candidates (E4), repeated warning patterns (E5), batch refresh helper (E6). File header includes Phase E workflow and the automation boundary summary. |

No migrations. No function changes. No app code changes. No type changes.

The design document (`PHASE_E_AUTOMATION_ASSIST_DESIGN.md`, this file) serves as the operational runbook.

---

## SECTION 7 — Exact Claude Code Prompt

```
You are implementing Phase E of the SnatchIt marketplace trust-and-safety system.

CONTEXT — Existing system:
- Phase B: seller_flags table, seller_risk_scores table, refresh_seller_risk_score(),
  refresh_all_seller_risk_scores(), PHASE_B_DETECTION_QUERIES.sql (10 rules)
- Phase C: PHASE_C_ADMIN_SQL_PACK.sql (manual flag lifecycle queries)
- Phase D: can_create_listing() RPC (soft enforcement)

SEVERITY POLICY (must be encoded in the review queue):
1. high_dispute_rate max severity = warning (NEVER critical)
2. rapid_send default = info; warning only if account_age_days < 3 AND count > 5
3. same_event_overload critical only if > 6 listings AND account_age_days < 7
4. Trust stabilization: age > 30d AND loss_rate = 0 → tier cap = medium
   (except with open duplicate_proof/duplicate_evidence flags)

TASK: Create exactly ONE file: PHASE_E_AUTOMATION_ASSIST_SQL_PACK.sql

This file must contain 6 query blocks with clear header comments:

1. E1 — SELLERS NEEDING SCORE REFRESH
   - Identify sellers whose seller_risk_scores.updated_at is older than their
     most recent transfer activity (created_at, seller_sent_at, dispute_resolved_at),
     listing activity (created_at), or flag activity (created_at, reviewed_at)
   - Include sellers with no seller_risk_scores row at all (unscored)
   - Output: seller_id, display_name, current_tier (or 'UNSCORED'), score_updated_at,
     latest_activity, staleness_interval, open_flags_count, critical_flags_count,
     staleness_tier (UNSCORED / CRITICAL_STALE / STANDARD_STALE)
   - Sort: unscored first, then high/critical tier stale, then others, by staleness desc

2. E2 — TOP RISKY SELLERS WITH NO OPEN FLAGS
   - Sellers in seller_risk_scores with risk_tier IN (medium, high, critical)
     AND open_flags_count = 0
   - Output: full risk score fields, display_name
   - Sort: critical first, then by dispute_loss_rate desc

3. E3 — UNIFIED REVIEW QUEUE
   - Consolidate all 10 detection rules as CTEs
   - UNION ALL into normalized shape: seller_id, flag_type, suggested_severity,
     signal_detail (human-readable), listing_ids, transfer_ids
   - Severity must follow the 4 policy rules above
   - LEFT JOIN seller_flags to compute has_open_flag_for_type (boolean)
   - LEFT JOIN seller_risk_scores for current_risk_tier, open_flags_count
   - Compute score_is_stale boolean
   - Sort by composite priority:
     (1) suggested_severity: critical→1, warning→2, info→3
     (2) has_open_flag_for_type: false→0, true→1
     (3) score_is_stale: true→0, false→1
     (4) current_risk_tier: critical→1, high→2, medium→3, low/null→4
     (5) seller_id for stable grouping
   - Output columns: priority_rank, seller_id, display_name, flag_type,
     suggested_severity, signal_detail, current_risk_tier, open_flags_count,
     has_open_flag_for_type, score_is_stale, score_last_updated,
     listing_ids, transfer_ids

4. E4 — TRUST STABILIZATION STALE CANDIDATES
   - Sellers with account_age_days > 30, dispute_loss_rate = 0,
     risk_tier IN (high, critical), no open duplicate_proof or duplicate_evidence flags
   - These sellers should be refreshed so the trust stabilization cap applies
   - Output: seller_id, display_name, current_tier, account_age_days,
     dispute_loss_rate, open_flags_count, score_last_updated, latest_activity

5. E5 — REPEATED WARNING PATTERNS
   - Sellers with 2+ resolved flags where resolution = 'warned' for the same flag_type
   - Output: seller_id, display_name, flag_type, times_warned, first_warned,
     last_warned, current_tier, open_flags_count, has_current_open_flag (boolean)
   - Sort: times_warned desc

6. E6 — MANUAL BATCH REFRESH (STALE ONLY)
   - DO $$ block that loops over stale sellers (same staleness logic as E1)
     and calls refresh_seller_risk_score() for each
   - RAISE NOTICE with count of sellers refreshed
   - Followed by verification SELECT showing recently updated scores

FILE HEADER must include:
- Title: Phase E — Automation-Assist SQL Pack
- Date
- Warning: "Automation-ASSIST only. No automatic flag insertion. No automatic enforcement.
  Human reviews every signal and decides every action."
- The 4 severity policy rules
- Brief description of how Phase E fits into the operator workflow:
  "Run E6 (batch refresh) → Run E3 (review queue) → Work top-to-bottom using Phase C templates"

CRITICAL RULES:
- Do NOT create any new tables or alter existing tables
- Do NOT create any new persistent functions (the DO $$ block in E6 is an anonymous block, not a stored function)
- Do NOT add any RLS policies
- Do NOT add any triggers or background jobs
- All queries except E6 must be pure SELECT statements
- Every parameterized value uses '<placeholder>' style
- Include comments explaining when and why to use each query
- Reference Phase C queries by number where the operator should use them next

Save the file to the project root as PHASE_E_AUTOMATION_ASSIST_SQL_PACK.sql
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
