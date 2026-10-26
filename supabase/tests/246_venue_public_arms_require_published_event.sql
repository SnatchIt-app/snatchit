-- ============================================================================
-- 246_venue_public_arms_require_published_event.sql — migration 20261022000000 (registry 176).
--
-- Registry 176 / pgTAP 246, allocated by A (origin/a/registry-20261021). A reviews before this leaves
-- draft. Owner decision V-13 (2026-10-21): before venue_api is exposed, the PUBLIC arms of
-- venue.ticket_type and venue.inventory_batch require a non-draft parent event, by the rule
-- catalog_event_sel_anon uses (status <> 'draft', R3-3a). The _venue arms (081) are unchanged.
--
-- Fixture style: 226 (synthetic rows inserted as postgres with fixed ids, read back as each caller
-- through tap.login, rolled back). Fixture: Org A / Room A with one event in EACH of the six statuses
-- (e1 on_sale, e2 draft, e3 announced, e4 live, e5 completed, e6 cancelled), Org B / Room B with a
-- draft e7. Every event carries a public ticket type with one batch; the draft e2 and the on-sale e1
-- also carry a hidden and a door_only type, each with a batch. Callers: Room A venue_manager, Org A
-- org_owner, Org A org_member, Room A venue_box_office, Room A venue_finance, Room B venue_finance, an
-- outsider (signed in, no grant) and anon.
--
--   Section A  shape: the policy set, command/roles/permissive of all four arms, the draft conjunct in
--              both public quals (and no '>='), the anon schema wall, the E-29 column grants, RLS on.
--   Section B  the finding, as the outsider: a draft's public type and batch are gone (base tables and
--              venue_api); every non-draft status keeps them; hidden and door_only stay invisible; the
--              set of events reached through venue.ticket_type equals the set catalog.event shows.
--   Section C  anon: still refused at the schema wall.
--   Section D  staff of ANOTHER venue: A's draft is gone; their own draft is still readable through
--              their own _venue arm.
--   Section E  Room A staff on the draft e2: manager and owner read all three types and batches;
--              venue_finance reads public + door_only types and their batches (081 tiers, unchanged);
--              org_member and venue_box_office keep the draft's non-hidden types but lose its batches
--              (they are not in 081's batch arm — the documented consequence, 176_READERS.md).
--   Section F  hidden rows on a published event are unchanged for the manager.
--   Section V  venue_api still equals the base tables under the caller's RLS.
--   Section P  definition pins: each of the four policy quals equals the qual of a twin policy built in
--              this transaction on a temp table of the same name (both deparsed by the same session, as
--              226 F6 does for views): the two public arms from this migration's text, the two _venue
--              arms from 081's text, unchanged.
--
-- Expected on the chain WITHOUT 176 (081 bodies; not run yet, by reading): A4, B1, B2, B7, B8, B9,
-- B10, B11, B12, D1, D2, E8, E11, P1 and P2 fail (15); the other 35 pass.
-- ============================================================================
BEGIN;
SELECT plan(50);
SELECT tap.seed_core();

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('24600000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.a.246@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('24600000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.246@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('24600000-0000-4000-8000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'member.a.246@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('24600000-0000-4000-8000-0000000000a4', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'box.a.246@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('24600000-0000-4000-8000-0000000000a5', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.246@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('24600000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.b.246@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('24600000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider.246@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('24600000-0000-4000-8000-00000000000a', 'Org A 246', 'Org A 246', 'active'),
  ('24600000-0000-4000-8000-00000000000b', 'Org B 246', 'Org B 246', 'active');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'Room A 246', 'wynwood',  'approved'),
  ('24600000-0000-4000-8000-0000000000bb', '24600000-0000-4000-8000-00000000000b', 'Room B 246', 'brickell', 'approved');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('24600000-0000-4000-8000-00000000000a', '24600000-0000-4000-8000-0000000000a2', 'org_owner'),
  ('24600000-0000-4000-8000-00000000000a', '24600000-0000-4000-8000-0000000000a3', 'org_member');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-0000000000a1', 'venue_manager'),
  ('24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-0000000000a4', 'venue_box_office'),
  ('24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-0000000000a5', 'venue_finance'),
  ('24600000-0000-4000-8000-0000000000bb', '24600000-0000-4000-8000-0000000000b1', 'venue_finance');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('24600000-0000-4000-8000-0000000000e1', '24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'A on sale 246',   'on_sale'),
  ('24600000-0000-4000-8000-0000000000e2', '24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'A draft 246',     'draft'),
  ('24600000-0000-4000-8000-0000000000e3', '24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'A announced 246', 'announced'),
  ('24600000-0000-4000-8000-0000000000e4', '24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'A live 246',      'live'),
  ('24600000-0000-4000-8000-0000000000e5', '24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'A completed 246', 'completed'),
  ('24600000-0000-4000-8000-0000000000e6', '24600000-0000-4000-8000-0000000000aa', '24600000-0000-4000-8000-00000000000a', 'A cancelled 246', 'cancelled'),
  ('24600000-0000-4000-8000-0000000000e7', '24600000-0000-4000-8000-0000000000bb', '24600000-0000-4000-8000-00000000000b', 'B draft 246',     'draft');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('24600000-0000-4000-8000-0000000000f1', '24600000-0000-4000-8000-0000000000e1', now() + interval '3 days',  'scheduled'),
  ('24600000-0000-4000-8000-0000000000f2', '24600000-0000-4000-8000-0000000000e2', now() + interval '30 days', 'scheduled'),
  ('24600000-0000-4000-8000-0000000000f3', '24600000-0000-4000-8000-0000000000e3', now() + interval '10 days', 'scheduled'),
  ('24600000-0000-4000-8000-0000000000f4', '24600000-0000-4000-8000-0000000000e4', now() + interval '1 hour',  'scheduled'),
  ('24600000-0000-4000-8000-0000000000f5', '24600000-0000-4000-8000-0000000000e5', now() - interval '3 days',  'scheduled'),
  ('24600000-0000-4000-8000-0000000000f6', '24600000-0000-4000-8000-0000000000e6', now() + interval '20 days', 'scheduled'),
  ('24600000-0000-4000-8000-0000000000f7', '24600000-0000-4000-8000-0000000000e7', now() + interval '40 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('24600000-0000-4000-8000-000000000011', '24600000-0000-4000-8000-0000000000e1', 'admission', 'GA on sale 246',     2500, 'public'),
  ('24600000-0000-4000-8000-00000000001a', '24600000-0000-4000-8000-0000000000e1', 'admission', 'Hidden on sale 246', 1800, 'hidden'),
  ('24600000-0000-4000-8000-00000000001b', '24600000-0000-4000-8000-0000000000e1', 'admission', 'Door on sale 246',   3000, 'door_only'),
  ('24600000-0000-4000-8000-000000000012', '24600000-0000-4000-8000-0000000000e2', 'admission', 'GA draft 246',       2600, 'public'),
  ('24600000-0000-4000-8000-000000000013', '24600000-0000-4000-8000-0000000000e2', 'admission', 'Hidden draft 246',   1900, 'hidden'),
  ('24600000-0000-4000-8000-000000000014', '24600000-0000-4000-8000-0000000000e2', 'admission', 'Door draft 246',     3100, 'door_only'),
  ('24600000-0000-4000-8000-000000000015', '24600000-0000-4000-8000-0000000000e3', 'admission', 'GA announced 246',   2700, 'public'),
  ('24600000-0000-4000-8000-000000000016', '24600000-0000-4000-8000-0000000000e4', 'admission', 'GA live 246',        2800, 'public'),
  ('24600000-0000-4000-8000-000000000017', '24600000-0000-4000-8000-0000000000e5', 'admission', 'GA completed 246',   2900, 'public'),
  ('24600000-0000-4000-8000-000000000018', '24600000-0000-4000-8000-0000000000e6', 'admission', 'GA cancelled 246',   3200, 'public'),
  ('24600000-0000-4000-8000-000000000019', '24600000-0000-4000-8000-0000000000e7', 'admission', 'GA B draft 246',     3300, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('24600000-0000-4000-8000-000000000021', '24600000-0000-4000-8000-000000000011', '24600000-0000-4000-8000-0000000000f1', 'public_sale', 300, 6, 120),
  ('24600000-0000-4000-8000-00000000002a', '24600000-0000-4000-8000-00000000001a', '24600000-0000-4000-8000-0000000000f1', 'presale',     100, 0, 10),
  ('24600000-0000-4000-8000-00000000002b', '24600000-0000-4000-8000-00000000001b', '24600000-0000-4000-8000-0000000000f1', 'door',         50, 0, 0),
  ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000012', '24600000-0000-4000-8000-0000000000f2', 'public_sale', 200, 0, 0),
  ('24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000013', '24600000-0000-4000-8000-0000000000f2', 'presale',      40, 0, 0),
  ('24600000-0000-4000-8000-000000000024', '24600000-0000-4000-8000-000000000014', '24600000-0000-4000-8000-0000000000f2', 'door',         30, 0, 0),
  ('24600000-0000-4000-8000-000000000025', '24600000-0000-4000-8000-000000000015', '24600000-0000-4000-8000-0000000000f3', 'public_sale', 150, 0, 0),
  ('24600000-0000-4000-8000-000000000026', '24600000-0000-4000-8000-000000000016', '24600000-0000-4000-8000-0000000000f4', 'public_sale', 150, 0, 75),
  ('24600000-0000-4000-8000-000000000027', '24600000-0000-4000-8000-000000000017', '24600000-0000-4000-8000-0000000000f5', 'public_sale', 150, 0, 150),
  ('24600000-0000-4000-8000-000000000028', '24600000-0000-4000-8000-000000000018', '24600000-0000-4000-8000-0000000000f6', 'public_sale', 150, 0, 0),
  ('24600000-0000-4000-8000-000000000029', '24600000-0000-4000-8000-000000000019', '24600000-0000-4000-8000-0000000000f7', 'public_sale', 120, 0, 0);

-- ── Section A — shape ───────────────────────────────────────────────────────
SELECT is((SELECT string_agg(c.relname || '.' || p.polname, ',' ORDER BY c.relname, p.polname)
             FROM pg_policy p JOIN pg_class c ON c.oid = p.polrelid JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'venue' AND c.relname IN ('ticket_type', 'inventory_batch')),
          'inventory_batch.venue_inventory_batch_sel_public,inventory_batch.venue_inventory_batch_sel_venue,'
          || 'ticket_type.venue_ticket_type_sel_public,ticket_type.venue_ticket_type_sel_venue',
          'A1: each table keeps exactly its two 081 policy names (1-for-1 replacement, no extra arm)');
SELECT is((SELECT string_agg(policyname || ':' || cmd || ':' || array_to_string(roles, ',') || ':' || permissive || ':' || coalesce(with_check, '<null>'), ';' ORDER BY policyname)
             FROM pg_policies
            WHERE schemaname = 'venue' AND policyname IN ('venue_ticket_type_sel_public', 'venue_inventory_batch_sel_public')),
          'venue_inventory_batch_sel_public:SELECT:authenticated:PERMISSIVE:<null>;venue_ticket_type_sel_public:SELECT:authenticated:PERMISSIVE:<null>',
          'A2: both public arms stay FOR SELECT TO authenticated, PERMISSIVE, no WITH CHECK');
SELECT is((SELECT string_agg(policyname || ':' || cmd || ':' || array_to_string(roles, ',') || ':' || permissive || ':' || coalesce(with_check, '<null>'), ';' ORDER BY policyname)
             FROM pg_policies
            WHERE schemaname = 'venue' AND policyname IN ('venue_ticket_type_sel_venue', 'venue_inventory_batch_sel_venue')),
          'venue_inventory_batch_sel_venue:SELECT:authenticated:PERMISSIVE:<null>;venue_ticket_type_sel_venue:SELECT:authenticated:PERMISSIVE:<null>',
          'A3: both _venue arms keep FOR SELECT TO authenticated, PERMISSIVE, no WITH CHECK (their quals: P3, P4)');
SELECT ok((SELECT bool_and(position('<> ''draft''' IN qual) > 0 AND position('>=' IN qual) = 0) AND count(*) = 2
             FROM pg_policies
            WHERE schemaname = 'venue' AND policyname IN ('venue_ticket_type_sel_public', 'venue_inventory_batch_sel_public')),
          'A4: R3-3a — both public quals test status <> ''draft'' and neither uses >= (lexicographic over text)');
SELECT ok(NOT has_schema_privilege('anon', 'venue', 'USAGE')
          AND NOT has_table_privilege('anon', 'venue.ticket_type', 'SELECT')
          AND NOT has_table_privilege('anon', 'venue.inventory_batch', 'SELECT'),
          'A5: anon still has no USAGE on venue and no SELECT on either table (E-30 wall unchanged)');
SELECT ok(NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'capacity', 'SELECT')
          AND NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'held', 'SELECT')
          AND NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'sold', 'SELECT')
          AND has_column_privilege('authenticated', 'venue.inventory_batch', 'remaining', 'SELECT')
          AND has_table_privilege('authenticated', 'venue.ticket_type', 'SELECT'),
          'A6: grants unchanged — E-29 counters withheld, remaining and ticket_type readable by authenticated');
SELECT ok((SELECT bool_and(c.relrowsecurity AND NOT c.relforcerowsecurity) AND count(*) = 2
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'venue' AND c.relname IN ('ticket_type', 'inventory_batch')),
          'A7: RLS stays enabled and not FORCEd on both tables');

-- ── Section B — the finding, as a signed-in user with no grant ──────────────
SELECT tap.login('24600000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 0,
          'B1: outsider reads NO ticket type of the draft e2 (its public type included)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 0,
          'B2: outsider reads NO batch of the draft e2 (its public batch''s remaining included)');
SELECT is((SELECT count(*)::int FROM venue.ticket_type
            WHERE ticket_type_id IN ('24600000-0000-4000-8000-000000000011', '24600000-0000-4000-8000-000000000015', '24600000-0000-4000-8000-000000000016',
                                     '24600000-0000-4000-8000-000000000017', '24600000-0000-4000-8000-000000000018')), 5,
          'B3: outsider reads the public type of every non-draft status: on_sale, announced, live, completed, cancelled');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000021', '24600000-0000-4000-8000-000000000025', '24600000-0000-4000-8000-000000000026',
                               '24600000-0000-4000-8000-000000000027', '24600000-0000-4000-8000-000000000028')), 5,
          'B4: outsider reads the public batch of every non-draft status');
SELECT is((SELECT count(*)::int FROM venue.ticket_type
            WHERE ticket_type_id IN ('24600000-0000-4000-8000-00000000001a', '24600000-0000-4000-8000-00000000001b')), 0,
          'B5: outsider still reads neither the hidden nor the door_only type of the on-sale e1');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-00000000002a', '24600000-0000-4000-8000-00000000002b')), 0,
          'B6: outsider still reads neither the hidden-type nor the door_only-type batch of e1');
SELECT set_eq(
  $$ SELECT DISTINCT t.event_id FROM venue.ticket_type t WHERE t.event_id::text LIKE '24600000-%' $$,
  $$ SELECT e.event_id FROM catalog.event e WHERE e.event_id::text LIKE '24600000-%' $$,
  'B7: the events an outsider reaches through venue.ticket_type are exactly the events catalog.event shows them (catalog_event_sel_anon''s rule)');
SELECT set_eq(
  $$ SELECT b.batch_id FROM venue.inventory_batch b WHERE b.batch_id::text LIKE '24600000-%' $$,
  $$ VALUES ('24600000-0000-4000-8000-000000000021'::uuid), ('24600000-0000-4000-8000-000000000025'::uuid),
            ('24600000-0000-4000-8000-000000000026'::uuid), ('24600000-0000-4000-8000-000000000027'::uuid),
            ('24600000-0000-4000-8000-000000000028'::uuid) $$,
  'B8: the outsider''s whole batch view of the fixture is the five public batches of non-draft events');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = '24600000-0000-4000-8000-000000000019'), 0,
          'B9: outsider reads no public type of Room B''s draft e7');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch WHERE batch_id = '24600000-0000-4000-8000-000000000029'), 0,
          'B10: outsider reads no batch of Room B''s draft e7');
