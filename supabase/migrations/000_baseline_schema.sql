-- =============================================================================
-- SnatchIt — Supabase Schema
-- Run this in: Supabase Dashboard → SQL Editor → New query → Run
--
-- Tables:  profiles · listings · bids
-- Storage: auction-media bucket (create manually in Storage UI or via block 5)
-- =============================================================================


-- ===========================================================================
-- 1. PROFILES
-- ===========================================================================
create table if not exists public.profiles (
  id          uuid        primary key references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  full_name   text,
  phone       text
);

-- Auto-create a profile row whenever a new user signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- RLS
alter table public.profiles enable row level security;

drop policy if exists "profiles: owner select"  on public.profiles;
drop policy if exists "profiles: public read"   on public.profiles;
drop policy if exists "profiles: owner insert"  on public.profiles;
drop policy if exists "profiles: owner update"  on public.profiles;

-- Any authenticated user can read any profile (display_name, avatar, etc. are not sensitive).
-- PostgREST joins (bids → profiles) require this policy.
create policy "profiles: public read"
  on public.profiles for select
  using (true);

create policy "profiles: owner insert"
  on public.profiles for insert
  with check (id = auth.uid());

create policy "profiles: owner update"
  on public.profiles for update
  using (id = auth.uid());


-- ===========================================================================
-- 2. LISTINGS
-- ===========================================================================
create table if not exists public.listings (
  id               uuid        primary key default gen_random_uuid(),
  created_at       timestamptz not null default now(),
  seller_id        uuid        not null references auth.users (id),

  -- Event
  event_name       text        not null,
  venue            text        not null,
  neighborhood     text        not null
    check (neighborhood in (
      'south beach','wynwood','brickell','downtown miami',
      'design district','coconut grove','little havana','miami beach','midtown'
    )),
  event_date       date        not null,
  event_time       time        not null,

  -- Tickets
  ticket_type      text        not null check (ticket_type in ('GA','VIP','TABLE')),
  quantity         int         not null check (quantity >= 1),
  transfer_method  text        not null check (transfer_method in ('mobile_transfer','email')),
  restrictions     text,

  -- Pricing
  starting_bid     int         not null check (starting_bid > 0),
  buy_now_enabled  boolean     not null default false,
  buy_now_price    int         check (buy_now_price is null or buy_now_price > 0),
  duration_hours   int         not null check (duration_hours in (1,3,6,12,24,48)),

  -- Auction window
  starts_at        timestamptz not null default now(),
  ends_at          timestamptz not null,

  -- Live state
  current_bid      int         not null,

  -- Media
  cover_image_path text        not null
);

create index if not exists listings_seller_id_idx    on public.listings (seller_id);
create index if not exists listings_ends_at_idx      on public.listings (ends_at);
create index if not exists listings_neighborhood_idx on public.listings (neighborhood);

-- ── Performance indexes on status/auction_status/reserved_until are created
--    AFTER the listings ADD COLUMN block below — those columns do not exist at
--    this point in a fresh bootstrap. (Gate-2 fix: index-before-column ordering.)

alter table public.listings enable row level security;

drop policy if exists "listings: public select"  on public.listings;
drop policy if exists "listings: auth insert"    on public.listings;
drop policy if exists "listings: seller update"     on public.listings;
drop policy if exists "listings: seller update own" on public.listings;
drop policy if exists "listings: seller delete"     on public.listings;

create policy "listings: public select"
  on public.listings for select using (true);

create policy "listings: auth insert"
  on public.listings for insert
  with check (seller_id = auth.uid());

create policy "listings: seller update own"
  on public.listings for update
  using (seller_id = auth.uid())
  with check (
    seller_id = auth.uid()
    -- WITH CHECK ensures seller_id can't be changed to someone else
  );

create policy "listings: seller delete"
  on public.listings for delete
  using (seller_id = auth.uid());


-- ===========================================================================
-- 3. BIDS
-- ===========================================================================
create table if not exists public.bids (
  id          uuid        primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  listing_id  uuid        not null references public.listings (id) on delete cascade,
  bidder_id   uuid        not null references auth.users (id),
  amount      int         not null check (amount > 0)
);

