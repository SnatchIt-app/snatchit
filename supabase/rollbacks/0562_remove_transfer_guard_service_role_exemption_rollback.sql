-- Rollback 056b — restore the temporary service_role exemption in the transfer
-- state guard.
--
-- Apply this ONLY if removing the exemption breaks a live payout path, i.e. if
-- some service_role writer still updates transfers.status / payout_released_at
-- / stripe_transfer_id directly and now fails with:
--
--     'Cannot directly modify transfer state columns. Use the appropriate RPC.'
--
-- Restoring the exemption reopens a real hole: any holder of service_role can
-- rewrite seller_id / buyer_id / payout_released_at and redirect a payout. Use
-- it as a stopgap to keep payouts recording, then fix the offending writer to
-- call the 056a RPCs and re-apply 056b. Do not leave this in place.

CREATE OR REPLACE FUNCTION public.guard_transfer_state_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $function$
BEGIN
  IF current_setting('app.bypass_transfer_guard', true) = 'on' THEN RETURN NEW; END IF;
  -- TEMPORARY (removed in 056b): restored by rollback.
  IF current_user = 'service_role' THEN RETURN NEW; END IF;

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