SELECT is((SELECT count(*)::int FROM venue_api.ticket_types WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 0,
          'B11: the REST surface — venue_api.ticket_types shows the outsider nothing of the draft e2');
SELECT is((SELECT count(*)::int FROM venue_api.inventory_batches WHERE batch_id = '24600000-0000-4000-8000-000000000022'), 0,
          'B12: the REST surface — venue_api.inventory_batches does not show the draft''s public remaining');
SELECT is((SELECT count(*)::int FROM venue_api.ticket_types WHERE event_id = '24600000-0000-4000-8000-0000000000e1'), 1,
          'B13: venue_api.ticket_types still shows the outsider the on-sale public type (and only it)');
SELECT is((SELECT remaining FROM venue_api.inventory_batches WHERE batch_id = '24600000-0000-4000-8000-000000000021'), 174,
          'B14: venue_api.inventory_batches still shows the on-sale public batch''s remaining (300 - 6 - 120)');
SELECT tap.logout();

-- ── Section C — anon ────────────────────────────────────────────────────────
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT count(*) FROM venue.ticket_type $$, '42501', NULL,
                 'C1: anon is refused venue.ticket_type at the schema wall (076/E-30, unchanged)');
SELECT throws_ok($$ SELECT count(*) FROM venue.inventory_batch $$, '42501', NULL,
                 'C2: anon is refused venue.inventory_batch at the schema wall');