create index if not exists bids_listing_id_idx on public.bids (listing_id);
create index if not exists bids_bidder_id_idx  on public.bids (bidder_id);

-- ── Performance indexes ─────────────────────────────────────────────────────
create index if not exists idx_bids_listing_id
  on public.bids (listing_id, amount desc);
create index if not exists idx_bids_bidder_id
  on public.bids (bidder_id, created_at desc);
create index if not exists idx_bids_rate_limit
  on public.bids (listing_id, bidder_id, created_at desc);

alter table public.bids enable row level security;

drop policy if exists "bids: public select" on public.bids;
drop policy if exists "bids: auth insert"   on public.bids;

create policy "bids: public select"
  on public.bids for select using (true);

create policy "bids: auth insert"
  on public.bids for insert
  with check (bidder_id = auth.uid());


-- ===========================================================================
-- 4. BID VALIDATION TRIGGER
-- Enforces: amount > current_bid  AND  auction not ended
-- Updates listings.current_bid atomically on every valid bid.
-- Recommended over RPC — runs inside the transaction, cannot be bypassed.
-- ===========================================================================
create or replace function public.validate_and_apply_bid()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_current_bid int;
  v_ends_at     timestamptz;
  v_seller_id   uuid;
  v_last_bid_at timestamptz;
begin
  select current_bid, ends_at, seller_id
    into v_current_bid, v_ends_at, v_seller_id
    from public.listings
   where id = new.listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- Seller cannot bid on own listing (shill-bid prevention)
  if new.bidder_id = v_seller_id then
    raise exception 'You cannot bid on your own listing.';
  end if;

  if now() > v_ends_at then
    raise exception 'This auction has ended.';
  end if;

  if new.amount <= v_current_bid then
    raise exception 'Bid must be greater than the current bid of $%.', v_current_bid;
  end if;

  -- Rate limit: 1 bid per 3 seconds per user per listing
  select created_at into v_last_bid_at
    from public.bids
   where listing_id = new.listing_id
     and bidder_id  = new.bidder_id
   order by created_at desc
   limit 1;

  if v_last_bid_at is not null and now() - v_last_bid_at < interval '3 seconds' then
    raise exception 'Please wait before bidding again.';
  end if;

  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set current_bid       = new.amount,
         bid_count         = bid_count + 1,
         highest_bidder_id = new.bidder_id
   where id = new.listing_id;

  return new;
end;
$$;

drop trigger if exists before_bid_insert on public.bids;
create trigger before_bid_insert
  before insert on public.bids
  for each row execute procedure public.validate_and_apply_bid();


-- ===========================================================================
-- 5. STORAGE — auction-media bucket
-- Run once. Skip if you already created the bucket in the Storage UI.
-- ===========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'auction-media',
  'auction-media',
  true,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict (id) do nothing;

drop policy if exists "storage: public read"   on storage.objects;
drop policy if exists "storage: owner upload"  on storage.objects;
drop policy if exists "storage: owner delete"  on storage.objects;

create policy "storage: public read"
  on storage.objects for select
  using (bucket_id = 'auction-media');

create policy "storage: owner upload"
  on storage.objects for insert
  with check (
    bucket_id = 'auction-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "storage: owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'auction-media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );


-- ===========================================================================
-- 6. MIGRATIONS — Add columns missing from TypeScript types
-- Safe to re-run: every statement uses ADD COLUMN IF NOT EXISTS.
-- ===========================================================================

-- ── profiles ────────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists display_name       text;
alter table public.profiles add column if not exists avatar_url         text;   -- legacy full-URL column (kept for backward compat)
alter table public.profiles add column if not exists avatar_path        text;
alter table public.profiles add column if not exists phone_number       text;
alter table public.profiles add column if not exists is_verified_buyer  boolean not null default false;
alter table public.profiles add column if not exists is_verified_seller boolean not null default false;
alter table public.profiles add column if not exists wallet_balance     numeric(10,2) not null default 0;
alter table public.profiles add column if not exists bio                text;
alter table public.profiles add column if not exists preferred_neighborhoods text[] not null default '{}';

