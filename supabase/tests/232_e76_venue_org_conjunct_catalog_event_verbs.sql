-- ============================================================================
-- 232_e76_venue_org_conjunct_catalog_event_verbs.sql — migration 20261027020000
-- (registry 165).
--
-- Registry 165 / pgTAP 232 — assigned by Claude A 2026-10-26. A reviews before
-- this leaves draft. DARK: applied nowhere. 165 replaces four catalog bodies
-- (update_event, create_event_session, update_event_session, publish_event) with
-- their predecessors plus ONE edit: the venue-role arm requires the venue's
-- CURRENT operator to be the event's org (088 cancel_event's E-76 conjunct; B's
-- 187 shape, D/s7-e76-catalog/B-CONJUNCT-SHAPE-187.md).
--
--   Section A  shape: the four bodies are 165's (md5(prosrc)); still postgres-
--              owned SECURITY DEFINER plpgsql, search_path = '', jsonb; ACL still
--              exactly owner + authenticated (165 granted nothing); one function
--              per name; create_event / cancel_event / update_venue untouched; the
--              conjunct is in each of the four; catalog.event.venue_id is NOT NULL
--              with an FK to catalog.venue (B's (c): a venue-less event cannot
--              exist, and the exists() is false for a missing room row).
--   Section K  control — the conjunct does not touch the normal path: Room V1's
--              bound manager (Org A's room, Org A's events) succeeds on all four.
--   Section F  THE FLIP — Room V2 created under Org A, its events stamped Org A,
--              then moved to Org B by a DIRECT `UPDATE catalog.venue` as postgres
--              (update_venue's org_id path is frozen — Decision C,
--              'operatorship_transfer_frozen' — so this state exists only from
--              history; B's 257 models it the same way). The former-operator
--              manager is REFUSED on Org A's event by all four (each body's own
--              42501 message), nothing is written, and each refusal is byte-
--              identical (SQLSTATE + SQLERRM) to a role-less fan's (B's (b)).
--   Section M  the marketing-only arm is covered too: the former-operator
--              venue_marketing is refused a description / session_label patch on
--              Org A's event; Room V1's venue_marketing still makes both.
--   Section W  164's wrapper inherits the body's refusal (venue_cmd.update_event).
--   Section B  RESIDUAL, unchanged by design: the same former-operator manager
--              on the NEW operator's (Org B's) event at V2 is accepted on all four
--              — his V2 role row outlived the move and venue.org_id = event.org_id
--              there. Revoking such rows belongs to the operator-transfer path,
--              which is frozen; B's door-plane helper answers the same way.
--   Section O  the ORG arm is unchanged (088 / 162 precedent): Org A's owner still
--              runs all four on its own event at the room Org B now operates;
--              Org B's owner is still refused on Org A's event.
--   Section C  verbs 165 does not change: cancel_event still refuses the former-
--              operator manager (088); create_event at V2 by him is accepted and
--              stamps the room's CURRENT org (B) — the conjunct holds by
--              construction; update_venue of V2 by him is accepted (164's S8
--              baseline: no event to bind).
--   Section U  STATUS QUO, not changed by 165: these bodies answer an unknown
--              event / session 'not_found' (P0002) BEFORE authority (078/093/102),
--              so they are not oracle-free the way B's door helper is. Pinned and
--              flagged for A/B.
--
-- Fixture: 231 style (synthetic rows as postgres, fixed ids, tag 23200000-…,
-- read back as each caller through tap.login, rolled back). Org A: owner 101.
-- Room V1 (Org A): manager 111, marketing 115. Room V2 (re-operated A -> B):
-- manager 121 and marketing 122 = the former-operator staff. Org B owner 201.
-- Fan 199. Events: e01/e02 at V1 (Org A; K, M controls); e06 at V2 (Org A's;
-- F, M, W, C targets); e09 at V2 (Org B's, inserted after the move; B); e16 at V2
-- (Org A's; O). Session times are fixed instants in 2027 (no now() drift).
-- Every positive-path call goes through tap._val232 (the returned text, or 'ERROR
-- <SQLSTATE>|<SQLERRM>'), so a wrongful refusal reads `not ok` instead of aborting.
--
-- Expected on the 167 tree WITHOUT 165 (RED, predicted before the first run):
-- A1-A4 fail (the predecessors' md5s), A5-A9 pass, A10 fails (no body carries the
-- conjunct); K0-K4 pass; F0 passes, F1-F4 fail (the calls succeed), F5 fails (they
-- wrote), F6-F9 fail (121's calls succeed or, for publish_event, fail
-- illegal_transition after F4 — never the fan's 42501); M0 passes, M1-M2 fail,
-- M3-M5 pass; W1 fails; B0-B4, O0-O9, C0-C4, U0-U4 pass.
-- Predicted RED run: all 57 emitted (nothing aborts) = 40 ok + 17 not ok
-- (A1-A4, A10, F1-F4, W1, F5, F6-F9, M1, M2).
-- ============================================================================
BEGIN;
SELECT plan(57);

CREATE TABLE tap.memo_232 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store232(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_232 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch232(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_232 WHERE k = $1 $m$;
-- SQLSTATE|SQLERRM of a statement run AS THE CALLER (invoker), or 'no error'
CREATE FUNCTION tap._err232(q text) RETURNS text
LANGUAGE plpgsql AS
$m$ BEGIN EXECUTE q; RETURN 'no error'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || '|' || SQLERRM; END $m$;
-- the text a statement returns AS THE CALLER, or 'ERROR <SQLSTATE>|<SQLERRM>' — so a positive-path assertion
-- that is wrongly refused reads `not ok` instead of aborting the file (NC3 found the abort, 2026-10-27)
CREATE FUNCTION tap._val232(q text) RETURNS text
LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN 'ERROR ' || SQLSTATE || '|' || SQLERRM; END $m$;
GRANT EXECUTE ON FUNCTION tap._store232(text, text), tap._fetch232(text), tap._err232(text), tap._val232(text) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('23200000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.232@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23200000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.232@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23200000-0000-4000-8000-000000000115', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v1.232@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23200000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.232@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23200000-0000-4000-8000-000000000122', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v2.former.232@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23200000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.232@test.local',            '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23200000-0000-4000-8000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.b.232@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('23200000-0000-4000-8000-00000000000a', 'Org A 232', 'Org A 232', 'active'),
  ('23200000-0000-4000-8000-00000000000b', 'Org B 232', 'Org B 232', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('23200000-0000-4000-8000-00000000000a', '23200000-0000-4000-8000-000000000101', 'org_owner'),
  ('23200000-0000-4000-8000-00000000000b', '23200000-0000-4000-8000-000000000201', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('23200000-0000-4000-8000-0000000000a1', '23200000-0000-4000-8000-00000000000a', 'Room V1 232', 'wynwood',  'approved'),
  ('23200000-0000-4000-8000-0000000000a2', '23200000-0000-4000-8000-00000000000a', 'Room V2 232', 'brickell', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('23200000-0000-4000-8000-0000000000a1', '23200000-0000-4000-8000-000000000111', 'venue_manager'),
  ('23200000-0000-4000-8000-0000000000a1', '23200000-0000-4000-8000-000000000115', 'venue_marketing'),
  ('23200000-0000-4000-8000-0000000000a2', '23200000-0000-4000-8000-000000000121', 'venue_manager'),
  ('23200000-0000-4000-8000-0000000000a2', '23200000-0000-4000-8000-000000000122', 'venue_marketing');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23200000-0000-4000-8000-00000000e001', '23200000-0000-4000-8000-0000000000a1', '23200000-0000-4000-8000-00000000000a', 'e01 V1 232',            'draft'),
  ('23200000-0000-4000-8000-00000000e002', '23200000-0000-4000-8000-0000000000a1', '23200000-0000-4000-8000-00000000000a', 'e02 V1 publish 232',    'draft'),
  ('23200000-0000-4000-8000-00000000e006', '23200000-0000-4000-8000-0000000000a2', '23200000-0000-4000-8000-00000000000a', 'e06 V2 (A event) 232',  'draft'),
  ('23200000-0000-4000-8000-00000000e016', '23200000-0000-4000-8000-0000000000a2', '23200000-0000-4000-8000-00000000000a', 'e16 V2 (A event) 232',  'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, status, door_open_at) VALUES
  ('23200000-0000-4000-8000-00000000f001', '23200000-0000-4000-8000-00000000e001', NULL, '2027-01-11 01:00:00+00', 'scheduled', NULL),
  ('23200000-0000-4000-8000-00000000f002', '23200000-0000-4000-8000-00000000e002', NULL, '2027-01-12 01:00:00+00', 'scheduled', NULL),
  ('23200000-0000-4000-8000-00000000f006', '23200000-0000-4000-8000-00000000e006', NULL, '2027-01-16 01:00:00+00', 'scheduled', NULL),
  ('23200000-0000-4000-8000-00000000f016', '23200000-0000-4000-8000-00000000e016', NULL, '2027-01-26 01:00:00+00', 'scheduled', NULL);
-- THE RE-OPERATION: Room V2 moves from Org A to Org B (direct UPDATE — the RPC
-- path is frozen, Decision C). e06 / e16 keep org_id = A.
UPDATE catalog.venue SET org_id = '23200000-0000-4000-8000-00000000000b'
 WHERE venue_id = '23200000-0000-4000-8000-0000000000a2';
-- e09: the NEW operator's (Org B's) event at V2, created after the move.
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23200000-0000-4000-8000-00000000e009', '23200000-0000-4000-8000-0000000000a2', '23200000-0000-4000-8000-00000000000b', 'e09 V2 (B event) 232', 'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, status, door_open_at) VALUES
  ('23200000-0000-4000-8000-00000000f009', '23200000-0000-4000-8000-00000000e009', NULL, '2027-01-19 01:00:00+00', 'scheduled', NULL);

-- ── Section A — shape ───────────────────────────────────────────────────────
SELECT is((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('catalog.update_event(uuid, jsonb, text)')),
  '1bf2a04bf1ffccfdbed04d8b067dd2df', 'A1: catalog.update_event carries 165''s body (078 + the E-76 conjunct)');
SELECT is((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('catalog.create_event_session(uuid, jsonb, text)')),
  'ee243b12a8b51c7692a8f6ed22506a34', 'A2: catalog.create_event_session carries 165''s body (078 + the E-76 conjunct)');
SELECT is((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('catalog.update_event_session(uuid, jsonb, text)')),
  '9e834d57e7810f81d1f9ed11c79dcd24', 'A3: catalog.update_event_session carries 165''s body (093 + the E-76 conjunct)');
SELECT is((SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('catalog.publish_event(uuid, text, text)')),
  'b31abddf9aad2cb7b119d517424bb494', 'A4: catalog.publish_event carries 165''s body (102 + the E-76 conjunct)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'catalog' AND p.prosecdef AND l.lanname = 'plpgsql'
              AND 'search_path=""' = ANY (coalesce(p.proconfig, '{}'))
              AND p.proowner = 'postgres'::regrole AND pg_get_function_result(p.oid) = 'jsonb'
              AND p.proname IN ('update_event','create_event_session','update_event_session','publish_event')), 4,
  'A5: each of the four is still a postgres-owned SECURITY DEFINER plpgsql body with search_path = '''' returning jsonb');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'catalog'
        AND p.proname IN ('update_event','create_event_session','update_event_session','publish_event') $$,
  $$ VALUES ('update_event:postgres:EXECUTE'), ('update_event:authenticated:EXECUTE'),
            ('create_event_session:postgres:EXECUTE'), ('create_event_session:authenticated:EXECUTE'),
            ('update_event_session:postgres:EXECUTE'), ('update_event_session:authenticated:EXECUTE'),
            ('publish_event:postgres:EXECUTE'), ('publish_event:authenticated:EXECUTE') $$,
  'A6: the four ACLs are UNCHANGED by 165 — exactly owner (postgres) + authenticated; anon / service_role / PUBLIC hold none');
SELECT is((SELECT string_agg(p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')', ', ' ORDER BY p.proname)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND p.proname IN ('update_event','create_event_session','update_event_session','publish_event')),
  'create_event_session(uuid, jsonb, text), publish_event(uuid, text, text), update_event(uuid, jsonb, text), update_event_session(uuid, jsonb, text)',
  'A7: one function per name — same signatures, no overload added');
SELECT is((SELECT string_agg(p.proname || '=' || md5(p.prosrc), ' ' ORDER BY p.proname)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND p.proname IN ('create_event','cancel_event','update_venue')),
  'cancel_event=d1ce1b824338a3293e9fa882ab7f068a create_event=e48b7093e3a92f3b396450565d9f3261 update_venue=d286ada0e16854918622627994873d3b',
  'A8: create_event (078), cancel_event (088) and update_venue (093) are untouched by 165');
SELECT is((SELECT a.attnotnull::text || '|' || (SELECT count(*) FROM pg_constraint c
                                                 WHERE c.conrelid = 'catalog.event'::regclass AND c.contype = 'f'
                                                   AND c.confrelid = 'catalog.venue'::regclass AND c.conkey = ARRAY[a.attnum])::text
             FROM pg_attribute a WHERE a.attrelid = 'catalog.event'::regclass AND a.attname = 'venue_id'),
  'true|1', 'A9: catalog.event.venue_id is NOT NULL with an FK to catalog.venue — a venue-less event cannot exist (B''s (c) holds by construction)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog'
              AND p.proname IN ('update_event','create_event_session','update_event_session','publish_event')
              AND p.prosrc ~ 'and exists \(select 1 from catalog\.venue v\s+where v\.venue_id = v_venue(_id)? and v\.org_id = v_org_id\)'), 4,
  'A10: each of the four carries the conjunct venue.org_id = event.org_id on its venue-role arm');

-- ── Section K — control: Room V1's bound manager (Org A's room, Org A's events) ─
SELECT tap.login('23200000-0000-4000-8000-000000000111');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000111',
  'K0: V1 manager block runs as authenticated with its own auth.uid()');
SELECT is(tap._val232($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e001', '{"title":"e01 retitled by V1 manager"}', 'ck232-k-1') ->> 'status'$$), 'ok',
  'K1: control — the current operator''s manager still runs update_event');
SELECT is(tap._val232($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e001', '{"starts_at":"2027-02-11T01:00:00Z"}', 'ck232-k-2') ->> 'status'$$), 'ok',
  'K2: control — …create_event_session');
SELECT is(tap._val232($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f001', '{"starts_at":"2027-01-11T02:00:00Z"}', 'ck232-k-3') ->> 'status'$$), 'ok',
  'K3: control — …update_event_session');
SELECT is(tap._val232($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e002', 'announced', 'ck232-k-4') ->> 'event_status'$$), 'announced',
  'K4: control — …publish_event');
SELECT tap.logout();

-- ── Section F — THE FLIP: the former-operator manager on Org A's event at V2 ─
SELECT tap.login('23200000-0000-4000-8000-000000000121');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000121',
  'F0: former-operator manager block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e006', '{"title":"e06 retitled by former manager"}', 'ck232-f-1')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required',
  'F1: E-76 — the former-operator manager is REFUSED update_event on Org A''s event at the room Org B now operates');
SELECT throws_ok($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e006', '{"starts_at":"2027-02-16T01:00:00Z"}', 'ck232-f-2')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'F2: E-76 — …REFUSED create_event_session');
SELECT throws_ok($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f006', '{"starts_at":"2027-01-16T02:00:00Z"}', 'ck232-f-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'F3: E-76 — …REFUSED update_event_session');
SELECT throws_ok($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e006', 'announced', 'ck232-f-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'F4: E-76 — …REFUSED publish_event');
SELECT tap._store232('f6_121', tap._err232($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e006', '{"title":"x"}', 'ck232-f-6')$$));
SELECT tap._store232('f7_121', tap._err232($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e006', '{"starts_at":"2027-02-17T01:00:00Z"}', 'ck232-f-7')$$));
SELECT tap._store232('f8_121', tap._err232($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f006', '{"starts_at":"2027-01-16T03:00:00Z"}', 'ck232-f-8')$$));
SELECT tap._store232('f9_121', tap._err232($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e006', 'announced', 'ck232-f-9')$$));
-- Section W — 164's wrapper inherits the body's refusal
SELECT throws_ok($$SELECT venue_cmd.update_event('23200000-0000-4000-8000-00000000e006', '{"title":"x"}', 'ck232-w-1')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required',
  'W1: through 164''s wrapper venue_cmd.update_event the former-operator manager gets the same refusal');
SELECT tap.logout();
SELECT tap.login('23200000-0000-4000-8000-000000000199');
SELECT tap._store232('f6_fan', tap._err232($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e006', '{"title":"x"}', 'ck232-f-6f')$$));
SELECT tap._store232('f7_fan', tap._err232($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e006', '{"starts_at":"2027-02-17T01:00:00Z"}', 'ck232-f-7f')$$));
SELECT tap._store232('f8_fan', tap._err232($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f006', '{"starts_at":"2027-01-16T03:00:00Z"}', 'ck232-f-8f')$$));
SELECT tap._store232('f9_fan', tap._err232($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e006', 'announced', 'ck232-f-9f')$$));
SELECT tap.logout();
SELECT is((SELECT e.title || '|' || e.status || '|' || (SELECT count(*) FROM catalog.event_session s WHERE s.event_id = e.event_id)::text || '|' ||
                  (SELECT s.starts_at = '2027-01-16 01:00:00+00'::timestamptz FROM catalog.event_session s WHERE s.session_id = '23200000-0000-4000-8000-00000000f006')::text
             FROM catalog.event e WHERE e.event_id = '23200000-0000-4000-8000-00000000e006'),
  'e06 V2 (A event) 232|draft|1|true',
  'F5: nothing was written — e06 keeps its title and draft status, one session, and f06''s original starts_at');
SELECT is(tap._fetch232('f6_121'), tap._fetch232('f6_fan'),
  'F6: no oracle — the wrong-operator refusal of update_event is byte-identical (SQLSTATE + SQLERRM) to a role-less fan''s');
SELECT is(tap._fetch232('f7_121'), tap._fetch232('f7_fan'),
  'F7: …create_event_session');
SELECT is(tap._fetch232('f8_121'), tap._fetch232('f8_fan'),
  'F8: …update_event_session');
SELECT is(tap._fetch232('f9_121'), tap._fetch232('f9_fan'),
  'F9: …publish_event');

-- ── Section M — the marketing-only arm ──────────────────────────────────────
SELECT tap.login('23200000-0000-4000-8000-000000000122');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000122',
  'M0: former-operator venue_marketing block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e006', '{"description":"former marketing copy"}', 'ck232-m-1')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required',
  'M1: E-76 — the former-operator venue_marketing is REFUSED a marketing-only update_event (description) on Org A''s event');
SELECT throws_ok($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f006', '{"session_label":"former label"}', 'ck232-m-2')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'M2: E-76 — …REFUSED a marketing-only update_event_session (session_label)');
SELECT tap.logout();
SELECT tap.login('23200000-0000-4000-8000-000000000115');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000115',
  'M3: V1 venue_marketing block runs as authenticated with its own auth.uid()');
SELECT is(tap._val232($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e001', '{"description":"V1 marketing copy"}', 'ck232-m-4') ->> 'status'$$), 'ok',
  'M4: control — the current operator''s venue_marketing still makes a description patch');
SELECT is(tap._val232($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f001', '{"session_label":"V1 label"}', 'ck232-m-5') ->> 'status'$$), 'ok',
  'M5: control — …and a session_label patch');
SELECT tap.logout();

-- ── Section B — RESIDUAL (unchanged by design): the new operator's event at V2 ─
SELECT tap.login('23200000-0000-4000-8000-000000000121');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000121',
  'B0: former-operator manager block (again) runs as authenticated with its own auth.uid()');
SELECT is(tap._val232($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e009', '{"title":"e09 retitled"}', 'ck232-b-1') ->> 'status'$$), 'ok',
  'B1: RESIDUAL — on Org B''s event at V2 the same manager is accepted (venue.org_id = event.org_id; his role row outlived the move; revocation is the frozen transfer path''s)');
SELECT is(tap._val232($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e009', '{"starts_at":"2027-02-19T01:00:00Z"}', 'ck232-b-2') ->> 'status'$$), 'ok',
  'B2: RESIDUAL — …create_event_session');
SELECT is(tap._val232($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f009', '{"starts_at":"2027-01-19T02:00:00Z"}', 'ck232-b-3') ->> 'status'$$), 'ok',
  'B3: RESIDUAL — …update_event_session');
SELECT is(tap._val232($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e009', 'announced', 'ck232-b-4') ->> 'event_status'$$), 'announced',
  'B4: RESIDUAL — …publish_event');
SELECT tap.logout();

-- ── Section O — the ORG arm is unchanged ────────────────────────────────────
SELECT tap.login('23200000-0000-4000-8000-000000000101');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000101',
  'O0: Org A owner block runs as authenticated with its own auth.uid()');
SELECT is(tap._val232($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e016', '{"title":"e16 retitled by Org A"}', 'ck232-o-1') ->> 'status'$$), 'ok',
  'O1: org arm — Org A''s owner still runs update_event on its own event at the room Org B now operates');
SELECT is(tap._val232($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e016', '{"starts_at":"2027-02-26T01:00:00Z"}', 'ck232-o-2') ->> 'status'$$), 'ok',
  'O2: org arm — …create_event_session');
SELECT is(tap._val232($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f016', '{"starts_at":"2027-01-26T02:00:00Z"}', 'ck232-o-3') ->> 'status'$$), 'ok',
  'O3: org arm — …update_event_session');
SELECT is(tap._val232($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e016', 'announced', 'ck232-o-4') ->> 'event_status'$$), 'announced',
  'O4: org arm — …publish_event');
SELECT tap.logout();
SELECT tap.login('23200000-0000-4000-8000-000000000201');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000201',
  'O5: Org B owner block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000e016', '{"title":"x"}', 'ck232-o-6')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required',
  'O6: event-org arm — the new operator''s owner is still refused update_event on Org A''s event');
SELECT throws_ok($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000e016', '{"starts_at":"2027-02-27T01:00:00Z"}', 'ck232-o-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'O7: event-org arm — …create_event_session');
SELECT throws_ok($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000f016', '{"starts_at":"2027-01-26T03:00:00Z"}', 'ck232-o-8')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'O8: event-org arm — …update_event_session');
SELECT throws_ok($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000e016', 'on_sale', 'ck232-o-9')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'O9: event-org arm — …publish_event (the role check precedes the on_sale gates)');
SELECT tap.logout();

-- ── Section C — verbs 165 does not change ───────────────────────────────────
SELECT tap.login('23200000-0000-4000-8000-000000000121');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000121',
  'C0: former-operator manager block (third) runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT catalog.cancel_event('23200000-0000-4000-8000-00000000e006', 'weather', 'ck232-c-1')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only',
  'C1: cancel_event still refuses the former-operator manager (088''s conjunct, the shape 165 copies)');
SELECT tap._store232('c_ev', tap._val232($$SELECT catalog.create_event('23200000-0000-4000-8000-0000000000a2', 'Former manager event 232',
          '{"starts_at":"2027-03-02T01:00:00Z"}', 'ck232-c-2') ->> 'event_id'$$));
SELECT is(tap._val232($$SELECT catalog.update_venue('23200000-0000-4000-8000-0000000000a2', '{"name":"Room V2 renamed 232"}', 'ck232-c-3') ->> 'status'$$), 'ok',
  'C2: update_venue of V2 by the former-operator manager is accepted (164''s S8 baseline: no event to bind; not 165''s)');
SELECT tap.logout();
SELECT is((SELECT e.status || '|' || e.org_id::text FROM catalog.event e WHERE e.event_id::text = tap._fetch232('c_ev')),
  'draft|23200000-0000-4000-8000-00000000000b',
  'C3: create_event at V2 by him is accepted and stamps the room''s CURRENT operator (Org B) — the conjunct holds by construction');
SELECT is((SELECT count(*)::int FROM catalog.event e
            WHERE e.event_id::text = tap._fetch232('c_ev')
              AND EXISTS (SELECT 1 FROM catalog.venue v WHERE v.venue_id = e.venue_id AND v.org_id = e.org_id)), 1,
  'C4: …so venue.org_id = event.org_id on the event create_event made');

-- ── Section U — STATUS QUO (not changed by 165): not_found precedes authority ─
SELECT tap.login('23200000-0000-4000-8000-000000000199');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|23200000-0000-4000-8000-000000000199',
  'U0: fan block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT catalog.update_event('23200000-0000-4000-8000-00000000eeee', '{"title":"x"}', 'ck232-u-1')$$,
  'P0002', 'not_found: event 23200000-0000-4000-8000-00000000eeee',
  'U1: STATUS QUO — update_event answers an unknown event not_found before authority (078; flagged for A/B, not changed by 165)');
SELECT throws_ok($$SELECT catalog.create_event_session('23200000-0000-4000-8000-00000000eeee', '{"starts_at":"2027-03-01T01:00:00Z"}', 'ck232-u-2')$$,
  'P0002', 'not_found: event 23200000-0000-4000-8000-00000000eeee',
  'U2: STATUS QUO — …create_event_session (078)');
SELECT throws_ok($$SELECT catalog.update_event_session('23200000-0000-4000-8000-00000000ffff', '{"starts_at":"2027-03-01T01:00:00Z"}', 'ck232-u-3')$$,
  'P0002', 'not_found: session 23200000-0000-4000-8000-00000000ffff',
  'U3: STATUS QUO — …update_event_session (093)');
SELECT throws_ok($$SELECT catalog.publish_event('23200000-0000-4000-8000-00000000eeee', 'announced', 'ck232-u-4')$$,
  'P0002', 'not_found: event 23200000-0000-4000-8000-00000000eeee',
  'U4: STATUS QUO — …publish_event (102)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
