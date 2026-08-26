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

SELECT plan(22);
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

-- FINDING (open): guard_proof_status() keys on the LEGACY GUC
-- request.jwt.claim.role, which modern PostgREST does not set, and otherwise
-- exempts session_user 'postgres' — for a real client request both checks
-- resolve NULL/false and the trigger falls through, so a seller can set their
-- own proof_status='approved' (self-verification). Pinned as TODO at the
-- grant level; flips green once proof_status is column-revoked or the guard
-- is rewritten against request.jwt.claims.
SELECT todo('guard_proof_status is fail-open under claims-v2; needs column revoke or guard rewrite', 1);
SELECT ok(NOT has_column_privilege('authenticated', 'public.listings', 'proof_status', 'UPDATE'),
  'authenticated should not hold UPDATE on listings.proof_status');

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
