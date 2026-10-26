-- ============================================================================
-- 257_e76_door_operator_binding.sql — migration 20261027000000 (registry 187).
--   E-76 on the door plane: a venue role reaches a session's door gates only while
--   the venue's CURRENT operator org is the event's org. Nine gates, three directions:
--   (P) current operator's staff → every gate works;
--   (F) the FORMER operator's staff after an operatorship move (role still on the venue)
--       → every gate refuses 42501, identical text to a missing role (no oracle);
--   (N) the NEW operator's staff on the former operator's event → every gate refuses;
--   (C) the new operator's staff on the new operator's OWN event → gates work (control).
--   Plus: the helper is zero-grant; nine STRUCTURAL pins (G1-G9) that each gate's body calls
--   the helper (A's request: one pin per gate a mutant can kill — behavioural pins alone do
--   not isolate sync_scan_device_manifest, whose nested get_door_manifest also refuses);
--   the device gates (venue-level) stay out of scope.
--   NEGATIVE CONTROL: on a chain WITHOUT 187 every (F)/(N) assertion fails (the gates
--   admit); recorded in planning/2026-10-26-launch/B/evidence (RED run) and by the
--   per-gate mutant run (helper call removed from gate k → pin k fails).
--   The operatorship move is performed directly on catalog.venue.org_id here (the test runs
--   as the harness role). It CANNOT be done through the RPC surface today: 093's
--   catalog.update_venue refuses an org_id patch (`operatorship_transfer_frozen`, Decision
--   C), so this fixture models the world after the atomic re-scoping verb ships — and the
--   reachable case now, a venue role that outlives an out-of-band operator change.
-- ============================================================================
BEGIN;
SELECT plan(47);
SELECT tap.seed_core();

