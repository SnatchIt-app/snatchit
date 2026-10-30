-- ============================================================================
-- 260_door_schedule_conformance.sql — migration 20261030030000 (registry 190).
--   catalog.set_session_door_schedule brought to RPC §20.6.5:
--   (A) authority = org_owner/org_admin | venue_manager | platform_admin, checked BEFORE the
--       boundary test so an outsider learns nothing about the boundary;
--   (B) boundary_engaged once door_open_at is set (exact contract code), nothing written;
--   (C) custody guards: free while the session has no atom; once atoms exist, earlier freely,
--       later only INSIDE config('door.schedule_move_grace_interval') (absent ⇒ no later move,
--       PFA-9 fail-to-safe; `>=` grace is refused, matching 079/093), reason code mandatory;
--   (D) kernel.admin_audit 'session.door_schedule.change' with before/after + reason_code, and
--       the result carries doors_at AND the recomputed effective_freeze_at.
--   Plus: the signature/grant/definer posture is unchanged, and T-RPC-DOOR-23 as the only
--   coherent reading of the two specs (no ASSIGNMENT to door_open_at; reading it is guard B —
--   the ambiguity is flagged in the migration header for A).
--   NEGATIVE CONTROL: on a chain WITHOUT 190 the A/C/D groups fail (086 allows a later move with
--   no reason and no audit row, omits platform_admin, leaks the boundary state to an outsider and
--   returns a two-key result); recorded in planning/2026-10-26-launch/B/evidence.
-- ============================================================================
BEGIN;
SELECT plan(35);
SELECT tap.seed_core();

