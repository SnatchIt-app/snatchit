-- Rollback for 047_block_activity_on_cancelled_listings.sql
--
-- Restores validate_and_apply_bid() and reserve_buy_now() to their pre-047
-- definitions. WARNING: this re-opens the hole where a cancelled listing can
-- still receive bids and Buy Now reservations until its clock expires.

BEGIN;


-- ── Bids: reject unless the auction is still active ─────────────────────────
CREATE OR REPLACE FUNCTION public.validate_and_apply_bid()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_current_bid    int;
  v_ends_at        timestamptz;
  v_seller_id      uuid;
  v_last_bid_at    timestamptz;
BEGIN
  SELECT current_bid, ends_at, seller_id
    INTO v_current_bid, v_ends_at, v_seller_id
    FROM public.listings
   WHERE id = NEW.listing_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found.';
  END IF;

  IF NEW.bidder_id = v_seller_id THEN
    RAISE EXCEPTION 'You cannot bid on your own listing.';
  END IF;

  IF NOW() > v_ends_at THEN
    RAISE EXCEPTION 'This auction has ended.';
  END IF;

  IF NEW.amount <= v_current_bid THEN
    RAISE EXCEPTION 'Bid must be greater than the current bid of $%.', v_current_bid;
  END IF;

  SELECT created_at INTO v_last_bid_at
    FROM public.bids
   WHERE listing_id = NEW.listing_id
     AND bidder_id  = NEW.bidder_id
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_last_bid_at IS NOT NULL AND NOW() - v_last_bid_at < INTERVAL '3 seconds' THEN
    RAISE EXCEPTION 'Please wait before bidding again.';
  END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET current_bid       = NEW.amount,
         bid_count         = bid_count + 1,
         highest_bidder_id = NEW.bidder_id
   WHERE id = NEW.listing_id;

  RETURN NEW;
END;
$function$;

-- ── Buy Now: reject a reservation on a cancelled listing ────────────────────
CREATE OR REPLACE FUNCTION public.reserve_buy_now(p_listing_id uuid, p_user_id uuid, p_minutes integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_caller_id      uuid;
  v_status         text;
  v_ends_at        timestamptz;
  v_reserved_by    uuid;
  v_reserved_until timestamptz;
begin
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  -- 0) Auto-release any expired reservation on THIS listing first.
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'active',
         reserved_by    = null,
         reserved_until = null
   where id = p_listing_id
     and status = 'reserved'
     and reserved_until <= now();

  -- 1) Lock the listing row for the duration of this transaction.
  select status, ends_at, reserved_by, reserved_until
    into v_status, v_ends_at, v_reserved_by, v_reserved_until
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- 1b) Reject self-purchase — seller cannot reserve their own listing.
  if exists (
    select 1 from public.listings
     where id = p_listing_id and seller_id = v_caller_id
  ) then
    raise exception 'You cannot purchase your own listing.';
  end if;

  -- 2) Reject if already sold.
  if v_status = 'sold' then
    raise exception 'This listing has already been sold.';
  end if;

  -- 3) Reject if auction has ended.
  if now() > v_ends_at then
    raise exception 'This auction has ended.';
  end if;

  -- 4) Handle existing reservation.
  if v_status = 'reserved' then
    if v_reserved_by is distinct from v_caller_id
       and v_reserved_until > now() then
      raise exception 'This listing is already reserved by another buyer.';
    end if;
  end if;

  -- 5) Reserve the listing.
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'reserved',
         reserved_by    = v_caller_id,
         reserved_until = now() + (p_minutes || ' minutes')::interval
   where id = p_listing_id;
end;
$function$;

COMMIT;