-- ── listings — reservation / sale lifecycle ─────────────────────────────────
alter table public.listings add column if not exists status          text        not null default 'active'
  check (status in ('active','reserved','sold'));
alter table public.listings add column if not exists reserved_by     uuid        references auth.users (id);
alter table public.listings add column if not exists reserved_until  timestamptz;
alter table public.listings add column if not exists sold_at         timestamptz;
alter table public.listings add column if not exists updated_at      timestamptz not null default now();

-- ── listings — auction intelligence ─────────────────────────────────────────
alter table public.listings add column if not exists auction_status      text not null default 'active'
  check (auction_status in ('active','ended','sold','cancelled'));
alter table public.listings add column if not exists winner_user_id      uuid references auth.users (id);
alter table public.listings add column if not exists winning_bid_amount  int;
alter table public.listings add column if not exists ended_at            timestamptz;

-- ── listings — bid tracking (denormalised for fast reads) ─────────────────
alter table public.listings add column if not exists bid_count          int  not null default 0;
alter table public.listings add column if not exists highest_bidder_id  uuid references auth.users (id);

-- ── Performance indexes (relocated here so their columns exist on a fresh DB) ─
create index if not exists idx_listings_status          on public.listings (status);
create index if not exists idx_listings_auction_status  on public.listings (auction_status);
create index if not exists idx_listings_ends_at         on public.listings (ends_at) where auction_status = 'active';
create index if not exists idx_listings_reserved_until  on public.listings (reserved_until) where status = 'reserved';

-- ── listings — updated_at trigger ───────────────────────────────────────────
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists listings_set_updated_at on public.listings;
create trigger listings_set_updated_at
  before update on public.listings
  for each row execute procedure public.set_updated_at();


-- ===========================================================================
-- 7a. cleanup_expired_reservations — release stale reservations
-- Called inline by reserve_buy_now; also usable from a cron job.
-- ===========================================================================
create or replace function public.cleanup_expired_reservations()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'active',
         reserved_by    = null,
         reserved_until = null
   where status = 'reserved'
     and reserved_until <= now();
end;
$$;


-- ===========================================================================
-- 7b. reserve_buy_now — atomic Buy Now reservation
-- Called from ListingDetailScreen via supabase.rpc('reserve_buy_now', {...})
-- Params: p_listing_id uuid, p_user_id uuid, p_minutes int
-- Auto-releases any expired reservation on the target listing before locking.
-- ===========================================================================
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
  v_caller_id      uuid;        -- resolved identity: auth.uid() or p_user_id
  v_status         text;
  v_ends_at        timestamptz;
  v_reserved_by    uuid;
  v_reserved_until timestamptz;
begin
  -- SECURITY: use auth.uid() for client calls; fall back to p_user_id for
  -- service-role / webhook / SQL Editor calls where auth.uid() is NULL.
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
    -- If reserved by someone else and not yet expired, reject.
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


-- ===========================================================================
-- 8. mark_listing_sold — finalize a Buy Now purchase
-- Called from CheckoutScreen via supabase.rpc('mark_listing_sold', {...})
-- Params: p_listing_id uuid, p_user_id uuid
-- ===========================================================================
create or replace function public.mark_listing_sold(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id      uuid;        -- resolved identity: auth.uid() or p_user_id
  v_status         text;
  v_reserved_by    uuid;
  v_reserved_until timestamptz;
begin
  -- SECURITY: auth.uid() wins for client calls; p_user_id used for service-role.
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  -- 1) Lock the listing row.
  select status, reserved_by, reserved_until
    into v_status, v_reserved_by, v_reserved_until
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- 2) Already sold — nothing to do, but not an error for idempotency.
  if v_status = 'sold' then
    return;
  end if;

  -- 3) Must be reserved by this caller.
  if v_status <> 'reserved' or v_reserved_by is distinct from v_caller_id then
    raise exception 'This listing is not reserved by you.';
  end if;

  -- 4) Reservation must not have expired.
  if v_reserved_until <= now() then
    -- Reset to active since the reservation lapsed.
    perform set_config('app.bypass_listing_guard', 'on', true);
    update public.listings
       set status         = 'active',
           reserved_by    = null,
           reserved_until = null
     where id = p_listing_id;
    raise exception 'Your reservation has expired. Please try again.';
  end if;

  -- 5) Mark sold.
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'sold',
         sold_at        = now(),
         reserved_by    = null,
         reserved_until = null
   where id = p_listing_id;