CREATE TABLE tap.memo_260 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store260(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_260 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch260(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_260 WHERE k=$1 $m$;
-- kernel.admin_audit is not readable by the test personas (no grant); these definer readers are
-- the audit equivalents of the memo helpers above.
CREATE FUNCTION tap._doors260(sess text) RETURNS timestamptz
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT doors_at FROM catalog.event_session WHERE session_id=$1::uuid $m$;
CREATE FUNCTION tap._audit260n(sess text) RETURNS int
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT count(*)::int FROM kernel.admin_audit
  WHERE action='session.door_schedule.change' AND subject_kind='event_session' AND subject_id=$1::uuid $m$;
-- NOTE: kernel.admin_audit.occurred_at defaults to now(), which is TRANSACTION-stable, so inside
-- one pgTAP transaction every row this suite writes shares a timestamp and "the newest row" is not
-- orderable by time. Rows are therefore selected by their reason code, which is unique per call.
CREATE FUNCTION tap._audit260by(sess text, reason text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT jsonb_build_object('n',count(*),
         'actor',min(a.actor_identity::text),
         'before_doors',min(a.before->>'doors_at'),'after_doors',min(a.after->>'doors_at'))
    FROM kernel.admin_audit a
   WHERE a.action='session.door_schedule.change' AND a.subject_kind='event_session'
     AND a.subject_id=$1::uuid AND a.reason_code=$2 $m$;

-- ── FIXTURE — org(approved) + venue(approved); seller = venue_manager; three sessions:
-- sN (no atoms), sA (atoms issued), sB (boundary engaged via an opened manifest).
SELECT tap.login(tap.seller());
SELECT tap._store260('org', (kernel.create_organization('DS Co','DS Co','ck260-o') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch260('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store260('venue', (catalog.create_venue(tap._fetch260('org')::uuid,'DS Hall','wynwood',NULL,'ck260-v') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch260('venue')::uuid,'approved','miami_gate','ck260-a');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch260('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;
SELECT tap.login(tap.seller());
SELECT tap._store260('eN', (catalog.create_event(tap._fetch260('venue')::uuid,'DS none',
  jsonb_build_object('starts_at',(now()+interval '20 days')::text,'ends_at',(now()+interval '20 days 5 hours')::text),'ck260-eN') ->> 'event_id'));
SELECT tap._store260('sN', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch260('eN')::uuid));
SELECT tap._store260('eA', (catalog.create_event(tap._fetch260('venue')::uuid,'DS atoms',
  jsonb_build_object('starts_at',(now()+interval '21 days')::text,'ends_at',(now()+interval '21 days 5 hours')::text),'ck260-eA') ->> 'event_id'));
SELECT tap._store260('sA', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch260('eA')::uuid));
SELECT tap._store260('ttA', (venue.create_ticket_type(tap._fetch260('eA')::uuid,'admission','GA',5000,'public','ck260-ttA') ->> 'ticket_type_id'));
SELECT tap._store260('bA', (venue.create_inventory_batch(tap._fetch260('ttA')::uuid, tap._fetch260('sA')::uuid, 'comp', 50, 0, 'ck260-bA') ->> 'batch_id'));
SELECT tap._store260('eB', (catalog.create_event(tap._fetch260('venue')::uuid,'DS boundary',
  jsonb_build_object('starts_at',(now()+interval '22 days')::text,'ends_at',(now()+interval '22 days 5 hours')::text),'ck260-eB') ->> 'event_id'));
SELECT tap._store260('sB', (SELECT session_id::text FROM catalog.event_session WHERE event_id=tap._fetch260('eB')::uuid));
SELECT tap.logout();
WITH k AS (INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch260('eA')::uuid, 'PUBKEY-260A', 'kms-260A', 'active', now(), 'ES256') RETURNING key_id)
SELECT tap._store260('kA', (SELECT key_id::text FROM k));
SELECT tap._store260('mA', (kernel.issue_ticket_atoms(jsonb_build_object(
  'session_id',tap._fetch260('sA')::uuid,'org_id',tap._fetch260('org')::uuid,'ticket_type_id',tap._fetch260('ttA')::uuid,
  'batch_id',tap._fetch260('bA')::uuid,'owner_id',tap.buyer(),'quantity',2,'cause','comp',
  'cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch260('kA')::uuid),'ck260-mA') -> 'atom_ids')::text);
-- sB: open a manifest as the venue manager; the first open engages the boundary (engage_door_freeze)
SELECT tap.login(tap.seller());
SELECT venue.open_door_manifest(tap._fetch260('sB')::uuid, 'doors_open', 'ck260-mfB');
SELECT tap.logout();
SELECT isnt((SELECT door_open_at FROM catalog.event_session WHERE session_id=tap._fetch260('sB')::uuid), NULL,
  'FX1: session sB has its boundary engaged (door_open_at set by engage_door_freeze)');
SELECT is((SELECT count(*)::int FROM kernel.tickets WHERE event_session_id=tap._fetch260('sA')::uuid), 2,
  'FX2: session sA has atoms; sN has none');

-- ── A — AUTHORITY ───────────────────────────────────────────────────────────
SELECT tap.login(tap.seller());    -- venue_manager
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sN')::uuid, (now()+interval '20 days')::timestamptz, NULL, 'ck260-a1') ->> 'status'), 'ok',
  'A1: venue_manager may set the schedule (no atoms, no reason needed)');
SELECT tap.logout();
SELECT tap.login(tap.admin_user());  -- platform_admin: ADDED by 190 (§20.6.5 allow-list)
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sN')::uuid, (now()+interval '20 days 1 hour')::timestamptz, 'ops', 'ck260-a2') ->> 'status'), 'ok',
  'A2: platform_admin may set the schedule (086 refused it — the allow-list 190 restores)');
SELECT tap.logout();
SELECT tap.login(tap.other_user());  -- no role anywhere
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,'x','ck260-a3')$$, tap._fetch260('sN'), (now()+interval '20 days')::timestamptz),
  '%insufficient_privilege%', 'A3: an unprivileged caller is refused 42501');
-- the no-oracle pin: on a BOUNDARY-ENGAGED session the outsider still gets 42501, never boundary_engaged
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,'x','ck260-a4')$$, tap._fetch260('sB'), (now()+interval '22 days')::timestamptz),
  '%insufficient_privilege%', 'A4: authority is checked BEFORE the boundary — an outsider cannot learn the boundary state (086 leaked it)');
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,'x','ck260-a5')$$, gen_random_uuid()::text, (now()+interval '20 days')::timestamptz),
  '%not_found%', 'A5: an unknown session is not_found (contract error set)');
SELECT tap.logout();

-- ── B — BOUNDARY ────────────────────────────────────────────────────────────
SELECT tap.login(tap.seller());
SELECT tap._store260('doorsB', (SELECT coalesce(doors_at::text,'(null)') FROM catalog.event_session WHERE session_id=tap._fetch260('sB')::uuid));
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,'late','ck260-b1')$$, tap._fetch260('sB'), (now()+interval '22 days 2 hours')::timestamptz),
  '%boundary_engaged%', 'B1: an authorized caller is refused boundary_engaged once door_open_at is set (exact contract code)');
