-- ============================================================================
-- 266_ops_operational_config.sql — registry 197 (20261031180000).
-- The console's path for the four single-admin operational keys:
--   SET   ops.set_operational_config  — INVOKER passthrough to catalog.set_platform_config; gates: session,
--         platform_admin, aal2, money keys refused, explicit allow-list;
--   LIST  ops.list_operational_config — DEFINER read of the same four keys' live values.
-- Personas: admin (platform_admin), support (platform_support), fan (no platform role), anon.
-- Every call goes through tap._try266 (value helper), so RED (main without 197) and the mutants emit every
-- assertion instead of aborting at the first missing function.
-- ============================================================================
BEGIN;
SELECT plan(24);

CREATE FUNCTION tap._try266(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN coalesce(r, 'null'::jsonb);
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
CREATE FUNCTION tap._aal266(p_aal text) RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_aal IS NULL THEN (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb - 'aal')::text
         ELSE (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb || jsonb_build_object('aal', p_aal))::text END,
    true);
END $m$;
CREATE TABLE tap.memo_266 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store266(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_266 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch266(k text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_266 WHERE k = $1 $m$;
CREATE FUNCTION tap._top266(k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT jsonb_build_object('version', c.version, 'value', c.value) FROM catalog.platform_config c
     WHERE c.key = k ORDER BY c.version DESC LIMIT 1 $m$;
CREATE FUNCTION tap._writes266() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT (SELECT count(*) FROM catalog.platform_config) || '|' ||
           (SELECT count(*) FROM kernel.approval_request WHERE action = 'config.set_money_key') || '|' ||
           (SELECT count(*) FROM kernel.admin_audit WHERE action LIKE 'config.%') $m$;
CREATE FUNCTION tap._audit266(k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT jsonb_build_object('actor', a.actor_identity, 'action', a.action, 'reason', a.reason_code, 'after', a.after)
     FROM kernel.admin_audit a WHERE a.action = 'config.change' AND a.after ->> 'key' = k
    ORDER BY a.created_at DESC, a.after ->> 'version' DESC LIMIT 1 $m$;
CREATE FUNCTION tap._keys266() RETURNS SETOF jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT jsonb_build_object('key', c.key, 'value', c.value)
      FROM (SELECT DISTINCT ON (key) key, value FROM catalog.platform_config ORDER BY key, version DESC) c
     ORDER BY c.key $m$;
-- X1 driver: for EVERY seeded key, a no-op write of its live value through the setter; returns the accepted keys
CREATE FUNCTION tap._x1266() RETURNS jsonb LANGUAGE plpgsql AS $m$
DECLARE k jsonb; r jsonb; acc text[] := '{}';
BEGIN
  FOR k IN SELECT * FROM tap._keys266() LOOP
    r := tap._try266(format('SELECT ops.set_operational_config(%L, %L::jsonb, %L, %L)',
                            k->>'key', (k->'value')::text, 'x1_probe', 'x1-' || (k->>'key')));
    IF r->>'status' = 'noop_replay' THEN acc := acc || (k->>'key'); END IF;
  END LOOP;
  RETURN to_jsonb(acc);
END $m$;
GRANT EXECUTE ON FUNCTION tap._try266(text), tap._aal266(text), tap._store266(text, text), tap._fetch266(text),
  tap._top266(text), tap._writes266(), tap._audit266(text), tap._keys266(), tap._x1266() TO authenticated, anon;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('26600000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.266@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26600000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'support.266@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26600000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.266@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES
  ('26600000-0000-4000-8000-000000000101', 'platform_admin'),
  ('26600000-0000-4000-8000-000000000103', 'platform_support');

-- ── A — posture
SELECT ok(
  (SELECT count(*) FROM pg_proc p
    WHERE p.oid IN (to_regprocedure('ops.set_operational_config(text,jsonb,text,text)'), to_regprocedure('ops.list_operational_config()'))
      AND p.proconfig = array['search_path=""'] AND p.proowner = 'postgres'::regrole
      AND p.prosecdef = (p.proname = 'list_operational_config')) = 2,
  'A1: the setter is SECURITY INVOKER, the list is DEFINER; search_path '''', owner postgres');
SELECT is(
  (SELECT string_agg(p.proname || '=' || (SELECT string_agg(e, ',' ORDER BY e) FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS e
            FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) x), ' ' ORDER BY p.proname)
     FROM pg_proc p WHERE p.pronamespace = 'ops'::regnamespace AND p.proname IN ('set_operational_config','list_operational_config')),
  'list_operational_config=authenticated:EXECUTE,postgres:EXECUTE set_operational_config=authenticated:EXECUTE,postgres:EXECUTE',
  'A2: EXECUTE is exactly authenticated + postgres on both (no PUBLIC, no anon, no service_role)');

-- ── L — list (before any write)
SELECT tap.login('26600000-0000-4000-8000-000000000101');
SELECT tap._aal266('aal2');
SELECT is(
  (SELECT jsonb_agg(jsonb_build_object('key', i->>'key', 'version', i->'version', 'value', i->'value') ORDER BY ord)
     FROM jsonb_array_elements(tap._try266('SELECT ops.list_operational_config()')->'items') WITH ORDINALITY AS t(i, ord)),
  '[{"key":"inventory.per_user_active_hold_max","version":1,"value":null},{"key":"inventory.hold_ttl_interval","version":1,"value":null},{"key":"feature.native_issuance_enabled","version":1,"value":false},{"key":"feature.native_scanning_enabled","version":1,"value":false}]'::jsonb,
  'L1: a platform_admin at aal2 lists exactly the four keys, in order, with their live version and value');

-- ── X — the setter's allow-list IS the list's key set, over every seeded key
SELECT tap._store266('w0', tap._writes266());
SELECT tap._store266('x1', tap._x1266()::text);
SELECT is(
  tap._fetch266('x1')::jsonb,
  '["feature.native_issuance_enabled","feature.native_scanning_enabled","inventory.hold_ttl_interval","inventory.per_user_active_hold_max"]'::jsonb,
  'X1: over EVERY seeded key, the setter accepts (a no-op write of the live value) exactly the four keys the list returns');
SELECT is(
  jsonb_build_object('accepted', jsonb_array_length(tap._fetch266('x1')::jsonb), 'unchanged', tap._writes266() = tap._fetch266('w0')),
  '{"accepted":4,"unchanged":true}'::jsonb,
  'X2: the sweep accepted its four keys and wrote nothing (no config version, no parked request, no audit row)');

-- ── R — set (admin at aal2 unless stated)
SELECT tap._store266('r1', tap._try266($q$SELECT ops.set_operational_config('inventory.per_user_active_hold_max', '6'::jsonb, 'set_hold_max', 'cmd-266-r1')$q$)::text);
SELECT is(
  jsonb_build_object('status', tap._fetch266('r1')::jsonb->>'status', 'top', tap._top266('inventory.per_user_active_hold_max')),
  '{"status":"ok","top":{"version":2,"value":6}}'::jsonb,
  'R1: hold max 6 applies at once for ONE platform_admin (a single-admin key: no second founder)');
SELECT is(
  (SELECT jsonb_build_object('actor', a->>'actor', 'reason', a->>'reason', 'value', a->'after'->'value') FROM (SELECT tap._audit266('inventory.per_user_active_hold_max') AS a) x),
  '{"actor":"26600000-0000-4000-8000-000000000101","reason":"set_hold_max","value":6}'::jsonb,
  'R2: the audit row names the CALLER as actor (identity preserved through the INVOKER passthrough)');
SELECT tap._store266('r3', tap._try266($q$SELECT ops.set_operational_config('inventory.hold_ttl_interval', '"10 minutes"'::jsonb, 'set_hold_ttl', 'cmd-266-r3')$q$)::text);
SELECT is(
  jsonb_build_object('status', tap._fetch266('r3')::jsonb->>'status', 'top', tap._top266('inventory.hold_ttl_interval')),
  '{"status":"ok","top":{"version":2,"value":"10 minutes"}}'::jsonb,
  'R3: hold TTL "10 minutes" applies at once');
SELECT tap._store266('w3', tap._writes266());
SELECT is(
  (SELECT jsonb_build_object('refused', (r->>'message') LIKE 'precondition_failed: bad_value%', 'unchanged', tap._writes266() = tap._fetch266('w3'))
     FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('inventory.hold_ttl_interval', '600'::jsonb, 'x', 'cmd-266-r4')$q$) AS r) x),
  '{"refused":true,"unchanged":true}'::jsonb,
  'R4: set_platform_config''s own validation still applies — a bare-number TTL (read as seconds) is refused, nothing written');
SELECT is(
  (SELECT jsonb_build_object('refused', (r->>'message') LIKE 'precondition_failed: bad_value%', 'unchanged', tap._writes266() = tap._fetch266('w3'))
     FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('inventory.per_user_active_hold_max', '0'::jsonb, 'x', 'cmd-266-r5')$q$) AS r) x),
  '{"refused":true,"unchanged":true}'::jsonb,
  'R5: a hold max below 1 is refused by set_platform_config, nothing written');
SELECT tap._store266('r6', tap._try266($q$SELECT ops.set_operational_config('feature.native_issuance_enabled', 'true'::jsonb, 'stage8_flip', 'cmd-266-r6')$q$)::text);
SELECT tap._store266('r6b', tap._try266($q$SELECT ops.set_operational_config('feature.native_issuance_enabled', 'false'::jsonb, 'kill_switch', 'cmd-266-r6b')$q$)::text);
SELECT is(
  jsonb_build_object('on', tap._fetch266('r6')::jsonb->>'status', 'off', tap._fetch266('r6b')::jsonb->>'status', 'top', tap._top266('feature.native_issuance_enabled')),
  '{"on":"ok","off":"ok","top":{"version":3,"value":false}}'::jsonb,
  'R6: the issuance flag is reachable both ways — on (the Stage 8 flip) and back off (the kill switch)');
SELECT tap._store266('w7', tap._writes266());
SELECT is(
  (SELECT jsonb_build_object('refused', (r->>'message') LIKE 'precondition_failed: bad_value%', 'unchanged', tap._writes266() = tap._fetch266('w7'))
     FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('feature.native_scanning_enabled', '"yes"'::jsonb, 'x', 'cmd-266-r7')$q$) AS r) x),
  '{"refused":true,"unchanged":true}'::jsonb,
  'R7: a flag stays a boolean (set_platform_config''s type witness), nothing written');
SELECT is(
  (SELECT jsonb_build_object('status', r->>'status', 'unchanged', tap._writes266() = tap._fetch266('w7'))
     FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('inventory.per_user_active_hold_max', '6'::jsonb, 'again', 'cmd-266-r8')$q$) AS r) x),
  '{"status":"noop_replay","unchanged":true}'::jsonb,
  'R8: the same value again is a noop_replay, nothing written');
SELECT is(
  (SELECT jsonb_build_object('money', (r->>'message') LIKE 'invalid_input: refund.org_auto_execute_max_minor is a dual-control money key%', 'unchanged', tap._writes266() = tap._fetch266('w7'))
     FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('refund.org_auto_execute_max_minor', '9000'::jsonb, 'x', 'cmd-266-r9')$q$) AS r) x),
  '{"money":true,"unchanged":true}'::jsonb,
  'R9: a dual-control money key is refused by the defensive check — nothing parked, nothing written');
SELECT tap._store266('r10a', tap._try266($q$SELECT ops.set_operational_config('feature.native_resale_enabled', 'true'::jsonb, 'x', 'cmd-266-r10a')$q$)::text);
SELECT tap._store266('r10b', tap._try266($q$SELECT ops.set_operational_config('notify.announcement_hold_seconds', '600'::jsonb, 'x', 'cmd-266-r10b')$q$)::text);
SELECT is(
  jsonb_build_object(
     'resale', (tap._fetch266('r10a')::jsonb->>'message') LIKE 'invalid_input: feature.native_resale_enabled is not an operational setting%',
     'notify', (tap._fetch266('r10b')::jsonb->>'message') LIKE 'invalid_input: notify.announcement_hold_seconds is not an operational setting%',
     'unchanged', tap._writes266() = tap._fetch266('w7')),
  '{"resale":true,"notify":true,"unchanged":true}'::jsonb,
  'R10: a key outside the allow-list (feature.native_resale_enabled, notify.*) is refused, and nothing is written');
SELECT tap._aal266('aal1');
SELECT is(
  (SELECT jsonb_build_object('step_up', (r->>'message') LIKE 'step_up_required:%', 'unchanged', tap._writes266() = tap._fetch266('w7'))
     FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('feature.native_scanning_enabled', 'true'::jsonb, 'x', 'cmd-266-r12')$q$) AS r) x),
  '{"step_up":true,"unchanged":true}'::jsonb,
  'R12: an aal1 session is refused step_up_required, nothing written');
SELECT tap._aal266(NULL);
SELECT is(
  (SELECT (r->>'message') LIKE 'step_up_unavailable:%' FROM (SELECT tap._try266($q$SELECT ops.set_operational_config('feature.native_scanning_enabled', 'true'::jsonb, 'x', 'cmd-266-r13')$q$) AS r) x),
  true,
  'R13: a session without an aal claim is refused step_up_unavailable');
SELECT tap.login('26600000-0000-4000-8000-000000000103');
SELECT tap._aal266('aal2');
SELECT is(
  tap._try266($q$SELECT ops.set_operational_config('feature.native_issuance_enabled', 'false'::jsonb, 'x', 'cmd-266-r14')$q$),
  '{"error":"42501","message":"insufficient_privilege: platform_admin required (ops.set_operational_config)"}'::jsonb,
  'R14: platform_support at aal2 is refused by the WRAPPER''s platform_admin gate');
SELECT tap.login('26600000-0000-4000-8000-000000000199');
SELECT tap._aal266('aal2');
SELECT is(
  tap._try266($q$SELECT ops.set_operational_config('feature.native_issuance_enabled', 'false'::jsonb, 'x', 'cmd-266-r15')$q$),
  '{"error":"42501","message":"insufficient_privilege: platform_admin required (ops.set_operational_config)"}'::jsonb,
  'R15: a user with no platform role is refused by the wrapper''s platform_admin gate');
SELECT tap.login_anon();
SELECT is(
  tap._try266($q$SELECT ops.set_operational_config('feature.native_issuance_enabled', 'false'::jsonb, 'x', 'cmd-266-r16')$q$),
  '{"error":"42501","message":"permission denied for schema ops"}'::jsonb,
  'R16: anon is refused before the function (no USAGE on ops; and no EXECUTE, A2)');

-- ── L — list after the writes, and its refusals
SELECT tap.login('26600000-0000-4000-8000-000000000101');
SELECT tap._aal266('aal2');
SELECT is(
  (SELECT jsonb_object_agg(i->>'key', jsonb_build_object('v', i->'version', 'value', i->'value'))
     FROM jsonb_array_elements(tap._try266('SELECT ops.list_operational_config()')->'items') i),
  '{"inventory.per_user_active_hold_max":{"v":2,"value":6},"inventory.hold_ttl_interval":{"v":2,"value":"10 minutes"},"feature.native_issuance_enabled":{"v":3,"value":false},"feature.native_scanning_enabled":{"v":1,"value":false}}'::jsonb,
  'L2: the list shows each key''s LIVE version and value after the writes');
SELECT tap.login('26600000-0000-4000-8000-000000000103');
SELECT tap._aal266('aal2');
SELECT is((SELECT r->>'error' FROM (SELECT tap._try266('SELECT ops.list_operational_config()') AS r) x), '42501',
  'L3: platform_support is refused (platform_admin only)');
SELECT tap.login('26600000-0000-4000-8000-000000000199');
SELECT tap._aal266('aal2');
SELECT is((SELECT r->>'error' FROM (SELECT tap._try266('SELECT ops.list_operational_config()') AS r) x), '42501',
  'L4: a user with no platform role is refused');
SELECT tap.login('26600000-0000-4000-8000-000000000101');
SELECT tap._aal266('aal1');
SELECT is(
  (SELECT (r->>'message') LIKE 'step_up_required:%' FROM (SELECT tap._try266('SELECT ops.list_operational_config()') AS r) x),
  true,
  'L5: an aal1 admin session is refused step_up_required');

SELECT * FROM finish();
ROLLBACK;
