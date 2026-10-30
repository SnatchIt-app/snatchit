-- ============================================================================
-- 190_sync_scan_device_manifest_open_unexpired.sql — migration 125 (086↔112/113
-- scanning-contract correction). venue.sync_scan_device_manifest binds a scan
-- device ONLY to the episode venue.get_door_manifest reports open:true
-- (status='open' AND not_after > now(), 112/113 / door §7.5) and to exactly the
-- manifest it returned; an expired-but-open, closed or absent episode leaves the
-- device row untouched and returns open:false. Signature, VOLATILE/definer/
-- search_path shape, grants and the 086 authorization are unchanged. The
-- regression pins the definition (A), the shape (B), the observable contract
-- including the corrected expired-but-open case (C), authorization (D) and the
-- census (E). now() is frozen for the suite transaction, so windows are
-- backdated with the transition guard disabled as superuser (as in 178 §F).
-- ============================================================================
BEGIN;
SELECT plan(30);
SELECT tap.seed_core();

CREATE TABLE tap.memo_190 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store190(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_190 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch190(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_190 WHERE k=$1 $m$;
SELECT tap._store190('def', pg_get_functiondef('venue.sync_scan_device_manifest(uuid,uuid,integer)'::regprocedure));

-- ── FIXTURE — venue (approved), seller = venue_manager, other_user = venue_scanner,
-- one event/session, one registered scan device. No atoms needed (entry_count 0). ──
SELECT tap.login(tap.seller());
SELECT tap._store190('org', (kernel.create_organization('SD Co','SD Co','sd190-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch190('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store190('venue', (catalog.create_venue(tap._fetch190('org')::uuid,'SD Hall','wynwood',NULL,'sd190-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch190('venue')::uuid,'approved','miami_gate','sd190-a');
SELECT tap.logout();
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch190('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()),
       (tap._fetch190('venue')::uuid, tap.other_user(), 'venue_scanner', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store190('e', (catalog.create_event(tap._fetch190('venue')::uuid,'SD Night',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'sd190-e') ->> 'event_id'));
SELECT tap._store190('s', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch190('e')::uuid));
SELECT tap._store190('dev', (venue.register_scan_device(tap._fetch190('venue')::uuid, 'scanner-190', 'sd190-dev') ->> 'device_id'));
SELECT tap.logout();

-- ── A. definition (125) ──────────────────────────────────────────────────────
SELECT has_function('venue'::name, 'sync_scan_device_manifest'::name, ARRAY['uuid','uuid','integer']::name[], 'A1: venue.sync_scan_device_manifest(uuid,uuid,integer) exists (same signature as 086)');
SELECT ok(tap._fetch190('def') ~ 'v_res := venue\.get_door_manifest\(p_session_id, 0\)', 'A2: the episode comes from the M2 contract read (venue.get_door_manifest), one read');
SELECT ok(tap._fetch190('def') ~ 'manifest_id\s+= \(v_res ->> ''manifest_id''\)::uuid' AND tap._fetch190('def') ~ '\(v_res ->> ''open''\)::boolean',
  'A3: the device is bound from the returned payload, only when it reports open:true');
SELECT ok(tap._fetch190('def') !~ 'from venue\.door_manifest where session_id = p_session_id and status = ''open''',
  'A4: the 086 status=open-only episode select is gone');
SELECT ok(obj_description('venue.sync_scan_device_manifest(uuid,uuid,integer)'::regprocedure, 'pg_proc') LIKE '%125: the device is bound%',
  'A5: the comment records the 125 change');

-- ── B. shape and grants unchanged from 086 ───────────────────────────────────
SELECT ok(has_function_privilege('authenticated', 'venue.sync_scan_device_manifest(uuid,uuid,integer)', 'EXECUTE'), 'B1: authenticated keeps EXECUTE (caller-authorized verb, RLS §11.1)');
SELECT ok(NOT has_function_privilege('service_role', 'venue.sync_scan_device_manifest(uuid,uuid,integer)', 'EXECUTE'), 'B2: service_role has no EXECUTE (unchanged; the door path is not this function)');
SELECT ok(NOT has_function_privilege('anon', 'venue.sync_scan_device_manifest(uuid,uuid,integer)', 'EXECUTE'), 'B3: anon has no EXECUTE (unchanged)');
SELECT ok((SELECT p.prosecdef AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 'v' AND (p.prorettype::regtype)::text = 'jsonb'
             FROM pg_proc p WHERE p.oid = 'venue.sync_scan_device_manifest(uuid,uuid,integer)'::regprocedure),
  'B4: SECURITY DEFINER, search_path pinned, VOLATILE, returns jsonb (unchanged)');

-- ── C. observable contract ───────────────────────────────────────────────────
SELECT is((SELECT manifest_id IS NULL AND manifest_version IS NULL AND last_sync_at IS NULL FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid), true,
  'C0: a freshly registered device carries no binding');

-- C1–C4: open, unexpired episode v1 → bound to exactly the returned manifest.
SELECT tap.login(tap.seller());
SELECT tap._store190('m1', (venue.open_door_manifest(tap._fetch190('s')::uuid,'doors_open','sd190-d1') ->> 'manifest_id'));
SELECT tap.login(tap.other_user());
SELECT tap._store190('r1', venue.sync_scan_device_manifest(tap._fetch190('dev')::uuid, tap._fetch190('s')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch190('r1')::jsonb ->> 'open'), 'true', 'C1: open, unexpired episode → payload open:true');
SELECT is((tap._fetch190('r1')::jsonb ->> 'manifest_version'), '1', 'C2: …manifest_version 1');
SELECT is((SELECT manifest_id::text || '/' || manifest_version::text FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid),
  (tap._fetch190('r1')::jsonb ->> 'manifest_id') || '/1', 'C3: the device is bound to EXACTLY the manifest_id/version the payload returned');
SELECT is((SELECT last_sync_at FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid), now(), 'C4: last_sync_at stamped');

-- sentinel: backdate the stamp (superuser) so "untouched" is observable under a frozen now().
UPDATE venue.scan_device SET last_sync_at = now() - interval '10 minutes' WHERE device_id = tap._fetch190('dev')::uuid;

-- C5–C6: closed episode → open:false, binding untouched (086 behaviour preserved).
SELECT tap.login(tap.seller());
SELECT venue.close_door_manifest(tap._fetch190('s')::uuid, 'doors_closed', 'sd190-c1');
SELECT tap.login(tap.other_user());
SELECT tap._store190('r2', venue.sync_scan_device_manifest(tap._fetch190('dev')::uuid, tap._fetch190('s')::uuid, 1)::text);
SELECT tap.logout();
SELECT is((tap._fetch190('r2')::jsonb ->> 'open') || '/' || (tap._fetch190('r2')::jsonb ->> 'status'), 'false/no_open_episode', 'C5: closed episode → open:false / no_open_episode (not an error)');
SELECT is((SELECT manifest_id::text || '/' || manifest_version::text || '/' || (last_sync_at = now() - interval '10 minutes')::text FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid),
  tap._fetch190('m1') || '/1/true', 'C6: …device binding and last_sync_at untouched');

-- C7–C11: THE CORRECTION — expired-but-still-open episode v2 → open:false, device NOT bound.
SELECT tap.login(tap.seller());
SELECT tap._store190('m2', (venue.open_door_manifest(tap._fetch190('s')::uuid,'doors_open','sd190-d2') ->> 'manifest_id'));
SELECT tap.logout();
ALTER TABLE venue.door_manifest DISABLE TRIGGER tg_door_manifest_transition;
UPDATE venue.door_manifest SET opened_at = now() - interval '3 hours', not_after = now() - interval '1 second' WHERE manifest_id = tap._fetch190('m2')::uuid;
ALTER TABLE venue.door_manifest ENABLE TRIGGER tg_door_manifest_transition;
SELECT tap.login(tap.other_user());
SELECT tap._store190('r3', venue.sync_scan_device_manifest(tap._fetch190('dev')::uuid, tap._fetch190('s')::uuid, 1)::text);
SELECT tap.logout();
SELECT is((tap._fetch190('r3')::jsonb ->> 'open') || '/' || (tap._fetch190('r3')::jsonb ->> 'status'), 'false/no_open_episode',
  'C7: an episode past its STORED not_after (status still open) → open:false, the same answer 112/113 give');
SELECT is((SELECT manifest_id::text || '/' || manifest_version::text FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid),
  tap._fetch190('m1') || '/1', 'C8: …the device is NOT bound to the expired episode (086 bound it: m2/2)');
SELECT is((SELECT last_sync_at = now() - interval '10 minutes' FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid), true, 'C9: …last_sync_at untouched');
SELECT is((SELECT status || '/' || (not_after < now())::text FROM venue.door_manifest WHERE manifest_id = tap._fetch190('m2')::uuid), 'open/true',
  'C10: …the door_manifest row itself is untouched (status open, not_after still in the past; nothing written)');
SELECT ok(NOT (tap._fetch190('r3')::jsonb ? 'manifest_id') AND jsonb_array_length(tap._fetch190('r3')::jsonb -> 'entries') = 0,
  'C11: …the expired result carries no header and no entries (nothing to bind authority to)');

-- C12–C15: a fresh episode v3 after the expired one is closed → bound again; repeat sync idempotent.
SELECT tap.login(tap.seller());
SELECT venue.close_door_manifest(tap._fetch190('s')::uuid, 'doors_closed', 'sd190-c2');
SELECT tap._store190('m3', (venue.open_door_manifest(tap._fetch190('s')::uuid,'doors_open','sd190-d3') ->> 'manifest_id'));
SELECT tap.login(tap.other_user());
SELECT tap._store190('r4', venue.sync_scan_device_manifest(tap._fetch190('dev')::uuid, tap._fetch190('s')::uuid, 2)::text);
SELECT tap._store190('r5', venue.sync_scan_device_manifest(tap._fetch190('dev')::uuid, tap._fetch190('s')::uuid, 3)::text);
SELECT tap.logout();
SELECT is((tap._fetch190('r4')::jsonb ->> 'open') || '/' || (tap._fetch190('r4')::jsonb ->> 'manifest_version'), 'true/3', 'C12: the fresh episode v3 is open');
SELECT is((SELECT manifest_id::text || '/' || manifest_version::text FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid),
  tap._fetch190('m3') || '/3', 'C13: …device re-bound to m3/3');
SELECT is((SELECT last_sync_at FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid), now(), 'C14: …last_sync_at re-stamped');
SELECT is((tap._fetch190('r5')::jsonb ->> 'manifest_id') || '/' || (SELECT manifest_id::text FROM venue.scan_device WHERE device_id = tap._fetch190('dev')::uuid),
  tap._fetch190('m3') || '/' || tap._fetch190('m3'), 'C15: a repeat sync is idempotent (same manifest, same binding)');

-- ── D. authorization unchanged from 086 ──────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(format('SELECT venue.sync_scan_device_manifest(%L::uuid, %L::uuid, 3)', tap._fetch190('dev'), tap._fetch190('s')), '42501',
  NULL, 'D1: a caller without a venue role is refused 42501 (device-venue gate)');
SELECT tap.login(tap.other_user());
SELECT throws_ok(format('SELECT venue.sync_scan_device_manifest(%L::uuid, %L::uuid, 3)', gen_random_uuid()::text, tap._fetch190('s')), 'P0002',
  NULL, 'D2: an unknown device is not_found (P0002)');
SELECT tap.login(tap.seller());
SELECT is((venue.sync_scan_device_manifest(tap._fetch190('dev')::uuid, tap._fetch190('s')::uuid, 3) ->> 'open'), 'true', 'D3: venue_manager may sync (unchanged)');
SELECT tap.logout();

-- ── E. census / identity ─────────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue' AND p.proname = 'sync_scan_device_manifest'), 1,
  'E1: exactly one venue.sync_scan_device_manifest (body-only replace; census 0)');
SELECT is((SELECT count(*)::int FROM venue.door_manifest WHERE session_id = tap._fetch190('s')::uuid AND status = 'open'), 1,
  'E2: exactly one open episode remains (v3); the read never wrote door_manifest');

SELECT * FROM finish();
ROLLBACK;
