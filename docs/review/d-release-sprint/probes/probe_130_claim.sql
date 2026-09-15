-- D attacks on 130 claim_checkout_supersede @ 927b46d. Local DB; BEGIN…ROLLBACK.
-- Staleness is simulated by back-dating supersede_claimed_at as postgres (the clock cannot be advanced in one transaction).
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO anon, authenticated, service_role;
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, created_at, stripe_livemode) VALUES
 ('d1300000-0000-4000-8000-000000000001', tap.listing_c(), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_d130_p1', 'pending', 'buy_now', now(), false),
 ('d1300000-0000-4000-8000-000000000002', tap.listing_c(), tap.buyer(), tap.seller(), 30000, 3000, 3000, 33000, 'pi_d130_p2', 'pending', 'buy_now', now(), false);
SELECT tap.login_service();
-- Q1 stale claim on a DIFFERENT row of the group
INSERT INTO o(k,v) SELECT 'Q1a.claim_p1', public.claim_checkout_supersede(tap.listing_c(), tap.buyer(), 'd1300000-0000-4000-8000-000000000001')::text;
INSERT INTO o(k,v) SELECT 'Q1b.fresh_p1_blocks_p2', (public.claim_checkout_supersede(tap.listing_c(), tap.buyer(), 'd1300000-0000-4000-8000-000000000002') ->> 'reason');
SELECT tap.logout();
UPDATE public.payments SET supersede_claimed_at = now() - interval '121 seconds' WHERE id = 'd1300000-0000-4000-8000-000000000001';
SELECT tap.login_service();
INSERT INTO o(k,v) SELECT 'Q1c.stale_p1_allows_p2', (public.claim_checkout_supersede(tap.listing_c(), tap.buyer(), 'd1300000-0000-4000-8000-000000000002') ->> 'reason');
-- the stale holder's late release cannot free P2's claim
INSERT INTO o(k,v) SELECT 'Q1d.late_release_p1', public.release_checkout_supersede('d1300000-0000-4000-8000-000000000001', (SELECT supersede_claim_token FROM public.payments WHERE id='d1300000-0000-4000-8000-000000000001'))::text;
INSERT INTO o(k,v) SELECT 'Q1e.p2_still_claimed', (SELECT (supersede_claim_token IS NOT NULL)::text FROM public.payments WHERE id='d1300000-0000-4000-8000-000000000002');
-- Q2 same-row reclaim after 120 s; old token's release refused
SELECT tap.logout();
UPDATE public.payments SET supersede_claimed_at = now() - interval '121 seconds' WHERE id = 'd1300000-0000-4000-8000-000000000002';
CREATE TEMP TABLE t_old AS SELECT supersede_claim_token AS tok FROM public.payments WHERE id='d1300000-0000-4000-8000-000000000002'; GRANT SELECT ON t_old TO service_role;
SELECT tap.login_service();
INSERT INTO o(k,v) SELECT 'Q2a.reclaim_same_row', (public.claim_checkout_supersede(tap.listing_c(), tap.buyer(), 'd1300000-0000-4000-8000-000000000002') ->> 'reason');
INSERT INTO o(k,v) SELECT 'Q2b.old_token_release', (public.release_checkout_supersede('d1300000-0000-4000-8000-000000000002', (SELECT tok FROM t_old)) ->> 'reason');
-- Q3 a fresh claim held on a row that LEAVES 'pending' (e.g. the webhook settles it) — does it still block the group?
SELECT tap.logout();
UPDATE public.payments SET supersede_claim_token = gen_random_uuid(), supersede_claimed_at = now() WHERE id = 'd1300000-0000-4000-8000-000000000001';
UPDATE public.payments SET supersede_claim_token = NULL, supersede_claimed_at = NULL WHERE id = 'd1300000-0000-4000-8000-000000000002';
SELECT set_config('app.bypass_payment_guard','on',true);
SAVEPOINT st; UPDATE public.payments SET status = 'succeeded', paid_at = now() WHERE id = 'd1300000-0000-4000-8000-000000000001'; RELEASE SAVEPOINT st;
INSERT INTO o(k,v) SELECT 'Q3.p1_status_now', status FROM public.payments WHERE id='d1300000-0000-4000-8000-000000000001';
SELECT tap.login_service();
INSERT INTO o(k,v) SELECT 'Q3.claim_p2_while_p1_claim_fresh_but_not_pending', (public.claim_checkout_supersede(tap.listing_c(), tap.buyer(), 'd1300000-0000-4000-8000-000000000002') ->> 'reason');
SELECT tap.logout();
-- Q4 client writability of the claim columns (buyer of the row, anon)
SELECT tap.login(tap.buyer());
WITH u AS (UPDATE public.payments SET supersede_claim_token = gen_random_uuid(), supersede_claimed_at = now() - interval '1 hour' WHERE id = 'd1300000-0000-4000-8000-000000000002' RETURNING 1) INSERT INTO o(k,v) SELECT 'Q4a.buyer_update_rows', count(*)::text FROM u;
INSERT INTO o(k,v) SELECT 'Q4b.buyer_can_read_claim_token', (SELECT (supersede_claim_token IS NOT NULL)::text FROM public.payments WHERE id='d1300000-0000-4000-8000-000000000002');
SAVEPOINT c; SELECT public.claim_checkout_supersede(tap.listing_c(), tap.buyer(), 'd1300000-0000-4000-8000-000000000002'); ROLLBACK TO SAVEPOINT c;
SELECT tap.logout();
SELECT tap.login_anon();
WITH u AS (UPDATE public.payments SET supersede_claimed_at = NULL WHERE id = 'd1300000-0000-4000-8000-000000000002' RETURNING 1) INSERT INTO o(k,v) SELECT 'Q4c.anon_update_rows', count(*)::text FROM u;
SELECT tap.logout();
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
