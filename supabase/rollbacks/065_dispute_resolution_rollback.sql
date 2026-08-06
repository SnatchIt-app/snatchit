-- Rollback 065 — remove the dispute resolution path.
--
-- Returns disputes to being an absorbing state: nothing will clear disputed_at,
-- so no disputed transfer can ever be paid out again, including ones won at
-- Stripe. Only do this if 065 is implicated in a regression.
--
-- dispute_resolutions is NOT dropped. It is the audit history of decisions that
-- were actually made, some of which may have unfrozen a payout that has since
-- been paid. Dropping it would destroy the only record of who decided what.
-- The append-only trigger stays with it.
--
-- Transfers already resolved seller_win are NOT rewound: their disputed_at is
-- already NULL and status already buyer_confirmed, and re-freezing them could
-- strand a payout mid-flight. Re-freeze individually if genuinely required.

DROP FUNCTION IF EXISTS public.resolve_transfer_dispute(uuid, text, uuid, text, text);
DROP FUNCTION IF EXISTS public.get_disputes_awaiting_refund();

-- Restore the pre-065 admin_resolve_dispute: records the decision only, leaves
-- status='disputed' and disputed_at set, writes no audit row.
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
  IF p_resolution NOT IN ('resolved_seller_paid','resolved_buyer_refunded','resolved_partial_refund') THEN
    RAISE EXCEPTION 'Invalid resolution type: %', p_resolution;
  END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET dispute_resolution=p_resolution, dispute_resolved_at=now(), dispute_resolved_by=p_admin_id
   WHERE id=p_transfer_id AND status='disputed' AND dispute_resolved_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not in disputed state, or already resolved.';
  END IF;
END; $function$;

-- Drop the three dispute_* columns back out of the state guard (065 added them).
-- Body is otherwise the 056b/056c version.
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
