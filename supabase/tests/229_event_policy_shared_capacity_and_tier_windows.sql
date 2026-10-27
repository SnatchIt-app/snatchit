-- ============================================================================
-- 229_event_policy_shared_capacity_and_tier_windows.sql — migration
-- 20261026100000 (registry 162).
--
-- Registry 162 / pgTAP 229 — assigned by Claude A 2026-10-26 (CONTRACTS.md §4).
-- A reviews before this leaves draft. DARK: applied nowhere; venue_api/venue_cmd
-- are not exposed; nothing here changes a flag or a config key.
--
-- Covers 162: (a) catalog.venue.timezone + catalog.set_venue_timezone;
-- (b) catalog.event.age_policy + catalog.set_event_age_policy; (c) catalog.
-- event_session.sales_capacity + catalog.set_session_sales_capacity and the
-- shared-room guard inside venue.create_inventory_batch / set_batch_capacity
-- (body-only replaces of 160's bodies); (d) venue.ticket_type.sale_starts_at /
-- sale_ends_at + venue.set_ticket_type_sale_window + venue.ticket_type_on_sale;
-- (e) A's R3 ruling — the ORG arm of the six venue.* writers/setters binds to
-- the EVENT's org (kernel.has_org_role on event.org_id, the cancel_event
-- helper), no longer the venue's CURRENT operator; (f) venue_api.ticket_types /
-- events / event_sessions re-created with the new columns appended LAST; (g) the
-- five venue_cmd wrappers and every grant decision of the package.
--
-- Fixture style: 227 (synthetic rows inserted as postgres with fixed ids, tag
-- 22900000-…, read back as each caller through tap.login, rolled back). One
-- identity per label: org_owner, org_admin, org_finance of Org A; Room V1
-- (Org A, never moved, capacity_hint NULL) venue_manager / venue_finance /
-- venue_box_office / venue_scanner / venue_marketing; Room V3 (Org B,
-- capacity_hint 40) venue_manager = the CROSS-venue manager; Room V2 = the
-- RE-OPERATED room: created under Org A, its event e5 stamped Org A, then moved
-- to Org B — its venue_manager is the FORMER-OPERATOR manager; Org B's
-- org_owner; a fan with no grant; anon. Events at V1: e1 draft (three tiers, NO
-- batch — the shared-room scenario builds them), e2 on_sale (public / hidden /
-- door_only tiers; two batches), e3 completed, e4 cancelled, e7 announced, e8
-- live. e5 at V2 (Org A's event on a room Org B now operates). e6 at V3 (Org
-- B's own draft; its session f6 already holds a 20-seat batch).
--
--   Section A  shape + ACL (NULL-safe on the chain without 162): the five
--              columns, their types/nullability/default/CHECKs; the five
--              functions with the exact EXECUTE ACL (authenticated only;
--              nothing for anon/PUBLIC/service_role), SECURITY DEFINER +
--              search_path, STABLE predicate; venue 92 / catalog 20 / venue_cmd
--              11 / five-schema 313; the five wrappers (prosecdef=false,
--              LANGUAGE sql, argument lists and result types equal the
--              targets', delegating to catalog./venue.<same name>, exact ACL);
--              the three views' columns in order with the new ones LAST,
--              options and ACL unchanged; the two column grants (timezone,
--              age_policy) present, sales_capacity withheld, E-29 unchanged; the
--              seven event-org-arm bodies, the seven E-76 conjuncts, the two
--              shared-room guards, the `for update` in every new setter
--              (every setter locks its parent row — read from the source);
--              A47/A48 (A's N1): each batch writer's FIRST row lock is the
--              session row, taken before the pool read (set_batch_capacity:
--              before the batch's `for update of b`) — regex over prosrc.
--   Section B  the R3 ruling on the re-operated room: Org B's owner (the NEW
--              operator) REFUSED on Org A's event e5 by all six 160 bodies and
--              the new setter (negative controls, FIRST — throws_ok does not
--              abort the RED run); Org A's owner (the event's own org) ACCEPTED
--              by all seven (positive controls); the E-76 venue arm, the bound
--              manager, the cross-venue manager and cross-org refusals unchanged.
--   Section T  set_venue_timezone: default, accepted names (America/New_York,
--              America/Chicago), Mars/Olympus refused, authority matrix (3
--              allowed, 7 refused 42501, anon, unauthenticated), the venue-level
--              status quo on the re-operated room (A's call), audit exactly one
--              row per change, none on noop; the *_local projections equal
--              `at time zone` and the fan reads them on a public event.
--   Section G  set_event_age_policy: three values, 'adults' refused
--              (invalid_input before the CHECK; the CHECK itself at the table),
--              NULL clears, noop, terminal, authority matrix, audit before/after,
--              the fan reads age_policy of a published event through venue_api.
--   Section S  SHARED CAPACITY (the RED->GREEN scenario): pool 50 — 30 + 30
--              refused session_capacity_exceeded; 30 + 20 ok; raising the 20 to
--              21 refused; a comp batch counts; lowering the pool to 49 refused
--              below_allocated; NULL = unlimited (160 behaviour); capacity_hint
--              40 — 50 refused above_venue_capacity, 40 ok, 41 refused;
--              authority matrix; terminal; audit.
--   Section W  windows: starts inclusive, ends exclusive, NULL open on either
--              side, NULL/NULL clears, ends <= starts refused (setter and CHECK),
--              hidden never on sale, draft/announced/completed/cancelled never,
--              on_sale/live yes, door_only yes, unknown id false; authority
--              matrix; audit. W50/W51: a window is a pair of absolute instants —
--              the caller's session TimeZone changes neither what the setter
--              stores for an offset-qualified literal nor the predicate's verdict
--              (UTC / America/New_York / Pacific/Kiritimati); the venue timezone
--              governs display only (T27/T31). naive timestamp literals are
--              interpreted in the caller's session TimeZone (PostgREST: UTC) —
--              clients MUST send ISO-8601 with an offset, converting the venue's
--              local wall-clock using catalog.venue.timezone.
--   Section P  176 interplay: a PUBLIC tier of a DRAFT event is invisible to a
--              fan through venue_api; the on-sale public tier is visible with
--              on_sale_now; hidden/door_only stay invisible.
--   Section C  venue_cmd: each wrapper yields the definer's result; refusals
--              propagate unchanged; anon at the schema wall; no auth.uid().
--
-- Expected on 159+176+160+161 WITHOUT 162 (RED, predicted before the first run;
-- the reconciliation against the actual run is in the evidence dir
-- EVIDENCE-162.md §1): A1-A36, A40, A43-A48 fail (columns, functions, wrappers,
-- counts, view columns, grants and body text absent — 43; A47/A48 added for A's
-- N1: 160's two batch writers take no session lock); A37-A39, A41, A42
-- pass (5, by vacuity: the three views keep their options/ACL, venue_api still
-- has no function, sales_capacity cannot be selected because it does not exist,
-- E-29 unchanged). Section B negatives B1-B7: B1-B6 fail (160's org arm ACCEPTS
-- Org B's owner on e5 — throws_ok reports not ok without aborting), B7 (the new
-- setter) fails with 42883 inside throws_ok (not ok, no abort). Then B8 — the
-- first positive `is()` call — raises 42501 on 160 (Org A's owner is refused by
-- the old arm) and aborts the transaction, so B9 onward is never emitted.
-- Predicted RED run: 55 emitted = 50 not ok + 5 ok; plan unmet (was 53 = 48 + 5
-- before A47/A48).
-- ============================================================================
BEGIN;
SELECT plan(235);

CREATE TABLE tap.memo_229 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store229(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_229 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch229(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_229 WHERE k = $1 $m$;
-- definer read of the raw per-session allocation (E-29: no client role may SELECT capacity)
CREATE FUNCTION tap._alloc229(s uuid) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT coalesce(sum(capacity), 0)::integer FROM venue.inventory_batch WHERE event_session_id = s $m$;
-- definer read of the session's pool (sales_capacity is withheld from every client role — 229 A41 pins that; this stands in for a postgres read inside a logged-in step)
-- plpgsql, not sql: a sql body is validated at CREATE time and would abort the whole file on the chain without 162 (no RED run at all).
CREATE FUNCTION tap._pool229(s uuid) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS
$m$ BEGIN RETURN (SELECT sales_capacity FROM catalog.event_session WHERE session_id = s); END $m$;
GRANT EXECUTE ON FUNCTION tap._store229(text, text), tap._fetch229(text), tap._alloc229(uuid), tap._pool229(uuid) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('22900000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.229@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.a.229@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.229@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.229@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.v1.229@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'box.v1.229@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000114', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v1.229@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000115', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v1.229@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.229@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v3.cross.229@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.229@test.local',       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22900000-0000-4000-8000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.b.229@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('22900000-0000-4000-8000-00000000000a', 'Org A 229', 'Org A 229', 'active'),
  ('22900000-0000-4000-8000-00000000000b', 'Org B 229', 'Org B 229', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('22900000-0000-4000-8000-00000000000a', '22900000-0000-4000-8000-000000000101', 'org_owner'),
  ('22900000-0000-4000-8000-00000000000a', '22900000-0000-4000-8000-000000000102', 'org_admin'),
  ('22900000-0000-4000-8000-00000000000a', '22900000-0000-4000-8000-000000000103', 'org_finance'),
  ('22900000-0000-4000-8000-00000000000b', '22900000-0000-4000-8000-000000000201', 'org_owner');
-- V2 is created under Org A (its event e5 is stamped Org A below), then moved. V3 carries capacity_hint 40.
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status, capacity_hint) VALUES
  ('22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'Room V1 229', 'wynwood',  'approved', NULL),
  ('22900000-0000-4000-8000-0000000000a2', '22900000-0000-4000-8000-00000000000a', 'Room V2 229', 'brickell', 'approved', NULL),
  ('22900000-0000-4000-8000-0000000000b3', '22900000-0000-4000-8000-00000000000b', 'Room V3 229', 'midtown',  'approved', 40);
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-000000000111', 'venue_manager'),
  ('22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-000000000112', 'venue_finance'),
  ('22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-000000000113', 'venue_box_office'),
  ('22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-000000000115', 'venue_marketing'),
  ('22900000-0000-4000-8000-0000000000a2', '22900000-0000-4000-8000-000000000121', 'venue_manager'),
  ('22900000-0000-4000-8000-0000000000b3', '22900000-0000-4000-8000-000000000131', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('22900000-0000-4000-8000-0000000000e1', '22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'V1 draft 229',     'draft'),
  ('22900000-0000-4000-8000-0000000000e2', '22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'V1 on sale 229',   'on_sale'),
  ('22900000-0000-4000-8000-0000000000e3', '22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'V1 completed 229', 'completed'),
  ('22900000-0000-4000-8000-0000000000e4', '22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'V1 cancelled 229', 'cancelled'),
  ('22900000-0000-4000-8000-0000000000e5', '22900000-0000-4000-8000-0000000000a2', '22900000-0000-4000-8000-00000000000a', 'V2 (A event) 229', 'on_sale'),
  ('22900000-0000-4000-8000-0000000000e6', '22900000-0000-4000-8000-0000000000b3', '22900000-0000-4000-8000-00000000000b', 'V3 (B event) 229', 'draft'),
  ('22900000-0000-4000-8000-0000000000e7', '22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'V1 announced 229', 'announced'),
  ('22900000-0000-4000-8000-0000000000e8', '22900000-0000-4000-8000-0000000000a1', '22900000-0000-4000-8000-00000000000a', 'V1 live 229',      'live');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, ends_at, doors_at, status) VALUES
  ('22900000-0000-4000-8000-0000000000f1', '22900000-0000-4000-8000-0000000000e1', now() + interval '30 days', NULL, NULL, 'scheduled'),
  ('22900000-0000-4000-8000-0000000000f2', '22900000-0000-4000-8000-0000000000e2', '2026-11-20 02:00:00+00', '2026-11-20 06:00:00+00', '2026-11-20 01:00:00+00', 'scheduled'),
  ('22900000-0000-4000-8000-0000000000f3', '22900000-0000-4000-8000-0000000000e3', now() - interval '3 days',  NULL, NULL, 'completed'),
  ('22900000-0000-4000-8000-0000000000f4', '22900000-0000-4000-8000-0000000000e4', now() + interval '5 days',  NULL, NULL, 'cancelled'),
  ('22900000-0000-4000-8000-0000000000f5', '22900000-0000-4000-8000-0000000000e5', now() + interval '7 days',  NULL, NULL, 'scheduled'),
  ('22900000-0000-4000-8000-0000000000f6', '22900000-0000-4000-8000-0000000000e6', now() + interval '9 days',  NULL, NULL, 'scheduled'),
  ('22900000-0000-4000-8000-0000000000f7', '22900000-0000-4000-8000-0000000000e7', now() + interval '11 days', NULL, NULL, 'scheduled'),
  ('22900000-0000-4000-8000-0000000000f8', '22900000-0000-4000-8000-0000000000e8', now() + interval '1 hour',  NULL, NULL, 'live');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('22900000-0000-4000-8000-000000000011', '22900000-0000-4000-8000-0000000000e1', 'admission', 'GA draft 229',       2500, 'public'),
  ('22900000-0000-4000-8000-000000000012', '22900000-0000-4000-8000-0000000000e1', 'admission', 'Second draft 229',   2000, 'hidden'),
  ('22900000-0000-4000-8000-000000000013', '22900000-0000-4000-8000-0000000000e1', 'admission', 'Comp draft 229',     1000, 'hidden'),
  ('22900000-0000-4000-8000-000000000021', '22900000-0000-4000-8000-0000000000e2', 'admission', 'GA on sale 229',     3000, 'public'),
  ('22900000-0000-4000-8000-000000000022', '22900000-0000-4000-8000-0000000000e2', 'admission', 'Hidden on sale 229', 1800, 'hidden'),
  ('22900000-0000-4000-8000-000000000023', '22900000-0000-4000-8000-0000000000e2', 'table',     'Door table 229',     1500, 'door_only'),
  ('22900000-0000-4000-8000-000000000031', '22900000-0000-4000-8000-0000000000e3', 'admission', 'GA completed 229',   2700, 'public'),
  ('22900000-0000-4000-8000-000000000041', '22900000-0000-4000-8000-0000000000e4', 'admission', 'GA cancelled 229',   2800, 'public'),
  ('22900000-0000-4000-8000-000000000051', '22900000-0000-4000-8000-0000000000e5', 'admission', 'GA V2 229',          4000, 'public'),
  ('22900000-0000-4000-8000-000000000061', '22900000-0000-4000-8000-0000000000e6', 'admission', 'GA V3 229',          3300, 'public'),
  ('22900000-0000-4000-8000-000000000071', '22900000-0000-4000-8000-0000000000e7', 'admission', 'GA announced 229',   3100, 'public'),
  ('22900000-0000-4000-8000-000000000081', '22900000-0000-4000-8000-0000000000e8', 'admission', 'GA live 229',        3200, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('22900000-0000-4000-8000-0000000000c2', '22900000-0000-4000-8000-000000000021', '22900000-0000-4000-8000-0000000000f2', 'public_sale', 300, 6, 120),
  ('22900000-0000-4000-8000-0000000000c3', '22900000-0000-4000-8000-000000000023', '22900000-0000-4000-8000-0000000000f2', 'door',        100, 0, 100),
  ('22900000-0000-4000-8000-0000000000c4', '22900000-0000-4000-8000-000000000031', '22900000-0000-4000-8000-0000000000f3', 'public_sale', 150, 0, 150),
  ('22900000-0000-4000-8000-0000000000c5', '22900000-0000-4000-8000-000000000041', '22900000-0000-4000-8000-0000000000f4', 'public_sale', 150, 0, 0),
  ('22900000-0000-4000-8000-0000000000c6', '22900000-0000-4000-8000-000000000051', '22900000-0000-4000-8000-0000000000f5', 'public_sale', 200, 0, 15),
  ('22900000-0000-4000-8000-0000000000c7', '22900000-0000-4000-8000-000000000061', '22900000-0000-4000-8000-0000000000f6', 'public_sale', 20, 0, 0);
-- THE RE-OPERATION: Room V2 moves from Org A to Org B. e5 keeps org_id = A (the tenancy move does not re-stamp).
UPDATE catalog.venue SET org_id = '22900000-0000-4000-8000-00000000000b'
 WHERE venue_id = '22900000-0000-4000-8000-0000000000a2';

-- ── Section A — shape + ACL (NULL-safe) ──────────────────────────────────────
SELECT col_type_is('catalog'::name, 'venue'::name, 'timezone'::name, 'text', 'A1: catalog.venue.timezone is text');
SELECT col_not_null('catalog'::name, 'venue'::name, 'timezone'::name, 'A2: timezone is NOT NULL');
SELECT col_default_is('catalog'::name, 'venue'::name, 'timezone'::name, 'America/New_York', 'A3: timezone defaults to America/New_York (owner decision open; reversible)');
SELECT col_type_is('catalog'::name, 'event'::name, 'age_policy'::name, 'text', 'A4: catalog.event.age_policy is text');
SELECT col_is_null('catalog'::name, 'event'::name, 'age_policy'::name, 'A5: age_policy is nullable (NULL = not specified)');
SELECT throws_ok($$UPDATE catalog.event SET age_policy = 'adults' WHERE event_id = '22900000-0000-4000-8000-0000000000e1'$$,
  '23514', NULL, 'A6: CHECK — age_policy ''adults'' is refused at the table');
SELECT col_type_is('catalog'::name, 'event_session'::name, 'sales_capacity'::name, 'integer', 'A7: catalog.event_session.sales_capacity is integer');
SELECT col_is_null('catalog'::name, 'event_session'::name, 'sales_capacity'::name, 'A8: sales_capacity is nullable (NULL = unlimited)');
SELECT throws_ok($$UPDATE catalog.event_session SET sales_capacity = 0 WHERE session_id = '22900000-0000-4000-8000-0000000000f1'$$,
  '23514', NULL, 'A9: CHECK — sales_capacity 0 is refused at the table (> 0)');
SELECT col_type_is('venue'::name, 'ticket_type'::name, 'sale_starts_at'::name, 'timestamp with time zone', 'A10: venue.ticket_type.sale_starts_at is timestamptz');
SELECT col_type_is('venue'::name, 'ticket_type'::name, 'sale_ends_at'::name, 'timestamp with time zone', 'A11: venue.ticket_type.sale_ends_at is timestamptz');
SELECT throws_ok($$UPDATE venue.ticket_type SET sale_starts_at = '2036-11-02 00:00+00', sale_ends_at = '2036-11-01 00:00+00' WHERE ticket_type_id = '22900000-0000-4000-8000-000000000011'$$,
  '23514', NULL, 'A12: CHECK — sale_ends_at before sale_starts_at is refused at the table');
SELECT throws_ok($$UPDATE venue.ticket_type SET sale_starts_at = '2036-11-01 00:00+00', sale_ends_at = '2036-11-01 00:00+00' WHERE ticket_type_id = '22900000-0000-4000-8000-000000000011'$$,
  '23514', NULL, 'A13: CHECK — sale_ends_at = sale_starts_at is refused (strictly after)');
SELECT has_function('catalog'::name, 'set_venue_timezone'::name, ARRAY['uuid','text','text','text']::name[],
  'A14: catalog.set_venue_timezone(uuid, text, text, text) exists');
SELECT has_function('catalog'::name, 'set_event_age_policy'::name, ARRAY['uuid','text','text','text']::name[],
  'A15: catalog.set_event_age_policy(uuid, text, text, text) exists');
SELECT has_function('catalog'::name, 'set_session_sales_capacity'::name, ARRAY['uuid','integer','text','text']::name[],
  'A16: catalog.set_session_sales_capacity(uuid, integer, text, text) exists');
SELECT has_function('venue'::name, 'set_ticket_type_sale_window'::name, ARRAY['uuid','timestamp with time zone','timestamp with time zone','text','text']::name[],
  'A17: venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text) exists');
SELECT has_function('venue'::name, 'ticket_type_on_sale'::name, ARRAY['uuid','timestamp with time zone']::name[],
  'A18: venue.ticket_type_on_sale(uuid, timestamptz) exists');
-- the exact EXECUTE surface of the five new functions (CI's grant manifest reads public only; this is the gate)
SELECT set_eq(
  $$ SELECT n.nspname || '.' || p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE ((n.nspname = 'catalog' AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity'))
          OR (n.nspname = 'venue'   AND p.proname IN ('set_ticket_type_sale_window','ticket_type_on_sale')))
        AND a.grantee <> p.proowner $$,
  $$ VALUES ('catalog.set_venue_timezone:authenticated:EXECUTE'), ('catalog.set_event_age_policy:authenticated:EXECUTE'),
            ('catalog.set_session_sales_capacity:authenticated:EXECUTE'), ('venue.set_ticket_type_sale_window:authenticated:EXECUTE'),
            ('venue.ticket_type_on_sale:authenticated:EXECUTE') $$,
  'A19: the five new functions grant EXECUTE to authenticated and to NOBODY else (no PUBLIC, anon, service_role)');
-- to_regprocedure (not a ::regprocedure cast): on the chain WITHOUT 162 this reads `not ok` instead of 42883.
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('catalog.set_venue_timezone(uuid, text, text, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('catalog.set_event_age_policy(uuid, text, text, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('catalog.set_session_sales_capacity(uuid, integer, text, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.ticket_type_on_sale(uuid, timestamptz)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.ticket_type_on_sale(uuid, timestamptz)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('catalog.set_venue_timezone(uuid, text, text, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('catalog.set_event_age_policy(uuid, text, text, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('catalog.set_session_sales_capacity(uuid, integer, text, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.ticket_type_on_sale(uuid, timestamptz)'), 'EXECUTE'), false),
  'A20: anon (and service_role on the predicate) have no EXECUTE on any of the five; authenticated has it on all five');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE ((n.nspname = 'catalog' AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity'))
                OR (n.nspname = 'venue'   AND p.proname IN ('set_ticket_type_sale_window','ticket_type_on_sale')))
              AND p.prosecdef AND p.proconfig::text LIKE '%search_path=%'), 5,
  'A21: all five are SECURITY DEFINER with a pinned search_path (066 invariant)');
SELECT is((SELECT string_agg(p.proname || '=' || p.provolatile::text, ',' ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE ((n.nspname = 'catalog' AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity'))
                OR (n.nspname = 'venue'   AND p.proname IN ('set_ticket_type_sale_window','ticket_type_on_sale')))),
  'set_event_age_policy=v,set_session_sales_capacity=v,set_ticket_type_sale_window=v,set_venue_timezone=v,ticket_type_on_sale=s',
  'A22: ticket_type_on_sale is STABLE (a read); the four setters are VOLATILE');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue'), 96,
  -- 2026-10-26 (registry 163): 92 -> 96 (+get_session_scan_counters, list_session_scan_counters, record_scan_staff, filter_staff_scan_meta; 94 if 163's PART B is dropped).
  'A23: venue holds NINETY-SIX functions — 90 (160) + set_ticket_type_sale_window + ticket_type_on_sale + 163''s four (144 A15 / 145 A4 / 148 B5 / 179 A8 / 180 A5 / 227 A12 / 230 A19 move with it)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'catalog'), 20,
  'A24: catalog holds TWENTY functions — 17 + set_venue_timezone, set_event_age_policy, set_session_sales_capacity (154 A10 moves with it)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname IN ('kernel','venue','catalog','market','notify')), 317,
  -- 2026-10-26 (registry 163): 313 -> 317 (+4 venue: get_session_scan_counters, list_session_scan_counters, record_scan_staff, filter_staff_scan_meta; 315 if 163's PART B is dropped).
  'A25: five-schema routine census 317 — 308 post-160 + 162''s five + 163''s four (148 B2 / 156 A20 / 157 A46 / 179 A9 / 180 A6 move with it)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_cmd'), 21,
  -- 2026-10-27 (registry 164): 14 -> 21 (+164's seven catalog event/session/venue wrappers; pgTAP 231).
  -- 2026-10-26 (registry 163): 11 -> 14 (+get_session_scan_counters, record_scan, validate_ticket_online; 12 if 163's PART B is dropped).
  'A26: venue_cmd holds TWENTY-ONE functions — 161''s six + 162''s five + 163''s three + 164''s seven wrappers (228 A2/A3 move with it)');
SELECT set_eq(
  $$ SELECT p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_cmd'
        AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity','set_ticket_type_sale_window','ticket_type_on_sale') $$,
  $$ VALUES ('set_venue_timezone(uuid, text, text, text)'), ('set_event_age_policy(uuid, text, text, text)'),
            ('set_session_sales_capacity(uuid, integer, text, text)'),
            ('set_ticket_type_sale_window(uuid, timestamp with time zone, timestamp with time zone, text, text)'),
            ('ticket_type_on_sale(uuid, timestamp with time zone)') $$,
  'A27: exactly these five wrapper signatures in venue_cmd');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd'
              AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity','set_ticket_type_sale_window','ticket_type_on_sale')
              AND NOT p.prosecdef AND l.lanname = 'sql' AND p.proconfig::text LIKE '%search_path=%'), 5,
  'A28: the five wrappers are SECURITY INVOKER (prosecdef = false, counted positively), LANGUAGE sql, search_path pinned');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd'
        AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity','set_ticket_type_sale_window','ticket_type_on_sale')
        AND a.grantee <> p.proowner $$,
  $$ VALUES ('set_venue_timezone:authenticated:EXECUTE'), ('set_event_age_policy:authenticated:EXECUTE'),
            ('set_session_sales_capacity:authenticated:EXECUTE'), ('set_ticket_type_sale_window:authenticated:EXECUTE'),
            ('ticket_type_on_sale:authenticated:EXECUTE') $$,
  'A29: the wrapper ACL matrix is exactly EXECUTE to authenticated on each of the five (no PUBLIC, anon, service_role; no DEFAULTED proacl)');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            JOIN pg_proc t ON t.proname = w.proname AND t.pronamespace IN ('venue'::regnamespace, 'catalog'::regnamespace)
            WHERE n.nspname = 'venue_cmd'
              AND w.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity','set_ticket_type_sale_window','ticket_type_on_sale')
              AND pg_get_function_arguments(w.oid) = pg_get_function_arguments(t.oid)
              AND pg_get_function_result(w.oid) = pg_get_function_result(t.oid)), 5,
  'A30: each wrapper''s argument list (names, types, defaults) and result type equal its catalog./venue. target''s');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            WHERE n.nspname = 'venue_cmd'
              AND ((w.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity') AND w.prosrc LIKE '%catalog.' || w.proname || '(%')
                OR (w.proname IN ('set_ticket_type_sale_window','ticket_type_on_sale') AND w.prosrc LIKE '%venue.' || w.proname || '(%'))), 5,
  'A31: each wrapper delegates to <target schema>.<same name>');
SELECT is((SELECT string_agg(p.proname || '=' || p.provolatile::text, ',' ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd'
              AND p.proname IN ('set_venue_timezone','set_event_age_policy','set_session_sales_capacity','set_ticket_type_sale_window','ticket_type_on_sale')),
  'set_event_age_policy=v,set_session_sales_capacity=v,set_ticket_type_sale_window=v,set_venue_timezone=v,ticket_type_on_sale=s',
  'A32: the predicate wrapper is STABLE and the four command wrappers are VOLATILE');
SELECT is((SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = 'venue_api.ticket_types'::regclass AND a.attnum > 0 AND NOT a.attisdropped),
  'ticket_type_id,event_id,kind,name,price_minor,currency,visibility,created_at,updated_at,display_rank,sale_starts_at,sale_ends_at,on_sale_now',
  'A33: venue_api.ticket_types projects 160''s ten columns in order with sale_starts_at, sale_ends_at, on_sale_now appended LAST');
SELECT is((SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = 'venue_api.events'::regclass AND a.attnum > 0 AND NOT a.attisdropped),
  'event_id,venue_id,org_id,title,status,created_at,updated_at,description,age_policy,timezone',
  'A34: venue_api.events projects 159''s eight columns in order (description at 8, 159 rev. 2026-10-26) with age_policy, timezone appended LAST');
SELECT is((SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = 'venue_api.event_sessions'::regclass AND a.attnum > 0 AND NOT a.attisdropped),
  'session_id,event_id,session_label,starts_at,ends_at,doors_at,door_open_at,status,created_at,updated_at,timezone,starts_at_local,ends_at_local,doors_at_local',
  'A35: venue_api.event_sessions projects 159''s ten columns in order with timezone, starts_at_local, ends_at_local, doors_at_local appended LAST');
SELECT is((SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = 'venue_api.event_sessions'::regclass AND a.attnum > 10 AND NOT a.attisdropped),
  'timezone:text,starts_at_local:text,ends_at_local:text,doors_at_local:text',
  'A36: the four appended session columns are text (to_char(… at time zone v.timezone, ''YYYY-MM-DD HH24:MI''))');
SELECT is((SELECT count(*)::int FROM pg_class c CROSS JOIN LATERAL unnest(c.reloptions) o
            WHERE c.oid IN ('venue_api.ticket_types'::regclass, 'venue_api.events'::regclass, 'venue_api.event_sessions'::regclass)
              AND o IN ('security_invoker=true','security_barrier=true')), 6,
  'A37: the three re-created views are still security_invoker AND security_barrier');
SELECT set_eq(
  $$ SELECT c.relname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE c.oid IN ('venue_api.ticket_types'::regclass, 'venue_api.events'::regclass, 'venue_api.event_sessions'::regclass) AND a.grantee <> c.relowner $$,
  $$ VALUES ('ticket_types:authenticated:SELECT'), ('events:authenticated:SELECT'), ('event_sessions:authenticated:SELECT') $$,
  'A38: the three views'' ACLs are still exactly SELECT to authenticated');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_api'), 0,
  'A39: venue_api still holds no function (226 A3 stays true: the predicate lives in venue, the view only calls it)');
-- column grants (CASE guards the chain without 162: has_column_privilege raises on a missing column)
SELECT ok((CASE WHEN EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.venue'::regclass AND attname = 'timezone' AND NOT attisdropped)
                THEN has_column_privilege('authenticated', 'catalog.venue', 'timezone', 'SELECT') AND has_column_privilege('anon', 'catalog.venue', 'timezone', 'SELECT')
                ELSE false END)
      AND (CASE WHEN EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.event'::regclass AND attname = 'age_policy' AND NOT attisdropped)
                THEN has_column_privilege('authenticated', 'catalog.event', 'age_policy', 'SELECT') AND has_column_privilege('anon', 'catalog.event', 'age_policy', 'SELECT')
                ELSE false END),
  'A40: anon and authenticated may SELECT catalog.venue.timezone and catalog.event.age_policy (the 078 column lists + one column each)');
SELECT ok(NOT (CASE WHEN EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'catalog.event_session'::regclass AND attname = 'sales_capacity' AND NOT attisdropped)
                    THEN has_column_privilege('authenticated', 'catalog.event_session', 'sales_capacity', 'SELECT') OR has_column_privilege('anon', 'catalog.event_session', 'sales_capacity', 'SELECT')
                    ELSE false END),
  'A41: catalog.event_session.sales_capacity is NOT client-selectable (E-29 posture: a capacity figure; staff see it in the setter''s result)');
SELECT ok(NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'capacity', 'SELECT')
      AND NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'held', 'SELECT')
      AND NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'sold', 'SELECT'),
  'A42: E-29 unchanged — capacity/held/sold are not client-selectable (162 adds NO column grant on inventory_batch)');
-- body text pins (R3 org arm, E-76 venue arm, the shared-room guard, the parent-row lock)
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN (to_regprocedure('venue.create_ticket_type(uuid, text, text, integer, text, text)'),
                            to_regprocedure('venue.set_ticket_type_price(uuid, integer, text, text)'),
                            to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'),
                            to_regprocedure('venue.set_batch_capacity(uuid, integer, text, text)'),
                            to_regprocedure('venue.set_ticket_type_visibility(uuid, text, text, text)'),
                            to_regprocedure('venue.set_ticket_type_rank(uuid, smallint, text)'),
                            to_regprocedure('venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)'))
              AND p.prosrc LIKE $$%kernel.has_org_role(v_org_id, array['org_owner','org_admin'])%$$
              AND p.prosrc NOT LIKE '%has_org_role_over_venue%'), 7,
  'A43: R3 — the six replaced venue.* bodies and the new setter bind the ORG arm to the EVENT''s org (kernel.has_org_role on v_org_id; no has_org_role_over_venue left)');
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN (to_regprocedure('venue.create_ticket_type(uuid, text, text, integer, text, text)'),
                            to_regprocedure('venue.set_ticket_type_price(uuid, integer, text, text)'),
                            to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'),
                            to_regprocedure('venue.set_batch_capacity(uuid, integer, text, text)'),
                            to_regprocedure('venue.set_ticket_type_visibility(uuid, text, text, text)'),
                            to_regprocedure('venue.set_ticket_type_rank(uuid, smallint, text)'),
                            to_regprocedure('venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)'),
                            to_regprocedure('catalog.set_event_age_policy(uuid, text, text, text)'),
                            to_regprocedure('catalog.set_session_sales_capacity(uuid, integer, text, text)'))
              AND p.prosrc LIKE '%and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id)%'), 9,
  'A44: E-76 — all seven venue.* bodies and the two catalog event/session setters keep the current-operator conjunct on the venue arm');
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN (to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'),
                            to_regprocedure('venue.set_batch_capacity(uuid, integer, text, text)'))
              AND p.prosrc LIKE '%session_capacity_exceeded%'
              AND p.prosrc LIKE '%from catalog.event_session s%for update%'), 2,
  'A45: both batch writers lock the session row (for update) and carry the session_capacity_exceeded guard');
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN (to_regprocedure('catalog.set_venue_timezone(uuid, text, text, text)'),
                            to_regprocedure('catalog.set_event_age_policy(uuid, text, text, text)'),
                            to_regprocedure('catalog.set_session_sales_capacity(uuid, integer, text, text)'),
                            to_regprocedure('venue.set_ticket_type_sale_window(uuid, timestamptz, timestamptz, text, text)'))
              AND p.prosrc LIKE '%for update%'), 4,
  'A46: every new setter locks its parent row (for update) before it writes — read from the function source');
-- A47/A48 (A's N1, review of #168, 2026-10-26): A45's LIKE '%from catalog.event_session s%for update%' is also
-- satisfied by set_batch_capacity's LATER batch lock ('for update of b'), so a body with the session-row lock
-- deleted stayed green on 229/227 (with 162's post-flight md5 check switched off) while A's two-connection race
-- resized 20 -> 40 beside a committed 20 and booked 60 into a 50 pool; on create_inventory_batch only A45's text
-- caught it (70 > 50). These two pins read the real statements: each writer's FIRST row lock is the session row
-- (catalog.event_session ... for update — bare, not a batch lock), taken BEFORE the pool is summed and, in
-- set_batch_capacity, BEFORE the batch's 'for update of b' (rank 1 then rank 2, the cancel_event order).
-- Race evidence (the behaviour these text pins stand for): D's two-connection race with the lock in place —
-- the second connection blocks on the session row, then is refused session_capacity_exceeded (planning/
-- 2026-10-26-launch/D/s2-policy/race/: run_race.sh, round1_20_20.log, round2_10_10.log); A's review race with
-- each lock removed (create 70 > 50, resize 60 > 50 — A's review evidence race/race.log).
SELECT ok(coalesce((SELECT p.prosrc ~* $re$from\s+catalog\.event_session\s+s\s+where\s+s\.session_id\s*=\s*p_session_id\s+for\s+update\s*;.*from\s+venue\.inventory_batch\s+b\s+where\s+b\.event_session_id\s*=\s*p_session_id\s*;.*insert\s+into\s+venue\.inventory_batch\s*\($re$
                      AND split_part(lower(p.prosrc), 'for update', 1) ~ $re$from\s+catalog\.event_session\s+s\s+where\s+s\.session_id\s*=\s*p_session_id\s+\Z$re$
                      FROM pg_proc p WHERE p.oid = to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)')), false),
  'A47: N1 — create_inventory_batch: its first row lock is the SESSION row (from catalog.event_session s where s.session_id = p_session_id for update), taken before the pool is summed and the batch inserted');
SELECT ok(coalesce((SELECT p.prosrc ~* $re$from\s+catalog\.event_session\s+s\s+where\s+s\.session_id\s*=\s*\(select\s+b\.event_session_id\s+from\s+venue\.inventory_batch\s+b\s+where\s+b\.batch_id\s*=\s*p_batch_id\)\s+for\s+update\s*;.*from\s+venue\.inventory_batch\s+b\s+join\s+venue\.ticket_type\s+tt[^;]*\sfor\s+update\s+of\s+b\s*;.*from\s+venue\.inventory_batch\s+b\s+where\s+b\.event_session_id\s*=\s*v_session\s+and\s+b\.batch_id\s*<>\s*p_batch_id\s*;$re$
                      AND split_part(lower(p.prosrc), 'for update', 1) ~ $re$from\s+catalog\.event_session\s+s\s+where\s+s\.session_id\s*=\s*\(select\s+b\.event_session_id\s+from\s+venue\.inventory_batch\s+b\s+where\s+b\.batch_id\s*=\s*p_batch_id\)\s+\Z$re$
                      FROM pg_proc p WHERE p.oid = to_regprocedure('venue.set_batch_capacity(uuid, integer, text, text)')), false),
  'A48: N1 — set_batch_capacity: its first row lock is the SESSION row (catalog.event_session ... for update), BEFORE the batch''s for update of b, and the pool is summed after both');

-- ── Section B — R3: the org arm binds to the EVENT's org (re-operated Room V2: venue B, event e5 A) ──
-- NEGATIVE controls first (throws_ok does not abort the RED run): Org B's owner, the NEW operator, on Org A's event.
SELECT tap.login('22900000-0000-4000-8000-000000000201');
SELECT throws_ok($$SELECT venue.set_ticket_type_price('22900000-0000-4000-8000-000000000051', 4300, 'demand', 'ck229-b-1')$$,
  '42501', NULL, 'B1: R3 — Org B''s owner (new operator of Room V2) is REFUSED set_ticket_type_price on Org A''s event e5');
SELECT throws_ok($$SELECT venue.create_ticket_type('22900000-0000-4000-8000-0000000000e5', 'admission', 'B GA', 4100, 'public', 'ck229-b-2')$$,
  '42501', NULL, 'B2: R3 — Org B''s owner is REFUSED create_ticket_type on e5');
SELECT throws_ok($$SELECT venue.create_inventory_batch('22900000-0000-4000-8000-000000000051', '22900000-0000-4000-8000-0000000000f5', 'presale', 10, 0, 'ck229-b-3')$$,
  '42501', NULL, 'B3: R3 — Org B''s owner is REFUSED create_inventory_batch on e5');
SELECT throws_ok($$SELECT venue.set_batch_capacity('22900000-0000-4000-8000-0000000000c6', 250, 'expansion', 'ck229-b-4')$$,
  '42501', NULL, 'B4: R3 — Org B''s owner is REFUSED set_batch_capacity on e5''s batch');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22900000-0000-4000-8000-000000000051', 'hidden', 'x', 'ck229-b-5')$$,
  '42501', NULL, 'B5: R3 — Org B''s owner is REFUSED set_ticket_type_visibility on e5');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22900000-0000-4000-8000-000000000051', 1::smallint, 'ck229-b-6')$$,
  '42501', NULL, 'B6: R3 — Org B''s owner is REFUSED set_ticket_type_rank on e5');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000051', NULL, '2036-01-01 00:00+00', 'x', 'ck229-b-7')$$,
  '42501', NULL, 'B7: R3 — Org B''s owner is REFUSED set_ticket_type_sale_window on e5');
SELECT tap.logout();
-- POSITIVE controls: Org A's owner — the EVENT's own org — on e5, although Room V2 now belongs to Org B.
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is((venue.set_ticket_type_price('22900000-0000-4000-8000-000000000051', 4200, 'demand', 'ck229-b-8') ->> 'price_minor'), '4200',
  'B8: R3 — the event''s OWN org_owner (A) is ACCEPTED by set_ticket_type_price on e5 (227 B9 flips with this)');
SELECT is((venue.create_ticket_type('22900000-0000-4000-8000-0000000000e5', 'admission', 'A GA at V2', 4100, 'hidden', 'ck229-b-9') ->> 'status'), 'ok',
  'B9: R3 — Org A''s owner is ACCEPTED by create_ticket_type on e5');
SELECT tap._store229('b10_batch',
  (venue.create_inventory_batch('22900000-0000-4000-8000-000000000051', '22900000-0000-4000-8000-0000000000f5', 'presale', 10, 0, 'ck229-b-10') ->> 'batch_id'));
SELECT ok((SELECT count(*) = 1 FROM venue.inventory_batch WHERE batch_id = tap._fetch229('b10_batch')::uuid),
  'B10: R3 — Org A''s owner is ACCEPTED by create_inventory_batch on e5 (a 10-seat presale batch; f5 has no pool)');
SELECT is((venue.set_batch_capacity('22900000-0000-4000-8000-0000000000c6', 250, 'expansion', 'ck229-b-11') ->> 'capacity'), '250',
  'B11: R3 — Org A''s owner is ACCEPTED by set_batch_capacity on e5''s batch');
SELECT is((venue.set_ticket_type_visibility('22900000-0000-4000-8000-000000000051', 'door_only', 'door_list', 'ck229-b-12') ->> 'visibility'), 'door_only',
  'B12: R3 — Org A''s owner is ACCEPTED by set_ticket_type_visibility on e5');
SELECT is((venue.set_ticket_type_rank('22900000-0000-4000-8000-000000000051', 3::smallint, 'ck229-b-13') ->> 'display_rank'), '3',
  'B13: R3 — Org A''s owner is ACCEPTED by set_ticket_type_rank on e5');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000051', NULL, '2036-01-01 00:00+00', 'close_date', 'ck229-b-14') ->> 'status'), 'ok',
  'B14: R3 — Org A''s owner is ACCEPTED by set_ticket_type_sale_window on e5');
SELECT tap.logout();
-- the E-76 venue arm, the bound manager, the cross-venue manager and the cross-org refusal are unchanged
SELECT tap.login('22900000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT venue.create_ticket_type('22900000-0000-4000-8000-0000000000e5', 'admission', 'Former GA', 4100, 'public', 'ck229-b-15')$$,
  '42501', NULL, 'B15: E-76 — the FORMER-OPERATOR manager (Room V2, now Org B) is still refused on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000111');
SELECT is((venue.create_ticket_type('22900000-0000-4000-8000-0000000000e1', 'admission', 'B16 tier 229', 2000, 'hidden', 'ck229-b-16') ->> 'status'), 'ok',
  'B16: the BOUND venue_manager of Room V1 (Org A, never moved) is still accepted on Org A''s event e1');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT venue.create_ticket_type('22900000-0000-4000-8000-0000000000e1', 'admission', 'Cross GA', 2000, 'public', 'ck229-b-17')$$,
  '42501', NULL, 'B17: the CROSS-venue manager (Room V3) is still refused on Room V1''s event');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000201');
SELECT is((venue.create_ticket_type('22900000-0000-4000-8000-0000000000e6', 'admission', 'B own GA', 2000, 'public', 'ck229-b-18') ->> 'status'), 'ok',
  'B18: Org B''s owner is accepted on Org B''s OWN event e6 at Org B''s room (both arms agree where venue.org = event.org)');
SELECT tap.logout();

-- ── Section T — catalog.set_venue_timezone ──────────────────────────────────
SELECT is((SELECT count(*)::int FROM catalog.venue WHERE venue_id::text LIKE '22900000-%' AND timezone = 'America/New_York'), 3,
  'T1: every fixture venue carries the default America/New_York');
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is(catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Chicago', 'ops_tz', 'ck229-t-1'),
  jsonb_build_object('status','ok','venue_id','22900000-0000-4000-8000-0000000000a1','timezone','America/Chicago'),
  'T2: org_owner sets Room V1 to America/Chicago — {status ok, venue_id, timezone}');
SELECT tap.logout();
SELECT is((SELECT timezone FROM catalog.venue WHERE venue_id = '22900000-0000-4000-8000-0000000000a1'), 'America/Chicago',
  'T3: the value is persisted on catalog.venue');
SELECT tap.login('22900000-0000-4000-8000-000000000102');
SELECT is((catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/New_York', 'back_east', 'ck229-t-4') ->> 'timezone'), 'America/New_York',
  'T4: org_admin sets America/New_York (accepted name)');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000111');
SELECT is((catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Chicago', 'ops_tz_mgr', 'ck229-t-5') ->> 'timezone'), 'America/Chicago',
  'T5: the venue''s venue_manager sets America/Chicago (update_venue''s arm 2, mirrored)');
SELECT is(catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Chicago', 'again', 'ck229-t-6'),
  jsonb_build_object('status','noop','venue_id','22900000-0000-4000-8000-0000000000a1','timezone','America/Chicago'),
  'T6: the same value returns {status noop}');
SELECT throws_like($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'Mars/Olympus', 'x', 'ck229-t-7')$$,
  'invalid_input: unknown_timezone%', 'T7: Mars/Olympus is not in pg_timezone_names -> invalid_input');
SELECT throws_like($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', NULL, 'x', 'ck229-t-8')$$,
  'invalid_input: timezone required', 'T8: NULL timezone -> invalid_input (the column is NOT NULL; there is no "clear")');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', '', 'ck229-t-9')$$,
  'P0001', 'precondition_failed: reason_required', 'T9: a timezone change requires a reason code');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', '  ')$$,
  'P0001', 'precondition_failed: command key required', 'T10: an empty command key is refused');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000ff', 'America/Denver', 'x', 'ck229-t-11')$$,
  'P0002', NULL, 'T11: an unknown venue is not_found');
SELECT tap.logout();
-- refused 42501: org_finance, venue_finance, box_office, scanner, marketing, cross-venue manager, fan; anon; unauthenticated
SELECT tap.login('22900000-0000-4000-8000-000000000103');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r1')$$, '42501', NULL, 'T12: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r2')$$, '42501', NULL, 'T13: venue_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r3')$$, '42501', NULL, 'T14: venue_box_office is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r4')$$, '42501', NULL, 'T15: venue_scanner is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r5')$$, '42501', NULL, 'T16: venue_marketing is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r6')$$, '42501', NULL, 'T17: the CROSS-venue manager (Room V3) is refused on Room V1');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r7')$$, '42501', NULL, 'T18: a fan is refused');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r8')$$, '42501', NULL, 'T19: anon has no EXECUTE');
SELECT tap.logout();
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-t-r9')$$, '42501', NULL, 'T20: no auth.uid() -> insufficient_privilege (authentication required)');
-- the re-operated room, venue-level: update_venue's arms resolve the venue's CURRENT org and its own staff
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a2', 'America/Denver', 'x', 'ck229-t-21')$$,
  '42501', NULL, 'T21: Org A''s owner is refused on Room V2, which Org B now operates (a venue attribute follows the venue''s CURRENT org — update_venue''s arm 1)');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000201');
SELECT is((catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a2', 'America/Denver', 'new_operator', 'ck229-t-22') ->> 'timezone'), 'America/Denver',
  'T22: Org B''s owner (the current operator) sets Room V2''s timezone');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000121');
SELECT is((catalog.set_venue_timezone('22900000-0000-4000-8000-0000000000a2', 'America/Phoenix', 'staff_tz', 'ck229-t-23') ->> 'timezone'), 'America/Phoenix',
  'T23: STATUS QUO (A to rule) — Room V2''s venue_manager (granted under the former operator; staff_role is per venue and ruling C froze the re-scoping) is ACCEPTED on the venue-level setter, exactly as update_venue accepts them');
SELECT tap.logout();
-- audit: exactly one row per real change
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'venue.timezone_change' AND subject_kind = 'venue'
            AND subject_id = '22900000-0000-4000-8000-0000000000a1'), 3,
  'T24: exactly THREE audit rows for Room V1 — T2, T4, T5; none for the noop T6 or the refusals');
SELECT is((SELECT before::text || ' -> ' || after::text || ' / ' || reason_code || ' / ' || actor_identity::text
             FROM kernel.admin_audit WHERE action = 'venue.timezone_change'
              AND subject_id = '22900000-0000-4000-8000-0000000000a1' AND reason_code = 'ops_tz'),
  '{"timezone": "America/New_York"} -> {"timezone": "America/Chicago"} / ops_tz / 22900000-0000-4000-8000-000000000101',
  'T25: the T2 audit row carries before/after timezone, the reason code and the actor');
-- local projections: Room V1 is America/Chicago (CST, UTC-6 on 2026-11-20); f2 = 02:00Z -> 2026-11-19 20:00 local
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is((SELECT timezone || '|' || starts_at_local || '|' || ends_at_local || '|' || doors_at_local
             FROM venue_api.event_sessions WHERE session_id = '22900000-0000-4000-8000-0000000000f2'),
  'America/Chicago|2026-11-19 20:00|2026-11-20 00:00|2026-11-19 19:00',
  'T26: venue_api.event_sessions projects the venue''s timezone and the three *_local texts (02:00Z/06:00Z/01:00Z -> 20:00/00:00/19:00 Chicago)');
SELECT is((SELECT starts_at_local FROM venue_api.event_sessions WHERE session_id = '22900000-0000-4000-8000-0000000000f2'),
          (SELECT to_char(s.starts_at AT TIME ZONE 'America/Chicago', 'YYYY-MM-DD HH24:MI') FROM catalog.event_session s WHERE s.session_id = '22900000-0000-4000-8000-0000000000f2'),
  'T27: starts_at_local equals `starts_at at time zone <venue timezone>` computed from the base row');
SELECT is((SELECT timezone FROM venue_api.events WHERE event_id = '22900000-0000-4000-8000-0000000000e2'), 'America/Chicago',
  'T28: venue_api.events carries the venue''s timezone');
SELECT is((SELECT count(*) FROM venue_api.events), (SELECT count(*) FROM catalog.event),
  'T29: the events view still equals the base table row-for-row under RLS (the LEFT JOIN adds columns, never drops rows)');
SELECT is((SELECT count(*) FROM venue_api.event_sessions), (SELECT count(*) FROM catalog.event_session),
  'T30: the sessions view still equals the base table row-for-row under RLS');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT is((SELECT timezone || '|' || starts_at_local FROM venue_api.event_sessions WHERE session_id = '22900000-0000-4000-8000-0000000000f2'),
  'America/Chicago|2026-11-19 20:00',
  'T31: a fan reads the timezone and the local time of a PUBLISHED event''s session (the column grant on catalog.venue.timezone works under security_invoker)');
SELECT is((SELECT count(*)::int FROM venue_api.event_sessions WHERE session_id = '22900000-0000-4000-8000-0000000000f1'), 0,
  'T32: …and still cannot see the DRAFT''s session at all (RLS unchanged by the appended columns)');
SELECT tap.logout();

-- ── Section G — catalog.set_event_age_policy ────────────────────────────────
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is(catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'bar_license', 'ck229-g-1'),
  jsonb_build_object('status','ok','event_id','22900000-0000-4000-8000-0000000000e1','age_policy','21_plus'),
  'G1: org_owner sets the draft e1 to 21_plus — {status ok, event_id, age_policy}');
