-- ============================================================================
-- 040_authenticated_boundaries.sql — a signed-in user cannot touch anyone
-- else's rows, cannot escalate their own, and every state mutation goes
-- through the sanctioned path (guards 000/046, policies 036/038/070, strict
-- identity 059).
-- ORDERING NOTE: listing-guard assertions run BEFORE any bid/RPC succeeds —
-- validate_and_apply_bid() arms app.bypass_listing_guard for the rest of the
-- transaction (no statement-level reset exists for the LISTING guard; only
-- transfers got 056c). tap.reset_guards() is called as extra insurance.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(32);
SELECT tap.seed_core();

-- ── Cross-user writes are invisible no-ops ──────────────────────────────────
SELECT tap.login(tap.buyer());

SELECT is_empty(
  $$ WITH u AS (UPDATE public.listings SET event_name = 'hijack'
                 WHERE seller_id = tap.seller() RETURNING id)
     SELECT * FROM u $$,
  'user A cannot update user B''s listing (RLS row scope)');
SELECT is_empty(
  $$ WITH u AS (UPDATE public.profiles SET display_name = 'hijack'
                 WHERE id = tap.seller() RETURNING id)
     SELECT * FROM u $$,
  'user A cannot update user B''s profile (RLS row scope)');
SELECT results_eq(
  $$ WITH u AS (UPDATE public.profiles SET bio = 'my new bio'
                 WHERE id = tap.buyer() RETURNING id)
     SELECT count(*) FROM u $$,
  ARRAY[1::bigint], 'user CAN update their own profile''s editable columns');

-- ── Self-escalation via profiles columns is a privilege error ───────────────
SELECT throws_ok(
  $$ UPDATE public.profiles SET wallet_balance = 1000000 WHERE id = tap.buyer() $$,
  '42501', NULL, 'cannot self-assign wallet_balance (041 column grants)');
SELECT throws_ok(
  $$ UPDATE public.profiles SET stripe_onboarding_complete = true WHERE id = tap.buyer() $$,
  '42501', NULL, 'cannot self-satisfy the listing gate (stripe_onboarding_complete)');
SELECT throws_ok(
  $$ UPDATE public.profiles SET is_verified_seller = true WHERE id = tap.buyer() $$,
  '42501', NULL, 'cannot self-verify (is_verified_seller)');
SELECT throws_ok(
  $$ INSERT INTO public.profiles (id) VALUES (gen_random_uuid()) $$,
  '42501', NULL, 'cannot insert profile rows directly (handle_new_user only)');

-- ── Listing creation gate (036/038/070) ─────────────────────────────────────
-- buyer: no Stripe onboarding, no verified phone -> policy WITH CHECK fails.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path)
     VALUES (tap.buyer(), 'Nope', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg') $$,
  '42501', NULL, 'listing INSERT denied without onboarding + verified phone');

-- seller: onboarded + phone_confirmed_at set in fixtures -> allowed.
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT lives_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path)
     VALUES (tap.seller(), 'Legit', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg') $$,
  'onboarded seller with verified phone CAN create a listing');

-- ── Listing state guard (000/046) — before any bid arms the bypass GUC ─────
SELECT tap.reset_guards();
SELECT throws_ok(
  $$ UPDATE public.listings SET status = 'sold' WHERE id = tap.listing_a() $$,
  'P0001', 'Cannot directly modify auction state columns. Use the appropriate RPC.',
  'seller cannot flip own listing to sold directly');
SELECT throws_ok(
  $$ UPDATE public.listings SET bid_count = 999, highest_bidder_id = tap.seller()
      WHERE id = tap.listing_a() $$,
  'P0001', 'Cannot directly modify auction state columns. Use the appropriate RPC.',
  'seller cannot rewrite bid_count/highest_bidder_id (046)');
SELECT throws_ok(
  $$ UPDATE public.listings SET seller_id = tap.buyer() WHERE id = tap.listing_a() $$,
  'P0001', 'Cannot change listing owner.',
  'listing identity columns immutable');
SELECT results_eq(
  $$ WITH u AS (UPDATE public.listings SET event_name = 'Renamed Event A'
                 WHERE id = tap.listing_a() RETURNING id)
     SELECT count(*) FROM u $$,
  ARRAY[1::bigint], 'benign metadata update on own listing still works');

-- ── DB-1: proof_status may only be changed by Snatch It review ─────────────
-- These exercise the REAL `UPDATE public.listings` path so the trigger itself
-- fires; asserting on grants alone would not prove the guard works.
--
-- HARNESS NOTE: pg_prove connects as `postgres`, so session_user is 'postgres'
-- in EVERY test. A guard that trusted session_user unconditionally would make
-- all of these vacuous. The contract these tests pin is therefore:
--   deny whenever request.jwt.claims identifies a non-service caller,
--   REGARDLESS of session_user;
--   allow only the service_role claim, or a genuine claims-less admin session.
-- That is both the correct security boundary and the only one testable here.

-- Negative 1: owner cannot self-approve (pending_review -> approved)
SELECT throws_ok(
  $$ UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_a() $$,
  'proof_status can only be changed by Snatch It review',
  'seller cannot self-approve proof_status (pending_review -> approved)');

