-- ============================================================================
-- ROLLBACK for 20260906100000_checkout_reservation_authority.sql
--
-- Restores the THREE shipped-client RPC bodies exactly as migration
-- 0590_strict_auth_on_listing_checkout_rpcs.sql defined them (text copied
-- verbatim from that file — not retyped), re-issues the 0552/0590 grant
-- posture, and drops the Package 1 settlement core.
--
-- WARNING: this re-opens investigation findings F03 (mark_listing_sold /
-- complete_auction_payment settle WITHOUT a payment check) and F04
-- (reserve_buy_now honours an unbounded p_minutes, extends on every call, has
-- no per-buyer limit and no rate limit). Prefer fixing forward. Do NOT run
-- while Package 2's settle_verified_payment exists — it calls the core.
--
-- Verification after rollback:
--   select proname from pg_proc where pronamespace='public'::regnamespace
--     and proname='settle_listing_for_payment';   -- expect 0 rows
--   supabase/tests/120_reservation_lifecycle.sql must FAIL its new-behaviour
--   assertions (A2/A4/A6/A9/B1/B3 ... and H1-H4/H6/H8/H9: paid inventory
--   becomes re-reservable again); 030/040/110 #17 revert to 0590 text.
-- ============================================================================

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

-- Grant posture as left by 0552 + 0590 (client roles: authenticated; server:
-- service_role; anon/PUBLIC stripped).
REVOKE EXECUTE ON FUNCTION public.mark_listing_sold(uuid, uuid)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.complete_auction_payment(uuid, uuid)   FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reserve_buy_now(uuid, uuid, integer)   FROM PUBLIC, anon, authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.mark_listing_sold(uuid, uuid)          TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.complete_auction_payment(uuid, uuid)   TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.reserve_buy_now(uuid, uuid, integer)   TO authenticated, service_role;

-- Package 1 core: nothing else references it until Package 2 lands.
DROP FUNCTION IF EXISTS public.settle_listing_for_payment(uuid);
