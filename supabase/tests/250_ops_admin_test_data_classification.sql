-- 250_ops_admin_test_data_classification.sql — pgTAP for migration 180 (A, 2026-10-26; registry 180 / pgTAP 250)
-- Spec: F's docs/dashboards/ADMIN_TEST_DATA_CLASSIFICATION.md §2 (lineage), §3 (surfaces), §4 (server contract).
-- RED on 157 alone (every new signature missing), GREEN on 157 + 180. Fixtures are explicit rows under tap._f250(n);
-- nothing here relies on seed_core's livemode values. Readers are called as the platform admin with an aal2 claim.
-- Negative controls (runner, not in-suite): M1 every payment not test; M2 list_orders ignores the switch; M3 NULL livemode = test;
-- M4 hidden listing with a live payment = test — each must fail the pins named in A/evidence/dc1/mutants.out.
BEGIN;
SELECT plan(157);
SELECT tap.seed_core();
CREATE FUNCTION tap._f250(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT ('00000000-0000-4250-8000-' || lpad(n::text, 12, '0'))::uuid $$;
CREATE FUNCTION tap._aal2_250() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._admin250() RETURNS void LANGUAGE plpgsql AS $f$ begin perform tap.login(tap.admin_user()); perform tap._aal2_250(); end $f$;
CREATE FUNCTION tap._ids250(j jsonb) RETURNS uuid[] LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(array_agg(coalesce(x->>'id', x->>'payment_id', x->>'transfer_id')::uuid), '{}'::uuid[]) FROM jsonb_array_elements(j) x $$;   -- order rows carry payment_id, not id
CREATE FUNCTION tap._flags250(j jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT coalesce(string_agg(DISTINCT coalesce(x->>'is_test','<missing>'), ',' ORDER BY coalesce(x->>'is_test','<missing>')), '') FROM jsonb_array_elements(j) x $$;
CREATE FUNCTION tap._cnt250_open_test_cases() RETURNS int LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT count(*)::int FROM ops."case" k WHERE k.status NOT IN ('resolved','dismissed') AND ops.is_test_case(k.id) $$;
CREATE FUNCTION tap._cnt250_test_payments() RETURNS int LANGUAGE sql STABLE SECURITY DEFINER AS $$ SELECT count(*)::int FROM public.payments p WHERE p.stripe_livemode = false $$;
-- strip rule (CONTRACTS/180 header): replacement blocks -> their original line; addition blocks -> nothing; the switch parameter -> gone
CREATE FUNCTION tap._strip250(sig text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT md5(replace(replace(regexp_replace(regexp_replace(pg_get_functiondef(sig::regprocedure),
           '  -- 180 begin \(replaces: ([^\n]*?)\)\n.*?\n  -- 180 end\n', '\1' || E'\n', 'g'),
           '  -- 180 begin\n.*?\n  -- 180 end\n', '', 'g'),
         '(p_include_test boolean DEFAULT false)', '()'), ', p_include_test boolean DEFAULT false', '')) $$;
GRANT USAGE ON SCHEMA tap TO PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA tap TO PUBLIC;

-- ── fixtures (postgres, no claims: the listing triggers trust this path) ──
-- L1 hidden, no payments → test · L2 hidden + LIVE payment → NOT test · L3 hidden + test payment → test
-- L4 not hidden, only test payments → test · L5 not hidden, NULL-livemode payment → NOT test · L6 no marker, no payments → NOT test
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
SELECT tap._f250(n), tap.seller(), 'Fixture 250-' || n, 'Club 250', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
       100, true, 200, 24, now() - interval '2 days', CASE WHEN n <= 3 THEN now() - interval '1 day' ELSE now() + interval '1 day' END, 100,
       'fixtures/250.jpg', CASE WHEN n <= 3 THEN 'ended' ELSE 'active' END
  FROM generate_series(1, 8) n;   -- L7 (unhidden; only a test payment) -> test; L8 (unhidden; a live payment) -> NOT test
INSERT INTO public.listing_visibility (listing_id, hidden_reason, hidden_by) SELECT tap._f250(n), 'pgTAP 250 fixture', 'pgTAP 250' FROM generate_series(1, 3) n;
-- payments: P11 live on L2 · P12 test on L3 · P13 test on L4 · P14 NULL livemode on L5 · P17 test + total mismatch on L7 · P18 live + total mismatch on L8 (one succeeded payment per listing)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, stripe_livemode) VALUES
  (tap._f250(11), tap._f250(2), tap.buyer(), tap.seller(), 9091, 909, 909, 10000, 'pi_250_11', 'succeeded', 'buy_now', now() - interval '3 days', now() - interval '3 days', true),
  (tap._f250(12), tap._f250(3), tap.buyer(), tap.seller(), 9091, 909, 909, 10000, 'pi_250_12', 'succeeded', 'buy_now', now() - interval '3 days', now() - interval '3 days', false),
  (tap._f250(13), tap._f250(4), tap.buyer(), tap.seller(), 9091, 909, 909, 10000, 'pi_250_13', 'succeeded', 'buy_now', now() - interval '3 days', now() - interval '3 days', false),
  (tap._f250(14), tap._f250(5), tap.buyer(), tap.seller(), 9091, 909, 909, 10000, 'pi_250_14', 'succeeded', 'buy_now', now() - interval '3 days', now() - interval '3 days', NULL),
  (tap._f250(17), tap._f250(7), tap.buyer(), tap.seller(), 9091, 909, 909, 9999,  'pi_250_17', 'succeeded', 'buy_now', now() - interval '3 days', now() - interval '3 days', false),
  (tap._f250(18), tap._f250(8), tap.buyer(), tap.seller(), 9091, 909, 909, 9999,  'pi_250_18', 'succeeded', 'buy_now', now() - interval '3 days', now() - interval '3 days', true);
-- transfers: T21 on P11 (live) · T22 on P12 (test), both pending and due within 6 h
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, created_at, expires_at) VALUES
  (tap._f250(21), tap._f250(2), tap._f250(11), tap.seller(), tap.buyer(), 'mobile_transfer', 'pending', now() - interval '2 days', now() + interval '3 hours'),
  (tap._f250(22), tap._f250(3), tap._f250(12), tap.seller(), tap.buyer(), 'mobile_transfer', 'pending', now() - interval '2 days', now() + interval '3 hours');
-- cases: K31 on P12 (test, open) · K32 on P14 (real, open) · K33 subject none (open, never test) · K34 on L2 (hidden+live, not test, open) · K35 on T22 (test, resolved)
INSERT INTO ops."case" (id, case_type, subject_kind, subject_id, subject_ref, dedupe_key, title, status, priority, detected_at, resolved_at) VALUES
  (tap._f250(31), 'paid_unsettled', 'payment',  tap._f250(12), NULL, 'pgtap250:k31', 'K31 test payment',  'open',     'p1', now() - interval '1 hour', NULL),
  (tap._f250(32), 'paid_unsettled', 'payment',  tap._f250(14), NULL, 'pgtap250:k32', 'K32 null livemode', 'open',     'p2', now() - interval '1 hour', NULL),
  (tap._f250(33), 'paid_unsettled', 'none',     NULL, 'job:pgtap250', 'pgtap250:k33', 'K33 no subject',    'open',     'p3', now() - interval '1 hour', NULL),
  (tap._f250(34), 'paid_unsettled', 'listing',  tap._f250(2),  NULL, 'pgtap250:k34', 'K34 hidden live',   'open',     'p3', now() - interval '1 hour', NULL),
  (tap._f250(35), 'paid_unsettled', 'transfer', tap._f250(22), NULL, 'pgtap250:k35', 'K35 test transfer', 'resolved', 'p4', now() - interval '1 hour', now());
-- reports: R41 on L1 (test) · R42 on L6 (not test) · R43 on a user (never test)
INSERT INTO public.reports (id, reporter_id, target_type, target_id, reason, status) VALUES
  (tap._f250(41), tap.other_user(), 'listing', tap._f250(1), 'other', 'pending'),
  (tap._f250(42), tap.other_user(), 'listing', tap._f250(6), 'other', 'pending'),
  (tap._f250(43), tap.other_user(), 'user',    tap.buyer(),  'other', 'pending');

-- ── R1 shape: signatures, predicates, ACLs, strip-equivalence ──

SELECT ok(to_regprocedure('ops.today(boolean)') IS NOT NULL, 'R1.1 today: 180 signature ops.today(boolean) exists');
SELECT ok(to_regprocedure('ops.list_cases(jsonb,text,integer,boolean)') IS NOT NULL, 'R1.1 list_cases: 180 signature ops.list_cases(jsonb,text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.case_detail(uuid)') IS NOT NULL, 'R1.1 case_detail: 180 signature ops.case_detail(uuid) exists');
SELECT ok(to_regprocedure('ops.list_orders(jsonb,text,integer,boolean)') IS NOT NULL, 'R1.1 list_orders: 180 signature ops.list_orders(jsonb,text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.order_detail(uuid)') IS NOT NULL, 'R1.1 order_detail: 180 signature ops.order_detail(uuid) exists');
SELECT ok(to_regprocedure('ops.order_timeline(uuid)') IS NOT NULL, 'R1.1 order_timeline: 180 signature ops.order_timeline(uuid) exists');
SELECT ok(to_regprocedure('ops.money_overview(date,date,boolean)') IS NOT NULL, 'R1.1 money_overview: 180 signature ops.money_overview(date,date,boolean) exists');
SELECT ok(to_regprocedure('ops.list_payouts(jsonb,text,integer,boolean)') IS NOT NULL, 'R1.1 list_payouts: 180 signature ops.list_payouts(jsonb,text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.reconciliation_queue(text,integer,boolean)') IS NOT NULL, 'R1.1 reconciliation_queue: 180 signature ops.reconciliation_queue(text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.list_listings(jsonb,text,integer,boolean)') IS NOT NULL, 'R1.1 list_listings: 180 signature ops.list_listings(jsonb,text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.listing_detail(uuid)') IS NOT NULL, 'R1.1 listing_detail: 180 signature ops.listing_detail(uuid) exists');
SELECT ok(to_regprocedure('ops.list_reports(jsonb,text,integer,boolean)') IS NOT NULL, 'R1.1 list_reports: 180 signature ops.list_reports(jsonb,text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.search(text,integer,boolean)') IS NOT NULL, 'R1.1 search: 180 signature ops.search(text,integer,boolean) exists');
SELECT ok(to_regprocedure('ops.today()') IS NULL, 'R1.2 predecessor signature ops.today() is gone');
SELECT ok(to_regprocedure('ops.list_cases(jsonb,text,integer)') IS NULL, 'R1.2 predecessor signature ops.list_cases(jsonb,text,integer) is gone');
SELECT ok(to_regprocedure('ops.list_orders(jsonb,text,integer)') IS NULL, 'R1.2 predecessor signature ops.list_orders(jsonb,text,integer) is gone');
SELECT ok(to_regprocedure('ops.money_overview(date,date)') IS NULL, 'R1.2 predecessor signature ops.money_overview(date,date) is gone');
SELECT ok(to_regprocedure('ops.list_payouts(jsonb,text,integer)') IS NULL, 'R1.2 predecessor signature ops.list_payouts(jsonb,text,integer) is gone');
SELECT ok(to_regprocedure('ops.reconciliation_queue(text,integer)') IS NULL, 'R1.2 predecessor signature ops.reconciliation_queue(text,integer) is gone');
SELECT ok(to_regprocedure('ops.list_listings(jsonb,text,integer)') IS NULL, 'R1.2 predecessor signature ops.list_listings(jsonb,text,integer) is gone');
SELECT ok(to_regprocedure('ops.list_reports(jsonb,text,integer)') IS NULL, 'R1.2 predecessor signature ops.list_reports(jsonb,text,integer) is gone');
SELECT ok(to_regprocedure('ops.search(text,integer)') IS NULL, 'R1.2 predecessor signature ops.search(text,integer) is gone');
SELECT ok(to_regprocedure('ops.is_test_payment(uuid)') IS NOT NULL, 'R1.3 predicate ops.is_test_payment(uuid) exists');
SELECT ok(to_regprocedure('ops.is_test_transfer(uuid)') IS NOT NULL, 'R1.3 predicate ops.is_test_transfer(uuid) exists');
SELECT ok(to_regprocedure('ops.is_test_listing(uuid)') IS NOT NULL, 'R1.3 predicate ops.is_test_listing(uuid) exists');
SELECT ok(to_regprocedure('ops.is_test_report(uuid)') IS NOT NULL, 'R1.3 predicate ops.is_test_report(uuid) exists');
SELECT ok(to_regprocedure('ops.is_test_case(uuid)') IS NOT NULL, 'R1.3 predicate ops.is_test_case(uuid) exists');
SELECT ok(to_regprocedure('ops.is_test_subject(text,uuid)') IS NOT NULL, 'R1.3 predicate ops.is_test_subject(text,uuid) exists');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.today(boolean)'::regprocedure), true, 'R1.4 today: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.list_cases(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.4 list_cases: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.case_detail(uuid)'::regprocedure), true, 'R1.4 case_detail: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.list_orders(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.4 list_orders: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.order_detail(uuid)'::regprocedure), true, 'R1.4 order_detail: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.order_timeline(uuid)'::regprocedure), true, 'R1.4 order_timeline: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.money_overview(date,date,boolean)'::regprocedure), true, 'R1.4 money_overview: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.list_payouts(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.4 list_payouts: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.reconciliation_queue(text,integer,boolean)'::regprocedure), true, 'R1.4 reconciliation_queue: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.list_listings(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.4 list_listings: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.listing_detail(uuid)'::regprocedure), true, 'R1.4 listing_detail: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.list_reports(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.4 list_reports: authenticated-only EXECUTE');
SELECT is((SELECT coalesce(array_to_string(proacl, ','), '<default>') ~ 'authenticated=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'anon=X' AND coalesce(array_to_string(proacl, ','), '') !~ 'service_role=X' AND coalesce(array_to_string(proacl, ','), '') !~ '^=X' FROM pg_proc WHERE oid = 'ops.search(text,integer,boolean)'::regprocedure), true, 'R1.4 search: authenticated-only EXECUTE');
SELECT is((SELECT has_function_privilege('authenticated', 'ops.is_test_payment(uuid)'::regprocedure, 'EXECUTE') OR has_function_privilege('anon', 'ops.is_test_payment(uuid)'::regprocedure, 'EXECUTE')), false, 'R1.5 ops.is_test_payment(uuid): no client EXECUTE (definer-internal)');
SELECT is((SELECT has_function_privilege('authenticated', 'ops.is_test_transfer(uuid)'::regprocedure, 'EXECUTE') OR has_function_privilege('anon', 'ops.is_test_transfer(uuid)'::regprocedure, 'EXECUTE')), false, 'R1.5 ops.is_test_transfer(uuid): no client EXECUTE (definer-internal)');
SELECT is((SELECT has_function_privilege('authenticated', 'ops.is_test_listing(uuid)'::regprocedure, 'EXECUTE') OR has_function_privilege('anon', 'ops.is_test_listing(uuid)'::regprocedure, 'EXECUTE')), false, 'R1.5 ops.is_test_listing(uuid): no client EXECUTE (definer-internal)');
SELECT is((SELECT has_function_privilege('authenticated', 'ops.is_test_report(uuid)'::regprocedure, 'EXECUTE') OR has_function_privilege('anon', 'ops.is_test_report(uuid)'::regprocedure, 'EXECUTE')), false, 'R1.5 ops.is_test_report(uuid): no client EXECUTE (definer-internal)');
SELECT is((SELECT has_function_privilege('authenticated', 'ops.is_test_case(uuid)'::regprocedure, 'EXECUTE') OR has_function_privilege('anon', 'ops.is_test_case(uuid)'::regprocedure, 'EXECUTE')), false, 'R1.5 ops.is_test_case(uuid): no client EXECUTE (definer-internal)');
SELECT is((SELECT has_function_privilege('authenticated', 'ops.is_test_subject(text,uuid)'::regprocedure, 'EXECUTE') OR has_function_privilege('anon', 'ops.is_test_subject(text,uuid)'::regprocedure, 'EXECUTE')), false, 'R1.5 ops.is_test_subject(text,uuid): no client EXECUTE (definer-internal)');
SELECT is(tap._strip250('ops.today(boolean)'), 'da8289c36caf73d76b929eb14feaaaad', 'R1.6 today: minus the 180 blocks and the switch = predecessor byte for byte (md5 da8289c3)');
SELECT is(tap._strip250('ops.list_cases(jsonb,text,integer,boolean)'), '96177f2e77b88b58a05f8527a568550a', 'R1.6 list_cases: minus the 180 blocks and the switch = predecessor byte for byte (md5 96177f2e)');
SELECT is(tap._strip250('ops.case_detail(uuid)'), '5f6645a0d52d0e58948ff9ae0defdd94', 'R1.6 case_detail: minus the 180 blocks and the switch = predecessor byte for byte (md5 5f6645a0)');
SELECT is(tap._strip250('ops.list_orders(jsonb,text,integer,boolean)'), '0a66c02369840233f5ce485dcbb4e386', 'R1.6 list_orders: minus the 180 blocks and the switch = predecessor byte for byte (md5 0a66c023)');
SELECT is(tap._strip250('ops.order_detail(uuid)'), '4358f577291f84b25986b8904b38ab36', 'R1.6 order_detail: minus the 180 blocks and the switch = predecessor byte for byte (md5 4358f577)');
SELECT is(tap._strip250('ops.order_timeline(uuid)'), '1ac47ec8cf7c04459b3307611f8d5c13', 'R1.6 order_timeline: minus the 180 blocks and the switch = predecessor byte for byte (md5 1ac47ec8)');
SELECT ok(tap._strip250('ops.money_overview(date,date,boolean)') IN ('2903d6deb3a9949cb317ba9d05b860ab', '895b0fa065d7fbdae1cd192d92219b0e'), 'R1.6 money_overview: minus the 180 blocks and the switch = the environment''s predecessor (production 118 body 2903d6de, or the CI chain''s parked 126 body)');
SELECT is(tap._strip250('ops.list_payouts(jsonb,text,integer,boolean)'), 'c1c81cc8c2f526f2a48bc5b3f060197e', 'R1.6 list_payouts: minus the 180 blocks and the switch = predecessor byte for byte (md5 c1c81cc8)');
SELECT is(tap._strip250('ops.reconciliation_queue(text,integer,boolean)'), 'b8cfac065c780f07e77e6abf7f8eb129', 'R1.6 reconciliation_queue: minus the 180 blocks and the switch = predecessor byte for byte (md5 b8cfac06)');
SELECT is(tap._strip250('ops.list_listings(jsonb,text,integer,boolean)'), 'a9d99c85727437888a526e6d994b45cb', 'R1.6 list_listings: minus the 180 blocks and the switch = predecessor byte for byte (md5 a9d99c85)');
SELECT is(tap._strip250('ops.listing_detail(uuid)'), '5208dbb14d749db54c2fdd62e50ab800', 'R1.6 listing_detail: minus the 180 blocks and the switch = predecessor byte for byte (md5 5208dbb1)');
SELECT is(tap._strip250('ops.list_reports(jsonb,text,integer,boolean)'), 'b41569ac86023709e7f93d039f06f84b', 'R1.6 list_reports: minus the 180 blocks and the switch = predecessor byte for byte (md5 b41569ac)');
SELECT is(tap._strip250('ops.search(text,integer,boolean)'), '8e99fcbe8f57472a54724f8a6be41eaf', 'R1.6 search: minus the 180 blocks and the switch = predecessor byte for byte (md5 8e99fcbe)');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.today(boolean)'::regprocedure), true, 'R1.7 today: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.list_cases(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.7 list_cases: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.case_detail(uuid)'::regprocedure), true, 'R1.7 case_detail: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.list_orders(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.7 list_orders: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.order_detail(uuid)'::regprocedure), true, 'R1.7 order_detail: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.order_timeline(uuid)'::regprocedure), true, 'R1.7 order_timeline: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.money_overview(date,date,boolean)'::regprocedure), true, 'R1.7 money_overview: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.list_payouts(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.7 list_payouts: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.reconciliation_queue(text,integer,boolean)'::regprocedure), true, 'R1.7 reconciliation_queue: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.list_listings(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.7 list_listings: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.listing_detail(uuid)'::regprocedure), true, 'R1.7 listing_detail: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.list_reports(jsonb,text,integer,boolean)'::regprocedure), true, 'R1.7 list_reports: SECURITY DEFINER, search_path empty');
SELECT is((SELECT prosecdef AND array_to_string(proconfig, ',') = 'search_path=""' FROM pg_proc WHERE oid = 'ops.search(text,integer,boolean)'::regprocedure), true, 'R1.7 search: SECURITY DEFINER, search_path empty');
-- ── R2 untouched neighbours (production md5s read 2026-10-26) ──
SELECT is(md5(pg_get_functiondef('ops.action_detail(uuid)'::regprocedure)), 'd1dcd69386f8f8dce5b03f37c9c3eeb6', 'R2 ops.action_detail(uuid) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.audit_log(text,integer)'::regprocedure)), '2a97902bea2e6e7d96accf1b1f6ce267', 'R2 ops.audit_log(text,integer) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.case_row(ops."case")'::regprocedure)), 'f13730132ee10d8904f086a7ece3167b', 'R2 ops.case_row(ops."case") unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.list_actions(jsonb,text,integer)'::regprocedure)), '16a213ecc0b118f5562969d9ebaab8a6', 'R2 ops.list_actions(jsonb,text,integer) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.list_approvals(text)'::regprocedure)), 'fffda19ae1499d4a89284ff84cf73b94', 'R2 ops.list_approvals(text) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.list_users(jsonb,text,integer)'::regprocedure)), '279198faddd8f8197d8ccb3f81f8c13c', 'R2 ops.list_users(jsonb,text,integer) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.listing_summary(uuid)'::regprocedure)), 'df7ad2ec8405348f40560ae0e9bb3d0f', 'R2 ops.listing_summary(uuid) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.order_row(payments,transfers)'::regprocedure)), '70cf6885643e4eab1370117c65f854de', 'R2 ops.order_row(payments,transfers) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.transfer_json(transfers)'::regprocedure)), '0019c2fd1fdd3712c482fcdcf00a2bff', 'R2 ops.transfer_json(transfers) unchanged by 180');
SELECT is(md5(pg_get_functiondef('ops.user_detail(uuid)'::regprocedure)), '2efcb5a57b60d5b3d28a17d3e37a00b4', 'R2 ops.user_detail(uuid) unchanged by 180');

