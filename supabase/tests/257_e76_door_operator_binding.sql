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
SELECT plan(68);
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
-- a third event (eC/sC) carries the manifest episodes, so sA's own door boundary stays untouched
SELECT tap._store257('eC', (catalog.create_event(tap._fetch257('venue')::uuid,'OP A manifests',
  jsonb_build_object('starts_at',(now()+interval '10 days')::text,'ends_at',(now()+interval '10 days 5 hours')::text),'ck257-eC') ->> 'event_id'));
SELECT tap._store257('sC', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch257('eC')::uuid));
SELECT isnt(tap._fetch257('sC'), NULL, 'FX3: the manifest-only session sC exists under org A');
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
-- the four gates A's review added (N2 issue_comp / open / close, N3 mint), current operator
SELECT is((venue.issue_comp(tap._fetch257('ca')::uuid, tap.buyer(), 1, 'ck257-p10') ->> 'status'), 'ok',
  'P10: issue_comp mints under the current operator (A''s probe minted on the FORMER operator''s event before 187)');
SELECT tap._store257('ca2', (venue.allocate_comp(tap._fetch257('sA')::uuid, tap._fetch257('bA')::uuid, 1, 'press', 'ck257-ca2') ->> 'comp_allocation_id'));
SELECT isnt(tap._fetch257('ca2'), NULL, 'FX4: a second comp allocation is left UNISSUED for the F/N cases');
SELECT ok((venue.open_door_manifest(tap._fetch257('sC')::uuid, 'doors_open', 'ck257-p11') ->> 'manifest_id') IS NOT NULL,
  'P11: open_door_manifest opens an episode under the current operator');
SELECT is((venue.close_door_manifest(tap._fetch257('sC')::uuid, 'doors_closed', 'ck257-p12') ->> 'status'), 'ok',
  'P12: close_door_manifest closes it under the current operator');
SELECT tap.logout();
SELECT tap.login_service();
SELECT ok((venue.mint_door_session(tap._fetch257('venue')::uuid, tap._fetch257('sA')::uuid, tap._fetch257('dev')::uuid, 'pin-257b', 'ck257-p13') ->> 'secret') IS NOT NULL,
  'P13: mint_door_session mints under the current operator (service_role machine path)');
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
SELECT throws_like(format($$SELECT venue.issue_comp(%L,%L,1,'ck257-f12')$$, tap._fetch257('ca2'), tap.buyer()),
  '%insufficient_privilege%', 'F12: issue_comp refuses the former operator''s manager (A''s N2 probe: this minted a comp atom on the former operator''s event before 187)');
SELECT throws_like(format($$SELECT venue.open_door_manifest(%L,'doors_open','ck257-f13')$$, tap._fetch257('sC')),
  '%insufficient_privilege%', 'F13: open_door_manifest refuses');
SELECT throws_like(format($$SELECT venue.close_door_manifest(%L,'doors_closed','ck257-f14')$$, tap._fetch257('sC')),
  '%insufficient_privilege%', 'F14: close_door_manifest refuses');
SELECT tap.logout();
-- mint is the service_role machine path and §9.6 keeps ONE opaque class: the refusal must read
-- door_session_invalid, NOT insufficient_privilege, or the error itself becomes an operator oracle.
SELECT tap.login_service();
SELECT throws_like(format($$SELECT venue.mint_door_session(%L,%L,%L,'pin-257b','ck257-f15')$$, tap._fetch257('venue'), tap._fetch257('sA'), tap._fetch257('dev')),
  '%door_session_invalid%', 'F15: mint_door_session refuses a pre-move PIN AFTER the operator change (N3) — and in its own opaque class');
SELECT tap.logout();
SELECT tap.login(tap.seller());
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

SELECT throws_like(format($$SELECT venue.issue_comp(%L,%L,1,'ck257-n10')$$, tap._fetch257('ca2'), tap.buyer()),
  '%insufficient_privilege%', 'N10: issue_comp refuses the NEW operator''s manager on the former operator''s event');
SELECT throws_like(format($$SELECT venue.open_door_manifest(%L,'doors_open','ck257-n11')$$, tap._fetch257('sC')),
  '%insufficient_privilege%', 'N11: open_door_manifest refuses');
SELECT throws_like(format($$SELECT venue.close_door_manifest(%L,'doors_closed','ck257-n12')$$, tap._fetch257('sC')),
  '%insufficient_privilege%', 'N12: close_door_manifest refuses');
SELECT is((SELECT count(*)::int FROM venue.comp_allocation WHERE id=tap._fetch257('ca2')::uuid AND status='allocated'), 1,
  'N13: the refused issue_comp left the allocation unissued (nothing minted)');

-- ── (C) control: the new operator's staff on the NEW operator's own event at the same venue works
SELECT tap._store257('eB', (catalog.create_event(tap._fetch257('venue')::uuid,'OP B night',
  jsonb_build_object('starts_at',(now()+interval '12 days')::text,'ends_at',(now()+interval '12 days 5 hours')::text),'ck257-eB') ->> 'event_id'));
