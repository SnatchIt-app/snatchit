-- ============================================================
-- Migration 012: Phase B V1 — Anti-Fraud & Seller Risk Controls
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

  -- dispute_loss_rate: losses / completed (not losses / disputes)
  -- This measures what % of completed sales ended in a buyer-win refund.
  -- Used for tiering. Raw dispute_rate is still stored for observability.
  IF v_total_completed >= 3 THEN
    v_dispute_loss_rate := ROUND(v_total_dispute_losses::numeric / v_total_completed, 4);
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
  -- RULES (Phase C corrections applied):
  --   1. high_dispute_rate NEVER drives critical — only dispute_loss_rate does
  --   2. rapid_send removed from tier determination (informational only)
  --   3. same_event_overload critical only for accounts < 7 days (handled via flag severity, not here)
  --   4. Trust stabilization: account > 30 days + zero losses → cap at medium
  --      (exception: dup_proof or dup_evidence bypass the cap)
  IF v_dup_proof > 0 OR v_dup_evidence > 0 OR v_dispute_loss_rate > 0.20 THEN
    v_risk_tier := 'critical';
  ELSIF v_critical_flags > 0 OR v_open_flags >= 3 OR (v_account_age < 3 AND v_active_listings > 5) OR v_dispute_loss_rate > 0.10 THEN
    v_risk_tier := 'high';
  ELSIF v_open_flags >= 1 OR v_expiry_rate > 0.30 OR v_dispute_loss_rate > 0.05 THEN
    v_risk_tier := 'medium';
  ELSE
    v_risk_tier := 'low';
  END IF;

  -- Trust stabilization: established clean sellers cap at medium
  IF v_account_age > 30 AND v_dispute_loss_rate = 0
     AND v_dup_proof = 0 AND v_dup_evidence = 0
     AND v_risk_tier IN ('high', 'critical') THEN
    v_risk_tier := 'medium';
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
