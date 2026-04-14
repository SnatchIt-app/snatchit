-- Migration 018: Prevent self-purchase in reserve_buy_now
-- Adds a seller_id check so the listing owner cannot reserve their own listing.

create or replace function public.reserve_buy_now(
  p_listing_id uuid,
  p_user_id    uuid,
  p_minutes    int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
$$;