SELECT tap.logout();
SELECT is((SELECT age_policy FROM catalog.event WHERE event_id = '22900000-0000-4000-8000-0000000000e1'), '21_plus',
  'G2: the value is persisted on catalog.event');
SELECT tap.login('22900000-0000-4000-8000-000000000102');
SELECT is((catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '18_plus', 'promoter_ask', 'ck229-g-3') ->> 'age_policy'), '18_plus',
  'G3: org_admin sets 18_plus');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000111');
SELECT is((catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', 'all_ages', 'matinee', 'ck229-g-4') ->> 'age_policy'), 'all_ages',
  'G4: the BOUND venue_manager sets all_ages (the three values accepted)');
SELECT is(catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', 'all_ages', 'again', 'ck229-g-5'),
  jsonb_build_object('status','noop','event_id','22900000-0000-4000-8000-0000000000e1','age_policy','all_ages'),
  'G5: the same value returns {status noop}');
SELECT throws_like($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', 'adults', 'x', 'ck229-g-6')$$,
  'invalid_input: bad age_policy%', 'G6: ''adults'' is invalid_input (before the table CHECK)');
SELECT is((catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', NULL, 'unspecified', 'ck229-g-7') ->> 'status'), 'ok',
  'G7: NULL clears the policy (not specified is a state, not an error)');
SELECT tap.logout();
SELECT ok((SELECT age_policy IS NULL FROM catalog.event WHERE event_id = '22900000-0000-4000-8000-0000000000e1'),
  'G8: the cleared policy is NULL on the table');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'event.age_policy_change' AND subject_kind = 'event'
            AND subject_id = '22900000-0000-4000-8000-0000000000e1'), 4,
  'G9: exactly FOUR audit rows for e1 — G1, G3, G4, G7; none for the noop G5 or the refusal G6');
