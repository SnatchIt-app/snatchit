-- ============================================================================
-- 186_ops_console_refund_semantics.sql — migration 120.
--   Section A: ops.build_daily_summary never states a refunded AMOUNT: a $100
--     payment marked refunded (as the charge.refunded webhook does after an
--     externally issued $10 partial refund) yields refunded_cents = null,
--     refunded_count = 1, refunded_upper_bound_cents = 10000, certainty
--     'uncertain'. Empty window and mixed statuses.
--   Section B: agreement across the three surfaces — money_overview,
--     metric_snapshot 'money.refunded' and the daily summary — on what is known
--     (count) and what is not (amount).
--   Section C: legacy stored summaries (numeric refunded_cents, no certainty)
--     are normalised on read by ops.latest_summary() and rewritten in place by
--     ops.normalize_summary_body(); the underlying payment is untouched.
--   Section D: grants.
-- ============================================================================
BEGIN;
SELECT plan(27);
SELECT tap.seed_core();

CREATE FUNCTION tap._aal2_186() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- ── Fixture: a $100 payment (total 10000) that the webhook marked refunded
-- after an EXTERNAL $10 partial refund. Locally nothing records the $10.
INSERT INTO auth.users (id, email, aud, role)
VALUES ('88888888-0000-0000-0000-000000000186', 'buyer186@example.test', 'authenticated', 'authenticated') ON CONFLICT DO NOTHING;
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id,
                             status, mode, created_at, paid_at, refunded_at, seller_fee, stripe_livemode, stripe_refund_id)
VALUES ('bbbbbbbb-0000-0000-0000-000000000186', tap.listing_c(), '88888888-0000-0000-0000-000000000186', tap.seller(),
        9091, 909, 10000, 'pi_test_186', 'refunded', 'buy_now', now() - interval '3 hours', now() - interval '3 hours',
        now() - interval '1 hour', 909, false, 're_test_186_partial');

-- ── Section A — build_daily_summary ─────────────────────────────────────────
SELECT tap.login_service();
SELECT ok((ops.run_job('daily_summary','manual') ->> 'status') = 'succeeded', 'A1: daily_summary job runs');
SELECT tap.logout();

CREATE TEMP TABLE memo186 AS
  SELECT body #> '{money,live_24h}' AS live FROM ops.daily_summary ORDER BY summary_date DESC LIMIT 1;

SELECT is((SELECT jsonb_typeof(live -> 'refunded_cents') FROM memo186), 'null',
  'A2: refunded_cents is JSON null — the amount is not stated');
SELECT is((SELECT (live ->> 'refunded_count')::int FROM memo186), 1,
  'A3: refunded_count = 1 (the count of status changes is reliable)');
SELECT is((SELECT (live ->> 'refunded_upper_bound_cents')::int FROM memo186), 10000,
  'A4: refunded_upper_bound_cents = 10000 = Σ payments.total (labelled bound, not $100 refunded)');
SELECT is((SELECT live ->> 'refunded_certainty' FROM memo186), 'uncertain', 'A5: refunded_certainty = uncertain');
SELECT ok((SELECT live ->> 'refunded_note' FROM memo186) ILIKE '%partial%',
  'A6: the note explains partial refunds are indistinguishable locally');
SELECT is((SELECT (live ->> 'captured_cents')::int FROM memo186) >= 10000, true,
  'A7: captured volume still includes the refunded row (captured ≠ refunded)');

