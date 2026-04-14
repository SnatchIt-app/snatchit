-- ============================================================
-- Migration 013: Phase D — Soft Enforcement Pre-Listing Check
-- Adds a single RPC: can_create_listing(p_seller_id uuid)
-- No schema changes. No triggers. No automation.
-- ============================================================


CREATE OR REPLACE FUNCTION public.can_create_listing(p_seller_id uuid)
RETURNS TABLE (
  allowed   boolean,
  reason    text,
  risk_tier text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_risk_tier         text;
  v_is_blocked        boolean;
BEGIN
  -- Caller must be the seller themselves
  IF auth.uid() IS DISTINCT FROM p_seller_id THEN
    RAISE EXCEPTION 'Unauthorized: caller does not match p_seller_id';
  END IF;

  -- Fetch current risk posture
  SELECT
    srs.risk_tier,
    srs.is_listing_blocked
  INTO
    v_risk_tier,
    v_is_blocked
  FROM seller_risk_scores srs
  WHERE srs.seller_id = p_seller_id;

  -- No row → new/clean seller → allow
  IF NOT FOUND THEN
    RETURN QUERY SELECT true, 'ok'::text, NULL::text;
    RETURN;
  END IF;

  -- Hard block: admin has toggled is_listing_blocked
  IF v_is_blocked THEN
    RETURN QUERY SELECT false, 'listing_blocked'::text, v_risk_tier;
    RETURN;
  END IF;

  -- Critical tier: block listing creation
  IF v_risk_tier = 'critical' THEN
    RETURN QUERY SELECT false, 'critical_risk'::text, v_risk_tier;
    RETURN;
  END IF;

  -- High tier: allow with warning
  IF v_risk_tier = 'high' THEN
    RETURN QUERY SELECT true, 'high_risk_warning'::text, v_risk_tier;
    RETURN;
  END IF;

  -- Medium tier: allow with light warning
  IF v_risk_tier = 'medium' THEN
    RETURN QUERY SELECT true, 'medium_risk_warning'::text, v_risk_tier;
    RETURN;
  END IF;

  -- Low tier: all clear
  RETURN QUERY SELECT true, 'ok'::text, v_risk_tier;
END;
$$;

COMMENT ON FUNCTION public.can_create_listing IS
  'Phase D: Pre-listing risk gate. Returns (allowed, reason, risk_tier). Called by frontend before submit. SECURITY DEFINER — auth.uid() must match p_seller_id.';
