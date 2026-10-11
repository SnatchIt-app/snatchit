-- ============================================================================
-- 220_detect_refunds_state_on.sql — F-DETECT-REFUNDS-UNOBSERVABLE-1
-- (migration 20261011000000, registry 153).
--
-- ops.detect_refunds() returned {scanned, opened, resolved}. `scanned` mixes the
-- ungated loops with the two 150 refund-state branches, so three situations
-- produced identical output:
--   (a) the branches were skipped (refund_state_detection_enabled off);
--   (b) they ran over an empty refund-state table;
--   (c) they ran over rows that matched neither branch (e.g. only succeeded).
-- Production showed items_scanned = 2 across 288 runs before the flip, 255
-- after, and still 2 with two real succeeded rows present. 153 adds:
--   state_on       — whether the branches ran;
--   state_scanned  — rows the two branches iterated (0 when off);
--   state_rows     — refund-state rows the branches could see (NULL when off).
-- The acceptance condition (D, 2026-10-11): with the flag OFF the output must
-- DIFFER from the flag ON over zero rows. Before 153 they were identical, which
-- is the defect restated; T10 is that negative control.
-- Tested through the front door as well: ops.run_job('refunds', ...) is what the
-- cron calls, and the job_run row is asserted.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);
SELECT tap.seed_core();

CREATE FUNCTION pg_temp.run_refunds() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM tap.login_service();
  v := ops.run_job('refunds', 'test');
  PERFORM tap.logout();
  RETURN v;
END $f$;

CREATE FUNCTION pg_temp.last_detail() RETURNS jsonb LANGUAGE sql AS $f$
  SELECT r.detail FROM ops.job_run r WHERE r.job_name = 'refunds' ORDER BY r.started_at DESC, r.id DESC LIMIT 1 $f$;

CREATE FUNCTION pg_temp.refund(p_pi text, p_re text, p_status text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM tap.login_service();
  v := public.record_refund_state(p_pi, p_re, p_status, 11000,
         CASE WHEN p_status = 'failed' THEN 'expired_or_canceled_card' END, 'dashboard', 'reconcile');
  PERFORM tap.logout();
  RETURN v;
END $f$;

CREATE TEMP TABLE _out (k text PRIMARY KEY, v jsonb);

-- ── (a) detection OFF ───────────────────────────────────────────────────────
UPDATE ops.setting SET value = 'false'::jsonb WHERE key = 'refund_state_detection_enabled';
INSERT INTO _out VALUES ('off', ops.detect_refunds());

SELECT is((SELECT v ->> 'state_on' FROM _out WHERE k = 'off'), 'false',
  'T1: off: state_on = false');
SELECT is((SELECT (v ->> 'state_scanned')::int FROM _out WHERE k = 'off'), 0,
  'T2: off: state_scanned = 0');
SELECT ok((SELECT v ? 'state_rows' AND jsonb_typeof(v -> 'state_rows') = 'null' FROM _out WHERE k = 'off'),
  'T3: off: state_rows is present and null (the table was not read)');
SELECT ok((SELECT v ?& ARRAY['scanned','opened','resolved','state_on','state_scanned','state_rows'] FROM _out WHERE k = 'off'),
  'T4: the result keeps scanned, opened and resolved, and adds the three new keys');
SELECT is(pg_temp.run_refunds() ->> 'status', 'succeeded',
  'T5: run_job(''refunds'') succeeds with detection off');
SELECT is(pg_temp.last_detail() ->> 'state_on', 'false',
  'T6: the job_run row for that tick records state_on = false');

-- ── (b) detection ON over an empty refund-state table ───────────────────────
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'refund_state_detection_enabled';
INSERT INTO _out VALUES ('on_empty', ops.detect_refunds());

SELECT is((SELECT v ->> 'state_on' FROM _out WHERE k = 'on_empty'), 'true',
  'T7: on, empty: state_on = true');
SELECT is((SELECT (v ->> 'state_rows')::int FROM _out WHERE k = 'on_empty'), 0,
  'T8: on, empty: state_rows = 0');
SELECT is((SELECT (v ->> 'state_scanned')::int FROM _out WHERE k = 'on_empty'), 0,
  'T9: on, empty: state_scanned = 0');
-- the negative control: same data, same legacy counters, different output
SELECT ok((SELECT a.v - ARRAY['state_on','state_scanned','state_rows'] = b.v - ARRAY['state_on','state_scanned','state_rows']
                  AND a.v IS DISTINCT FROM b.v
             FROM _out a, _out b WHERE a.k = 'off' AND b.k = 'on_empty'),
  'T10: OFF and ON-over-zero-rows agree on the legacy counters yet differ in output (identical before 153)');
SELECT is(pg_temp.run_refunds() ->> 'status', 'succeeded',
  'T11: run_job(''refunds'') succeeds with detection on');

-- ── (c) ON over a row neither branch selects (a succeeded refund) ───────────
SELECT is(pg_temp.refund('pi_fixture_a', 're_t220_succeeded_000001', 'succeeded') ->> 'recorded', 'true',
  'F1: fixture: a succeeded refund-state row, recorded through record_refund_state');
INSERT INTO _out VALUES ('on_succeeded', ops.detect_refunds());

SELECT is((SELECT (v ->> 'state_rows')::int FROM _out WHERE k = 'on_succeeded'), 1,
  'T12: on, one succeeded row: state_rows = 1 (the branches saw the row)');
SELECT is((SELECT (v ->> 'state_scanned')::int FROM _out WHERE k = 'on_succeeded'), 0,
  'T13: on, one succeeded row: state_scanned = 0 (neither branch selects succeeded)');

-- ── (d) ON over a row a branch selects (a failed refund) ────────────────────
SELECT is(pg_temp.refund('pi_fixture_b', 're_t220_failed_000000001', 'failed') ->> 'recorded', 'true',
  'F2: fixture: a failed refund-state row, recorded through record_refund_state');
INSERT INTO _out VALUES ('on_failed', ops.detect_refunds());

SELECT is((SELECT (v ->> 'state_scanned')::int FROM _out WHERE k = 'on_failed'), 1,
  'T14: on, plus one failed row: state_scanned = 1');
SELECT is((SELECT (v ->> 'opened')::int FROM _out WHERE k = 'on_failed'), 1,
  'T15: and that failed refund opens one case');

-- ── unchanged security posture ──────────────────────────────────────────────
SELECT ok((SELECT p.prosecdef AND p.proconfig = ARRAY['search_path=""']
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'ops' AND p.proname = 'detect_refunds'),
  'T16: detect_refunds stays SECURITY DEFINER with search_path ''''');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.detect_refunds()', 'EXECUTE'),
  'T17: authenticated cannot execute detect_refunds');
SELECT ok(NOT has_function_privilege('service_role', 'ops.detect_refunds()', 'EXECUTE'),
  'T18: service_role cannot execute detect_refunds directly (only through run_job)');

SELECT * FROM finish();
ROLLBACK;