-- Negative 2: owner cannot clear a rejection (rejected -> approved).
-- Seed the rejected state through the trusted path first.
SELECT tap.logout();
SELECT lives_ok(
  $$ UPDATE public.listings SET proof_status = 'rejected' WHERE id = tap.listing_b() $$,
  'service path may set proof_status = rejected (fixture)');
SELECT tap.login(tap.seller());
SELECT throws_ok(
  $$ UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_b() $$,
  'proof_status can only be changed by Snatch It review',
  'seller cannot clear their own rejection (rejected -> approved) — this is the payout-risk bypass');

-- Negative 3: owner cannot move an approval backwards either
SELECT tap.logout();
SELECT lives_ok(
  $$ UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_d() $$,
  'service path may set proof_status = approved (fixture)');
SELECT tap.login(tap.seller());
SELECT throws_ok(
  $$ UPDATE public.listings SET proof_status = 'rejected' WHERE id = tap.listing_d() $$,
  'proof_status can only be changed by Snatch It review',
  'seller cannot change an approved listing to rejected');

-- Negative 4: forging a service_role claim while holding the authenticated
-- SQL role must NOT grant the service path.
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap.set_claims(tap.seller(), 'service_role');
SELECT throws_ok(
  $$ UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_a() $$,
  'proof_status can only be changed by Snatch It review',
  'a forged service_role claim under the authenticated SQL role is rejected');

-- Negative 5: the legacy singular GUC must not be honoured as an escape hatch.
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT throws_ok(
  $$ UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_a() $$,
  'proof_status can only be changed by Snatch It review',
  'legacy request.jwt.claim.role spoof does not bypass the guard');

-- Negative 6: a non-owner is stopped by RLS before the trigger is reached
-- (0 rows matched, no exception).
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT results_eq(
  $$ WITH u AS (UPDATE public.listings SET proof_status = 'approved'
                 WHERE id = tap.listing_a() RETURNING id)
     SELECT count(*) FROM u $$,
  ARRAY[0::bigint],
  'a non-owner cannot reach another seller listing at all (RLS)');

-- Positive 1: the service_role persona retains the review path
SELECT tap.logout();
SELECT tap.login_service();
SELECT lives_ok(
  $$ UPDATE public.listings SET proof_status = 'approved' WHERE id = tap.listing_a() $$,
  'service_role may perform Snatch It review');

-- Positive 2: a claims-less admin session (operator via SQL editor / cron)
SELECT tap.logout();
SELECT lives_ok(
  $$ UPDATE public.listings SET proof_status = 'rejected' WHERE id = tap.listing_a() $$,
  'claims-less admin session may perform Snatch It review');

-- Positive 3: an ordinary metadata edit that does not touch proof_status is
-- unaffected by the guard.
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT results_eq(
  $$ WITH u AS (UPDATE public.listings SET venue = 'Club A Renamed'
                 WHERE id = tap.listing_a() RETURNING id)
     SELECT count(*) FROM u $$,
  ARRAY[1::bigint],
  'metadata update that leaves proof_status alone still succeeds');

-- ── Bids: sanctioned path + immutability ────────────────────────────────────
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ INSERT INTO public.bids (listing_id, bidder_id, amount)
     VALUES (tap.listing_a(), tap.buyer(), 150) $$,
  'buyer can place a valid bid');
SELECT is((SELECT current_bid FROM public.listings WHERE id = tap.listing_a()),
  150, 'bid trigger synced listings.current_bid');
SELECT throws_ok(
  $$ INSERT INTO public.bids (listing_id, bidder_id, amount)
     VALUES (tap.listing_b(), tap.other_user(), 160) $$,
  '42501', NULL, 'cannot place a bid as somebody else (WITH CHECK bidder_id)');
SELECT throws_ok(
  $$ INSERT INTO public.bids (listing_id, bidder_id, amount)
     VALUES (tap.listing_c(), tap.buyer(), 160) $$,
  'P0001', 'This listing has been cancelled.',
  'cannot bid on a cancelled listing (047)');
SELECT is_empty(
  $$ WITH u AS (UPDATE public.bids SET amount = 1
                 WHERE bidder_id = tap.buyer() RETURNING id)
     SELECT * FROM u $$,
  'bids are client-immutable: UPDATE matches zero rows (no policy)');
SELECT is_empty(
  $$ WITH d AS (DELETE FROM public.bids
                 WHERE bidder_id = tap.buyer() RETURNING id)
     SELECT * FROM d $$,
  'bids are client-immutable: DELETE matches zero rows (no policy)');

-- ── Sanctioned RPCs still enforce actor + business rules ────────────────────
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT throws_ok(
  $$ SELECT public.reserve_buy_now(tap.listing_b(), tap.seller(), 10) $$,
  'P0001', 'You cannot purchase your own listing.',
  'self-purchase rejected (018)');
-- 059 strict identity: p_user_id cannot impersonate when a session exists.
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.seller()) $$,
  'P0001', 'Only the seller can mark a transfer as sent.',
  'authenticated caller cannot spoof identity via p_user_id (auth.uid() wins, 059)');

SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