SELECT is((SELECT before::text || ' -> ' || after::text || ' / ' || reason_code || ' / ' || actor_identity::text
             FROM kernel.admin_audit WHERE action = 'event.age_policy_change'
              AND subject_id = '22900000-0000-4000-8000-0000000000e1' AND reason_code = 'unspecified'),
  '{"age_policy": "all_ages"} -> {"age_policy": null} / unspecified / 22900000-0000-4000-8000-000000000111',
  'G10: the G7 audit row carries before all_ages / after null, the reason and the actor');
-- refused 42501
SELECT tap.login('22900000-0000-4000-8000-000000000103');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r1')$$, '42501', NULL, 'G11: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r2')$$, '42501', NULL, 'G12: venue_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r3')$$, '42501', NULL, 'G13: venue_box_office is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r4')$$, '42501', NULL, 'G14: venue_scanner is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r5')$$, '42501', NULL, 'G15: venue_marketing is refused (an age policy is an admission rule, not marketing copy — update_event''s marketing arm does not apply)');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r6')$$, '42501', NULL, 'G16: the CROSS-venue manager is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e5', '21_plus', 'x', 'ck229-g-r7')$$, '42501', NULL, 'G17: E-76 — the FORMER-OPERATOR manager is refused on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r8')$$, '42501', NULL, 'G18: a fan is refused');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r9')$$, '42501', NULL, 'G19: anon has no EXECUTE');
SELECT tap.logout();
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-g-r10')$$, '42501', NULL, 'G20: no auth.uid() -> insufficient_privilege');
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e3', '21_plus', 'x', 'ck229-g-t1')$$,
  'P0001', 'precondition_failed: event_terminal', 'G21: refused on a COMPLETED event');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e4', '21_plus', 'x', 'ck229-g-t2')$$,
  'P0001', 'precondition_failed: event_terminal', 'G22: refused on a CANCELLED event');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000ee', '21_plus', 'x', 'ck229-g-i1')$$,
  'P0002', NULL, 'G23: an unknown event is not_found');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', NULL, 'ck229-g-i2')$$,
  'P0001', 'precondition_failed: reason_required', 'G24: a policy change requires a reason code');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', '')$$,
  'P0001', 'precondition_failed: command key required', 'G25: an empty command key is refused');
