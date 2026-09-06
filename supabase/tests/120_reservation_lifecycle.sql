-- ============================================================================
-- 120_reservation_lifecycle.sql — Package 1 (PAYMENTS_RELIABILITY_2026-09).
--
-- Pins the ratified reservation + settlement contract introduced by migration
-- 20260906100000_checkout_reservation_authority.sql:
--
--   * reserve_buy_now: TTL is server-owned (10 min max, p_minutes only accepted
--     for wire compatibility); a holder re-reserving keeps its window; one live
--     reservation per buyer; check_rate_limit(caller,'reserve_buy_now',20,600)
--     fail-closed.
--   * mark_listing_sold / complete_auction_payment: require a bound SUCCEEDED
--     payment for auth.uid() and delegate to the settlement core. Unpaid
--     callers can no longer strand inventory (investigation F03).
--   * settle_listing_for_payment(uuid): the ONE listing-settlement core. Money
--     wins — a succeeded payment settles a lapsed reservation or a foreign
--     live Buy-Now hold; sold-to-another / cancelled / non-winner outcomes are
--     'unfulfillable' with NO side effects; zero client EXECUTE.
--   * complete_auction_payment refuses while another buyer's Buy-Now hold is
--     live (ratified decision 3).
--
-- Every fixture lives and dies inside this file's transaction. now() is
-- frozen for the transaction, so "lapsed" windows are set explicitly and the
-- no-extension assertion shortens the window first to make it observable.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(49);

SELECT tap.seed_core();

-- ── File-local fixtures (as postgres) ───────────────────────────────────────
-- 101-103: plain Buy-Now listings for the reservation assertions.
-- 104: Buy-Now listing held LIVE by other_user; buyer holds a succeeded payment.
-- 105: Buy-Now listing whose reservation by buyer has LAPSED; succeeded payment.
-- 106: ended auction, winner buyer, NO payment.
-- 107: ended auction, winner buyer, succeeded auction payment.
-- 108: ended auction, winner buyer, succeeded payment, other_user holds LIVE.
-- 109: already SOLD to a refunded payment (its transfer exists); a second
--      succeeded payment by other_user arrives late.
-- 110: ended auction, winner buyer, other_user holds LIVE and has a succeeded
--      auction payment although NOT the winner.
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time,
   ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
   buy_now_price, duration_hours, starts_at, ends_at, current_bid,
   cover_image_path, auction_status)
SELECT ('aaaaaaaa-0000-0000-0000-0000000001' || n)::uuid, tap.seller(),
       'Fixture 120-' || n, 'Club ' || n, 'wynwood', current_date + 30, '21:00',
       'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(),
       now() + interval '24 hours', 100, 'fixtures/120-' || n || '.jpg', 'active'
  FROM unnest(ARRAY['01','02','03','04','05','06','07','08','09','10']) AS n;

SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status='reserved', reserved_by=tap.other_user(), reserved_until=now() + interval '5 minutes'
 WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000104','aaaaaaaa-0000-0000-0000-000000000108','aaaaaaaa-0000-0000-0000-000000000110');
UPDATE public.listings SET status='reserved', reserved_by=tap.buyer(), reserved_until=now() - interval '1 minute'
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000105';
UPDATE public.listings SET auction_status='ended', winner_user_id=tap.buyer(), winning_bid_amount=150, ends_at=now() - interval '1 minute'
 WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000106','aaaaaaaa-0000-0000-0000-000000000107',
              'aaaaaaaa-0000-0000-0000-000000000108','aaaaaaaa-0000-0000-0000-000000000110');
UPDATE public.listings SET status='sold', auction_status='sold', sold_at=now()
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000109';
SELECT tap.reset_guards();

INSERT INTO public.payments
  (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
   stripe_payment_intent_id, status, mode, paid_at)
