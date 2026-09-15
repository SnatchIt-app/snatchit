-- ============================================================================
-- 127_release_reservation_guards_rollback.sql — restores the pre-127 state:
-- `public.release_reservation` returns to its APPLIED (0590) body (sold +
-- hold-ownership checks only, no succeeded-payment guard, no comment), and
-- `public.release_reservation_for_payment` is dropped.
--
-- WHAT THIS RE-INTRODUCES, deliberately and on the record: L2 (a live release
-- can free a PAID order's hold between the payment succeeding and the listing
-- reading `sold`) and L1 (a stale cancellation can free a hold taken after the
-- payment it claims to belong to). Production is forward-only by policy; this
-- is an emergency measure needing its own authorization.
--
-- The pre-127 state is 0590's body, NOT 000_baseline's: 0590 removed the last
-- `coalesce(auth.uid(), p_user_id)` fallbacks, and a rollback that restored the
-- baseline would silently undo that applied hardening. Body-only, grants preserved. Census -1
-- (the new function goes away). Any caller of release_reservation_for_payment
-- MUST be redeployed to the pre-127 webhook first, or it will fail PGRST202 /
-- undefined_function.
-- ============================================================================
begin;

drop function if exists public.release_reservation_for_payment(uuid, uuid, uuid);

-- 0590:64-84 VERBATIM (D review G-4): a reformatted body restores the logic but
-- not the text, so pg_get_functiondef's md5 after rollback differed from the
-- pre-127 value and a hash read-back could not prove the rollback. Byte-for-byte
-- from 0590_strict_auth_on_listing_checkout_rpcs.sql; do not tidy it.
CREATE OR REPLACE FUNCTION public.release_reservation(p_listing_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_reserved_by uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  -- Intentionally no NULL guard (preserved): if identity is unresolved we
  -- simply match nothing below and no-op.

  SELECT status, reserved_by INTO v_status, v_reserved_by
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_status = 'sold' THEN RETURN; END IF;

  IF v_status = 'reserved' AND v_reserved_by = v_caller_id THEN
    PERFORM set_config('app.bypass_listing_guard', 'on', true);
    UPDATE public.listings SET status='active', reserved_by=null, reserved_until=null
     WHERE id = p_listing_id;
  END IF;
END; $function$;

comment on function public.release_reservation(uuid, uuid) is null;

commit;
