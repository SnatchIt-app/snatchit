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
--   tag). Nine assertions are new (plan 47 -> 56), each added because a planted
--   mutant of the migration survived the 47 (see
--   docs/venue-dashboard/VENUE_API_PROVISIONAL_MIGRATION.md §4.4):
--     E8–E11 the "mine only" filter of my_staff_roles / my_org_roles is the
--            view's own `identity_id = auth.uid()`, not RLS: a scanner can read
--            its venue's whole roster in the base table but sees only its own
--            row in the view (no UI role escalation); same for an org member.
--     F1–F5 the exact privilege surface. supabase/ci/expected_grants.txt and
--            the grant-decision manifest read `public` only, so this file is
--            the CI gate for venue_api: exact relation + column ACL, exact
--            schema ACL, no default-ACL grant in the schema, security_barrier
--            on every view, and the exact projected column set.
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
SELECT plan(56);
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
          'F3: no default privilege is granted inside venue_api (a later object gets nothing implicitly)');
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
            ('events.created_at'), ('events.updated_at'),
            ('event_sessions.session_id'), ('event_sessions.event_id'), ('event_sessions.session_label'),
            ('event_sessions.starts_at'), ('event_sessions.ends_at'), ('event_sessions.doors_at'),
            ('event_sessions.door_open_at'), ('event_sessions.status'), ('event_sessions.created_at'),
            ('event_sessions.updated_at'),
            ('resale_policies.policy_id'), ('resale_policies.scope_kind'), ('resale_policies.venue_id'),
            ('resale_policies.event_id'), ('resale_policies.mode'), ('resale_policies.price_cap_bps'),
            ('resale_policies.royalty_bps'), ('resale_policies.version'), ('resale_policies.effective_from'),
            ('resale_policies.created_at'),
            ('ticket_types.ticket_type_id'), ('ticket_types.event_id'), ('ticket_types.kind'), ('ticket_types.name'),
            ('ticket_types.price_minor'), ('ticket_types.currency'), ('ticket_types.visibility'),
            ('ticket_types.created_at'), ('ticket_types.updated_at'),
            ('inventory_batches.batch_id'), ('inventory_batches.ticket_type_id'), ('inventory_batches.event_session_id'),
            ('inventory_batches.release_kind'), ('inventory_batches.is_sharded'), ('inventory_batches.remaining'),
            ('inventory_batches.created_at'), ('inventory_batches.updated_at'),
            ('my_staff_roles.venue_id'), ('my_staff_roles.role'),
            ('my_org_roles.org_id'), ('my_org_roles.role') $$,
  'F5: the views project exactly these 55 columns (a widened view fails here before it reaches the API)');

SELECT * FROM finish();
ROLLBACK;