SELECT is((catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e5', '21_plus', 'bar_license', 'ck229-g-26') ->> 'age_policy'), '21_plus',
  'G26: R3 — the event''s OWN org_owner (A) is ACCEPTED on e5 at the re-operated room (the org arm is the EVENT''s org, as update_event''s)');
SELECT is((catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e2', '21_plus', 'bar_license', 'ck229-g-27') ->> 'status'), 'ok',
  'G27: allowed on an ON_SALE event');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000201');
SELECT throws_ok($$SELECT catalog.set_event_age_policy('22900000-0000-4000-8000-0000000000e5', 'all_ages', 'x', 'ck229-g-28')$$,
  '42501', NULL, 'G28: R3 — Org B''s owner (the new operator of Room V2) is REFUSED on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT is((SELECT age_policy FROM venue_api.events WHERE event_id = '22900000-0000-4000-8000-0000000000e2'), '21_plus',
  'G29: a fan reads age_policy of the PUBLISHED event e2 through venue_api.events (the column grant on catalog.event.age_policy)');
SELECT tap.logout();

-- ── Section S — SHARED CAPACITY (session f1 of the draft e1; three tiers; no batch yet) ──
SELECT tap.login('22900000-0000-4000-8000-000000000111');
SELECT is(catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 50, 'room_size', 'ck229-s-1'),
  jsonb_build_object('status','ok','session_id','22900000-0000-4000-8000-0000000000f1','sales_capacity',50,'allocated',0),
  'S1: the bound manager sets f1''s pool to 50 — {status ok, session_id, sales_capacity, allocated 0}');
SELECT is(tap._pool229('22900000-0000-4000-8000-0000000000f1'), 50,
  'S2: persisted (read through a definer helper: the column is withheld from the manager, A41)');
SELECT tap._store229('s_b1',
  (venue.create_inventory_batch('22900000-0000-4000-8000-000000000011', '22900000-0000-4000-8000-0000000000f1', 'public_sale', 30, 0, 'ck229-s-3') ->> 'batch_id'));
SELECT is(tap._alloc229('22900000-0000-4000-8000-0000000000f1'), 30,
  'S3: the first batch (30) is created; allocation 30 of 50');
SELECT throws_like($$SELECT venue.create_inventory_batch('22900000-0000-4000-8000-000000000012', '22900000-0000-4000-8000-0000000000f1', 'public_sale', 30, 0, 'ck229-s-4')$$,
  'precondition_failed: session_capacity_exceeded%', 'S4: RED->GREEN — a second 30-seat batch is REFUSED: 30 + 30 > 50 (the two tiers share one room)');
SELECT is(tap._alloc229('22900000-0000-4000-8000-0000000000f1'), 30,
  'S5: …and nothing was allocated by the refusal');
SELECT tap._store229('s_b2',
  (venue.create_inventory_batch('22900000-0000-4000-8000-000000000012', '22900000-0000-4000-8000-0000000000f1', 'public_sale', 20, 0, 'ck229-s-6') ->> 'batch_id'));
SELECT is(tap._alloc229('22900000-0000-4000-8000-0000000000f1'), 50,
  'S6: 30 + 20 is accepted; the room is full (50 of 50)');
SELECT throws_like($$SELECT venue.set_batch_capacity(tap._fetch229('s_b2')::uuid, 21, 'one_more', 'ck229-s-7')$$,
  'precondition_failed: session_capacity_exceeded%', 'S7: raising the 20-seat batch to 21 is REFUSED (30 + 21 > 50)');
SELECT is((venue.set_batch_capacity(tap._fetch229('s_b2')::uuid, 19, 'trim', 'ck229-s-8') ->> 'capacity'), '19',
  'S8: lowering it to 19 is accepted (30 + 19 = 49)');
SELECT throws_like($$SELECT venue.create_inventory_batch('22900000-0000-4000-8000-000000000013', '22900000-0000-4000-8000-0000000000f1', 'comp', 2, 0, 'ck229-s-9')$$,
  'precondition_failed: session_capacity_exceeded%', 'S9: a COMP batch counts against the pool — 2 comps are refused (49 + 2 > 50)');
SELECT tap._store229('s_b3',
  (venue.create_inventory_batch('22900000-0000-4000-8000-000000000013', '22900000-0000-4000-8000-0000000000f1', 'comp', 1, 0, 'ck229-s-10') ->> 'batch_id'));
SELECT is(tap._alloc229('22900000-0000-4000-8000-0000000000f1'), 50,
  'S10: one comp fits (49 + 1 = 50)');
SELECT throws_like($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 49, 'shrink', 'ck229-s-11')$$,
  'precondition_failed: below_allocated%', 'S11: lowering the pool to 49 is REFUSED below_allocated (50 allocated)');