end;
$$;


-- ===========================================================================
-- 9. release_reservation — cancel a Buy Now reservation
-- Called from CheckoutScreen on unmount (back/cancel without confirming)
-- Params: p_listing_id uuid, p_user_id uuid
-- ===========================================================================
create or replace function public.release_reservation(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id   uuid;        -- resolved identity: auth.uid() or p_user_id
  v_status      text;
  v_reserved_by uuid;
begin
  -- SECURITY: auth.uid() wins for client calls; p_user_id used for service-role.
  -- No NULL guard here — if both are NULL we simply perform a no-op (nothing
  -- was ever reserved by an identifiable caller).
  v_caller_id := coalesce(auth.uid(), p_user_id);

  -- 1) Lock the listing row.
  select status, reserved_by
    into v_status, v_reserved_by
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    return;  -- nothing to release
  end if;

  -- 2) Already sold — no-op (purchase went through on another device / tab).
  if v_status = 'sold' then
    return;
  end if;

  -- 3) Only release if still reserved by this same caller.
  if v_status = 'reserved' and v_reserved_by = v_caller_id then
    perform set_config('app.bypass_listing_guard', 'on', true);
    update public.listings
       set status         = 'active',
           reserved_by    = null,
           reserved_until = null
     where id = p_listing_id;
  end if;

  -- Any other state (active, reserved by someone else) — no-op.
end;
$$;


-- ===========================================================================
-- 10. finalize_auction — determine winner after auction clock expires
-- Called from ListingDetailScreen via supabase.rpc('finalize_auction', {...})
-- Params: p_listing_id uuid
-- ===========================================================================
create or replace function public.finalize_auction(
  p_listing_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_auction_status text;
  v_ends_at        timestamptz;
  v_top_bidder     uuid;
  v_top_amount     int;
begin
  -- 1) Lock the listing row.
  select auction_status, ends_at
    into v_auction_status, v_ends_at
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- 2) Must still be active.
  if v_auction_status <> 'active' then
    raise exception 'Auction is not active (current status: %).', v_auction_status;
  end if;

  -- 3) Clock must have expired.
  if v_ends_at > now() then
    raise exception 'Auction has not ended yet.';
  end if;

  -- 4) Find the highest bid.
  select bidder_id, amount
    into v_top_bidder, v_top_amount
    from public.bids
   where listing_id = p_listing_id
   order by amount desc
   limit 1;

  -- 5) Update the listing.
  perform set_config('app.bypass_listing_guard', 'on', true);
  if v_top_bidder is not null then
    -- Winner exists.
    update public.listings
       set auction_status     = 'ended',
           winner_user_id     = v_top_bidder,
           winning_bid_amount = v_top_amount,
           ended_at           = now()
     where id = p_listing_id;
  else
    -- No bids — end with no winner.
    update public.listings
       set auction_status = 'ended',
           ended_at       = now()
     where id = p_listing_id;
  end if;
end;
$$;


-- ===========================================================================
-- 10b. auto_finalize_expired_auctions — batch finalization
-- Called by cron/edge function to finalize expired auctions.
-- Loops over ALL listings where auction_status='active' AND ends_at <= now(),
-- determines winner (if any), and sets auction_status='ended'.
-- Also cleans up expired reservations via cleanup_expired_reservations().
-- Returns the number of auctions finalized.
-- ===========================================================================
create or replace function public.auto_finalize_expired_auctions()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing   record;
  v_top_bid   record;
  v_count     int := 0;
