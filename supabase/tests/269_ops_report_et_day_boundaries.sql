-- ============================================================================
-- 269_ops_report_et_day_boundaries.sql — registry 200 (20261102140000).
-- Admin-report day boundaries in America/New_York (owner decision 2026-11-02; A's decisions):
--   C1 ops.money_overview(date,date)  ET calendar days; default to-date = ET today; basis "ET calendar day";
--   C2 ops.refresh_metrics()          window_30d from ET midnight 30 days back; labels "(ET date)";
--   C3 ops.build_daily_summary(date)  default = the previous full ET day; window [p_date 00:00 ET, next 00:00 ET),
--                                     half-open, 25 h / 23 h on the DST days; basis "ET"; a future p_date is
--                                     refused (invalid_input), ET today (a partial day) is allowed;
--   C4 ops.primary_reconciliation     linked_at (and item (v)'s paid time) on ET calendar days.
-- Anchors that DISCRIMINATE (2026-11-01 05:00Z / 06:00Z do not: both are Nov 1 in UTC and in ET, so they appear
-- only as interior points — the repeated 01:00 hour, EDT then EST):
--   2026-11-01 03:59:59Z = Oct 31 23:59:59 EDT   2026-11-01 04:00:00Z = Nov 1 00:00 EDT
--   2026-11-02 04:59:59Z = Nov 1 23:59:59 EST    2026-11-02 05:00:00Z = Nov 2 00:00 EST    (ET Nov 1 = 25 h)
--   2026-03-08 04:59:59Z = Mar 7 23:59:59 EST    2026-03-08 05:00:00Z = Mar 8 00:00 EST
--   2026-03-09 03:59:59Z = Mar 8 23:59:59 EDT    2026-03-09 04:00:00Z = Mar 9 00:00 EDT    (ET Mar 8 = 23 h)
-- Every boundary case is asserted twice, under SET LOCAL timezone = 'UTC' and = 'America/Los_Angeles': a body that
-- reads the session/server zone, or assumes a UTC server, fails at least one of the two.
-- Money figures are DELTAS against a baseline read before the anchor payments exist. Each anchor payment carries a
-- distinct power-of-two total (a1=1 … a6=32, b1=64 … b4=512), so a delta names exactly which anchors a window holds.
-- A read that follows a write runs as a separate statement. Every call goes through tap._try269 or a helper that
-- catches, so RED (main without 200) and the mutants emit every assertion instead of aborting.
-- Run as the default `postgres` user.
-- ============================================================================
BEGIN;
SELECT plan(35);

CREATE TABLE tap.memo_269 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._store269(p_k text, p_v jsonb) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_269 VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch269(p_k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_269 WHERE k = p_k $m$;
CREATE FUNCTION tap._try269(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN coalesce(r, 'null'::jsonb);
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
CREATE FUNCTION tap._aal269(p text) RETURNS void LANGUAGE plpgsql AS $m$ BEGIN PERFORM set_config('request.jwt.claims',
  (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb || jsonb_build_object('aal', p))::text, true); END $m$;
-- an instant as UTC text, whatever the session zone
CREATE FUNCTION tap._z269(t timestamptz) RETURNS text LANGUAGE sql STABLE AS
$m$ SELECT to_char(t AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') $m$;
-- the label of a 269 fixture payment
CREATE FUNCTION tap._lab269(p uuid) RETURNS text LANGUAGE sql IMMUTABLE AS $m$
  SELECT CASE WHEN p::text LIKE 'a2690000-0000-4000-a000-%' THEN
    CASE right(p::text, 3) WHEN '601' THEN 'L1' WHEN '602' THEN 'L2' WHEN '603' THEN 'L3' WHEN '604' THEN 'L4'
                           WHEN '701' THEN 'a1' WHEN '702' THEN 'a2' WHEN '703' THEN 'a3' WHEN '704' THEN 'a4'
                           WHEN '705' THEN 'a5' WHEN '706' THEN 'a6' WHEN '711' THEN 'b1' WHEN '712' THEN 'b2'
                           WHEN '713' THEN 'b3' WHEN '714' THEN 'b4' WHEN '801' THEN 'c1' WHEN '802' THEN 'c2' END END $m$;
-- C1: the gross-volume figure of one window, as the current (operator) session sees it
CREATE FUNCTION tap._mo269(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql AS $m$
DECLARE r jsonb;
BEGIN
  r := tap._try269(format('SELECT ops.money_overview(%L::date, %L::date)', p_from, p_to));
  IF r ? 'error' THEN RETURN r; END IF;
  RETURN jsonb_build_object('cents', (r #>> '{metrics,gross_captured_volume,value_cents}')::bigint,
                            'count', (r #>> '{metrics,gross_captured_volume,count}')::bigint);
END $m$;
-- stored after − stored baseline (an error on either side is passed through)
CREATE FUNCTION tap._delta269(p_after text, p_base text) RETURNS jsonb LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN tap._fetch269(p_after) ? 'error' THEN tap._fetch269(p_after)
              WHEN tap._fetch269(p_base) ? 'error' THEN tap._fetch269(p_base)
              ELSE jsonb_build_object(
                     'cents', (tap._fetch269(p_after) ->> 'cents')::bigint - (tap._fetch269(p_base) ->> 'cents')::bigint,
                     'count', (tap._fetch269(p_after) ->> 'count')::bigint - (tap._fetch269(p_base) ->> 'count')::bigint) END $m$;
-- C3: build one day's summary (the write), then read the stored row (a separate statement)
CREATE FUNCTION tap._build269(p_date date) RETURNS jsonb LANGUAGE plpgsql AS $m$
DECLARE r jsonb;
BEGIN
  BEGIN
    r := ops.build_daily_summary(p_date);
  EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM);
  END;
  RETURN (SELECT jsonb_build_object(
            'summary_date', s.summary_date,
            'from',  tap._z269((r #>> '{period,from}')::timestamptz),
            'to',    tap._z269((r #>> '{period,to}')::timestamptz),
            'hours', (extract(epoch FROM (r #>> '{period,to}')::timestamptz - (r #>> '{period,from}')::timestamptz) / 3600)::integer,
            'basis', s.body #>> '{money,basis}',
            'cents', (s.body #>> '{money,live_24h,captured_cents}')::bigint,
            'count', (s.body #>> '{money,live_24h,captured_count}')::bigint)
            FROM ops.daily_summary s WHERE s.summary_date = p_date);
END $m$;
CREATE FUNCTION tap._build269_default() RETURNS jsonb LANGUAGE plpgsql AS $m$
DECLARE r jsonb;
BEGIN
  r := ops.build_daily_summary();
  RETURN jsonb_build_object('summary_date', r ->> 'summary_date',
                            'from', tap._z269((r #>> '{period,from}')::timestamptz),
                            'to',   tap._z269((r #>> '{period,to}')::timestamptz));
EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM);
END $m$;
-- C2: refresh the snapshot (the write), then read money.gross_captured (a separate statement)
CREATE FUNCTION tap._refresh269() RETURNS jsonb LANGUAGE plpgsql AS $m$
BEGIN
  BEGIN
    PERFORM ops.refresh_metrics();
  EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM);
  END;
  RETURN (SELECT jsonb_build_object(
            'w_cents', (m.value #>> '{window_30d,cents}')::bigint, 'w_count', (m.value #>> '{window_30d,count}')::bigint,
            'a_cents', (m.value #>> '{all_time,cents}')::bigint,   'a_count', (m.value #>> '{all_time,count}')::bigint)
            FROM ops.metric_snapshot m WHERE m.key = 'money.gross_captured');
END $m$;
CREATE FUNCTION tap._rdelta269(p_after text, p_base text) RETURNS jsonb LANGUAGE sql STABLE AS $m$
  SELECT CASE WHEN tap._fetch269(p_after) ? 'error' THEN tap._fetch269(p_after)
              WHEN tap._fetch269(p_base) ? 'error' THEN tap._fetch269(p_base)
              ELSE (SELECT jsonb_object_agg(k, (tap._fetch269(p_after) ->> k)::bigint - (tap._fetch269(p_base) ->> k)::bigint)
                      FROM unnest(ARRAY['w_cents', 'w_count', 'a_cents', 'a_count']) k) END $m$;
-- C4: which 269 fixtures a window holds — finalized rows (L*) and item (v) paid_never_finalized (a*/b*)
CREATE FUNCTION tap._rec269(p_from date, p_to date) RETURNS jsonb LANGUAGE plpgsql AS $m$
DECLARE r jsonb;
BEGIN
  r := tap._try269(format('SELECT ops.primary_reconciliation(%L::date, %L::date)', p_from, p_to));
  IF r ? 'error' THEN RETURN r; END IF;
  RETURN jsonb_build_object(
    'rows', coalesce((SELECT jsonb_agg(l ORDER BY l) FROM (SELECT tap._lab269((e ->> 'payment_id')::uuid) AS l
                        FROM jsonb_array_elements(r -> 'rows') e) x WHERE l IS NOT NULL), '[]'::jsonb),
    'v',    coalesce((SELECT jsonb_agg(l ORDER BY l) FROM (SELECT tap._lab269((e ->> 'payment_id')::uuid) AS l
                        FROM jsonb_array_elements(r -> 'attention') e WHERE e ->> 'code' = 'paid_never_finalized') x
                       WHERE l IS NOT NULL), '[]'::jsonb),
    'basis', r ->> 'basis');
END $m$;
-- the posture of one function: ET md5, SECURITY DEFINER, search_path '', owner, volatility, exact ACL
CREATE FUNCTION tap._posture269(p_sig text, p_et text[]) RETURNS jsonb LANGUAGE sql STABLE AS $m$
  SELECT coalesce((SELECT jsonb_build_object(
           'et_md5', md5(pg_get_functiondef(p.oid)) = ANY (p_et),
           'definer', p.prosecdef, 'search_path', p.proconfig = ARRAY['search_path=""'],
           'owner', p.proowner::regrole::text, 'volatility', p.provolatile::text,
           'acl', (SELECT string_agg(e, ',' ORDER BY e)
                     FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS e
                             FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) x))
           FROM pg_proc p WHERE p.oid = to_regprocedure(p_sig)), '{"absent":true}'::jsonb) $m$;
GRANT EXECUTE ON FUNCTION tap._store269(text, jsonb), tap._fetch269(text), tap._try269(text), tap._aal269(text),
  tap._z269(timestamptz), tap._lab269(uuid), tap._mo269(date, date), tap._delta269(text, text), tap._rec269(date, date)
  TO authenticated;

-- ── Fixture (synthetic; inserted as postgres) ───────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT u.id::uuid, repeat('0', 32)::uuid, 'authenticated', 'authenticated', u.email, '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM (VALUES ('a2690000-0000-4000-a000-000000000101', 'buyer.269@test.local'),
               ('a2690000-0000-4000-a000-000000000a01', 'admin.269@test.local')) u(id, email)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES ('a2690000-0000-4000-a000-000000000a01', 'platform_admin');
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('a2690000-0000-4000-a000-00000000000a', 'Org 269', 'Org 269', 'active');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('a2690000-0000-4000-a000-0000000000a1', 'a2690000-0000-4000-a000-00000000000a', 'Room 269', 'wynwood', 'approved');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('a2690000-0000-4000-a000-0000000000e1', 'a2690000-0000-4000-a000-0000000000a1', 'a2690000-0000-4000-a000-00000000000a', 'Days 269', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('a2690000-0000-4000-a000-0000000000f1', 'a2690000-0000-4000-a000-0000000000e1', now() + interval '30 days', 'scheduled');
-- C4 finalized rows: four paid orders linked at the four discriminating fall-back anchors (paid_at far outside
-- every window, so they move no money figure)
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key)
SELECT ('a2690000-0000-4000-a000-000000000' || n)::uuid, 'a2690000-0000-4000-a000-000000000101', 'a2690000-0000-4000-a000-0000000000f1',
       'a2690000-0000-4000-a000-00000000000a', 'paid', 'app', 2500, 'USD', 'o-269-' || n
  FROM unnest(ARRAY['301', '302', '303', '304']) n;
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at)
SELECT ('a2690000-0000-4000-a000-000000000' || n)::uuid, NULL, 'a2690000-0000-4000-a000-000000000101', NULL, 2500, 250, 0, 2750,
       'pi_269_' || n, 'succeeded', 'native_primary', timestamptz '2001-01-01 12:00Z', timestamptz '2001-01-01 12:00Z'
  FROM unnest(ARRAY['601', '602', '603', '604']) n;
INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor, linked_at) VALUES
  ('a2690000-0000-4000-a000-000000000601', 'a2690000-0000-4000-a000-000000000301', 2750, timestamptz '2026-11-01 03:59:59Z'),  -- L1 Oct 31 ET
  ('a2690000-0000-4000-a000-000000000602', 'a2690000-0000-4000-a000-000000000302', 2750, timestamptz '2026-11-01 04:00:00Z'),  -- L2 Nov 1 ET
  ('a2690000-0000-4000-a000-000000000603', 'a2690000-0000-4000-a000-000000000303', 2750, timestamptz '2026-11-02 04:59:59Z'),  -- L3 Nov 1 ET
  ('a2690000-0000-4000-a000-000000000604', 'a2690000-0000-4000-a000-000000000304', 2750, timestamptz '2026-11-02 05:00:00Z');  -- L4 Nov 2 ET

-- ── Baselines (before the anchor payments exist) ────────────────────────────
SELECT tap.login('a2690000-0000-4000-a000-000000000a01');
SELECT tap._aal269('aal2');
SET LOCAL timezone = 'UTC';
SELECT tap._store269('mo0_utc_nov1', tap._mo269('2026-11-01', '2026-11-01'));
SELECT tap._store269('mo0_utc_nov2', tap._mo269('2026-11-02', '2026-11-02'));
SELECT tap._store269('mo0_utc_mar8', tap._mo269('2026-03-08', '2026-03-08'));
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('mo0_la_nov1', tap._mo269('2026-11-01', '2026-11-01'));
SELECT tap._store269('mo0_la_nov2', tap._mo269('2026-11-02', '2026-11-02'));
SELECT tap._store269('mo0_la_mar8', tap._mo269('2026-03-08', '2026-03-08'));
SELECT tap.logout();
SET LOCAL timezone = 'UTC';
SELECT tap._store269('bd0_utc_nov1', tap._build269('2026-11-01'));
SELECT tap._store269('bd0_utc_nov2', tap._build269('2026-11-02'));
SELECT tap._store269('bd0_utc_mar8', tap._build269('2026-03-08'));
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('bd0_la_nov1', tap._build269('2026-11-01'));
SELECT tap._store269('bd0_la_nov2', tap._build269('2026-11-02'));
SELECT tap._store269('bd0_la_mar8', tap._build269('2026-03-08'));

-- ── The anchor payments: native_primary, succeeded, never linked (C4 item (v) candidates; C1 / C3 money)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at)
SELECT ('a2690000-0000-4000-a000-000000000' || a.n)::uuid, NULL, 'a2690000-0000-4000-a000-000000000101', NULL, a.cents, 0, 0, a.cents,
       'pi_269_' || a.n, 'succeeded', 'native_primary', a.at, a.at
  FROM (VALUES ('701',   1, timestamptz '2026-11-01 03:59:59Z'),   -- a1 Oct 31 23:59:59 EDT
               ('702',   2, timestamptz '2026-11-01 04:00:00Z'),   -- a2 Nov 1 00:00 EDT
               ('703',   4, timestamptz '2026-11-01 05:00:00Z'),   -- a3 Nov 1 01:00 EDT (interior, non-discriminating)
               ('704',   8, timestamptz '2026-11-01 06:00:00Z'),   -- a4 Nov 1 01:00 EST (interior, non-discriminating)
               ('705',  16, timestamptz '2026-11-02 04:59:59Z'),   -- a5 Nov 1 23:59:59 EST
               ('706',  32, timestamptz '2026-11-02 05:00:00Z'),   -- a6 Nov 2 00:00 EST
               ('711',  64, timestamptz '2026-03-08 04:59:59Z'),   -- b1 Mar 7 23:59:59 EST
               ('712', 128, timestamptz '2026-03-08 05:00:00Z'),   -- b2 Mar 8 00:00 EST
               ('713', 256, timestamptz '2026-03-09 03:59:59Z'),   -- b3 Mar 8 23:59:59 EDT
               ('714', 512, timestamptz '2026-03-09 04:00:00Z')    -- b4 Mar 9 00:00 EDT
       ) a(n, cents, at);

SELECT is(
  (SELECT jsonb_build_object('payments', (SELECT count(*) FROM public.payments WHERE id::text LIKE 'a2690000-%'),
                             'links',    (SELECT count(*) FROM kernel.payment_native WHERE payment_id::text LIKE 'a2690000-%'),
                             'baseline_errors', (SELECT count(*) FROM tap.memo_269 WHERE v ? 'error'))),
  '{"payments":14,"links":4,"baseline_errors":0}'::jsonb,
  'F1: fixtures — 4 linked + 10 anchor payments, 4 payment_native links, every baseline read without error');

-- ── P — posture of the four bodies (pinned ET md5; definer, search_path, owner, volatility and ACL as before)
SELECT is(tap._posture269('ops.money_overview(date,date)', ARRAY['1183b6b0ea1449e4c62daee4e523b908', 'c5ba4b2b061acf43303c47ab27acb390']),
  '{"et_md5":true,"definer":true,"search_path":true,"owner":"postgres","volatility":"s","acl":"authenticated:EXECUTE,postgres:EXECUTE"}'::jsonb,
  'P1: ops.money_overview carries a 200 ET body (production 1183b6b0 or CI c5ba4b2b); STABLE DEFINER, search_path '''', owner postgres, EXECUTE authenticated + postgres');
SELECT is(tap._posture269('ops.refresh_metrics()', ARRAY['765004a913c384e41f6dcff6edad6b60', '58e7ba9d6d621e4cb95ffafe8a18bc6d']),
  '{"et_md5":true,"definer":true,"search_path":true,"owner":"postgres","volatility":"v","acl":"postgres:EXECUTE"}'::jsonb,
  'P2: ops.refresh_metrics carries a 200 ET body (production 765004a9 or CI 58e7ba9d); DEFINER, search_path '''', owner postgres, EXECUTE postgres only');
SELECT is(tap._posture269('ops.build_daily_summary(date)', ARRAY['0a2dbc93f29aad0f17acb620c564a933', '6667c83b04344e9f8b02334b4ac7c7ed']),
  '{"et_md5":true,"definer":true,"search_path":true,"owner":"postgres","volatility":"v","acl":"postgres:EXECUTE"}'::jsonb,
  'P3: ops.build_daily_summary carries a 200 ET body (production 0a2dbc93 or CI 6667c83b); DEFINER, search_path '''', owner postgres, EXECUTE postgres only');
SELECT is(tap._posture269('ops.primary_reconciliation(date,date)', ARRAY['bc708b9977a9b2da5dac908f0f3f87d0']),
  '{"et_md5":true,"definer":true,"search_path":true,"owner":"postgres","volatility":"s","acl":"authenticated:EXECUTE,postgres:EXECUTE"}'::jsonb,
  'P4: ops.primary_reconciliation carries 200''s ET body (bc708b99); STABLE DEFINER, search_path '''', owner postgres, EXECUTE authenticated + postgres');

-- ── C1 — ops.money_overview (operator at aal2)
SELECT tap.login('a2690000-0000-4000-a000-000000000a01');
SELECT tap._aal269('aal2');
SET LOCAL timezone = 'UTC';
SELECT tap._store269('mo1_utc_nov1', tap._mo269('2026-11-01', '2026-11-01'));
SELECT tap._store269('mo1_utc_nov2', tap._mo269('2026-11-02', '2026-11-02'));
SELECT tap._store269('mo1_utc_mar8', tap._mo269('2026-03-08', '2026-03-08'));
SELECT tap._store269('mod_utc', tap._try269('SELECT ops.money_overview(NULL, NULL)'));
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('mo1_la_nov1', tap._mo269('2026-11-01', '2026-11-01'));
SELECT tap._store269('mo1_la_nov2', tap._mo269('2026-11-02', '2026-11-02'));
SELECT tap._store269('mo1_la_mar8', tap._mo269('2026-03-08', '2026-03-08'));
SELECT tap._store269('mod_la', tap._try269('SELECT ops.money_overview(NULL, NULL)'));
SELECT is(tap._delta269('mo1_utc_nov1', 'mo0_utc_nov1'), '{"cents":30,"count":4}'::jsonb,
  'C1.1 [UTC session]: money_overview(Nov 1, Nov 1) = the 25 h ET day — a2 (04:00Z) a3 a4 a5 (Nov 2 04:59:59Z); not a1 (Nov 1 03:59:59Z), not a6 (Nov 2 05:00Z)');
SELECT is(tap._delta269('mo1_la_nov1', 'mo0_la_nov1'), '{"cents":30,"count":4}'::jsonb,
  'C1.1 [Los_Angeles session]: the same ET day, whatever the session zone');
SELECT is(tap._delta269('mo1_utc_nov2', 'mo0_utc_nov2'), '{"cents":32,"count":1}'::jsonb,
  'C1.2 [UTC session]: money_overview(Nov 2, Nov 2) holds a6 (05:00Z = 00:00 EST) and not a5 (04:59:59Z)');
SELECT is(tap._delta269('mo1_la_nov2', 'mo0_la_nov2'), '{"cents":32,"count":1}'::jsonb,
  'C1.2 [Los_Angeles session]: the same');
SELECT is(tap._delta269('mo1_utc_mar8', 'mo0_utc_mar8'), '{"cents":384,"count":2}'::jsonb,
  'C1.3 [UTC session]: money_overview(Mar 8, Mar 8) = the 23 h ET day — b2 (05:00Z) b3 (Mar 9 03:59:59Z); not b1, not b4 (Mar 9 04:00Z)');
SELECT is(tap._delta269('mo1_la_mar8', 'mo0_la_mar8'), '{"cents":384,"count":2}'::jsonb,
  'C1.3 [Los_Angeles session]: the same');
-- (C1.4 compares with the ET date at run time; it can tell a UTC default apart only while the two dates differ,
-- 00:00-04:00/05:00Z. The body itself is pinned by P1, and C1.1-C1.3 catch any UTC lo/hi.)
SELECT is((SELECT jsonb_build_object('error', r -> 'error', 'to', r -> 'to', 'from', r -> 'from') FROM (SELECT tap._fetch269('mod_utc') AS r) x),
  jsonb_build_object('error', NULL, 'to', to_jsonb((now() AT TIME ZONE 'America/New_York')::date),
                     'from', to_jsonb((now() AT TIME ZONE 'America/New_York')::date - 30)),
  'C1.4 [UTC session]: the default range ends on ET today and starts 30 days earlier');
SELECT is((SELECT jsonb_build_object('error', r -> 'error', 'to', r -> 'to', 'from', r -> 'from') FROM (SELECT tap._fetch269('mod_la') AS r) x),
  jsonb_build_object('error', NULL, 'to', to_jsonb((now() AT TIME ZONE 'America/New_York')::date),
                     'from', to_jsonb((now() AT TIME ZONE 'America/New_York')::date - 30)),
  'C1.4 [Los_Angeles session]: the same');
SELECT is((SELECT jsonb_build_object(
             'gross',    r #>> '{metrics,gross_captured_volume,basis}',
             'fees',     r #>> '{metrics,platform_fees_gross,basis}',
             'released', r #>> '{metrics,seller_funds_released,basis}',
             'utc_calendar_day', (SELECT count(*) FROM jsonb_each(r -> 'metrics') m WHERE m.value ->> 'basis' LIKE '%UTC calendar day%'))
             FROM (SELECT tap._fetch269('mod_utc') AS r) x),
  '{"gross":"paid_at, ET calendar day","fees":"paid_at, ET calendar day","released":"payout_released_at, ET calendar day","utc_calendar_day":0}'::jsonb,
  'C1.5: basis labels say "ET calendar day"; no metric says "UTC calendar day"');

-- ── C4 — ops.primary_reconciliation (operator at aal2)
SET LOCAL timezone = 'UTC';
SELECT tap._store269('rc_utc_nov1',  tap._rec269('2026-11-01', '2026-11-01'));
SELECT tap._store269('rc_utc_mar8',  tap._rec269('2026-03-08', '2026-03-08'));
SELECT tap._store269('rc_utc_open1', tap._rec269(NULL, '2026-11-01'));
SELECT tap._store269('rc_utc_open2', tap._rec269('2026-11-02', NULL));
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('rc_la_nov1',  tap._rec269('2026-11-01', '2026-11-01'));
SELECT tap._store269('rc_la_mar8',  tap._rec269('2026-03-08', '2026-03-08'));
SELECT tap._store269('rc_la_open1', tap._rec269(NULL, '2026-11-01'));
SELECT tap._store269('rc_la_open2', tap._rec269('2026-11-02', NULL));
SELECT tap.logout();
SELECT is((SELECT jsonb_build_object('rows', r -> 'rows', 'v', r -> 'v', 'error', r -> 'error') FROM (SELECT tap._fetch269('rc_utc_nov1') AS r) x),
  '{"rows":["L2","L3"],"v":["a2","a3","a4","a5"],"error":null}'::jsonb,
  'C4.1 [UTC session]: primary_reconciliation(Nov 1, Nov 1) — finalized rows linked 04:00Z and Nov 2 04:59:59Z (not 03:59:59Z, not Nov 2 05:00Z); item (v) the same ET day');
SELECT is((SELECT jsonb_build_object('rows', r -> 'rows', 'v', r -> 'v', 'error', r -> 'error') FROM (SELECT tap._fetch269('rc_la_nov1') AS r) x),
  '{"rows":["L2","L3"],"v":["a2","a3","a4","a5"],"error":null}'::jsonb,
  'C4.1 [Los_Angeles session]: the same');
SELECT is((SELECT jsonb_build_object('rows', r -> 'rows', 'v', r -> 'v', 'error', r -> 'error') FROM (SELECT tap._fetch269('rc_utc_mar8') AS r) x),
  '{"rows":[],"v":["b2","b3"],"error":null}'::jsonb,
  'C4.2 [UTC session]: primary_reconciliation(Mar 8, Mar 8) — item (v) holds the 23 h ET day only (b2, b3)');
SELECT is((SELECT jsonb_build_object('rows', r -> 'rows', 'v', r -> 'v', 'error', r -> 'error') FROM (SELECT tap._fetch269('rc_la_mar8') AS r) x),
  '{"rows":[],"v":["b2","b3"],"error":null}'::jsonb,
  'C4.2 [Los_Angeles session]: the same');
SELECT is(jsonb_build_object('to_nov1', tap._fetch269('rc_utc_open1') -> 'rows', 'from_nov2', tap._fetch269('rc_utc_open2') -> 'rows'),
  '{"to_nov1":["L1","L2","L3"],"from_nov2":["L4"]}'::jsonb,
  'C4.3 [UTC session]: an open bound keeps the ET edge on the other side — (NULL, Nov 1) ends at Nov 2 05:00Z, (Nov 2, NULL) starts there');
SELECT is(jsonb_build_object('to_nov1', tap._fetch269('rc_la_open1') -> 'rows', 'from_nov2', tap._fetch269('rc_la_open2') -> 'rows'),
  '{"to_nov1":["L1","L2","L3"],"from_nov2":["L4"]}'::jsonb,
  'C4.3 [Los_Angeles session]: the same');
SELECT is(tap._fetch269('rc_utc_nov1') ->> 'basis', 'kernel.payment_native.linked_at, ET calendar day; a NULL bound is open',
  'C4.4: the basis label says "ET calendar day"');

-- ── C3 — ops.build_daily_summary (internal: called as postgres, as run_job does)
SET LOCAL timezone = 'UTC';
SELECT tap._store269('bd1_utc_nov1', tap._build269('2026-11-01'));
SELECT tap._store269('bd1_utc_nov2', tap._build269('2026-11-02'));
SELECT tap._store269('bd1_utc_mar8', tap._build269('2026-03-08'));
SELECT tap._store269('bdd_utc', tap._build269_default());
SELECT tap._store269('bdf_utc', tap._build269((now() AT TIME ZONE 'America/New_York')::date + 1));
SELECT tap._store269('bdf_utc_rows', to_jsonb((SELECT count(*) FROM ops.daily_summary WHERE summary_date = (now() AT TIME ZONE 'America/New_York')::date + 1)));
SELECT tap._store269('bdt_utc', tap._build269((now() AT TIME ZONE 'America/New_York')::date));
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('bd1_la_nov1', tap._build269('2026-11-01'));
SELECT tap._store269('bd1_la_nov2', tap._build269('2026-11-02'));
SELECT tap._store269('bd1_la_mar8', tap._build269('2026-03-08'));
SELECT tap._store269('bdd_la', tap._build269_default());
SELECT tap._store269('bdf_la', tap._build269((now() AT TIME ZONE 'America/New_York')::date + 1));
SELECT tap._store269('bdf_la_rows', to_jsonb((SELECT count(*) FROM ops.daily_summary WHERE summary_date = (now() AT TIME ZONE 'America/New_York')::date + 1)));
SELECT tap._store269('bdt_la', tap._build269((now() AT TIME ZONE 'America/New_York')::date));
SELECT is((SELECT jsonb_build_object('summary_date', r -> 'summary_date', 'from', r -> 'from', 'to', r -> 'to', 'hours', r -> 'hours', 'basis', r -> 'basis', 'error', r -> 'error')
             FROM (SELECT tap._fetch269('bd1_utc_nov1') AS r) x),
  '{"summary_date":"2026-11-01","from":"2026-11-01T04:00:00Z","to":"2026-11-02T05:00:00Z","hours":25,"basis":"ET","error":null}'::jsonb,
  'C3.1 [UTC session]: build_daily_summary(2026-11-01) covers [Nov 1 04:00Z, Nov 2 05:00Z) — the 25 h ET day; summary_date = p_date; basis ET');
SELECT is((SELECT jsonb_build_object('summary_date', r -> 'summary_date', 'from', r -> 'from', 'to', r -> 'to', 'hours', r -> 'hours', 'basis', r -> 'basis', 'error', r -> 'error')
             FROM (SELECT tap._fetch269('bd1_la_nov1') AS r) x),
  '{"summary_date":"2026-11-01","from":"2026-11-01T04:00:00Z","to":"2026-11-02T05:00:00Z","hours":25,"basis":"ET","error":null}'::jsonb,
  'C3.1 [Los_Angeles session]: the same');
SELECT is((SELECT jsonb_build_object('summary_date', r -> 'summary_date', 'from', r -> 'from', 'to', r -> 'to', 'hours', r -> 'hours', 'error', r -> 'error')
             FROM (SELECT tap._fetch269('bd1_utc_mar8') AS r) x),
  '{"summary_date":"2026-03-08","from":"2026-03-08T05:00:00Z","to":"2026-03-09T04:00:00Z","hours":23,"error":null}'::jsonb,
  'C3.2 [UTC session]: build_daily_summary(2026-03-08) covers [Mar 8 05:00Z, Mar 9 04:00Z) — the 23 h ET day');
SELECT is((SELECT jsonb_build_object('summary_date', r -> 'summary_date', 'from', r -> 'from', 'to', r -> 'to', 'hours', r -> 'hours', 'error', r -> 'error')
             FROM (SELECT tap._fetch269('bd1_la_mar8') AS r) x),
  '{"summary_date":"2026-03-08","from":"2026-03-08T05:00:00Z","to":"2026-03-09T04:00:00Z","hours":23,"error":null}'::jsonb,
  'C3.2 [Los_Angeles session]: the same');
SELECT is(jsonb_build_object('nov1', tap._delta269('bd1_utc_nov1', 'bd0_utc_nov1'), 'nov2', tap._delta269('bd1_utc_nov2', 'bd0_utc_nov2'),
                             'mar8', tap._delta269('bd1_utc_mar8', 'bd0_utc_mar8')),
  '{"nov1":{"cents":30,"count":4},"nov2":{"cents":32,"count":1},"mar8":{"cents":384,"count":2}}'::jsonb,
  'C3.3 [UTC session]: half-open days — the 05:00Z instant (a6, 32) is in Nov 2''s summary and not Nov 1''s; Mar 9 04:00Z (b4) is not in Mar 8''s');
SELECT is(jsonb_build_object('nov1', tap._delta269('bd1_la_nov1', 'bd0_la_nov1'), 'nov2', tap._delta269('bd1_la_nov2', 'bd0_la_nov2'),
                             'mar8', tap._delta269('bd1_la_mar8', 'bd0_la_mar8')),
  '{"nov1":{"cents":30,"count":4},"nov2":{"cents":32,"count":1},"mar8":{"cents":384,"count":2}}'::jsonb,
  'C3.3 [Los_Angeles session]: the same');
SELECT is(tap._fetch269('bdd_utc'),
  jsonb_build_object('summary_date', ((now() AT TIME ZONE 'America/New_York')::date - 1)::text,
                     'from', tap._z269(((now() AT TIME ZONE 'America/New_York')::date - 1)::timestamp AT TIME ZONE 'America/New_York'),
                     'to',   tap._z269(((now() AT TIME ZONE 'America/New_York')::date)::timestamp AT TIME ZONE 'America/New_York')),
  'C3.4 [UTC session]: with no argument it summarizes the previous full ET day: summary_date = ET yesterday, [its 00:00 ET, ET today 00:00)');
SELECT is(tap._fetch269('bdd_la'),
  jsonb_build_object('summary_date', ((now() AT TIME ZONE 'America/New_York')::date - 1)::text,
                     'from', tap._z269(((now() AT TIME ZONE 'America/New_York')::date - 1)::timestamp AT TIME ZONE 'America/New_York'),
                     'to',   tap._z269(((now() AT TIME ZONE 'America/New_York')::date)::timestamp AT TIME ZONE 'America/New_York')),
  'C3.4 [Los_Angeles session]: the same');
SELECT is(jsonb_build_object(
             'future_error', tap._fetch269('bdf_utc') -> 'error', 'future_message', tap._fetch269('bdf_utc') -> 'message',
             'future_rows', tap._fetch269('bdf_utc_rows'),
             'today', (SELECT jsonb_build_object('summary_date', r -> 'summary_date', 'from', r -> 'from', 'to', r -> 'to', 'error', r -> 'error')
                         FROM (SELECT tap._fetch269('bdt_utc') AS r) x)),
  jsonb_build_object(
             'future_error', 'P0001',
             'future_message', format('invalid_input: p_date %s is after the current ET date', (now() AT TIME ZONE 'America/New_York')::date + 1),
             'future_rows', 0,
             'today', jsonb_build_object('summary_date', to_jsonb((now() AT TIME ZONE 'America/New_York')::date),
                                         'from', tap._z269(((now() AT TIME ZONE 'America/New_York')::date)::timestamp AT TIME ZONE 'America/New_York'),
                                         'to', tap._z269(now()), 'error', NULL)),
  'C3.6 [UTC session]: a future ET date (ET today + 1) is refused invalid_input and writes no summary row; ET today (a partial day) builds [00:00 ET, now())');
SELECT is(jsonb_build_object(
             'future_error', tap._fetch269('bdf_la') -> 'error', 'future_message', tap._fetch269('bdf_la') -> 'message',
             'future_rows', tap._fetch269('bdf_la_rows'),
             'today', (SELECT jsonb_build_object('summary_date', r -> 'summary_date', 'from', r -> 'from', 'to', r -> 'to', 'error', r -> 'error')
                         FROM (SELECT tap._fetch269('bdt_la') AS r) x)),
  jsonb_build_object(
             'future_error', 'P0001',
             'future_message', format('invalid_input: p_date %s is after the current ET date', (now() AT TIME ZONE 'America/New_York')::date + 1),
             'future_rows', 0,
             'today', jsonb_build_object('summary_date', to_jsonb((now() AT TIME ZONE 'America/New_York')::date),
                                         'from', tap._z269(((now() AT TIME ZONE 'America/New_York')::date)::timestamp AT TIME ZONE 'America/New_York'),
                                         'to', tap._z269(now()), 'error', NULL)),
  'C3.6 [Los_Angeles session]: the same');
SELECT is(pg_get_function_arguments(to_regprocedure('ops.build_daily_summary(date)')),
  'p_date date DEFAULT (((now() AT TIME ZONE ''America/New_York''::text))::date - 1)',
  'C3.5: the declared default is ET yesterday — (now() at time zone ''America/New_York'')::date - 1');

-- ── C2 — ops.refresh_metrics window_30d (internal: called as postgres)
SET LOCAL timezone = 'UTC';
SELECT tap._store269('rm0_utc', tap._refresh269());
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('rm0_la', tap._refresh269());
-- c1 exactly at ET midnight 30 days back (inside), c2 one second earlier (outside)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, created_at, paid_at)
SELECT ('a2690000-0000-4000-a000-000000000' || c.n)::uuid, NULL, 'a2690000-0000-4000-a000-000000000101', NULL, c.cents, 0, 0, c.cents,
       'pi_269_' || c.n, 'succeeded', 'native_primary', c.at, c.at
  FROM (SELECT '801' AS n, 1024 AS cents, ((now() AT TIME ZONE 'America/New_York')::date - 30)::timestamp AT TIME ZONE 'America/New_York' AS at
        UNION ALL
        SELECT '802', 2048, (((now() AT TIME ZONE 'America/New_York')::date - 30)::timestamp AT TIME ZONE 'America/New_York') - interval '1 second') c;
SET LOCAL timezone = 'UTC';
SELECT tap._store269('rm1_utc', tap._refresh269());
SET LOCAL timezone = 'America/Los_Angeles';
SELECT tap._store269('rm1_la', tap._refresh269());
SELECT is(tap._rdelta269('rm1_utc', 'rm0_utc'), '{"w_cents":1024,"w_count":1,"a_cents":3072,"a_count":2}'::jsonb,
  'C2.1 [UTC session]: window_30d starts exactly at ET midnight 30 days back — the payment at it counts, the one a second earlier does not (all-time has both)');
SELECT is(tap._rdelta269('rm1_la', 'rm0_la'), '{"w_cents":1024,"w_count":1,"a_cents":3072,"a_count":2}'::jsonb,
  'C2.1 [Los_Angeles session]: the same');
SELECT is((SELECT jsonb_build_object(
             'gross',    max(value ->> 'basis') FILTER (WHERE key = 'money.gross_captured'),
             'fees',     max(value ->> 'basis') FILTER (WHERE key = 'money.platform_fees'),
             'released', max(value ->> 'basis') FILTER (WHERE key = 'money.released_to_connected'),
             'refunded_et', bool_or(value ->> 'basis' LIKE '%(ET date)%') FILTER (WHERE key = 'money.refunded'),
             'utc', count(*) FILTER (WHERE value ->> 'basis' LIKE '%UTC%'))
             FROM ops.metric_snapshot WHERE key LIKE 'money.%'),
  '{"gross":"paid_at (ET date)","fees":"paid_at (ET date)","released":"payout_released_at (ET date)","refunded_et":true,"utc":0}'::jsonb,
  'C2.2: snapshot labels say "(ET date)" (money.refunded too); no money.* basis says UTC');

SELECT * FROM finish();
ROLLBACK;
