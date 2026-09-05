-- ============================================================================
-- 179_get_door_manifest_door_machine_authority.sql — migration 113 (P1-M2-DOOR-AUTHZ).
--   venue.get_door_manifest_door (service_role machine path): the door session is
--   the sole authority and DECIDES SCOPE — a valid bound device syncs full and
--   incremental manifests identical to the staff read; wrong token / device /
--   session, unknown ids, revoked and expired door sessions, service_role without
--   credentials, and credentials invalidated between the edge's admit check and
--   the machine RPC are all refused opaquely; anon/authenticated cannot call the
--   machine entrypoint or the zero-grant core; the staff path is unchanged; the
--   census moved by exactly two.
-- ============================================================================
BEGIN;
SELECT plan(45);
SELECT tap.seed_core();

CREATE TABLE tap.memo_179 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store179(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_179 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch179(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_179 WHERE k=$1 $m$;

-- ── FIXTURE — venue(approved), seller = venue_manager, other_user = venue_scanner,
-- event A (3 atoms, open manifest) + event B (session only), device, PIN, minted
-- door session bound to (device, session A), native issuance + scanning ON. ───
SELECT tap.login(tap.seller());
SELECT tap._store179('org', (kernel.create_organization('DM Co','DM Co','dm179-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch179('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store179('venue', (catalog.create_venue(tap._fetch179('org')::uuid,'DM Hall','wynwood',NULL,'dm179-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch179('venue')::uuid,'approved','miami_gate','dm179-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch179('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()),
       (tap._fetch179('venue')::uuid, tap.other_user(), 'venue_scanner', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store179('eA', (catalog.create_event(tap._fetch179('venue')::uuid,'DM A',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'dm179-eA') ->> 'event_id'));
SELECT tap._store179('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch179('eA')::uuid));
SELECT tap._store179('ttA', (venue.create_ticket_type(tap._fetch179('eA')::uuid,'admission','GA',5000,'public','dm179-ttA') ->> 'ticket_type_id'));
SELECT tap._store179('bA', (venue.create_inventory_batch(tap._fetch179('ttA')::uuid, tap._fetch179('sA')::uuid, 'comp', 100, 0, 'dm179-bA') ->> 'batch_id'));
SELECT tap._store179('eB', (catalog.create_event(tap._fetch179('venue')::uuid,'DM B',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'dm179-eB') ->> 'event_id'));
SELECT tap._store179('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch179('eB')::uuid));
SELECT tap._store179('dev', (venue.register_scan_device(tap._fetch179('venue')::uuid, 'scanner-179', 'dm179-dev') ->> 'device_id'));
SELECT tap._store179('pin', (venue.create_door_pin(tap._fetch179('venue')::uuid, tap._fetch179('sA')::uuid, 'front', 'pin-179', (now()+interval '1 day'), 'dm179-pin') ->> 'pin_id'));
SELECT tap.logout();
WITH kA AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch179('eA')::uuid, 'PUBKEY-179A', 'kms-179A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store179('kA', (SELECT key_id::text FROM kA));
SELECT kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch179('sA')::uuid,'org_id',tap._fetch179('org')::uuid,'ticket_type_id',tap._fetch179('ttA')::uuid,
  'batch_id',tap._fetch179('bA')::uuid,'owner_id',tap.buyer(),'quantity',3,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch179('kA')::uuid),'dm179-mA');
SELECT tap.login(tap.seller());
SELECT tap._store179('m1', (venue.open_door_manifest(tap._fetch179('sA')::uuid,'doors_open','dm179-d1') ->> 'manifest_id'));
SELECT tap.logout();
SELECT tap.login_service();
SELECT tap._store179('mint', (venue.mint_door_session(tap._fetch179('venue')::uuid, tap._fetch179('sA')::uuid, tap._fetch179('dev')::uuid, 'pin-179', 'dm179-mint')::text));
SELECT tap._store179('dsid', (tap._fetch179('mint')::jsonb ->> 'door_session_id'));
SELECT tap._store179('secret', (tap._fetch179('mint')::jsonb ->> 'secret'));
SELECT tap.logout();

-- ── A. grants, definer invariants, census ───────────────────────────────────
SELECT ok(has_function_privilege('service_role', 'venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)', 'EXECUTE'), 'A1: service_role may EXECUTE the machine entrypoint');
SELECT ok(NOT has_function_privilege('authenticated', 'venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)', 'EXECUTE'),
  'A2: authenticated and anon hold NO EXECUTE on the machine entrypoint');
SELECT ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
            WHERE n.nspname='venue' AND p.proname IN ('get_door_manifest_door','_get_door_manifest_core')
              AND a.privilege_type='EXECUTE' AND a.grantee = 0),
  'A3: PUBLIC holds NO EXECUTE on either new function (explicitly revoked)');
SELECT ok(NOT has_function_privilege('service_role', 'venue._get_door_manifest_core(uuid,integer)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'venue._get_door_manifest_core(uuid,integer)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue._get_door_manifest_core(uuid,integer)', 'EXECUTE'),
  'A4: the core is ZERO-grant (service_role, authenticated, anon)');
SELECT ok(has_function_privilege('authenticated', 'venue.get_door_manifest(uuid,integer)', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'venue.get_door_manifest(uuid,integer)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.get_door_manifest(uuid,integer)', 'EXECUTE'),
  'A5: the STAFF RPC grants are unchanged (authenticated yes; service_role and anon no)');
SELECT is((SELECT count(*)::int FROM pg_proc p WHERE p.oid IN ('venue.get_door_manifest(uuid,integer)'::regprocedure,
             'venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)'::regprocedure, 'venue._get_door_manifest_core(uuid,integer)'::regprocedure)
             AND p.prosecdef AND p.proconfig::text LIKE '%search_path=%'), 3,
  'A6: all three are SECURITY DEFINER with pinned search_path (066 invariant)');
SELECT is((SELECT provolatile FROM pg_proc WHERE oid = 'venue.get_door_manifest_door(uuid,uuid,text,uuid,integer)'::regprocedure), 'v',
  'A7: the machine entrypoint is VOLATILE (assert_door_session touches last_seen_at)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='venue'), 85,
  'A8: venue holds 85 functions — 83 post-108 + 113''s core and machine entrypoint');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 294,
  'A9: five-schema routine census 294 (292 post-111 + 113''s two)');

-- ── B. valid bound device — full + incremental sync, identical to the staff read ──
SELECT tap.login_service();
SELECT tap._store179('door_full', venue.get_door_manifest_door(tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'), tap._fetch179('dev')::uuid, 0)::text);
SELECT tap.login(tap.other_user());
SELECT tap._store179('staff_full', venue.get_door_manifest(tap._fetch179('sA')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch179('door_full')::jsonb ->> 'open'), 'true', 'B1: machine full sync ⇒ open:true');
SELECT is((tap._fetch179('door_full')::jsonb ->> 'session_id'), tap._fetch179('sA'), 'B2: …for the BOUND session');
SELECT is((tap._fetch179('door_full')::jsonb ->> 'manifest_id'), tap._fetch179('m1'), 'B3: …the open manifest');
SELECT is(jsonb_array_length(tap._fetch179('door_full')::jsonb -> 'entries'), 3, 'B4: …three entries');
SELECT is(tap._fetch179('door_full')::jsonb, tap._fetch179('staff_full')::jsonb, 'B5: machine read == staff read, byte for byte (112 response preserved: header, stored not_after, privacy exclusions)');
SELECT ok(NOT (tap._fetch179('door_full') LIKE '%public_key%') AND NOT (tap._fetch179('door_full') LIKE '%owner%'), 'B6: never public_key, never identity');
SELECT venue.append_door_manifest_delta(tap._fetch179('sA')::uuid,
  ARRAY[(SELECT ticket_atom_id FROM venue.door_manifest_entry WHERE manifest_id = tap._fetch179('m1')::uuid ORDER BY serial_no LIMIT 1)],
  'revoke', gen_random_uuid());
SELECT tap.login_service();
SELECT tap._store179('door_since0', venue.get_door_manifest_door(tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'), tap._fetch179('dev')::uuid, 0)::text);
SELECT tap._store179('door_since1', venue.get_door_manifest_door(tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'), tap._fetch179('dev')::uuid, 1)::text);
SELECT tap._store179('door_sinceNull', venue.get_door_manifest_door(tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'), tap._fetch179('dev')::uuid, NULL)::text);
SELECT tap.logout();
SELECT is(jsonb_array_length(tap._fetch179('door_since0')::jsonb -> 'deltas'), 1, 'B7: incremental since 0 ⇒ the revoke delta');
SELECT is((tap._fetch179('door_since0')::jsonb ->> 'max_delta_seq'), '1', 'B8: …header max_delta_seq 1');
SELECT is(jsonb_array_length(tap._fetch179('door_since1')::jsonb -> 'deltas'), 0, 'B9: since 1 ⇒ nothing new');
SELECT is(jsonb_array_length(tap._fetch179('door_sinceNull')::jsonb -> 'deltas'), 1, 'B10: NULL since ⇒ full (the edge passes null when the body omits since_delta_seq)');

-- ── C. wrong token / device / session / unknown id — opaque door_session_invalid ──
SELECT tap.login_service();
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), 'not-the-secret', tap._fetch179('dev')),
  '%door_session_invalid%', 'C1: wrong token ⇒ door_session_invalid');
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), tap._fetch179('secret'), gen_random_uuid()),
  '%door_session_invalid%', 'C2: wrong device (body cross-check disagrees with the bound row) ⇒ door_session_invalid');
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sB'), tap._fetch179('dsid'), tap._fetch179('secret'), tap._fetch179('dev')),
  '%door_session_invalid%', 'C3: wrong session (session B with a door session bound to A) ⇒ door_session_invalid — the machine cannot pick scope');
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), gen_random_uuid(), tap._fetch179('secret'), tap._fetch179('dev')),
  '%door_session_invalid%', 'C4: unknown door_session_id ⇒ door_session_invalid (not not_found)');
SELECT throws_ok(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), 'not-the-secret', tap._fetch179('dev')),
  '42501', NULL, 'C5: …all under the ONE opaque class 42501');
SELECT tap.logout();

-- ── D. service_role without valid credentials; direct anon/authenticated calls ──
SELECT tap.login_service();
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), gen_random_uuid(), '', gen_random_uuid()),
  '%door_session_invalid%', 'D1: service_role with no valid door credentials ⇒ refused (the grant alone authorizes nothing)');
SELECT throws_ok(format($q$SELECT venue._get_door_manifest_core(%L,0)$q$, tap._fetch179('sA')), '42501', NULL, 'D2: service_role cannot call the core directly');
SELECT tap.login_anon();
SELECT throws_ok(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), tap._fetch179('secret'), tap._fetch179('dev')),
  '42501', NULL, 'D3: anon cannot call the machine entrypoint even with VALID door credentials');
