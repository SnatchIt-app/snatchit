-- 059_strict_auth_on_listing_checkout_rpcs.sql   APPLIED 2026-08-05, verified.
-- (applied as 059 + 059b)
--
-- Removes the LAST coalesce(auth.uid(), p_user_id) identity fallbacks, from the
-- six remaining RPCs: cancel_listing, release_reservation, mark_listing_sold,
-- complete_auction_payment, reserve_buy_now (059) and ensure_transfer_exists
-- (059b).
--
-- 055c had already revoked anon/PUBLIC EXECUTE on these, so the fallback was no
-- longer reachable without a session. This removes the pattern itself so a
-- future re-GRANT cannot silently reopen the hole.
--
-- auth.uid() is now authoritative everywhere; p_user_id is honoured ONLY when
-- request_is_service_role() is true, where auth.uid() is structurally NULL.
-- Signatures, bodies, guard-bypass GUCs and error strings are otherwise
-- preserved verbatim. ensure_transfer_exists keeps its payments
-- pending->succeeded promotion untouched -- that is payment logic and out of
-- scope here.
--
-- Verified live on a throwaway listing, then cleaned up:
--   LEGIT buyer reserve_buy_now          OK
--   LEGIT buyer release_reservation      OK
--   LEGIT seller cancel_listing          OK
--   ADV  forged p_user_id -> mark_listing_sold   REJECTED (not reserved by you)
--   ADV  forged p_user_id -> cancel_listing      REJECTED (only your own listings)
-- Post-apply: coalesce(auth.uid() fallbacks remaining across public = 0.
--
-- Rollback: supabase/rollbacks/059_strict_auth_on_listing_checkout_rpcs_rollback.sql

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805044821. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 059: remove the last coalesce(auth.uid(), p_user_id) identity fallbacks.
-- 055c already revoked anon/PUBLIC EXECUTE on these five, so the fallback was
-- no longer reachable unauthenticated. This removes the pattern itself so a
-- future re-GRANT cannot silently reopen it. auth.uid() is now authoritative;
-- p_user_id is honoured ONLY for service_role callers, where auth.uid() is
-- structurally NULL. Bodies are otherwise preserved verbatim.

CREATE OR REPLACE FUNCTION public.cancel_listing(p_listing_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_seller_id uuid; v_status text; v_auction_status text;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  SELECT seller_id, status, auction_status INTO v_seller_id, v_status, v_auction_status
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'You can only cancel your own listings.'; END IF;
  IF v_status = 'sold' THEN RAISE EXCEPTION 'This listing has already been sold and cannot be cancelled.'; END IF;
  IF v_auction_status = 'cancelled' THEN RETURN; END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET auction_status='cancelled', status='active', reserved_by=NULL,
         reserved_until=NULL, ended_at=now()
   WHERE id = p_listing_id;
END; $function$;

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

CREATE OR REPLACE FUNCTION public.mark_listing_sold(p_listing_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_reserved_by uuid; v_reserved_until timestamptz;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  SELECT status, reserved_by, reserved_until INTO v_status, v_reserved_by, v_reserved_until
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;
  IF v_status = 'sold' THEN RETURN; END IF;
  IF v_status <> 'reserved' OR v_reserved_by IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'This listing is not reserved by you.';
  END IF;

  IF v_reserved_until <= now() THEN
    PERFORM set_config('app.bypass_listing_guard', 'on', true);
    UPDATE public.listings SET status='active', reserved_by=null, reserved_until=null
     WHERE id = p_listing_id;
    RAISE EXCEPTION 'Your reservation has expired. Please try again.';
  END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET status='sold', auction_status='sold', sold_at=now(),
         reserved_by=null, reserved_until=null
   WHERE id = p_listing_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.complete_auction_payment(p_listing_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_auction_status text; v_winner_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  SELECT status, auction_status, winner_user_id INTO v_status, v_auction_status, v_winner_id
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;
  IF v_status = 'sold' THEN RETURN; END IF;
  IF v_auction_status = 'sold' THEN RETURN; END IF;
  IF v_auction_status <> 'ended' THEN RAISE EXCEPTION 'Auction is not in ended state.'; END IF;
  IF v_winner_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'You are not the auction winner.'; END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings SET status='sold', auction_status='sold', sold_at=now()
   WHERE id = p_listing_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.reserve_buy_now(p_listing_id uuid, p_user_id uuid, p_minutes integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_ends_at timestamptz;
        v_reserved_by uuid; v_reserved_until timestamptz; v_auction_status text;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings SET status='active', reserved_by=null, reserved_until=null
   WHERE id = p_listing_id AND status='reserved' AND reserved_until <= now();

  SELECT status, ends_at, reserved_by, reserved_until, auction_status
    INTO v_status, v_ends_at, v_reserved_by, v_reserved_until, v_auction_status
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;

  IF EXISTS (SELECT 1 FROM public.listings WHERE id = p_listing_id AND seller_id = v_caller_id) THEN
    RAISE EXCEPTION 'You cannot purchase your own listing.';
  END IF;
  IF v_status = 'sold' THEN RAISE EXCEPTION 'This listing has already been sold.'; END IF;
  IF v_auction_status = 'cancelled' THEN RAISE EXCEPTION 'This listing has been cancelled.'; END IF;
  IF now() > v_ends_at THEN RAISE EXCEPTION 'This auction has ended.'; END IF;
  IF v_status = 'reserved' THEN
    IF v_reserved_by IS DISTINCT FROM v_caller_id AND v_reserved_until > now() THEN
      RAISE EXCEPTION 'This listing is already reserved by another buyer.';
    END IF;
  END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET status='reserved', reserved_by=v_caller_id,
         reserved_until = now() + (p_minutes || ' minutes')::interval
   WHERE id = p_listing_id;
END; $function$;

REVOKE EXECUTE ON FUNCTION public.cancel_listing(uuid,uuid)           FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.release_reservation(uuid,uuid)      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_listing_sold(uuid,uuid)        FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.complete_auction_payment(uuid,uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reserve_buy_now(uuid,uuid,integer)  FROM PUBLIC, anon;