SELECT is((SELECT coalesce(doors_at::text,'(null)') FROM catalog.event_session WHERE session_id=tap._fetch260('sB')::uuid), tap._fetch260('doorsB'),
  'B2: the refused call wrote nothing');
SELECT is(tap._audit260n(tap._fetch260('sB')), 0, 'B3: and no audit row for a refused change');

-- ── C — CUSTODY GUARDS (atoms exist) ────────────────────────────────────────
-- baseline: set sA's doors_at while it is still free of a later-move constraint (earlier move)
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sA')::uuid, (now()+interval '20 days 12 hours')::timestamptz, 'initial', 'ck260-c0') ->> 'status'), 'ok',
  'C0: an EARLIER move with atoms succeeds (earlier is always free) when a reason is given');
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,NULL,'ck260-c1')$$, tap._fetch260('sA'), (now()+interval '20 days 6 hours')::timestamptz),
  '%reason_required%', 'C1: with atoms, a move WITHOUT a reason code is refused (mandatory reason)');
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,'   ','ck260-c2')$$, tap._fetch260('sA'), (now()+interval '20 days 6 hours')::timestamptz),
  '%reason_required%', 'C2: a blank reason code is refused too');
-- grace key UNSEEDED -> no later move at all (PFA-9 fail-to-safe). The config and session reads
-- below run LOGGED OUT (the harness role): the personas hold no grant on catalog.platform_config
-- or catalog.event_session, and this suite is about the RPC's behaviour, not about those grants.
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM catalog.platform_config WHERE key='door.schedule_move_grace_interval'), 0,
  'C3: door.schedule_move_grace_interval is NOT seeded (PFA-9 CLASS A)');
SELECT tap.login(tap.seller());
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,%L,'push','ck260-c4')$$, tap._fetch260('sA'), (now()+interval '20 days 13 hours')::timestamptz),
  '%move_exceeds_grace%', 'C4: with atoms and NO grace configured, a LATER move is refused (fail-to-safe)');
SELECT tap.logout();
SELECT is(tap._doors260(tap._fetch260('sA')), (now()+interval '20 days 12 hours')::timestamptz,
  'C5: the refused later move left doors_at at its previous value');
-- now seed a 2-hour grace and re-test the boundary conditions
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('door.schedule_move_grace_interval', 1, '"2 hours"'::jsonb, 'restricted');
SELECT tap.login(tap.seller());
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sA')::uuid, (tap._doors260(tap._fetch260('sA')) + interval '1 hour'), 'push 1h', 'ck260-c6') ->> 'status'), 'ok',
  'C6: a later move INSIDE the grace (1 h < 2 h) succeeds with a reason');
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,(tap._doors260(%L) + interval '2 hours'),'push 2h','ck260-c7')$$, tap._fetch260('sA'), tap._fetch260('sA')),
  '%move_exceeds_grace%', 'C7: a later move of EXACTLY the grace is refused (>= semantics, identical to 079/093)');
SELECT throws_like(format($$SELECT catalog.set_session_door_schedule(%L,(tap._doors260(%L) + interval '3 hours'),'push 3h','ck260-c8')$$, tap._fetch260('sA'), tap._fetch260('sA')),
  '%move_exceeds_grace%', 'C8: a later move beyond the grace is refused');
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sA')::uuid, (tap._doors260(tap._fetch260('sA')) - interval '5 hours'), 'pull in', 'ck260-c9') ->> 'status'), 'ok',
  'C9: an earlier move is never grace-bound');
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sA')::uuid, NULL, 'clear', 'ck260-c10') ->> 'status'), 'ok',
  'C10: clearing doors_at (NULL) is allowed — the backstop moves EARLIER, to starts_at');
-- a session with NO atoms is never grace-bound or reason-bound
SELECT is((catalog.set_session_door_schedule(tap._fetch260('sN')::uuid, (now()+interval '25 days')::timestamptz, NULL, 'ck260-c11') ->> 'status'), 'ok',
  'C11: with no atoms a far-LATER move needs neither grace nor reason (free while nothing is issued)');

