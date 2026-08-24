-- Migration 070: reconcile RLS policies + triggers to match production (Gate-2)
--
-- The Gate-2 fresh-DB replay showed production carries a set of RLS policies (on bids/listings/
-- profiles/transfers) and two triggers (bids.on_new_bid_notify, listings.trg_listings_updated_at)
-- that were applied OUT-OF-BAND during the web-accounts workstream (Supabase dashboard / SQL editor)
-- and never vendored — while the repo chain still produced the older mobile-baseline policy/trigger
-- names. The effective access control is equivalent (the prod-only policies are renamed/redundant
-- SELECT/UPDATE variants), but the object sets differed, so a fresh env did not reproduce production.
--
-- This migration captures production's EXACT policy + trigger set (verbatim from pg_policies /
-- pg_get_triggerdef on 2026-08-24) and aligns a fresh database to it. All DROP ... IF EXISTS +
-- CREATE are idempotent and run in one transaction, so this is a net no-op on production (it
-- recreates the identical objects atomically) and brings fresh/staging envs into exact agreement.
-- The `listings: auth insert` policy (the phone_verified + onboarding gate) is recreated verbatim.

-- ============================ bids ============================
drop policy if exists "bids: auth insert"        on public.bids;
drop policy if exists "bids: public select"      on public.bids;
drop policy if exists "bids_insert_authenticated" on public.bids;
drop policy if exists "bids_select_all"          on public.bids;
drop policy if exists "bids_select_own"          on public.bids;
create policy "bids_insert_authenticated" on public.bids for insert
  with check ((auth.uid() is not null) and (bidder_id = auth.uid()));
create policy "bids_select_all" on public.bids for select using (true);
create policy "bids_select_own" on public.bids for select to authenticated using (bidder_id = auth.uid());

-- ============================ listings ============================
drop policy if exists "listings: auth insert"       on public.listings;
drop policy if exists "listings: public select"     on public.listings;
drop policy if exists "listings: seller delete"     on public.listings;
drop policy if exists "listings: seller update own" on public.listings;
drop policy if exists "listings_delete_own"         on public.listings;
drop policy if exists "listings_select_all"         on public.listings;
drop policy if exists "listings_update_own"         on public.listings;
drop policy if exists "listings_update_own_meta"    on public.listings;
create policy "listings: auth insert" on public.listings for insert
  with check ((seller_id = auth.uid())
    and (exists (select 1 from public.profiles p where ((p.id = auth.uid()) and (p.stripe_onboarding_complete = true))))
    and phone_verified());
create policy "listings: seller update own" on public.listings for update
  using (seller_id = auth.uid()) with check (seller_id = auth.uid());
create policy "listings_delete_own" on public.listings for delete using (seller_id = auth.uid());
create policy "listings_select_all" on public.listings for select using (true);
create policy "listings_update_own" on public.listings for update
  using (seller_id = auth.uid()) with check (seller_id = auth.uid());
create policy "listings_update_own_meta" on public.listings for update to authenticated
  using (seller_id = auth.uid()) with check (seller_id = auth.uid());

-- ============================ profiles ============================
drop policy if exists "profiles: public read"  on public.profiles;
drop policy if exists "profiles: owner insert" on public.profiles;
drop policy if exists "profiles: owner update" on public.profiles;
drop policy if exists "profiles_insert_own"    on public.profiles;
drop policy if exists "profiles_select_all"    on public.profiles;
drop policy if exists "profiles_select_own"    on public.profiles;
drop policy if exists "profiles_update_own"    on public.profiles;
create policy "profiles: public read" on public.profiles for select using (true);
create policy "profiles_insert_own" on public.profiles for insert with check (id = auth.uid());
create policy "profiles_select_all" on public.profiles for select using (true);
create policy "profiles_select_own" on public.profiles for select using (id = auth.uid());
create policy "profiles_update_own" on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- ============================ transfers ============================
drop policy if exists "Buyers can view own transfers"  on public.transfers;
drop policy if exists "Sellers can view own transfers" on public.transfers;
drop policy if exists "Users can view their transfers" on public.transfers;
drop policy if exists "transfers: buyer select"        on public.transfers;
drop policy if exists "transfers: seller select"       on public.transfers;
create policy "Buyers can view own transfers"  on public.transfers for select using (auth.uid() = buyer_id);
create policy "Sellers can view own transfers" on public.transfers for select using (auth.uid() = seller_id);
create policy "Users can view their transfers" on public.transfers for select using ((auth.uid() = buyer_id) or (auth.uid() = seller_id));
create policy "transfers: buyer select"  on public.transfers for select using (buyer_id = auth.uid());
create policy "transfers: seller select" on public.transfers for select using (seller_id = auth.uid());

-- ============================ triggers ============================
-- notify_outbid on new bids (out-of-band in prod)
drop trigger if exists on_new_bid_notify on public.bids;
create trigger on_new_bid_notify after insert on public.bids for each row execute function public.notify_outbid();
-- listings updated_at trigger: production uses name trg_listings_updated_at (baseline used listings_set_updated_at)
drop trigger if exists listings_set_updated_at on public.listings;
drop trigger if exists trg_listings_updated_at on public.listings;
create trigger trg_listings_updated_at before update on public.listings for each row execute function public.set_updated_at();