SELECT throws_ok($$ SELECT count(*) FROM venue_api.ticket_types $$, '42501', NULL,
                 'C3: anon is refused venue_api.ticket_types (159 grants authenticated only)');
SELECT tap.logout();

-- ── Section D — staff of another venue ──────────────────────────────────────
SELECT tap.login('24600000-0000-4000-8000-0000000000b1');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 0,
          'D1: Room B finance reads no type of Room A''s draft (a role elsewhere is a stranger here)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 0,
          'D2: Room B finance reads no batch of Room A''s draft');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE ticket_type_id = '24600000-0000-4000-8000-000000000019'), 1,
          'D3: Room B finance still reads its OWN draft''s public type (081 _venue arm, unchanged)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch WHERE batch_id = '24600000-0000-4000-8000-000000000029'), 1,
          'D4: Room B finance still reads its OWN draft''s batch (081 batch arm: venue_finance)');
SELECT tap.logout();

-- ── Section E — Room A staff on the draft e2 ────────────────────────────────
SELECT tap.login('24600000-0000-4000-8000-0000000000a1');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 3,
          'E1: venue_manager still reads all three draft types (public, hidden, door_only)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 3,
          'E2: venue_manager still reads all three draft batches');
SELECT tap.logout();
SELECT tap.login('24600000-0000-4000-8000-0000000000a2');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 3,
          'E3: org_owner still reads all three draft types');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 3,
          'E4: org_owner still reads all three draft batches');
