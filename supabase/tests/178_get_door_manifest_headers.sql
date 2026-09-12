-- ============================================================================
-- 178_get_door_manifest_headers.sql — migration 112 (P1-M2-HEADER).
--   venue.get_door_manifest returns the stored manifest header (open, session_id,
--   opened_at, not_after) with the unchanged entry/delta projections; the no-
--   episode result carries open:false + the compatible status + empty arrays;
--   an episode past its stored not_after is reported open:false (door §7.5)
--   while the row stays untouched; grants/authorization/privacy unchanged;
--   the service_role door path is (still) unauthorized — recorded as the open
--   P1-M2-DOOR-AUTHZ finding.
-- ============================================================================
BEGIN;
SELECT plan(41);
SELECT tap.seed_core();

CREATE TABLE tap.memo_178 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store178(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_178 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch178(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_178 WHERE k=$1 $m$;

-- ── FIXTURE — venue (approved), seller = venue_manager, other_user = venue_scanner,
-- one event/session, 2 comp atoms, an open episode. ──────────────────────────
SELECT tap.login(tap.seller());
SELECT tap._store178('org', (kernel.create_organization('GM Co','GM Co','gm178-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch178('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store178('venue', (catalog.create_venue(tap._fetch178('org')::uuid,'GM Hall','wynwood',NULL,'gm178-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch178('venue')::uuid,'approved','miami_gate','gm178-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch178('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()),
       (tap._fetch178('venue')::uuid, tap.other_user(), 'venue_scanner', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store178('e', (catalog.create_event(tap._fetch178('venue')::uuid,'GM Night',
  jsonb_build_object('starts_at',(now()+interval '9 days')::text,'ends_at',(now()+interval '9 days 5 hours')::text),'gm178-e') ->> 'event_id'));
SELECT tap._store178('s', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch178('e')::uuid));
SELECT tap._store178('tt', (venue.create_ticket_type(tap._fetch178('e')::uuid,'admission','GA',5000,'public','gm178-tt') ->> 'ticket_type_id'));
SELECT tap._store178('b', (venue.create_inventory_batch(tap._fetch178('tt')::uuid, tap._fetch178('s')::uuid, 'comp', 100, 0, 'gm178-b') ->> 'batch_id'));
SELECT tap.logout();
WITH k AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch178('e')::uuid, 'PUBKEY-178', 'kms-178', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store178('k', (SELECT key_id::text FROM k));
SELECT kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch178('s')::uuid,'org_id',tap._fetch178('org')::uuid,'ticket_type_id',tap._fetch178('tt')::uuid,
  'batch_id',tap._fetch178('b')::uuid,'owner_id',tap.buyer(),'quantity',2,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch178('k')::uuid),'gm178-m');
SELECT tap.login(tap.seller());
SELECT tap._store178('m1', (venue.open_door_manifest(tap._fetch178('s')::uuid,'doors_open','gm178-d1') ->> 'manifest_id'));
SELECT tap.logout();

-- ── A. grants / authorization surface (unchanged; the door path is the open finding) ──
SELECT ok(has_function_privilege('authenticated', 'venue.get_door_manifest(uuid,integer)', 'EXECUTE'), 'A1: authenticated may EXECUTE (unchanged)');
SELECT ok(NOT has_function_privilege('service_role', 'venue.get_door_manifest(uuid,integer)', 'EXECUTE'),
  'A2: service_role holds NO EXECUTE — the door-session /manifest/sync relay (service_role client) cannot reach this RPC (P1-M2-DOOR-AUTHZ, recorded, unchanged here)');
SELECT ok(NOT has_function_privilege('anon', 'venue.get_door_manifest(uuid,integer)', 'EXECUTE'), 'A3: anon has no EXECUTE (unchanged)');
SELECT ok((SELECT prosecdef AND proconfig::text LIKE '%search_path=%' FROM pg_proc WHERE oid = 'venue.get_door_manifest(uuid,integer)'::regprocedure),
  'A4: SECURITY DEFINER with pinned search_path (066 invariant)');

-- ── B. open episode — full snapshot as venue_scanner ─────────────────────────
SELECT tap.login(tap.other_user());
SELECT tap._store178('full', venue.get_door_manifest(tap._fetch178('s')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch178('full')::jsonb ->> 'open'), 'true', 'B1: open:true');
SELECT is((tap._fetch178('full')::jsonb ->> 'status'), 'ok', 'B2: status ok (compatible with 150 D10)');
SELECT is((tap._fetch178('full')::jsonb ->> 'session_id'), tap._fetch178('s'), 'B3: session_id is the manifest''s session (MP1-READ-SET header)');
SELECT is((tap._fetch178('full')::jsonb ->> 'manifest_id'), tap._fetch178('m1'), 'B4: manifest_id');
SELECT is((tap._fetch178('full')::jsonb ->> 'manifest_version'), '1', 'B5: manifest_version 1');
SELECT is(((tap._fetch178('full')::jsonb ->> 'not_after')::timestamptz), (SELECT not_after FROM venue.door_manifest WHERE manifest_id = tap._fetch178('m1')::uuid),
  'B6: not_after is the STORED row value (never manufactured at fetch)');
SELECT is(((tap._fetch178('full')::jsonb ->> 'opened_at')::timestamptz), (SELECT opened_at FROM venue.door_manifest WHERE manifest_id = tap._fetch178('m1')::uuid),
  'B7: opened_at is the stored row value');
SELECT is((tap._fetch178('full')::jsonb ->> 'manifest_digest'), (SELECT manifest_digest FROM venue.door_manifest WHERE manifest_id = tap._fetch178('m1')::uuid), 'B8: manifest_digest is the stored digest');
SELECT is((tap._fetch178('full')::jsonb ->> 'max_delta_seq'), '0', 'B9: max_delta_seq 0 before any delta');
SELECT is(jsonb_array_length(tap._fetch178('full')::jsonb -> 'entries'), 2, 'B10: two entries (the two comp atoms)');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch178('full')::jsonb -> 'entries' -> 0) k)::text[],
  ARRAY['credential_version','resale_state','serial_no','signing_key_id','ticket_atom_id','ticket_state','ticket_type_id'],
  'B11: entry projection is exactly the 086 seven fields (MP1 per-atom set + operator extras)');
SELECT ok(NOT ((tap._fetch178('full')::jsonb)::text LIKE '%public_key%') AND NOT ((tap._fetch178('full')::jsonb)::text LIKE '%owner%'),
  'B12: never public_key, never identity (PFA-24)');
SELECT is(jsonb_array_length(tap._fetch178('full')::jsonb -> 'deltas'), 0, 'B13: no deltas yet');
SELECT is((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(tap._fetch178('full')::jsonb) k)::text[],
  ARRAY['deltas','entries','manifest_digest','manifest_id','manifest_version','max_delta_seq','not_after','open','opened_at','session_id','status'],
  'B14: header key set = 086''s seven + open/session_id/opened_at/not_after');

-- ── C. incremental deltas ───────────────────────────────────────────────────
SELECT venue.append_door_manifest_delta(tap._fetch178('s')::uuid,
  ARRAY[(SELECT ticket_atom_id FROM venue.door_manifest_entry WHERE manifest_id = tap._fetch178('m1')::uuid ORDER BY serial_no LIMIT 1)],
  'revoke', gen_random_uuid());
SELECT tap.login(tap.other_user());
SELECT tap._store178('since0', venue.get_door_manifest(tap._fetch178('s')::uuid, 0)::text);
SELECT tap._store178('since1', venue.get_door_manifest(tap._fetch178('s')::uuid, 1)::text);
SELECT tap._store178('sinceNull', venue.get_door_manifest(tap._fetch178('s')::uuid, NULL)::text);
SELECT tap.logout();
SELECT is(jsonb_array_length(tap._fetch178('since0')::jsonb -> 'deltas'), 1, 'C1: since 0 ⇒ the revoke delta');
SELECT is((tap._fetch178('since0')::jsonb -> 'deltas' -> 0 ->> 'op'), 'revoke', 'C2: …op=revoke');
SELECT is((tap._fetch178('since0')::jsonb ->> 'max_delta_seq'), '1', 'C3: header max_delta_seq advanced to 1');
SELECT is(jsonb_array_length(tap._fetch178('since1')::jsonb -> 'deltas'), 0, 'C4: since 1 ⇒ no deltas (already synced)');
SELECT is(jsonb_array_length(tap._fetch178('since1')::jsonb -> 'entries'), 2, 'C5: entries still returned (086 superset behaviour preserved)');
SELECT is(jsonb_array_length(tap._fetch178('sinceNull')::jsonb -> 'deltas'), 1, 'C6: NULL since ⇒ full (coalesce 0), unchanged');
SELECT is((tap._fetch178('since1')::jsonb ->> 'session_id'), tap._fetch178('s'), 'C7: header present on incremental reads too');

-- ── D. unauthorized / wrong-session callers ─────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(format($q$SELECT venue.get_door_manifest(%L, 0)$q$, tap._fetch178('s')), '42501', NULL, 'D1: a non-staff identity is refused insufficient_privilege');
SELECT throws_ok($q$SELECT venue.get_door_manifest(gen_random_uuid(), 0)$q$, '42501', NULL, 'D2: an unknown session (no venue resolves) is refused, not "no episode"');
SELECT tap.login_anon();
SELECT throws_ok(format($q$SELECT venue.get_door_manifest(%L, 0)$q$, tap._fetch178('s')), NULL, NULL, 'D3: anon cannot call it');
SELECT tap.login_service();
SELECT throws_ok(format($q$SELECT venue.get_door_manifest(%L, 0)$q$, tap._fetch178('s')), NULL, NULL,
  'D4: service_role (the door-session relay principal) is refused — P1-M2-DOOR-AUTHZ recorded, unchanged by 112');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT throws_ok($q$SELECT venue.get_door_manifest(gen_random_uuid(), 0)$q$, '42501', NULL, 'D5: a scanner asking for a session outside its venue is refused');
SELECT tap.logout();

-- ── E. closed episode ───────────────────────────────────────────────────────
SELECT tap.login(tap.seller());
SELECT is((venue.close_door_manifest(tap._fetch178('s')::uuid,'doors_closed','gm178-c1') ->> 'status'), 'ok', 'E1: close the episode');
SELECT tap.login(tap.other_user());
SELECT tap._store178('closed', venue.get_door_manifest(tap._fetch178('s')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch178('closed')::jsonb ->> 'open'), 'false', 'E2: closed ⇒ open:false');
SELECT is((tap._fetch178('closed')::jsonb ->> 'status'), 'no_open_episode', 'E3: the compatible status string is preserved (171 F5)');
SELECT is(jsonb_array_length(tap._fetch178('closed')::jsonb -> 'entries'), 0, 'E4: entries []');
SELECT is(jsonb_array_length(tap._fetch178('closed')::jsonb -> 'deltas'), 0, 'E5: deltas []');
SELECT ok(NOT (tap._fetch178('closed')::jsonb ? 'session_id') AND NOT (tap._fetch178('closed')::jsonb ? 'manifest_id'),
  'E6: a closed result carries no header (nothing to bind authority to)');

-- ── F. expired-but-open episode (door §7.5 precondition) ─────────────────────
-- now() is frozen for this whole (rolled-back) suite transaction, so the clock
-- cannot "pass" here; the stored window is backdated instead — trigger disabled
-- as superuser for the fixture only — which ALSO proves the RPC reads the
-- STORED not_after (the only thing it could compare against).
SELECT tap.login(tap.seller());
SELECT tap._store178('m2', (venue.open_door_manifest(tap._fetch178('s')::uuid,'doors_open','gm178-d2') ->> 'manifest_id'));
SELECT tap.login(tap.other_user());
SELECT tap._store178('fresh', venue.get_door_manifest(tap._fetch178('s')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch178('fresh')::jsonb ->> 'open'), 'true', 'F1: the re-opened episode (v2) is open while inside its stored window');
SELECT is((tap._fetch178('fresh')::jsonb ->> 'manifest_version'), '2', 'F2: manifest_version 2');
ALTER TABLE venue.door_manifest DISABLE TRIGGER tg_door_manifest_transition;
UPDATE venue.door_manifest SET opened_at = now() - interval '3 hours', not_after = now() - interval '1 second' WHERE manifest_id = tap._fetch178('m2')::uuid;
ALTER TABLE venue.door_manifest ENABLE TRIGGER tg_door_manifest_transition;
SELECT tap.login(tap.other_user());
SELECT tap._store178('expired', venue.get_door_manifest(tap._fetch178('s')::uuid, 0)::text);
SELECT tap.logout();
SELECT is((tap._fetch178('expired')::jsonb ->> 'open'), 'false', 'F3: past its stored not_after the episode is reported open:false (fail closed at the source)');
SELECT is((SELECT status FROM venue.door_manifest WHERE manifest_id = tap._fetch178('m2')::uuid), 'open', 'F4: …while the row itself is untouched by the read (status still open; no expiry written)');
SELECT is((SELECT not_after FROM venue.door_manifest WHERE manifest_id = tap._fetch178('m2')::uuid) < now(), true, 'F5: the stored not_after really is in the past');

SELECT * FROM finish();
ROLLBACK;