SELECT is(catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 50, 'same', 'ck229-s-12'),
  jsonb_build_object('status','noop','session_id','22900000-0000-4000-8000-0000000000f1','sales_capacity',50,'allocated',50),
  'S12: the same pool returns {status noop} with the current allocation');
SELECT is((catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 60, 'extra_room', 'ck229-s-13') ->> 'sales_capacity'), '60',
  'S13: raising the pool to 60 is accepted');
SELECT is((catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', NULL, 'unlimited', 'ck229-s-14') ->> 'status'), 'ok',
  'S14: NULL clears the pool');
SELECT is((venue.create_inventory_batch('22900000-0000-4000-8000-000000000011', '22900000-0000-4000-8000-0000000000f1', 'presale', 1000, 0, 'ck229-s-15') ->> 'capacity'), '1000',
  'S15: with NULL sales_capacity a 1000-seat batch is accepted — unlimited, the 160 behaviour, pinned');
SELECT throws_like($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 50, 'too_late', 'ck229-s-16')$$,
  'precondition_failed: below_allocated%', 'S16: a pool below the 1050 now allocated is refused');
SELECT throws_like($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 0, 'x', 'ck229-s-17')$$,
  'invalid_input: bad sales_capacity%', 'S17: 0 is invalid_input (before the CHECK; NULL is the way to clear)');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 2000, '', 'ck229-s-18')$$,
  'P0001', 'precondition_failed: reason_required', 'S18: a pool change requires a reason code');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'event_session.sales_capacity_change' AND subject_kind = 'event_session'
            AND subject_id = '22900000-0000-4000-8000-0000000000f1'), 3,
  'S19: exactly THREE audit rows for f1 — S1, S13, S14; none for the noop S12 or the refusals');
