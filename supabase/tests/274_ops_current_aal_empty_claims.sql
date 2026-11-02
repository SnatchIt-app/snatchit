-- ============================================================================
-- 274_ops_current_aal_empty_claims.sql — registry 205 (20261102181000).
-- ops.current_aal() reads an EMPTY-STRING request.jwt.claims exactly like an ABSENT one (NULL), so every caller
-- answers as it does for absent claims; MALFORMED non-empty claims still raise 22P02 (fail closed, its own class).
-- Probes, run per claims-GUC state by tap._cap274 into tap.memo_274 and asserted in later statements:
--   current_aal     ops.current_aal()                  as postgres (its owner; no other role may EXECUTE it)
--   assert_reader   ops.assert_reader()                as postgres (the reader gate itself)
--   operators       ops.operators()                    as authenticated platform_admin (assert_reader path)
--   list_config     ops.list_config_approvals()        as authenticated platform_admin (assert_role path)
--   whoami          ops.whoami()                       as authenticated platform_admin
--   evidence_admin  ops.evidence_operator_may_read()   as authenticated platform_admin
--   evidence_fan    ops.evidence_operator_may_read()   as authenticated non-operator
-- These are every live caller of ops.current_aal (A4 keeps that list exact; A5 pins the body md5 of each caller and of
-- ops.assert_role(text[]) at main's text, since 205 changes none of them). The persona is identified through the
-- legacy request.jwt.claim.sub GUC, which auth.uid() reads first: the only way auth.uid() is non-null while the
-- claims are absent, '' or malformed. The ABSENT state is captured first: once a session sets the claims GUC it never
-- reads NULL again (G1 proves each state was the intended one).
-- Every call goes through tap._try274 (value helper), so on RED (main without 205) and under mutants the file emits
-- all its assertions instead of aborting.
-- ============================================================================
BEGIN;
SELECT plan(36);

CREATE FUNCTION tap._try274(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r text; BEGIN EXECUTE p_sql INTO r; RETURN jsonb_build_object('value', r);
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
-- an outcome as one text: 'ERROR <sqlstate> <message up to the first colon>' or the value ('<null>' for NULL)
CREATE FUNCTION tap._out274(r jsonb) RETURNS text LANGUAGE sql IMMUTABLE AS
$m$ SELECT CASE WHEN r ? 'error' THEN 'ERROR ' || (r ->> 'error') || ' ' || split_part(r ->> 'message', ':', 1)
                ELSE coalesce(r ->> 'value', '<null>') END $m$;
CREATE FUNCTION tap._claims274(p_aal text) RETURNS text LANGUAGE sql IMMUTABLE AS
$m$ SELECT jsonb_build_object('sub', 'a2740000-0000-4000-a000-0000000000a1', 'role', 'authenticated', 'aal', p_aal)::text $m$;
CREATE TABLE tap.memo_274 (k text PRIMARY KEY, v jsonb NOT NULL);
CREATE FUNCTION tap._m274(p_k text) RETURNS jsonb LANGUAGE sql STABLE AS $m$ SELECT v FROM tap.memo_274 WHERE k = p_k $m$;
-- rows inserted, updated or deleted by THIS transaction in the application schemas (tap and temp tables excluded)
CREATE FUNCTION tap._w274() RETURNS bigint LANGUAGE sql STABLE AS
$m$ SELECT coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0)::bigint FROM pg_stat_xact_all_tables
     WHERE schemaname IN ('public', 'ops', 'kernel', 'catalog', 'venue', 'venue_api', 'venue_cmd', 'auth', 'storage') $m$;
-- One state: set the claims GUC (unless p_set is false: the absent state), then every probe; the result is stored as
-- postgres after the role is reset. The role switches are statement-level set_config calls, as tap.login does.
CREATE FUNCTION tap._cap274(p_state text, p_claims text, p_set boolean) RETURNS void LANGUAGE plpgsql AS $m$
DECLARE v jsonb;
BEGIN
  IF p_set THEN PERFORM set_config('request.jwt.claims', p_claims, true); END IF;
  PERFORM set_config('request.jwt.claim.sub', 'a2740000-0000-4000-a000-0000000000a1', true);
  v := jsonb_build_object('guc', current_setting('request.jwt.claims', true));
  v := v || jsonb_build_object('current_aal', tap._try274('SELECT ops.current_aal()'));
  v := v || jsonb_build_object('assert_reader', tap._try274('SELECT ops.assert_reader()::text || ''passed'''));
  PERFORM set_config('role', 'authenticated', true);
  v := v || jsonb_build_object('operators', tap._try274('SELECT ops.operators()::text'));
  v := v || jsonb_build_object('list_config', tap._try274('SELECT ops.list_config_approvals()::text'));
  v := v || jsonb_build_object('whoami', tap._try274('SELECT ops.whoami()::text'));
  v := v || jsonb_build_object('evidence_admin', tap._try274('SELECT ops.evidence_operator_may_read()::text'));
  PERFORM set_config('request.jwt.claim.sub', 'a2740000-0000-4000-a000-0000000000f1', true);
  v := v || jsonb_build_object('evidence_fan', tap._try274('SELECT ops.evidence_operator_may_read()::text'));
  PERFORM set_config('request.jwt.claim.sub', 'a2740000-0000-4000-a000-0000000000a1', true);
  PERFORM set_config('role', 'none', true);
  INSERT INTO tap.memo_274 VALUES (p_state, v);
END $m$;
-- ops.current_aal() over JSON values of the wrong shape and over whitespace, in input order
CREATE FUNCTION tap._types274(p_inputs text[]) RETURNS void LANGUAGE plpgsql AS $m$
DECLARE v jsonb := '[]'; i text; r jsonb;
BEGIN
  FOREACH i IN ARRAY p_inputs LOOP
    PERFORM set_config('request.jwt.claims', i, true);
    r := tap._try274('SELECT ops.current_aal()');
    v := v || jsonb_build_array(CASE WHEN r ? 'error' THEN to_jsonb('ERROR ' || (r ->> 'error')) ELSE r -> 'value' END);
  END LOOP;
  INSERT INTO tap.memo_274 VALUES ('types', v);
END $m$;
-- direct calls to ops.current_aal() as authenticated (aal2 claims) and as anon
CREATE FUNCTION tap._roles274() RETURNS void LANGUAGE plpgsql AS $m$
DECLARE v jsonb := '{}';
BEGIN
  PERFORM set_config('request.jwt.claims', tap._claims274('aal2'), true);
  PERFORM set_config('role', 'authenticated', true);
  v := v || jsonb_build_object('authenticated', tap._out274(tap._try274('SELECT ops.current_aal()')));
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('role', 'anon', true);
  v := v || jsonb_build_object('anon', tap._out274(tap._try274('SELECT ops.current_aal()')));
  PERFORM set_config('role', 'none', true);
  INSERT INTO tap.memo_274 VALUES ('roles', v);
END $m$;
GRANT EXECUTE ON FUNCTION tap._try274(text), tap._out274(jsonb) TO authenticated, anon;

-- Fixtures (as postgres): one platform_admin and one account with no platform role.
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('a2740000-0000-4000-a000-0000000000a1', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'admin.274@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('a2740000-0000-4000-a000-0000000000f1', repeat('0', 32)::uuid, 'authenticated', 'authenticated', 'fan.274@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES ('a2740000-0000-4000-a000-0000000000a1', 'platform_admin');
INSERT INTO tap.memo_274 VALUES ('w0', to_jsonb(tap._w274()));

-- ── Captures. ABSENT first (the claims GUC has never been set in this session), then each set state.
SELECT tap._cap274('absent', NULL, false);
SELECT tap._cap274('empty', '', true);
SELECT tap._cap274('braces', '{}', true);
SELECT tap._cap274('malformed', '{"aal":', true);
SELECT tap._cap274('notjson', 'not-json{', true);
SELECT tap._cap274('aal1', tap._claims274('aal1'), true);
SELECT tap._cap274('aal2', tap._claims274('aal2'), true);
SELECT tap._types274(array['"aal2"', '[]', 'null', '{"aal":null}', '{"aal":2}', '{"aal":"AAL2"}', '{"aal":["aal2"]}', ' ', '{"aal":"aal2"} ']);
SELECT tap._roles274();
INSERT INTO tap.memo_274 VALUES ('w1', to_jsonb(tap._w274()));

-- ── A — posture and identity
SELECT ok(
  (SELECT count(*) FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
    WHERE p.pronamespace = 'ops'::regnamespace AND p.proname = 'current_aal'
      AND p.oid = to_regprocedure('ops.current_aal()') AND l.lanname = 'sql' AND p.provolatile = 's'
      AND p.prosecdef AND p.proconfig = array['search_path=""'] AND p.proowner = 'postgres'::regrole
      AND p.prorettype = 'text'::regtype) = 1
  AND (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'ops'::regnamespace AND p.proname = 'current_aal') = 1,
  'A1: ops.current_aal() is the only overload: sql, STABLE, SECURITY DEFINER, search_path '''', owner postgres, returns text');
SELECT is(
  (SELECT string_agg(e, ',' ORDER BY e) FROM (
     SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS e
       FROM pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE p.oid = to_regprocedure('ops.current_aal()')) x),
  'postgres:EXECUTE',
  'A2: EXECUTE on ops.current_aal() is its owner''s only (no PUBLIC, anon, authenticated or service_role)');
SELECT is(
  md5(pg_get_functiondef(to_regprocedure('ops.current_aal()'))),
  '2ea76875ab125648ab5745609f7ed1ef',
  'A3: ops.current_aal() carries the body 205 declares (md5 2ea76875ab125648ab5745609f7ed1ef)');
SELECT is(
  (SELECT string_agg(p.oid::regprocedure::text, ' ' ORDER BY p.oid::regprocedure::text) FROM pg_proc p
    WHERE p.prosrc LIKE '%ops.current_aal()%' AND p.oid <> to_regprocedure('ops.current_aal()')
      AND p.pronamespace <> 'tap'::regnamespace),
  'ops.assert_reader() ops.evidence_operator_may_read() ops.whoami()',
  'A4: outside the test harness, the live callers of ops.current_aal() are exactly assert_reader, evidence_operator_may_read and whoami — each probed below');
-- md5(pg_get_functiondef(...)) measured on a local PG17 replay of main 7496fee3 (d197_base), before and after 205;
-- a missing signature reads '<missing>' instead of dropping out of the list
SELECT is(
  (SELECT string_agg(s.sig || '=' || coalesce(md5(pg_get_functiondef(to_regprocedure(s.sig))), '<missing>'), ' ' ORDER BY s.n)
     FROM unnest(array['ops.assert_reader()', 'ops.assert_role(text[])', 'ops.whoami()', 'ops.evidence_operator_may_read()'])
          WITH ORDINALITY AS s(sig, n)),
  'ops.assert_reader()=24c003a983cb577b6ad178fc595c17c5 ops.assert_role(text[])=0b3bf7d903322c5ec83964a3a6c00907 '
  || 'ops.whoami()=e3de6980a9b8c5c172627acbb256d2bb ops.evidence_operator_may_read()=76a71c68d1934d532f6ef4bfc906c53a',
  'A5: assert_reader, assert_role, whoami and evidence_operator_may_read keep main''s bodies (205 changes ops.current_aal() only)');

-- ── G — each capture ran in the intended claims state
SELECT is(
  (SELECT jsonb_object_agg(m.k, m.v -> 'guc') FROM tap.memo_274 m
    WHERE m.k IN ('absent', 'empty', 'braces', 'malformed', 'notjson', 'aal1', 'aal2')),
  jsonb_build_object('absent', NULL::text, 'empty', '', 'braces', '{}', 'malformed', '{"aal":', 'notjson', 'not-json{',
                     'aal1', tap._claims274('aal1'), 'aal2', tap._claims274('aal2')),
  'G1: the claims GUC read at each capture: absent = NULL, empty = '''', then {}, two malformed texts, aal1 and aal2 claims');

-- ── N — ABSENT claims (unchanged by 205)
SELECT is(tap._m274('absent') -> 'current_aal', '{"value": null}'::jsonb,
  'N1: absent claims — ops.current_aal() returns NULL');
SELECT is(
  jsonb_build_object('assert_reader', tap._out274(tap._m274('absent') -> 'assert_reader'),
                     'operators',     tap._out274(tap._m274('absent') -> 'operators'),
                     'list_config',   tap._out274(tap._m274('absent') -> 'list_config')),
  '{"assert_reader":"ERROR P0001 step_up_unavailable","operators":"ERROR P0001 step_up_unavailable","list_config":"ERROR P0001 step_up_unavailable"}'::jsonb,
  'N2: absent claims — assert_reader, operators (assert_reader path) and list_config_approvals (assert_role path) refuse step_up_unavailable (P0001)');
SELECT is(
  (SELECT jsonb_build_object('raised', r ? 'error', 'aal', (r ->> 'value')::jsonb -> 'aal', 'role', (r ->> 'value')::jsonb ->> 'role')
     FROM (SELECT tap._m274('absent') -> 'whoami' AS r) x),
  '{"raised":false,"aal":null,"role":"platform_admin"}'::jsonb,
  'N3: absent claims — ops.whoami() answers without raising: role platform_admin, aal null');
SELECT is(tap._m274('absent') -> 'evidence_admin', '{"value": null}'::jsonb,
  'N4: absent claims — ops.evidence_operator_may_read() is NULL (not true) for a platform_admin, without raising');
SELECT is(tap._m274('absent') -> 'evidence_fan', '{"value": "false"}'::jsonb,
  'N5: absent claims — ops.evidence_operator_may_read() is false for a non-operator');

-- ── E — EMPTY-STRING claims (before 205: 22P02 from every caller)
SELECT is(tap._m274('empty') -> 'current_aal', '{"value": null}'::jsonb,
  'E1: claims '''' — ops.current_aal() returns NULL, as for absent claims (no 22P02)');
SELECT is(
  jsonb_build_object('assert_reader', tap._out274(tap._m274('empty') -> 'assert_reader'),
                     'operators',     tap._out274(tap._m274('empty') -> 'operators'),
                     'list_config',   tap._out274(tap._m274('empty') -> 'list_config')),
  '{"assert_reader":"ERROR P0001 step_up_unavailable","operators":"ERROR P0001 step_up_unavailable","list_config":"ERROR P0001 step_up_unavailable"}'::jsonb,
  'E2: claims '''' — assert_reader, operators and list_config_approvals refuse step_up_unavailable (P0001), not 22P02');
SELECT is(
  (SELECT jsonb_build_object('raised', r ? 'error', 'aal', (r ->> 'value')::jsonb -> 'aal', 'role', (r ->> 'value')::jsonb ->> 'role')
     FROM (SELECT tap._m274('empty') -> 'whoami' AS r) x),
  '{"raised":false,"aal":null,"role":"platform_admin"}'::jsonb,
  'E3: claims '''' — ops.whoami() answers without raising: role platform_admin, aal null');
SELECT is(tap._m274('empty') -> 'evidence_admin', '{"value": null}'::jsonb,
  'E4: claims '''' — ops.evidence_operator_may_read() is NULL (not true) for a platform_admin, without raising');
SELECT is(tap._m274('empty') -> 'evidence_fan', '{"value": "false"}'::jsonb,
  'E5: claims '''' — ops.evidence_operator_may_read() is false for a non-operator, without raising');

-- ── I — EMPTY-STRING and ABSENT claims give identical results, caller by caller (value or SQLSTATE + message)
SELECT is(tap._m274('empty') -> 'current_aal', tap._m274('absent') -> 'current_aal',
  'I1: ops.current_aal(): claims '''' and absent claims give the identical result');
SELECT is(tap._m274('empty') -> 'assert_reader', tap._m274('absent') -> 'assert_reader',
  'I2: ops.assert_reader(): claims '''' and absent claims give the identical result');
SELECT is(tap._m274('empty') -> 'operators', tap._m274('absent') -> 'operators',
  'I3: ops.operators(): claims '''' and absent claims give the identical result');
SELECT is(tap._m274('empty') -> 'list_config', tap._m274('absent') -> 'list_config',
  'I4: ops.list_config_approvals(): claims '''' and absent claims give the identical result');
SELECT is(tap._m274('empty') -> 'whoami', tap._m274('absent') -> 'whoami',
  'I5: ops.whoami(): claims '''' and absent claims give the identical result');
SELECT is(tap._m274('empty') -> 'evidence_admin', tap._m274('absent') -> 'evidence_admin',
  'I6: ops.evidence_operator_may_read() as a platform_admin: claims '''' and absent claims give the identical result');
SELECT is(tap._m274('empty') -> 'evidence_fan', tap._m274('absent') -> 'evidence_fan',
  'I7: ops.evidence_operator_may_read() as a non-operator: claims '''' and absent claims give the identical result');

-- ── B — '{}' (a JSON object with no aal) reads like absent claims everywhere (unchanged by 205)
SELECT is(tap._m274('braces') - 'guc', tap._m274('absent') - 'guc',
  'B1: claims {} give the same result as absent claims for every probe');

-- ── M — MALFORMED non-empty claims stay fail-closed with 22P02 (never NULL, never a step_up_* answer, never a pass)
SELECT is(
  jsonb_build_array(tap._out274(tap._m274('malformed') -> 'current_aal'), tap._out274(tap._m274('notjson') -> 'current_aal')),
  '["ERROR 22P02 invalid input syntax for type json","ERROR 22P02 invalid input syntax for type json"]'::jsonb,
  'M1: claims {"aal": and not-json{ — ops.current_aal() raises 22P02 (not caught)');
SELECT is(
  (SELECT jsonb_object_agg(e.key, left(tap._out274(e.value), 11)) FROM jsonb_each(tap._m274('malformed') - 'guc' - 'current_aal') e),
  '{"assert_reader":"ERROR 22P02","operators":"ERROR 22P02","list_config":"ERROR 22P02","whoami":"ERROR 22P02","evidence_admin":"ERROR 22P02","evidence_fan":"false"}'::jsonb,
  'M2: claims {"aal": — every platform_admin caller raises 22P02; the non-operator''s evidence check is false');
SELECT is(
  (SELECT jsonb_object_agg(e.key, left(tap._out274(e.value), 11)) FROM jsonb_each(tap._m274('notjson') - 'guc' - 'current_aal') e),
  '{"assert_reader":"ERROR 22P02","operators":"ERROR 22P02","list_config":"ERROR 22P02","whoami":"ERROR 22P02","evidence_admin":"ERROR 22P02","evidence_fan":"false"}'::jsonb,
  'M3: claims not-json{ — every platform_admin caller raises 22P02; the non-operator''s evidence check is false');

-- ── T — value shapes: only the exact empty string is normalised
SELECT is(tap._m274('types'),
  '[null,null,null,null,"2","AAL2","[\"aal2\"]","ERROR 22P02","aal2"]'::jsonb,
  'T1: ops.current_aal() over "aal2", [], null, {"aal":null}, {"aal":2}, {"aal":"AAL2"}, {"aal":["aal2"]}, a single space, and aal2 with a trailing space: NULL x4, the text of aal, 22P02 for whitespace-only text');

-- ── L — aal1 claims (unchanged by 205)
SELECT is(tap._m274('aal1') -> 'current_aal', '{"value": "aal1"}'::jsonb,
  'L1: aal1 claims — ops.current_aal() returns aal1');
SELECT is(
  jsonb_build_object('assert_reader', tap._out274(tap._m274('aal1') -> 'assert_reader'),
                     'operators',     tap._out274(tap._m274('aal1') -> 'operators'),
                     'list_config',   tap._out274(tap._m274('aal1') -> 'list_config')),
  '{"assert_reader":"ERROR P0001 step_up_required","operators":"ERROR P0001 step_up_required","list_config":"ERROR P0001 step_up_required"}'::jsonb,
  'L2: aal1 claims — assert_reader, operators and list_config_approvals refuse step_up_required (P0001)');
SELECT is(
  jsonb_build_object('whoami_aal', (tap._m274('aal1') -> 'whoami' ->> 'value')::jsonb -> 'aal',
                     'evidence_admin', tap._out274(tap._m274('aal1') -> 'evidence_admin'),
                     'evidence_fan',   tap._out274(tap._m274('aal1') -> 'evidence_fan')),
  '{"whoami_aal":"aal1","evidence_admin":"false","evidence_fan":"false"}'::jsonb,
  'L3: aal1 claims — whoami reports aal1; the evidence check is false for a platform_admin and for a non-operator');

-- ── H — aal2 claims (unchanged by 205)
SELECT is(tap._m274('aal2') -> 'current_aal', '{"value": "aal2"}'::jsonb,
  'H1: aal2 claims — ops.current_aal() returns aal2');
SELECT is(
  jsonb_build_object('assert_reader', tap._out274(tap._m274('aal2') -> 'assert_reader'),
                     'operators_lists_admin', coalesce((tap._m274('aal2') -> 'operators' ->> 'value')::jsonb
                                                       @> '[{"user_id":"a2740000-0000-4000-a000-0000000000a1","role":"platform_admin"}]'::jsonb, false),
                     'list_config_state', (tap._m274('aal2') -> 'list_config' ->> 'value')::jsonb ->> 'state'),
  '{"assert_reader":"passed","operators_lists_admin":true,"list_config_state":"pending"}'::jsonb,
  'H2: aal2 claims — assert_reader passes; operators lists the platform_admin; list_config_approvals answers (state pending)');
SELECT is(
  jsonb_build_object('whoami_aal', (tap._m274('aal2') -> 'whoami' ->> 'value')::jsonb -> 'aal',
                     'evidence_admin', tap._out274(tap._m274('aal2') -> 'evidence_admin'),
                     'evidence_fan',   tap._out274(tap._m274('aal2') -> 'evidence_fan')),
  '{"whoami_aal":"aal2","evidence_admin":"true","evidence_fan":"false"}'::jsonb,
  'H3: aal2 claims — whoami reports aal2; the evidence check is true for a platform_admin and false for a non-operator');

-- ── R — no client role may call ops.current_aal() directly
SELECT is(
  (SELECT jsonb_object_agg(e.key, left(e.value #>> '{}', 11)) FROM jsonb_each(tap._m274('roles')) e),
  '{"authenticated":"ERROR 42501","anon":"ERROR 42501"}'::jsonb,
  'R1: ops.current_aal() called directly as authenticated (aal2 claims) and as anon is refused 42501');

-- ── W — every probe above is read-only
SELECT is(
  jsonb_build_object('fixture_writes_seen', (tap._m274('w0') #>> '{}')::bigint > 0,
                     'probe_writes', (tap._m274('w1') #>> '{}')::bigint - (tap._m274('w0') #>> '{}')::bigint),
  '{"fixture_writes_seen":true,"probe_writes":0}'::jsonb,
  'W1: no probe inserted, updated or deleted a row in an application schema (the counter sees this transaction''s fixture writes)');

SELECT * FROM finish();
ROLLBACK;
