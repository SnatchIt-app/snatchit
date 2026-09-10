-- ============================================================================
-- venue/scripts/rehearsal-fixtures.sql — SYNTHETIC venue-dashboard fixtures for
-- the LOCAL rehearsal harness ONLY. Never a migration; never staging/production.
--
--   * Refuses to run unless the database name contains 'rehears'.
--   * Depends on admin/scripts/fixtures.sql having created ops_harness.accounts
--     (the auth stub reads plain-text harness logins from it).
--   * Fixed UUIDs prefixed 'c1a55e01-…' (slice 1); every insert is idempotent.
--   * Two organizations, two approved venues, four synthetic people:
--       venue.manager.a@example.test   venue_manager  @ Venue A (org A)
--       org.owner.a@example.test       org_owner      @ org A   (sees org A drafts)
--       venue.finance.b@example.test   venue_finance  @ Venue B (org B)
--       outsider@example.test          no grants anywhere
--     Password for all: harness-pass-123.
--   * Org A: one on_sale event (public + hidden ticket types, batches),
--     one DRAFT event (visible to org A plane only). Org B: one announced event.
-- ============================================================================
\set ON_ERROR_STOP on
SELECT current_database() ~ 'rehears' AS ok \gset
\if :ok
\else
  \echo 'REFUSING: database name must contain rehears'
  \quit 1
\endif

BEGIN;

