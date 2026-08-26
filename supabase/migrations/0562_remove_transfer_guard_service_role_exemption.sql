-- 056b — remove the temporary service_role exemption from the transfer state guard.
--
-- 055 shipped guard_transfer_state_columns() with a deliberate escape hatch:
--
--     IF current_user = 'service_role' THEN RETURN NEW; END IF;
--
-- At that point four Edge Function code paths still wrote transfers.status,
-- payout_released_at and stripe_transfer_id directly through PostgREST as
-- service_role, and a PostgREST request cannot set a transaction-local GUC.
-- Without the exemption those writes would have failed and real payouts would
-- have stopped being recorded, so the hole stayed open on purpose.
--
-- The exemption is also far wider than it looks. service_role is the key used
-- by every server-side integration; anything holding it could rewrite
-- seller_id, buyer_id, payout_released_at or status at will and redirect a
-- payout. It only ever earned its place as a deploy-ordering concession.
--
-- All four writers now route through the SECURITY DEFINER RPCs added in 056a,
-- each of which sets app.bypass_transfer_guard itself:
--
--   confirm-and-release      v33 -> record_transfer_payout
--   enforce-transfer-expiry  v36 -> record_transfer_payout
--   stripe-webhook           v38 -> freeze_transfer_for_dispute
--   stripe-webhook           v38 -> mark_transfer_reversed
--
-- Verified before applying:
--   * zero remaining `.from('transfers').update(...)` in supabase/functions/
--     (the three surviving writes are INSERTs, and the trigger is BEFORE
--     UPDATE only, so they are untouched by this guard either way)
--   * the web app holds no service_role client and only SELECTs transfers
--   * transfer d6f3e170 recorded a real live-mode payout
--     (tr_3U1EKkGdOzCmGbHw1FMKi6b0) through record_transfer_payout, proving
--     the RPC path carries production traffic end to end
--
-- Body is otherwise byte-identical to 055. Only the exemption block is gone.

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

COMMENT ON FUNCTION public.guard_transfer_state_columns() IS
  'Transfer state columns are RPC-only. The sole bypass is the transaction-local '
  'GUC app.bypass_transfer_guard, which only SECURITY DEFINER RPCs set. There is '
  'no role-based exemption: service_role is deliberately NOT trusted here (056b).';