-- ── R3 predicates on every §2 branch ──
SELECT is(ops.is_test_payment(tap._f250(11)), false, 'R3.1 live payment is not test');
SELECT is(ops.is_test_payment(tap._f250(12)), true,  'R3.2 stripe_livemode=false payment is test');
SELECT is(ops.is_test_payment(tap._f250(14)), false, 'R3.3 NULL livemode = unclassified = NOT test');
SELECT is(ops.is_test_payment(gen_random_uuid()), false, 'R3.4 unknown payment id is not test (never errors)');
SELECT is(ops.is_test_transfer(tap._f250(21)), false, 'R3.5 transfer of a live payment is not test');
SELECT is(ops.is_test_transfer(tap._f250(22)), true,  'R3.6 transfer of a test payment is test');
SELECT is(ops.is_test_listing(tap._f250(1)), true,  'R3.7 hidden listing with no payment is test');
SELECT is(ops.is_test_listing(tap._f250(2)), false, 'R3.8 hidden listing with a LIVE payment is NOT test (real history stays)');
SELECT is(ops.is_test_listing(tap._f250(3)), true,  'R3.9 hidden listing whose only payment is test is test');
SELECT is(ops.is_test_listing(tap._f250(4)), true,  'R3.10 unhidden listing whose every payment is test is test');
SELECT is(ops.is_test_listing(tap._f250(5)), false, 'R3.11 unhidden listing with a NULL-livemode payment is NOT test');
SELECT is(ops.is_test_listing(tap._f250(6)), false, 'R3.12 listing with no marker and no payment is NOT test');
SELECT is(ops.is_test_case(tap._f250(31)), true,  'R3.13 case on a test payment is test');
SELECT is(ops.is_test_case(tap._f250(32)), false, 'R3.14 case on a NULL-livemode payment is not test');
SELECT is(ops.is_test_case(tap._f250(33)), false, 'R3.15 subject-less case is never test');
SELECT is(ops.is_test_case(tap._f250(34)), false, 'R3.16 case on the hidden+live listing is not test');
SELECT is(ops.is_test_case(tap._f250(35)), true,  'R3.17 case on a test transfer is test');
SELECT is(ops.is_test_report(tap._f250(41)), true,  'R3.18 report on a test listing is test');
SELECT is(ops.is_test_report(tap._f250(42)), false, 'R3.19 report on a real listing is not test');
SELECT is(ops.is_test_report(tap._f250(43)), false, 'R3.20 report on a user is never test');
SELECT is(ops.is_test_subject('user', tap.buyer()), false, 'R3.21 users are never classified');
SELECT is(ops.is_test_subject('payment', tap._f250(12)), true, 'R3.22 subject dispatcher: payment');
SELECT is(ops.is_test_subject('listing', tap._f250(2)), false, 'R3.23 subject dispatcher: hidden+live listing');
SELECT is(ops.is_test_subject('setting', gen_random_uuid()), false, 'R3.24 unknown kinds are never test');

