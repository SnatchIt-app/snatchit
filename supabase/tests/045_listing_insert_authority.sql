-- ============================================================================
-- 045_listing_insert_authority.sql — H-1 (HIGH): public.listings has UPDATE-side
-- column guards and NO INSERT-side guard.
--
-- THE BOUNDARY THIS FILE PINS
-- guard_listing_state_columns() (000/046) and guard_listing_identity_columns()
-- are BEFORE **UPDATE** triggers. `authenticated` holds table-wide INSERT,
-- pg_attribute.attacl is NULL for every column of public.listings, and the
-- INSERT policy "listings: auth insert" constrains only seller_id = auth.uid(),
-- profiles.stripe_onboarding_complete and phone_verified(). So every column the
-- UPDATE guards protect could simply be supplied AT CREATION.
--
-- Why that is not cosmetic: supabase/functions/create-payment-intent/index.ts
-- (auction branch) reads `winner_user_id` and prices the PaymentIntent from
-- `winning_bid_amount ?? current_bid`; app/(tabs)/bids.tsx renders
-- auction_status='ended' AND winner_user_id = me as "WON". A seller could
-- therefore CREATE a listing that names an arbitrary victim as the winner at an
-- arbitrary price, and that victim is presented with a real Stripe checkout.
-- (trg_notify_auction_won_inbox is AFTER UPDATE OF winner_user_id, so the forged
-- row does not even raise an inbox notification — it is silent.)
--
-- proof_status is NOT re-tested here. Migration 071 already made
-- trg_guard_proof_status BEFORE INSERT OR UPDATE and
-- 040_authenticated_boundaries.sql owns its behavioural assertions. This file
-- asserts only that 071's INSERT-side wiring is still in place (#20), so the two
-- guards cannot silently diverge.
--
-- ORDERING NOTE (harness rule 2, supabase/tests/README.md): app.bypass_listing_guard
-- is transaction-local with no statement-level reset for listings. This file
-- calls no RPC, and the one assertion that deliberately arms the GUC (#14)
-- resets it immediately afterwards.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);
SELECT tap.seed_core();

SELECT tap.reset_guards();
SELECT tap.login(tap.seller());

-- ── Server-controlled auction state must not be settable at INSERT ──────────
-- Each of these is an ordinary authenticated seller who fully satisfies
-- "listings: auth insert" (onboarded + phone-verified, seller_id = auth.uid()),
-- inserting a listing for themselves. Nothing but a guard can stop them.

-- #1 — the headline vector: name a victim as the auction winner.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, winner_user_id)
     VALUES (tap.seller(), 'Forged winner', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             tap.buyer()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot name a winner_user_id at INSERT (H-1 headline vector)');

-- #2 — the price the victim would be charged.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, winning_bid_amount)
     VALUES (tap.seller(), 'Forged amount', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg', 900) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp winning_bid_amount at INSERT (prices create-payment-intent)');

-- #3 — current_bid is NOT NULL with no default and the real client DOES send it
-- (src/screens/CreateListingScreen.tsx sets current_bid = startingBidNum), so
-- the boundary is not "never settable" but "must equal starting_bid". Anything
-- else is a fabricated demand signal on a listing with zero bids.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path)
     VALUES (tap.seller(), 'Forged current_bid', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 950, 'x.jpg') $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot open a listing with current_bid <> starting_bid (fake demand)');

-- #4 — bid_count gates edit-after-bids / delete-after-bids client-side (046).
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, bid_count)
     VALUES (tap.seller(), 'Forged bid_count', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg', 37) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp bid_count at INSERT');

-- #5
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, highest_bidder_id)
     VALUES (tap.seller(), 'Forged highest bidder', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             tap.buyer()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp highest_bidder_id at INSERT');

-- #6 — auction_status='ended' is the state complete_auction_payment() requires.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, auction_status)
     VALUES (tap.seller(), 'Forged auction_status', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg', 'ended') $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot create a listing already in auction_status=ended');

-- #7
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, status)
     VALUES (tap.seller(), 'Forged status', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg', 'sold') $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot create a listing already in status=sold');

-- #8 / #9 — the Buy Now reservation pair (reserve_buy_now / release_reservation).
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, reserved_by)
     VALUES (tap.seller(), 'Forged reserved_by', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             tap.buyer()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp reserved_by at INSERT');
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, reserved_until)
     VALUES (tap.seller(), 'Forged reserved_until', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             now() + interval '1 hour') $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp reserved_until at INSERT');

-- #10 / #11 — settlement timestamps written only by mark_listing_sold() /
-- finalize_auction() / auto_finalize_expired_auctions().
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, sold_at)
     VALUES (tap.seller(), 'Forged sold_at', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg', now()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp sold_at at INSERT');
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, ended_at)
     VALUES (tap.seller(), 'Forged ended_at', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg', now()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot stamp ended_at at INSERT');

-- #12 — the identity guard's created_at rule, which only ever applied to UPDATE.
-- A backdated row outranks honest listings in every "newest first" surface.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, created_at)
     VALUES (tap.seller(), 'Backdated', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             now() - interval '400 days') $$,
  'Cannot set server-controlled listing columns on insert.',
  'seller cannot backdate created_at at INSERT (identity guard was UPDATE-only)');

