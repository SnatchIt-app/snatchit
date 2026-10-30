-- ============================================================================
-- 231_venue_cmd_event_verbs.sql — migration 20261027010000 (registry 164).
--
-- Registry 164 / pgTAP 231 — assigned by Claude A 2026-10-26 (registry 164/231).
-- Wrapper set ruled by A + F 2026-10-26: create_event, update_event,
-- create_event_session, update_event_session, publish_event, cancel_event,
-- update_venue (set_session_door_schedule dropped — B fixes its body to §20.6.5
-- first). A reviews before this leaves draft. DARK: applied nowhere; venue_cmd is
-- not exposed (owner setting).
--
-- The CI grant gates read `public` only, so THIS FILE (with 228's schema-wide
-- sweep) is the gate for the seven wrappers AND for the claim that 164 changed
-- nothing on the seven catalog targets.
--
--   Section A  shape + ACL. The seven wrappers: exact signatures; prosecdef =
--              false, LANGUAGE sql, search_path = '', VOLATILE; identity
--              arguments, full arguments and result type equal the catalog
--              target's; the body is exactly `select catalog.<same name>(<same
--              arguments>)`; EXECUTE exactly authenticated (aclexplode +
--              has_function_privilege for authenticated / anon / service_role /
--              PUBLIC; no DEFAULTED proacl). The seven catalog TARGETS: ACL still
--              exactly owner (postgres) + authenticated, SECURITY DEFINER, plpgsql,
--              search_path = '' — 164 granted nothing. No wrapper for the
--              platform verbs (create_venue, approve_venue, set_platform_config,
--              set_resale_policy) nor for set_session_door_schedule.
--   Section B  the role switch is real: inside ONE statement, current_user is
--              'authenticated' while the wrapper runs, and the body's audit row
--              carries the caller as actor (a postgres replay would bypass the
--              ACL and prove nothing — NC3).
--   Section M  allowed callers through the wrappers: org_owner, org_admin and the
--              bound venue_manager of Room V1 each succeed on all seven verbs.
--   Section R  refused callers: org_finance, venue_finance, venue_box_office,
--              venue_scanner, venue_marketing (title / time patches), the
--              cross-venue manager and a fan each get the BODY's 42501 (exact
--              message) on all seven verbs; each block first pins current_user.
--   Section N  anon: 42501 at the schema wall on all seven (no USAGE on
--              venue_cmd); no auth.uid(): the body's 'authentication required'.
--   Section S  the re-operated room (Room V2: created under Org A, its event e06
--              stamped Org A, then moved to Org B):
--                "FLIPPED BY 165" (2026-10-27; pgTAP 232) the former-operator
--                manager is REFUSED on Org A's event by update_event,
--                create_event_session, update_event_session and publish_event —
--                the E-76 conjunct is now on those catalog bodies' venue-role arm
--                (before 165 all four ACCEPTED him: the status quo 164 pinned);
--                "STATUS QUO (165 baseline)" create_event at V2 by that manager
--                (stamps the CURRENT operator's org) and update_venue of V2 by
--                that manager (no event to bind) — unchanged by 165;
--              cancel_event ALREADY refused that manager (088's E-76 conjunct).
--              The event-org arm: Org B's owner is refused on Org A's event,
--              Org A's owner is accepted on it; update_venue follows the room's
--              CURRENT org. The cross-venue manager's positive control (own room).
--   Section E  body behaviours through the wrapper: create_event born draft,
--              approved venue required, first-session starts_at required, unknown
--              venue P0002; update_event unwritable_key (also for a fan — the key
--              set is checked before authority), reason_required after draft,
--              event_terminal, the marketing-only arm; create_event_session
--              event_terminal (completed, cancelled), starts_at required, unknown
--              keys ignored with server-derived status; update_event_session
--              session_terminal, unwritable_key, doors_at edit, boundary_engaged
--              once the door opened, the marketing-only label arm; publish_event
--              illegal_transition, bad target_status for 'cancelled',
--              empty_inventory, org_not_saleable, connect_not_ready (the clone
--              fixture state allows those three of the five on_sale gates);
--              cancel_event cascade + audit, noop_replay, bounded reason;
--              update_venue operatorship_transfer_frozen (owner AND bound
--              manager), unwritable_key, the 9-value neighborhood CHECK, the audit
--              reason always 'profile_edit'.
--   Section W  the wrapper's result equals the direct call's, one representative
--              call per verb.
--   Section C  the wrapper adds NO privilege: with EXECUTE on the seven catalog
--              bodies revoked from authenticated (inside this transaction), an
--              org_owner calling each wrapper gets 'permission denied for function
--              <name>' (42501) — not the body's P0002 — then the grants are
--              restored and re-pinned. A SECURITY DEFINER wrapper fails here (NC1).
--   Section L  the function ACL is a wall of its own: with USAGE on venue_cmd
--              lent to anon (inside this transaction), anon still gets
--              'permission denied for function <name>' on all seven; USAGE is
--              revoked again and the schema ACL re-pinned. (Behind the wrapper's
--              ACL stands the body's: anon holds no EXECUTE on the catalog
--              targets either, and the message text is the same because the
--              names are — L1 is the assertion that names the wrapper's ACL.)
--
-- set_session_door_schedule is NOT routed and NOT pinned here beyond its
-- absence (A18). B's known gap (RPC §20.6.5: no reason, no audit row on that
-- body today) is B's to fix under B's own number — flagged in 164's header.
--
-- Fixture: 227 style (synthetic rows as postgres, fixed ids, tag 23100000-…,
-- read back as each caller through tap.login, rolled back). Org A: owner 101,
-- admin 102, finance 103. Room V1 (Org A, approved): manager 111, finance 112,
-- box office 113, scanner 114, marketing 115. Room V2 (re-operated A -> B):
-- manager 121 = the former-operator manager. Room V3 (Org B): manager 131 = the
-- cross-venue manager. Room V4 (Org A, pending). Org B owner 201. Fan 199.
-- Events at V1: e01 draft (the matrix target; sessions f01, f08 cancelled, f09
-- door opened), e02 announced (no tier), e03 announced (tier + batch), e04
-- completed, e05 cancelled, e11-e15 drafts for publish_event, e21/e23-e25 drafts
-- and e22 announced for cancel_event. e06 at V2 (Org A's event, draft). e07 at V3
-- (Org B's own event).
--
-- Expected on the 182 tree WITHOUT 164 (RED, predicted before the first run; the
-- reconciliation is in EVIDENCE-164.md): A1-A14 fail (14; the wrappers are absent
-- — every A-assertion over the wrappers counts pg_proc rows, so it reads `not ok`
-- instead of aborting); A15-A18 pass (4; the targets' ACL and posture are already
-- what 164 must leave untouched, and no platform/door wrapper exists). Then B1 —
-- the first call of a missing wrapper — raises 42883 and aborts the transaction;
-- B2 onward is not emitted. Predicted RED run: 18 emitted = 14 not ok + 4 ok;
-- plan 190 unmet.
-- ============================================================================
BEGIN;
SELECT plan(190);

CREATE TABLE tap.memo_231 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store231(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_231 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch231(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_231 WHERE k = $1 $m$;
-- key set + the object without its generated ids: what "same result" means for a creating verb
CREATE FUNCTION tap._shape231(j jsonb) RETURNS text
LANGUAGE sql IMMUTABLE AS
$m$ SELECT (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(j) k) || '|' || (j - 'event_id' - 'session_id')::text $m$;
GRANT EXECUTE ON FUNCTION tap._store231(text, text), tap._fetch231(text), tap._shape231(jsonb) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('23100000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.231@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.a.231@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.231@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.231@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.v1.231@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'box.v1.231@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000114', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v1.231@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000115', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v1.231@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.231@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v3.cross.231@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.231@test.local',      '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23100000-0000-4000-8000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.b.231@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('23100000-0000-4000-8000-00000000000a', 'Org A 231', 'Org A 231', 'active'),
  ('23100000-0000-4000-8000-00000000000b', 'Org B 231', 'Org B 231', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('23100000-0000-4000-8000-00000000000a', '23100000-0000-4000-8000-000000000101', 'org_owner'),
  ('23100000-0000-4000-8000-00000000000a', '23100000-0000-4000-8000-000000000102', 'org_admin'),
  ('23100000-0000-4000-8000-00000000000a', '23100000-0000-4000-8000-000000000103', 'org_finance'),
  ('23100000-0000-4000-8000-00000000000b', '23100000-0000-4000-8000-000000000201', 'org_owner');
-- V2 is created under Org A (its event e06 is stamped Org A below), then moved.
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'Room V1 231', 'wynwood',        'approved'),
  ('23100000-0000-4000-8000-0000000000a2', '23100000-0000-4000-8000-00000000000a', 'Room V2 231', 'brickell',       'approved'),
  ('23100000-0000-4000-8000-0000000000b3', '23100000-0000-4000-8000-00000000000b', 'Room V3 231', 'midtown',        'approved'),
  ('23100000-0000-4000-8000-0000000000a4', '23100000-0000-4000-8000-00000000000a', 'Room V4 231', 'downtown miami', 'pending');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-000000000111', 'venue_manager'),
  ('23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-000000000112', 'venue_finance'),
  ('23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-000000000113', 'venue_box_office'),
  ('23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-000000000115', 'venue_marketing'),
  ('23100000-0000-4000-8000-0000000000a2', '23100000-0000-4000-8000-000000000121', 'venue_manager'),
  ('23100000-0000-4000-8000-0000000000b3', '23100000-0000-4000-8000-000000000131', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23100000-0000-4000-8000-00000000e001', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e01 draft 231',      'draft'),
  ('23100000-0000-4000-8000-00000000e002', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e02 announced 231',  'announced'),
  ('23100000-0000-4000-8000-00000000e003', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e03 announced 231',  'announced'),
  ('23100000-0000-4000-8000-00000000e004', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e04 completed 231',  'completed'),
  ('23100000-0000-4000-8000-00000000e005', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e05 cancelled 231',  'cancelled'),
  ('23100000-0000-4000-8000-00000000e006', '23100000-0000-4000-8000-0000000000a2', '23100000-0000-4000-8000-00000000000a', 'e06 V2 (A event) 231', 'draft'),
  ('23100000-0000-4000-8000-00000000e007', '23100000-0000-4000-8000-0000000000b3', '23100000-0000-4000-8000-00000000000b', 'e07 V3 (B event) 231', 'draft'),
  ('23100000-0000-4000-8000-00000000e011', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e11 publish owner 231',   'draft'),
  ('23100000-0000-4000-8000-00000000e012', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e12 publish admin 231',   'draft'),
  ('23100000-0000-4000-8000-00000000e013', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e13 publish manager 231', 'draft'),
  ('23100000-0000-4000-8000-00000000e014', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e14 publish wrapper 231', 'draft'),
  ('23100000-0000-4000-8000-00000000e015', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e15 publish direct 231',  'draft'),
  ('23100000-0000-4000-8000-00000000e021', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e21 cancel owner 231',    'draft'),
  ('23100000-0000-4000-8000-00000000e022', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e22 cancel admin 231',    'announced'),
  ('23100000-0000-4000-8000-00000000e023', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e23 cancel manager 231',  'draft'),
  ('23100000-0000-4000-8000-00000000e024', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e24 cancel wrapper 231',  'draft'),
  ('23100000-0000-4000-8000-00000000e025', '23100000-0000-4000-8000-0000000000a1', '23100000-0000-4000-8000-00000000000a', 'e25 cancel direct 231',   'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, status, door_open_at) VALUES
  ('23100000-0000-4000-8000-00000000f001', '23100000-0000-4000-8000-00000000e001', NULL,              now() + interval '30 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f008', '23100000-0000-4000-8000-00000000e001', 'cancelled night', now() + interval '40 days', 'cancelled', NULL),
  ('23100000-0000-4000-8000-00000000f009', '23100000-0000-4000-8000-00000000e001', 'door night',      now() + interval '2 hours', 'scheduled', now() - interval '10 minutes'),
  ('23100000-0000-4000-8000-00000000f002', '23100000-0000-4000-8000-00000000e002', NULL, now() + interval '20 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f003', '23100000-0000-4000-8000-00000000e003', NULL, now() + interval '20 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f004', '23100000-0000-4000-8000-00000000e004', NULL, now() - interval '3 days',  'completed', NULL),
  ('23100000-0000-4000-8000-00000000f005', '23100000-0000-4000-8000-00000000e005', NULL, now() + interval '5 days',  'cancelled', NULL),
  ('23100000-0000-4000-8000-00000000f006', '23100000-0000-4000-8000-00000000e006', NULL, now() + interval '7 days',  'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f007', '23100000-0000-4000-8000-00000000e007', NULL, now() + interval '9 days',  'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f011', '23100000-0000-4000-8000-00000000e011', NULL, now() + interval '11 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f012', '23100000-0000-4000-8000-00000000e012', NULL, now() + interval '12 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f013', '23100000-0000-4000-8000-00000000e013', NULL, now() + interval '13 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f014', '23100000-0000-4000-8000-00000000e014', NULL, now() + interval '14 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f015', '23100000-0000-4000-8000-00000000e015', NULL, now() + interval '15 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f021', '23100000-0000-4000-8000-00000000e021', NULL, now() + interval '21 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f022', '23100000-0000-4000-8000-00000000e022', NULL, now() + interval '22 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f023', '23100000-0000-4000-8000-00000000e023', NULL, now() + interval '23 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f024', '23100000-0000-4000-8000-00000000e024', NULL, now() + interval '24 days', 'scheduled', NULL),
  ('23100000-0000-4000-8000-00000000f025', '23100000-0000-4000-8000-00000000e025', NULL, now() + interval '25 days', 'scheduled', NULL);
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('23100000-0000-4000-8000-00000000d003', '23100000-0000-4000-8000-00000000e003', 'admission', 'GA e03 231', 2500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('23100000-0000-4000-8000-00000000c003', '23100000-0000-4000-8000-00000000d003', '23100000-0000-4000-8000-00000000f003', 'public_sale', 100, 0, 0);
-- THE RE-OPERATION: Room V2 moves from Org A to Org B. e06 keeps org_id = A (the
-- stand-in for the pre-093 tenancy move, 078:684-704, which did not re-stamp
-- events; 093's Decision C freezes the verb, so this state exists only from history).
UPDATE catalog.venue SET org_id = '23100000-0000-4000-8000-00000000000b'
 WHERE venue_id = '23100000-0000-4000-8000-0000000000a2';

-- ── Section A — shape + ACL ──────────────────────────────────────────────────
-- Every assertion over the wrappers counts pg_proc rows (no regprocedure cast), so
-- on a chain without 164 it reads `not ok` instead of aborting the file.
SELECT set_eq(
  $$ SELECT p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'venue_cmd'
        AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue') $$,
  $$ VALUES ('create_event(uuid, text, jsonb, text)'), ('update_event(uuid, jsonb, text)'),
            ('create_event_session(uuid, jsonb, text)'), ('update_event_session(uuid, jsonb, text)'),
            ('publish_event(uuid, text, text)'), ('cancel_event(uuid, text, text)'), ('update_venue(uuid, jsonb, text)') $$,
  'A1: venue_cmd holds exactly these seven 164 signatures (one overload each)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND NOT p.prosecdef
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A2: all seven are SECURITY INVOKER (prosecdef = false, counted positively)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND l.lanname = 'sql'
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A3: all seven are LANGUAGE sql (no logic can hide in a wrapper)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proconfig = ARRAY['search_path=""']
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A4: all seven pin search_path to the empty string (and set nothing else)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.provolatile = 'v'
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A5: all seven are VOLATILE (commands, like their targets)');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            JOIN pg_proc t ON t.proname = w.proname AND t.pronamespace = 'catalog'::regnamespace
            WHERE n.nspname = 'venue_cmd'
              AND w.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')
              AND pg_get_function_identity_arguments(w.oid) = pg_get_function_identity_arguments(t.oid)), 7,
  'A6: each wrapper''s identity argument list (names and types) equals its catalog target''s');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            JOIN pg_proc t ON t.proname = w.proname AND t.pronamespace = 'catalog'::regnamespace
            WHERE n.nspname = 'venue_cmd'
              AND w.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')
              AND pg_get_function_arguments(w.oid) = pg_get_function_arguments(t.oid)), 7,
  'A7: each wrapper''s full argument list (names, types, defaults) equals its catalog target''s');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            JOIN pg_proc t ON t.proname = w.proname AND t.pronamespace = 'catalog'::regnamespace
            WHERE n.nspname = 'venue_cmd'
              AND w.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')
              AND pg_get_function_result(w.oid) = pg_get_function_result(t.oid) AND pg_get_function_result(w.oid) = 'jsonb'), 7,
  'A8: each wrapper''s result type equals its catalog target''s (jsonb)');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            WHERE n.nspname = 'venue_cmd'
              AND w.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')
              AND regexp_replace(btrim(w.prosrc, E' \n\t\r'), '\s+', ' ', 'g')
                  = 'select catalog.' || w.proname || '(' || array_to_string(w.proargnames, ', ') || ')'), 7,
  'A9: each body is exactly `select catalog.<same name>(<its own arguments, in order>)` — a one-line delegation');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd' AND a.grantee <> p.proowner
        AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue') $$,
  $$ VALUES ('create_event:authenticated:EXECUTE'), ('update_event:authenticated:EXECUTE'),
            ('create_event_session:authenticated:EXECUTE'), ('update_event_session:authenticated:EXECUTE'),
            ('publish_event:authenticated:EXECUTE'), ('cancel_event:authenticated:EXECUTE'), ('update_venue:authenticated:EXECUTE') $$,
  'A10: the wrapper ACL matrix (aclexplode) is exactly EXECUTE to authenticated on each of the seven — no PUBLIC, anon, service_role');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A11: has_function_privilege(authenticated, EXECUTE) is true on all seven');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A12: has_function_privilege(anon, EXECUTE) is false on all seven (counted positively)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A13: has_function_privilege(service_role, EXECUTE) is false on all seven (no server-side caller)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proacl IS NOT NULL
              AND NOT has_function_privilege('public', p.oid, 'EXECUTE')
              AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A14: no proacl is DEFAULTED and PUBLIC holds nothing on any of the seven');
-- the TARGETS: 164 granted nothing and revoked nothing
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'catalog'
        AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue') $$,
  $$ VALUES ('create_event:postgres:EXECUTE'), ('create_event:authenticated:EXECUTE'),
            ('update_event:postgres:EXECUTE'), ('update_event:authenticated:EXECUTE'),
            ('create_event_session:postgres:EXECUTE'), ('create_event_session:authenticated:EXECUTE'),
            ('update_event_session:postgres:EXECUTE'), ('update_event_session:authenticated:EXECUTE'),
            ('publish_event:postgres:EXECUTE'), ('publish_event:authenticated:EXECUTE'),
            ('cancel_event:postgres:EXECUTE'), ('cancel_event:authenticated:EXECUTE'),
            ('update_venue:postgres:EXECUTE'), ('update_venue:authenticated:EXECUTE') $$,
  'A15: the seven catalog TARGETS'' ACLs are UNCHANGED by 164 — exactly owner (postgres) + authenticated, production''s {postgres=X/postgres,authenticated=X/postgres}');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog' AND p.proacl IS NOT NULL
              AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
              AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
              AND NOT has_function_privilege('public', p.oid, 'EXECUTE')
              AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A16: on each target anon, service_role and PUBLIC hold no EXECUTE, authenticated does, and no proacl is DEFAULTED');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'catalog' AND p.prosecdef AND l.lanname = 'plpgsql'
              AND 'search_path=""' = ANY (coalesce(p.proconfig, '{}'))
              AND p.proowner = 'postgres'::regrole AND pg_get_function_result(p.oid) = 'jsonb'
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')), 7,
  'A17: each target is still a postgres-owned SECURITY DEFINER plpgsql body with search_path = '''' returning jsonb (the authority the wrappers route to)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd'
              AND p.proname IN ('create_venue','approve_venue','set_platform_config','set_resale_policy','set_session_door_schedule')), 0,
  'A18: NO venue_cmd route to the platform verbs (create_venue, approve_venue, set_platform_config, set_resale_policy) nor to set_session_door_schedule (dropped until B fixes its body)');

-- ── Section B — the role switch is real ─────────────────────────────────────
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT is((SELECT current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text || '|'
                  || (venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"address":"1 Wrapper Way"}', 'ck231-b1') ->> 'status')),
  'authenticated|authenticated|23100000-0000-4000-8000-000000000101|ok',
  'B1: in ONE statement the wrapper runs while current_user = ''authenticated'' (role GUC too) as the owner''s auth.uid() — and succeeds');
SELECT tap.logout();
SELECT is((SELECT actor_identity::text || '|' || (after ->> 'address') FROM kernel.admin_audit
            WHERE action = 'venue.update' AND subject_id = '23100000-0000-4000-8000-0000000000a1'),
  '23100000-0000-4000-8000-000000000101|1 Wrapper Way',
  'B2: the definer body audited that call with the CALLER as actor (auth.uid() seen through SECURITY INVOKER)');

-- ── Section M — allowed callers succeed on all seven verbs ───────────────────
-- org_owner (101)
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT is((SELECT current_user::text || '|' || (venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'Created by owner 231',
             jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-m-ce-101') ->> 'status')), 'authenticated|ok',
  'M1: org_owner — create_event through the wrapper (current_user = authenticated during the call)');
SELECT is((venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"e01 by owner"}', 'ck231-m-ue-101') ->> 'status'), 'ok',
  'M2: org_owner — update_event (title of a draft)');
SELECT is((venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001',
             jsonb_build_object('starts_at', now() + interval '31 days', 'session_label', 'by owner'), 'ck231-m-cs-101') ->> 'status'), 'ok',
  'M3: org_owner — create_event_session');
SELECT is((venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001',
             jsonb_build_object('starts_at', now() + interval '30 days 1 hour'), 'ck231-m-us-101') ->> 'status'), 'ok',
  'M4: org_owner — update_event_session (starts_at)');
SELECT is((venue_cmd.publish_event('23100000-0000-4000-8000-00000000e011', 'announced', 'ck231-m-pe-101') ->> 'event_status'), 'announced',
  'M5: org_owner — publish_event draft -> announced');
SELECT is((venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e021', 'weather', 'ck231-m-xe-101') ->> 'status'), 'ok',
  'M6: org_owner — cancel_event on a draft');
SELECT is((venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"address":"101 Owner St"}', 'ck231-m-uv-101') ->> 'status'), 'ok',
  'M7: org_owner — update_venue (address)');
SELECT tap.logout();
-- org_admin (102)
SELECT tap.login('23100000-0000-4000-8000-000000000102');
SELECT is((SELECT current_user::text || '|' || (venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'Created by admin 231',
             jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-m-ce-102') ->> 'status')), 'authenticated|ok',
  'M8: org_admin — create_event (current_user = authenticated during the call)');
SELECT is((venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"e01 by admin"}', 'ck231-m-ue-102') ->> 'status'), 'ok',
  'M9: org_admin — update_event');
SELECT is((venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001',
             jsonb_build_object('starts_at', now() + interval '32 days', 'session_label', 'by admin'), 'ck231-m-cs-102') ->> 'status'), 'ok',
  'M10: org_admin — create_event_session');
SELECT is((venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001',
             jsonb_build_object('starts_at', now() + interval '30 days 2 hours'), 'ck231-m-us-102') ->> 'status'), 'ok',
  'M11: org_admin — update_event_session');
SELECT is((venue_cmd.publish_event('23100000-0000-4000-8000-00000000e012', 'announced', 'ck231-m-pe-102') ->> 'event_status'), 'announced',
  'M12: org_admin — publish_event draft -> announced');
SELECT is((venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e022', 'weather', 'ck231-m-xe-102') ->> 'status'), 'ok',
  'M13: org_admin — cancel_event on an announced event');
SELECT is((venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"address":"102 Admin St"}', 'ck231-m-uv-102') ->> 'status'), 'ok',
  'M14: org_admin — update_venue');
SELECT tap.logout();
-- the bound venue_manager of Room V1 (111)
SELECT tap.login('23100000-0000-4000-8000-000000000111');
SELECT is((SELECT current_user::text || '|' || (venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'Created by manager 231',
             jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-m-ce-111') ->> 'status')), 'authenticated|ok',
  'M15: bound venue_manager — create_event (current_user = authenticated during the call)');
SELECT is((venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"e01 by manager"}', 'ck231-m-ue-111') ->> 'status'), 'ok',
  'M16: bound venue_manager — update_event');
SELECT is((venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001',
             jsonb_build_object('starts_at', now() + interval '33 days', 'session_label', 'by manager'), 'ck231-m-cs-111') ->> 'status'), 'ok',
  'M17: bound venue_manager — create_event_session');
SELECT is((venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001',
             jsonb_build_object('starts_at', now() + interval '30 days 3 hours'), 'ck231-m-us-111') ->> 'status'), 'ok',
  'M18: bound venue_manager — update_event_session');
SELECT is((venue_cmd.publish_event('23100000-0000-4000-8000-00000000e013', 'announced', 'ck231-m-pe-111') ->> 'event_status'), 'announced',
  'M19: bound venue_manager — publish_event draft -> announced');
SELECT is((venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e023', 'weather', 'ck231-m-xe-111') ->> 'status'), 'ok',
  'M20: bound venue_manager — cancel_event (Room V1 is still Org A''s: 088''s E-76 conjunct holds)');
SELECT is((venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"address":"111 Manager St"}', 'ck231-m-uv-111') ->> 'status'), 'ok',
  'M21: bound venue_manager — update_venue');
SELECT tap.logout();

-- ── Section R — refused callers get the BODY's 42501 on all seven verbs ──────
-- org_finance (103)
SELECT tap.login('23100000-0000-4000-8000-000000000103');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000103',
  'R1: org_finance block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-103-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R2: org_finance — create_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-103-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R3: org_finance — update_event refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-103-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R4: org_finance — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-103-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R5: org_finance — update_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-103-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R6: org_finance — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-103-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R7: org_finance — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-103-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R8: org_finance — update_venue refused');
SELECT tap.logout();
-- venue_finance (112)
SELECT tap.login('23100000-0000-4000-8000-000000000112');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000112',
  'R9: venue_finance block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-112-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R10: venue_finance — create_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-112-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R11: venue_finance — update_event refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-112-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R12: venue_finance — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-112-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R13: venue_finance — update_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-112-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R14: venue_finance — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-112-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R15: venue_finance — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-112-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R16: venue_finance — update_venue refused');
SELECT tap.logout();
-- venue_box_office (113)
SELECT tap.login('23100000-0000-4000-8000-000000000113');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000113',
  'R17: venue_box_office block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-113-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R18: venue_box_office — create_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-113-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R19: venue_box_office — update_event refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-113-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R20: venue_box_office — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-113-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R21: venue_box_office — update_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-113-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R22: venue_box_office — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-113-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R23: venue_box_office — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-113-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R24: venue_box_office — update_venue refused');
SELECT tap.logout();
-- venue_scanner (114)
SELECT tap.login('23100000-0000-4000-8000-000000000114');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000114',
  'R25: venue_scanner block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-114-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R26: venue_scanner — create_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-114-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R27: venue_scanner — update_event refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-114-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R28: venue_scanner — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-114-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R29: venue_scanner — update_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-114-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R30: venue_scanner — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-114-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R31: venue_scanner — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-114-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R32: venue_scanner — update_venue refused');
SELECT tap.logout();
-- venue_marketing (115) — title / time patches (its marketing-only arm is pinned in E12/E24)
SELECT tap.login('23100000-0000-4000-8000-000000000115');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000115',
  'R33: venue_marketing block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-115-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R34: venue_marketing — create_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-115-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R35: venue_marketing — update_event with a TITLE refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-115-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R36: venue_marketing — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-115-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R37: venue_marketing — update_event_session with a TIME column refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-115-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R38: venue_marketing — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-115-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R39: venue_marketing — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-115-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R40: venue_marketing — update_venue refused');
SELECT tap.logout();
-- the cross-venue manager (131, manager of Room V3 / Org B) on Room V1's objects
SELECT tap.login('23100000-0000-4000-8000-000000000131');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000131',
  'R41: cross-venue manager block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-131-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R42: cross-venue manager — create_event at V1 refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-131-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R43: cross-venue manager — update_event refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-131-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R44: cross-venue manager — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-131-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R45: cross-venue manager — update_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-131-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R46: cross-venue manager — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-131-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R47: cross-venue manager — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-131-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R48: cross-venue manager — update_venue of V1 refused');
SELECT tap.logout();
-- a fan (199) with no grant
SELECT tap.login('23100000-0000-4000-8000-000000000199');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000199',
  'R49: fan block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-r-199-1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R50: fan — create_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-r-199-2')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required', 'R51: fan — update_event refused');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-r-199-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R52: fan — create_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-r-199-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R53: fan — update_event_session refused');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-r-199-5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R54: fan — publish_event refused');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-r-199-6')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only', 'R55: fan — cancel_event refused');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-r-199-7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R56: fan — update_venue refused');
SELECT tap.logout();

-- ── Section N — anon and the unauthenticated path ───────────────────────────
SELECT tap.login_anon();
SELECT is(current_user::text || '|' || coalesce(auth.uid()::text, 'no-uid'), 'anon|no-uid', 'N1: the anon block runs as anon with no auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-n-1')$$,
  '42501', 'permission denied for schema venue_cmd', 'N2: anon — create_event refused at the schema wall');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"title":"x"}', 'ck231-n-2')$$,
  '42501', 'permission denied for schema venue_cmd', 'N3: anon — update_event refused at the schema wall');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '34 days'), 'ck231-n-3')$$,
  '42501', 'permission denied for schema venue_cmd', 'N4: anon — create_event_session refused at the schema wall');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('starts_at', now() + interval '35 days'), 'ck231-n-4')$$,
  '42501', 'permission denied for schema venue_cmd', 'N5: anon — update_event_session refused at the schema wall');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'announced', 'ck231-n-5')$$,
  '42501', 'permission denied for schema venue_cmd', 'N6: anon — publish_event refused at the schema wall');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'weather', 'ck231-n-6')$$,
  '42501', 'permission denied for schema venue_cmd', 'N7: anon — cancel_event refused at the schema wall');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"x"}', 'ck231-n-7')$$,
  '42501', 'permission denied for schema venue_cmd', 'N8: anon — update_venue refused at the schema wall');
SELECT tap.logout();
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-n-9')$$,
  '42501', 'insufficient_privilege: authentication required', 'N9: no auth.uid() through the wrapper — the body''s authentication-required refusal propagates');

-- ── Section S — the re-operated room (Room V2: Org A -> Org B; e06 is Org A's) ─
SELECT tap.login('23100000-0000-4000-8000-000000000121');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000121',
  'S1: former-operator manager block runs as authenticated with its own auth.uid()');
SELECT tap._store231('s_ev', (venue_cmd.create_event('23100000-0000-4000-8000-0000000000a2', 'Former manager event 231',
          jsonb_build_object('starts_at', now() + interval '8 days'), 'ck231-s-ce') ->> 'event_id'));
SELECT ok(tap._fetch231('s_ev') IS NOT NULL,
  'S2: STATUS QUO (165 baseline) — the former-operator manager CREATES an event at the re-operated Room V2 through the wrapper');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e006', '{"title":"e06 retitled by former manager"}', 'ck231-s-ue')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required',
  'S3: FLIPPED BY 165 — the former-operator manager is REFUSED update_event on Org A''s event at Room V2 (E-76 conjunct on catalog.update_event)');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e006',
             jsonb_build_object('starts_at', now() + interval '9 days', 'session_label', 'former'), 'ck231-s-cs')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S4: FLIPPED BY 165 — the former-operator manager is REFUSED create_event_session on Org A''s event (E-76 conjunct on catalog.create_event_session)');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f006',
             jsonb_build_object('starts_at', now() + interval '7 days 1 hour'), 'ck231-s-us')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S5: FLIPPED BY 165 — the former-operator manager is REFUSED update_event_session on Org A''s session (E-76 conjunct on catalog.update_event_session)');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e006', 'announced', 'ck231-s-pe')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S6: FLIPPED BY 165 — the former-operator manager is REFUSED publish_event on Org A''s event (E-76 conjunct on catalog.publish_event)');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e006', 'weather', 'ck231-s-xe')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only',
  'S7: cancel_event refuses the former-operator manager (088''s E-76 conjunct — the shape 165 copied onto S3-S6)');
SELECT is((venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a2', '{"name":"Room V2 renamed by former manager"}', 'ck231-s-uv') ->> 'status'), 'ok',
  'S8: STATUS QUO (165 baseline) — the former-operator manager''s staff grant still EDITS Room V2''s profile (no event to bind)');
SELECT tap.logout();
SELECT is((SELECT e.status || '|' || e.org_id::text FROM catalog.event e WHERE e.event_id = tap._fetch231('s_ev')::uuid),
  'draft|23100000-0000-4000-8000-00000000000b',
  'S9: STATUS QUO (165 baseline) — that event is born draft and stamped with the room''s CURRENT operator (Org B), not the manager''s former org');
-- Org B's owner (the new operator) on Org A's event at its room
SELECT tap.login('23100000-0000-4000-8000-000000000201');
SELECT is(current_user::text || '|' || current_setting('role') || '|' || auth.uid()::text, 'authenticated|authenticated|23100000-0000-4000-8000-000000000201',
  'S10: Org B owner block runs as authenticated with its own auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e006', '{"title":"x"}', 'ck231-s-b-1')$$,
  '42501', 'insufficient_privilege: venue_manager/org_owner/org_admin required',
  'S11: event-org arm — the new operator''s owner is refused on Org A''s event (update_event)');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e006', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-s-b-2')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S12: event-org arm — refused on Org A''s event (create_event_session)');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f006', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-s-b-3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S13: event-org arm — refused on Org A''s session (update_event_session)');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e006', 'on_sale', 'ck231-s-b-4')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S14: event-org arm — refused on Org A''s event (publish_event; the role check precedes the on_sale gates)');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e006', 'weather', 'ck231-s-b-5')$$,
  '42501', 'insufficient_privilege: org_owner / org_admin / venue_manager (current operator) / platform_admin only',
  'S15: event-org arm — refused on Org A''s event (cancel_event)');
SELECT is((venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a2', '{"address":"201 New Operator Ave"}', 'ck231-s-b-6') ->> 'status'), 'ok',
  'S16: update_venue follows the room''s CURRENT org — the new operator''s owner edits Room V2');
SELECT tap.logout();
-- Org A's owner (the former operator) on its own event at the moved room, and on the room
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT is((venue_cmd.update_event('23100000-0000-4000-8000-00000000e006', '{"description":"Org A still owns e06"}', 'ck231-s-a-1') ->> 'status'), 'ok',
  'S17: event-org arm — Org A''s owner still edits its own event at the room Org B now operates');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a2', '{"name":"x"}', 'ck231-s-a-2')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required',
  'S18: …but Org A''s owner can no longer edit Room V2 itself (the room''s org is now B)');
SELECT tap.logout();

-- ── Section E — body behaviours through the wrapper ─────────────────────────
-- create_event
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT tap._store231('e_ev', (venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'Born draft 231',
          '{"starts_at":"2026-12-31T21:00:00Z","session_label":"opening"}', 'ck231-e-ce-1') ->> 'event_id'));
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a4', 'Pending room event', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-e-ce-2')$$,
  'P0001', 'precondition_failed: venue is not approved', 'E2: create_event at a PENDING room is refused (venue must be approved)');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'No start 231', '{"session_label":"no start"}', 'ck231-e-ce-3')$$,
  'P0001', 'invalid_input: starts_at required', 'E3: create_event whose first session has no starts_at is refused');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000ff', 'Ghost room', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-e-ce-4')$$,
  'P0002', NULL, 'E4: create_event at an unknown room — P0002');
SELECT tap.logout();
SELECT is((SELECT e.status || '|' || e.org_id::text || '|' || e.venue_id::text || '|'
                  || (SELECT count(*) FROM catalog.event_session s WHERE s.event_id = e.event_id)::text || '|'
                  || (SELECT bool_and(s.starts_at = '2026-12-31T21:00:00Z'::timestamptz AND s.status = 'scheduled') FROM catalog.event_session s WHERE s.event_id = e.event_id)::text
             FROM catalog.event e WHERE e.event_id = tap._fetch231('e_ev')::uuid),
  'draft|23100000-0000-4000-8000-00000000000a|23100000-0000-4000-8000-0000000000a1|1|true',
  'E1: an event created through the wrapper is born DRAFT, stamped with the room''s org, with exactly one scheduled session at the given starts_at');
SELECT is((SELECT count(*)::int FROM catalog.event WHERE title = 'No start 231'), 0,
  'E5: the refused create (E3) left no event row behind (the implicit-session failure rolls the whole call back)');
-- update_event
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"status":"on_sale"}', 'ck231-e-ue-1')$$,
  'P0001', 'invalid_input: unwritable_key status', 'E6: update_event refuses an unwritable key (status) — invalid_input: unwritable_key');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e002', '{"title":"e02 renamed"}', 'ck231-e-ue-2')$$,
  'P0001', 'precondition_failed: reason_required for a title change after draft', 'E8: a title change after draft (announced) without reason_code is refused');
SELECT is((venue_cmd.update_event('23100000-0000-4000-8000-00000000e002', '{"title":"e02 renamed","reason_code":"rename"}', 'ck231-e-ue-3') ->> 'status'), 'ok',
  'E9: …and accepted with a reason_code');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e004', '{"description":"late"}', 'ck231-e-ue-4')$$,
  'P0001', 'precondition_failed: event_terminal', 'E11: update_event on a COMPLETED event — event_terminal');
SELECT tap.logout();
SELECT tap.login('23100000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"org_id":"23100000-0000-4000-8000-00000000000b"}', 'ck231-e-ue-5')$$,
  'P0001', 'invalid_input: unwritable_key org_id', 'E7: a FAN naming org_id learns invalid_input, not 42501 — the key set is checked before authority (T-RPC-CAT-01)');
SELECT tap.logout();
SELECT tap.login('23100000-0000-4000-8000-000000000115');
SELECT is((venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"description":"marketing copy 231"}', 'ck231-e-ue-6') ->> 'status'), 'ok',
  'E12: the marketing-only arm — venue_marketing may edit description (never title: R35)');
SELECT tap.logout();
SELECT is((SELECT reason_code || '|' || (after ->> 'title') FROM kernel.admin_audit
            WHERE action = 'event.update' AND subject_id = '23100000-0000-4000-8000-00000000e002'),
  'rename|e02 renamed', 'E10: the post-draft title change is audited with its reason_code');
-- create_event_session
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e004', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-e-cs-1')$$,
  'P0001', 'precondition_failed: event_terminal', 'E13: create_event_session on a COMPLETED event — event_terminal');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e005', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-e-cs-2')$$,
  'P0001', 'precondition_failed: event_terminal', 'E14: create_event_session on a CANCELLED event — event_terminal');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', '{"session_label":"no start"}', 'ck231-e-cs-3')$$,
  'P0001', 'invalid_input: starts_at required', 'E15: create_event_session without starts_at is refused');
SELECT tap._store231('e_ses', (venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001',
          jsonb_build_object('starts_at', now() + interval '36 days', 'session_label', 'ignored keys', 'status', 'live', 'home_region', 'eu-west'),
          'ck231-e-cs-4') ->> 'session_id'));
SELECT ok(tap._fetch231('e_ses') IS NOT NULL, 'E16: create_event_session silently IGNORES unknown keys (no key loop) — the call succeeds');
SELECT tap.logout();
SELECT is((SELECT status || '|' || home_region FROM catalog.event_session WHERE session_id = tap._fetch231('e_ses')::uuid), 'scheduled|us-east',
  'E17: …and status / home_region stay SERVER-DERIVED (a client-sent status ''live'' never lands) — clients must refuse unknown keys themselves');
-- update_event_session
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f008', '{"session_label":"revived"}', 'ck231-e-us-1')$$,
  'P0001', 'precondition_failed: session_terminal', 'E18: update_event_session on a CANCELLED session (of a live draft event) — session_terminal');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f004', '{"session_label":"revived"}', 'ck231-e-us-2')$$,
  'P0001', 'precondition_failed: session_terminal', 'E19: update_event_session on a COMPLETED session — session_terminal');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('door_open_at', now()), 'ck231-e-us-3')$$,
  'P0001', 'invalid_input: unwritable_key door_open_at', 'E20: update_event_session refuses door_open_at (sole writer: engage_door_freeze) — unwritable_key');
SELECT is((venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', jsonb_build_object('doors_at', now() + interval '30 days'), 'ck231-e-us-4') ->> 'status'), 'ok',
  'E21: doors_at is edited through update_event_session (F''s door-time route; set_session_door_schedule is not routed)');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f009', jsonb_build_object('doors_at', now() + interval '1 hour'), 'ck231-e-us-5')$$,
  'P0001', 'precondition_failed: boundary_engaged', 'E23: once the door opened (door_open_at set), a doors_at move is refused — boundary_engaged');
SELECT tap.logout();
SELECT is((SELECT doors_at = now() + interval '30 days' FROM catalog.event_session WHERE session_id = '23100000-0000-4000-8000-00000000f001'), true,
  'E22: …and the new doors_at is stored');
SELECT tap.login('23100000-0000-4000-8000-000000000115');
SELECT is((venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', '{"session_label":"marketing label"}', 'ck231-e-us-6') ->> 'status'), 'ok',
  'E24: the marketing-only arm — venue_marketing may relabel a session (never move its times: R37)');
SELECT tap.logout();
-- publish_event
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'on_sale', 'ck231-e-pe-1')$$,
  'P0001', 'precondition_failed: illegal_transition (draft -> on_sale)', 'E25: draft -> on_sale jumps a step — illegal_transition');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e001', 'cancelled', 'ck231-e-pe-2')$$,
  'P0001', 'invalid_input: bad target_status cancelled (cancellation is catalog.cancel_event)', 'E26: publish_event refuses cancellation — bad target_status');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e002', 'on_sale', 'ck231-e-pe-3')$$,
  'P0001', 'precondition_failed: empty_inventory', 'E27: announced -> on_sale with NO tier/batch — empty_inventory');
SELECT tap.logout();
UPDATE kernel.organization SET status = 'suspended' WHERE org_id = '23100000-0000-4000-8000-00000000000a';
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e003', 'on_sale', 'ck231-e-pe-4')$$,
  'P0001', 'precondition_failed: org_not_saleable — a suspended organization may not go on sale', 'E28: on_sale gate 1 — a suspended org: org_not_saleable');
SELECT tap.logout();
UPDATE kernel.organization SET status = 'active' WHERE org_id = '23100000-0000-4000-8000-00000000000a';
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e003', 'on_sale', 'ck231-e-pe-5')$$,
  'P0001', 'precondition_failed: connect_not_ready', 'E29: on_sale gate 2 — an active org with no Connect account: connect_not_ready');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-00000000e004', 'live', 'ck231-e-pe-6')$$,
  'P0001', 'precondition_failed: illegal_transition (completed -> live)', 'E31: a completed event cannot move — illegal_transition');
SELECT tap.logout();
SELECT is((SELECT string_agg(e.event_id::text || '=' || e.status, ',' ORDER BY e.event_id) FROM catalog.event e
            WHERE e.event_id IN ('23100000-0000-4000-8000-00000000e002', '23100000-0000-4000-8000-00000000e003', '23100000-0000-4000-8000-00000000e011'))
          || '|' || (SELECT count(*)::text FROM kernel.admin_audit a WHERE a.action = 'event.status' AND a.subject_id = '23100000-0000-4000-8000-00000000e011'
                       AND a.actor_identity = '23100000-0000-4000-8000-000000000101' AND a.reason_code = 'publish'),
  '23100000-0000-4000-8000-00000000e002=announced,23100000-0000-4000-8000-00000000e003=announced,23100000-0000-4000-8000-00000000e011=announced|1',
  'E30: the refused on_sale attempts left e02/e03 announced; M5''s publish of e11 is audited once (event.status, reason publish, actor = the owner)');
-- cancel_event
SELECT is((SELECT e.status || '|' || (SELECT string_agg(s.status, ',') FROM catalog.event_session s WHERE s.event_id = e.event_id) || '|'
                  || (SELECT count(*) FROM kernel.admin_audit a WHERE a.action = 'event.cancel' AND a.subject_id = e.event_id
                        AND a.reason_code = 'weather' AND a.actor_identity = '23100000-0000-4000-8000-000000000101')::text
             FROM catalog.event e WHERE e.event_id = '23100000-0000-4000-8000-00000000e021'),
  'cancelled|cancelled|1',
  'E32: M6''s cancel through the wrapper cancelled the event AND its session and wrote one event.cancel audit row (reason weather, actor = the owner)');
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT is((venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e021', 'weather', 'ck231-e-xe-1') ->> 'status'), 'noop_replay',
  'E33: cancelling again is re-entrant — noop_replay');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e001', 'bad reason!', 'ck231-e-xe-2')$$,
  'P0001', 'invalid_input: reason_code must be 1-64 chars of [A-Za-z0-9._:-]', 'E34: the cancel reason that lands in the audit is bounded (E-80)');
-- update_venue
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"org_id":"23100000-0000-4000-8000-00000000000b","reason_code":"sale"}', 'ck231-e-uv-1')$$,
  'P0001', 'precondition_failed: operatorship_transfer_frozen — venue operatorship transfer is suspended pending the 093+ atomic re-scoping verb (Decision C). Contact the platform owner.',
  'E35: an org_id patch is refused — operatorship_transfer_frozen (Decision C), even for the operating org''s owner');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"approval_status":"approved"}', 'ck231-e-uv-2')$$,
  'P0001', 'invalid_input: unwritable_key approval_status', 'E38: update_venue refuses an unwritable key (approval_status) — invalid_input: unwritable_key');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"neighborhood":"atlantis"}', 'ck231-e-uv-3')$$,
  '23514', NULL, 'E39: a neighborhood outside the 9-value CHECK is refused at the table (23514)');
SELECT is((venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"name":"Room V1 renamed","reason_code":"renovation"}', 'ck231-e-uv-4') ->> 'status'), 'ok',
  'E40: a name patch carrying a reason_code is accepted');
SELECT tap.logout();
SELECT tap.login('23100000-0000-4000-8000-000000000111');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"org_id":"23100000-0000-4000-8000-00000000000b"}', 'ck231-e-uv-5')$$,
  'P0001', 'precondition_failed: operatorship_transfer_frozen — venue operatorship transfer is suspended pending the 093+ atomic re-scoping verb (Decision C). Contact the platform owner.',
  'E37: the bound venue_manager reaches the same freeze (operator changes are frozen for every authorized caller)');
SELECT tap.logout();
SELECT is((SELECT org_id::text FROM catalog.venue WHERE venue_id = '23100000-0000-4000-8000-0000000000a1'), '23100000-0000-4000-8000-00000000000a',
  'E36: Room V1 is still Org A''s after both org_id attempts');
SELECT is((SELECT reason_code || '|' || (after ->> 'name') FROM kernel.admin_audit
            WHERE action = 'venue.update' AND subject_id = '23100000-0000-4000-8000-0000000000a1' AND after ->> 'name' = 'Room V1 renamed'),
  'profile_edit|Room V1 renamed',
  'E41: the audit reason is ''profile_edit'' even when the patch carries a reason_code (093 no longer assigns it) — the dashboard must not promise a custom reason');

-- ── Section W — wrapper result equals direct result (one call per verb) ──────
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT tap._store231('w1w', venue_cmd.create_event('23100000-0000-4000-8000-0000000000a1', 'W1 wrapper 231', jsonb_build_object('starts_at', now() + interval '12 days'), 'ck231-w1-w')::text);
SELECT tap._store231('w1d', catalog.create_event('23100000-0000-4000-8000-0000000000a1', 'W1 direct 231', jsonb_build_object('starts_at', now() + interval '12 days'), 'ck231-w1-d')::text);
SELECT is(tap._shape231(tap._fetch231('w1w')::jsonb), tap._shape231(tap._fetch231('w1d')::jsonb),
  'W1: create_event — wrapper and direct return the same keys and the same values apart from the generated ids');
SELECT is(venue_cmd.update_event('23100000-0000-4000-8000-00000000e001', '{"description":"same copy"}', 'ck231-w2-w'),
          catalog.update_event('23100000-0000-4000-8000-00000000e001', '{"description":"same copy"}', 'ck231-w2-d'),
  'W2: update_event — identical results');
SELECT tap._store231('w3w', venue_cmd.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '37 days', 'session_label', 'W3 wrapper'), 'ck231-w3-w')::text);
SELECT tap._store231('w3d', catalog.create_event_session('23100000-0000-4000-8000-00000000e001', jsonb_build_object('starts_at', now() + interval '38 days', 'session_label', 'W3 direct'), 'ck231-w3-d')::text);
SELECT is(tap._shape231(tap._fetch231('w3w')::jsonb), tap._shape231(tap._fetch231('w3d')::jsonb),
  'W3: create_event_session — same keys and values apart from the generated session id');
SELECT is(venue_cmd.update_event_session('23100000-0000-4000-8000-00000000f001', '{"session_label":"W4 night"}', 'ck231-w4-w'),
          catalog.update_event_session('23100000-0000-4000-8000-00000000f001', '{"session_label":"W4 night"}', 'ck231-w4-d'),
  'W4: update_event_session — identical results (status, session_id, effective_freeze_at)');
SELECT is(venue_cmd.publish_event('23100000-0000-4000-8000-00000000e014', 'announced', 'ck231-w5-w'),
          catalog.publish_event('23100000-0000-4000-8000-00000000e015', 'announced', 'ck231-w5-d'),
  'W5: publish_event — identical results on twin drafts');
SELECT is(venue_cmd.cancel_event('23100000-0000-4000-8000-00000000e024', 'weather', 'ck231-w6-w') - 'event_id',
          catalog.cancel_event('23100000-0000-4000-8000-00000000e025', 'weather', 'ck231-w6-d') - 'event_id',
  'W6: cancel_event — identical results on twin drafts (apart from the event id)');
SELECT is(venue_cmd.update_venue('23100000-0000-4000-8000-0000000000a1', '{"capacity_hint":300}', 'ck231-w7-w'),
          catalog.update_venue('23100000-0000-4000-8000-0000000000a1', '{"capacity_hint":300}', 'ck231-w7-d'),
  'W7: update_venue — identical results');
SELECT tap.logout();

-- ── Section C — the wrapper adds NO privilege ────────────────────────────────
-- Inside this transaction only: take EXECUTE on the seven bodies away from
-- authenticated. Each call below names an UNKNOWN id, so a wrapper that leaked
-- privilege would reach the body and answer P0002 instead of 42501.
DO $c$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['catalog.create_event(uuid,text,jsonb,text)','catalog.update_event(uuid,jsonb,text)',
                           'catalog.create_event_session(uuid,jsonb,text)','catalog.update_event_session(uuid,jsonb,text)',
                           'catalog.publish_event(uuid,text,text)','catalog.cancel_event(uuid,text,text)','catalog.update_venue(uuid,jsonb,text)'] LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', f);
  END LOOP;
END $c$;
SELECT is((SELECT count(*) FILTER (WHERE n.nspname = 'venue_cmd' AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))::text || '|'
                  || count(*) FILTER (WHERE n.nspname = 'catalog' AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))::text
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname IN ('venue_cmd','catalog')
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')),
  '7|0', 'C1: during the subtraction authenticated holds EXECUTE on all seven wrappers and on none of the seven bodies');
SELECT tap.login('23100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000ff', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-c-1')$$,
  '42501', 'permission denied for function create_event', 'C2: create_event — the org_owner loses the wrapper with the body (the body''s permission error, not P0002)');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-0000000000ff', '{"title":"x"}', 'ck231-c-2')$$,
  '42501', 'permission denied for function update_event', 'C3: update_event — no privilege added');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-0000000000ff', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-c-3')$$,
  '42501', 'permission denied for function create_event_session', 'C4: create_event_session — no privilege added');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-0000000000ff', '{"session_label":"x"}', 'ck231-c-4')$$,
  '42501', 'permission denied for function update_event_session', 'C5: update_event_session — no privilege added');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-0000000000ff', 'announced', 'ck231-c-5')$$,
  '42501', 'permission denied for function publish_event', 'C6: publish_event — no privilege added');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-0000000000ff', 'weather', 'ck231-c-6')$$,
  '42501', 'permission denied for function cancel_event', 'C7: cancel_event — no privilege added');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000ff', '{"name":"x"}', 'ck231-c-7')$$,
  '42501', 'permission denied for function update_venue', 'C8: update_venue — no privilege added');
SELECT tap.logout();
DO $c$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['catalog.create_event(uuid,text,jsonb,text)','catalog.update_event(uuid,jsonb,text)',
                           'catalog.create_event_session(uuid,jsonb,text)','catalog.update_event_session(uuid,jsonb,text)',
                           'catalog.publish_event(uuid,text,text)','catalog.cancel_event(uuid,text,text)','catalog.update_venue(uuid,jsonb,text)'] LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', f);
  END LOOP;
END $c$;
SELECT is((SELECT string_agg(p.proname || '=' || coalesce(p.proacl::text, 'DEFAULTED'), ';' ORDER BY p.proname)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'catalog'
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')),
  'cancel_event={postgres=X/postgres,authenticated=X/postgres};create_event={postgres=X/postgres,authenticated=X/postgres};'
  || 'create_event_session={postgres=X/postgres,authenticated=X/postgres};publish_event={postgres=X/postgres,authenticated=X/postgres};'
  || 'update_event={postgres=X/postgres,authenticated=X/postgres};update_event_session={postgres=X/postgres,authenticated=X/postgres};'
  || 'update_venue={postgres=X/postgres,authenticated=X/postgres}',
  'C9: grants restored — every target''s proacl is again exactly production''s {postgres=X/postgres,authenticated=X/postgres}');

-- ── Section L — the function ACL is a wall of its own ────────────────────────
-- Inside this transaction only: lend anon USAGE on venue_cmd, so the call gets
-- past the schema wall and meets the function ACLs (the wrapper's first; the
-- catalog body's behind it refuses with the same text — L1 pins the wrapper's).
GRANT USAGE ON SCHEMA venue_cmd TO anon;
SELECT is((SELECT has_schema_privilege('anon', 'venue_cmd', 'USAGE')::text || '|'
                  || count(*) FILTER (WHERE has_function_privilege('anon', p.oid, 'EXECUTE'))::text
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd'
              AND p.proname IN ('create_event','update_event','create_event_session','update_event_session','publish_event','cancel_event','update_venue')),
  'true|0', 'L1: with USAGE lent, anon still holds EXECUTE on none of the seven');
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue_cmd.create_event('23100000-0000-4000-8000-0000000000ff', 'x', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-l-1')$$,
  '42501', 'permission denied for function create_event', 'L2: anon past the schema wall — create_event still refused by the function ACL');
SELECT throws_ok($$SELECT venue_cmd.update_event('23100000-0000-4000-8000-0000000000ff', '{"title":"x"}', 'ck231-l-2')$$,
  '42501', 'permission denied for function update_event', 'L3: anon — update_event refused by the function ACL');
SELECT throws_ok($$SELECT venue_cmd.create_event_session('23100000-0000-4000-8000-0000000000ff', jsonb_build_object('starts_at', now() + interval '10 days'), 'ck231-l-3')$$,
  '42501', 'permission denied for function create_event_session', 'L4: anon — create_event_session refused by the function ACL');
SELECT throws_ok($$SELECT venue_cmd.update_event_session('23100000-0000-4000-8000-0000000000ff', '{"session_label":"x"}', 'ck231-l-4')$$,
  '42501', 'permission denied for function update_event_session', 'L5: anon — update_event_session refused by the function ACL');
SELECT throws_ok($$SELECT venue_cmd.publish_event('23100000-0000-4000-8000-0000000000ff', 'announced', 'ck231-l-5')$$,
  '42501', 'permission denied for function publish_event', 'L6: anon — publish_event refused by the function ACL');
SELECT throws_ok($$SELECT venue_cmd.cancel_event('23100000-0000-4000-8000-0000000000ff', 'weather', 'ck231-l-6')$$,
  '42501', 'permission denied for function cancel_event', 'L7: anon — cancel_event refused by the function ACL');
SELECT throws_ok($$SELECT venue_cmd.update_venue('23100000-0000-4000-8000-0000000000ff', '{"name":"x"}', 'ck231-l-7')$$,
  '42501', 'permission denied for function update_venue', 'L8: anon — update_venue refused by the function ACL');
SELECT tap.logout();
REVOKE USAGE ON SCHEMA venue_cmd FROM anon;
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
      WHERE n.nspname = 'venue_cmd' AND a.grantee <> n.nspowner $$,
  $$ VALUES ('authenticated:USAGE') $$,
  'L9: the lent USAGE is gone — schema venue_cmd ACL is again exactly USAGE to authenticated (161, unchanged by 164)');

SELECT * FROM finish();
ROLLBACK;