CREATE TABLE tap.memo_257 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store257(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_257 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch257(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_257 WHERE k=$1 $m$;

-- ── FIXTURE — org A operates venue V; event E (session sA) belongs to A; seller = venue_manager on V;
-- device, PIN, 4 comp atoms, a comp allocation, a guest list entry; flags ON. (174/253 shape.)
SELECT tap.login(tap.seller());
SELECT tap._store257('orgA', (kernel.create_organization('OP A','OP A','ck257-oA') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch257('orgA')::uuid;
SELECT tap.login(tap.other_user());
SELECT tap._store257('orgB', (kernel.create_organization('OP B','OP B','ck257-oB') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch257('orgB')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store257('venue', (catalog.create_venue(tap._fetch257('orgA')::uuid,'OP Hall','wynwood',NULL,'ck257-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch257('venue')::uuid,'approved','miami_gate','ck257-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch257('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store257('eA', (catalog.create_event(tap._fetch257('venue')::uuid,'OP A night',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'ck257-eA') ->> 'event_id'));
SELECT tap._store257('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch257('eA')::uuid));
SELECT tap._store257('ttA', (venue.create_ticket_type(tap._fetch257('eA')::uuid,'admission','GA',5000,'public','ck257-ttA') ->> 'ticket_type_id'));
SELECT tap._store257('bA', (venue.create_inventory_batch(tap._fetch257('ttA')::uuid, tap._fetch257('sA')::uuid, 'comp', 100, 0, 'ck257-bA') ->> 'batch_id'));
SELECT tap._store257('dev', (venue.register_scan_device(tap._fetch257('venue')::uuid, 'scanner-257', 'ck257-dev') ->> 'device_id'));
SELECT tap._store257('gl', (venue.create_guest_list(tap._fetch257('sA')::uuid, 'VIP', 'ck257-gl') ->> 'guest_list_id'));
SELECT tap._store257('ge', (venue.upsert_guest_entry(tap._fetch257('gl')::uuid, NULL, 'Guest One', 1, 'ck257-ge') ->> 'guest_entry_id'));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch257('eA')::uuid, 'PUBKEY-257A', 'kms-257A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store257('kA', (SELECT key_id::text FROM kA));
SELECT tap._store257('mA', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch257('sA')::uuid,'org_id',tap._fetch257('orgA')::uuid,'ticket_type_id',tap._fetch257('ttA')::uuid,
  'batch_id',tap._fetch257('bA')::uuid,'owner_id',tap.buyer(),'quantity',4,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch257('kA')::uuid),'ck257-mA') -> 'atom_ids')::text);
SELECT is((SELECT org_id FROM catalog.event WHERE event_id = tap._fetch257('eA')::uuid), tap._fetch257('orgA')::uuid,
  'FX: event E belongs to org A (the venue''s operator at creation)');

-- helper under test: zero client grant
-- (to_regprocedure keeps this a clean FAIL, not a raise, on a chain without 187)
SELECT ok(to_regprocedure('venue.assert_session_operator(uuid)') IS NOT NULL
       AND NOT has_function_privilege('anon', to_regprocedure('venue.assert_session_operator(uuid)'), 'EXECUTE')
       AND NOT has_function_privilege('authenticated', to_regprocedure('venue.assert_session_operator(uuid)'), 'EXECUTE')
       AND NOT has_function_privilege('service_role', to_regprocedure('venue.assert_session_operator(uuid)'), 'EXECUTE'),
  'H1: venue.assert_session_operator exists and has no client EXECUTE (anon/authenticated/service_role)');

-- ── (P) current operator: every gate works for the venue_manager ───────────
SELECT tap.login(tap.seller());
SELECT tap._store257('pin1', (venue.create_door_pin(tap._fetch257('venue')::uuid, tap._fetch257('sA')::uuid, 'front', 'pin-257', (now()+interval '1 day'), 'ck257-pin1') ->> 'pin_id'));
SELECT ok(tap._fetch257('pin1') IS NOT NULL, 'P1: create_door_pin works under the current operator');
SELECT is((venue.get_door_manifest(tap._fetch257('sA')::uuid, 0) ->> 'status'), 'no_open_episode', 'P2: get_door_manifest reaches the read (no open episode yet)');
SELECT is((venue.validate_ticket_online((tap._fetch257('mA')::jsonb->>0)::uuid, tap._fetch257('sA')::uuid) ->> 'status'), 'ok', 'P3: validate_ticket_online reads the atom');
SELECT is((venue.sync_scan_device_manifest(tap._fetch257('dev')::uuid, tap._fetch257('sA')::uuid, 0) ->> 'status'), 'no_open_episode', 'P4: sync_scan_device_manifest reaches the read');
SELECT tap._store257('ca', (venue.allocate_comp(tap._fetch257('sA')::uuid, tap._fetch257('bA')::uuid, 2, 'press', 'ck257-ca') ->> 'comp_allocation_id'));
SELECT ok(tap._fetch257('ca') IS NOT NULL, 'P5: allocate_comp works under the current operator');
SELECT is((venue.check_in_guest_entry(tap._fetch257('ge')::uuid, tap._fetch257('sA')::uuid, 'arrived', 'ck257-ge-in') ->> 'status'), 'ok', 'P6: check_in_guest_entry works under the current operator');
SELECT is((venue.record_scan((tap._fetch257('mA')::jsonb->>0)::uuid, tap._fetch257('sA')::uuid, NULL, '{}'::jsonb, 'ck257-scan0') ->> 'result'), 'admitted', 'P7: record_scan admits under the current operator');
SELECT is(((venue.reconcile_offline_scans(tap._fetch257('sA')::uuid, tap._fetch257('dev')::uuid,
  jsonb_build_array(jsonb_build_object('ticket_atom_id', tap._fetch257('mA')::jsonb->>1, 'scan_sequence', 1)), 'ck257-rec') ->> 'admitted')), '1', 'P8: reconcile_offline_scans admits under the current operator');
SELECT is((venue.revoke_door_pin(tap._fetch257('pin1')::uuid, 'ck257-pin1-rev') ->> 'status'), 'ok', 'P9: revoke_door_pin works under the current operator');
SELECT tap._store257('pin2', (venue.create_door_pin(tap._fetch257('venue')::uuid, tap._fetch257('sA')::uuid, 'front', 'pin-257b', (now()+interval '1 day'), 'ck257-pin2') ->> 'pin_id'));
SELECT tap.logout();

-- ── OPERATORSHIP MOVE: venue V now operated by org B; event E still belongs to A; seller keeps the venue role.
UPDATE catalog.venue SET org_id = tap._fetch257('orgB')::uuid, updated_at = now() WHERE venue_id = tap._fetch257('venue')::uuid;
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch257('venue')::uuid, tap.other_user(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT is((SELECT count(*)::int FROM venue.staff_role WHERE venue_id = tap._fetch257('venue')::uuid AND identity_id = tap.seller() AND role='venue_manager'), 1,
  'FX: the former operator''s staff STILL holds venue_manager on the venue (the gap 187 closes)');

-- ── (F) former operator's staff after the move: every gate refuses 42501 ─────
SELECT tap.login(tap.seller());
SELECT throws_like(format($$SELECT venue.record_scan(%L,%L,NULL,'{}'::jsonb,'ck257-f1')$$, (tap._fetch257('mA')::jsonb->>2), tap._fetch257('sA')), '%insufficient_privilege%', 'F1: record_scan refuses the former operator''s venue_manager');
SELECT throws_like(format($$SELECT venue.reconcile_offline_scans(%L,%L,'[]'::jsonb,'ck257-f2')$$, tap._fetch257('sA'), tap._fetch257('dev')), '%insufficient_privilege%', 'F2: reconcile_offline_scans refuses');
SELECT throws_like(format($$SELECT venue.validate_ticket_online(%L,%L)$$, (tap._fetch257('mA')::jsonb->>2), tap._fetch257('sA')), '%insufficient_privilege%', 'F3: validate_ticket_online refuses');
SELECT throws_like(format($$SELECT venue.get_door_manifest(%L,0)$$, tap._fetch257('sA')), '%insufficient_privilege%', 'F4: get_door_manifest refuses');
SELECT throws_like(format($$SELECT venue.sync_scan_device_manifest(%L,%L,0)$$, tap._fetch257('dev'), tap._fetch257('sA')), '%insufficient_privilege%', 'F5: sync_scan_device_manifest refuses');
SELECT throws_like(format($$SELECT venue.create_door_pin(%L,%L,'side','pin-x',now()+interval '1 day','ck257-f6')$$, tap._fetch257('venue'), tap._fetch257('sA')), '%insufficient_privilege%', 'F6: create_door_pin refuses');
SELECT throws_like(format($$SELECT venue.revoke_door_pin(%L,'ck257-f7')$$, tap._fetch257('pin2')), '%insufficient_privilege%', 'F7: revoke_door_pin refuses (session = the PIN''s)');
SELECT throws_like(format($$SELECT venue.allocate_comp(%L,%L,1,'press','ck257-f8')$$, tap._fetch257('sA'), tap._fetch257('bA')), '%insufficient_privilege%', 'F8: allocate_comp refuses');
SELECT throws_like(format($$SELECT venue.check_in_guest_entry(%L,%L,'arrived','ck257-f9')$$, tap._fetch257('ge'), tap._fetch257('sA')), '%insufficient_privilege%', 'F9: check_in_guest_entry refuses');
SELECT tap.logout();
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id=(tap._fetch257('mA')::jsonb->>2)::uuid), 'active', 'F10: the refused scan left the atom active (nothing consumed)');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id=(tap._fetch257('mA')::jsonb->>2)::uuid), 0, 'F11: the refused scan wrote no ledger row');

-- ── (N) the NEW operator's staff on the FORMER operator's event: every gate refuses ─
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT venue.record_scan(%L,%L,NULL,'{}'::jsonb,'ck257-n1')$$, (tap._fetch257('mA')::jsonb->>2), tap._fetch257('sA')), '%insufficient_privilege%', 'N1: record_scan refuses the new operator''s staff on the former operator''s event');
SELECT throws_like(format($$SELECT venue.reconcile_offline_scans(%L,%L,'[]'::jsonb,'ck257-n2')$$, tap._fetch257('sA'), tap._fetch257('dev')), '%insufficient_privilege%', 'N2: reconcile_offline_scans refuses');
SELECT throws_like(format($$SELECT venue.validate_ticket_online(%L,%L)$$, (tap._fetch257('mA')::jsonb->>2), tap._fetch257('sA')), '%insufficient_privilege%', 'N3: validate_ticket_online refuses');
SELECT throws_like(format($$SELECT venue.get_door_manifest(%L,0)$$, tap._fetch257('sA')), '%insufficient_privilege%', 'N4: get_door_manifest refuses');
SELECT throws_like(format($$SELECT venue.sync_scan_device_manifest(%L,%L,0)$$, tap._fetch257('dev'), tap._fetch257('sA')), '%insufficient_privilege%', 'N5: sync_scan_device_manifest refuses');
SELECT throws_like(format($$SELECT venue.create_door_pin(%L,%L,'side','pin-y',now()+interval '1 day','ck257-n6')$$, tap._fetch257('venue'), tap._fetch257('sA')), '%insufficient_privilege%', 'N6: create_door_pin refuses');
SELECT throws_like(format($$SELECT venue.revoke_door_pin(%L,'ck257-n7')$$, tap._fetch257('pin2')), '%insufficient_privilege%', 'N7: revoke_door_pin refuses');
SELECT throws_like(format($$SELECT venue.allocate_comp(%L,%L,1,'press','ck257-n8')$$, tap._fetch257('sA'), tap._fetch257('bA')), '%insufficient_privilege%', 'N8: allocate_comp refuses');
SELECT throws_like(format($$SELECT venue.check_in_guest_entry(%L,%L,'arrived','ck257-n9')$$, tap._fetch257('ge'), tap._fetch257('sA')), '%insufficient_privilege%', 'N9: check_in_guest_entry refuses');

-- ── (C) control: the new operator's staff on the NEW operator's own event at the same venue works
SELECT tap._store257('eB', (catalog.create_event(tap._fetch257('venue')::uuid,'OP B night',
  jsonb_build_object('starts_at',(now()+interval '12 days')::text,'ends_at',(now()+interval '12 days 5 hours')::text),'ck257-eB') ->> 'event_id'));
SELECT tap._store257('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch257('eB')::uuid));
SELECT is((SELECT org_id FROM catalog.event WHERE event_id = tap._fetch257('eB')::uuid), tap._fetch257('orgB')::uuid, 'C0: the new event belongs to the current operator (org B)');
SELECT is((venue.get_door_manifest(tap._fetch257('sB')::uuid, 0) ->> 'status'), 'no_open_episode', 'C1: get_door_manifest works for the current operator''s own event');
SELECT ok((venue.create_door_pin(tap._fetch257('venue')::uuid, tap._fetch257('sB')::uuid, 'front', 'pin-257c', (now()+interval '1 day'), 'ck257-pinB') ->> 'pin_id') IS NOT NULL, 'C2: create_door_pin works for the current operator''s own event');
SELECT is((venue.validate_ticket_online(gen_random_uuid(), tap._fetch257('sB')::uuid) ->> 'status'), 'not_found', 'C3: validate_ticket_online passes the gates for the current operator (unknown atom → not_found, not 42501)');
SELECT tap.logout();

-- ── no-oracle: an unknown session refuses identically for a venue_manager
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT venue.get_door_manifest(%L,0)$$, gen_random_uuid()::text), '%insufficient_privilege%', 'O1: an unknown session refuses with the same insufficient_privilege (no existence oracle)');
SELECT tap.logout();

-- ── out of scope, pinned as such: the venue-level device gates still work for the venue role (no event to bind)
SELECT tap.login(tap.seller());
SELECT is((venue.set_scan_device_status(tap._fetch257('dev')::uuid, 'active', 'still active', 'ck257-dev-st') ->> 'status'), 'ok', 'X1: set_scan_device_status (venue-level, no session) is unchanged by 187');
SELECT tap.logout();

-- ── STRUCTURAL (G1-G9): every gate's own body calls the helper. Behavioural pins cannot
-- isolate a single gate (a nested gate's refusal can stand in — proven: removing only
-- sync_scan_device_manifest's call still refuses via get_door_manifest), so each gate also
-- carries a pin a per-gate mutant kills. Same discipline as T-RPC-DOOR-01's structural pin.
SELECT ok(pg_get_functiondef('venue.record_scan(uuid,uuid,uuid,jsonb,text)'::regprocedure) LIKE '%assert_session_operator%',
  'G1: venue.record_scan calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)'::regprocedure) LIKE '%assert_session_operator%',
  'G2: venue.reconcile_offline_scans calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.validate_ticket_online(uuid,uuid)'::regprocedure) LIKE '%assert_session_operator%',
  'G3: venue.validate_ticket_online calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.revoke_door_pin(uuid,text)'::regprocedure) LIKE '%assert_session_operator%',
  'G4: venue.revoke_door_pin calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.allocate_comp(uuid,uuid,integer,text,text)'::regprocedure) LIKE '%assert_session_operator%',
  'G5: venue.allocate_comp calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.check_in_guest_entry(uuid,uuid,text,text)'::regprocedure) LIKE '%assert_session_operator%',
  'G6: venue.check_in_guest_entry calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)'::regprocedure) LIKE '%assert_session_operator%',
  'G7: venue.create_door_pin calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.get_door_manifest(uuid,integer)'::regprocedure) LIKE '%assert_session_operator%',
  'G8: venue.get_door_manifest calls venue.assert_session_operator (E-76 gate present in its own body)');
SELECT ok(pg_get_functiondef('venue.sync_scan_device_manifest(uuid,uuid,integer)'::regprocedure) LIKE '%assert_session_operator%',
  'G9: venue.sync_scan_device_manifest calls venue.assert_session_operator (E-76 gate present in its own body)');

SELECT * FROM finish();
ROLLBACK;
