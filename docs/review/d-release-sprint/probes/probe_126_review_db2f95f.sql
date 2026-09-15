-- D-4 independent cases for 126 @ db2f95f. Local rehearsal DB; BEGIN…ROLLBACK; refunds via record_payment_refund.
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
INSERT INTO auth.users (id, email, aud, role) VALUES ('d1260000-0000-4000-8000-0000000000ee','d126r@example.test','authenticated','authenticated') ON CONFLICT DO NOTHING;
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO authenticated;
CREATE FUNCTION pg_temp.pay(p_id uuid, p_pi text, p_total int, p_paid timestamptz) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, seller_fee, stripe_livemode)
  VALUES (p_id, tap.listing_c(), 'd1260000-0000-4000-8000-0000000000ee', tap.seller(), p_total - p_total/11, p_total/11, p_total, p_pi, 'succeeded', 'buy_now', p_paid, p_paid, p_total/11, false) $$;
-- C1 refund + lost chargeback (A8 / R126-1)
SELECT pg_temp.pay('d1260000-0000-4000-8000-0000000000c1','pi_r_c1',10000, now()-interval '2 hours');
SELECT public.record_payment_refund('pi_r_c1','re_r_c1',NULL,10000,'dashboard'); SELECT public.record_payment_refund('pi_r_c1',NULL,'dp_r_c1',10000,'dispute_lost');
INSERT INTO o(k,v) SELECT 'C1.refund+chargeback', ops.refund_facts(now()-interval '1 day', now()+interval '1 minute')::text;
-- C2 partial then amount-less full on another payment (same window) -> expect C1 10000 + C2 10000
SELECT pg_temp.pay('d1260000-0000-4000-8000-0000000000c2','pi_r_c2',10000, now()-interval '2 hours');
SELECT public.record_payment_refund('pi_r_c2','re_r_c2a',NULL,6000,'dashboard'); SELECT public.record_payment_refund('pi_r_c2','re_r_c2b',NULL,NULL,'dashboard');
INSERT INTO o(k,v) SELECT 'C2.window_c1+c2', ops.refund_facts(now()-interval '1 day', now()+interval '1 minute')::text;
-- C3 exact half-open boundary on the ledger's own created_at
INSERT INTO o(k,v) SELECT 'C3.hi_equals_created_at(excluded)', (ops.refund_facts(now()-interval '1 day', (SELECT min(created_at) FROM public.payment_refunds WHERE payment_id='d1260000-0000-4000-8000-0000000000c1')) ->> 'cents');
INSERT INTO o(k,v) SELECT 'C3.hi_plus_1us(included)', (ops.refund_facts(now()-interval '1 day', (SELECT min(created_at) FROM public.payment_refunds WHERE payment_id='d1260000-0000-4000-8000-0000000000c1') + interval '1 microsecond') ->> 'cents');
INSERT INTO o(k,v) SELECT 'C3.lo_equals_created_at(included)', (ops.refund_facts((SELECT min(created_at) FROM public.payment_refunds WHERE payment_id='d1260000-0000-4000-8000-0000000000c1'), now()+interval '1 minute') ->> 'cents');
-- C4 legacy refund (pre-ledger): status refunded, refunded_at in window, amount_refunded_cents NULL, no ledger row
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, refunded_at, seller_fee, stripe_livemode, stripe_refund_id)
VALUES ('d1260000-0000-4000-8000-0000000000c4', tap.listing_c(), 'd1260000-0000-4000-8000-0000000000ee', tap.seller(), 4545, 455, 5000, 'pi_r_c4', 'refunded', 'buy_now', now()-interval '5 hours', now()-interval '5 hours', now()-interval '1 hour', 455, false, 're_r_c4_legacy');
INSERT INTO o(k,v) SELECT 'C4.with_legacy', ops.refund_facts(now()-interval '1 day', now()+interval '1 minute')::text;
-- C5 legacy status-only refund with NULL refunded_at (manual SQL drift) -> visible anywhere?
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, seller_fee, stripe_livemode)
VALUES ('d1260000-0000-4000-8000-0000000000c5', tap.listing_c(), 'd1260000-0000-4000-8000-0000000000ee', tap.seller(), 2727, 273, 3000, 'pi_r_c5', 'refunded', 'buy_now', now()-interval '400 days', now()-interval '400 days', 273, false);
INSERT INTO o(k,v) SELECT 'C5.all_time_with_null_refunded_at', (ops.refund_facts('-infinity'::timestamptz, 'infinity'::timestamptz) - 'note' - 'basis' - 'source')::text;
-- C6 refund in window on a payment paid 40 days ago; money_overview last 7 days, two session time zones
SELECT pg_temp.pay('d1260000-0000-4000-8000-0000000000c6','pi_r_c6',8000, now()-interval '40 days');
SELECT public.record_payment_refund('pi_r_c6','re_r_c6',NULL,2000,'dashboard');
SELECT tap.login(tap.admin_user());
SELECT set_config('request.jwt.claims', (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true);
SET LOCAL TimeZone = 'UTC';
INSERT INTO o(k,v) SELECT 'C6.money_overview_7d_UTC', ((ops.money_overview(((now() at time zone 'UTC')::date - 7), (now() at time zone 'UTC')::date) #> '{metrics,refunded_volume}') - 'definition' - 'note')::text;
SET LOCAL TimeZone = 'Pacific/Kiritimati';
INSERT INTO o(k,v) SELECT 'C6.money_overview_7d_UTC+14', ((ops.money_overview(((now() at time zone 'UTC')::date - 7), (now() at time zone 'UTC')::date) #> '{metrics,refunded_volume}') - 'definition' - 'note')::text;
SELECT tap.logout();
SET LOCAL TimeZone = 'UTC';
-- C7 grants on the internal definition
INSERT INTO o(k,v) SELECT 'C7.refund_facts_execute anon|authenticated|service_role', concat_ws('|', has_function_privilege('anon','ops.refund_facts(timestamptz,timestamptz)','EXECUTE'), has_function_privilege('authenticated','ops.refund_facts(timestamptz,timestamptz)','EXECUTE'), has_function_privilege('service_role','ops.refund_facts(timestamptz,timestamptz)','EXECUTE'));
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
