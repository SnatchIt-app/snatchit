-- ============================================================================
-- 180_signing_key_door_delivery_and_manifest_signing_context.sql — migration 114.
--   venue.get_signing_keys_door: a bearer-only door device reads M1 for its
--   BOUND scope (global + its event's per_event + its venue's per_venue, all
--   statuses incl. rotating/revoked/future) as exactly the PFA-16+103 public
--   projection — never kms_handle_ref, never unrelated rows; invalid door
--   sessions and direct anon/authenticated/service_role-without-credentials
--   calls are refused. venue.get_manifest_signing_context: the single active
--   global key's identity (key_id + kms_handle_ref + ES256 + public_key) for the
--   door-manifest edge; fails closed with stable codes when there is none; the
--   staff/client projection and grants on kernel.signing_key are unchanged; the
--   census moved by exactly two.
-- ============================================================================
BEGIN;
SELECT plan(42);
SELECT tap.seed_core();

CREATE TABLE tap.memo_180 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store180(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_180 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch180(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_180 WHERE k=$1 $m$;

-- ── FIXTURE — venue A (approved) + venue B; event A (bound) + event B (unrelated);
-- device, PIN, minted door session on A; keys: 3 global (active / rotating-expired
-- / revoked), per_event A (active), per_event A (future not_before), per_event B
-- (UNRELATED), per_venue A, per_venue B (UNRELATED). The future-window row is
-- `rotating` (one ACTIVE per event, signing_key_active_event_uq). ─────────────
SELECT tap.login(tap.seller());
SELECT tap._store180('org', (kernel.create_organization('KD Co','KD Co','kd180-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch180('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store180('venue', (catalog.create_venue(tap._fetch180('org')::uuid,'KD Hall','wynwood',NULL,'kd180-v') ->> 'venue_id'));
SELECT tap._store180('venueB', (catalog.create_venue(tap._fetch180('org')::uuid,'KD Annex','wynwood',NULL,'kd180-vB') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch180('venue')::uuid,'approved','miami_gate','kd180-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch180('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()),
       (tap._fetch180('venue')::uuid, tap.other_user(), 'venue_scanner', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store180('eA', (catalog.create_event(tap._fetch180('venue')::uuid,'KD A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'kd180-eA') ->> 'event_id'));
SELECT tap._store180('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch180('eA')::uuid));
SELECT tap._store180('eB', (catalog.create_event(tap._fetch180('venue')::uuid,'KD B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'kd180-eB') ->> 'event_id'));
SELECT tap._store180('dev', (venue.register_scan_device(tap._fetch180('venue')::uuid, 'scanner-180', 'kd180-dev') ->> 'device_id'));
SELECT tap._store180('pin', (venue.create_door_pin(tap._fetch180('venue')::uuid, tap._fetch180('sA')::uuid, 'front', 'pin-180', (now()+interval '1 day'), 'kd180-pin') ->> 'pin_id'));
SELECT tap.logout();
-- keys (insert guard disabled by seed_core for the fixture; placeholder PEM text)
WITH k AS (INSERT INTO kernel.signing_key (scope, public_key, kms_handle_ref, status, not_before, not_after, algorithm)
  VALUES ('global', 'PEM-G-ACTIVE', 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b01', 'active', now() - interval '1 hour', NULL, 'ES256') RETURNING key_id)
SELECT tap._store180('g_active', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, public_key, kms_handle_ref, status, not_before, not_after, algorithm)
  VALUES ('global', 'PEM-G-ROTATING', 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b02', 'rotating', now() - interval '30 days', now() - interval '1 day', 'ES256') RETURNING key_id)
SELECT tap._store180('g_rotating', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, public_key, kms_handle_ref, status, not_before, not_after, algorithm)
  VALUES ('global', 'PEM-G-REVOKED', 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b03', 'revoked', now() - interval '60 days', now() - interval '30 days', 'ES256') RETURNING key_id)
SELECT tap._store180('g_revoked', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch180('eA')::uuid, 'PEM-E-ACTIVE', 'kms-180-eA', 'active', now() - interval '1 hour', 'ES256') RETURNING key_id)
SELECT tap._store180('e_active', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch180('eA')::uuid, 'PEM-E-FUTURE', 'kms-180-eA-future', 'rotating', now() + interval '1 day', 'ES256') RETURNING key_id)   -- rotating: signing_key_active_event_uq allows ONE active per event
SELECT tap._store180('e_future', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch180('eB')::uuid, 'PEM-E-OTHER', 'kms-180-eB', 'active', now() - interval '1 hour', 'ES256') RETURNING key_id)
SELECT tap._store180('e_other', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, venue_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_venue', tap._fetch180('venue')::uuid, 'PEM-V-A', 'kms-180-vA', 'active', now() - interval '1 hour', 'ES256') RETURNING key_id)
SELECT tap._store180('v_venue', (SELECT key_id::text FROM k));
WITH k AS (INSERT INTO kernel.signing_key (scope, venue_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_venue', tap._fetch180('venueB')::uuid, 'PEM-V-B', 'kms-180-vB', 'active', now() - interval '1 hour', 'ES256') RETURNING key_id)
SELECT tap._store180('v_other', (SELECT key_id::text FROM k));
SELECT tap.login_service();
SELECT tap._store180('mint', (venue.mint_door_session(tap._fetch180('venue')::uuid, tap._fetch180('sA')::uuid, tap._fetch180('dev')::uuid, 'pin-180', 'kd180-mint')::text));
SELECT tap._store180('dsid', (tap._fetch180('mint')::jsonb ->> 'door_session_id'));
SELECT tap._store180('secret', (tap._fetch180('mint')::jsonb ->> 'secret'));
SELECT tap.logout();

-- ── A. grants / invariants / census / staff projection unchanged ────────────
SELECT ok(has_function_privilege('service_role', 'venue.get_signing_keys_door(uuid,uuid,text,uuid)', 'EXECUTE')
      AND has_function_privilege('service_role', 'venue.get_manifest_signing_context()', 'EXECUTE'),
  'A1: service_role may EXECUTE both machine functions');
SELECT ok(NOT has_function_privilege('authenticated', 'venue.get_signing_keys_door(uuid,uuid,text,uuid)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.get_signing_keys_door(uuid,uuid,text,uuid)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'venue.get_manifest_signing_context()', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.get_manifest_signing_context()', 'EXECUTE'),
  'A2: authenticated and anon hold NO EXECUTE on either');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE n.nspname='venue' AND p.proname IN ('get_signing_keys_door','get_manifest_signing_context')
              AND a.privilege_type='EXECUTE' AND a.grantee = 0),
  'A3: PUBLIC holds NO EXECUTE on either (explicitly revoked)');
SELECT is((SELECT count(*)::int FROM pg_proc p WHERE p.oid IN ('venue.get_signing_keys_door(uuid,uuid,text,uuid)'::regprocedure,
             'venue.get_manifest_signing_context()'::regprocedure) AND p.prosecdef AND p.proconfig::text LIKE '%search_path=%'), 2,
  'A4: both SECURITY DEFINER with pinned search_path (066 invariant)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue'), 87,
  'A5: venue holds 87 functions — 85 post-113 + 114''s two');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 296,
  'A6: five-schema routine census 296 (294 post-113 + 114''s two)');
SELECT is((SELECT array_agg(column_name::text ORDER BY column_name) FROM information_schema.column_privileges
            WHERE table_schema='kernel' AND table_name='signing_key' AND grantee='authenticated' AND privilege_type='SELECT'),
  ARRAY['algorithm','event_id','key_id','not_after','not_before','public_key','scope','status','venue_id'],
  'A7: the STAFF/CLIENT projection is unchanged — authenticated SELECT on exactly the 9 public columns (083 + 103), never kms_handle_ref');
SELECT ok(NOT has_table_privilege('service_role', 'kernel.signing_key', 'SELECT'), 'A8: service_role still has no direct SELECT on kernel.signing_key (reads go through the definer functions)');
SELECT ok(EXISTS (SELECT 1 FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relname='signing_key' AND p.polname='kernel_signing_key_sel_public'),
  'A9: the PFA-16 public-projection policy is untouched');

-- ── B. M1 door read — valid bound device ────────────────────────────────────
SELECT tap.login_service();
SELECT tap._store180('m1', venue.get_signing_keys_door(tap._fetch180('sA')::uuid, tap._fetch180('dsid')::uuid, tap._fetch180('secret'), tap._fetch180('dev')::uuid)::text);
SELECT tap.logout();
SELECT is((tap._fetch180('m1')::jsonb ->> 'session_id'), tap._fetch180('sA'), 'B1: bound session echoed');
SELECT is((tap._fetch180('m1')::jsonb ->> 'event_id'), tap._fetch180('eA'), 'B2: bound event');
SELECT is((tap._fetch180('m1')::jsonb ->> 'venue_id'), tap._fetch180('venue'), 'B3: bound venue');
SELECT is(jsonb_array_length(tap._fetch180('m1')::jsonb -> 'keys'), 6, 'B4: exactly six rows — 3 global + 2 per_event(A) + 1 per_venue(A)');
SELECT is((SELECT array_agg(k ->> 'key_id' ORDER BY k ->> 'key_id') FROM jsonb_array_elements(tap._fetch180('m1')::jsonb -> 'keys') k),
  (SELECT array_agg(v ORDER BY v) FROM tap.memo_180 WHERE k IN ('g_active','g_rotating','g_revoked','e_active','e_future','v_venue')),
  'B5: …and they are exactly the six in-scope keys (rotating, revoked and future rows INCLUDED)');
SELECT ok(NOT (tap._fetch180('m1') LIKE '%' || tap._fetch180('e_other') || '%') AND NOT (tap._fetch180('m1') LIKE '%' || tap._fetch180('v_other') || '%'),
  'B6: the unrelated event''s and venue''s keys are NOT returned');
SELECT is((SELECT array_agg(DISTINCT (SELECT array_agg(f ORDER BY f) FROM jsonb_object_keys(k) f)::text) FROM jsonb_array_elements(tap._fetch180('m1')::jsonb -> 'keys') k),
  ARRAY['{algorithm,event_id,key_id,not_after,not_before,public_key,scope,status,venue_id}'],
  'B7: every row is EXACTLY the 9-field public projection');
SELECT ok(NOT (tap._fetch180('m1') LIKE '%kms_handle_ref%') AND NOT (tap._fetch180('m1') LIKE '%arn:aws:kms%') AND NOT (tap._fetch180('m1') LIKE '%kms-180%'),
  'B8: no KMS handle / ARN leaks (none of the fixture handles appears in the response)');
SELECT is((SELECT array_agg(DISTINCT k ->> 'status' ORDER BY k ->> 'status') FROM jsonb_array_elements(tap._fetch180('m1')::jsonb -> 'keys') k),
  ARRAY['active','revoked','rotating'], 'B9: statuses active/rotating/revoked all present (the verifier applies key_revoked/key_window, not the RPC)');
SELECT ok((SELECT bool_and(k ->> 'algorithm' = 'ES256') FROM jsonb_array_elements(tap._fetch180('m1')::jsonb -> 'keys') k), 'B10: algorithm carried per row (103)');

-- ── C. M1 door read — invalid door sessions / direct callers ────────────────
SELECT tap.login_service();
SELECT throws_like(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, tap._fetch180('sA'), tap._fetch180('dsid'), 'not-the-secret', tap._fetch180('dev')),
  '%door_session_invalid%', 'C1: wrong token ⇒ door_session_invalid');
SELECT throws_like(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, tap._fetch180('sA'), tap._fetch180('dsid'), tap._fetch180('secret'), gen_random_uuid()),
  '%door_session_invalid%', 'C2: wrong device ⇒ door_session_invalid');
SELECT throws_like(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, gen_random_uuid(), tap._fetch180('dsid'), tap._fetch180('secret'), tap._fetch180('dev')),
  '%door_session_invalid%', 'C3: wrong session ⇒ door_session_invalid (scope cannot be picked by the caller)');
SELECT throws_like(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, tap._fetch180('sA'), gen_random_uuid(), '', gen_random_uuid()),
  '%door_session_invalid%', 'C4: service_role without valid door credentials ⇒ refused');
SELECT tap.login_anon();
SELECT throws_ok(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, tap._fetch180('sA'), tap._fetch180('dsid'), tap._fetch180('secret'), tap._fetch180('dev')),
  '42501', NULL, 'C5: anon cannot call it even with VALID door credentials');
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, tap._fetch180('sA'), tap._fetch180('dsid'), tap._fetch180('secret'), tap._fetch180('dev')),
  '42501', NULL, 'C6: authenticated staff cannot call it even with VALID door credentials (grant class)');
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 8, 'C7: …the STAFF path is unchanged: authenticated still reads the full public projection directly (all 8 fixture rows)');
SELECT throws_ok($q$SELECT kms_handle_ref FROM kernel.signing_key LIMIT 1$q$, '42501', NULL, 'C8: …and still cannot read kms_handle_ref');
SELECT tap.logout();

-- ── D. manifest signing context ─────────────────────────────────────────────
SELECT tap.login_service();
SELECT tap._store180('ctx', venue.get_manifest_signing_context()::text);
SELECT tap.logout();
SELECT is((tap._fetch180('ctx')::jsonb ->> 'status'), 'ok', 'D1: context available');
SELECT is((tap._fetch180('ctx')::jsonb ->> 'key_id'), tap._fetch180('g_active'), 'D2: key_id = the single ACTIVE GLOBAL key — the same row M1 lists');
SELECT is((tap._fetch180('ctx')::jsonb ->> 'kms_handle_ref'), 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b01', 'D3: kms_handle_ref from the SAME row (a handle, not material)');
SELECT is((tap._fetch180('ctx')::jsonb ->> 'algorithm'), 'ES256', 'D4: algorithm ES256');
SELECT is((tap._fetch180('ctx')::jsonb ->> 'public_key'), 'PEM-G-ACTIVE', 'D5: public_key from the same row (the edge verifies every signature under it)');
SELECT is((tap._fetch180('ctx')::jsonb ->> 'key_status'), 'active', 'D6: key_status active');
SELECT ok(EXISTS (SELECT 1 FROM jsonb_array_elements(tap._fetch180('m1')::jsonb -> 'keys') k WHERE k ->> 'key_id' = tap._fetch180('ctx')::jsonb ->> 'key_id' AND k ->> 'public_key' = tap._fetch180('ctx')::jsonb ->> 'public_key'),
  'D7: ONE authority — the context''s key_id/public_key are byte-identical to the M1 row a door device receives');
SELECT tap.login_anon();
SELECT throws_ok($q$SELECT venue.get_manifest_signing_context()$q$, '42501', NULL, 'D8: anon cannot call the context');
SELECT tap.login(tap.other_user());
SELECT throws_ok($q$SELECT venue.get_manifest_signing_context()$q$, '42501', NULL, 'D9: authenticated cannot call the context (kms_handle_ref stays fenced)');
SELECT tap.logout();
-- no active global key: the active key moves to rotating (forward-only status; guard permits) ⇒ unavailable, stable code
UPDATE kernel.signing_key SET status = 'rotating' WHERE key_id = tap._fetch180('g_active')::uuid;
SELECT tap.login_service();
SELECT tap._store180('ctx2', venue.get_manifest_signing_context()::text);
SELECT tap._store180('m1b', venue.get_signing_keys_door(tap._fetch180('sA')::uuid, tap._fetch180('dsid')::uuid, tap._fetch180('secret'), tap._fetch180('dev')::uuid)::text);
SELECT tap.logout();
SELECT is((tap._fetch180('ctx2')::jsonb ->> 'status'), 'unavailable', 'D10: with no ACTIVE global key the context is unavailable (fail closed; the edge never signs)');
SELECT is((tap._fetch180('ctx2')::jsonb ->> 'code'), 'no_active_global_key', 'D11: …stable code no_active_global_key');
SELECT ok(NOT (tap._fetch180('ctx2')::jsonb ? 'kms_handle_ref'), 'D12: …and carries no handle');
SELECT is((SELECT k ->> 'status' FROM jsonb_array_elements(tap._fetch180('m1b')::jsonb -> 'keys') k WHERE k ->> 'key_id' = tap._fetch180('g_active')), 'rotating',
  'D13: M1 now reports that key rotating — a verifier keeps accepting in-window signatures made under it (rotation rule), the edge stops making new ones');

-- ── E. revoked door session ⇒ the M1 read is refused ────────────────────────
SELECT tap.login(tap.seller());
SELECT is((venue.revoke_door_session(tap._fetch180('dsid')::uuid, 'operator_revoked', 'kd180-rv') ->> 'status'), 'ok', 'E1: revoke the door session');
SELECT tap.login_service();
SELECT throws_like(format($q$SELECT venue.get_signing_keys_door(%L,%L,%L,%L)$q$, tap._fetch180('sA'), tap._fetch180('dsid'), tap._fetch180('secret'), tap._fetch180('dev')),
  '%door_session_invalid%', 'E2: a revoked door session cannot read M1');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
