-- 065 — a trusted, auditable way to resolve a transfer dispute.
--
-- THE BUG: a dispute is currently an absorbing state.
--
-- Nothing anywhere clears disputed_at. admin_resolve_dispute() exists but is
-- called by nothing, and it only records the decision — it writes
-- dispute_resolution / _at / _by and leaves status = 'disputed' and
-- disputed_at set. Every payout gate then stays shut:
--
--   payout-logic.ts:80                 disputedAt !== null      (dead code —
--                                      imported only by its own test)
--   confirm-and-release/index.ts:279   status or disputed_at
--   confirm-and-release/index.ts:440   recheck before the Stripe call
--   enforce-transfer-expiry:553        cron payout pre-flight
--   enforce-transfer-expiry:797        Phase 2b sweep filter
--   record_transfer_payout             056d predicate
--
-- charge.dispute.closed never touches transfers in any branch, so even a
-- dispute WON at Stripe leaves the seller permanently unpayable, despite the
-- comment at :598 claiming the payout path resumes.
--
-- Production today: 5 disputed transfers, aged 61-125 days, every one with a
-- succeeded payment and no payout. None carries a dispute_reason, because no
-- caller passes one — mobile and web both invoke buyer_dispute_transfer with
-- the id alone.
--
-- SEMANTIC CHANGE, stated plainly: disputed_at now means "has an OPEN
-- dispute", not "was ever disputed". A seller-win clears it, which is what
-- reopens the payout path without needing an Edge Function redeploy. The
-- historical fact is not lost — it moves to dispute_resolutions below, and
-- dispute_resolved_at / _by stay on the row.
--
-- Money is deliberately NOT moved here. A buyer-win records the decision and
-- leaves the payout frozen; issuing the actual refund stays a separate,
-- explicitly authorised action. This function only ever changes state.

-- ── Immutable audit history ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dispute_resolutions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  transfer_id     uuid NOT NULL REFERENCES public.transfers(id),
  outcome         text NOT NULL CHECK (outcome IN ('seller_win','buyer_win','partial_refund')),
  resolution      text NOT NULL CHECK (resolution IN ('resolved_seller_paid','resolved_buyer_refunded','resolved_partial_refund')),
  refund_required boolean NOT NULL,
  actor_id        uuid NOT NULL REFERENCES auth.users(id),
  reason          text,
  notes           text,
  previous_status text NOT NULL,
  new_status      text NOT NULL,
  payout_unfrozen boolean NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS dispute_resolutions_transfer_idx
  ON public.dispute_resolutions (transfer_id, created_at DESC);

ALTER TABLE public.dispute_resolutions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.dispute_resolutions FROM PUBLIC, anon, authenticated;

-- Append-only. RLS with zero policies already blocks the client roles, but the
-- point of an audit log is that nothing rewrites it, including service_role
-- and a future careless migration.
CREATE OR REPLACE FUNCTION public.dispute_resolutions_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  RAISE EXCEPTION 'dispute_resolutions is append-only (065).';
END; $function$;

DROP TRIGGER IF EXISTS trg_dispute_resolutions_append_only ON public.dispute_resolutions;
CREATE TRIGGER trg_dispute_resolutions_append_only
  BEFORE UPDATE OR DELETE ON public.dispute_resolutions
  FOR EACH ROW EXECUTE FUNCTION public.dispute_resolutions_append_only();


