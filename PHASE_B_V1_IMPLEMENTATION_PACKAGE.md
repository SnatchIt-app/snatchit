# Phase B V1 — Hardened Implementation Package

**Date:** 2026-04-06
**Status:** Ready for immediate implementation
**Inputs reviewed:** PHASE_B_ANTI_FRAUD_DESIGN.md + 012_seller_risk.sql
**Principle:** Safe foundation + observability first. Zero automation. Zero enforcement.

---

## SECTION 1 — What to Keep Right Now

These items ship in Phase B V1. All are additive, read-only, and zero-impact on the running app.

| Item | Rationale |
|------|-----------|
| `seller_flags` table | Core storage. Must exist before anything else. Admin-only, RLS-enabled, no client policies. |
| `seller_risk_scores` table | Materialized cache. Needed for dashboard queries. Admin-only. |
| `refresh_seller_risk_score(uuid)` function | On-demand single-seller recompute. SECURITY DEFINER, called manually by admin. |
| `refresh_all_seller_risk_scores()` function | Batch recompute. Called manually by admin after running detection queries. |
| All indexes from design doc | Required for dashboard query performance. |
| RLS enabled on both tables | Security baseline. No client policies — service role only. |
| 10 read-only detection queries (SELECT only) | Admin runs these manually in SQL Editor to *see* who triggers rules. No INSERTs. |
| Dashboard queries Q1–Q8 | Admin observability. Appended to existing admin SQL pack. |
| TypeScript types for SellerFlag, SellerRiskScore, and union types | Keeps types in sync for future admin UI work. Zero runtime impact. |

---

## SECTION 2 — What to Postpone

These items are **removed from the V1 implementation pass**. They remain in the design doc for later phases.

| Item | Why Postpone | When to Revisit |
|------|-------------|-----------------|
| **Q9: Full detection sweep (INSERT INTO seller_flags)** | Auto-inserting flags before we've validated thresholds against real data is dangerous. False positives on day 1 would pollute the flags table and erode trust in the system. | After running read-only detection queries for 1–2 weeks and confirming thresholds produce zero false positives on known-good sellers. |
| **Listing creation enforcement hook** (`is_listing_blocked` check) | Modifies the listing creation path — the highest-traffic write path in the app. Any bug here blocks all sellers. | After flags + scores are proven stable and admin has manually blocked at least one seller successfully via SQL. |
| **Any automatic flag insertion (triggers, cron, edge functions)** | Automation without a feedback loop is the #1 source of fraud system false positives. We need manual observation first. | After manual sweep has been run 5+ times with zero false positives. |
| **seller_flags_severity_check constraint** | The original CHECK constraint restricts which flag_types can be `critical`. This is premature — during manual flag insertion, admin should be free to set any severity on any type. The constraint can be added later once the severity model is validated. | After 30+ flags have been manually created and severity patterns are established. |
| **Pre-listing check RPC** | App-code change. Not needed until enforcement is active. | Phase B V2. |
| **Admin UI / panel** | Supabase SQL Editor is sufficient for private beta scale. | When flag volume exceeds what SQL Editor can handle comfortably (~50+ flags). |

### Design doc Section 9 (Q9) — Specific deferral note

The full detection sweep query in the design doc uses `INSERT INTO seller_flags ... SELECT` with deduplication logic (`NOT EXISTS` in past 24h). This is well-designed but should only be activated **after** the read-only detection queries have been validated against real data. The V1 package ships the detection queries as SELECT-only. Admin manually creates flags via INSERT after reviewing detection output.

---

## SECTION 3 — Hardened Migration Plan

The migration must be safe to paste into Supabase SQL Editor and re-run without error.

### Changes from original 012_seller_risk.sql

| Change | Reason |
|--------|--------|
| Wrap `CREATE INDEX` in `DO $$ ... IF NOT EXISTS` blocks | Postgres `CREATE INDEX` does not support `IF NOT EXISTS` before v14 without `CONCURRENTLY`. Supabase uses pg15+ but the `DO` block pattern is universally safe and idempotent. |
| Remove `seller_flags_severity_check` CHECK constraint | Postponed per Section 2. Premature restriction. |
| Add explicit `DROP FUNCTION IF EXISTS` before `CREATE OR REPLACE` | Belt-and-suspenders for function signature changes. `CREATE OR REPLACE` only works if return type hasn't changed. |
| Add verification queries at the end | Admin confirms success immediately after running. |
| Wrap the entire migration in a transaction comment block | Supabase SQL Editor auto-wraps in transactions, but comments make intent clear. |