-- ── R4 readers (platform admin, aal2) ──
SELECT tap._admin250();
-- cases
SELECT ok(NOT (tap._ids250(ops.list_cases('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(31)]), 'R4.1 list_cases default hides the open test case K31');
SELECT ok(tap._ids250(ops.list_cases('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(32), tap._f250(33), tap._f250(34)], 'R4.2 list_cases default keeps the real, subject-less and hidden+live cases');
SELECT ok(tap._ids250(ops.list_cases('{}'::jsonb, NULL, 50, true) -> 'items') @> ARRAY[tap._f250(31), tap._f250(35)], 'R4.3 list_cases with the switch returns the test cases too');
SELECT is(tap._flags250(ops.list_cases('{}'::jsonb) -> 'items'), 'false', 'R4.4 list_cases default: every item carries is_test=false');
SELECT is((SELECT x ->> 'is_test' FROM jsonb_array_elements(ops.list_cases('{}'::jsonb, NULL, 50, true) -> 'items') x WHERE (x ->> 'id')::uuid = tap._f250(31)), 'true', 'R4.5 K31 is badged is_test=true under the switch');
SELECT is((ops.list_cases('{}'::jsonb) ->> 'count_hint')::int, jsonb_array_length(ops.list_cases('{}'::jsonb) -> 'items'), 'R4.6 list_cases count_hint matches the excluded page (default)');
SELECT is((ops.case_detail(tap._f250(31)) -> 'case' ->> 'is_test'), 'true', 'R4.7 case_detail by URL renders the test case with is_test=true');
SELECT is((ops.case_detail(tap._f250(32)) -> 'case' ->> 'is_test'), 'false', 'R4.8 case_detail real case is_test=false');
-- today
SELECT ok(NOT (tap._ids250(ops.today() -> 'attention') @> ARRAY[tap._f250(31)]) AND tap._ids250(ops.today() -> 'attention') @> ARRAY[tap._f250(32)], 'R4.9 today attention hides K31, keeps K32');
SELECT is((ops.today() -> 'test_excluded' ->> 'open_cases')::int, (ops.today(true) -> 'metrics' ->> 'open_cases')::int - (ops.today() -> 'metrics' ->> 'open_cases')::int, 'R4.10 today.test_excluded.open_cases equals the open cases the switch adds back');
SELECT is((ops.today(true) -> 'test_excluded' ->> 'open_cases')::int, 0, 'R4.11 today(true).test_excluded is zero');
SELECT ok((ops.today(true) -> 'metrics' ->> 'open_cases')::int - (ops.today() -> 'metrics' ->> 'open_cases')::int >= 1 AND tap._cnt250_open_test_cases() = (ops.today() -> 'test_excluded' ->> 'open_cases')::int, 'R4.12 the switch adds back at least K31; test_excluded.open_cases = the open test cases (K35 resolved is not counted)');
SELECT is((ops.today(true) -> 'metrics' ->> 'transfers_due_6h')::int - (ops.today() -> 'metrics' ->> 'transfers_due_6h')::int, 1, 'R4.13 transfers_due_6h excludes T22 (test) by default');
SELECT ok((ops.today() -> 'test_excluded' ->> 'payments')::int >= 3 AND (ops.today() -> 'test_excluded' ->> 'payments')::int = tap._cnt250_test_payments(), 'R4.14 today.test_excluded.payments counts every stripe_livemode=false payment (at least P12, P13, P17)');
-- orders
SELECT ok(NOT (tap._ids250(ops.list_orders('{}'::jsonb) -> 'items') && ARRAY[tap._f250(12), tap._f250(13), tap._f250(17)]), 'R4.15 list_orders default hides the three test payments');
SELECT ok(tap._ids250(ops.list_orders('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(11), tap._f250(14), tap._f250(18)], 'R4.16 list_orders default keeps live and NULL-livemode payments');
SELECT ok(tap._ids250(ops.list_orders('{}'::jsonb, NULL, 50, true) -> 'items') @> ARRAY[tap._f250(12), tap._f250(13), tap._f250(17)], 'R4.17 list_orders with the switch returns the test payments');
SELECT is(tap._flags250(ops.list_orders('{}'::jsonb) -> 'items'), 'false', 'R4.18 list_orders default: every item is_test=false');
SELECT is((ops.list_orders('{}'::jsonb) ->> 'count_hint')::int, jsonb_array_length(ops.list_orders('{}'::jsonb) -> 'items'), 'R4.19 list_orders count_hint matches the excluded page');
SELECT is(ops.order_detail(tap._f250(12)) ->> 'is_test', 'true', 'R4.20 order_detail (157 body + 180) badges a test payment');
SELECT is(ops.order_detail(tap._f250(11)) ->> 'is_test', 'false', 'R4.21 order_detail live payment is_test=false');
SELECT is(ops.order_timeline(tap._f250(12)) ->> 'is_test', 'true', 'R4.22 order_timeline badges a test payment');
SELECT ok(ops.order_detail(tap._f250(12)) ? 'unsettled_money_actions', 'R4.23 order_detail keeps 157''s unsettled_money_actions key');
-- money
SELECT ok((ops.money_overview(NULL, NULL, true) -> 'metrics' -> 'gross_captured_volume' ->> 'count')::int - (ops.money_overview() -> 'metrics' -> 'gross_captured_volume' ->> 'count')::int >= 3, 'R4.24 money_overview default excludes at least the 3 test captures (P12, P13, P17) from gross volume');
SELECT is(ops.money_overview() ->> 'includes_test', 'false', 'R4.25 money_overview default says includes_test=false');
SELECT is(ops.money_overview(NULL, NULL, true) ->> 'includes_test', 'true', 'R4.26 money_overview switch says includes_test=true');
SELECT ok((ops.money_overview() ->> 'test_excluded')::int >= 3 AND (ops.money_overview() ->> 'test_excluded')::int = (ops.money_overview(NULL, NULL, true) -> 'metrics' -> 'gross_captured_volume' ->> 'count')::int - (ops.money_overview() -> 'metrics' -> 'gross_captured_volume' ->> 'count')::int, 'R4.27 money_overview.test_excluded = the captures the switch adds back (at least 3)');
-- payouts
SELECT ok(NOT (tap._ids250(ops.list_payouts('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(22)]) AND tap._ids250(ops.list_payouts('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(21)], 'R4.28 list_payouts default hides T22, keeps T21');
SELECT is((SELECT x ->> 'is_test' FROM jsonb_array_elements(ops.list_payouts('{}'::jsonb, NULL, 50, true) -> 'items') x WHERE (x ->> 'id')::uuid = tap._f250(22)), 'true', 'R4.29 T22 badged under the switch');
SELECT is((ops.list_payouts('{}'::jsonb) ->> 'count_hint')::int, jsonb_array_length(ops.list_payouts('{}'::jsonb) -> 'items'), 'R4.30 list_payouts count_hint matches the excluded page');
-- reconciliation queue (total_mismatch rows P17 test, P18 live)
SELECT ok(NOT (tap._ids250(jsonb_path_query_array(ops.reconciliation_queue(NULL, 50) -> 'items', '$[*] ? (@.kind == "total_mismatch")') ) @> ARRAY[tap._f250(17)]), 'R4.31 reconciliation_queue default hides the test mismatch P17');
SELECT ok((SELECT bool_or((x ->> 'subject_id')::uuid = tap._f250(18)) FROM jsonb_array_elements(ops.reconciliation_queue(NULL, 50) -> 'items') x), 'R4.32 reconciliation_queue default keeps the live mismatch P18');
SELECT ok((SELECT bool_or((x ->> 'subject_id')::uuid = tap._f250(17) AND x ->> 'is_test' = 'true') FROM jsonb_array_elements(ops.reconciliation_queue(NULL, 50, true) -> 'items') x), 'R4.33 reconciliation_queue switch returns P17 badged');
SELECT is((ops.reconciliation_queue(NULL, 50) ->> 'count_hint')::int, jsonb_array_length(ops.reconciliation_queue(NULL, 50) -> 'items'), 'R4.34 reconciliation_queue count_hint matches the excluded page');
-- listings
SELECT ok(NOT (tap._ids250(ops.list_listings('{}'::jsonb) -> 'items') && ARRAY[tap._f250(1), tap._f250(3), tap._f250(4), tap._f250(7)]), 'R4.35 list_listings default hides L1, L3, L4, L7');
SELECT ok(tap._ids250(ops.list_listings('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(2), tap._f250(5), tap._f250(6), tap._f250(8)], 'R4.36 list_listings default keeps L2 (hidden+live), L5, L6, L8');
SELECT ok(tap._ids250(ops.list_listings('{}'::jsonb, NULL, 50, true) -> 'items') @> ARRAY[tap._f250(1), tap._f250(3), tap._f250(4), tap._f250(7)], 'R4.37 list_listings switch returns the test listings');
SELECT is((ops.list_listings(jsonb_build_object('seller_id', tap.seller())) ->> 'count_hint')::int, jsonb_array_length(ops.list_listings(jsonb_build_object('seller_id', tap.seller())) -> 'items'), 'R4.38 list_listings count_hint matches the excluded page (fixture seller)');
SELECT is(ops.listing_detail(tap._f250(1)) ->> 'is_test', 'true', 'R4.39 listing_detail by URL renders L1 with is_test=true');
SELECT is(ops.listing_detail(tap._f250(2)) ->> 'is_test', 'false', 'R4.40 listing_detail L2 is_test=false');
-- reports
SELECT ok(NOT (tap._ids250(ops.list_reports('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(41)]) AND tap._ids250(ops.list_reports('{}'::jsonb) -> 'items') @> ARRAY[tap._f250(42), tap._f250(43)], 'R4.41 list_reports default hides R41, keeps R42 and the user report R43');
SELECT is((SELECT x ->> 'is_test' FROM jsonb_array_elements(ops.list_reports('{}'::jsonb, NULL, 50, true) -> 'items') x WHERE (x ->> 'id')::uuid = tap._f250(41)), 'true', 'R4.42 R41 badged under the switch');
SELECT is((ops.list_reports('{}'::jsonb) ->> 'count_hint')::int, jsonb_array_length(ops.list_reports('{}'::jsonb) -> 'items'), 'R4.43 list_reports count_hint matches the excluded page');
-- search
SELECT ok(NOT (tap._ids250(ops.search('Fixture 250', 20) -> 'hits') && ARRAY[tap._f250(1), tap._f250(3), tap._f250(4), tap._f250(7)]) AND tap._ids250(ops.search('Fixture 250', 20) -> 'hits') @> ARRAY[tap._f250(2), tap._f250(5), tap._f250(6), tap._f250(8)], 'R4.44 search default hides test listings, keeps the rest');
SELECT ok(tap._ids250(ops.search('Fixture 250', 20, true) -> 'hits') @> ARRAY[tap._f250(1), tap._f250(3), tap._f250(4), tap._f250(7)], 'R4.45 search switch returns the test listings');
SELECT is((SELECT x ->> 'is_test' FROM jsonb_array_elements(ops.search('pi_250_12', 20, true) -> 'hits') x WHERE (x ->> 'id')::uuid = tap._f250(12)), 'true', 'R4.46 search by Stripe id badges the test payment');
SELECT is(jsonb_array_length(ops.search('pi_250_12', 20) -> 'hits'), 0, 'R4.47 search default hides the test payment by Stripe id');
-- untouched readers still answer (signature + a call)
SELECT lives_ok($$ SELECT ops.list_approvals() $$, 'R4.48 list_approvals is callable and untouched');
SELECT lives_ok($$ SELECT ops.list_users('{}'::jsonb) $$, 'R4.49 list_users is callable and untouched');
SELECT tap.logout();
SELECT throws_ok($$ SELECT ops.list_cases('{}'::jsonb) $$, '42501', NULL, 'R4.50 the readers still refuse an unauthenticated caller (ops.assert_reader unchanged)');

SELECT * FROM finish();
ROLLBACK;
