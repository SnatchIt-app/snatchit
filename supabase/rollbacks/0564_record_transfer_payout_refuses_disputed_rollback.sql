-- Rollback 056d — remove the dispute predicate from record_transfer_payout.
--
-- Restores the pre-056d body, where the writer guarded only on "not already
-- paid" and would happily record a payout against a transfer with an open
-- dispute. Protection then rests entirely on the four caller-side checks in
-- confirm-and-release and enforce-transfer-expiry.
--
-- Apply only if the predicate is blocking a payout that ops has decided should
-- go through. The better fix in that case is to resolve the dispute
-- 'resolved_seller_paid', which this predicate already allows.

CREATE OR REPLACE FUNCTION public.record_transfer_payout(p_transfer_id uuid, p_stripe_transfer_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RETURN false;
  END IF;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);

  UPDATE public.transfers
     SET payout_released_at = now(),
         stripe_transfer_id = p_stripe_transfer_id
   WHERE id = p_transfer_id
     AND stripe_transfer_id IS NULL
     AND payout_released_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;
END; $function$;