begin
  for v_listing in
    select id
      from public.listings
     where auction_status = 'active'
       and ends_at <= now()
       for update skip locked
  loop
    -- Find the highest bid for this listing
    select bidder_id, amount
      into v_top_bid
      from public.bids
     where listing_id = v_listing.id
     order by amount desc
     limit 1;

    perform set_config('app.bypass_listing_guard', 'on', true);

    if v_top_bid.bidder_id is not null then
      update public.listings
         set auction_status     = 'ended',
             winner_user_id     = v_top_bid.bidder_id,
             winning_bid_amount = v_top_bid.amount,
             ended_at           = now()
       where id = v_listing.id;
    else
      update public.listings
         set auction_status = 'ended',
             ended_at       = now()
       where id = v_listing.id;
    end if;

    v_count := v_count + 1;
  end loop;

  -- Also clean up expired reservations while we're here
  perform public.cleanup_expired_reservations();

  return v_count;
end;
$$;


-- ===========================================================================
-- 10b. cancel_listing — seller cancels their own listing (even with bids)
-- Sets auction_status to 'cancelled' so bids are voided but the record stays.
-- ===========================================================================
create or replace function public.cancel_listing(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id      uuid;        -- resolved identity: auth.uid() or p_user_id
  v_seller_id      uuid;
  v_status         text;
  v_auction_status text;
begin
  -- SECURITY: auth.uid() wins for client calls; p_user_id used for service-role.
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  select seller_id, status, auction_status
    into v_seller_id, v_status, v_auction_status
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;
  if v_seller_id is distinct from v_caller_id then
    raise exception 'You can only cancel your own listings.';
  end if;
  if v_status = 'sold' then
    raise exception 'This listing has already been sold and cannot be cancelled.';
  end if;
  if v_auction_status = 'cancelled' then
    return; -- already cancelled, idempotent
  end if;

  perform set_config('app.bypass_listing_guard', 'on', true);

  update public.listings
     set auction_status = 'cancelled',
         status         = 'active',
         reserved_by    = null,
         reserved_until = null,
         ended_at       = now()
   where id = p_listing_id;
end;
$$;


-- ===========================================================================
-- 11. GUARD TRIGGER — block direct client edits to state columns on listings
-- SECURITY DEFINER RPCs set a session flag before modifying these columns.
-- Direct client UPDATEs (via PostgREST) cannot set this flag.
-- ===========================================================================
create or replace function public.guard_listing_state_columns()
returns trigger language plpgsql as $$
begin
  -- Allow if called from a trusted RPC (they set this flag before updating)
  if current_setting('app.bypass_listing_guard', true) = 'on' then
    return new;
  end if;

  -- Block changes to state-managed columns
  if new.current_bid        is distinct from old.current_bid
  or new.bid_count          is distinct from old.bid_count
  or new.highest_bidder_id  is distinct from old.highest_bidder_id
  or new.status             is distinct from old.status
  or new.auction_status     is distinct from old.auction_status
  or new.winner_user_id     is distinct from old.winner_user_id
  or new.winning_bid_amount is distinct from old.winning_bid_amount
  or new.reserved_by        is distinct from old.reserved_by
  or new.reserved_until     is distinct from old.reserved_until
  or new.sold_at            is distinct from old.sold_at
  or new.ended_at           is distinct from old.ended_at
  then
    raise exception 'Cannot directly modify auction state columns. Use the appropriate action (bid, buy now, etc.).';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_listing_state on public.listings;
create trigger guard_listing_state
  before update on public.listings
  for each row execute procedure public.guard_listing_state_columns();


-- ===========================================================================
-- 11b. IDENTITY GUARD — block changes to immutable identity columns
-- These columns must NEVER change after insert, even by the seller.
-- Unlike the state guard above, there is no bypass flag — nothing may
-- change seller_id, id, or created_at.
-- ===========================================================================
create or replace function public.guard_listing_identity_columns()
returns trigger language plpgsql as $$
begin
  if new.seller_id is distinct from old.seller_id then
    raise exception 'Cannot change listing owner.';
  end if;
  if new.id is distinct from old.id then
    raise exception 'Cannot change listing ID.';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'Cannot change creation timestamp.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_listing_identity on public.listings;
create trigger trg_guard_listing_identity
  before update on public.listings
  for each row execute function public.guard_listing_identity_columns();


-- ===========================================================================
-- 12. profiles_public view — REMOVED
-- The "profiles: public read" policy (block 1) now allows any authenticated
-- user to SELECT from profiles directly.  PostgREST resolves
-- bids → profiles joins without needing an intermediate view.
-- Drop the view if it was created by a previous schema run.
-- ===========================================================================
drop view if exists public.profiles_public;


-- ===========================================================================
-- 12. STORAGE — avatars bucket + policies
-- Path pattern: <userId>/avatar_<timestamp>.<ext>
-- Mirrors the auction-media pattern from block 5.
-- ===========================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic']
)
on conflict (id) do nothing;