-- #13 — the complete H-1 exploit in one statement, exactly as it would be sent.
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path,
        auction_status, winner_user_id, winning_bid_amount, bid_count, ended_at)
     VALUES (tap.seller(), 'Full exploit', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             'ended', tap.buyer(), 900, 14, now()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'the full forged-auction INSERT (ended + victim winner + price) is rejected');

-- #14 — app.bypass_listing_guard must NOT open the INSERT path. It is a plain
-- transaction-local GUC with no statement-level reset for listings (README
-- harness rule 2), armed by validate_and_apply_bid(), reserve_buy_now(),
-- complete_auction_payment() and friends and left armed for the remainder of the
-- transaction. Honouring it on INSERT would mean "a transaction that has placed
-- a bid may then forge a listing". Zero functions in this database INSERT into
-- public.listings, so nothing legitimate needs it.
SELECT set_config('app.bypass_listing_guard', 'on', true);
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path, winner_user_id)
     VALUES (tap.seller(), 'Bypass attempt', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             tap.buyer()) $$,
  'Cannot set server-controlled listing columns on insert.',
  'app.bypass_listing_guard does NOT open the INSERT path');
SELECT tap.reset_guards();

-- ── The legitimate paths must keep working ─────────────────────────────────
-- Without these three the assertions above would be satisfied by a blanket ban
-- on creating listings, which is not a fix.

-- #15 — the exact shape src/screens/CreateListingScreen.tsx sends.
SELECT lives_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, restrictions, starting_bid,
        buy_now_enabled, buy_now_price, duration_hours, ends_at, current_bid,
        cover_image_path, ticket_platform, proof_of_ownership_path,
        seller_commitment_accepted_at, category)
     VALUES (tap.seller(), 'Legit create', 'Club X', 'wynwood', current_date + 7, '21:00',
             'GA', 2, 'mobile_transfer', 'no re-entry', 60,
             false, NULL, 24, now() + interval '24 hours', 60,
             'covers/x.jpg', 'ticketmaster', 'proof/x.jpg', now(), 'nightlife') $$,
  'ordinary seller listing creation still succeeds (client column set, current_bid = starting_bid)');

-- #16 — the Buy Now variant, so buy_now_price is not accidentally caught.
SELECT lives_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
        buy_now_price, duration_hours, ends_at, current_bid, cover_image_path)
     VALUES (tap.seller(), 'Legit buy-now', 'Club Y', 'brickell', current_date + 7, '22:00',
             'VIP', 1, 'email', 80, true, 200, 12, now() + interval '12 hours', 80,
             'covers/y.jpg') $$,
  'Buy Now listing creation still succeeds (price fields are seller-set by design)');

-- #17 — the trusted server path may seed anything (backfills, future RPCs).
SELECT tap.logout();
SELECT tap.login_service();
SELECT lives_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path,
        auction_status, winner_user_id, winning_bid_amount, bid_count, ended_at)
     VALUES (tap.seller(), 'Service seeded', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             'ended', tap.buyer(), 900, 14, now()) $$,
  'service_role may seed server-controlled columns on INSERT');

-- #18 — the operator path: claims-less postgres (migration, pg_cron, SQL editor).
SELECT tap.logout();
SELECT lives_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path,
        auction_status, winner_user_id, winning_bid_amount, bid_count, created_at)
     VALUES (tap.seller(), 'Operator seeded', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg',
             'ended', tap.buyer(), 900, 14, now() - interval '30 days') $$,
  'claims-less operator session may seed server-controlled columns on INSERT');

-- ── Structural: the wiring itself ──────────────────────────────────────────
-- #19 — the guard must be attached FOR EACH ROW BEFORE INSERT. tgtype bits:
-- 1 = ROW, 2 = BEFORE, 4 = INSERT.
SELECT ok(
  EXISTS (SELECT 1 FROM pg_trigger t
           WHERE t.tgrelid = 'public.listings'::regclass
             AND NOT t.tgisinternal
             AND t.tgname = 'trg_guard_listing_insert'
             AND (t.tgtype & 1) = 1 AND (t.tgtype & 2) = 2 AND (t.tgtype & 4) = 4),
  'trg_guard_listing_insert is attached BEFORE INSERT FOR EACH ROW on public.listings');

-- #20 — 071 owns proof_status; assert only that its INSERT wiring survives, so
-- the two INSERT-side guards on this table cannot silently diverge. Behaviour is
-- tested in 040_authenticated_boundaries.sql and is deliberately not duplicated.
SELECT ok(
  EXISTS (SELECT 1 FROM pg_trigger t
           WHERE t.tgrelid = 'public.listings'::regclass
             AND NOT t.tgisinternal
             AND t.tgname = 'trg_guard_proof_status'
             AND (t.tgtype & 4) = 4 AND (t.tgtype & 16) = 16),
  'trg_guard_proof_status still fires on INSERT as well as UPDATE (071)');

SELECT * FROM finish();
ROLLBACK;