SELECT throws_ok(format($q$SELECT venue._get_door_manifest_core(%L,0)$q$, tap._fetch179('sA')), '42501', NULL, 'D4: anon cannot call the core');
SELECT tap.login(tap.other_user());
SELECT throws_ok(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), tap._fetch179('secret'), tap._fetch179('dev')),
  '42501', NULL, 'D5: an authenticated staff scanner cannot call the machine entrypoint even with VALID door credentials (grant class, not role)');
SELECT throws_ok(format($q$SELECT venue._get_door_manifest_core(%L,0)$q$, tap._fetch179('sA')), '42501', NULL, 'D6: authenticated cannot call the core');
SELECT tap.logout();

-- ── E. staff behaviour unchanged (178 is the full matrix; the boundary is re-pinned here) ──
SELECT tap.login(tap.other_user());
SELECT is((venue.get_door_manifest(tap._fetch179('sA')::uuid, 1) ->> 'open'), 'true', 'E1: authorized staff read still works (scanner)');
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($q$SELECT venue.get_door_manifest(%L, 0)$q$, tap._fetch179('sA')), '42501', NULL, 'E2: unauthorized staff read still refused insufficient_privilege');
SELECT tap.login_service();
SELECT throws_ok(format($q$SELECT venue.get_door_manifest(%L, 0)$q$, tap._fetch179('sA')), '42501', NULL, 'E3: service_role still cannot call the STAFF RPC (the machine path is the only door route)');
SELECT tap.logout();