-- ── D — AUDIT + RESULT ──────────────────────────────────────────────────────
SELECT tap._store260('audit_before', tap._audit260n(tap._fetch260('sA'))::text);
SELECT tap._store260('prev_doors', tap._doors260(tap._fetch260('sA'))::text);   -- NULL after C10's clear
SELECT tap._store260('r', (catalog.set_session_door_schedule(tap._fetch260('sA')::uuid, (now()+interval '21 days')::timestamptz, 'final notice', 'ck260-d1'))::text);
SELECT is(tap._fetch260('r')::jsonb ->> 'status', 'ok', 'D1: the call succeeds');
SELECT is((tap._fetch260('r')::jsonb ->> 'doors_at')::timestamptz, tap._doors260(tap._fetch260('sA')),
  'D2: the result carries the NEW doors_at (086 returned only status + session_id)');
SELECT is((tap._fetch260('r')::jsonb ->> 'effective_freeze_at')::timestamptz, catalog.effective_freeze_at(tap._fetch260('sA')::uuid),
  'D3: the result carries the RECOMPUTED effective_freeze_at — the operator sees the consequence in the same round trip');
SELECT is(tap._audit260n(tap._fetch260('sA')) - tap._fetch260('audit_before')::int, 1,
  'D4: the D1 change added EXACTLY one audit row for sA (delta, not a magic total)');
SELECT ok((tap._audit260by(tap._fetch260('sA'), 'final notice') ->> 'n')::int = 1
       AND (tap._audit260by(tap._fetch260('sA'), 'final notice') ->> 'before_doors') IS NOT DISTINCT FROM tap._fetch260('prev_doors')
       AND (tap._audit260by(tap._fetch260('sA'), 'final notice') ->> 'after_doors')::timestamptz = tap._doors260(tap._fetch260('sA'))
       AND (tap._audit260by(tap._fetch260('sA'), 'final notice') ->> 'actor')::uuid = tap.seller(),
  'D5: the D1 row is unique for its reason code and records before = the previous doors_at (NULL here: C10 cleared it, so a clear-then-set transition is recorded faithfully), after = the new value, and the acting identity');
SELECT is(tap._audit260n(tap._fetch260('sA')), 5,
  'D4b: sA holds exactly FIVE rows — one per successful change (C0, C6, C9, C10, D1) and none for the five refusals (C1, C2, C4, C7, C8)');
SELECT ok((tap._audit260by(tap._fetch260('sN'), 'schedule_set') ->> 'n')::int >= 1,
  'D6: a no-atom change with no reason is still audited, under the default reason code');
SELECT tap.logout();

-- ── E — POSTURE + STRUCTURAL ────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='catalog' AND p.proname='set_session_door_schedule'), 1,
  'E1: exactly one overload (signature unchanged by 190)');
SELECT ok((SELECT p.prosecdef AND p.proconfig::text LIKE '%search_path=%'
             FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='catalog' AND p.proname='set_session_door_schedule'),
  'E2: still SECURITY DEFINER with a pinned search_path (066 invariant)');
SELECT ok(has_function_privilege('authenticated', 'catalog.set_session_door_schedule(uuid,timestamptz,text,text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'catalog.set_session_door_schedule(uuid,timestamptz,text,text)', 'EXECUTE'),
  'E3: grants unchanged — authenticated EXECUTE, never anon (142 F3 closure)');
-- T-RPC-DOOR-23, as the only coherent reading of §20.6.5 vs RLS §2208 / ROLE_MODEL §1494:
-- the body may READ door_open_at (that IS guard B) but must never ASSIGN it; engage_door_freeze
-- is the sole writer (O-5), and the 086 trigger enforces that independently of this function.
SELECT ok(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure) !~* 'door_open_at[[:space:]]*=[[:space:]]*',
  'E4: T-RPC-DOOR-23 — the body contains NO assignment to door_open_at (it only reads it for the boundary guard)');
-- E5a/E5b: one structural pin per concern, so each survives a degenerate mutant. (Removing BLOCK D
-- wholesale cannot be tested behaviourally: that block carries the RETURN, so the function stops
-- returning and every assertion errors instead of failing — recorded in the mutant log.)
SELECT ok(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure) LIKE '%session.door_schedule.change%',
  'E5a: the audit write is present in the body (structural, so a later body-only re-create cannot drop it silently)');
SELECT ok(pg_get_functiondef('catalog.set_session_door_schedule(uuid,timestamptz,text,text)'::regprocedure) LIKE '%schedule_move_grace_interval%',
  'E5b: the grace read is present in the body (same reason)');

SELECT * FROM finish();
ROLLBACK;
