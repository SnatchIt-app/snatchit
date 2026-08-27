-- ============================================================================
-- 030_anon_boundaries.sql — the publishable anon key can browse and nothing
-- else: every write path and every financial RPC is closed (055c/059/063/067).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(28);
SELECT tap.seed_core();

SELECT tap.login_anon();

-- ── Browse works ────────────────────────────────────────────────────────────
SELECT is((SELECT count(*) FROM public.listings), 4::bigint,
  'anon can browse listings (public read)');
SELECT lives_ok($$ SELECT amount FROM public.bids $$, 'anon can read bids (public read)');

-- ── Table writes all fail ───────────────────────────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, duration_hours,
        ends_at, current_bid, cover_image_path)
     VALUES (tap.seller(), 'X', 'X', 'wynwood', current_date + 1, '20:00',
             'GA', 1, 'email', 50, 24, now() + interval '1 day', 50, 'x.jpg') $$,
  '42501', NULL, 'anon INSERT on listings denied');
SELECT throws_ok(
  $$ INSERT INTO public.bids (listing_id, bidder_id, amount)
     VALUES (tap.listing_a(), tap.buyer(), 150) $$,
  '42501', NULL, 'anon INSERT on bids denied');
SELECT is_empty(
  $$ WITH u AS (UPDATE public.listings SET event_name = 'pwn' RETURNING id)
     SELECT * FROM u $$,
  'anon UPDATE on listings matches zero rows');
SELECT is_empty(
  $$ WITH d AS (DELETE FROM public.listings RETURNING id) SELECT * FROM d $$,
  'anon DELETE on listings matches zero rows');

-- ── Money tables ────────────────────────────────────────────────────────────
SELECT is_empty($$ SELECT id FROM public.payments $$,
  'anon sees zero payments rows (RLS scoping)');
SELECT throws_ok(
  $$ INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, mode)
     VALUES (tap.listing_d(), tap.buyer(), tap.seller(), 1, 0, 1, 'buy_now') $$,
  '42501', NULL, 'anon INSERT on payments denied');
SELECT is_empty($$ SELECT id FROM public.transfers $$,
  'anon sees zero transfers rows (RLS scoping)');
SELECT throws_ok(
  $$ UPDATE public.transfers SET status = 'auto_released' $$,
  '42501', NULL, 'anon UPDATE on transfers denied outright (SELECT-only grant, 055)');
SELECT throws_ok(
  $$ INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, expires_at)
     VALUES (tap.listing_d(), tap.payment_d(), tap.seller(), tap.buyer(), 'email', now()) $$,
  '42501', NULL, 'anon INSERT on transfers denied outright');

-- ── Service tables are invisible ────────────────────────────────────────────
SELECT throws_ok($$ SELECT * FROM public.admin_users $$,           '42501', NULL, 'anon SELECT admin_users denied');
SELECT throws_ok($$ SELECT * FROM public.rate_limits $$,           '42501', NULL, 'anon SELECT rate_limits denied');
SELECT throws_ok($$ SELECT * FROM public.stripe_webhook_events $$, '42501', NULL, 'anon SELECT stripe_webhook_events denied');
SELECT is_empty($$ SELECT * FROM public.disputes $$,               'anon sees zero disputes rows (RLS deny-all)');

-- ── Financial / custody RPC surface: EXECUTE denied to anon ────────────────
SELECT ok(NOT has_function_privilege('anon', 'public.reserve_buy_now(uuid,uuid,integer)', 'EXECUTE'), 'anon: no EXECUTE reserve_buy_now (055c)');
SELECT ok(NOT has_function_privilege('anon', 'public.mark_listing_sold(uuid,uuid)', 'EXECUTE'),       'anon: no EXECUTE mark_listing_sold (055c)');
SELECT ok(NOT has_function_privilege('anon', 'public.complete_auction_payment(uuid,uuid)', 'EXECUTE'),'anon: no EXECUTE complete_auction_payment (055c)');
SELECT ok(NOT has_function_privilege('anon', 'public.cancel_listing(uuid,uuid)', 'EXECUTE'),          'anon: no EXECUTE cancel_listing (055c)');
SELECT ok(NOT has_function_privilege('anon', 'public.release_reservation(uuid,uuid)', 'EXECUTE'),     'anon: no EXECUTE release_reservation (055c)');
SELECT ok(NOT has_function_privilege('anon', 'public.ensure_transfer_exists(uuid,uuid)', 'EXECUTE'),  'anon: no EXECUTE ensure_transfer_exists (059b)');
SELECT ok(NOT has_function_privilege('anon', 'public.mark_transfer_sent(uuid,uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.mark_transfer_sent(uuid,uuid,text)', 'EXECUTE'), 'anon: no EXECUTE mark_transfer_sent (both overloads, 055/055d)');
SELECT ok(NOT has_function_privilege('anon', 'public.confirm_transfer_received(uuid,uuid)', 'EXECUTE'),'anon: no EXECUTE confirm_transfer_received (055)');
SELECT ok(NOT has_function_privilege('anon', 'public.buyer_dispute_transfer(uuid,uuid,text,text,text)', 'EXECUTE'), 'anon: no EXECUTE buyer_dispute_transfer (055)');
SELECT ok(NOT has_function_privilege('anon', 'public.finalize_auction(uuid)', 'EXECUTE'),             'anon: no EXECUTE finalize_auction (063 — price attack closed)');
SELECT ok(NOT has_function_privilege('anon', 'public.check_rate_limit(uuid,text,integer,integer)', 'EXECUTE'), 'anon: no EXECUTE check_rate_limit (063)');
SELECT ok(NOT has_function_privilege('anon', 'public.record_transfer_payout(uuid,text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.freeze_transfer_for_dispute(uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.mark_transfer_reversed(text)', 'EXECUTE'),       'anon: no EXECUTE on any 056a payout writer RPC');

-- Live probe: the sharpest historical hole (identity forgery via p_user_id).
SELECT throws_ok(
  $$ SELECT public.reserve_buy_now(tap.listing_a(), tap.buyer(), 10) $$,
  '42501', NULL, 'anon calling reserve_buy_now with a forged p_user_id is refused at EXECUTE');

SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