-- --- 1. Synthetic auth users --------------------------------------------------
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
VALUES
  ('c1a55e01-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'venue.manager.a@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('c1a55e01-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'org.owner.a@example.test',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('c1a55e01-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'venue.finance.b@example.test', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('c1a55e01-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@example.test',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;

INSERT INTO ops_harness.accounts (email, password_plain, user_id, aal, label) VALUES
  ('venue.manager.a@example.test', 'harness-pass-123', 'c1a55e01-0000-4000-8000-0000000000a1', 'aal1', 'venue_manager at Venue A (org A)'),
  ('org.owner.a@example.test',     'harness-pass-123', 'c1a55e01-0000-4000-8000-0000000000a2', 'aal1', 'org_owner of org A'),
  ('venue.finance.b@example.test', 'harness-pass-123', 'c1a55e01-0000-4000-8000-0000000000b1', 'aal1', 'venue_finance at Venue B (org B)'),
  ('outsider@example.test',        'harness-pass-123', 'c1a55e01-0000-4000-8000-0000000000c1', 'aal1', 'authenticated, no org/venue grant')
ON CONFLICT (email) DO NOTHING;

-- --- 2. Organizations and venues --------------------------------------------
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('c1a55e01-0000-4000-8000-00000000000a', 'Rehearsal Org A LLC (synthetic)', 'Rehearsal Org A (synthetic)', 'active'),
  ('c1a55e01-0000-4000-8000-00000000000b', 'Rehearsal Org B LLC (synthetic)', 'Rehearsal Org B (synthetic)', 'active')
ON CONFLICT (org_id) DO NOTHING;

INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, capacity_hint, approval_status) VALUES
  ('c1a55e01-0000-4000-8000-0000000000aa', 'c1a55e01-0000-4000-8000-00000000000a', 'Rehearsal Room A (synthetic)', 'wynwood', '1 Synthetic St', 500, 'approved'),
  ('c1a55e01-0000-4000-8000-0000000000bb', 'c1a55e01-0000-4000-8000-00000000000b', 'Rehearsal Room B (synthetic)', 'brickell', '2 Synthetic Ave', 300, 'approved')
ON CONFLICT (venue_id) DO NOTHING;

-- --- 3. Grants (direct inserts: rehearsal only; production uses the grant RPCs)
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('c1a55e01-0000-4000-8000-00000000000a', 'c1a55e01-0000-4000-8000-0000000000a2', 'org_owner')
ON CONFLICT (org_id, identity_id) DO NOTHING;

INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('c1a55e01-0000-4000-8000-0000000000aa', 'c1a55e01-0000-4000-8000-0000000000a1', 'venue_manager'),
  ('c1a55e01-0000-4000-8000-0000000000bb', 'c1a55e01-0000-4000-8000-0000000000b1', 'venue_finance')
ON CONFLICT (venue_id, identity_id, role) DO NOTHING;

-- --- 4. Events, sessions, ticket types, batches -------------------------------
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('c1a55e01-0000-4000-8000-0000000000e1', 'c1a55e01-0000-4000-8000-0000000000aa', 'c1a55e01-0000-4000-8000-00000000000a', 'Rehearsal Night A (synthetic, on sale)', 'on_sale'),
  ('c1a55e01-0000-4000-8000-0000000000e2', 'c1a55e01-0000-4000-8000-0000000000aa', 'c1a55e01-0000-4000-8000-00000000000a', 'Rehearsal Draft A (synthetic, draft)',   'draft'),
  ('c1a55e01-0000-4000-8000-0000000000e3', 'c1a55e01-0000-4000-8000-0000000000bb', 'c1a55e01-0000-4000-8000-00000000000b', 'Rehearsal Night B (synthetic, announced)', 'announced')
ON CONFLICT (event_id) DO NOTHING;

INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, doors_at, status) VALUES
  ('c1a55e01-0000-4000-8000-0000000000f1', 'c1a55e01-0000-4000-8000-0000000000e1', NULL, now() + interval '3 days', now() + interval '3 days' - interval '1 hour', 'scheduled'),
  ('c1a55e01-0000-4000-8000-0000000000f2', 'c1a55e01-0000-4000-8000-0000000000e2', NULL, now() + interval '30 days', NULL, 'scheduled'),
  ('c1a55e01-0000-4000-8000-0000000000f3', 'c1a55e01-0000-4000-8000-0000000000e3', NULL, now() + interval '10 days', NULL, 'scheduled')
ON CONFLICT (session_id) DO NOTHING;

INSERT INTO catalog.resale_policy (policy_id, scope_kind, venue_id, event_id, mode, version, effective_from) VALUES
  ('c1a55e01-0000-4000-8000-0000000000d1', 'event', NULL, 'c1a55e01-0000-4000-8000-0000000000e1', 'face_value_queue', 1, now())
ON CONFLICT (policy_id) DO NOTHING;

INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('c1a55e01-0000-4000-8000-000000000011', 'c1a55e01-0000-4000-8000-0000000000e1', 'admission', 'General admission (synthetic)', 2500, 'public'),
  ('c1a55e01-0000-4000-8000-000000000012', 'c1a55e01-0000-4000-8000-0000000000e1', 'admission', 'Hidden early bird (synthetic)', 1800, 'hidden'),
  ('c1a55e01-0000-4000-8000-000000000013', 'c1a55e01-0000-4000-8000-0000000000e3', 'admission', 'General admission B (synthetic)', 4000, 'public')
ON CONFLICT (ticket_type_id) DO NOTHING;

INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('c1a55e01-0000-4000-8000-000000000021', 'c1a55e01-0000-4000-8000-000000000011', 'c1a55e01-0000-4000-8000-0000000000f1', 'public_sale', 300, 6, 120),
  ('c1a55e01-0000-4000-8000-000000000022', 'c1a55e01-0000-4000-8000-000000000012', 'c1a55e01-0000-4000-8000-0000000000f1', 'presale',     100, 0, 100),
  ('c1a55e01-0000-4000-8000-000000000023', 'c1a55e01-0000-4000-8000-000000000013', 'c1a55e01-0000-4000-8000-0000000000f3', 'public_sale', 200, 0, 15)
ON CONFLICT (batch_id) DO NOTHING;

COMMIT;

\echo '[venue fixtures] TEST HARNESS synthetic data present:'
SELECT 'accounts' AS what, count(*) FROM ops_harness.accounts WHERE user_id::text LIKE 'c1a55e01-%'
UNION ALL SELECT 'orgs',    count(*) FROM kernel.organization WHERE org_id::text LIKE 'c1a55e01-%'
UNION ALL SELECT 'venues',  count(*) FROM catalog.venue WHERE venue_id::text LIKE 'c1a55e01-%'
UNION ALL SELECT 'events',  count(*) FROM catalog.event WHERE event_id::text LIKE 'c1a55e01-%'
UNION ALL SELECT 'staff',   count(*) FROM venue.staff_role WHERE identity_id::text LIKE 'c1a55e01-%'
UNION ALL SELECT 'batches', count(*) FROM venue.inventory_batch WHERE batch_id::text LIKE 'c1a55e01-%';