-- ── The resolution path ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.resolve_transfer_dispute(
  p_transfer_id uuid,
  p_outcome     text,
  p_actor_id    uuid,
  p_reason      text DEFAULT NULL,
  p_notes       text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_prev_status text;
  v_new_status  text;
  v_resolution  text;
  v_unfreeze    boolean;
  v_refund      boolean;
  v_paid        timestamptz;
BEGIN
  IF p_outcome NOT IN ('seller_win','buyer_win','partial_refund') THEN
    RAISE EXCEPTION 'Invalid outcome: %. Expected seller_win, buyer_win or partial_refund.', p_outcome;
  END IF;

  -- An actor is mandatory and must be a real admin. This is the "explicit
  -- trusted decision" gate: EXECUTE is service_role-only, so a client cannot
  -- reach this at all, and even a server caller must name a known admin.
  IF p_actor_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = p_actor_id) THEN
    RAISE EXCEPTION 'Resolution requires a known admin actor.';
  END IF;

  SELECT status, payout_released_at INTO v_prev_status, v_paid
    FROM public.transfers
   WHERE id = p_transfer_id
     AND disputed_at IS NOT NULL
     AND dispute_resolved_at IS NULL
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, has no open dispute, or is already resolved.';
  END IF;

  IF p_outcome = 'seller_win' THEN
    v_resolution := 'resolved_seller_paid';
    v_refund     := false;
    -- Clearing disputed_at is what actually reopens the payout path: it
    -- satisfies the 056d predicate in record_transfer_payout AND the
    -- disputed_at checks in confirm-and-release and enforce-transfer-expiry,
    -- so the existing cron resumes without an Edge Function change.
    -- buyer_confirmed is the payable state both payout callers expect; if the
    -- payout already went out we leave the status alone rather than rewinding.
    v_unfreeze   := (v_paid IS NULL);
    v_new_status := CASE WHEN v_paid IS NULL THEN 'buyer_confirmed' ELSE v_prev_status END;
  ELSE
    -- Buyer win / partial: the seller does not get paid. disputed_at stays
    -- set, so every payout gate stays shut, and status stays 'disputed' —
    -- there is no 'resolved' value in transfers_status_check, and inventing
    -- one would mean touching a constraint the whole state machine reads.
    -- dispute_resolved_at is what marks it handled.
    v_resolution := CASE WHEN p_outcome = 'buyer_win'
                         THEN 'resolved_buyer_refunded'
                         ELSE 'resolved_partial_refund' END;
    v_refund     := true;
    v_unfreeze   := false;
    v_new_status := v_prev_status;
  END IF;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET dispute_resolution  = v_resolution,
         dispute_resolved_at = now(),
         dispute_resolved_by = p_actor_id,
         dispute_notes       = coalesce(p_notes, dispute_notes),
         status              = v_new_status,
         disputed_at         = CASE WHEN v_unfreeze THEN NULL ELSE disputed_at END
   WHERE id = p_transfer_id;

  INSERT INTO public.dispute_resolutions
    (transfer_id, outcome, resolution, refund_required, actor_id, reason, notes,
     previous_status, new_status, payout_unfrozen)
  VALUES
    (p_transfer_id, p_outcome, v_resolution, v_refund, p_actor_id, p_reason, p_notes,
     v_prev_status, v_new_status, v_unfreeze);

  RETURN jsonb_build_object(
    'transfer_id',     p_transfer_id,
    'outcome',         p_outcome,
    'resolution',      v_resolution,
    'previous_status', v_prev_status,
    'new_status',      v_new_status,
    'payout_unfrozen', v_unfreeze,
    'refund_required', v_refund
  );
END; $function$;

-- admin_resolve_dispute predates this and writes the same columns without an
-- audit row or a status transition. Redirected rather than left alongside, so
-- there is exactly one way to resolve a dispute.
CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_transfer_id uuid,
  p_resolution  text,
  p_admin_id    uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public.resolve_transfer_dispute(
    p_transfer_id,
    CASE p_resolution
      WHEN 'resolved_seller_paid'    THEN 'seller_win'
      WHEN 'resolved_buyer_refunded' THEN 'buyer_win'
      WHEN 'resolved_partial_refund' THEN 'partial_refund'
      ELSE p_resolution  -- falls through to the outcome validation below
    END,
    p_admin_id,
    'via admin_resolve_dispute',
    NULL
  );
