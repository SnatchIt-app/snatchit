-- 059b_strict_auth_ensure_transfer_exists.sql
-- Rewrites ensure_transfer_exists() to strict auth.uid() identity (service_role may
-- still supply p_user_id), removing the last coalesce(auth.uid(), p_user_id) spoofing
-- fallback. Payment pending->succeeded promotion, ON CONFLICT idempotency and the
-- transfer-guard bypass GUC are preserved verbatim. Revokes anon/PUBLIC EXECUTE.
-- Recovered from supabase_migrations.schema_migrations version 20260805044913; applied 20260805044913. Not re-applied.

-- 059b: last coalesce(auth.uid(), p_user_id) fallback. Identity resolution only
-- -- the payments pending->succeeded promotion is payment logic and is
-- preserved verbatim, as is the ON CONFLICT idempotency and the bypass GUC.
CREATE OR REPLACE FUNCTION public.ensure_transfer_exists(p_listing_id uuid, p_user_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_payment_id uuid; v_seller_id uuid; v_buyer_id uuid;
  v_transfer_method text; v_existing_transfer uuid; v_new_transfer uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT id, seller_id, buyer_id INTO v_payment_id, v_seller_id, v_buyer_id
    FROM public.payments
   WHERE listing_id = p_listing_id AND buyer_id = v_caller_id
     AND status IN ('pending','succeeded')
   ORDER BY created_at DESC LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'No payment found for this listing.'; END IF;

  UPDATE public.payments
     SET status='succeeded', paid_at = coalesce(paid_at, now())
   WHERE id = v_payment_id AND status = 'pending';

  SELECT id INTO v_existing_transfer FROM public.transfers WHERE payment_id = v_payment_id;
  IF FOUND THEN RETURN v_existing_transfer; END IF;

  SELECT transfer_method INTO v_transfer_method FROM public.listings WHERE id = p_listing_id;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);

  INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
  VALUES (p_listing_id, v_payment_id, v_seller_id, v_buyer_id,
          coalesce(v_transfer_method,'mobile_transfer'), 'pending', now() + interval '24 hours')
  ON CONFLICT (payment_id) DO NOTHING
  RETURNING id INTO v_new_transfer;

  IF v_new_transfer IS NULL THEN
    SELECT id INTO v_new_transfer FROM public.transfers WHERE payment_id = v_payment_id;
  END IF;

  RETURN v_new_transfer;
END; $function$;

REVOKE EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid,uuid) TO authenticated, service_role;
