-- ============================================================================
-- 182_ops_console_read_api.sql — migration 116 (Operating Console read API).
--   Section A: authorization — anon and a non-operator authenticated user get
--     42501; an operator without aal2 is refused with step_up_*.
--   Section B: an operator at aal2 — search, order_detail (masked contact,
--     funds state), order_timeline ordering, keyset pagination, cases, money
--     metrics, job_health availability flag, today() shape, reconciliation
--     detectors, cursor validation, settings gate.
--   Section C: grants — every 116 function is EXECUTE-able by `authenticated`
--     (readers) and by nobody else; anon has EXECUTE on none.
-- ============================================================================
BEGIN;
SELECT plan(45);
SELECT tap.seed_core();

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._aal1() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal1"}'::jsonb)::text, true); end $f$;

-- seed_core() already allowlists tap.admin_user() in public.admin_users; keep it explicit.
INSERT INTO public.admin_users (user_id, label) VALUES (tap.admin_user(), 'TEST ADMIN') ON CONFLICT (user_id) DO NOTHING;

-- ── Section A — authorization ───────────────────────────────────────────────
SELECT tap.login_anon();
SELECT throws_ok($$SELECT ops.search('fixture')$$, '42501', NULL, 'A1: anon cannot call ops.search (42501)');
SELECT throws_ok(format($$SELECT ops.order_detail(%L)$$, tap.payment_a()), '42501', NULL, 'A2: anon cannot call ops.order_detail (42501)');
SELECT tap.logout();

SELECT tap.login(tap.buyer());
SELECT tap._aal2();
SELECT throws_ok($$SELECT ops.search('fixture')$$, '42501', NULL, 'A3: an authenticated non-operator gets 42501 from ops.search');
SELECT throws_ok(format($$SELECT ops.order_detail(%L)$$, tap.payment_a()), '42501', NULL, 'A4: an authenticated non-operator gets 42501 from ops.order_detail');
SELECT tap.logout();

SELECT tap.login(tap.admin_user());
SELECT tap._aal1();
SELECT throws_like($$SELECT ops.search('fixture')$$, '%step_up_required%', 'A5: an operator at aal1 is refused with step_up_required');
SELECT throws_like($$SELECT ops.today()$$, '%step_up_required%', 'A6: today() at aal1 is refused with step_up_required');
SELECT tap.logout();

SELECT tap.login(tap.admin_user());   -- claims carry no aal at all
SELECT throws_like($$SELECT ops.search('fixture')$$, '%step_up_unavailable%', 'A7: an operator whose session carries no aal claim is refused with step_up_unavailable');
SELECT tap.logout();

-- ── Section B — operator at aal2 ────────────────────────────────────────────
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();

SELECT ok(
  EXISTS (SELECT 1 FROM jsonb_array_elements(ops.search('aaaaaaaa-0000') -> 'hits') h
           WHERE h ->> 'kind' = 'listing' AND (h ->> 'id')::uuid = tap.listing_a()),
  'B1: search finds listing A by uuid prefix');
SELECT ok(
  EXISTS (SELECT 1 FROM jsonb_array_elements(ops.search(tap.payment_a()::text) -> 'hits') h
           WHERE h ->> 'kind' = 'payment' AND (h ->> 'id')::uuid = tap.payment_a()),
  'B2: search finds payment A by full id');
SELECT ok(
  EXISTS (SELECT 1 FROM jsonb_array_elements(ops.search('pi_fixture_b') -> 'hits') h
           WHERE h ->> 'kind' = 'payment' AND (h ->> 'id')::uuid = tap.payment_b()),
  'B3: search finds payment B by exact pi_ id');
SELECT ok(
  EXISTS (SELECT 1 FROM jsonb_array_elements(ops.search('buyer@test.local') -> 'hits') h
           WHERE h ->> 'kind' = 'user' AND (h ->> 'id')::uuid = tap.buyer()
             AND h ->> 'sub' NOT LIKE 'buyer@%'),
  'B4: search finds the buyer by exact email and returns only the masked email');