SELECT is((SELECT before::text || ' -> ' || after::text || ' / ' || reason_code || ' / ' || actor_identity::text
             FROM kernel.admin_audit WHERE action = 'event_session.sales_capacity_change'
              AND subject_id = '22900000-0000-4000-8000-0000000000f1' AND reason_code = 'unlimited'),
  '{"sales_capacity": 60} -> {"sales_capacity": null} / unlimited / 22900000-0000-4000-8000-000000000111',
  'S20: the S14 audit row carries before 60 / after null, the reason and the actor');
SELECT is((SELECT session_version FROM catalog.event_session WHERE session_id = '22900000-0000-4000-8000-0000000000f1'), 1,
  'S21: session_version is untouched by the pool setter (it is 093''s time-change dedupe key; stale-version semantics stay 093''s)');
-- capacity_hint: Room V3 carries 40; its session f6 already holds a 20-seat batch (as Org B's owner)
SELECT tap.login('22900000-0000-4000-8000-000000000201');
SELECT throws_like($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f6', 50, 'x', 'ck229-s-22')$$,
  'precondition_failed: above_venue_capacity%', 'S22: a pool of 50 on a room with capacity_hint 40 is REFUSED above_venue_capacity');
SELECT is((catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f6', 40, 'room_size', 'ck229-s-23') ->> 'sales_capacity'), '40',
  'S23: a pool equal to capacity_hint (40) is accepted');
SELECT throws_like($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f6', 19, 'x', 'ck229-s-24')$$,
  'precondition_failed: below_allocated%', 'S24: 19 is refused below_allocated (20 allocated)');
SELECT throws_like($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f6', 41, 'x', 'ck229-s-25')$$,
  'precondition_failed: above_venue_capacity%', 'S25: 41 is refused above_venue_capacity');
SELECT throws_like($$SELECT venue.create_inventory_batch('22900000-0000-4000-8000-000000000061', '22900000-0000-4000-8000-0000000000f6', 'door', 21, 0, 'ck229-s-26')$$,
  'precondition_failed: session_capacity_exceeded%', 'S26: a 21-seat door batch on f6 is refused (20 + 21 > 40)');
SELECT tap.logout();
-- authority matrix on set_session_sales_capacity (f1 is V1's; f5 is e5's)
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is((catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1100, 'owner', 'ck229-s-27') ->> 'sales_capacity'), '1100',
  'S27: org_owner is allowed (1100 >= the 1050 allocated)');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000102');
SELECT is((catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1200, 'admin', 'ck229-s-28') ->> 'sales_capacity'), '1200',
  'S28: org_admin is allowed');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000103');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r1')$$, '42501', NULL, 'S29: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r2')$$, '42501', NULL, 'S30: venue_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r3')$$, '42501', NULL, 'S31: venue_box_office is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r4')$$, '42501', NULL, 'S32: venue_scanner is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r5')$$, '42501', NULL, 'S33: venue_marketing is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r6')$$, '42501', NULL, 'S34: the CROSS-venue manager is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f5', 300, 'x', 'ck229-s-r7')$$, '42501', NULL, 'S35: E-76 — the FORMER-OPERATOR manager is refused on e5''s session');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r8')$$, '42501', NULL, 'S36: a fan is refused');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r9')$$, '42501', NULL, 'S37: anon has no EXECUTE');