VALUES
  ('bbbbbbbb-0000-0000-0000-000000000104', 'aaaaaaaa-0000-0000-0000-000000000104', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_120_104',  'succeeded', 'buy_now', now()),
  ('bbbbbbbb-0000-0000-0000-000000000105', 'aaaaaaaa-0000-0000-0000-000000000105', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_120_105',  'succeeded', 'buy_now', now()),
  ('bbbbbbbb-0000-0000-0000-000000000107', 'aaaaaaaa-0000-0000-0000-000000000107', tap.buyer(),      tap.seller(), 15000, 1500, 1500, 16500, 'pi_120_107',  'succeeded', 'auction', now()),
  ('bbbbbbbb-0000-0000-0000-000000000108', 'aaaaaaaa-0000-0000-0000-000000000108', tap.buyer(),      tap.seller(), 15000, 1500, 1500, 16500, 'pi_120_108',  'succeeded', 'auction', now()),
  ('bbbbbbbb-0000-0000-0000-000000000191', 'aaaaaaaa-0000-0000-0000-000000000109', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_120_109a', 'refunded',  'buy_now', now()),
  ('bbbbbbbb-0000-0000-0000-000000000192', 'aaaaaaaa-0000-0000-0000-000000000109', tap.other_user(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_120_109b', 'succeeded', 'buy_now', now()),
  ('bbbbbbbb-0000-0000-0000-000000000110', 'aaaaaaaa-0000-0000-0000-000000000110', tap.other_user(), tap.seller(), 15000, 1500, 1500, 16500, 'pi_120_110',  'succeeded', 'auction', now()),
  ('bbbbbbbb-0000-0000-0000-000000000103', tap.listing_c(),                        tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_120_c',    'succeeded', 'buy_now', now());

INSERT INTO public.transfers
  (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
VALUES
  ('cccccccc-0000-0000-0000-000000000109', 'aaaaaaaa-0000-0000-0000-000000000109',
   'bbbbbbbb-0000-0000-0000-000000000191', tap.seller(), tap.buyer(), 'mobile_transfer', 'pending', now() + interval '24 hours');

-- ── A. reserve_buy_now — server-owned TTL, no extension, one hold per buyer, rate limit ──
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ SELECT public.reserve_buy_now('aaaaaaaa-0000-0000-0000-000000000101', tap.buyer(), 525600) $$,
  'A1 reserve with p_minutes=525600 (one year) is accepted for wire compatibility');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.buyer() AND reserved_until <= now() + interval '10 minutes'
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101'),
  'A2 ...but the effective window is never more than 10 minutes (TTL is server-owned)');

SELECT tap.logout();
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET reserved_until = now() + interval '3 minutes' WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101';
SELECT tap.reset_guards();
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ SELECT public.reserve_buy_now('aaaaaaaa-0000-0000-0000-000000000101', tap.buyer(), 10) $$,
  'A3 the holder re-reserving its own live hold succeeds');
SELECT is(
  (SELECT reserved_until FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101'),
  now() + interval '3 minutes',
  'A4 ...and keeps the EXISTING window — re-reserving does not extend it');

SELECT lives_ok(
  $$ SELECT public.reserve_buy_now('aaaaaaaa-0000-0000-0000-000000000102', tap.buyer(), 10) $$,
  'A5 the same buyer reserves a second listing');
SELECT ok(
  (SELECT status = 'active' AND reserved_by IS NULL AND reserved_until IS NULL
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101'),
  'A6 ...which releases the first hold (one live reservation per buyer)');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.buyer() AND reserved_until = now() + interval '10 minutes'
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000102'),
  'A7 ...and the second listing is held for exactly 10 minutes');

SELECT tap.logout();
INSERT INTO public.rate_limits (user_id, action, window_start, counter)
VALUES (tap.buyer(), 'reserve_buy_now', now(), 19)
ON CONFLICT (user_id, action) DO UPDATE SET counter = EXCLUDED.counter, window_start = EXCLUDED.window_start;
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ SELECT public.reserve_buy_now('aaaaaaaa-0000-0000-0000-000000000103', tap.buyer(), 10) $$,
  'A8 the 20th reservation attempt inside the 10-minute window is allowed');
SELECT tap.logout();
UPDATE public.rate_limits SET counter = 20, window_start = now() WHERE user_id = tap.buyer() AND action = 'reserve_buy_now';
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT public.reserve_buy_now('aaaaaaaa-0000-0000-0000-000000000101', tap.buyer(), 10) $$,
  'P0001', 'Too many reservation attempts. Please try again later.',
  'A9 the 21st attempt is refused by check_rate_limit(caller, reserve_buy_now, 20, 600)');
SELECT ok(
  (SELECT status = 'active' AND reserved_by IS NULL FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000101')
  AND (SELECT status = 'reserved' AND reserved_by = tap.buyer() FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000103'),
  'A10 a refused attempt changes nothing: target stays free, the existing hold stays');
SELECT tap.logout();
DELETE FROM public.rate_limits WHERE user_id = tap.buyer() AND action = 'reserve_buy_now';

-- ── B. the wrappers require a bound SUCCEEDED payment ───────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT public.mark_listing_sold('aaaaaaaa-0000-0000-0000-000000000103', tap.buyer()) $$,
  'P0001', 'No verified payment found for this listing. Payment must be confirmed before the sale can complete.',
  'B1 the live reservation holder WITHOUT a succeeded payment cannot mark the listing sold (F03)');
SELECT is(
  (SELECT status FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000103'),
  'reserved', 'B2 ...and the listing is untouched');
SELECT throws_ok(
  $$ SELECT public.complete_auction_payment('aaaaaaaa-0000-0000-0000-000000000106', tap.buyer()) $$,
  'P0001', 'No verified payment found for this listing. Payment must be confirmed before the sale can complete.',
  'B3 the auction winner WITHOUT a succeeded payment cannot complete the sale');
SELECT is(
  (SELECT status FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000106'),
  'active', 'B4 ...and the listing is untouched');

-- ── C. settlement through the core: sold + ONE transfer, idempotent ─────────
SELECT lives_ok(
  $$ SELECT public.complete_auction_payment('aaaaaaaa-0000-0000-0000-000000000107', tap.buyer()) $$,
  'C1 the winner with a succeeded auction payment completes the sale');
SELECT ok(
  (SELECT status = 'sold' AND auction_status = 'sold' AND sold_at IS NOT NULL
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000107'),
  'C2 ...listing is sold');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000107'),
  1::bigint, 'C3 ...exactly one transfer row was created');
SELECT ok(
  (SELECT payment_id = 'bbbbbbbb-0000-0000-0000-000000000107' AND seller_id = tap.seller() AND buyer_id = tap.buyer()
      AND status = 'pending' AND transfer_method = 'mobile_transfer' AND expires_at = now() + interval '24 hours'
     FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000107'),
  'C4 ...bound to the payment, parties from the payment row, pending, 24h expiry');
SELECT lives_ok(
  $$ SELECT public.complete_auction_payment('aaaaaaaa-0000-0000-0000-000000000107', tap.buyer()) $$,
  'C5 calling the wrapper again is a no-op (client retry / webhook-then-client)');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000107'),
  1::bigint, 'C6 ...still one transfer');
SELECT tap.logout();
SELECT is(
  public.settle_listing_for_payment('bbbbbbbb-0000-0000-0000-000000000107'),
  'already_settled', 'C7 the core reports already_settled for the listing''s own succeeded payment');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000107'),
  1::bigint, 'C8 ...and still one transfer');
SELECT is(
  (SELECT status FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000107'),
  'succeeded', 'C9 the core never writes payments');

-- ── D. money wins (ratified decision 1) ─────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ SELECT public.mark_listing_sold('aaaaaaaa-0000-0000-0000-000000000105', tap.buyer()) $$,
  'D1 a succeeded payment settles a LAPSED reservation (no "reservation has expired" side effect)');
SELECT ok(
  (SELECT status = 'sold' AND auction_status = 'sold' AND reserved_by IS NULL AND reserved_until IS NULL
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000105'),
  'D2 ...listing sold, reservation columns cleared');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000105'),
  1::bigint, 'D3 ...transfer created');
SELECT lives_ok(
  $$ SELECT public.mark_listing_sold('aaaaaaaa-0000-0000-0000-000000000104', tap.buyer()) $$,
  'D4 a succeeded Buy-Now payment settles even while ANOTHER buyer holds a live reservation (that holder cannot have paid)');
SELECT ok(
  (SELECT status = 'sold' AND reserved_by IS NULL FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000104'),
  'D5 ...listing sold to the payer');

-- ── E. Buy-Now hold has priority over an auction win while live (decision 3) ─
SELECT throws_ok(
  $$ SELECT public.complete_auction_payment('aaaaaaaa-0000-0000-0000-000000000108', tap.buyer()) $$,
  'P0001', 'This listing is already reserved by another buyer.',
  'E1 the paid winner is refused while another buyer''s Buy-Now hold is live');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.other_user() AND auction_status = 'ended'
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000108'),
  'E2 ...listing state untouched');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000108'),
  0::bigint, 'E3 ...no transfer');
SELECT tap.logout();

-- ── F. the core's terminal outcomes have no side effects ────────────────────
SELECT throws_ok(
  $$ SELECT public.settle_listing_for_payment(tap.payment_d()) $$,
  'P0001', 'Payment has not succeeded; cannot settle the listing.',
  'F1 core refuses a pending payment');
SELECT is(
  public.settle_listing_for_payment('bbbbbbbb-0000-0000-0000-000000000192'),
  'unfulfillable', 'F2 core: listing already sold to a DIFFERENT payment => unfulfillable');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000109'),
  1::bigint, 'F3 ...no second transfer');
SELECT is(
  public.settle_listing_for_payment('bbbbbbbb-0000-0000-0000-000000000103'),
  'unfulfillable', 'F4 core: cancelled listing => unfulfillable');
SELECT ok(
  (SELECT status = 'active' AND auction_status = 'cancelled' FROM public.listings WHERE id = tap.listing_c()),
  'F5 ...cancelled listing untouched');
SELECT is(
  public.settle_listing_for_payment('bbbbbbbb-0000-0000-0000-000000000110'),
  'unfulfillable', 'F6 core: auction payment from a NON-winner => unfulfillable');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.other_user() AND reserved_until = now() + interval '5 minutes'
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000110'),
  'F7 ...the core never expires or releases a reservation as a side effect');
SELECT is(
  (SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000110'),
  0::bigint, 'F8 ...no transfer');

-- ── G. grant posture and shape ──────────────────────────────────────────────
SELECT ok(NOT has_function_privilege('anon', 'public.settle_listing_for_payment(uuid)', 'EXECUTE'),
  'G1 settle_listing_for_payment: no EXECUTE for anon');
SELECT ok(NOT has_function_privilege('authenticated', 'public.settle_listing_for_payment(uuid)', 'EXECUTE'),
  'G2 settle_listing_for_payment: no EXECUTE for authenticated');
SELECT ok(NOT has_function_privilege('service_role', 'public.settle_listing_for_payment(uuid)', 'EXECUTE'),
  'G3 settle_listing_for_payment: no EXECUTE for service_role (reached only through owner functions)');
SELECT ok(
  (SELECT p.proacl IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
     FROM pg_proc p WHERE p.oid = 'public.settle_listing_for_payment(uuid)'::regprocedure),
  'G4 settle_listing_for_payment: explicit ACL, no PUBLIC EXECUTE (not left on the default)');
SELECT ok(
  (SELECT p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres' AND 'search_path=public' = ANY (p.proconfig)
     FROM pg_proc p WHERE p.oid = 'public.settle_listing_for_payment(uuid)'::regprocedure),
  'G5 settle_listing_for_payment: SECURITY DEFINER, owned by postgres, search_path pinned');
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT public.settle_listing_for_payment(tap.payment_a()) $$,
  '42501', NULL, 'G6 authenticated cannot call the core directly');
SELECT tap.logout();
SELECT tap.login_service();
SELECT throws_ok(
  $$ SELECT public.settle_listing_for_payment(tap.payment_a()) $$,
  '42501', NULL, 'G7 service_role cannot call the core directly');
SELECT tap.logout();
SELECT ok(has_function_privilege('authenticated', 'public.mark_listing_sold(uuid,uuid)', 'EXECUTE'),
  'G8 mark_listing_sold still EXECUTE for authenticated (shipped clients)');
SELECT ok(has_function_privilege('authenticated', 'public.complete_auction_payment(uuid,uuid)', 'EXECUTE'),
  'G9 complete_auction_payment still EXECUTE for authenticated');
SELECT ok(has_function_privilege('authenticated', 'public.reserve_buy_now(uuid,uuid,integer)', 'EXECUTE'),
  'G10 reserve_buy_now still EXECUTE for authenticated');

SELECT * FROM finish();
ROLLBACK;