### Hardened migration SQL

See **Section 6** implementation prompt — the exact SQL is embedded there for Claude Code to produce as a file.

---

## SECTION 4 — Final Implementation Order

Execute in exactly this order. Each step must succeed before proceeding.

```
STEP 1: Create hardened migration file
  → /supabase/migrations/012_seller_risk.sql
  → Overwrite the existing draft with the hardened version
  → DO NOT RUN IT YET — just create the file

STEP 2: Run migration manually in Supabase SQL Editor
  → Copy-paste the full contents of 012_seller_risk.sql
  → Verify output: "2 tables created, 2 functions created, 7 indexes created"
  → Run the embedded verification queries at the bottom

STEP 3: Run verification queries
  → SELECT COUNT(*) FROM seller_flags;  -- expect 0
  → SELECT COUNT(*) FROM seller_risk_scores;  -- expect 0
  → SELECT refresh_all_seller_risk_scores();  -- expect integer (seller count)
  → SELECT * FROM seller_risk_scores ORDER BY risk_tier;  -- inspect results

STEP 4: Create detection queries file
  → /PHASE_B_DETECTION_QUERIES.sql
  → SELECT-only queries for all 10 detection rules
  → NO INSERT statements — observation only
  → Run each query in SQL Editor to validate against real data

STEP 5: Update admin SQL pack
  → Append Phase B dashboard queries (Q1–Q8) to /DAY5_ADMIN_SQL_PACK.sql
  → Run Q7 (risk score summary) to confirm scores look right

STEP 6: Update TypeScript types
  → Add types to /src/types/index.ts
  → No runtime impact — just type definitions

STEP 7 (LATER — NOT IN THIS PASS): Enforcement
  → Only after 1–2 weeks of manual observation
  → Add listing creation hook
  → Add automated flag insertion sweep
```

---

## SECTION 5 — Exact Files to Produce

Claude Code should create or update exactly these files and nothing else:

| # | Action | File Path | Description |
|---|--------|-----------|-------------|
| 1 | **OVERWRITE** | `/supabase/migrations/012_seller_risk.sql` | Hardened, idempotent migration (replaces existing draft) |
| 2 | **CREATE** | `/PHASE_B_DETECTION_QUERIES.sql` | 10 read-only SELECT detection queries + threshold reference |
| 3 | **APPEND** | `/DAY5_ADMIN_SQL_PACK.sql` | Phase B dashboard queries Q1–Q8 appended after existing content |
| 4 | **APPEND** | `/src/types/index.ts` | SellerFlag, SellerRiskScore, and union types added at end of file |

**Files NOT touched:**
- No files in `/app/` (no UI changes)
- No files in `/supabase/migrations/001–011` (existing migrations preserved)
- No edge functions created or modified
- No `/src/lib/`, `/src/hooks/`, `/src/components/` changes

---

## SECTION 6 — Exact Claude Code Implementation Prompt

Copy-paste this entire block to Claude Code:

---