END; $function$;

-- Ops surface: decided for the buyer, refund not yet issued.
CREATE OR REPLACE FUNCTION public.get_disputes_awaiting_refund()
RETURNS TABLE (
  transfer_id  uuid,
  resolution   text,
  resolved_at  timestamptz,
  base_cents   integer,
  payment_status text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT t.id, t.dispute_resolution, t.dispute_resolved_at, p.amount, p.status
    FROM public.transfers t
    JOIN public.payments p ON p.id = t.payment_id
   WHERE t.dispute_resolved_at IS NOT NULL
     AND t.dispute_resolution IN ('resolved_buyer_refunded','resolved_partial_refund')
     AND p.status <> 'refunded'
   ORDER BY t.dispute_resolved_at;
$function$;

-- The state guard covers status and disputed_at but not the resolution
-- columns, which rest on table grants alone. Fold them in so a future grant
-- change cannot expose them to direct writes.
CREATE OR REPLACE FUNCTION public.guard_transfer_state_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF current_setting('app.bypass_transfer_guard', true) = 'on' THEN RETURN NEW; END IF;

  IF NEW.status               IS DISTINCT FROM OLD.status
  OR NEW.seller_id            IS DISTINCT FROM OLD.seller_id
  OR NEW.buyer_id             IS DISTINCT FROM OLD.buyer_id
  OR NEW.payment_id           IS DISTINCT FROM OLD.payment_id
  OR NEW.listing_id           IS DISTINCT FROM OLD.listing_id
  OR NEW.seller_sent_at       IS DISTINCT FROM OLD.seller_sent_at
  OR NEW.buyer_confirmed_at   IS DISTINCT FROM OLD.buyer_confirmed_at
  OR NEW.disputed_at          IS DISTINCT FROM OLD.disputed_at
  OR NEW.dispute_resolution   IS DISTINCT FROM OLD.dispute_resolution
  OR NEW.dispute_resolved_at  IS DISTINCT FROM OLD.dispute_resolved_at
  OR NEW.dispute_resolved_by  IS DISTINCT FROM OLD.dispute_resolved_by
  OR NEW.payout_released_at   IS DISTINCT FROM OLD.payout_released_at
  OR NEW.stripe_transfer_id   IS DISTINCT FROM OLD.stripe_transfer_id
  OR NEW.payout_hold_until    IS DISTINCT FROM OLD.payout_hold_until
  OR NEW.payout_review_status IS DISTINCT FROM OLD.payout_review_status
  OR NEW.payout_risk_tier     IS DISTINCT FROM OLD.payout_risk_tier
  OR NEW.payout_reason_codes  IS DISTINCT FROM OLD.payout_reason_codes
  OR NEW.auto_release_at      IS DISTINCT FROM OLD.auto_release_at
  OR NEW.expires_at           IS DISTINCT FROM OLD.expires_at
  OR NEW.expired_at           IS DISTINCT FROM OLD.expired_at
  THEN
    RAISE EXCEPTION 'Cannot directly modify transfer state columns. Use the appropriate RPC.';
  END IF;

  IF OLD.transfer_evidence_path IS NOT NULL
     AND NEW.transfer_evidence_path IS DISTINCT FROM OLD.transfer_evidence_path THEN
    RAISE EXCEPTION 'transfer_evidence_path is append-only.';
  END IF;
  IF OLD.dispute_evidence_path IS NOT NULL
     AND NEW.dispute_evidence_path IS DISTINCT FROM OLD.dispute_evidence_path THEN
    RAISE EXCEPTION 'dispute_evidence_path is append-only.';
  END IF;
  RETURN NEW;
END; $function$;

REVOKE ALL ON FUNCTION public.resolve_transfer_dispute(uuid, text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_disputes_awaiting_refund()                          FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_transfer_dispute(uuid, text, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_disputes_awaiting_refund()                         TO service_role;
