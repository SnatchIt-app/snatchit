-- ============================================================
-- Migration 001: Profile + Auction additions for Profile screen
-- Run in Supabase Dashboard → SQL Editor
-- ============================================================

-- ── Add new columns to profiles ──────────────────────────────
alter table public.profiles
  add column if not exists phone_number        text,
  add column if not exists is_verified_buyer   boolean not null default false,
  add column if not exists is_verified_seller  boolean not null default false,
  add column if not exists wallet_balance       numeric(10,2) not null default 0;

-- ── Legacy: auctions table no longer exists (replaced by listings) ────
-- The following statements are kept commented-out for historical reference.
-- winner_user_id and winning_bid_amount are now on public.listings (see schema.sql block 6).
-- ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS winner_id uuid;
-- ALTER TABLE public.auctions ADD COLUMN IF NOT EXISTS final_price int;