```
You are implementing the safe V1 foundation of Phase B anti-fraud for SnatchIt.

CRITICAL RULES:
- All changes are ADDITIVE ONLY
- Do NOT modify any existing files except DAY5_ADMIN_SQL_PACK.sql (append only) and src/types/index.ts (append only)
- Do NOT add enforcement hooks, automated flag insertion, or any app-code changes
- Do NOT run the migration — it will be run manually in Supabase SQL Editor
- Do NOT modify any files in /app/, /src/lib/, /src/hooks/, /src/components/
- Do NOT touch migration files 001–011

═══════════════════════════════════════════════
FILE 1: OVERWRITE /supabase/migrations/012_seller_risk.sql
═══════════════════════════════════════════════

Write this exact SQL:

-- ============================================================
-- Migration 012: Phase B — Anti-Fraud & Seller Risk Controls
-- Safe V1: Tables + Functions + Indexes only
-- No enforcement hooks. No automatic flag insertion.
-- Idempotent: safe to re-run in Supabase SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- 1. seller_flags — individual risk flag events
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seller_flags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),

  seller_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  flag_type text NOT NULL CHECK (flag_type IN (
    'same_event_overload',
    'high_dispute_rate',
    'high_dispute_loss_rate',
    'duplicate_proof',
    'duplicate_evidence',
    'rapid_send',
    'new_account_high_value',
    'high_listing_velocity',
    'missing_payout_setup',
    'repeated_expiry'
  )),

  severity text NOT NULL DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),

  details text,

  listing_id uuid REFERENCES public.listings(id) ON DELETE SET NULL,
  transfer_id uuid REFERENCES public.transfers(id) ON DELETE SET NULL,

  reviewed_at timestamptz,
  reviewed_by uuid REFERENCES auth.users(id),
  resolution text CHECK (resolution IN (
    'dismissed',
    'warned',
    'listing_blocked',
    'seller_suspended',
    'escalated'
  )),
  resolution_notes text
);

-- Idempotent index creation
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_flags_seller_id') THEN
    CREATE INDEX idx_seller_flags_seller_id ON public.seller_flags(seller_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_flags_flag_type') THEN
    CREATE INDEX idx_seller_flags_flag_type ON public.seller_flags(flag_type);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_flags_severity') THEN
    CREATE INDEX idx_seller_flags_severity ON public.seller_flags(severity);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_flags_unreviewed') THEN
    CREATE INDEX idx_seller_flags_unreviewed ON public.seller_flags(created_at) WHERE reviewed_at IS NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_flags_created_at') THEN
    CREATE INDEX idx_seller_flags_created_at ON public.seller_flags(created_at DESC);
  END IF;
END $$;

ALTER TABLE public.seller_flags ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.seller_flags IS
  'Phase B V1: Individual risk flags raised against sellers. Admin-only visibility. No client RLS policies.';


-- ------------------------------------------------------------
-- 2. seller_risk_scores — materialized risk summary per seller
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.seller_risk_scores (
  seller_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  updated_at timestamptz NOT NULL DEFAULT now(),

  account_age_days int NOT NULL DEFAULT 0,
  total_listings int NOT NULL DEFAULT 0,
  active_listings int NOT NULL DEFAULT 0,
  total_completed int NOT NULL DEFAULT 0,
  total_disputes int NOT NULL DEFAULT 0,
  total_dispute_losses int NOT NULL DEFAULT 0,
  total_expired int NOT NULL DEFAULT 0,
  rapid_send_count int NOT NULL DEFAULT 0,
  duplicate_proof_count int NOT NULL DEFAULT 0,
  duplicate_evidence_count int NOT NULL DEFAULT 0,

  dispute_rate numeric(5,4) NOT NULL DEFAULT 0,
  dispute_loss_rate numeric(5,4) NOT NULL DEFAULT 0,
  expiry_rate numeric(5,4) NOT NULL DEFAULT 0,

  risk_tier text NOT NULL DEFAULT 'low' CHECK (risk_tier IN ('low', 'medium', 'high', 'critical')),

  open_flags_count int NOT NULL DEFAULT 0,
  critical_flags_count int NOT NULL DEFAULT 0,

  is_listing_blocked boolean NOT NULL DEFAULT false,
  listing_blocked_at timestamptz,
  listing_blocked_reason text
);

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_risk_scores_risk_tier') THEN
    CREATE INDEX idx_seller_risk_scores_risk_tier ON public.seller_risk_scores(risk_tier);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_seller_risk_scores_blocked') THEN
    CREATE INDEX idx_seller_risk_scores_blocked ON public.seller_risk_scores(seller_id) WHERE is_listing_blocked = true;
  END IF;
END $$;

ALTER TABLE public.seller_risk_scores ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.seller_risk_scores IS
  'Phase B V1: Materialized risk summary per seller. Recomputed on-demand via refresh functions. No client RLS policies.';


-- ------------------------------------------------------------
-- 3. refresh_seller_risk_score(p_seller_id)
-- Recomputes a single seller risk score from source tables.
-- SECURITY DEFINER because it reads auth.users for account age.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.refresh_seller_risk_score(uuid);

CREATE OR REPLACE FUNCTION public.refresh_seller_risk_score(p_seller_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_age int;
  v_total_listings int;
  v_active_listings int;
  v_total_completed int;
  v_total_disputes int;
  v_total_dispute_losses int;
  v_total_expired int;
  v_rapid_send int;
  v_dup_proof int;
  v_dup_evidence int;
  v_dispute_rate numeric(5,4);
  v_dispute_loss_rate numeric(5,4);
  v_expiry_rate numeric(5,4);
  v_risk_tier text;
  v_open_flags int;
  v_critical_flags int;
BEGIN
  -- Account age
  SELECT COALESCE(EXTRACT(DAY FROM now() - created_at)::int, 0)
    INTO v_account_age
    FROM auth.users WHERE id = p_seller_id;

  -- Listing counts
  SELECT COUNT(*) INTO v_total_listings
    FROM listings WHERE seller_id = p_seller_id;

  SELECT COUNT(*) INTO v_active_listings
    FROM listings WHERE seller_id = p_seller_id AND status = 'active';

  -- Transfer counts
  SELECT COUNT(*) INTO v_total_completed
    FROM transfers WHERE seller_id = p_seller_id
      AND status IN ('buyer_confirmed', 'auto_released');

  SELECT COUNT(*) INTO v_total_disputes
    FROM transfers WHERE seller_id = p_seller_id
      AND (status = 'disputed' OR dispute_resolved_at IS NOT NULL);

  SELECT COUNT(*) INTO v_total_dispute_losses
    FROM transfers WHERE seller_id = p_seller_id
      AND dispute_resolution = 'resolved_buyer_refunded';

  SELECT COUNT(*) INTO v_total_expired
    FROM transfers WHERE seller_id = p_seller_id
      AND status = 'expired';

  -- Rapid send (sent within 5 minutes of transfer creation)
  SELECT COUNT(*) INTO v_rapid_send
    FROM transfers WHERE seller_id = p_seller_id
      AND seller_sent_at IS NOT NULL
      AND seller_sent_at - created_at < interval '5 minutes';

  -- Duplicate proof of ownership (same path on multiple active listings)
  SELECT COALESCE(SUM(cnt - 1), 0)::int INTO v_dup_proof
    FROM (
      SELECT proof_of_ownership_path, COUNT(*) as cnt
      FROM listings
      WHERE seller_id = p_seller_id
        AND status = 'active'
        AND proof_of_ownership_path IS NOT NULL
      GROUP BY proof_of_ownership_path
      HAVING COUNT(*) > 1
    ) sub;

  -- Duplicate transfer evidence (same path on multiple transfers)
  SELECT COALESCE(SUM(cnt - 1), 0)::int INTO v_dup_evidence
    FROM (
      SELECT transfer_evidence_path, COUNT(*) as cnt
      FROM transfers
      WHERE seller_id = p_seller_id
        AND transfer_evidence_path IS NOT NULL
      GROUP BY transfer_evidence_path
      HAVING COUNT(*) > 1
    ) sub;

  -- Compute rates (with minimum sample sizes to avoid noisy ratios)
  IF v_total_completed >= 3 THEN
    v_dispute_rate := ROUND(v_total_disputes::numeric / v_total_completed, 4);
  ELSE
    v_dispute_rate := 0;
  END IF;

  IF v_total_disputes >= 2 THEN
    v_dispute_loss_rate := ROUND(v_total_dispute_losses::numeric / v_total_disputes, 4);
  ELSE
    v_dispute_loss_rate := 0;
  END IF;

  IF v_total_completed + v_total_expired >= 3 THEN
    v_expiry_rate := ROUND(v_total_expired::numeric / (v_total_completed + v_total_expired), 4);
  ELSE
    v_expiry_rate := 0;
  END IF;

  -- Flag counts
  SELECT COUNT(*) INTO v_open_flags
    FROM seller_flags WHERE seller_id = p_seller_id AND reviewed_at IS NULL;

  SELECT COUNT(*) INTO v_critical_flags
    FROM seller_flags WHERE seller_id = p_seller_id
      AND reviewed_at IS NULL AND severity = 'critical';

  -- Determine risk tier
  IF v_critical_flags > 0 OR v_dispute_rate > 0.30 OR v_dup_proof > 0 THEN
    v_risk_tier := 'critical';
  ELSIF v_open_flags >= 3 OR v_dispute_rate > 0.20 OR (v_account_age < 3 AND v_active_listings > 5) THEN
    v_risk_tier := 'high';
  ELSIF v_open_flags >= 1 OR v_dispute_rate > 0.10 OR v_rapid_send > 2 THEN
    v_risk_tier := 'medium';
  ELSE
    v_risk_tier := 'low';
  END IF;

  -- Upsert into seller_risk_scores
  INSERT INTO seller_risk_scores (
    seller_id, updated_at,
    account_age_days, total_listings, active_listings,
    total_completed, total_disputes, total_dispute_losses, total_expired,
    rapid_send_count, duplicate_proof_count, duplicate_evidence_count,
    dispute_rate, dispute_loss_rate, expiry_rate,
    risk_tier, open_flags_count, critical_flags_count
  ) VALUES (
    p_seller_id, now(),
    v_account_age, v_total_listings, v_active_listings,
    v_total_completed, v_total_disputes, v_total_dispute_losses, v_total_expired,
    v_rapid_send, v_dup_proof, v_dup_evidence,
    v_dispute_rate, v_dispute_loss_rate, v_expiry_rate,
    v_risk_tier, v_open_flags, v_critical_flags
  )
  ON CONFLICT (seller_id) DO UPDATE SET
    updated_at = now(),
    account_age_days = EXCLUDED.account_age_days,
    total_listings = EXCLUDED.total_listings,
    active_listings = EXCLUDED.active_listings,
    total_completed = EXCLUDED.total_completed,
    total_disputes = EXCLUDED.total_disputes,
    total_dispute_losses = EXCLUDED.total_dispute_losses,
    total_expired = EXCLUDED.total_expired,
    rapid_send_count = EXCLUDED.rapid_send_count,
    duplicate_proof_count = EXCLUDED.duplicate_proof_count,
    duplicate_evidence_count = EXCLUDED.duplicate_evidence_count,
    dispute_rate = EXCLUDED.dispute_rate,
    dispute_loss_rate = EXCLUDED.dispute_loss_rate,
    expiry_rate = EXCLUDED.expiry_rate,
    risk_tier = EXCLUDED.risk_tier,
    open_flags_count = EXCLUDED.open_flags_count,
    critical_flags_count = EXCLUDED.critical_flags_count;
END;
$$;

COMMENT ON FUNCTION public.refresh_seller_risk_score IS
  'Phase B V1: Recompute risk score for a single seller from source tables. Called manually by admin.';


-- ------------------------------------------------------------
-- 4. refresh_all_seller_risk_scores()
-- Batch refresh for all sellers who have listings or transfers.
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.refresh_all_seller_risk_scores();

CREATE OR REPLACE FUNCTION public.refresh_all_seller_risk_scores()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller_id uuid;
  v_count int := 0;
BEGIN
  FOR v_seller_id IN
    SELECT DISTINCT seller_id FROM listings
    UNION
    SELECT DISTINCT seller_id FROM transfers WHERE seller_id IS NOT NULL
  LOOP
    PERFORM refresh_seller_risk_score(v_seller_id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.refresh_all_seller_risk_scores IS
  'Phase B V1: Batch recompute risk scores for all sellers. Returns count of sellers processed.';


-- ------------------------------------------------------------
-- 5. Post-migration verification (run these after migration)
-- ------------------------------------------------------------
-- SELECT COUNT(*) FROM seller_flags;                    -- expect 0
-- SELECT COUNT(*) FROM seller_risk_scores;              -- expect 0
-- SELECT refresh_all_seller_risk_scores();              -- expect integer >= 0
-- SELECT * FROM seller_risk_scores ORDER BY risk_tier;  -- inspect results


═══════════════════════════════════════════════
FILE 2: CREATE /PHASE_B_DETECTION_QUERIES.sql
═══════════════════════════════════════════════

Write this exact SQL. IMPORTANT: These are ALL read-only SELECT queries. No INSERT, UPDATE, or DELETE statements.

-- ============================================================
-- Phase B V1 — Detection Queries (READ-ONLY)
-- Usage: Run manually in Supabase SQL Editor to detect risk signals.
-- These queries SELECT only. They do NOT create flags automatically.
-- Admin reviews output and manually creates flags as needed.
-- ============================================================


-- ============================================================
-- THRESHOLD REFERENCE
-- ============================================================
-- Rule 1: same_event_overload     — same event+date listings > 3 (warning), > 6 (critical)
-- Rule 2: high_dispute_rate       — dispute rate > 20% (warning), > 40% (critical), min 3 completed
-- Rule 3: high_dispute_loss_rate  — loss rate > 50% (critical), min 2 disputes
-- Rule 4: duplicate_proof         — same proof path on 2+ active listings (critical)
-- Rule 5: duplicate_evidence      — same evidence path on 2+ transfers (critical)
-- Rule 6: rapid_send              — sent < 5min after creation, > 2 occurrences (warning)
-- Rule 7: new_account_high_value  — age < 7d + listing > $200 (warning)
-- Rule 8: high_listing_velocity   — > 5 listings in 24h (warning), > 10 (critical)
-- Rule 9: missing_payout_setup    — active listings, no Stripe Connect (info)
-- Rule 10: repeated_expiry        — > 2 expired transfers (warning), > 4 (critical)
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


═══════════════════════════════════════════════
FILE 3: APPEND to /DAY5_ADMIN_SQL_PACK.sql
═══════════════════════════════════════════════

Append the following content AFTER the existing content in DAY5_ADMIN_SQL_PACK.sql. Do NOT modify any existing content.

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


═══════════════════════════════════════════════
FILE 4: APPEND to /src/types/index.ts
═══════════════════════════════════════════════

Append the following TypeScript types AFTER the existing content at the end of src/types/index.ts. Do NOT modify any existing types.

// ── Phase B: Anti-Fraud & Seller Risk types (migration 012) ────────────────

export type FlagType =
  | 'same_event_overload'
  | 'high_dispute_rate'
  | 'high_dispute_loss_rate'
  | 'duplicate_proof'
  | 'duplicate_evidence'
  | 'rapid_send'
  | 'new_account_high_value'
  | 'high_listing_velocity'
  | 'missing_payout_setup'
  | 'repeated_expiry';

export type FlagSeverity = 'info' | 'warning' | 'critical';

export type FlagResolution =
  | 'dismissed'
  | 'warned'
  | 'listing_blocked'
  | 'seller_suspended'
  | 'escalated';

export type RiskTier = 'low' | 'medium' | 'high' | 'critical';

export type SellerFlag = {
  id:               string;
  created_at:       string;
  seller_id:        string;
  flag_type:        FlagType;
  severity:         FlagSeverity;
  details:          string | null;
  listing_id:       string | null;
  transfer_id:      string | null;
  reviewed_at:      string | null;
  reviewed_by:      string | null;
  resolution:       FlagResolution | null;
  resolution_notes: string | null;
};

export type SellerRiskScore = {
  seller_id:              string;
  updated_at:             string;
  account_age_days:       number;
  total_listings:         number;
  active_listings:        number;
  total_completed:        number;
  total_disputes:         number;
  total_dispute_losses:   number;
  total_expired:          number;
  rapid_send_count:       number;
  duplicate_proof_count:  number;
  duplicate_evidence_count: number;
  dispute_rate:           number;
  dispute_loss_rate:      number;
  expiry_rate:            number;
  risk_tier:              RiskTier;
  open_flags_count:       number;
  critical_flags_count:   number;
  is_listing_blocked:     boolean;
  listing_blocked_at:     string | null;
  listing_blocked_reason: string | null;
};


═══════════════════════════════════════════════
VERIFICATION STEPS (do not skip)
═══════════════════════════════════════════════

After creating all 4 files:

1. Read back /supabase/migrations/012_seller_risk.sql and confirm:
   - CREATE TABLE IF NOT EXISTS for both tables
   - DO $$ blocks for all CREATE INDEX
   - DROP FUNCTION IF EXISTS before both CREATE OR REPLACE FUNCTION
   - No INSERT, UPDATE, or DELETE statements (except inside functions)
   - RLS enabled on both tables
   - No enforcement hooks

2. Read back /PHASE_B_DETECTION_QUERIES.sql and confirm:
   - All 10 rules present as SELECT-only queries
   - Zero INSERT/UPDATE/DELETE statements
   - Manual flag insert template is commented out

3. Read the tail of /DAY5_ADMIN_SQL_PACK.sql and confirm:
   - Phase B section appended after existing content
   - Existing queries not modified
   - PB-8 (resolve flag) is commented out as a template

4. Read the tail of /src/types/index.ts and confirm:
   - FlagType, FlagSeverity, FlagResolution, RiskTier union types present
   - SellerFlag and SellerRiskScore types present
   - All fields match the migration schema
   - No existing types modified

5. Do NOT run the migration. Report success.
```

---

STEP COMPLETE — WAITING FOR NEXT RUN