SELECT tap.logout();
SELECT tap.login('24600000-0000-4000-8000-0000000000a5');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 2,
          'E5: venue_finance still reads the draft''s public and door_only types, never the hidden one (§9.1 tiers)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 2,
          'E6: venue_finance still reads the draft''s public and door_only batches through the batch arm (the hidden-type batch stays unreadable: that arm resolves the event through a ticket_type read under the caller''s RLS — 081 as built, unchanged)');
SELECT tap.logout();
SELECT tap.login('24600000-0000-4000-8000-0000000000a3');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 2,
          'E7: org_member still reads the draft''s non-hidden types (081 _venue arm, unchanged)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 0,
          'E8: org_member no longer reads the draft''s batches — not in 081''s batch arm; the public arm was its only path (176_READERS.md)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000021', '24600000-0000-4000-8000-00000000002a', '24600000-0000-4000-8000-00000000002b')), 1,
          'E9: org_member still reads the on-sale e1''s public batch, and only it (unchanged)');
SELECT tap.logout();
SELECT tap.login('24600000-0000-4000-8000-0000000000a4');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e2'), 2,
          'E10: venue_box_office still reads the draft''s non-hidden types (081 _venue arm, unchanged)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000022', '24600000-0000-4000-8000-000000000023', '24600000-0000-4000-8000-000000000024')), 0,
          'E11: venue_box_office no longer reads the draft''s batches — not in 081''s batch arm (176_READERS.md)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000021', '24600000-0000-4000-8000-00000000002a', '24600000-0000-4000-8000-00000000002b')), 1,
          'E12: venue_box_office still reads the on-sale e1''s public batch, and only it (unchanged)');
