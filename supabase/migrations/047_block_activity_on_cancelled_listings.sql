-- =============================================================================
-- 047_block_activity_on_cancelled_listings.sql
--
-- Cancelling a listing did not actually stop it being bought. Found while
-- verifying the web seller-management surface (2026-08-04) and reproduced
-- against production in a rolled-back transaction:
--
--   cancel_listing()  -> status='active', auction_status='cancelled'
--                        (it deliberately resets status to 'active' so the
--                         reservation is released)
--   then, with the clock still in the future:
--     INSERT INTO bids ...          -> ALLOWED
--     SELECT reserve_buy_now(...)   -> ALLOWED
--
-- Neither validate_and_apply_bid() nor reserve_buy_now() looked at
-- auction_status; they only checked `status` and the `ends_at` clock. A
-- cancelled listing therefore stayed biddable and buyable until its timer
-- ran out — a live money path on a listing the seller had withdrawn.
--
-- This affects BOTH clients (mobile and web) because the gap is server-side.
--
-- Fix: both functions now reject a listing whose auction_status is not
-- 'active'. This enforces the existing intent of cancellation rather than
-- changing any business rule — a cancelled, ended, or sold auction was never
-- meant to accept new bids or reservations.
--
-- Scope is deliberately narrow: no signature changes, no new columns, no RLS
-- or policy changes, and the existing checks/ordering are preserved so error
-- messages callers already match on (mobile PlaceBidScreen, web
-- lib/bids.ts + lib/checkout.ts) keep working. The new messages are additive.
--
-- Rollback: supabase/rollbacks/047_block_activity_on_cancelled_listings_rollback.sql
-- =============================================================================

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
  v_auction_status text;
BEGIN
  SELECT current_bid, ends_at, seller_id, auction_status
    INTO v_current_bid, v_ends_at, v_seller_id, v_auction_status
    FROM public.listings
   WHERE id = NEW.listing_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found.';
  END IF;

  IF NEW.bidder_id = v_seller_id THEN
    RAISE EXCEPTION 'You cannot bid on your own listing.';
  END IF;

  -- Added in 047. Covers cancelled/ended/sold; the clock check below still
  -- handles the ordinary "timer ran out but cron hasn't finalized yet" case.
  IF v_auction_status = 'cancelled' THEN
    RAISE EXCEPTION 'This listing has been cancelled.';
  END IF;

  IF v_auction_status <> 'active' THEN
    RAISE EXCEPTION 'This auction has ended.';
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
  v_auction_status text;
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
  select status, ends_at, reserved_by, reserved_until, auction_status
    into v_status, v_ends_at, v_reserved_by, v_reserved_until, v_auction_status
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

  -- 2b) Added in 047 — a cancelled listing keeps status='active' so that its
  -- reservation is released, which previously left it purchasable.
  if v_auction_status = 'cancelled' then
    raise exception 'This listing has been cancelled.';
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