SELECT is((ops.order_detail(tap.payment_a()) -> 'payment' ->> 'id')::uuid, tap.payment_a(), 'B5: order_detail returns the payment');
SELECT is((ops.order_detail(tap.payment_a()) -> 'transfer' ->> 'id')::uuid, tap.transfer_a(), 'B6: order_detail joins transfer A');
SELECT is(ops.order_detail(tap.payment_a()) ->> 'seller_funds_state', 'awaiting_delivery', 'B7: a pending transfer derives seller_funds_state = awaiting_delivery');
SELECT is(ops.order_detail(tap.payment_b()) ->> 'seller_funds_state', 'awaiting_confirmation', 'B8: a seller_sent transfer derives awaiting_confirmation');
SELECT isnt(ops.order_detail(tap.payment_a()) -> 'buyer' ->> 'email_masked', 'buyer@test.local', 'B9: buyer.email_masked is not the raw email');
SELECT ok(ops.order_detail(tap.payment_a()) -> 'buyer' ->> 'email_masked' LIKE '%***@%', 'B10: buyer.email_masked is masked');
SELECT is(ops.order_detail(tap.payment_a()) -> 'buyer' ->> 'phone_masked', '•••0002', 'B11: buyer.phone_masked keeps only the last 4 digits');
SELECT ok(ops.order_detail(tap.payment_a()) -> 'payment' ? 'stripe_client_secret' IS FALSE, 'B12: payment json omits stripe_client_secret');
SELECT is(ops.order_detail(tap.payment_a()) -> 'evidence' -> 'transfer_evidence_path' ->> 'bucket', 'proof-docs', 'B13: evidence paths name their bucket');

SELECT cmp_ok(jsonb_array_length(ops.order_timeline(tap.payment_b()) -> 'events'), '>=', 2, 'B14: order_timeline(B) has at least 2 events');
SELECT ok(
  (SELECT bool_and(at >= coalesce(prev_at, '-infinity'::timestamptz)) FROM (
     SELECT (e ->> 'at')::timestamptz AS at, lag((e ->> 'at')::timestamptz) OVER (ORDER BY n) AS prev_at
       FROM jsonb_array_elements(ops.order_timeline(tap.payment_b()) -> 'events') WITH ORDINALITY AS x(e, n)) s),
  'B15: order_timeline events are sorted ascending by at');

SELECT ok(ops.list_orders('{}', NULL, 1) ->> 'next_cursor' IS NOT NULL, 'B16: list_orders(limit 1) returns a next_cursor');
SELECT isnt(
  ops.list_orders('{}', ops.list_orders('{}', NULL, 1) ->> 'next_cursor', 1) -> 'items' -> 0 ->> 'payment_id',
  ops.list_orders('{}', NULL, 1) -> 'items' -> 0 ->> 'payment_id',
  'B17: the second page returns a different order');
SELECT is((ops.list_orders('{}', NULL, 1) ->> 'count_hint')::int, 3, 'B18: count_hint on the first page counts every fixture payment');
SELECT is(jsonb_array_length(ops.list_orders('{"transfer_status":["seller_sent"]}', NULL, 50) -> 'items'), 1, 'B19: transfer_status filter narrows to transfer B');
SELECT is(ops.list_orders('{"q":"Fixture Event A"}', NULL, 50) -> 'items' -> 0 ->> 'payment_id', tap.payment_a()::text, 'B20: q filter matches event_name');
SELECT throws_like($$SELECT ops.list_orders('{}', 'not-a-cursor', 10)$$, '%malformed cursor%', 'B21: a malformed cursor is rejected');

SELECT is(ops.list_cases('{}', NULL, 50) -> 'items', '[]'::jsonb, 'B22: list_cases is empty with no cases');
SELECT is(jsonb_array_length(ops.list_payouts('{"state":"pending_release"}', NULL, 50) -> 'items'), 1, 'B23: list_payouts(pending_release) is transfer B');

SELECT is(
  (SELECT count(*)::int FROM jsonb_object_keys(ops.money_overview(NULL, NULL) -> 'metrics')), 6,
  'B24: money_overview returns the 6 §5 metrics');
SELECT ok(
  (SELECT bool_and(v ->> 'currency' = 'USD' AND v ? 'definition' AND v ? 'source' AND v ? 'basis')
     FROM jsonb_each(ops.money_overview(NULL, NULL) -> 'metrics') AS m(k, v)),
  'B25: every metric carries currency USD, definition, source and basis');
SELECT is((ops.money_overview(NULL, NULL) -> 'metrics' -> 'gross_captured_volume' ->> 'value_cents')::bigint, 22000::bigint,
  'B26: gross captured volume = the two succeeded fixture payments (2 × 11000)');

SELECT is(jsonb_typeof(ops.job_health() -> 'cron_jobs' -> 'available'), 'boolean', 'B27: job_health reports cron_jobs.available as a boolean');
SELECT is(jsonb_typeof(ops.today() -> 'attention'), 'array', 'B28: today() returns an attention array');
SELECT is((ops.today() -> 'metrics' ->> 'transfers_due_6h')::int, 0, 'B29: today() metrics compute (no transfer is due within 6h)');