SELECT tap.logout();

-- ── Section F — hidden rows on a published event, for the manager ───────────
SELECT tap.login('24600000-0000-4000-8000-0000000000a1');
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id = '24600000-0000-4000-8000-0000000000e1'), 3,
          'F1: venue_manager reads e1''s public, hidden and door_only types (unchanged)');
SELECT is((SELECT count(*)::int FROM venue.inventory_batch
            WHERE batch_id IN ('24600000-0000-4000-8000-000000000021', '24600000-0000-4000-8000-00000000002a', '24600000-0000-4000-8000-00000000002b')), 3,
          'F2: venue_manager reads all three e1 batches (unchanged)');
SELECT tap.logout();

-- ── Section V — venue_api still equals the base tables under RLS ────────────
SELECT tap.login('24600000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*) FROM venue_api.ticket_types), (SELECT count(*) FROM venue.ticket_type),
          'V1: outsider — venue_api.ticket_types equals venue.ticket_type under the same RLS');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches), (SELECT count(*) FROM venue.inventory_batch),
          'V2: outsider — venue_api.inventory_batches equals venue.inventory_batch under the same RLS');
SELECT tap.logout();
SELECT tap.login('24600000-0000-4000-8000-0000000000a3');
SELECT is((SELECT count(*) FROM venue_api.ticket_types), (SELECT count(*) FROM venue.ticket_type),
          'V3: org_member — venue_api.ticket_types equals the base table under the same RLS');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches), (SELECT count(*) FROM venue.inventory_batch),
          'V4: org_member — venue_api.inventory_batches equals the base table under the same RLS');
