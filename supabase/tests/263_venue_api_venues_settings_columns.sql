-- ============================================================================
-- 263_venue_api_venues_settings_columns.sql — migration 20261030094000 (registry 195).
--
-- Registry 195 (allocated by Claude A 2026-10-30 after the production Settings finding); pgTAP 263
-- is the next free number after 262 (#202 / 193; A to confirm). E reviews the exact head. DARK.
-- 226 keeps the schema-wide venue_api pins (F5 column set, F6 definitions); this file pins 195.
--
--   Section A  shape: venue_api.venues projects 159's seven columns in order, then address (text),
--              capacity_hint (integer), timezone (text) LAST; security_invoker AND security_barrier
--              still set; ACL still SELECT to authenticated only; comment unchanged; the
--              definition hashes to 195's md5 under search_path = ''.
--   Section B  RLS through the view (security_invoker: the caller's policies on catalog.venue):
--              a non-member sees ZERO rows for a draft room (negative control: a definer-rights
--              view would show it); the org's member reads the room's STORED address, capacity
--              hint and time zone (a non-default zone, so a default or a swapped column fails);
--              the room's venue_manager reads them too; a non-member reads an APPROVED room's
--              three values (public under catalog_venue_sel_anon — unchanged, now projected);
--              for each caller the view returns exactly the base table's rows; anon is stopped
--              at the schema (no USAGE on venue_api).
--
-- Reads as callers go through tap._val263 (the query's text, or {"error": "<SQLSTATE>|<SQLERRM>"}),
-- so a missing column reads `not ok` instead of aborting the file (232/234/261/262 pattern).
--
-- Fixture: synthetic rows as postgres, tag 26300000-…, rolled back. Org A (owner 101) runs room
-- R1 (DRAFT; manager 111; address '100 Draft Ave 263', capacity_hint 420, timezone
-- 'America/Chicago'). Org B runs room R2 (APPROVED; '200 Public St 263', 150,
-- 'America/Los_Angeles'). Fan 199 belongs to neither.
--
-- RED, measured on main c4f48885 WITHOUT 195 (a154c_green + main's migrations): 14 emitted, nothing
-- aborts — 8 ok (A2 A3 A4 A6 B1 B5 B6 B7: options, ACL, comment, base grants and RLS are what 195
-- must leave untouched) + 6 not ok (A1 A5 A7; B2 B3 B4 read columns that do not exist yet -> 42703).
-- Gate-removal mutants: see the PR (security_invoker off; a column mapped from the wrong base column).
-- ============================================================================
BEGIN;
SELECT plan(14);

CREATE TABLE tap.memo_263 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._val263(q text) RETURNS text
LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE || '|' || SQLERRM)::text; END $m$;
-- a view's deparse depends on search_path: hash it under a pinned '' path, the migration's own measure
CREATE FUNCTION tap._viewmd5_263(r regclass) RETURNS text
LANGUAGE sql SET search_path = '' AS
$m$ SELECT pg_catalog.md5(pg_catalog.pg_get_viewdef(r)) $m$;
GRANT EXECUTE ON FUNCTION tap._val263(text) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at)
SELECT u.id::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', u.email,
       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()
  FROM (VALUES ('26300000-0000-4000-8000-000000000101', 'owner.a.263@test.local'),
               ('26300000-0000-4000-8000-000000000111', 'mgr.r1.263@test.local'),
               ('26300000-0000-4000-8000-000000000199', 'fan.263@test.local')) u(id, email)
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('26300000-0000-4000-8000-00000000000a', 'Org A 263', 'Org A 263', 'active'),
  ('26300000-0000-4000-8000-00000000000b', 'Org B 263', 'Org B 263', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('26300000-0000-4000-8000-00000000000a', '26300000-0000-4000-8000-000000000101', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, capacity_hint, approval_status, timezone) VALUES
  ('26300000-0000-4000-8000-0000000000a1', '26300000-0000-4000-8000-00000000000a', 'R1 draft 263',  'wynwood',  '100 Draft Ave 263', 420, 'draft',    'America/Chicago'),
  ('26300000-0000-4000-8000-0000000000b2', '26300000-0000-4000-8000-00000000000b', 'R2 public 263', 'brickell', '200 Public St 263', 150, 'approved', 'America/Los_Angeles');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('26300000-0000-4000-8000-0000000000a1', '26300000-0000-4000-8000-000000000111', 'venue_manager');

-- ── Section A — shape ────────────────────────────────────────────────────────
SELECT is((SELECT string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' ORDER BY a.attnum)
             FROM pg_attribute a WHERE a.attrelid = 'venue_api.venues'::regclass AND a.attnum > 0 AND NOT a.attisdropped),
  'venue_id:uuid,org_id:uuid,name:text,neighborhood:text,approval_status:text,created_at:timestamp with time zone,updated_at:timestamp with time zone,address:text,capacity_hint:integer,timezone:text',
  'A1: venue_api.venues projects 159''s seven columns in order, then address (text), capacity_hint (integer), timezone (text) LAST');
SELECT is((SELECT array_to_string(array(SELECT o FROM unnest(c.reloptions) o ORDER BY o), ',') FROM pg_class c WHERE c.oid = 'venue_api.venues'::regclass),
  'security_barrier=true,security_invoker=true',
  'A2: security_invoker and security_barrier are both still set (the caller''s RLS applies)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE c.oid = 'venue_api.venues'::regclass AND a.grantee <> c.relowner
     UNION ALL
     SELECT 'column:' || att.attname FROM pg_attribute att
      WHERE att.attrelid = 'venue_api.venues'::regclass AND att.attnum > 0 AND att.attacl IS NOT NULL $$,
  $$ VALUES ('authenticated:SELECT') $$,
  'A3: the ACL is still exactly SELECT to authenticated (no write, no column grant, no anon/service_role/PUBLIC)');
SELECT is(obj_description('venue_api.venues'::regclass, 'pg_class') || '|' || (SELECT relowner::regrole::text FROM pg_class WHERE oid = 'venue_api.venues'::regclass),
  'catalog.venue, granted columns only; caller''s RLS applies.|postgres',
  'A4: the comment is unchanged and the view is still owned by postgres (159''s applied owner)');
SELECT is(tap._viewmd5_263('venue_api.venues'), '383f313b3c15e6291e6fab9aa6e456ca',
  'A5: the definition hashes to 195''s md5 under search_path = '''' (the pre-flight / rollback anchor)');
SELECT is((SELECT count(*)::int FROM (VALUES ('address'), ('capacity_hint'), ('timezone')) n(col)
            WHERE has_column_privilege('authenticated', 'catalog.venue', n.col, 'SELECT')), 3,
  'A6: authenticated holds column SELECT on catalog.venue.address / capacity_hint / timezone (the security_invoker view needs it)');
SELECT is((SELECT count(*)::int FROM information_schema.columns
            WHERE table_schema = 'venue_api' AND table_name = 'venues' AND column_name IN ('address','capacity_hint','timezone')), 3,
  'A7: information_schema reports the three new columns on venue_api.venues');

-- ── Section B — RLS through the view, as each caller ──────────────────────────
SELECT tap.login('26300000-0000-4000-8000-000000000199');
SELECT is(tap._val263($q$SELECT count(*)::text FROM venue_api.venues WHERE venue_id = '26300000-0000-4000-8000-0000000000a1'$q$), '0',
  'B1: a non-member sees ZERO rows for the draft room through the view (negative control: security_invoker, the caller''s RLS)');
SELECT is(tap._val263($q$SELECT address || '|' || capacity_hint || '|' || timezone FROM venue_api.venues WHERE venue_id = '26300000-0000-4000-8000-0000000000b2'$q$),
  '200 Public St 263|150|America/Los_Angeles',
  'B2: a non-member reads an APPROVED room''s stored address, capacity hint and time zone (public under catalog_venue_sel_anon, as in catalog.venue)');
SELECT is(tap._val263($q$SELECT ((SELECT count(*) FROM venue_api.venues) = (SELECT count(*) FROM catalog.venue))::text$q$), 'true',
  'B5: for the non-member the view returns exactly the base table''s rows (it never widens)');
SELECT tap.logout();
SELECT tap.login('26300000-0000-4000-8000-000000000101');
SELECT is(tap._val263($q$SELECT address || '|' || capacity_hint || '|' || timezone FROM venue_api.venues WHERE venue_id = '26300000-0000-4000-8000-0000000000a1'$q$),
  '100 Draft Ave 263|420|America/Chicago',
  'B3: the org''s member reads the draft room''s STORED address, capacity hint and time zone (America/Chicago, not the default)');
SELECT tap.logout();
SELECT tap.login('26300000-0000-4000-8000-000000000111');
SELECT is(tap._val263($q$SELECT address || '|' || capacity_hint || '|' || timezone FROM venue_api.venues WHERE venue_id = '26300000-0000-4000-8000-0000000000a1'$q$),
  '100 Draft Ave 263|420|America/Chicago',
  'B4: the room''s venue_manager reads the same stored values (catalog_venue_sel_venue)');
SELECT is(tap._val263($q$SELECT ((SELECT count(*) FROM venue_api.venues) = (SELECT count(*) FROM catalog.venue))::text$q$), 'true',
  'B6: for the venue_manager the view returns exactly the base table''s rows');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT count(*) FROM venue_api.venues$$, '42501', 'permission denied for schema venue_api',
  'B7: anon is stopped at the schema wall (no USAGE on venue_api)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
