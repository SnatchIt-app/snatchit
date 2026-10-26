-- ============================================================================
-- 226_venue_api_read_views.sql — migration 20261021120000 (venue_api read views).
--
-- Registry 159 / pgTAP 226, allocated by A in PR #115 (origin/a/registry-20261021).
-- A reviews before this leaves draft. Renamed from the provisional 224 (224 and
-- 225 belong to registry rows 157 and 158 of A). The version is unchanged.
--
--   Port of origin/venue/dashboard-v2 supabase/tests/188_venue_api_read_views.sql
--   (blob 7ed77132, plan 47, written for the same views under 20260910120000).
--   A1–E7 and D1–D5 are carried verbatim, fixture included (ids keep their 187
--   tag). 25 assertions are new (plan 47 -> 72), each added because a planted
--   mutant of the migration survived (see
--   docs/venue-dashboard/VENUE_API_PROVISIONAL_MIGRATION.md §4.4 to §4.6).
--   Round 1 (plan 56), mutants that survived the 47:
--     E8–E11 the "mine only" filter of my_staff_roles / my_org_roles is the
--            view's own `identity_id = auth.uid()`, not RLS: a scanner can read
--            its venue's whole roster in the base table but sees only its own
--            row in the view (no UI role escalation); same for an org member.
--     F1–F5 the exact privilege surface. supabase/ci/expected_grants.txt and
--            the grant-decision manifest read `public` only, so this file is
--            the CI gate for venue_api: exact relation + column ACL, exact
--            schema ACL, no default-ACL grant in the schema, security_barrier
--            on every view, and the exact projected column set.
--   Round 2 (plan 71, review of 3bf24c0b), mutants that survived the 56: a
--   REVOKE of a projected base column (views unreadable, 56/56 green),
--   WHERE false on venues or resale_policies, and s.ends_at AS starts_at.
--     C22–C30 venues and resale_policies read as the caller (manager, org
--            owner, outsider), with a draft venue and a draft-parent policy,
--            plus value checks on rows whose same-typed columns all differ.
--     D6–D9  view-equals-base counts for venues and resale_policies.
--     F6     each view definition equals the migration SELECT (pg_get_viewdef
--            of the real view against a temp view built from the same text).
--     F7     no GLOBAL table default of the owner grants PUBLIC, anon or
--            authenticated. F3 checks schema-scoped rows only, and its label
--            no longer claims more.
--   Round 3 (plan 72, review of 3d2b0bf5): the header claimed that A1-A3 and
--   F1 catch any object added to the schema. An enum, domain or range type, or
--   a table with no columns, added to venue_api leaves all 71 green (by
--   reading the queries, not run).
--     F8     no pg_type row in venue_api other than the eight views' row types
--            and their array types.
--   Section A: shape — schema, eight views, security_invoker on every one, no
--     function of any kind in the schema, grants exactly {authenticated}.
--   Section B: projection — no counter column (capacity/held/sold) and no
--     ungranted catalog column reaches a view.
--   Section C: tenant isolation as the caller — org-A manager sees A's data
--     INCLUDING A's draft (080 catalog_event_sel_venue: venue_manager reads its
--     venue's drafts; the other five venue roles do not); org-A owner sees the
--     draft; org-B finance sees neither A's draft, A's hidden type nor A's
--     hidden-type batch by id; an outsider sees only what is public; anon has
--     no schema usage at all.
--   Section D: the views never widen — a row absent from the base table for a
--     caller is absent from the view for the same caller.
-- Fixtures are synthetic, created inside this transaction and rolled back.
-- ============================================================================
BEGIN;
SELECT plan(72);
SELECT tap.seed_core();

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('18700000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.a.187@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('18700000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.187@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('18700000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.b.187@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('18700000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider.187@test.local','{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('18700000-0000-4000-8000-00000000000a', 'Org A 187', 'Org A 187', 'active'),
  ('18700000-0000-4000-8000-00000000000b', 'Org B 187', 'Org B 187', 'active');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('18700000-0000-4000-8000-0000000000aa', '18700000-0000-4000-8000-00000000000a', 'Room A 187', 'wynwood', 'approved'),
  ('18700000-0000-4000-8000-0000000000bb', '18700000-0000-4000-8000-00000000000b', 'Room B 187', 'brickell', 'approved');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('18700000-0000-4000-8000-00000000000a', '18700000-0000-4000-8000-0000000000a2', 'org_owner');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('18700000-0000-4000-8000-0000000000aa', '18700000-0000-4000-8000-0000000000a1', 'venue_manager'),
  ('18700000-0000-4000-8000-0000000000bb', '18700000-0000-4000-8000-0000000000b1', 'venue_finance');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('18700000-0000-4000-8000-0000000000e1', '18700000-0000-4000-8000-0000000000aa', '18700000-0000-4000-8000-00000000000a', 'A on sale 187', 'on_sale'),
  ('18700000-0000-4000-8000-0000000000e2', '18700000-0000-4000-8000-0000000000aa', '18700000-0000-4000-8000-00000000000a', 'A draft 187',   'draft'),
  ('18700000-0000-4000-8000-0000000000e3', '18700000-0000-4000-8000-0000000000bb', '18700000-0000-4000-8000-00000000000b', 'B announced 187', 'announced');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('18700000-0000-4000-8000-0000000000f1', '18700000-0000-4000-8000-0000000000e1', now() + interval '3 days', 'scheduled'),
  ('18700000-0000-4000-8000-0000000000f2', '18700000-0000-4000-8000-0000000000e2', now() + interval '30 days', 'scheduled'),
  ('18700000-0000-4000-8000-0000000000f3', '18700000-0000-4000-8000-0000000000e3', now() + interval '10 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('18700000-0000-4000-8000-000000000011', '18700000-0000-4000-8000-0000000000e1', 'admission', 'GA A 187', 2500, 'public'),
  ('18700000-0000-4000-8000-000000000012', '18700000-0000-4000-8000-0000000000e1', 'admission', 'Hidden A 187', 1800, 'hidden'),
  ('18700000-0000-4000-8000-000000000013', '18700000-0000-4000-8000-0000000000e3', 'admission', 'GA B 187', 4000, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('18700000-0000-4000-8000-000000000021', '18700000-0000-4000-8000-000000000011', '18700000-0000-4000-8000-0000000000f1', 'public_sale', 300, 6, 120),
  ('18700000-0000-4000-8000-000000000022', '18700000-0000-4000-8000-000000000012', '18700000-0000-4000-8000-0000000000f1', 'presale',     100, 0, 100),
  ('18700000-0000-4000-8000-000000000023', '18700000-0000-4000-8000-000000000013', '18700000-0000-4000-8000-0000000000f3', 'public_sale', 200, 0, 15);

-- ── Section A — shape ────────────────────────────────────────────────────────
SELECT has_schema('venue_api', 'A1: schema venue_api exists');
SELECT is((SELECT count(*) FROM pg_views WHERE schemaname = 'venue_api'), 8::bigint, 'A2: exactly eight views');
SELECT is((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_api'), 0::bigint, 'A3: no functions in venue_api (no definer surface)');
SELECT is((SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'venue_api' AND c.relkind = 'v'
             AND NOT EXISTS (SELECT 1 FROM unnest(c.reloptions) o WHERE o = 'security_invoker=true')), 0::bigint, 'A4: every view is security_invoker');
SELECT ok(has_schema_privilege('authenticated', 'venue_api', 'USAGE'), 'A5: authenticated has USAGE');
SELECT ok(NOT has_schema_privilege('anon', 'venue_api', 'USAGE'), 'A6: anon has no USAGE');
SELECT ok(has_table_privilege('authenticated', 'venue_api.events', 'SELECT'), 'A7: authenticated may SELECT venue_api.events');
SELECT ok(NOT has_table_privilege('anon', 'venue_api.events', 'SELECT'), 'A8: anon may not SELECT venue_api.events');
SELECT ok(NOT has_table_privilege('authenticated', 'venue_api.events', 'INSERT') AND NOT has_table_privilege('authenticated', 'venue_api.events', 'UPDATE') AND NOT has_table_privilege('authenticated', 'venue_api.events', 'DELETE'), 'A9: no write privilege on the views');
SELECT is((SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'venue_api' AND grantee NOT IN ('authenticated', 'postgres')), 0::bigint, 'A10: no grantee other than authenticated (and the owner)');

-- ── Section B — projection ───────────────────────────────────────────────────
SELECT is((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'venue_api' AND table_name = 'inventory_batches' AND column_name IN ('capacity','held','sold')), 0::bigint, 'B1: inventory_batches projects no capacity/held/sold');
SELECT has_column('venue_api', 'inventory_batches', 'remaining', 'B2: inventory_batches projects remaining');
SELECT is((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'venue_api' AND table_name = 'events' AND column_name IN ('description','hero_image_ref','genre_tags')), 0::bigint, 'B3: events projects no marketing columns');
SELECT ok((SELECT bool_and(pg_get_viewdef(c.oid) !~* 'security definer') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'venue_api' AND c.relkind = 'v'), 'B4: view definitions are plain selects');

-- ── Section C — tenant isolation, as the caller ──────────────────────────────
-- venue_manager at Room A: public data yes, A's draft YES (080 venue arm, manager only), hidden type YES (manager tier), batches YES.
SELECT tap.login('18700000-0000-4000-8000-0000000000a1');
SELECT is((SELECT count(*) FROM venue_api.events WHERE venue_id = '18700000-0000-4000-8000-0000000000aa'), 2::bigint, 'C1: manager A sees both Room A events, draft included (080 venue arm)');
SELECT is((SELECT count(*) FROM venue_api.events WHERE event_id = '18700000-0000-4000-8000-0000000000e2'), 1::bigint, 'C2: manager A reads A''s draft by id');
SELECT is((SELECT count(*) FROM venue_api.ticket_types WHERE event_id = '18700000-0000-4000-8000-0000000000e1'), 2::bigint, 'C3: manager A sees public + hidden types of A');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches WHERE ticket_type_id IN ('18700000-0000-4000-8000-000000000011','18700000-0000-4000-8000-000000000012')), 2::bigint, 'C4: manager A sees both A batches');
SELECT is((SELECT count(*) FROM venue_api.event_sessions WHERE event_id = '18700000-0000-4000-8000-0000000000e2'), 1::bigint, 'C5: manager A reads the draft''s session (visibility resolves through the event)');
SELECT is((SELECT count(*) FROM venue_api.events WHERE venue_id = '18700000-0000-4000-8000-0000000000bb'), 1::bigint, 'C6: manager A sees B''s ANNOUNCED event (catalog is public read) — scoping is by route, not by RLS, for non-drafts');
SELECT is((SELECT count(*) FROM venue_api.ticket_types WHERE event_id = '18700000-0000-4000-8000-0000000000e3'), 1::bigint, 'C7: manager A sees B''s public ticket type only');
SELECT tap.logout();

-- org_owner of A: the draft IS visible.
SELECT tap.login('18700000-0000-4000-8000-0000000000a2');
SELECT is((SELECT count(*) FROM venue_api.events WHERE venue_id = '18700000-0000-4000-8000-0000000000aa'), 2::bigint, 'C8: org owner A sees both A events including the draft');
SELECT is((SELECT count(*) FROM venue_api.event_sessions WHERE event_id = '18700000-0000-4000-8000-0000000000e2'), 1::bigint, 'C9: org owner A sees the draft''s session');
SELECT is((SELECT count(*) FROM venue_api.ticket_types WHERE event_id = '18700000-0000-4000-8000-0000000000e1' AND visibility = 'hidden'), 1::bigint, 'C10: org owner A sees A''s hidden type');
SELECT tap.logout();

-- venue_finance at Room B: A's hidden type NO; A's batches by id NO; B's batch YES; A's draft NO.
SELECT tap.login('18700000-0000-4000-8000-0000000000b1');
SELECT is((SELECT count(*) FROM venue_api.ticket_types WHERE ticket_type_id = '18700000-0000-4000-8000-000000000012'), 0::bigint, 'C11: finance B cannot read A''s hidden type by id');
SELECT is((SELECT count(*) FROM venue_api.ticket_types WHERE ticket_type_id = '18700000-0000-4000-8000-000000000011'), 1::bigint, 'C12: finance B can read A''s PUBLIC type (public catalog)');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches WHERE batch_id = '18700000-0000-4000-8000-000000000022'), 0::bigint, 'C13: finance B cannot read A''s hidden-type batch by id');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches WHERE batch_id = '18700000-0000-4000-8000-000000000023'), 1::bigint, 'C14: finance B reads B''s own batch');
SELECT is((SELECT count(*) FROM venue_api.events WHERE event_id = '18700000-0000-4000-8000-0000000000e2'), 0::bigint, 'C15: finance B cannot read A''s draft by id');
SELECT tap.logout();

-- outsider (authenticated, no grants): public catalog only; no hidden type, no draft, no hidden-type batch.
SELECT tap.login('18700000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*) FROM venue_api.events WHERE event_id IN ('18700000-0000-4000-8000-0000000000e1','18700000-0000-4000-8000-0000000000e3')), 2::bigint, 'C16: outsider reads the two public events');
SELECT is((SELECT count(*) FROM venue_api.events WHERE event_id = '18700000-0000-4000-8000-0000000000e2'), 0::bigint, 'C17: outsider cannot read the draft by id');
SELECT is((SELECT count(*) FROM venue_api.ticket_types WHERE event_id = '18700000-0000-4000-8000-0000000000e1'), 1::bigint, 'C18: outsider sees only the public type');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches WHERE ticket_type_id = '18700000-0000-4000-8000-000000000012'), 0::bigint, 'C19: outsider cannot read the hidden-type batch');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches WHERE batch_id = '18700000-0000-4000-8000-000000000021'), 1::bigint, 'C20: outsider reads remaining of the public batch (world-readable projection, spec note 4)');
SELECT tap.logout();