-- reconciliation detectors: break an invariant inside the test transaction
-- (as the service path — the operator's authenticated role cannot write payments)
SELECT tap.logout();
UPDATE public.payments SET total = 12345 WHERE id = tap.payment_d();
SELECT tap.login(tap.admin_user());
SELECT tap._aal2();
SELECT ok(
  EXISTS (SELECT 1 FROM jsonb_array_elements(ops.reconciliation_queue(NULL, 50) -> 'items') i
           WHERE i ->> 'kind' = 'total_mismatch' AND (i ->> 'subject_id')::uuid = tap.payment_d()),
  'B30: reconciliation_queue surfaces total <> amount + buyer_fee');

SELECT is(jsonb_array_length(ops.settings()), 9, 'B31: settings() lists the 9 seeded console settings (8 from 115 + actions_enabled from 118) for a platform_admin');
SELECT tap.logout();

-- ── Section C — grants ──────────────────────────────────────────────────────
CREATE TEMP TABLE _f116 (sig text, reader boolean);
INSERT INTO _f116 VALUES
  ('ops.search(text,integer)', true), ('ops.list_orders(jsonb,text,integer)', true), ('ops.order_detail(uuid)', true),
  ('ops.order_timeline(uuid)', true), ('ops.list_cases(jsonb,text,integer)', true), ('ops.case_detail(uuid)', true),
  ('ops.list_users(jsonb,text,integer)', true), ('ops.user_detail(uuid)', true), ('ops.list_listings(jsonb,text,integer)', true),
  ('ops.listing_detail(uuid)', true), ('ops.list_reports(jsonb,text,integer)', true), ('ops.money_overview(date,date)', true),
  ('ops.list_payouts(jsonb,text,integer)', true), ('ops.reconciliation_queue(text,integer)', true), ('ops.job_health()', true),
  ('ops.audit_log(text,integer)', true), ('ops.list_actions(jsonb,text,integer)', true), ('ops.action_detail(uuid)', true),
  ('ops.list_approvals(text)', true), ('ops.today()', true), ('ops.latest_summary()', true), ('ops.settings()', true),
  ('ops.clamp_limit(integer)', false), ('ops.cursor_encode(timestamptz,uuid)', false), ('ops.cursor_decode(text)', false),
  ('ops.uuid_prefix_range(text)', false), ('ops.jsonb_text_array(jsonb)', false), ('ops.actor_label(uuid)', false),
  ('ops.user_summary(uuid)', false), ('ops.listing_summary(uuid)', false), ('ops.payment_json(public.payments)', false),
  ('ops.transfer_json(public.transfers)', false), ('ops.funds_state(public.transfers,public.payments)', false),
  ('ops.order_row(public.payments,public.transfers)', false), ('ops.subject_label(text,uuid,text)', false),
  ('ops.subject_summary(text,uuid,text)', false), ('ops.case_row(ops."case")', false), ('ops.action_row(ops.action)', false);

SELECT is((SELECT count(*)::int FROM _f116 WHERE to_regprocedure(sig) IS NOT NULL), 38, 'C1: all 38 functions of migration 116 exist');
SELECT ok(has_function_privilege('authenticated', 'ops.order_detail(uuid)', 'EXECUTE'), 'C2: authenticated may EXECUTE ops.order_detail');
SELECT ok(NOT has_function_privilege('anon', 'ops.order_detail(uuid)', 'EXECUTE'), 'C3: anon may not EXECUTE ops.order_detail');
SELECT ok((SELECT bool_and(has_function_privilege('authenticated', sig, 'EXECUTE')) FROM _f116 WHERE reader),
  'C4: authenticated has EXECUTE on every reader entry point');
SELECT ok((SELECT bool_and(NOT has_function_privilege('authenticated', sig, 'EXECUTE')) FROM _f116 WHERE NOT reader),
  'C5: authenticated has NO EXECUTE on any internal helper');
SELECT ok((SELECT bool_and(NOT has_function_privilege('anon', sig, 'EXECUTE')) FROM _f116),
  'C6: anon has EXECUTE on none of the 38 functions');
SELECT ok((SELECT bool_and(p.prosecdef AND coalesce(array_to_string(p.proconfig, ','), '') LIKE '%search_path=%')
             FROM _f116 f JOIN pg_proc p ON p.oid = to_regprocedure(f.sig) WHERE f.reader),
  'C7: every reader is SECURITY DEFINER with a pinned search_path');

SELECT * FROM finish();
ROLLBACK;