SELECT tap.logout();

-- ── Section P — definition pins (as postgres, last: the temp twins shadow the bare names) ─────
-- Each twin is a policy on a temp table carrying the real table's NAME and columns, so the deparser
-- renders its outer column references exactly as it renders the real policy's. Both sides are
-- deparsed by pg_get_expr in this same statement, so neither the search_path nor the deparser version
-- can make them differ. The public twins are this migration's USING clauses; the _venue twins are
-- 081's (lines 1001-1009 and 1028-1037), with venue.<table>.<column> written <table>.<column>.
CREATE TEMP TABLE ticket_type (LIKE venue.ticket_type);
CREATE TEMP TABLE inventory_batch (LIKE venue.inventory_batch);
CREATE POLICY exp_ticket_type_sel_public
  ON pg_temp.ticket_type FOR SELECT TO authenticated
  USING (visibility = 'public'
         AND EXISTS (SELECT 1 FROM catalog.event e
                      WHERE e.event_id = ticket_type.event_id
                        AND e.status <> 'draft'));
CREATE POLICY exp_inventory_batch_sel_public
  ON pg_temp.inventory_batch FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM venue.ticket_type tt
                   JOIN catalog.event e ON e.event_id = tt.event_id
                  WHERE tt.ticket_type_id = inventory_batch.ticket_type_id
                    AND tt.visibility = 'public'
                    AND e.status <> 'draft'));
CREATE POLICY exp_ticket_type_sel_venue
  ON pg_temp.ticket_type FOR SELECT TO authenticated
  USING (
        kernel.has_org_role_over_event(event_id, array['org_owner','org_admin'])
     or kernel.has_event_role(event_id, array['venue_manager'])
     or (visibility <> 'hidden'
         and (kernel.has_org_role_over_event(event_id, array['org_finance','org_member'])
              or kernel.has_event_role(event_id,
                   array['venue_finance','venue_box_office',
                         'venue_marketing','venue_promoter_manager','venue_scanner'])))
  );
CREATE POLICY exp_inventory_batch_sel_venue
  ON pg_temp.inventory_batch FOR SELECT TO authenticated
  USING (
    kernel.has_org_role_over_event(
      (select tt.event_id from venue.ticket_type tt
        where tt.ticket_type_id = inventory_batch.ticket_type_id),
      array['org_owner','org_admin','org_finance'])
    or kernel.has_event_role(
      (select tt.event_id from venue.ticket_type tt
        where tt.ticket_type_id = inventory_batch.ticket_type_id),
      array['venue_manager','venue_finance','venue_scanner'])
  );

SELECT is((SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'venue.ticket_type'::regclass AND p.polname = 'venue_ticket_type_sel_public'),
          (SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'pg_temp.ticket_type'::regclass AND p.polname = 'exp_ticket_type_sel_public'),
          'P1: venue_ticket_type_sel_public is exactly visibility = public AND a non-draft parent event');
SELECT is((SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'venue.inventory_batch'::regclass AND p.polname = 'venue_inventory_batch_sel_public'),
          (SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'pg_temp.inventory_batch'::regclass AND p.polname = 'exp_inventory_batch_sel_public'),
          'P2: venue_inventory_batch_sel_public is exactly a public type of a non-draft event');
SELECT is((SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'venue.ticket_type'::regclass AND p.polname = 'venue_ticket_type_sel_venue'),
          (SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'pg_temp.ticket_type'::regclass AND p.polname = 'exp_ticket_type_sel_venue'),
          'P3: venue_ticket_type_sel_venue is still 081''s two-tier clause, unchanged');
SELECT is((SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'venue.inventory_batch'::regclass AND p.polname = 'venue_inventory_batch_sel_venue'),
          (SELECT pg_get_expr(p.polqual, p.polrelid) FROM pg_policy p WHERE p.polrelid = 'pg_temp.inventory_batch'::regclass AND p.polname = 'exp_inventory_batch_sel_venue'),
          'P4: venue_inventory_batch_sel_venue is still 081''s staff clause, unchanged');

SELECT * FROM finish();
ROLLBACK;