-- anon: schema usage denied outright.
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT count(*) FROM venue_api.events $$, '42501', NULL, 'C21: anon is refused at the schema/view grant');
SELECT tap.logout();

-- ── Section E — own grants (dashboard entry policy) ─────────────────────────
SELECT is((SELECT count(*) FROM information_schema.columns WHERE table_schema = 'venue_api' AND table_name IN ('my_staff_roles','my_org_roles') AND column_name = 'identity_id'), 0::bigint, 'E1: grant views do not project identity_id');
SELECT tap.login('18700000-0000-4000-8000-0000000000a1');
SELECT is((SELECT string_agg(venue_id::text || ':' || role, ',') FROM venue_api.my_staff_roles), '18700000-0000-4000-8000-0000000000aa:venue_manager', 'E2: manager A sees exactly its own staff grant');
SELECT is((SELECT count(*) FROM venue_api.my_org_roles), 0::bigint, 'E3: manager A has no org role');
SELECT tap.logout();
SELECT tap.login('18700000-0000-4000-8000-0000000000a2');
SELECT is((SELECT string_agg(org_id::text || ':' || role, ',') FROM venue_api.my_org_roles), '18700000-0000-4000-8000-00000000000a:org_owner', 'E4: org owner A sees exactly its own org grant');
SELECT tap.logout();
SELECT tap.login('18700000-0000-4000-8000-0000000000b1');
SELECT is((SELECT count(*) FROM venue_api.my_staff_roles WHERE venue_id = '18700000-0000-4000-8000-0000000000aa'), 0::bigint, 'E5: finance B holds no grant at Room A (cross-venue entry denied by the app)');
SELECT tap.logout();
SELECT tap.login('18700000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*) FROM venue_api.my_staff_roles) + (SELECT count(*) FROM venue_api.my_org_roles), 0::bigint, 'E6: outsider has no grants at all -> no dashboard');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT count(*) FROM venue_api.my_staff_roles $$, '42501', NULL, 'E7: anon cannot read grant views');
SELECT tap.logout();

-- ── Section E (cont.) — "mine only" is the view's identity filter, not RLS ──
-- Two more synthetic grants: a scanner at Room A (080 venue arm: every staff
-- label reads its own venue's roster) and an org_finance member of org A (077
-- affiliate arm: members read their org's roster). Each can read the OTHER
-- person's row in the base table; the grant views must still return only theirs.
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('18700000-0000-4000-8000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.224@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('18700000-0000-4000-8000-0000000000a4', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.a.224@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('18700000-0000-4000-8000-00000000000a', '18700000-0000-4000-8000-0000000000a3', 'org_finance');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('18700000-0000-4000-8000-0000000000aa', '18700000-0000-4000-8000-0000000000a4', 'venue_scanner');
SELECT tap.login('18700000-0000-4000-8000-0000000000a4');
SELECT is((SELECT count(*) FROM venue.staff_role WHERE venue_id = '18700000-0000-4000-8000-0000000000aa'), 2::bigint, 'E8: control — scanner A reads Room A''s whole roster in the base table (manager + itself)');
SELECT is((SELECT string_agg(venue_id::text || ':' || role, ',') FROM venue_api.my_staff_roles), '18700000-0000-4000-8000-0000000000aa:venue_scanner', 'E9: scanner A''s my_staff_roles is exactly its own row, never the manager''s (no role escalation in the app)');
SELECT tap.logout();
SELECT tap.login('18700000-0000-4000-8000-0000000000a3');
SELECT is((SELECT count(*) FROM kernel.org_member WHERE org_id = '18700000-0000-4000-8000-00000000000a'), 2::bigint, 'E10: control — org finance A reads org A''s whole roster in the base table (owner + itself)');
SELECT is((SELECT string_agg(org_id::text || ':' || role, ',') FROM venue_api.my_org_roles), '18700000-0000-4000-8000-00000000000a:org_finance', 'E11: org finance A''s my_org_roles is exactly its own row, never the owner''s');
SELECT tap.logout();

-- ── Section C (cont.) — venues and resale_policies, as the caller ───────────
-- The app reads both on every route (venue scope, policies), so a revoked
-- base column or an emptied view must fail here, not only in the browser.
-- More synthetic rows, as postgres: a DRAFT venue of org A (Room C), a
-- venue-scoped policy on approved Room A, an event-scoped policy on A's DRAFT
-- event e2 (078 catalog_resale_policy_sel_public: a draft parent hides its
-- policy from every client), and a session of e1 whose starts_at, ends_at and
-- doors_at all differ, so a view that maps one base column to another name
-- returns a wrong value (C28-C30).
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('18700000-0000-4000-8000-0000000000cc', '18700000-0000-4000-8000-00000000000a', 'Room C 226', 'brickell', 'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at, doors_at) VALUES
  ('18700000-0000-4000-8000-0000000000f4', '18700000-0000-4000-8000-0000000000e1', 'Late 226',
   '2031-01-10 20:00:00+00', '2031-01-10 23:30:00+00', '2031-01-10 19:00:00+00');
INSERT INTO catalog.resale_policy (policy_id, scope_kind, venue_id, event_id, mode, price_cap_bps, royalty_bps, version, effective_from) VALUES
  ('18700000-0000-4000-8000-000000000031', 'venue', '18700000-0000-4000-8000-0000000000aa', NULL, 'fixed_cap', 10000, 500, 1, '2026-01-01 00:00:00+00'),
  ('18700000-0000-4000-8000-000000000032', 'event', NULL, '18700000-0000-4000-8000-0000000000e2', 'buy_now', NULL, NULL, 1, '2026-01-01 00:00:00+00');

-- venue_manager at Room A: both approved rooms, not org A's draft Room C (080 venue arm is per venue); Room A's policy, not the draft event's.
SELECT tap.login('18700000-0000-4000-8000-0000000000a1');
SELECT is((SELECT count(*) FROM venue_api.venues WHERE venue_id IN ('18700000-0000-4000-8000-0000000000aa','18700000-0000-4000-8000-0000000000bb')), 2::bigint, 'C22: manager A reads both approved rooms (Room A, Room B) through venue_api.venues');
SELECT is((SELECT count(*) FROM venue_api.venues WHERE venue_id = '18700000-0000-4000-8000-0000000000cc'), 0::bigint, 'C23: manager A cannot read org A''s draft Room C (no role there)');
SELECT is((SELECT count(*) FROM venue_api.resale_policies WHERE policy_id IN ('18700000-0000-4000-8000-000000000031','18700000-0000-4000-8000-000000000032')), 1::bigint, 'C24: manager A reads Room A''s venue policy and not the draft event''s policy (078 sel_public only)');
SELECT tap.logout();

-- org_owner of A: the draft venue IS visible (078 catalog_venue_sel_org).
SELECT tap.login('18700000-0000-4000-8000-0000000000a2');
SELECT is((SELECT count(*) FROM venue_api.venues WHERE org_id = '18700000-0000-4000-8000-00000000000a'), 2::bigint, 'C25: org owner A sees Room A and its draft Room C');
SELECT tap.logout();

-- outsider (authenticated, no grants): approved venues only; the venue policy only; values come from the matching base columns.
SELECT tap.login('18700000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*) FROM venue_api.venues WHERE venue_id IN ('18700000-0000-4000-8000-0000000000aa','18700000-0000-4000-8000-0000000000bb','18700000-0000-4000-8000-0000000000cc')), 2::bigint, 'C26: outsider reads the two approved rooms and not the draft Room C');
SELECT is((SELECT count(*) FROM venue_api.resale_policies WHERE policy_id IN ('18700000-0000-4000-8000-000000000031','18700000-0000-4000-8000-000000000032')), 1::bigint, 'C27: outsider reads Room A''s venue policy only');
SELECT is((SELECT v.org_id::text || '|' || v.name || '|' || v.neighborhood || '|' || v.approval_status
             FROM venue_api.venues v WHERE v.venue_id = '18700000-0000-4000-8000-0000000000aa'),
          '18700000-0000-4000-8000-00000000000a|Room A 187|wynwood|approved',
          'C28: outsider reads Room A''s org_id, name, neighborhood and approval_status from the matching base columns');
SELECT is((SELECT p.scope_kind || '|' || p.venue_id::text || '|' || coalesce(p.event_id::text, '-') || '|' || p.mode || '|'
                  || p.price_cap_bps::text || '|' || p.royalty_bps::text || '|' || p.version::text || '|'
                  || to_char(p.effective_from AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI')
             FROM venue_api.resale_policies p WHERE p.policy_id = '18700000-0000-4000-8000-000000000031'),
          'venue|18700000-0000-4000-8000-0000000000aa|-|fixed_cap|10000|500|1|2026-01-01 00:00',
          'C29: outsider reads the venue policy''s scope, target, mode, cap, royalty, version and effective_from from the matching base columns');
SELECT is((SELECT s.event_id::text || '|' || s.session_label || '|'
                  || to_char(s.starts_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || '|'
                  || to_char(s.ends_at   AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || '|'
                  || to_char(s.doors_at  AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI') || '|' || s.status
             FROM venue_api.event_sessions s WHERE s.session_id = '18700000-0000-4000-8000-0000000000f4'),
          '18700000-0000-4000-8000-0000000000e1|Late 226|2031-01-10 20:00|2031-01-10 23:30|2031-01-10 19:00|scheduled',
          'C30: outsider reads the session''s starts_at, ends_at and doors_at from the matching base columns (a swapped-column view fails here)');
SELECT tap.logout();

-- ── Section D — the views never widen ─────────────────────────────────────────
SELECT tap.login('18700000-0000-4000-8000-0000000000b1');
SELECT is((SELECT count(*) FROM venue_api.events), (SELECT count(*) FROM catalog.event), 'D1: finance B: events view row count equals base-table row count under the same RLS');
SELECT is((SELECT count(*) FROM venue_api.ticket_types), (SELECT count(*) FROM venue.ticket_type), 'D2: finance B: ticket_types view equals base table under RLS');
SELECT is((SELECT count(*) FROM venue_api.inventory_batches), (SELECT count(*) FROM venue.inventory_batch), 'D3: finance B: inventory_batches view equals base table under RLS');
SELECT tap.logout();
SELECT tap.login('18700000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*) FROM venue_api.events), (SELECT count(*) FROM catalog.event), 'D4: outsider: events view equals base table under RLS');
SELECT is((SELECT count(*) FROM venue_api.ticket_types), (SELECT count(*) FROM venue.ticket_type), 'D5: outsider: ticket_types view equals base table under RLS');
SELECT tap.logout();
-- venues and resale_policies the same way (the fixture makes both base counts non-zero for these callers).
SELECT tap.login('18700000-0000-4000-8000-0000000000b1');
SELECT is((SELECT count(*) FROM venue_api.venues), (SELECT count(*) FROM catalog.venue), 'D6: finance B: venues view equals base table under RLS');
SELECT is((SELECT count(*) FROM venue_api.resale_policies), (SELECT count(*) FROM catalog.resale_policy), 'D7: finance B: resale_policies view equals base table under RLS');
SELECT tap.logout();
SELECT tap.login('18700000-0000-4000-8000-0000000000c1');
SELECT is((SELECT count(*) FROM venue_api.venues), (SELECT count(*) FROM catalog.venue), 'D8: outsider: venues view equals base table under RLS');
SELECT is((SELECT count(*) FROM venue_api.resale_policies), (SELECT count(*) FROM catalog.resale_policy), 'D9: outsider: resale_policies view equals base table under RLS');
SELECT tap.logout();


-- ── Section F — the exact privilege surface (CI's only gate for venue_api) ──
-- expected_grants.txt / the grant-decision manifest read `public` only. These
-- read the catalog directly (not information_schema, which filters by the
-- reader's privileges) and exclude only the owner's implicit rights.
SELECT set_eq(
  $$ SELECT c.relname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE n.nspname = 'venue_api' AND a.grantee <> c.relowner
     UNION ALL
     SELECT c.relname || '.' || att.attname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_attribute att
       JOIN pg_class c ON c.oid = att.attrelid
       JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(att.attacl) a
      WHERE n.nspname = 'venue_api' AND att.attnum > 0 AND att.attacl IS NOT NULL $$,
  $$ VALUES ('event_sessions:authenticated:SELECT'), ('events:authenticated:SELECT'),
            ('inventory_batches:authenticated:SELECT'), ('my_org_roles:authenticated:SELECT'),
            ('my_staff_roles:authenticated:SELECT'), ('resale_policies:authenticated:SELECT'),
            ('ticket_types:authenticated:SELECT'), ('venues:authenticated:SELECT') $$,
  'F1: venue_api privilege matrix is exactly SELECT to authenticated on the eight views (no write, no column grant, no anon/service_role/PUBLIC)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_namespace n
      CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
      WHERE n.nspname = 'venue_api' AND a.grantee <> n.nspowner $$,
  $$ VALUES ('authenticated:USAGE') $$,
  'F2: schema venue_api ACL is exactly USAGE to authenticated');
SELECT is((SELECT count(*) FROM pg_default_acl d JOIN pg_namespace n ON n.oid = d.defaclnamespace
            CROSS JOIN LATERAL aclexplode(d.defaclacl) a WHERE n.nspname = 'venue_api'), 0::bigint,
          'F3: no schema-scoped default-ACL row in venue_api grants anything (the migration''s per-schema REVOKE stores none; global defaults are F7)');
SELECT is((SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'venue_api' AND c.relkind = 'v'
             AND NOT EXISTS (SELECT 1 FROM unnest(c.reloptions) o WHERE o = 'security_barrier=true')), 0::bigint, 'F4: every view is security_barrier');
SELECT set_eq(
  $$ SELECT c.relname || '.' || a.attname
       FROM pg_attribute a
       JOIN pg_class c ON c.oid = a.attrelid
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'venue_api' AND a.attnum > 0 AND NOT a.attisdropped $$,
  $$ VALUES ('venues.venue_id'), ('venues.org_id'), ('venues.name'), ('venues.neighborhood'), ('venues.approval_status'),
            ('venues.created_at'), ('venues.updated_at'),
            ('events.event_id'), ('events.venue_id'), ('events.org_id'), ('events.title'), ('events.status'),
            ('events.created_at'), ('events.updated_at'), ('events.age_policy'), ('events.timezone'),  -- 162 (S2) appends age_policy, timezone
            ('event_sessions.session_id'), ('event_sessions.event_id'), ('event_sessions.session_label'),
            ('event_sessions.starts_at'), ('event_sessions.ends_at'), ('event_sessions.doors_at'),
            ('event_sessions.door_open_at'), ('event_sessions.status'), ('event_sessions.created_at'),
            ('event_sessions.updated_at'), ('event_sessions.timezone'), ('event_sessions.starts_at_local'),  -- 162 (S2) appends timezone + three *_local
            ('event_sessions.ends_at_local'), ('event_sessions.doors_at_local'),
            ('resale_policies.policy_id'), ('resale_policies.scope_kind'), ('resale_policies.venue_id'),
            ('resale_policies.event_id'), ('resale_policies.mode'), ('resale_policies.price_cap_bps'),
            ('resale_policies.royalty_bps'), ('resale_policies.version'), ('resale_policies.effective_from'),
            ('resale_policies.created_at'),
            ('ticket_types.ticket_type_id'), ('ticket_types.event_id'), ('ticket_types.kind'), ('ticket_types.name'),
            ('ticket_types.price_minor'), ('ticket_types.currency'), ('ticket_types.visibility'),
            ('ticket_types.created_at'), ('ticket_types.updated_at'), ('ticket_types.display_rank'),  -- 160 (S1) appends display_rank
            ('ticket_types.sale_starts_at'), ('ticket_types.sale_ends_at'), ('ticket_types.on_sale_now'),  -- 162 (S2) appends the sale window + on_sale_now
            ('inventory_batches.batch_id'), ('inventory_batches.ticket_type_id'), ('inventory_batches.event_session_id'),
            ('inventory_batches.release_kind'), ('inventory_batches.is_sharded'), ('inventory_batches.remaining'),
            ('inventory_batches.created_at'), ('inventory_batches.updated_at'),
            ('my_staff_roles.venue_id'), ('my_staff_roles.role'),
            ('my_org_roles.org_id'), ('my_org_roles.role') $$,
  'F5: the views project exactly these 65 columns (55 of 159 + ticket_types.display_rank of 160 + 162''s nine: events.age_policy/timezone, event_sessions.timezone/*_local x3, ticket_types.sale_starts_at/sale_ends_at/on_sale_now; a widened view fails here before it reaches the API)');

-- F6 pins each view's DEFINITION, not only its column names (F5). The expected
-- definitions are the eight SELECTs of migration 20261021120000, copied
-- verbatim into transaction-local temp views (they die with the ROLLBACK).
-- Both sides are deparsed by pg_get_viewdef in this same session, so the
-- comparison needs no stored hash and does not depend on the deparser version.
-- A view that maps a base column to another name (s.ends_at AS starts_at), drops a filter
-- (identity_id = auth.uid()), adds WHERE false or reads another table fails here.
CREATE TEMP VIEW exp_venues AS
  SELECT v.venue_id, v.org_id, v.name, v.neighborhood, v.approval_status, v.created_at, v.updated_at
    FROM catalog.venue v;
CREATE TEMP VIEW exp_events AS
  SELECT e.event_id, e.venue_id, e.org_id, e.title, e.status, e.created_at, e.updated_at,
         e.age_policy, v.timezone   -- 162 (S2): age_policy + the venue's timezone (LEFT JOIN; row set unchanged)
    FROM catalog.event e
    LEFT JOIN catalog.venue v ON v.venue_id = e.venue_id;
CREATE TEMP VIEW exp_event_sessions AS
  SELECT s.session_id, s.event_id, s.session_label, s.starts_at, s.ends_at, s.doors_at,
         s.door_open_at, s.status, s.created_at, s.updated_at,
         v.timezone,   -- 162 (S2): timezone + three *_local texts in the venue's zone
         to_char(s.starts_at AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI') AS starts_at_local,
         to_char(s.ends_at   AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI') AS ends_at_local,
         to_char(s.doors_at  AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI') AS doors_at_local
    FROM catalog.event_session s
    LEFT JOIN catalog.event e ON e.event_id = s.event_id
    LEFT JOIN catalog.venue v ON v.venue_id = e.venue_id;
CREATE TEMP VIEW exp_resale_policies AS
  SELECT p.policy_id, p.scope_kind, p.venue_id, p.event_id, p.mode, p.price_cap_bps,
         p.royalty_bps, p.version, p.effective_from, p.created_at
    FROM catalog.resale_policy p;
CREATE TEMP VIEW exp_ticket_types AS
  SELECT t.ticket_type_id, t.event_id, t.kind, t.name, t.price_minor, t.currency, t.visibility,
         t.created_at, t.updated_at, t.display_rank,   -- 160 (S1): display_rank appended
         t.sale_starts_at, t.sale_ends_at,            -- 162 (S2): the sale window + on_sale_now appended LAST
         venue.ticket_type_on_sale(t.ticket_type_id) AS on_sale_now
    FROM venue.ticket_type t;
CREATE TEMP VIEW exp_inventory_batches AS
  SELECT b.batch_id, b.ticket_type_id, b.event_session_id, b.release_kind, b.is_sharded,
         b.remaining, b.created_at, b.updated_at
    FROM venue.inventory_batch b;
CREATE TEMP VIEW exp_my_staff_roles AS
  SELECT s.venue_id, s.role
    FROM venue.staff_role s
   WHERE s.identity_id = auth.uid();
CREATE TEMP VIEW exp_my_org_roles AS
  SELECT m.org_id, m.role
    FROM kernel.org_member m
   WHERE m.identity_id = auth.uid();
SELECT set_eq(
  $$ SELECT c.relname::text || ':' || md5(pg_get_viewdef(c.oid))
       FROM pg_class c
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'venue_api' AND c.relkind = 'v' $$,
  $$ SELECT substr(c.relname::text, 5) || ':' || md5(pg_get_viewdef(c.oid))
       FROM pg_class c
      WHERE c.relnamespace = pg_my_temp_schema() AND c.relkind = 'v' AND c.relname::text LIKE 'exp\_%' $$,
  'F6: each of the eight view definitions is exactly the migration''s SELECT (deparsed md5 per view)');

-- F7 is the other half of F3. A schema-scoped default can only ADD to the
-- global defaults (076, PFA-1), so what a table or view the owner adds here
-- later receives is decided by the owner's GLOBAL table defaults
-- (defaclnamespace = 0). The eight views were created by the same owner under
-- the same defaults, so a client row here would have been inherited by them at
-- CREATE time, and F1 would fail with F7 for any grant beyond the SELECT to
-- authenticated the views carry anyway. The CI stack carries no TABLE default-ACL entries at
-- all (supabase/ci/parity_grants.sql header). Objects another role creates
-- are not covered by F7. Whoever creates them, A2, A3, F1, F5 and F8 catch an
-- added view, function, granted relation, relation with columns or type. Other
-- object kinds (operators, collations, text-search objects, statistics
-- objects, triggers or rules on the views) are not swept.
SELECT is((SELECT count(*) FROM pg_default_acl d
             CROSS JOIN LATERAL aclexplode(d.defaclacl) a
            WHERE d.defaclnamespace = 0
              AND d.defaclobjtype = 'r'
              AND d.defaclrole = (SELECT n.nspowner FROM pg_namespace n WHERE n.nspname = 'venue_api')
              AND (a.grantee = 0 OR a.grantee IN (SELECT r.oid FROM pg_roles r WHERE r.rolname IN ('anon', 'authenticated')))),
          0::bigint,
          'F7: no GLOBAL table default privilege of the venue_api owner grants PUBLIC, anon or authenticated (with F3: a table or view the owner adds later starts with no client grant)');

-- F8 sweeps pg_type. A2 counts pg_views and A3 pg_proc. F1 lists only relations
-- with a non-owner ACL entry, and F5 only relations with columns. An enum,
-- domain, range or multirange type exists only in pg_type, and a table with no
-- columns and no grant leaves A2, A3, F1 and F5 green. The only types the
-- migration creates are each view's row type (pg_class.reltype) and its array
-- type (typarray of that row type). A ninth view is A2's, not F8's.
SELECT is((SELECT count(*) FROM pg_type t
             JOIN pg_namespace n ON n.oid = t.typnamespace
            WHERE n.nspname = 'venue_api'
              AND NOT EXISTS (SELECT 1 FROM pg_class c
                                JOIN pg_type rt ON rt.oid = c.reltype
                               WHERE c.relnamespace = t.typnamespace AND c.relkind = 'v'
                                 AND t.oid IN (rt.oid, rt.typarray))),
          0::bigint,
          'F8: no type in venue_api other than the eight views'' row types and their array types (an enum, domain, range, composite type or table row type fails here)');

SELECT * FROM finish();
ROLLBACK;
