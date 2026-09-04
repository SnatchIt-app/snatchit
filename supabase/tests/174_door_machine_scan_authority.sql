-- ============================================================================
-- 174_door_machine_scan_authority.sql — migration 108.
--   The service_role machine path (record_scan_door / reconcile_offline_scans_door):
--   the door session is the sole authority and DECIDES SCOPE. A body device/session
--   override is caught at assert_door_session; scan_meta.device_id is rejected; the
--   scan is device-attributed; a door session for session A cannot admit session B's
--   atom; the machine entrypoints are service_role-only; reconcile isolates a
--   wrong-session item and dedupes a repeat admit.
-- ============================================================================
BEGIN;
SELECT plan(11);
SELECT tap.seed_core();

CREATE TABLE tap.memo_174 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store174(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_174 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch174(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_174 WHERE k=$1 $m$;

-- ── FIXTURE — venue(approved), event A (3 atoms) + event B (1 atom), device,
-- PIN, minted door session on A, native scanning ON. ─────────────────────────
SELECT tap.login(tap.seller());
SELECT tap._store174('org', (kernel.create_organization('MK Co','MK Co','ck174-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch174('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store174('venue', (catalog.create_venue(tap._fetch174('org')::uuid,'MK Hall','wynwood',NULL,'ck174-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch174('venue')::uuid,'approved','miami_gate','ck174-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch174('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;

SELECT tap.login(tap.seller());
SELECT tap._store174('eA', (catalog.create_event(tap._fetch174('venue')::uuid,'MK A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck174-eA') ->> 'event_id'));
SELECT tap._store174('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch174('eA')::uuid));
SELECT tap._store174('ttA', (venue.create_ticket_type(tap._fetch174('eA')::uuid,'admission','GA',5000,'public','ck174-ttA') ->> 'ticket_type_id'));
SELECT tap._store174('bA', (venue.create_inventory_batch(tap._fetch174('ttA')::uuid, tap._fetch174('sA')::uuid, 'comp', 100, 0, 'ck174-bA') ->> 'batch_id'));
SELECT tap._store174('eB', (catalog.create_event(tap._fetch174('venue')::uuid,'MK B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck174-eB') ->> 'event_id'));
SELECT tap._store174('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch174('eB')::uuid));
SELECT tap._store174('ttB', (venue.create_ticket_type(tap._fetch174('eB')::uuid,'admission','GA',5000,'public','ck174-ttB') ->> 'ticket_type_id'));
SELECT tap._store174('bB', (venue.create_inventory_batch(tap._fetch174('ttB')::uuid, tap._fetch174('sB')::uuid, 'comp', 100, 0, 'ck174-bB') ->> 'batch_id'));
SELECT tap._store174('dev', (venue.register_scan_device(tap._fetch174('venue')::uuid, 'scanner-174', 'ck174-dev') ->> 'device_id'));
SELECT tap._store174('pin', (venue.create_door_pin(tap._fetch174('venue')::uuid, tap._fetch174('sA')::uuid, 'front', 'pin-174', (now()+interval '1 day'), 'ck174-pin') ->> 'pin_id'));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch174('eA')::uuid, 'PUBKEY-174A', 'kms-174A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store174('kA', (SELECT key_id::text FROM kA));
WITH kB AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch174('eB')::uuid, 'PUBKEY-174B', 'kms-174B', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store174('kB', (SELECT key_id::text FROM kB));
SELECT tap._store174('mA', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch174('sA')::uuid,'org_id',tap._fetch174('org')::uuid,'ticket_type_id',tap._fetch174('ttA')::uuid,
  'batch_id',tap._fetch174('bA')::uuid,'owner_id',tap.buyer(),'quantity',3,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch174('kA')::uuid),'ck174-mA') -> 'atom_ids')::text);
SELECT tap._store174('mB', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch174('sB')::uuid,'org_id',tap._fetch174('org')::uuid,'ticket_type_id',tap._fetch174('ttB')::uuid,
  'batch_id',tap._fetch174('bB')::uuid,'owner_id',tap.buyer(),'quantity',1,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch174('kB')::uuid),'ck174-mB') -> 'atom_ids')::text);
SELECT tap.login_service();
SELECT tap._store174('mint', (venue.mint_door_session(tap._fetch174('venue')::uuid, tap._fetch174('sA')::uuid, tap._fetch174('dev')::uuid, 'pin-174', 'ck174-mint')::text));
SELECT tap._store174('dsid', (tap._fetch174('mint')::jsonb ->> 'door_session_id'));
SELECT tap._store174('secret', (tap._fetch174('mint')::jsonb ->> 'secret'));
SELECT tap.logout();

-- ── D1 — a valid machine scan admits (bound scope) ──────────────────────────
SELECT tap.login_service();
SELECT is((venue.record_scan_door((tap._fetch174('mA')::jsonb->>0)::uuid, tap._fetch174('sA')::uuid,
             tap._fetch174('dsid')::uuid, tap._fetch174('secret'), tap._fetch174('dev')::uuid, '{}'::jsonb, 'ck174-scan0') ->> 'result'),
          'admitted',
  'D1: record_scan_door admits with a valid door session');

-- ── D2 — scan_meta.device_id override is rejected ───────────────────────────
SELECT throws_like(
  format($$SELECT venue.record_scan_door(%L,%L,%L,%L,%L,'{"device_id":"%s"}'::jsonb,'ck174-metadev')$$,
    (tap._fetch174('mA')::jsonb->>1), tap._fetch174('sA'), tap._fetch174('dsid'), tap._fetch174('secret'), tap._fetch174('dev'), gen_random_uuid()::text),
  '%scan_meta.device_id is not accepted%',
  'D2: a body scan_meta.device_id is rejected (device is server-derived)');

-- ── D3 — a body device that disagrees with the bound device is caught opaquely
SELECT throws_like(
  format($$SELECT venue.record_scan_door(%L,%L,%L,%L,%L,'{}'::jsonb,'ck174-wrongdev')$$,
    (tap._fetch174('mA')::jsonb->>1), tap._fetch174('sA'), tap._fetch174('dsid'), tap._fetch174('secret'), gen_random_uuid()::text),
  '%door_session_invalid%',
  'D3: a body device_id != the bound device is refused (assert_door_session, opaque)');

-- ── D4 — a body session that disagrees is caught opaquely ───────────────────
SELECT throws_like(
  format($$SELECT venue.record_scan_door(%L,%L,%L,%L,%L,'{}'::jsonb,'ck174-wrongsess')$$,
    (tap._fetch174('mA')::jsonb->>1), gen_random_uuid()::text, tap._fetch174('dsid'), tap._fetch174('secret'), tap._fetch174('dev')),
  '%door_session_invalid%',
  'D4: a body session_id != the bound session is refused (no scope override)');

-- ── D9 — a door session for A cannot admit session B''s atom ────────────────
SELECT is((venue.record_scan_door((tap._fetch174('mB')::jsonb->>0)::uuid, tap._fetch174('sA')::uuid,
             tap._fetch174('dsid')::uuid, tap._fetch174('secret'), tap._fetch174('dev')::uuid, '{}'::jsonb, 'ck174-xsession') ->> 'result'),
          'invalid',
  'D5: session A''s door session cannot admit an atom of session B (wrong_session -> invalid)');
SELECT tap.logout();

-- ── D6 — the admitted scan is device-attributed (machine path, NULL actor) ──
SELECT is((SELECT (device_id = tap._fetch174('dev')::uuid AND actor_identity_id IS NULL)
             FROM venue.scan WHERE ticket_atom_id = (tap._fetch174('mA')::jsonb->>0)::uuid AND result='admitted'), true,
  'D6: the machine-path scan row is device-attributed (device set, actor_identity NULL)');

-- ── D7 — the machine entrypoints are service_role-only ──────────────────────
SELECT tap.login(tap.seller());   -- authenticated venue_manager, but NOT service_role
SELECT throws_like(
  format($$SELECT venue.record_scan_door(%L,%L,%L,%L,%L,'{}'::jsonb,'ck174-authdenied')$$,
    (tap._fetch174('mA')::jsonb->>2), tap._fetch174('sA'), tap._fetch174('dsid'), tap._fetch174('secret'), tap._fetch174('dev')),
  '%permission denied%',
  'D7: an authenticated (non-service_role) caller cannot invoke record_scan_door');
SELECT tap.logout();

-- ── D8/D10 — machine reconcile: per-item session isolation + dedupe ─────────
-- batch: mA[1] (good, admits) + mA[2] carrying a WRONG session_id (isolated conflict).
SELECT tap.login_service();
SELECT tap._store174('rec', (venue.reconcile_offline_scans_door(
  tap._fetch174('sA')::uuid, tap._fetch174('dsid')::uuid, tap._fetch174('secret'), tap._fetch174('dev')::uuid,
  jsonb_build_array(
    jsonb_build_object('ticket_atom_id', tap._fetch174('mA')::jsonb->>1, 'scan_sequence', 1),
    jsonb_build_object('ticket_atom_id', tap._fetch174('mA')::jsonb->>2, 'session_id', gen_random_uuid()::text, 'scan_sequence', 2)
  ), 'ck174-rec')::text));
SELECT is(concat((tap._fetch174('rec')::jsonb->>'admitted'),'/',(tap._fetch174('rec')::jsonb->>'conflicts')), '1/1',
  'D8: machine reconcile admits the good item and isolates the wrong-session item as a conflict (no batch poison)');
-- replay mA[1] (now consumed/scanned) -> a conflict (not_active), never a second
-- admit. (Matches 171 R1: a re-scan of a consumed atom is a conflict, not a
-- duplicate — the duplicate class is the racing-admit unique_violation window.)
SELECT tap._store174('rec2', (venue.reconcile_offline_scans_door(
  tap._fetch174('sA')::uuid, tap._fetch174('dsid')::uuid, tap._fetch174('secret'), tap._fetch174('dev')::uuid,
  jsonb_build_array(jsonb_build_object('ticket_atom_id', tap._fetch174('mA')::jsonb->>1, 'scan_sequence', 3)), 'ck174-rec2')::text));
SELECT tap.logout();
SELECT is(concat((tap._fetch174('rec2')::jsonb->>'admitted'),'/',(tap._fetch174('rec2')::jsonb->>'conflicts')), '0/1',
  'D9: a repeated admit of a consumed atom reconciles as a conflict, never a second admitted row (first-in-wins)');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch174('mA')::jsonb->>1)::uuid AND result='admitted'), 1,
  'D10: exactly ONE authoritative admitted row persists for the reconciled atom');

-- D11: a batch mixing a GOOD row (mA[2], never scanned) with a MALFORMED row
-- (non-UUID ticket_atom_id) must NOT poison the batch — the good one admits, the
-- garbage row is isolated as a conflict (adversarial poison-pill fix: the atom
-- cast is inside the per-item block).
SELECT tap.login_service();
SELECT tap._store174('rec3', (venue.reconcile_offline_scans_door(
  tap._fetch174('sA')::uuid, tap._fetch174('dsid')::uuid, tap._fetch174('secret'), tap._fetch174('dev')::uuid,
  jsonb_build_array(
    jsonb_build_object('ticket_atom_id', tap._fetch174('mA')::jsonb->>2, 'scan_sequence', 1),
    jsonb_build_object('ticket_atom_id', 'not-a-uuid', 'scan_sequence', 2)
  ), 'ck174-rec3')::text));
SELECT tap.logout();
SELECT is(concat((tap._fetch174('rec3')::jsonb->>'admitted'),'/',(tap._fetch174('rec3')::jsonb->>'conflicts')), '1/1',
  'D11: a malformed (non-UUID) ticket_atom_id is isolated as a conflict; the good row still admits (no batch poison)');

SELECT * FROM finish();
ROLLBACK;