-- Mixed statuses: a succeeded and a pending payment in the window change nothing about refunds.
SELECT tap.login_service();
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at, seller_fee, stripe_livemode)
VALUES ('bbbbbbbb-0000-0000-0000-000000000187', tap.listing_d(), '88888888-0000-0000-0000-000000000186', tap.seller(), 1000, 100, 1100, 'pi_test_187', 'pending', 'buy_now', now() - interval '2 hours', NULL, 100, false)
ON CONFLICT DO NOTHING;
SELECT ok((ops.run_job('daily_summary','manual') ->> 'status') = 'succeeded', 'A8: re-run with mixed statuses');
SELECT tap.logout();
SELECT is((SELECT (body #>> '{money,live_24h,refunded_count}')::int FROM ops.daily_summary ORDER BY summary_date DESC LIMIT 1), 1,
  'A9: mixed statuses — refunded_count still 1');
SELECT is((SELECT jsonb_typeof(body #> '{money,live_24h,refunded_cents}') FROM ops.daily_summary ORDER BY summary_date DESC LIMIT 1), 'null',
  'A10: mixed statuses — amount still null');

-- Empty window: build the summary for a date with no payments. The builder is
-- an internal (owner-only) function that run_job wraps, so it is called from
-- the superuser context here, exactly as run_job's body does.
SELECT tap.logout();
SELECT lives_ok($$ SELECT ops.build_daily_summary(date '2001-01-01') $$, 'A11: empty window builds');
SELECT is((SELECT (body #>> '{money,live_24h,refunded_count}')::int FROM ops.daily_summary WHERE summary_date = date '2001-01-01'), 0,
  'A12: empty window — refunded_count 0');
SELECT is((SELECT (body #>> '{money,live_24h,refunded_upper_bound_cents}')::int FROM ops.daily_summary WHERE summary_date = date '2001-01-01'), 0,
  'A13: empty window — upper bound 0');
SELECT is((SELECT jsonb_typeof(body #> '{money,live_24h,refunded_cents}') FROM ops.daily_summary WHERE summary_date = date '2001-01-01'), 'null',
  'A14: empty window — amount is null, never 0 stated as a refunded amount');

-- ── Section B — the three surfaces agree ────────────────────────────────────
SELECT tap.login_service();
SELECT ok((ops.run_job('refresh_metrics','manual') ->> 'status') = 'succeeded', 'B1: refresh_metrics runs');
SELECT tap.logout();
-- Expected count computed as superuser (payments is RLS-hidden from a founder
-- session); relative to the data present, since fixtures may hold refunded rows.
CREATE TABLE tap.memo_186 (k text PRIMARY KEY, v int);
INSERT INTO tap.memo_186 SELECT 'expected_refunded', count(*)::int FROM public.payments
   WHERE status = 'refunded' AND refunded_at >= ((now() at time zone 'UTC')::date - 30)::timestamp at time zone 'UTC';
CREATE FUNCTION tap._fetch186(k text) RETURNS int LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_186 WHERE k=$1 $m$;
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_186();
SELECT is(jsonb_typeof(ops.money_overview(NULL, NULL) #> '{metrics,refunded_volume,value_cents}'), 'null',
  'B2: money_overview.refunded_volume.value_cents is null');
SELECT is((ops.money_overview(NULL, NULL) #>> '{metrics,refunded_volume,count}')::int, tap._fetch186('expected_refunded'),
  'B3: money_overview counts exactly the refunded payments in its window (incl. the $100 one)');
SELECT tap.logout();
SELECT is((SELECT value ->> 'certainty' FROM ops.metric_snapshot WHERE key = 'money.refunded'), 'uncertain',
  'B4: snapshot money.refunded is uncertain');
SELECT is((SELECT jsonb_typeof(value -> 'value_cents') FROM ops.metric_snapshot WHERE key = 'money.refunded'), 'null',
  'B5: snapshot money.refunded.value_cents is null');
SELECT is((SELECT (value #>> '{all_time,upper_bound_cents}')::int FROM ops.metric_snapshot WHERE key = 'money.refunded'),
  (SELECT sum(total)::int FROM public.payments WHERE status = 'refunded'),
  'B6: snapshot all-time upper bound = Σ total over refunded rows (a bound, stated as such)');

-- ── Section C — legacy stored summaries ─────────────────────────────────────
INSERT INTO ops.daily_summary (summary_date, generated_at, body, delivery_state)
VALUES (date '2099-12-31', now(),
        '{"money":{"live_24h":{"captured_cents":20000,"captured_count":2,"refunded_cents":10000,"released_to_connected_cents":0,"refunds_pending_count":0},"currency":"USD","basis":"UTC"}}'::jsonb,
        'portal_only');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2_186();
SELECT is(jsonb_typeof(ops.latest_summary() #> '{body,money,live_24h,refunded_cents}'), 'null',
  'C1: latest_summary() normalises a legacy body: refunded_cents becomes null');
SELECT is((ops.latest_summary() #>> '{body,money,live_24h,refunded_upper_bound_cents}')::int, 10000,
  'C2: ...the legacy figure survives only as the upper bound');
SELECT is(ops.latest_summary() #>> '{body,money,live_24h,legacy_normalized}', 'true',
  'C3: ...and is flagged legacy_normalized');
SELECT tap.logout();
-- the in-place rewrite the migration performs, applied to this row
UPDATE ops.daily_summary SET body = ops.normalize_summary_body(body) WHERE summary_date = date '2099-12-31';
SELECT is((SELECT body #>> '{money,live_24h,refunded_certainty}' FROM ops.daily_summary WHERE summary_date = date '2099-12-31'), 'uncertain',
  'C4: stored legacy row rewritten to the uncertain shape (idempotent normaliser)');
SELECT is((SELECT status FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000186'), 'refunded',
  'C5: the underlying payment row is untouched');

-- ── Section D — grants ──────────────────────────────────────────────────────
SELECT ok(has_function_privilege('authenticated', 'ops.latest_summary()', 'EXECUTE'), 'D1: latest_summary executable by authenticated');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.normalize_summary_body(jsonb)', 'EXECUTE'), 'D2: normaliser is internal');

SELECT finish();
ROLLBACK;