drop policy if exists "avatars: public read"   on storage.objects;
drop policy if exists "avatars: owner upload"  on storage.objects;
drop policy if exists "avatars: owner delete"  on storage.objects;

create policy "avatars: public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "avatars: owner upload"
  on storage.objects for insert
  with check (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "avatars: owner delete"
  on storage.objects for delete
  using (
    bucket_id = 'avatars'
    and auth.uid()::text = (storage.foldername(name))[1]
  );


-- ===========================================================================
-- 13. PUSH NOTIFICATIONS — tokens + preferences
-- ===========================================================================

-- ── Push Tokens ──────────────────────────────────────────────────────────────
-- Stores Expo push tokens per device per user.
create table if not exists public.push_tokens (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  token       text        not null unique,
  platform    text        not null check (platform in ('ios', 'android')),
  device_name text,
  created_at  timestamptz not null default now(),
  last_used   timestamptz,
  is_active   boolean     not null default true
);

create index if not exists idx_push_tokens_user_id
  on public.push_tokens(user_id);
create index if not exists idx_push_tokens_active
  on public.push_tokens(user_id) where is_active = true;

alter table public.push_tokens enable row level security;

drop policy if exists "push_tokens: owner insert" on public.push_tokens;
drop policy if exists "push_tokens: owner select" on public.push_tokens;
drop policy if exists "push_tokens: owner update" on public.push_tokens;
drop policy if exists "push_tokens: owner delete" on public.push_tokens;

create policy "push_tokens: owner insert"
  on public.push_tokens for insert
  with check (user_id = auth.uid());

create policy "push_tokens: owner select"
  on public.push_tokens for select
  using (user_id = auth.uid());

create policy "push_tokens: owner update"
  on public.push_tokens for update
  using (user_id = auth.uid());

create policy "push_tokens: owner delete"
  on public.push_tokens for delete
  using (user_id = auth.uid());

-- ── Notification Preferences ─────────────────────────────────────────────────
-- Per-user toggle settings. Auto-created on profile insert.
create table if not exists public.notification_preferences (
  user_id                 uuid        primary key references auth.users(id) on delete cascade,
  notify_outbid           boolean     not null default true,
  notify_auction_ending   boolean     not null default true,
  notify_auction_won      boolean     not null default true,
  notify_auction_lost     boolean     not null default false,
  notify_reservation_exp  boolean     not null default true,
  notify_listing_sold     boolean     not null default true,
  updated_at              timestamptz not null default now()
);

alter table public.notification_preferences enable row level security;

drop policy if exists "notification_preferences: owner manage" on public.notification_preferences;

create policy "notification_preferences: owner manage"
  on public.notification_preferences for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Auto-create preferences row when a new user signs up
create or replace function public.handle_new_user_notification_prefs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_new_user_notification_prefs on public.profiles;
create trigger trg_new_user_notification_prefs
  after insert on public.profiles
  for each row
  execute function public.handle_new_user_notification_prefs();

-- Backfill preferences for existing users
insert into public.notification_preferences (user_id)
select id from auth.users
on conflict (user_id) do nothing;


-- ===========================================================================
-- 14. PAYMENTS — tracks every Stripe charge
-- ===========================================================================

create table if not exists public.payments (
  id                         uuid        primary key default gen_random_uuid(),
  listing_id                 uuid        not null references public.listings(id),
  buyer_id                   uuid        not null references auth.users(id),
  seller_id                  uuid        not null references auth.users(id),

  -- Amounts (stored in cents for precision). 10/10 fee model:
  --   amount      = listing price (what seller listed)
  --   buyer_fee   = 10% added on top of `amount`, charged to buyer
  --   seller_fee  = 10% withheld from seller payout at release
  --   total       = amount + buyer_fee (= what Stripe charges the card)
  amount                     int         not null check (amount > 0),
  buyer_fee                  int         not null check (buyer_fee >= 0),
  seller_fee                 int         not null default 0 check (seller_fee >= 0),
  total                      int         not null check (total > 0),

  -- Stripe references
  stripe_payment_intent_id   text        unique,
  stripe_client_secret       text,

  -- Payment lifecycle
  status                     text        not null default 'pending'
                                         check (status in ('pending','processing','succeeded','failed','refunded')),
  payment_method             text,       -- 'card', 'apple_pay', 'google_pay'
  mode                       text        not null check (mode in ('buy_now','auction')),

  -- Timestamps
  created_at                 timestamptz not null default now(),
  paid_at                    timestamptz,
  failed_at                  timestamptz,
  refunded_at                timestamptz
);

-- ── Indexes ──────────────────────────────────────────────────────────────────
create index if not exists idx_payments_listing_id
  on public.payments(listing_id);
create index if not exists idx_payments_buyer_id
  on public.payments(buyer_id);
create index if not exists idx_payments_seller_id
  on public.payments(seller_id);
create index if not exists idx_payments_stripe_pi
  on public.payments(stripe_payment_intent_id);
create index if not exists idx_payments_status
  on public.payments(status);

-- ── RLS ──────────────────────────────────────────────────────────────────────
alter table public.payments enable row level security;

-- Buyers can see their own payments
drop policy if exists "payments: buyer select" on public.payments;
create policy "payments: buyer select"
  on public.payments for select
  using (buyer_id = auth.uid());

-- Sellers can see payments for their listings
drop policy if exists "payments: seller select" on public.payments;
create policy "payments: seller select"
  on public.payments for select
  using (seller_id = auth.uid());

-- Only edge functions (service role) can insert/update payments
-- No client-side insert/update policies — payments are server-managed


-- ===========================================================================
-- 15. complete_auction_payment — finalize an auction winner's payment
-- Called from CheckoutScreen (mode=auction) after Stripe payment succeeds.
-- Unlike mark_listing_sold (which requires status='reserved'), this checks
-- auction_status='ended' and winner_user_id matches the caller.
-- ===========================================================================
create or replace function public.complete_auction_payment(
  p_listing_id uuid,
  p_user_id    uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id      uuid;        -- resolved identity: auth.uid() or p_user_id
  v_auction_status text;
  v_winner_id      uuid;
begin
  -- SECURITY: auth.uid() wins for client calls; p_user_id used for service-role.
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  select auction_status, winner_user_id
    into v_auction_status, v_winner_id
    from public.listings
   where id = p_listing_id
     for update;

  if not found then
    raise exception 'Listing not found.';
  end if;

  -- Already sold — idempotent
  if v_auction_status = 'sold' then
    return;
  end if;

  if v_auction_status <> 'ended' then
    raise exception 'Auction is not in ended state.';
  end if;

  if v_winner_id is distinct from v_caller_id then
    raise exception 'You are not the auction winner.';
  end if;

  perform set_config('app.bypass_listing_guard', 'on', true);

  update public.listings
     set status         = 'sold',
         auction_status = 'sold',
         sold_at        = now()
   where id = p_listing_id;
end;
$$;