-- ── F. closed / expired manifest through the machine path ───────────────────
SELECT tap.login(tap.seller());
SELECT is((venue.close_door_manifest(tap._fetch179('sA')::uuid,'doors_closed','dm179-c1') ->> 'status'), 'ok', 'F1: close the episode');
SELECT tap.login_service();
SELECT tap._store179('door_closed', venue.get_door_manifest_door(tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'), tap._fetch179('dev')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch179('door_closed')::jsonb ->> 'open'), 'false', 'F2: closed ⇒ open:false through the machine path');
SELECT is((tap._fetch179('door_closed')::jsonb ->> 'status'), 'no_open_episode', 'F3: …compatible status');
SELECT is(jsonb_array_length(tap._fetch179('door_closed')::jsonb -> 'entries') + jsonb_array_length(tap._fetch179('door_closed')::jsonb -> 'deltas'), 0, 'F4: …empty arrays');
SELECT tap.login(tap.seller());
SELECT tap._store179('m2', (venue.open_door_manifest(tap._fetch179('sA')::uuid,'doors_open','dm179-d2') ->> 'manifest_id'));
SELECT tap.logout();
ALTER TABLE venue.door_manifest DISABLE TRIGGER tg_door_manifest_transition;
UPDATE venue.door_manifest SET opened_at = now() - interval '3 hours', not_after = now() - interval '1 second' WHERE manifest_id = tap._fetch179('m2')::uuid;
ALTER TABLE venue.door_manifest ENABLE TRIGGER tg_door_manifest_transition;
SELECT tap.login_service();
SELECT tap._store179('door_expired', venue.get_door_manifest_door(tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'), tap._fetch179('dev')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch179('door_expired')::jsonb ->> 'open'), 'false', 'F5: an episode past its STORED not_after ⇒ open:false through the machine path (row untouched)');
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch179('m2')::uuid), 'open', 'F6: …the row is untouched (no expiry written)');

-- ── G. credentials invalidated BETWEEN the edge's admit check and the machine RPC ──
SELECT tap.login_service();
SELECT is((SELECT event_session_id::text FROM kernel.assert_door_session(tap._fetch179('dev')::uuid, tap._fetch179('sA')::uuid, tap._fetch179('dsid')::uuid, tap._fetch179('secret'))),
  tap._fetch179('sA'), 'G1: the edge''s admit check (assert_door_session) passes');
SELECT tap.login(tap.seller());   -- venue_manager revokes (the operator action)
SELECT is((venue.revoke_door_session(tap._fetch179('dsid')::uuid, 'operator_revoked', 'dm179-rv') ->> 'status'), 'ok', 'G2: …then the door session is revoked by the venue manager');
SELECT tap.login_service();
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), tap._fetch179('secret'), tap._fetch179('dev')),
  '%door_session_invalid%', 'G3: the machine RPC re-asserts and refuses — the earlier edge check is NOT a substitute for the database-side gate');
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), tap._fetch179('dsid'), tap._fetch179('secret'), tap._fetch179('dev')),
  '%door_session_invalid%', 'G4: revoked door session ⇒ door_session_invalid (repeatably)');
-- expired door session: a fresh mint, then its expiry backdated (no guard trigger on door_session).
SELECT tap._store179('mint2', (venue.mint_door_session(tap._fetch179('venue')::uuid, tap._fetch179('sA')::uuid, tap._fetch179('dev')::uuid, 'pin-179', 'dm179-mint2')::text));
SELECT tap.logout();
SELECT is((tap._fetch179('mint2')::jsonb ->> 'status'), 'ok', 'G5: a second door session mints after the revoke');
UPDATE venue.door_session SET issued_at = now() - interval '3 hours', expires_at = now() - interval '1 second' WHERE door_session_id = (tap._fetch179('mint2')::jsonb ->> 'door_session_id')::uuid;   -- window_ck: expires_at > issued_at
SELECT tap.login_service();
SELECT throws_like(format($q$SELECT venue.get_door_manifest_door(%L,%L,%L,%L,0)$q$, tap._fetch179('sA'), (tap._fetch179('mint2')::jsonb ->> 'door_session_id'), (tap._fetch179('mint2')::jsonb ->> 'secret'), tap._fetch179('dev')),
  '%door_session_invalid%', 'G6: expired door session ⇒ door_session_invalid');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