SELECT tap.logout();
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1300, 'x', 'ck229-s-r10')$$, '42501', NULL, 'S38: no auth.uid() -> insufficient_privilege');
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f3', 500, 'x', 'ck229-s-t1')$$,
  'P0001', 'precondition_failed: event_terminal', 'S39: refused on a COMPLETED event''s session');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f4', 500, 'x', 'ck229-s-t2')$$,
  'P0001', 'precondition_failed: event_terminal', 'S40: refused on a CANCELLED event''s session');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000fe', 500, 'x', 'ck229-s-i1')$$,
  'P0002', NULL, 'S41: an unknown session is not_found');
SELECT is((catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f5', 300, 'owner_a', 'ck229-s-42') ->> 'allocated'), '260',
  'S42: R3 — the event''s OWN org_owner (A) sets e5''s pool at the re-operated room; allocated reads 260 (250 from B11 + 10 from B10)');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000201');
SELECT throws_ok($$SELECT catalog.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f5', 400, 'x', 'ck229-s-43')$$,
  '42501', NULL, 'S43: R3 — Org B''s owner is REFUSED on Org A''s event''s session');
SELECT tap.logout();

-- ── Section W — sale windows + venue.ticket_type_on_sale (e2 on_sale: t21 public, t22 hidden, t23 door_only) ──
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021'),
  'W1: a public tier of an on_sale event with no window is on sale now');
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', '2036-11-01 00:00+00', '2036-11-02 00:00+00', 'presale_day', 'ck229-w-2') ->> 'status'), 'ok',
  'W2: org_owner sets t21''s window [2036-11-01 00:00Z, 2036-11-02 00:00Z)');
SELECT tap.logout();
SELECT is((SELECT sale_starts_at::text || '|' || sale_ends_at::text FROM venue.ticket_type WHERE ticket_type_id = '22900000-0000-4000-8000-000000000021'),
          ('2036-11-01 00:00+00'::timestamptz)::text || '|' || ('2036-11-02 00:00+00'::timestamptz)::text,
  'W3: both bounds are persisted');
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-11-01 00:00:00+00'),
  'W4: starts is INCLUSIVE — on sale at exactly sale_starts_at');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-10-31 23:59:59+00'),
  'W5: one second before sale_starts_at -> not on sale');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-11-02 00:00:00+00'),
  'W6: ends is EXCLUSIVE — not on sale at exactly sale_ends_at');
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-11-01 23:59:59+00'),
  'W7: one second before sale_ends_at -> on sale');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021'),
  'W8: with a 2036 window the tier is NOT on sale now (p_at defaults to now())');
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT is((SELECT on_sale_now::text || '|' || sale_starts_at::text FROM venue_api.ticket_types WHERE ticket_type_id = '22900000-0000-4000-8000-000000000021'),
          'false|' || ('2036-11-01 00:00+00'::timestamptz)::text,
  'W9: a fan reads on_sale_now (false — the window is in 2036) and the window of the PUBLIC tier through venue_api.ticket_types');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'open_start', 'ck229-w-10') ->> 'status'), 'ok',
  'W10: NULL start, end 2036-11-02');
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2000-01-01 00:00+00'),
  'W11: NULL sale_starts_at = open on that side (on sale in 2000)');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-11-03 00:00+00'),
  'W12: …but not after the end');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', '2036-11-01 00:00+00', NULL, 'open_end', 'ck229-w-13') ->> 'status'), 'ok',
  'W13: start 2036-11-01, NULL end');
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2099-01-01 00:00+00'),
  'W14: NULL sale_ends_at = open on that side (on sale in 2099)');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-10-01 00:00+00'),
  'W15: …but not before the start');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, NULL, 'clear', 'ck229-w-16') ->> 'status'), 'ok',
  'W16: NULL/NULL clears the window');
SELECT ok((SELECT sale_starts_at IS NULL AND sale_ends_at IS NULL FROM venue.ticket_type WHERE ticket_type_id = '22900000-0000-4000-8000-000000000021'),
  'W17: both bounds are NULL on the table');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, NULL, 'again', 'ck229-w-18') ->> 'status'), 'noop',
  'W18: the same (NULL/NULL) window returns {status noop}');
SELECT throws_like($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', '2036-11-02 00:00+00', '2036-11-01 00:00+00', 'x', 'ck229-w-19')$$,
  'invalid_input: sale_ends_at must be after sale_starts_at', 'W19: an end before the start is invalid_input (before the CHECK)');
SELECT throws_like($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', '2036-11-01 00:00+00', '2036-11-01 00:00+00', 'x', 'ck229-w-20')$$,
  'invalid_input: sale_ends_at must be after sale_starts_at', 'W20: an end equal to the start is invalid_input (strictly after)');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', NULL, 'ck229-w-21')$$,
  'P0001', 'precondition_failed: reason_required', 'W21: a window change requires a reason code');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', ' ')$$,
  'P0001', 'precondition_failed: command key required', 'W22: an empty command key is refused');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-0000000000ff', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-23')$$,
  'P0002', NULL, 'W23: an unknown ticket type is not_found');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000031', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-24')$$,
  'P0001', 'precondition_failed: event_terminal', 'W24: refused on a COMPLETED event');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000041', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-25')$$,
  'P0001', 'precondition_failed: event_terminal', 'W25: refused on a CANCELLED event');
SELECT tap.logout();
-- the predicate's other conjuncts
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000022'),
  'W26: a HIDDEN tier of an on_sale event is never on sale');
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000023'),
  'W27: a door_only tier of an on_sale event IS on sale (sold at the door; visibility <> hidden)');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000011'),
  'W28: a public tier of a DRAFT event is not on sale');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000071'),
  'W29: a public tier of an ANNOUNCED event is not on sale');
SELECT ok(venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081'),
  'W30: a public tier of a LIVE event is on sale');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000031'),
  'W31: a public tier of a COMPLETED event is not on sale');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000041'),
  'W32: a public tier of a CANCELLED event is not on sale');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-0000000000ff'),
  'W33: an unknown id -> false, never NULL, never an error');
SELECT ok(NOT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', NULL),
  'W34: a NULL p_at -> false (the window cannot contain an unknown instant)');
-- authority matrix on set_ticket_type_sale_window
SELECT tap.login('22900000-0000-4000-8000-000000000102');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', '2036-12-01 00:00+00', NULL, 'admin', 'ck229-w-35') ->> 'status'), 'ok',
  'W35: org_admin is allowed');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000111');
SELECT is((venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, NULL, 'mgr_clear', 'ck229-w-36') ->> 'status'), 'ok',
  'W36: the BOUND venue_manager is allowed');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000103');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r1')$$, '42501', NULL, 'W37: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r2')$$, '42501', NULL, 'W38: venue_finance is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r3')$$, '42501', NULL, 'W39: venue_box_office is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r4')$$, '42501', NULL, 'W40: venue_scanner is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r5')$$, '42501', NULL, 'W41: venue_marketing is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r6')$$, '42501', NULL, 'W42: the CROSS-venue manager is refused');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000051', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r7')$$, '42501', NULL, 'W43: E-76 — the FORMER-OPERATOR manager is refused on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r8')$$, '42501', NULL, 'W44: a fan is refused');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r9')$$, '42501', NULL, 'W45: anon has no EXECUTE');
