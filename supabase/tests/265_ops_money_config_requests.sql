-- ============================================================================
-- 265_ops_money_config_requests.sql — registry 196 (20261030210000).
-- The console's money-key dual-control path:
--   REQUEST  ops.request_platform_config — INVOKER passthrough to catalog.set_platform_config, gated
--            platform_admin + aal2 + money keys only;
--   LIST     ops.list_config_approvals   — DEFINER read of kernel.approval_request 'config.set_money_key';
--   APPROVE  kernel.approve_refund_request (085, unchanged) — a second, distinct platform_admin at aal2.
-- Personas: admin1 + admin2 (platform_admin), support (platform_support), fan (no platform role), anon.
-- Every call goes through tap._try265 (value helper), so on RED (main without 196) and under mutants the file
-- emits all its assertions instead of aborting at the first missing function.
-- ============================================================================
BEGIN;
SELECT plan(28);

CREATE FUNCTION tap._try265(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS
$m$ DECLARE r jsonb; BEGIN EXECUTE p_sql INTO r; RETURN coalesce(r, 'null'::jsonb);
    EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE, 'message', SQLERRM); END $m$;
CREATE FUNCTION tap._aal265(p_aal text) RETURNS void LANGUAGE plpgsql AS $m$ BEGIN
  PERFORM set_config('request.jwt.claims',
    CASE WHEN p_aal IS NULL THEN (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb - 'aal')::text
         ELSE (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb || jsonb_build_object('aal', p_aal))::text END,
    true);
END $m$;
CREATE TABLE tap.memo_265 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store265(k text, v text) RETURNS text LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_265 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch265(k text) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_265 WHERE k = $1 $m$;
CREATE FUNCTION tap._req265(p_request_id uuid) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT to_jsonb(a) FROM kernel.approval_request a WHERE a.request_id = p_request_id $m$;
CREATE FUNCTION tap._nreq265() RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT count(*)::integer FROM kernel.approval_request WHERE action = 'config.set_money_key' $m$;
CREATE FUNCTION tap._top265(k text) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS
$m$ SELECT jsonb_build_object('version', c.version, 'value', c.value) FROM catalog.platform_config c
     WHERE c.key = k ORDER BY c.version DESC LIMIT 1 $m$;
CREATE FUNCTION tap._set265(k text, v jsonb) RETURNS void LANGUAGE sql SECURITY DEFINER AS $m$
  INSERT INTO catalog.platform_config (key, version, value, visibility)
  SELECT c.key, c.version + 1, v, c.visibility FROM catalog.platform_config c
   WHERE c.key = k ORDER BY c.version DESC LIMIT 1 $m$;
GRANT EXECUTE ON FUNCTION tap._try265(text), tap._aal265(text), tap._store265(text, text), tap._fetch265(text),
  tap._req265(uuid), tap._nreq265(), tap._top265(text) TO authenticated, anon;

INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('26500000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin1.265@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26500000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin2.265@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26500000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'support.265@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26500000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.265@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.platform_role (identity_id, role) VALUES
  ('26500000-0000-4000-8000-000000000101', 'platform_admin'),
  ('26500000-0000-4000-8000-000000000102', 'platform_admin'),
  ('26500000-0000-4000-8000-000000000103', 'platform_support');
-- a numeric current value, so a tightening (lower) applies at once and a loosening (higher) parks
SELECT tap._set265('refund.org_auto_execute_max_minor', '5000'::jsonb);
SELECT tap._store265('n0', tap._nreq265()::text);
SELECT tap._store265('notify0', tap._top265('notify.announcement_hold_seconds')::text);

-- ── A — posture
SELECT ok(
  (SELECT count(*) FROM pg_proc p
    WHERE p.oid IN (to_regprocedure('ops.money_config_key(text)'),
                    to_regprocedure('ops.request_platform_config(text,jsonb,text,text)'),
                    to_regprocedure('ops.list_config_approvals(text)'))
      AND p.proconfig = array['search_path=""'] AND p.proowner = 'postgres'::regrole
      AND p.prosecdef = (p.proname = 'list_config_approvals')) = 3,
  'A1: the three ops functions exist; request + predicate are SECURITY INVOKER, the list is DEFINER; search_path '''', owner postgres');
SELECT is(
  (SELECT string_agg(p.proname || '=' || (SELECT string_agg(e, ',' ORDER BY e) FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS e
            FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) x), ' ' ORDER BY p.proname)
     FROM pg_proc p WHERE p.pronamespace = 'ops'::regnamespace AND p.proname IN ('money_config_key','request_platform_config','list_config_approvals')),
  'list_config_approvals=authenticated:EXECUTE,postgres:EXECUTE money_config_key=authenticated:EXECUTE,postgres:EXECUTE request_platform_config=authenticated:EXECUTE,postgres:EXECUTE',
  'A2: EXECUTE is exactly authenticated + postgres on all three (no PUBLIC, no anon, no service_role)');

-- ── D — the predicate is set_platform_config's v_dual, and stays so
SELECT is(
  (SELECT btrim(regexp_replace(substring(p.prosrc FROM 'select\s+(.*?);'), '\s+', ' ', 'g')) FROM pg_proc p WHERE p.oid = to_regprocedure('ops.money_config_key(text)')),
  (SELECT btrim(regexp_replace(substring(p.prosrc FROM 'v_dual := (.*?);'), '\s+', ' ', 'g')) FROM pg_proc p WHERE p.oid = 'catalog.set_platform_config(text,jsonb,text,text)'::regprocedure),
  'D1: ops.money_config_key''s expression is catalog.set_platform_config''s v_dual, verbatim (drift alarm)');
SELECT is(
  tap._try265($q$SELECT to_jsonb(array[
      ops.money_config_key('refund.org_auto_execute_max_minor'), ops.money_config_key('payout.request_auto_max_minor'),
      ops.money_config_key('authn.money_action_required_aal'),   ops.money_config_key('comp.per_staff_step_up_max_units'),
      ops.money_config_key('wallet.apple.enabled'),              ops.money_config_key('credential.app_ttl_interval'),
      ops.money_config_key('door.session_ttl_interval'),         ops.money_config_key('fee.buyer_service_bps'),
      ops.money_config_key('deletion.post_event_hold_hours'),    ops.money_config_key('ticket.expiry_grace'),
      ops.money_config_key('signing.expected_key_fingerprint'),  ops.money_config_key('notify.announcement_hold_seconds'),
      ops.money_config_key('door.manifest_ttl_interval'),        ops.money_config_key('inventory.hold_ttl_interval')])$q$),
  '[true,true,true,true,true,true,true,true,true,true,true,false,false,false]'::jsonb,
  'D2: true for every dual-control namespace; false for notify.*, door.manifest_* and inventory.*');

-- ── R — request (admin1 unless stated)
SELECT tap.login('26500000-0000-4000-8000-000000000101');
SELECT tap._aal265('aal2');
SELECT tap._store265('r1', tap._try265($q$SELECT ops.request_platform_config('refund.org_auto_execute_max_minor', '9000'::jsonb, 'raise_auto_cap', 'cmd-265-r1')$q$)::text);
SELECT is(
  (SELECT jsonb_build_object('status', r->>'status', 'has_id', (r->>'request_id') IS NOT NULL) FROM (SELECT tap._fetch265('r1')::jsonb AS r) x),
  '{"status":"parked","has_id":true}'::jsonb,
  'R1: a platform_admin at aal2 requesting a LOOSENING gets status parked with a request_id');
SELECT is(
  (SELECT jsonb_build_object('requested_by', a->>'requested_by', 'action', a->>'action', 'org_id', a->'org_id',
                             'state', a->>'state', 'reason', a->>'reason_code', 'key', a->'payload'->>'key',
                             'proposed', a->'payload'->'proposed_value', 'cmd', a->>'command_idempotency_key')
     FROM (SELECT tap._req265((tap._fetch265('r1')::jsonb->>'request_id')::uuid) AS a) x),
  '{"requested_by":"26500000-0000-4000-8000-000000000101","action":"config.set_money_key","org_id":null,"state":"pending","reason":"raise_auto_cap","key":"refund.org_auto_execute_max_minor","proposed":9000,"cmd":"cmd-265-r1"}'::jsonb,
  'R2: the parked request records the CALLER as requested_by (identity preserved through the INVOKER passthrough), platform-scoped, pending');
-- write and read in separate statements: sibling subqueries share the statement's snapshot and do not see
-- the call's writes
SELECT tap._store265('r3', tap._try265($q$SELECT ops.request_platform_config('refund.org_auto_execute_max_minor', '1000'::jsonb, 'lower_auto_cap', 'cmd-265-r3')$q$)::text);
SELECT is(
  jsonb_build_object('status', tap._fetch265('r3')::jsonb->>'status', 'top', tap._top265('refund.org_auto_execute_max_minor')),
  '{"status":"ok","top":{"version":3,"value":1000}}'::jsonb,
  'R3: a TIGHTENING applies at once (one human may tighten; RPC §20.2.1) — the passthrough returns set_platform_config''s answer unchanged');
SELECT tap._aal265('aal1');
SELECT is(
  (SELECT jsonb_build_object('err', r->>'error', 'step_up', (r->>'message') LIKE 'step_up_required:%', 'n', tap._nreq265() - tap._fetch265('n0')::integer)
     FROM (SELECT tap._try265($q$SELECT ops.request_platform_config('payout.request_auto_max_minor', '7000'::jsonb, 'x', 'cmd-265-r4')$q$) AS r) x),
  '{"err":"P0001","step_up":true,"n":1}'::jsonb,
  'R4: an aal1 session is refused step_up_required and parks nothing (only R1''s request exists)');
SELECT tap._aal265(NULL);
SELECT is(
  (SELECT (r->>'message') LIKE 'step_up_unavailable:%' FROM (SELECT tap._try265($q$SELECT ops.request_platform_config('payout.request_auto_max_minor', '7000'::jsonb, 'x', 'cmd-265-r5')$q$) AS r) x),
  true,
  'R5: a session without an aal claim is refused step_up_unavailable');
SELECT tap.login('26500000-0000-4000-8000-000000000103');
SELECT tap._aal265('aal2');
SELECT is(
  tap._try265($q$SELECT ops.request_platform_config('payout.request_auto_max_minor', '7000'::jsonb, 'x', 'cmd-265-r6')$q$),
  '{"error":"42501","message":"insufficient_privilege: platform_admin required (ops.request_platform_config)"}'::jsonb,
  'R6: platform_support at aal2 is refused by the WRAPPER''s own platform_admin gate');
SELECT tap.login('26500000-0000-4000-8000-000000000199');
SELECT tap._aal265('aal2');
SELECT is(
  tap._try265($q$SELECT ops.request_platform_config('payout.request_auto_max_minor', '7000'::jsonb, 'x', 'cmd-265-r7')$q$),
  '{"error":"42501","message":"insufficient_privilege: platform_admin required (ops.request_platform_config)"}'::jsonb,
  'R7: a user with no platform role is refused by the wrapper''s platform_admin gate');
SELECT tap.login('26500000-0000-4000-8000-000000000101');
SELECT tap._aal265('aal2');
SELECT is(
  (SELECT jsonb_build_object('invalid', (r->>'message') LIKE 'invalid_input: notify.announcement_hold_seconds is not a dual-control money key%',
                             'unchanged', tap._top265('notify.announcement_hold_seconds')::text = tap._fetch265('notify0'),
                             'n', tap._nreq265() - tap._fetch265('n0')::integer)
     FROM (SELECT tap._try265($q$SELECT ops.request_platform_config('notify.announcement_hold_seconds', '600'::jsonb, 'x', 'cmd-265-r8')$q$) AS r) x),
  '{"invalid":true,"unchanged":true,"n":1}'::jsonb,
  'R8: a non-money key is refused (invalid_input) and NOT written — set_platform_config would have applied it at once');
SELECT tap.login_anon();
SELECT is(
  tap._try265($q$SELECT ops.request_platform_config('payout.request_auto_max_minor', '7000'::jsonb, 'x', 'cmd-265-r9')$q$),
  '{"error":"42501","message":"permission denied for schema ops"}'::jsonb,
  'R9: anon is refused before the function (no USAGE on ops; and no EXECUTE, A2)');

-- a second parked request (payout key, still at its seed) for the approve path
SELECT tap.login('26500000-0000-4000-8000-000000000101');
SELECT tap._aal265('aal2');
SELECT tap._store265('r2', tap._try265($q$SELECT ops.request_platform_config('payout.request_auto_max_minor', '7000'::jsonb, 'set_payout_auto', 'cmd-265-r2')$q$)::text);

-- ── L — list
SELECT tap.login('26500000-0000-4000-8000-000000000102');
SELECT tap._aal265('aal2');
SELECT tap._store265('l_admin2', tap._try265($q$SELECT ops.list_config_approvals('pending')$q$)::text);
SELECT is(
  (SELECT jsonb_build_object('key', i->>'key', 'proposed', i->'proposed_value', 'by', i->>'requested_by',
                             'mine', i->'requested_by_me', 'can_decide', i->'can_decide', 'state', i->>'state',
                             'v_at', i->'version_at_request', 'val_at', i->'value_at_request')
     FROM jsonb_array_elements(tap._fetch265('l_admin2')::jsonb->'items') i
    WHERE i->>'request_id' = tap._fetch265('r1')::jsonb->>'request_id'),
  '{"key":"refund.org_auto_execute_max_minor","proposed":9000,"by":"26500000-0000-4000-8000-000000000101","mine":false,"can_decide":true,"state":"pending","v_at":2,"val_at":5000}'::jsonb,
  'L1: a second admin sees admin1''s pending request (key, proposed value, the value + version pinned at request time), can decide it');
SELECT is(
  (SELECT jsonb_build_object('changed', i->'key_changed_since_request', 'live_v', i->'live_version', 'live', i->'live_value')
     FROM jsonb_array_elements(tap._fetch265('l_admin2')::jsonb->'items') i
    WHERE i->>'request_id' = tap._fetch265('r1')::jsonb->>'request_id'),
  '{"changed":true,"live_v":3,"live":1000}'::jsonb,
  'L2: key_changed_since_request is true after R3''s tightening moved the key (pinned v2, live v3 = 1000)');
SELECT is(
  (SELECT jsonb_build_object(
     'has_refund', EXISTS (SELECT 1 FROM jsonb_array_elements(l->'money_keys') k WHERE k->>'key' = 'refund.org_auto_execute_max_minor' AND k->'value' = '1000'::jsonb AND (k->>'version')::int = 3),
     'has_notify', EXISTS (SELECT 1 FROM jsonb_array_elements(l->'money_keys') k WHERE k->>'key' = 'notify.announcement_hold_seconds'))
     FROM (SELECT tap._fetch265('l_admin2')::jsonb AS l) x),
  '{"has_refund":true,"has_notify":false}'::jsonb,
  'L3: money_keys carries each money key''s live version and value, and no non-money key');
SELECT is(
  (SELECT jsonb_build_object('items', jsonb_array_length(tap._fetch265('l_admin2')::jsonb->'items'),
                             'no_at', position('@' IN tap._fetch265('l_admin2')) = 0)),
  '{"items":2,"no_at":true}'::jsonb,
  'L4: the (non-empty) list carries no email — people are ids only');
SELECT tap.login('26500000-0000-4000-8000-000000000101');
SELECT tap._aal265('aal2');
SELECT is(
  (SELECT jsonb_build_object('mine', i->'requested_by_me', 'can_decide', i->'can_decide')
     FROM jsonb_array_elements(tap._try265($q$SELECT ops.list_config_approvals('pending')$q$)->'items') i
    WHERE i->>'request_id' = tap._fetch265('r1')::jsonb->>'request_id'),
  '{"mine":true,"can_decide":false}'::jsonb,
  'L5: the requester sees requested_by_me = true and can_decide = false on their own request');
SELECT tap.login('26500000-0000-4000-8000-000000000103');
SELECT tap._aal265('aal2');
SELECT is(
  (SELECT r->>'error' FROM (SELECT tap._try265($q$SELECT ops.list_config_approvals('pending')$q$) AS r) x),
  '42501',
  'L6: platform_support is refused (platform_admin only)');
SELECT tap.login('26500000-0000-4000-8000-000000000199');
SELECT tap._aal265('aal2');
SELECT is(
  (SELECT r->>'error' FROM (SELECT tap._try265($q$SELECT ops.list_config_approvals('pending')$q$) AS r) x),
  '42501',
  'L7: a user with no platform role is refused');
SELECT tap.login('26500000-0000-4000-8000-000000000102');
SELECT tap._aal265('aal1');
SELECT is(
  (SELECT (r->>'message') LIKE 'step_up_required:%' FROM (SELECT tap._try265($q$SELECT ops.list_config_approvals('pending')$q$) AS r) x),
  true,
  'L8: an aal1 admin session is refused step_up_required');
SELECT tap._aal265('aal2');
SELECT is(
  (SELECT (r->>'message') LIKE 'invalid_input: state must be%' FROM (SELECT tap._try265($q$SELECT ops.list_config_approvals('bogus')$q$) AS r) x),
  true,
  'L9: an unknown state filter is refused');

-- ── P — decide through the existing kernel verb
SELECT tap.login('26500000-0000-4000-8000-000000000101');
SELECT tap._aal265('aal2');
SELECT is(
  (SELECT jsonb_build_object('self', (r->>'message') LIKE 'self_approval:%', 'state', tap._req265((tap._fetch265('r2')::jsonb->>'request_id')::uuid)->>'state')
     FROM (SELECT tap._try265(format('SELECT kernel.approve_refund_request(%L, ''approve'', null, ''cmd-265-p1'')', tap._fetch265('r2')::jsonb->>'request_id')) AS r) x),
  '{"self":true,"state":"pending"}'::jsonb,
  'P1: the requester cannot approve their own request (self_approval); it stays pending');
SELECT tap.login('26500000-0000-4000-8000-000000000102');
SELECT tap._aal265('aal1');
SELECT is(
  (SELECT (r->>'message') LIKE 'step_up_required:%' FROM (SELECT tap._try265(format('SELECT kernel.approve_refund_request(%L, ''approve'', null, ''cmd-265-p2'')', tap._fetch265('r2')::jsonb->>'request_id')) AS r) x),
  true,
  'P2: a second admin at aal1 cannot approve (step_up_required)');
SELECT tap._aal265('aal2');
SELECT tap._store265('p3', tap._try265(format('SELECT kernel.approve_refund_request(%L, ''approve'', ''ok_second_founder'', ''cmd-265-p3'')', tap._fetch265('r2')::jsonb->>'request_id'))::text);
SELECT is(
  jsonb_build_object('status', tap._fetch265('p3')::jsonb->>'status', 'top', tap._top265('payout.request_auto_max_minor')),
  '{"status":"approved","top":{"version":2,"value":7000}}'::jsonb,
  'P3: a distinct admin at aal2 approves; the proposed value becomes the next version of the key');
SELECT is(
  (SELECT jsonb_build_object('state', i->>'state', 'decided_by', i->>'decided_by', 'can_decide', i->'can_decide')
     FROM jsonb_array_elements(tap._try265($q$SELECT ops.list_config_approvals('approved')$q$)->'items') i
    WHERE i->>'request_id' = tap._fetch265('r2')::jsonb->>'request_id'),
  '{"state":"approved","decided_by":"26500000-0000-4000-8000-000000000102","can_decide":false}'::jsonb,
  'P4: the approved request lists under approved, decided_by = the second admin, no longer decidable');
SELECT tap._store265('p5', tap._try265(format('SELECT kernel.approve_refund_request(%L, ''deny'', ''key_moved_since'', ''cmd-265-p5'')', tap._fetch265('r1')::jsonb->>'request_id'))::text);
SELECT is(
  jsonb_build_object('status', tap._fetch265('p5')::jsonb->>'status', 'state', tap._req265((tap._fetch265('r1')::jsonb->>'request_id')::uuid)->>'state',
                     'top', tap._top265('refund.org_auto_execute_max_minor')),
  '{"status":"denied","state":"denied","top":{"version":3,"value":1000}}'::jsonb,
  'P5: a second admin denies the stale-pinned request; the key keeps its live value');
SELECT is(
  (SELECT jsonb_build_object('all', jsonb_array_length(l->'items'), 'pending', (SELECT count(*) FROM jsonb_array_elements(l->'items') i WHERE i->>'state' = 'pending'),
                             'state', l->>'state')
     FROM (SELECT tap._try265($q$SELECT ops.list_config_approvals('all')$q$) AS l) x),
  '{"all":2,"pending":0,"state":"all"}'::jsonb,
  'P6: state ''all'' returns both money-key requests (one approved, one denied), none pending');

SELECT * FROM finish();
ROLLBACK;
