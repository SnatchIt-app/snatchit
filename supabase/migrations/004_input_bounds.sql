-- =============================================================================
-- Migration 004: Server-enforced input bounds
-- =============================================================================
-- PURPOSE: Add CHECK constraints to prevent oversized text and out-of-range
-- numeric values from reaching the database regardless of client behavior.
--
-- This migration is additive only. No existing columns, types, or defaults
-- are changed. No indexes are added or removed.
--
-- REQUIRED PRE-CHECKS — run these in the SQL editor BEFORE applying.
-- Every query must return 0 rows. If any return rows, truncate or correct
-- the offending data before running this migration.
--
--   SELECT id FROM public.listings   WHERE char_length(event_name)  > 120;
--   SELECT id FROM public.listings   WHERE char_length(venue)        > 120;
--   SELECT id FROM public.listings   WHERE restrictions IS NOT NULL
--                                      AND char_length(restrictions) > 500;
--   SELECT id FROM public.profiles   WHERE display_name IS NOT NULL
--                                      AND char_length(display_name) > 50;
--   SELECT id FROM public.profiles   WHERE full_name IS NOT NULL
--                                      AND char_length(full_name)    > 100;
--   SELECT id FROM public.profiles   WHERE bio IS NOT NULL
--                                      AND char_length(bio)          > 200;
--   SELECT id FROM public.profiles   WHERE phone_number IS NOT NULL
--                                      AND char_length(phone_number) > 20;
--   SELECT id FROM public.listings   WHERE starting_bid  > 25000;
--   SELECT id FROM public.listings   WHERE buy_now_price > 25000;
--   SELECT id FROM public.bids       WHERE amount        > 25000;
-- =============================================================================


-- ===========================================================================
-- 1. listings — text field length constraints
-- ===========================================================================

-- event_name: 120 characters.
-- No real event name approaches this. Blocks oversized input at the DB layer.
alter table public.listings
  add constraint listings_event_name_length
    check (char_length(event_name) <= 120);

-- venue: 120 characters.
-- Same rationale as event_name.
alter table public.listings
  add constraint listings_venue_length
    check (char_length(venue) <= 120);

-- restrictions: 500 characters.
-- Intentionally more generous — seller notes may legitimately be a paragraph.
-- Still caps multi-kilobyte payloads.
alter table public.listings
  add constraint listings_restrictions_length
    check (restrictions is null or char_length(restrictions) <= 500);


-- ===========================================================================
-- 2. profiles — text field length constraints
-- ===========================================================================

-- display_name: 50 characters.
-- Matches the existing client-side maxLength={50} in edit-profile.tsx.
-- No currently-stored value can exceed this (client already enforced it).
alter table public.profiles
  add constraint profiles_display_name_length
    check (display_name is null or char_length(display_name) <= 50);

-- full_name: 100 characters.
-- Original auth-derived field. Generous for hyphenated / multi-part names.
alter table public.profiles
  add constraint profiles_full_name_length
    check (full_name is null or char_length(full_name) <= 100);

-- bio: 200 characters.
-- Matches the existing client-side maxLength={200} and the live char counter
-- in edit-profile.tsx. No currently-stored value should exceed this.
alter table public.profiles
  add constraint profiles_bio_length
    check (bio is null or char_length(bio) <= 200);

-- phone_number: 20 characters.
-- The longest valid E.164 international number is 15 digits + '+' and
-- formatting chars, giving ~18 chars at most. 20 provides a safe margin.
-- Note: the original 'phone' column (added in the initial schema) is unused
-- by the app; this constraint targets only the live 'phone_number' column.
alter table public.profiles
  add constraint profiles_phone_number_length
    check (phone_number is null or char_length(phone_number) <= 20);


-- ===========================================================================
-- 3. listings — numeric upper bounds
-- ===========================================================================
-- All listing prices are stored in DOLLARS (not cents).
-- $25,000 covers any realistic ticket or hospitality package on this platform.
-- The validate_and_apply_bid trigger already enforces bid > current_bid,
-- so the upper bound on bids (section 4) is independently enforced.

-- starting_bid: must be > 0 (existing) AND <= 25000.
alter table public.listings
  add constraint listings_starting_bid_upper
    check (starting_bid <= 25000);

-- buy_now_price: must be > 0 (existing) AND <= 25000.
-- NULL is permitted (buy_now not enabled) — the IS NULL branch of the
-- existing constraint already covers that; this constraint adds the upper cap.
alter table public.listings
  add constraint listings_buy_now_price_upper
    check (buy_now_price is null or buy_now_price <= 25000);


-- ===========================================================================
-- 4. bids — numeric upper bound
-- ===========================================================================
-- bids.amount is also stored in DOLLARS.
-- Cap matches listing price caps: a bid cannot meaningfully exceed the
-- maximum possible listing price.

alter table public.bids
  add constraint bids_amount_upper
    check (amount <= 25000);