SELECT throws_ok($$SELECT venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021')$$, '42501', NULL, 'W46: anon has no EXECUTE on the predicate either (anon reads go through 176''s arms and F''s views)');
SELECT tap.logout();
SELECT throws_ok($$SELECT venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'x', 'ck229-w-r10')$$, '42501', NULL, 'W47: no auth.uid() -> insufficient_privilege');
-- audit
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.sale_window_change' AND subject_kind = 'ticket_type'
            AND subject_id = '22900000-0000-4000-8000-000000000021'), 6,
  'W48: exactly SIX audit rows for t21 — W2, W10, W13, W16, W35, W36; none for the noop W18 or the refusals');
SELECT is((SELECT before::text || ' -> ' || after::text || ' / ' || reason_code || ' / ' || actor_identity::text
             FROM kernel.admin_audit WHERE action = 'ticket_type.sale_window_change'
              AND subject_id = '22900000-0000-4000-8000-000000000021' AND reason_code = 'presale_day'),
  '{"sale_ends_at": null, "sale_starts_at": null} -> {"sale_ends_at": "' || (to_json('2036-11-02 00:00+00'::timestamptz) #>> '{}') || '", "sale_starts_at": "' || (to_json('2036-11-01 00:00+00'::timestamptz) #>> '{}') || '"} / presale_day / 22900000-0000-4000-8000-000000000101',
  'W49: the W2 audit row carries before NULL/NULL, after both bounds, the reason and the actor');

-- ── Section W (TZ) — a window is a pair of absolute instants; the session TimeZone never enters ─
-- A's readiness question ("are session start and sale windows evaluated in the venue's timezone?"):
-- no — evaluation is timezone-INDEPENDENT. sale_starts_at / sale_ends_at / starts_at are timestamptz
-- instants and venue.ticket_type_on_sale compares instants; catalog.venue.timezone governs DISPLAY
-- only (T27/T31). naive timestamp literals are interpreted in the caller's session TimeZone
-- (PostgREST: UTC) — clients MUST send ISO-8601 with an offset, converting the venue's local
-- wall-clock using catalog.venue.timezone. Pinned on t81 (e8 live, public, no window so far; no
-- other assertion reads t81's window or its audit rows). The session TimeZone is restored after W51.
-- The helper SELECTs below print a prefixed value ('stored …'), never a bare result line: pg_prove parses any
-- output line beginning with the TAP result word as a test, so a stored status printed alone would add tests.
SELECT tap._store229('tz0', current_setting('TimeZone'));
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT set_config('TimeZone', 'UTC', true);
SELECT 'stored ' || tap._store229('w50_set_utc', venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000081', '2026-11-30 19:00:00-05', NULL, 'tz_utc', 'ck229-w-50a') ->> 'status');
SELECT tap.logout();
SELECT tap._store229('w50_utc', (SELECT to_char(sale_starts_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') || '+00' FROM venue.ticket_type WHERE ticket_type_id = '22900000-0000-4000-8000-000000000081'));
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT 'stored ' || tap._store229('w50_clear', venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000081', NULL, NULL, 'tz_clear', 'ck229-w-50b') ->> 'status');
SELECT set_config('TimeZone', 'Pacific/Kiritimati', true);
SELECT 'stored ' || tap._store229('w50_set_kir', venue.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000081', '2026-11-30 19:00:00-05', NULL, 'tz_kiritimati', 'ck229-w-50c') ->> 'status');
SELECT tap.logout();
SELECT tap._store229('w50_kir', (SELECT to_char(sale_starts_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') || '+00' FROM venue.ticket_type WHERE ticket_type_id = '22900000-0000-4000-8000-000000000081'));
SELECT is(tap._fetch229('w50_set_utc') || '/' || tap._fetch229('w50_clear') || '/' || tap._fetch229('w50_set_kir')
          || ' UTC:' || tap._fetch229('w50_utc') || ' KIR:' || tap._fetch229('w50_kir'),
  'ok/ok/ok UTC:2026-12-01 00:00:00+00 KIR:2026-12-01 00:00:00+00',
  'W50: set_ticket_type_sale_window given the offset-qualified ''2026-11-30 19:00:00-05'' stores the SAME instant (2026-12-01 00:00:00+00) whether the session TimeZone is UTC or Pacific/Kiritimati');
-- t81's window now starts at 2026-12-01 00:00Z (end open). Two fixed instants 30 min either side of the
-- boundary, each evaluated under three session zones; the local calendar date differs across the zones
-- (23:30Z is already Dec 1 in Kiritimati, 00:30Z is still Nov 30 in New York), so any zone-dependent
-- comparison would flip at least one verdict.
SELECT set_config('TimeZone', 'UTC', true);
SELECT tap._store229('w51_utc', venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081', '2026-11-30 23:30:00+00')::text || ','
                                || venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081', '2026-12-01 00:30:00+00')::text);
SELECT set_config('TimeZone', 'America/New_York', true);
SELECT tap._store229('w51_ny', venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081', '2026-11-30 23:30:00+00')::text || ','
                               || venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081', '2026-12-01 00:30:00+00')::text);
SELECT set_config('TimeZone', 'Pacific/Kiritimati', true);
SELECT tap._store229('w51_kir', venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081', '2026-11-30 23:30:00+00')::text || ','
                                || venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000081', '2026-12-01 00:30:00+00')::text);
SELECT set_config('TimeZone', tap._fetch229('tz0'), true);
SELECT is('UTC:' || tap._fetch229('w51_utc') || ' NY:' || tap._fetch229('w51_ny') || ' KIR:' || tap._fetch229('w51_kir'),
  'UTC:false,true NY:false,true KIR:false,true',
  'W51: venue.ticket_type_on_sale(t81, fixed instant) returns the same verdict under session TimeZone UTC, America/New_York and Pacific/Kiritimati (23:30Z before the 00:00Z start -> false; 00:30Z after -> true)');

-- ── Section P — 176 interplay through venue_api (as a fan) ──────────────────
-- P1 and P3 assert 176's published-event arm (F's #143). 176 is beneath this whole stack (A's base ruling,
-- 2026-10-26: 159 -> 176 -> 160 -> 161 -> 162), so Section P runs LIVE and unconditionally: no presence gate
-- and no masking call (CI's mask gate bans them outright, MASK_MAX_SKIP_CALLS=0). A chain without 176 now
-- fails P1/P3 loudly instead of passing them silently. P2 and P4 hold on 081's arms as well.
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM venue_api.ticket_types WHERE event_id = '22900000-0000-4000-8000-0000000000e1'), 0,
  'P1: a PUBLIC tier of a DRAFT event is invisible to a fan through venue_api.ticket_types (176''s published-event arm; the appended columns change nothing)');
SELECT is((SELECT string_agg(ticket_type_id::text || ':' || on_sale_now::text, ',' ORDER BY ticket_type_id) FROM venue_api.ticket_types WHERE event_id = '22900000-0000-4000-8000-0000000000e2'),
  '22900000-0000-4000-8000-000000000021:true',
  'P2: of the on_sale event''s three tiers the fan sees ONLY the public one, on_sale_now true (window cleared in W36); hidden and door_only stay invisible');
SELECT is((SELECT count(*)::int FROM venue_api.inventory_batches WHERE event_session_id = '22900000-0000-4000-8000-0000000000f1'), 0,
  'P3: the draft''s batches (created in Section S) are invisible to the fan (176''s published-event arm)');
SELECT is((SELECT count(*)::int FROM venue_api.events WHERE event_id = '22900000-0000-4000-8000-0000000000e1'), 0,
  'P4: the draft event itself stays invisible (the LEFT JOIN to catalog.venue adds no row)');
SELECT tap.logout();

-- ── Section C — venue_cmd wrappers ──────────────────────────────────────────
SELECT tap.login('22900000-0000-4000-8000-000000000101');
SELECT is((venue_cmd.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/New_York', 'wrap', 'ck229-c-1') ->> 'timezone'), 'America/New_York',
  'C1: set_venue_timezone through the wrapper — the definer''s result');
SELECT is((venue_cmd.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '18_plus', 'wrap', 'ck229-c-2') ->> 'age_policy'), '18_plus',
  'C2: set_event_age_policy through the wrapper');
SELECT is((venue_cmd.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 1250, 'wrap', 'ck229-c-3') ->> 'sales_capacity'), '1250',
  'C3: set_session_sales_capacity through the wrapper');
SELECT is((venue_cmd.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, '2036-11-02 00:00+00', 'wrap', 'ck229-c-4') ->> 'status'), 'ok',
  'C4: set_ticket_type_sale_window through the wrapper');
SELECT is(venue_cmd.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-11-01 00:00+00'),
          venue.ticket_type_on_sale('22900000-0000-4000-8000-000000000021', '2036-11-01 00:00+00'),
  'C5: ticket_type_on_sale through the wrapper equals the direct call');
SELECT throws_like($$SELECT venue_cmd.set_session_sales_capacity('22900000-0000-4000-8000-0000000000f1', 10, 'x', 'ck229-c-7')$$,
  'precondition_failed: below_allocated%', 'C7: below_allocated propagates unchanged through the wrapper');
SELECT tap.logout();
-- read as postgres (kernel.admin_audit is granted to no client role)
SELECT is((SELECT actor_identity FROM kernel.admin_audit WHERE action = 'event_session.sales_capacity_change' AND subject_id = '22900000-0000-4000-8000-0000000000f1' AND reason_code = 'wrap'),
          '22900000-0000-4000-8000-000000000101'::uuid,
  'C6: the wrapper''s audit row names the caller as actor (SECURITY INVOKER + the definer''s auth.uid())');
SELECT tap.login('22900000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue_cmd.set_event_age_policy('22900000-0000-4000-8000-0000000000e1', '21_plus', 'x', 'ck229-c-8')$$,
  '42501', NULL, 'C8: a fan through the wrapper: 42501 (the definer''s refusal, unchanged)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue_cmd.set_venue_timezone('22900000-0000-4000-8000-0000000000a1', 'America/Denver', 'x', 'ck229-c-9')$$,
  '42501', NULL, 'C9: anon is refused at the schema wall (no USAGE on venue_cmd)');
SELECT tap.logout();
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_sale_window('22900000-0000-4000-8000-000000000021', NULL, NULL, 'x', 'ck229-c-10')$$,
  '42501', NULL, 'C10: no auth.uid() through the wrapper: insufficient_privilege (authentication required)');

SELECT * FROM finish();
ROLLBACK;
