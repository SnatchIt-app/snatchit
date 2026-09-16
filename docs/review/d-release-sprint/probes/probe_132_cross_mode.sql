-- D: 132 @ b20ee46 — is a cross-mode double mint reachable for ONE buyer on ONE listing?
-- Group = (listing, buyer, mode); B's addendum asks D to confirm cross-mode is unreachable.
-- Real writers where they exist: client bid INSERT under RLS, reserve_buy_now, auto_finalize_expired_auctions.
-- The clock is advanced by moving ends_at (the only simulated step). BEGIN…ROLLBACK, local rehearsal DB.
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE||': '||SQLERRM; END $$;
GRANT EXECUTE ON FUNCTION pg_temp.try(text) TO authenticated, service_role;
-- an auction listing with Buy Now enabled, no payments, ending in 1 hour (copy of fixture B's shape)
SELECT set_config('app.bypass_listing_guard', 'on', true);
CREATE TEMP TABLE l0 AS SELECT * FROM public.listings WHERE id = tap.listing_b();
UPDATE l0 SET id = 'd1320000-aaaa-4000-8000-000000000001', status = 'active', auction_status = 'active', buy_now_enabled = true,
              buy_now_price = 150, starting_bid = 50, current_bid = 0, winner_user_id = NULL, reserved_by = NULL, reserved_until = NULL,
              ends_at = now() + interval '1 hour';
INSERT INTO public.listings SELECT * FROM l0;
SELECT 'setup.listing', status || '|' || auction_status || '|buy_now=' || buy_now_enabled || '|ends_in_future=' || (ends_at > now()) FROM public.listings WHERE id = 'd1320000-aaaa-4000-8000-000000000001';

-- 1. the buyer bids (client path: INSERT under RLS)
SELECT tap.login(tap.buyer());
SELECT '1.bid', pg_temp.try($q$WITH x AS (INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES ('d1320000-aaaa-4000-8000-000000000001', auth.uid(), 60) RETURNING 1) SELECT count(*)::text FROM x$q$);
-- 2. the same buyer takes a Buy Now hold while the auction is still running
SELECT '2.reserve_buy_now', pg_temp.try($q$SELECT public.reserve_buy_now('d1320000-aaaa-4000-8000-000000000001', auth.uid(), 10)::text$q$);
SELECT tap.logout();
SELECT '2.after_reserve', status || '|reserved_by_buyer=' || (reserved_by = tap.buyer()) || '|live=' || (reserved_until > now()) FROM public.listings WHERE id = 'd1320000-aaaa-4000-8000-000000000001';
-- 3. the auction clock runs out while the hold is live; the finalizer runs
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET ends_at = now() - interval '1 second' WHERE id = 'd1320000-aaaa-4000-8000-000000000001';
SELECT '3.finalize', pg_temp.try($q$SELECT public.auto_finalize_expired_auctions()::text$q$);
SELECT '3.after_finalize', status || '|' || auction_status || '|winner_is_buyer=' || coalesce((winner_user_id = tap.buyer())::text, 'null')
       || '|reserved_by_buyer=' || coalesce((reserved_by = tap.buyer())::text, 'null') || '|live=' || coalesce((reserved_until > now())::text, 'null')
  FROM public.listings WHERE id = 'd1320000-aaaa-4000-8000-000000000001';
-- 4. the edge's entitlement predicates (create-payment-intent @ b20ee46, lines 624-667), evaluated on that state
SELECT '4.buy_now_entitled', (status = 'reserved' AND reserved_by = tap.buyer() AND reserved_until > now() AND buy_now_enabled AND buy_now_price IS NOT NULL)::text
  FROM public.listings WHERE id = 'd1320000-aaaa-4000-8000-000000000001';
SELECT '4.auction_entitled', (status <> 'sold' AND auction_status = 'ended' AND winner_user_id = tap.buyer()
                              AND NOT (reserved_until > now() AND reserved_by IS DISTINCT FROM tap.buyer()))::text
  FROM public.listings WHERE id = 'd1320000-aaaa-4000-8000-000000000001';
-- 5. at 9d82247 the group key is (listing, buyer): the second mode is refused (claim_held).
-- Steps 6-7 are raw SQL that BYPASSES the edge; they show the DB alone does not stop two rows —
-- the edge's cross-mode prior read + 409 is what does (vitest X1-X5). Kept as the shape of F-132-1.
SET LOCAL ROLE service_role;
SELECT '5.claim_buy_now', pg_temp.try($q$SELECT public.claim_checkout_group('d1320000-aaaa-4000-8000-000000000001', '22222222-2222-2222-2222-222222222222', 'buy_now')->>'reason'$q$);
SELECT '5.claim_auction', pg_temp.try($q$SELECT public.claim_checkout_group('d1320000-aaaa-4000-8000-000000000001', '22222222-2222-2222-2222-222222222222', 'auction')->>'reason'$q$);
RESET ROLE;
-- 6. both edges insert their pending rows (distinct intents, distinct amounts): does anything refuse the second?
SELECT '6.pending_buy_now', pg_temp.try($q$WITH x AS (INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode)
  VALUES ('d1320000-aaaa-4000-8000-000000000001', tap.buyer(), tap.seller(), 15000, 1500, 1500, 16500, 'pi_d132_bn', 'pending', 'buy_now', false) RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT '6.pending_auction', pg_temp.try($q$WITH x AS (INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, stripe_livemode)
  VALUES ('d1320000-aaaa-4000-8000-000000000001', tap.buyer(), tap.seller(), 6000, 600, 600, 6600, 'pi_d132_au', 'pending', 'auction', false) RETURNING 1) SELECT count(*)::text FROM x$q$);
-- 7. sequential variant (no concurrency): with the buy_now attempt pending, the auction request's prior-payments read
--    (filtered by listing, buyer, mode) sees nothing to reuse or supersede → fresh mint
SELECT '7.auction_prior_read_rows', count(*)::text FROM public.payments
 WHERE listing_id = 'd1320000-aaaa-4000-8000-000000000001' AND buyer_id = tap.buyer() AND mode = 'auction' AND stripe_payment_intent_id <> 'pi_d132_au';
ROLLBACK;
