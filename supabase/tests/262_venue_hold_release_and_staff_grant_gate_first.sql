-- ============================================================================
-- 262_venue_hold_release_and_staff_grant_gate_first.sql — migration 20261030090000 (registry 193).
--
-- Registry 193 (allocated by Claude A 2026-10-30, pre-Stage-8 hardening); pgTAP 262 is the next
-- free number (260 = #179/190, 261 = 192; A to confirm). E reviews the exact head. DARK.
--
--   Section A  posture: both bodies are 193's (functiondef md5), SECURITY DEFINER, search_path = '',
--              EXECUTE exactly owner + authenticated (create or replace changed no grant).
--   Section S  the sweep with NO JWT (this file's first statements: request.jwt.claims unset, the
--              pg_cron context) still expires an expired hold through the engine's NULL-uid branch.
--   Section N  NEGATIVE CONTROLS, release_inventory_hold: a non-holder, non-staff caller gets the
--              SAME 42501 for an existing active hold, an unknown hold id and someone else's
--              released hold (no status leak, no noop_replay); a manager of ANOTHER venue too; an
--              `authenticated` JWT with no `sub` (NULL uid, not the service path) refuses; nothing
--              changed.
--   Section L  legitimate release paths unchanged: the holder releases (ok, counters, movement),
--              re-release and an own released hold are noop_replay, venue staff release a holder's
--              hold, the sweep under a service_role JWT. N8 (in L's flow): claims = '' with no sub
--              (tap.logout's persona, produced by no production path) is refused like any other
--              non-service NULL uid.
--   Section G  NEGATIVE CONTROLS, grant_staff_role: an unaffiliated caller and a manager of another
--              venue get the SAME 42501 for an existing, a nonexistent and an ERASED target, for an
--              unknown venue and for a self-grant; nothing written. Legitimate paths unchanged: the
--              org owner and the venue manager grant, re-grant is noop_replay, tier_guard and
--              self_grant still answer authorized callers; a nonexistent and an ERASED target give
--              ONE refusal (P0002 'not_found: identity <id>', identical shape).
--
-- Positive-path calls go through tap._val262 (the call's text, or {"error": "<SQLSTATE>|<SQLERRM>"}),
-- so a wrongful refusal or a gate-removal mutant reads `not ok` instead of aborting (232/234/261).
--
-- Fixture: synthetic rows as postgres, fixed ids, tag 26200000-…, rolled back. Org A (owner 121)
-- runs room V1 (manager 111, scanner 114); Org B runs room V3 (manager 131). Holder 101, other
-- buyer 102, fan 199. Grant targets: 151 (ordinary), 152 (ERASED tombstone: auth.users row kept,
-- identity_ext ERASED, as the deletion sweep leaves it), 26200000-…-00000000dead (no such user).
-- Event e01 at V1, session f01, tier d01, batch c01 (capacity 20). Holds of 101 on c01:
-- h1 active 1, h2 active 2, h3 released 1, h4 active 1, h5 active 2 EXPIRED; held = 6.
--
-- RED, measured on main c4f48885 WITHOUT 193 (a154c_green + main's migrations; CI emulation):
-- 35 emitted, nothing aborts — 20 ok + 15 not ok: A2 (predecessor md5s); N2 (P0002 not_found:
-- hold), N3 (noop_replay with the status), N4 (three different answers), N6 (an authenticated JWT
-- with no sub passes the 081 NULL-uid branch and RELEASES h4), N7 (h4 released), N8 (claims ''
-- with no sub passes it too); GN2 (P0002 identity), GN3 (identity_erased), GN4, GN5 (P0002 venue),
-- GN6 (self_grant), GN7 (identity_erased before the gate); GL5 (P0001 identity_erased), GL6.
-- S1, every L and GL1-4/7-9 pass on RED too: the sweep and the legitimate paths are unchanged.
-- Gate-removal mutants (193 with one block undone; 35 emitted each, never aborts):
--   release gate removed -> A2 N1-N8 (+ L1 L2 L5, consequential); NULL-uid restriction removed -> A2 N6 N7 N8;
--   '' accepted again (the pre-narrowing gate) -> A2 N8;
--   grant gate removed -> A2 GN1-GN8 (+ GL1 GL8 GL9, consequential); identity collapse undone -> A2 GL5 GL6.
-- ============================================================================
BEGIN;
SELECT plan(35);

CREATE TABLE tap.memo_262 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store262(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_262 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch262(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_262 WHERE k = $1 $m$;
-- the text a statement returns AS THE CALLER, or {"error": "<SQLSTATE>|<SQLERRM>"} (a JSON object either way)
CREATE FUNCTION tap._val262(q text) RETURNS text
LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE || '|' || SQLERRM)::text; END $m$;
GRANT EXECUTE ON FUNCTION tap._store262(text, text), tap._fetch262(text), tap._val262(text) TO authenticated, service_role;
GRANT SELECT, INSERT, UPDATE ON tap.memo_262 TO authenticated, service_role;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT u.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.email,
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM (VALUES ('26200000-0000-4000-8000-000000000101', 'holder.262@test.local'),
               ('26200000-0000-4000-8000-000000000102', 'other.262@test.local'),
               ('26200000-0000-4000-8000-000000000111', 'mgr.v1.262@test.local'),
               ('26200000-0000-4000-8000-000000000114', 'scan.v1.262@test.local'),
               ('26200000-0000-4000-8000-000000000121', 'owner.a.262@test.local'),
               ('26200000-0000-4000-8000-000000000131', 'mgr.v3.262@test.local'),
               ('26200000-0000-4000-8000-000000000151', 'target.262@test.local'),
               ('26200000-0000-4000-8000-000000000152', 'erased.262@test.local'),
               ('26200000-0000-4000-8000-000000000199', 'fan.262@test.local')) u(id, email)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.identity_ext (identity_id, deletion_state) VALUES
  ('26200000-0000-4000-8000-000000000152', 'ERASED')
ON CONFLICT (identity_id) DO UPDATE SET deletion_state = 'ERASED';
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('26200000-0000-4000-8000-00000000000a', 'Org A 262', 'Org A 262', 'active'),
  ('26200000-0000-4000-8000-00000000000b', 'Org B 262', 'Org B 262', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('26200000-0000-4000-8000-00000000000a', '26200000-0000-4000-8000-000000000121', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('26200000-0000-4000-8000-0000000000a1', '26200000-0000-4000-8000-00000000000a', 'Room V1 262', 'wynwood', 'approved'),
  ('26200000-0000-4000-8000-0000000000b3', '26200000-0000-4000-8000-00000000000b', 'Room V3 262', 'midtown', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('26200000-0000-4000-8000-0000000000a1', '26200000-0000-4000-8000-000000000111', 'venue_manager'),
  ('26200000-0000-4000-8000-0000000000a1', '26200000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('26200000-0000-4000-8000-0000000000b3', '26200000-0000-4000-8000-000000000131', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('26200000-0000-4000-8000-00000000e001', '26200000-0000-4000-8000-0000000000a1', '26200000-0000-4000-8000-00000000000a', 'e01 V1 262', 'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, status) VALUES
  ('26200000-0000-4000-8000-00000000f001', '26200000-0000-4000-8000-00000000e001', NULL, '2027-03-01 01:00:00+00', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('26200000-0000-4000-8000-00000000d001', '26200000-0000-4000-8000-00000000e001', 'admission', 'GA 262', 2500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-00000000d001', '26200000-0000-4000-8000-00000000f001', 'public_sale', 20, 6, 0);
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('26200000-0000-4000-8000-0000000000f1', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 1, 'active',   now() + interval '1 hour',   'ck-262-h1'),
  ('26200000-0000-4000-8000-0000000000f2', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 2, 'active',   now() + interval '1 hour',   'ck-262-h2'),
  ('26200000-0000-4000-8000-0000000000f3', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 1, 'released', now() + interval '1 hour',   'ck-262-h3'),
  ('26200000-0000-4000-8000-0000000000f4', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 1, 'active',   now() + interval '1 hour',   'ck-262-h4'),
  ('26200000-0000-4000-8000-0000000000f5', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 2, 'active',   now() - interval '1 minute', 'ck-262-h5');

-- ── Section S — the no-JWT sweep (FIRST: this session has never set request.jwt.claims) ───────
SELECT tap._store262('s_claims_null', (current_setting('request.jwt.claims', true) IS NULL)::text);
SELECT tap._store262('s1', tap._val262($q$SELECT venue.sweep_expired_inventory_holds()::text$q$));
SELECT is((SELECT (tap._fetch262('s_claims_null'), tap._fetch262('s1')::jsonb ->> 'swept', tap._fetch262('s1')::jsonb ->> 'errors',
                   (SELECT status FROM venue.inventory_hold WHERE hold_id = '26200000-0000-4000-8000-0000000000f5'),
                   (SELECT held FROM venue.inventory_batch WHERE batch_id = '26200000-0000-4000-8000-00000000c001'))::text),
  '(true,1,0,expired,4)',
  'S1: with NO JWT (claims unset: the pg_cron context) the sweep still expires the one expired hold through the engine (held 6 -> 4)');

-- ── Section A — posture ────────────────────────────────────────────────────
SELECT set_eq(
  $$ SELECT p.proname || '|' || p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ','), '-') || '|'
            || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE p.oid IN ('venue.release_inventory_hold(uuid,text)'::regprocedure, 'venue.grant_staff_role(uuid,uuid,text,text)'::regprocedure) $$,
  $$ VALUES ('release_inventory_hold|true|search_path=""|postgres:EXECUTE'), ('release_inventory_hold|true|search_path=""|authenticated:EXECUTE'),
            ('grant_staff_role|true|search_path=""|postgres:EXECUTE'),       ('grant_staff_role|true|search_path=""|authenticated:EXECUTE') $$,
  'A1: both stay SECURITY DEFINER with search_path = '''' and EXECUTE exactly owner + authenticated (no grant changed)');
SELECT is((SELECT string_agg(p.proname || '=' || md5(pg_get_functiondef(p.oid)), ' ' ORDER BY p.proname)
             FROM pg_proc p WHERE p.oid IN ('venue.release_inventory_hold(uuid,text)'::regprocedure, 'venue.grant_staff_role(uuid,uuid,text,text)'::regprocedure)),
  'grant_staff_role=3923ba5f9aba4512872693a0588bf353 release_inventory_hold=b981bef80b10455a0c45a6e908c91aec',
  'A2: both bodies are 193''s (the pre-flight / post-flight / rollback anchor)');

-- ── Section N — release_inventory_hold negative controls ────────────────────
SELECT tap.login('26200000-0000-4000-8000-000000000102');
SELECT tap._store262('n_active',  tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f1', 'n-262-1')::text$q$));
SELECT tap._store262('n_unknown', tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-00000000dead', 'n-262-2')::text$q$));
SELECT tap._store262('n_done',    tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f3', 'n-262-3')::text$q$));
SELECT tap.logout();
SELECT is(tap._fetch262('n_active')::jsonb ->> 'error', '42501|insufficient_privilege: not the holder or venue staff',
  'N1: another buyer releasing the holder''s ACTIVE hold -> 42501');
SELECT is(tap._fetch262('n_unknown')::jsonb ->> 'error', '42501|insufficient_privilege: not the holder or venue staff',
  'N2: …an UNKNOWN hold id -> the same 42501 (no not_found oracle)');
SELECT is(tap._fetch262('n_done')::jsonb ->> 'error', '42501|insufficient_privilege: not the holder or venue staff',
  'N3: …the holder''s RELEASED hold -> the same 42501 (no noop_replay, no status leak)');
SELECT is((SELECT count(DISTINCT v)::int FROM tap.memo_262 WHERE k IN ('n_active','n_unknown','n_done')), 1,
  'N4: the three answers are byte-identical (existence and status are indistinguishable to a non-holder)');
SELECT tap.login('26200000-0000-4000-8000-000000000131');
SELECT is(tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f2', 'n-262-5')::text$q$)::jsonb ->> 'error',
  '42501|insufficient_privilege: not the holder or venue staff',
  'N5: a venue_manager of ANOTHER venue -> the same 42501');
SELECT tap.logout();
-- an `authenticated` JWT that carries no subject: auth.uid() is NULL but this is NOT the service path
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT is(tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f4', 'n-262-6')::text$q$)::jsonb ->> 'error',
  '42501|insufficient_privilege: not the holder or venue staff',
  'N6: an authenticated JWT with no sub (NULL uid) refuses — the NULL-uid branch is the service path only');
SELECT tap.logout();
SELECT is((SELECT string_agg(h.status, ',' ORDER BY h.hold_id) || '|' || b.held || '|'
                  || (SELECT count(*) FROM venue.inventory_movement m WHERE m.movement_kind = 'release' AND m.cause_ref IN
                       ('26200000-0000-4000-8000-0000000000f1','26200000-0000-4000-8000-0000000000f2','26200000-0000-4000-8000-0000000000f3','26200000-0000-4000-8000-0000000000f4'))
             FROM venue.inventory_hold h, venue.inventory_batch b
            WHERE b.batch_id = '26200000-0000-4000-8000-00000000c001' AND h.batch_id = b.batch_id
            GROUP BY b.held),
  'active,active,released,active,expired|4|0',
  'N7: nothing changed — h1 h2 h4 still active, h3 released, held 4, no release movement for them');

-- ── Section L — legitimate release paths unchanged ───────────────────────────
SELECT tap.login('26200000-0000-4000-8000-000000000101');
SELECT tap._store262('l1', tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f1', 'l-262-1')::text$q$));
SELECT tap.logout();
SELECT is((SELECT (tap._fetch262('l1')::jsonb ->> 'status', (tap._fetch262('l1')::jsonb ->> 'remaining')::int = b.capacity - b.held - b.sold)::text
             FROM venue.inventory_batch b WHERE b.batch_id = '26200000-0000-4000-8000-00000000c001'),
  '(ok,t)',
  'L1: the holder releases her active hold -> {status ok, remaining = the batch''s capacity - held - sold}');
SELECT is((SELECT (h.status, (SELECT (m.delta_held, m.actor_identity)::text FROM venue.inventory_movement m
                                 WHERE m.cause_ref = h.hold_id AND m.movement_kind = 'release'))::text
             FROM venue.inventory_hold h WHERE h.hold_id = '26200000-0000-4000-8000-0000000000f1'),
  '(released,"(-1,26200000-0000-4000-8000-000000000101)")',
  'L2: …the hold is released and the release movement (-1) names the holder');
SELECT tap.login('26200000-0000-4000-8000-000000000101');
SELECT is(tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f1', 'l-262-3')::text$q$),
  '{"status": "noop_replay", "hold_status": "released"}',
  'L3: releasing it again is the terminal-state noop_replay (for the holder)');
SELECT is(tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f3', 'l-262-4')::text$q$),
  '{"status": "noop_replay", "hold_status": "released"}',
  'L4: the holder''s own already-released hold is noop_replay with its status (unchanged)');
SELECT tap.logout();
SELECT tap.login('26200000-0000-4000-8000-000000000114');
SELECT tap._store262('l5', tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f2', 'l-262-5')::text$q$));
SELECT tap.logout();
SELECT is((SELECT (tap._fetch262('l5')::jsonb ->> 'status', (tap._fetch262('l5')::jsonb ->> 'remaining')::int = b.capacity - b.held - b.sold,
                   (SELECT status FROM venue.inventory_hold WHERE hold_id = '26200000-0000-4000-8000-0000000000f2'))::text
             FROM venue.inventory_batch b WHERE b.batch_id = '26200000-0000-4000-8000-00000000c001'),
  '(ok,t,released)',
  'L5: venue staff (the room''s scanner) release the holder''s hold -> ok, remaining consistent, hold released');
-- the sweep under a service_role JWT (an edge/admin trigger): a fresh expired hold
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('26200000-0000-4000-8000-0000000000f6', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 1, 'active', now() - interval '1 minute', 'ck-262-h6');
UPDATE venue.inventory_batch SET held = held + 1 WHERE batch_id = '26200000-0000-4000-8000-00000000c001';
SELECT set_config('role', 'service_role', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT tap._store262('l6', tap._val262($q$SELECT venue.sweep_expired_inventory_holds()::text$q$));
SELECT tap.logout();
SELECT is((SELECT (tap._fetch262('l6')::jsonb ->> 'swept', tap._fetch262('l6')::jsonb ->> 'errors',
                   (SELECT status FROM venue.inventory_hold WHERE hold_id = '26200000-0000-4000-8000-0000000000f6'))::text),
  '(1,0,expired)',
  'L6: under a service_role JWT the sweep expires the hold (swept 1, errors 0)');
-- claims = '' with no subject (the tap.logout persona): NOT the cron context (cron's claims are NULL,
-- S1) and not a service_role JWT, so the NULL-uid branch refuses — no production path produces ''
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('26200000-0000-4000-8000-0000000000f7', '26200000-0000-4000-8000-00000000c001', '26200000-0000-4000-8000-000000000101', 1, 'active', now() + interval '1 hour', 'ck-262-h7');
UPDATE venue.inventory_batch SET held = held + 1 WHERE batch_id = '26200000-0000-4000-8000-00000000c001';
SELECT tap._store262('n8_claims', current_setting('request.jwt.claims', true));
SELECT tap._store262('n8', tap._val262($q$SELECT venue.release_inventory_hold('26200000-0000-4000-8000-0000000000f7', 'n-262-8')::text$q$));
SELECT is((SELECT (tap._fetch262('n8_claims'), tap._fetch262('n8')::jsonb ->> 'error',
                   (SELECT status FROM venue.inventory_hold WHERE hold_id = '26200000-0000-4000-8000-0000000000f7'))::text),
  '("","42501|insufficient_privilege: not the holder or venue staff",active)',
  'N8: claims = '''' with no sub (not NULL, not service_role) -> the same 42501, and the hold stays active');
SELECT is((SELECT b.held = (SELECT coalesce(sum(h.quantity), 0) FROM venue.inventory_hold h WHERE h.batch_id = b.batch_id AND h.status = 'active')
             FROM venue.inventory_batch b WHERE b.batch_id = '26200000-0000-4000-8000-00000000c001'), true,
  'L8: counters consistent: held equals the sum of the still-active holds after every release and sweep');

-- ── Section G — grant_staff_role ────────────────────────────────────────────
SELECT tap.login('26200000-0000-4000-8000-000000000199');
SELECT tap._store262('g_exist',  tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000151','venue_scanner','g-262-1')::text$q$));
SELECT tap._store262('g_none',   tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-00000000dead','venue_scanner','g-262-2')::text$q$));
SELECT tap._store262('g_erased', tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000152','venue_scanner','g-262-3')::text$q$));
SELECT tap._store262('g_venue',  tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-00000000dead','26200000-0000-4000-8000-000000000151','venue_scanner','g-262-4')::text$q$));
SELECT tap._store262('g_self',   tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000199','venue_scanner','g-262-5')::text$q$));
SELECT tap.logout();
SELECT tap.login('26200000-0000-4000-8000-000000000131');
SELECT tap._store262('g_x_erased', tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000152','venue_scanner','g-262-6')::text$q$));
SELECT tap.logout();
SELECT is(tap._fetch262('g_exist')::jsonb ->> 'error',
  '42501|insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required',
  'GN1: an unaffiliated caller granting to an EXISTING identity -> 42501');
SELECT is(tap._fetch262('g_none')::jsonb ->> 'error',
  '42501|insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required',
  'GN2: …to a NONEXISTENT identity -> the same 42501 (no account-existence oracle)');
SELECT is(tap._fetch262('g_erased')::jsonb ->> 'error',
  '42501|insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required',
  'GN3: …to an ERASED tombstone -> the same 42501 (no deletion oracle)');
SELECT is((SELECT count(DISTINCT v)::int FROM tap.memo_262 WHERE k IN ('g_exist','g_none','g_erased','g_x_erased')), 1,
  'GN4: existing, nonexistent and erased targets are byte-identical refusals (also for a manager of another venue)');
SELECT is(tap._fetch262('g_venue')::jsonb ->> 'error',
  '42501|insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required',
  'GN5: an UNKNOWN venue refuses like an unauthorized one (no venue-existence oracle)');
SELECT is(tap._fetch262('g_self')::jsonb ->> 'error',
  '42501|insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required',
  'GN6: an unauthorized SELF-grant hits the gate first (42501, not self_grant)');
SELECT is(tap._fetch262('g_x_erased')::jsonb ->> 'error',
  '42501|insufficient_privilege: venue_manager (non-manager labels) or org_owner/org_admin required',
  'GN7: a venue_manager of ANOTHER venue granting to the ERASED tombstone -> the same 42501');
SELECT is((SELECT count(*)::int FROM venue.staff_role s WHERE s.venue_id = '26200000-0000-4000-8000-0000000000a1'
              AND s.identity_id IN ('26200000-0000-4000-8000-000000000151','26200000-0000-4000-8000-000000000152','26200000-0000-4000-8000-000000000199'))
          + (SELECT count(*)::int FROM kernel.admin_audit a WHERE a.action = 'venue.staff_role.grant'
              AND a.actor_identity IN ('26200000-0000-4000-8000-000000000199','26200000-0000-4000-8000-000000000131')), 0,
  'GN8: nothing written — no staff_role row, no audit row from the refused callers');

SELECT tap.login('26200000-0000-4000-8000-000000000121');
SELECT is(tap._val262($q$SELECT (venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000151','venue_scanner','g-262-7') ->> 'status')$q$),
  'ok', 'GL1: the org owner grants venue_scanner to an ordinary identity -> ok');
SELECT is(tap._val262($q$SELECT (venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000151','venue_scanner','g-262-8') ->> 'status')$q$),
  'noop_replay', 'GL2: a re-grant is noop_replay (PK idempotency, unchanged)');
SELECT tap._store262('gl_none',   tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-00000000dead','venue_scanner','g-262-9')::text$q$));
SELECT tap._store262('gl_erased', tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000152','venue_scanner','g-262-10')::text$q$));
SELECT is(tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000121','venue_finance','g-262-11')::text$q$)::jsonb ->> 'error',
  'P0001|precondition_failed: self_grant', 'GL7: an AUTHORIZED self-grant still answers self_grant (unchanged)');
SELECT tap.logout();
SELECT is(tap._fetch262('gl_none')::jsonb ->> 'error', 'P0002|not_found: identity 26200000-0000-4000-8000-00000000dead',
  'GL4: an authorized grant to a NONEXISTENT identity -> P0002 not_found: identity <id>');
SELECT is(tap._fetch262('gl_erased')::jsonb ->> 'error', 'P0002|not_found: identity 26200000-0000-4000-8000-000000000152',
  'GL5: …to an ERASED tombstone -> the SAME refusal (P0002 not_found: identity <id>), never identity_erased');
SELECT is(replace(tap._fetch262('gl_erased'), '26200000-0000-4000-8000-000000000152', '<id>'),
          replace(tap._fetch262('gl_none'),   '26200000-0000-4000-8000-00000000dead', '<id>'),
  'GL6: the two refusals are identical once the id is masked (one code, one text shape: deletion is not revealed)');
SELECT tap.login('26200000-0000-4000-8000-000000000111');
SELECT is(tap._val262($q$SELECT (venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000151','venue_finance','g-262-12') ->> 'status')$q$),
  'ok', 'GL3: the room''s venue_manager grants venue_finance -> ok (non-manager labels, unchanged)');
SELECT is(tap._val262($q$SELECT venue.grant_staff_role('26200000-0000-4000-8000-0000000000a1','26200000-0000-4000-8000-000000000151','venue_manager','g-262-13')::text$q$)::jsonb ->> 'error',
  'P0001|precondition_failed: tier_guard — venue_manager is granted from the org plane',
  'GL8: a venue_manager granting venue_manager still answers tier_guard (AUTHZ-M7, unchanged)');
SELECT tap.logout();
SELECT is((SELECT string_agg(s.role || ':' || coalesce(s.granted_by::text, '-'), ',' ORDER BY s.role)
             FROM venue.staff_role s WHERE s.venue_id = '26200000-0000-4000-8000-0000000000a1'
              AND s.identity_id IN ('26200000-0000-4000-8000-000000000151','26200000-0000-4000-8000-000000000152'))
          || '|' || (SELECT count(*) FROM kernel.admin_audit a WHERE a.action = 'venue.staff_role.grant'
                      AND a.subject_id = '26200000-0000-4000-8000-000000000151'),
  'venue_finance:26200000-0000-4000-8000-000000000111,venue_scanner:26200000-0000-4000-8000-000000000121|2',
  'GL9: exactly the two granted rows (scanner by the owner, finance by the manager), two audit rows; the tombstone holds nothing');

SELECT * FROM finish();
ROLLBACK;
