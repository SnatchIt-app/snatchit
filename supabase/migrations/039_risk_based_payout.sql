-- ============================================================================
-- 039_risk_based_payout.sql — replace the blanket 72h auto-release with a
-- risk-based payout decision pipeline.
--
-- BEFORE: enforce_auto_release() (016) flipped EVERY seller_sent transfer past
-- auto_release_at to auto_released; the cron edge function then paid the
-- seller. Buyer silence alone released every transaction identically.
--
-- AFTER:
--   • get_auto_release_candidates() returns due transfers JOINED with all
--     risk signals (seller_risk_scores refreshed inline, payments, listings,
--     profiles) — read-only, no state change.
--   • The edge function classifies each candidate with the deterministic
--     policy in _shared/payout-policy.ts and applies exactly one of:
--       apply_auto_release()  — LOW risk → status 'auto_released' (then paid)
--       apply_payout_hold()   — MEDIUM   → held to a post-event safe point
--       apply_manual_review() — HIGH     → frozen for an operator
--   • Every decision (including buyer-confirmed releases) is recorded in
--     payout_decisions for audit.
--   • admin_release_held_payout() lets an operator (service role) release a
--     held/manual transfer; money still only moves in the edge function.
--
-- Buyer positive confirmation (confirm-and-release) and the 24h unsent-
-- transfer refund (Phase 1) are unchanged. Disputed transfers were and
-- remain excluded from every auto path (status filter + release guards).
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- 1. transfers: risk/hold/visibility columns
-- ────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.transfers
  ADD COLUMN IF NOT EXISTS buyer_viewed_at      timestamptz,
  ADD COLUMN IF NOT EXISTS payout_hold_until    timestamptz,
  ADD COLUMN IF NOT EXISTS payout_risk_tier     text
    CHECK (payout_risk_tier IN ('low','medium','high')),
  ADD COLUMN IF NOT EXISTS payout_reason_codes  text[],
  ADD COLUMN IF NOT EXISTS payout_review_status text
    CHECK (payout_review_status IN ('held','manual_review'));

COMMENT ON COLUMN public.transfers.buyer_viewed_at IS
  'First time the buyer opened the transfer/receive screen (set via mark_transfer_viewed RPC). Risk signal only.';
COMMENT ON COLUMN public.transfers.payout_hold_until IS
  'MEDIUM-risk hold: auto-release re-evaluates only after this time.';
COMMENT ON COLUMN public.transfers.payout_review_status IS
  'held = medium-risk time hold; manual_review = frozen until an operator acts.';