SELECT tap._store257('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch257('eB')::uuid));
SELECT is((SELECT org_id FROM catalog.event WHERE event_id = tap._fetch257('eB')::uuid), tap._fetch257('orgB')::uuid, 'C0: the new event belongs to the current operator (org B)');
SELECT is((venue.get_door_manifest(tap._fetch257('sB')::uuid, 0) ->> 'status'), 'no_open_episode', 'C1: get_door_manifest works for the current operator''s own event');
SELECT ok((venue.create_door_pin(tap._fetch257('venue')::uuid, tap._fetch257('sB')::uuid, 'front', 'pin-257c', (now()+interval '1 day'), 'ck257-pinB') ->> 'pin_id') IS NOT NULL, 'C2: create_door_pin works for the current operator''s own event');
SELECT is((venue.validate_ticket_online(gen_random_uuid(), tap._fetch257('sB')::uuid) ->> 'status'), 'not_found', 'C3: validate_ticket_online passes the gates for the current operator (unknown atom → not_found, not 42501)');
-- N1 (A's review): check_in_guest_entry used to accept p_session_id and NEVER use it. Both
-- directions are pinned here, from the NEW operator's seat: it legitimately operates sB.
SELECT tap._store257('glB', (venue.create_guest_list(tap._fetch257('sB')::uuid, 'VIP B', 'ck257-glB') ->> 'guest_list_id'));
SELECT tap._store257('geB', (venue.upsert_guest_entry(tap._fetch257('glB')::uuid, NULL, 'Guest B', 1, 'ck257-geB') ->> 'guest_entry_id'));
SELECT throws_like(format($$SELECT venue.check_in_guest_entry(%L,%L,'arrived','ck257-nm1')$$, tap._fetch257('geB'), tap._fetch257('sA')),
  '%session_mismatch%', 'NM1: its OWN entry with a disagreeing p_session_id is refused session_mismatch (the argument is no longer ignored)');
SELECT throws_like(format($$SELECT venue.check_in_guest_entry(%L,%L,'arrived','ck257-nm2')$$, tap._fetch257('ge'), tap._fetch257('sB')),
  '%insufficient_privilege%', 'NM2: the FORMER operator''s entry cannot be checked in by aiming p_session_id at a session the caller DOES operate — the gate uses the ENTRY''s own session (the bypass A found)');
SELECT is((SELECT status FROM venue.guest_entry WHERE id=tap._fetch257('ge')::uuid), 'arrived',
  'NM3: that entry still holds its pre-move state — the refused call wrote nothing');
SELECT tap.logout();

-- ── no-oracle: an unknown session refuses identically for a venue_manager
SELECT tap.login(tap.other_user());
SELECT throws_like(format($$SELECT venue.get_door_manifest(%L,0)$$, gen_random_uuid()::text), '%insufficient_privilege%', 'O1: an unknown session refuses with the same insufficient_privilege (no existence oracle)');
SELECT tap.logout();

-- ── out of scope, pinned as such: the venue-level device gates still work for the venue role (no event to bind)
SELECT tap.login(tap.seller());
SELECT is((venue.set_scan_device_status(tap._fetch257('dev')::uuid, 'active', 'still active', 'ck257-dev-st') ->> 'status'), 'ok', 'X1: set_scan_device_status (venue-level, no session) is unchanged by 187');
SELECT tap.logout();

-- ── STRUCTURAL (G1-G13, A review N4/N6): every gate's own body carries a LIVE call. The earlier
-- form was LIKE '%assert_session_operator%', which a commented-out `perform` would satisfy; these
-- strip a trailing comment from each line and require a real `perform venue.assert_session_operator(`
-- statement. Behavioural pins alone cannot isolate one gate anyway (removing only
-- sync_scan_device_manifest's call still refuses via its nested get_door_manifest), so each gate also
-- carries a pin its own mutant kills. Same discipline as T-RPC-DOOR-01's structural pin.
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.record_scan(uuid,uuid,uuid,jsonb,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G1: venue.record_scan carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.reconcile_offline_scans(uuid,uuid,jsonb,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G2: venue.reconcile_offline_scans carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.validate_ticket_online(uuid,uuid)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G3: venue.validate_ticket_online carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.revoke_door_pin(uuid,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G4: venue.revoke_door_pin carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.allocate_comp(uuid,uuid,integer,text,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G5: venue.allocate_comp carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.check_in_guest_entry(uuid,uuid,text,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G6: venue.check_in_guest_entry carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.create_door_pin(uuid,uuid,text,text,timestamptz,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G7: venue.create_door_pin carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.get_door_manifest(uuid,integer)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G8: venue.get_door_manifest carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.sync_scan_device_manifest(uuid,uuid,integer)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G9: venue.sync_scan_device_manifest carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.issue_comp(uuid,uuid,integer,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G10: venue.issue_comp carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.open_door_manifest(uuid,text,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G11: venue.open_door_manifest carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.close_door_manifest(uuid,text,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G12: venue.close_door_manifest carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');
SELECT is((SELECT count(*)::int FROM regexp_split_to_table(pg_get_functiondef('venue.mint_door_session(uuid,uuid,uuid,text,text)'::regprocedure), E'\n') AS ln
            WHERE regexp_replace(ln, '--.*$', '') ~ 'perform[[:space:]]+venue\.assert_session_operator[[:space:]]*\('), 1,
  'G13: venue.mint_door_session carries exactly one LIVE perform of venue.assert_session_operator (comments stripped)');

SELECT * FROM finish();
ROLLBACK;