CREATE INDEX IF NOT EXISTS idx_transfers_payout_review
  ON public.transfers (payout_review_status)
  WHERE payout_review_status IS NOT NULL;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. payout_policy — single-row, ops-tunable thresholds (documented defaults)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payout_policy (
  id                        int  PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  -- $200+ orders never auto-release on buyer silence.
  high_value_cents          int  NOT NULL DEFAULT 20000 CHECK (high_value_cents > 0),
  -- A seller needs 3 completed sales AND a 14-day-old account for LOW risk.
  low_min_completed_sales   int  NOT NULL DEFAULT 3  CHECK (low_min_completed_sales >= 0),
  low_min_account_age_days  int  NOT NULL DEFAULT 14 CHECK (low_min_account_age_days >= 0),
  -- MEDIUM holds release 24h after the event date (buyer had the event to complain).
  post_event_grace_hours    int  NOT NULL DEFAULT 24 CHECK (post_event_grace_hours >= 0),
  -- MEDIUM holds never exceed 7 days past auto_release_at; then manual review.
  medium_max_hold_days      int  NOT NULL DEFAULT 7  CHECK (medium_max_hold_days >= 1),
  updated_at                timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.payout_policy (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.payout_policy ENABLE ROW LEVEL SECURITY;
-- No client policies: service-role only.

-- ────────────────────────────────────────────────────────────────────────────
-- 3. payout_decisions — audit trail for every payout decision
--    (no ticket credentials or PII beyond the IDs already on transfers)
-- ────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payout_decisions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id      uuid NOT NULL REFERENCES public.transfers(id) ON DELETE CASCADE,
  payment_id       uuid REFERENCES public.payments(id) ON DELETE SET NULL,
  seller_id        uuid,
  buyer_id         uuid,
  risk_tier        text NOT NULL CHECK (risk_tier IN ('low','medium','high')),
  decision         text NOT NULL CHECK (decision IN ('release','hold','manual_review','refund')),
  reason_codes     text[] NOT NULL DEFAULT '{}',
  -- Snapshot of the non-sensitive inputs the decision was made from.
  evidence         jsonb  NOT NULL DEFAULT '{}'::jsonb,
  buyer_confirmed  boolean NOT NULL DEFAULT false,
  dispute_open     boolean NOT NULL DEFAULT false,
  event_date       date,
  hold_until       timestamptz,
  actor            text NOT NULL,        -- 'edge:confirm-and-release' | 'cron:enforce-transfer-expiry' | 'admin:<uuid>'
  decided_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payout_decisions_transfer
  ON public.payout_decisions (transfer_id, decided_at DESC);

ALTER TABLE public.payout_decisions ENABLE ROW LEVEL SECURITY;
-- No client policies: service-role only.

-- ────────────────────────────────────────────────────────────────────────────
-- 4. mark_transfer_viewed — buyer opened the transfer screen (risk signal)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_transfer_viewed(p_transfer_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.transfers
     SET buyer_viewed_at = COALESCE(buyer_viewed_at, now())
   WHERE id = p_transfer_id
     AND buyer_id = auth.uid();
END; $$;

REVOKE ALL ON FUNCTION public.mark_transfer_viewed(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_transfer_viewed(uuid) TO authenticated;

-- ────────────────────────────────────────────────────────────────────────────
-- 5. get_auto_release_candidates — due, undisputed, unheld transfers + signals
--    Read-only. Refreshes each candidate's seller risk score first so the
--    classifier always sees current numbers.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_auto_release_candidates()
RETURNS TABLE (
  transfer_id  uuid,
  payment_id   uuid,
  listing_id   uuid,
  seller_id    uuid,
  buyer_id     uuid,
  base_cents   int,
  has_evidence boolean,
  buyer_viewed boolean,
  ticket_platform text,
  event_date   date,
  proof_status text,
  auto_release_at timestamptz,
  payout_hold_until timestamptz,
  risk_tier    text,
  account_age_days int,
  total_completed int,
  total_disputes int,
  total_dispute_losses int,
  is_listing_blocked boolean,
  stripe_onboarding_complete boolean
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_seller uuid;
BEGIN
  -- Refresh risk scores for the sellers we are about to judge.
  FOR v_seller IN
    SELECT DISTINCT t.seller_id FROM public.transfers t
     WHERE t.status = 'seller_sent'
       AND t.auto_release_at IS NOT NULL
       AND t.auto_release_at < now()
       AND t.payout_released_at IS NULL
       AND (t.payout_hold_until IS NULL OR t.payout_hold_until < now())
       AND (t.payout_review_status IS DISTINCT FROM 'manual_review')
  LOOP
    BEGIN
      PERFORM public.refresh_seller_risk_score(v_seller);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'get_auto_release_candidates: risk refresh failed for %: %', v_seller, SQLERRM;
    END;
  END LOOP;

  RETURN QUERY
  SELECT
    t.id, t.payment_id, t.listing_id, t.seller_id, t.buyer_id,
    p.amount,
    (t.transfer_evidence_path IS NOT NULL),
    (t.buyer_viewed_at IS NOT NULL),
    l.ticket_platform,
    l.event_date,
    l.proof_status,
    t.auto_release_at,
    t.payout_hold_until,
    srs.risk_tier,
    srs.account_age_days,
    srs.total_completed,
    srs.total_disputes,
    srs.total_dispute_losses,
    srs.is_listing_blocked,
    COALESCE(pr.stripe_onboarding_complete, false)
  FROM public.transfers t
  JOIN public.payments  p  ON p.id = t.payment_id
  JOIN public.listings  l  ON l.id = t.listing_id
  LEFT JOIN public.seller_risk_scores srs ON srs.seller_id = t.seller_id
  LEFT JOIN public.profiles pr ON pr.id = t.seller_id
  WHERE t.status = 'seller_sent'
    AND t.auto_release_at IS NOT NULL
    AND t.auto_release_at < now()
    AND t.payout_released_at IS NULL
    AND (t.payout_hold_until IS NULL OR t.payout_hold_until < now())
    AND (t.payout_review_status IS DISTINCT FROM 'manual_review');
END; $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 6. apply_* — guarded state transitions (one per decision outcome)
-- ────────────────────────────────────────────────────────────────────────────

-- LOW risk (or elapsed MEDIUM hold): claim for payout. Returns true only for
-- the caller that performed the flip — the money-moving edge code runs only
-- on a true return, so concurrent runs cannot double-claim.
CREATE OR REPLACE FUNCTION public.apply_auto_release(p_transfer_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_claimed int;
BEGIN
  WITH claimable AS (
    SELECT t.id FROM public.transfers t
     WHERE t.id = p_transfer_id
       AND t.status = 'seller_sent'                                  -- excludes disputed
       AND t.payout_released_at IS NULL
       AND (t.payout_review_status IS DISTINCT FROM 'manual_review')
       FOR UPDATE SKIP LOCKED
  )
  UPDATE public.transfers t
     SET status = 'auto_released',
         payout_review_status = NULL,
         payout_hold_until = NULL
    FROM claimable c
   WHERE t.id = c.id;
  GET DIAGNOSTICS v_claimed = ROW_COUNT;
  RETURN v_claimed = 1;
END; $$;

-- MEDIUM risk: park until an event-relative safe point. Idempotent.
CREATE OR REPLACE FUNCTION public.apply_payout_hold(
  p_transfer_id uuid,
  p_hold_until  timestamptz,
  p_tier        text,
  p_reasons     text[]
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_updated int;
BEGIN
  UPDATE public.transfers
     SET payout_hold_until    = p_hold_until,
         payout_review_status = 'held',
         payout_risk_tier     = p_tier,
         payout_reason_codes  = p_reasons
   WHERE id = p_transfer_id
     AND status = 'seller_sent'
     AND payout_released_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END; $$;

-- HIGH risk: freeze for an operator. Idempotent; nothing auto-releases it.
CREATE OR REPLACE FUNCTION public.apply_manual_review(
  p_transfer_id uuid,
  p_tier        text,
  p_reasons     text[]
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_updated int;
BEGIN
  UPDATE public.transfers
     SET payout_review_status = 'manual_review',
         payout_hold_until    = NULL,
         payout_risk_tier     = p_tier,
         payout_reason_codes  = p_reasons
   WHERE id = p_transfer_id
     AND status = 'seller_sent'
     AND payout_released_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END; $$;

-- Operator release of a held/manual transfer (service role only — the admin
-- app runs server-side). Flips to auto_released; the next cron run pays via
-- the stuck-payout sweep. Records the decision itself.
CREATE OR REPLACE FUNCTION public.admin_release_held_payout(
  p_transfer_id uuid,
  p_admin_id    uuid,
  p_note        text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_updated int;
  v_row public.transfers%ROWTYPE;
BEGIN
  SELECT * INTO v_row FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RETURN false; END IF;

  IF v_row.status <> 'seller_sent' OR v_row.payout_released_at IS NOT NULL THEN
    RETURN false;  -- disputed, already paid, or otherwise not releasable
  END IF;

  UPDATE public.transfers
     SET status = 'auto_released',
         payout_review_status = NULL,
         payout_hold_until = NULL
   WHERE id = p_transfer_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  INSERT INTO public.payout_decisions
    (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision,
     reason_codes, evidence, actor)
  VALUES
    (p_transfer_id, v_row.payment_id, v_row.seller_id, v_row.buyer_id,
     COALESCE(v_row.payout_risk_tier, 'high'), 'release',
     ARRAY['ADMIN_MANUAL_RELEASE'],
     jsonb_build_object('note', p_note),
     'admin:' || p_admin_id::text);

  RETURN v_updated = 1;
END; $$;

-- ────────────────────────────────────────────────────────────────────────────
-- 7. Lock down: server-only execution for everything except mark_transfer_viewed
-- ────────────────────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.get_auto_release_candidates()                    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_auto_release(uuid)                         FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_payout_hold(uuid, timestamptz, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_manual_review(uuid, text, text[])          FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_release_held_payout(uuid, uuid, text)      FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_auto_release_candidates()                    TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_auto_release(uuid)                         TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_payout_hold(uuid, timestamptz, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_manual_review(uuid, text, text[])          TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_release_held_payout(uuid, uuid, text)      TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 8. Retire the blanket release. Kept as a stub that releases NOTHING so any
--    stale caller (old edge deploy mid-rollout) gets an empty set instead of
--    a blanket payout.
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_auto_release()
RETURNS TABLE (transfer_id uuid, payment_id uuid, listing_id uuid, buyer_id uuid, seller_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Deprecated by 039_risk_based_payout: blanket 72h release removed.
  -- Auto-release decisions now flow through get_auto_release_candidates()
  -- + the risk classifier in the enforce-transfer-expiry edge function.
  RETURN;
END; $$;

REVOKE ALL ON FUNCTION public.enforce_auto_release() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enforce_auto_release() TO service_role;

-- ────────────────────────────────────────────────────────────────────────────
-- 9. Admin visibility — payout review queue (service-role only via RLS-less
--    SECURITY DEFINER function; the admin app calls it with the service key)
-- ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_payout_review_queue()
RETURNS TABLE (
  transfer_id uuid,
  listing_id uuid,
  seller_id uuid,
  buyer_id uuid,
  event_name text,
  event_date date,
  base_cents int,
  seller_net_cents int,
  payout_status text,        -- 'held' | 'manual_review'
  risk_tier text,
  reason_codes text[],
  hold_until timestamptz,
  seller_sent_at timestamptz,
  auto_release_at timestamptz,
  next_action text
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT
    t.id, t.listing_id, t.seller_id, t.buyer_id,
    l.event_name, l.event_date,
    p.amount,
    p.amount - p.seller_fee,
    t.payout_review_status,
    t.payout_risk_tier,
    t.payout_reason_codes,
    t.payout_hold_until,
    t.seller_sent_at,
    t.auto_release_at,
    CASE t.payout_review_status
      WHEN 'manual_review' THEN 'Operator must review evidence and release, refund, or wait for the buyer.'
      WHEN 'held'          THEN 'Auto-releases after hold_until unless the buyer disputes first.'
    END
  FROM public.transfers t
  JOIN public.payments p ON p.id = t.payment_id
  JOIN public.listings l ON l.id = t.listing_id
  WHERE t.payout_review_status IS NOT NULL
    AND t.payout_released_at IS NULL
    AND t.status = 'seller_sent'
  ORDER BY t.auto_release_at ASC;
$$;

REVOKE ALL ON FUNCTION public.get_payout_review_queue() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_payout_review_queue() TO service_role;
