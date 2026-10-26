-- ============================================================================
-- 228_venue_cmd_transport.sql — migration 20261022110000 (registry 161).
--
-- Registry 161 / pgTAP 228 — assigned by Claude A 2026-10-22 (registry 573850a4).
-- A reviews before this leaves draft. DARK: applied nowhere; venue_cmd is not
-- exposed (owner setting).
--
-- The CI grant gates (grant-decision manifest, expected_grants.txt, Gate-2
-- census) read `public` only, so THIS FILE is the gate for venue_cmd, the way
-- 226 (F1-F8) is for venue_api and 246 (A5, C1-C3) for 176: the schema ACL and
-- every function's ACL are pinned by has_schema_privilege /
-- has_function_privilege for anon, authenticated, service_role and PUBLIC, and
-- by an exact aclexplode matrix, over EVERY function in the schema (not a fixed
-- list), so a wrapper added later without its REVOKE fails here.
--
--   Section A  shape + ACL: schema exists; exactly the six wrappers (and no
--              create_inventory_batch — withheld until S2's E-33 receipt); every
--              function prosecdef=false, LANGUAGE sql, search_path pinned,
--              delegating to venue.<same name>; argument lists and result types
--              equal the targets'; no relation, no type; schema USAGE exactly
--              authenticated; EXECUTE exactly authenticated on each; no anon, no
--              PUBLIC, no service_role, no DEFAULTED proacl; venue_api still has
--              no function; no default-ACL row scoped to venue_cmd.
--   Section B  behaviour as the caller: a wrapper call yields the same result
--              and the same audit row (action, actor, reason, before/after) as
--              the direct call; counters through the wrapper equal the direct
--              rows; refusals propagate UNCHANGED (42501, P0002, the exact
--              precondition_failed messages, E-76's refusal); anon and
--              unauthenticated are refused; noop is noop with no audit row.
--
-- Fixture: 226/246 style, tag 22800000-…: Org A / Room V1 (owner, manager, fan),
-- e1 on_sale with a public tier t11 (+ batch c1 300/6/120) and a hidden tier
-- t12, e2 completed with t21; Org B / Room V2 re-operated from Org A with Org A's
-- event e5 (the E-76 refusal through the wrapper).
--
-- Expected on 160 WITHOUT 161 (RED, predicted before the first run; the
-- reconciliation is in the evidence dir): A1-A3, A5-A7, A10-A12, A14-A20, A23
-- fail (18; schema and functions absent — A11/A12/A13/A15/A16 are written
-- NULL-safe so they read `not ok` instead of aborting); A4, A8, A9, A21, A22
-- pass (5; A4/A8/A9/A22 by vacuity, A21 genuinely). A13 fails (NULL-safe NOT
-- coalesce(…, true)). Then B1 — the first call of a missing wrapper — raises
-- 42883 and aborts the transaction; B2-B27 are not emitted. Predicted RED run:
-- 23 emitted = 18 not ok + 5 ok; plan 50 unmet.
-- ============================================================================
BEGIN;
SELECT plan(50);

CREATE TABLE tap.memo_228 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store228(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_228 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch228(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_228 WHERE k = $1 $m$;
GRANT EXECUTE ON FUNCTION tap._store228(text, text), tap._fetch228(text) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('22800000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.228@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22800000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.228@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22800000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.228@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22800000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.228@test.local',      '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('22800000-0000-4000-8000-00000000000a', 'Org A 228', 'Org A 228', 'active'),
  ('22800000-0000-4000-8000-00000000000b', 'Org B 228', 'Org B 228', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('22800000-0000-4000-8000-00000000000a', '22800000-0000-4000-8000-000000000101', 'org_owner');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('22800000-0000-4000-8000-0000000000a1', '22800000-0000-4000-8000-00000000000a', 'Room V1 228', 'wynwood',  'approved'),
  ('22800000-0000-4000-8000-0000000000a2', '22800000-0000-4000-8000-00000000000a', 'Room V2 228', 'brickell', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('22800000-0000-4000-8000-0000000000a1', '22800000-0000-4000-8000-000000000111', 'venue_manager'),
  ('22800000-0000-4000-8000-0000000000a2', '22800000-0000-4000-8000-000000000121', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('22800000-0000-4000-8000-0000000000e1', '22800000-0000-4000-8000-0000000000a1', '22800000-0000-4000-8000-00000000000a', 'V1 on sale 228',   'on_sale'),
  ('22800000-0000-4000-8000-0000000000e2', '22800000-0000-4000-8000-0000000000a1', '22800000-0000-4000-8000-00000000000a', 'V1 completed 228', 'completed'),
  ('22800000-0000-4000-8000-0000000000e5', '22800000-0000-4000-8000-0000000000a2', '22800000-0000-4000-8000-00000000000a', 'V2 (A event) 228', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('22800000-0000-4000-8000-0000000000f1', '22800000-0000-4000-8000-0000000000e1', now() + interval '3 days', 'scheduled'),
  ('22800000-0000-4000-8000-0000000000f2', '22800000-0000-4000-8000-0000000000e2', now() - interval '3 days', 'completed'),
  ('22800000-0000-4000-8000-0000000000f5', '22800000-0000-4000-8000-0000000000e5', now() + interval '7 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('22800000-0000-4000-8000-000000000011', '22800000-0000-4000-8000-0000000000e1', 'admission', 'GA 228',        2500, 'public'),
  ('22800000-0000-4000-8000-000000000012', '22800000-0000-4000-8000-0000000000e1', 'admission', 'Hidden 228',    1800, 'hidden'),
  ('22800000-0000-4000-8000-000000000021', '22800000-0000-4000-8000-0000000000e2', 'admission', 'GA done 228',   2700, 'public'),
  ('22800000-0000-4000-8000-000000000051', '22800000-0000-4000-8000-0000000000e5', 'admission', 'GA V2 228',     4000, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('22800000-0000-4000-8000-0000000000c1', '22800000-0000-4000-8000-000000000011', '22800000-0000-4000-8000-0000000000f1', 'public_sale', 300, 6, 120),
  ('22800000-0000-4000-8000-0000000000c5', '22800000-0000-4000-8000-000000000051', '22800000-0000-4000-8000-0000000000f5', 'public_sale', 200, 0, 15);
-- the re-operation of Room V2 (Org A -> Org B); e5 keeps org_id = A
UPDATE catalog.venue SET org_id = '22800000-0000-4000-8000-00000000000b'
 WHERE venue_id = '22800000-0000-4000-8000-0000000000a2';

-- ── Section A — shape + ACL ──────────────────────────────────────────────────
SELECT has_schema('venue_cmd', 'A1: schema venue_cmd exists');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_cmd'), 11,
  -- 2026-10-26 (registry 162, S2): 6 -> 11 (+set_venue_timezone, set_event_age_policy, set_session_sales_capacity, set_ticket_type_sale_window, ticket_type_on_sale).
  'A2: exactly ELEVEN functions in venue_cmd (161''s six + 162''s five)');
SELECT set_eq(
  $$ SELECT p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_cmd' $$,
  $$ VALUES ('create_ticket_type(uuid, text, text, integer, text, text)'), ('set_ticket_type_price(uuid, integer, text, text)'),
            ('set_ticket_type_visibility(uuid, text, text, text)'), ('set_ticket_type_rank(uuid, smallint, text)'),
            ('set_batch_capacity(uuid, integer, text, text)'), ('get_inventory_counters(uuid)'),
            -- 162 (S2)
            ('set_venue_timezone(uuid, text, text, text)'), ('set_event_age_policy(uuid, text, text, text)'),
            ('set_session_sales_capacity(uuid, integer, text, text)'),
            ('set_ticket_type_sale_window(uuid, timestamp with time zone, timestamp with time zone, text, text)'),
            ('ticket_type_on_sale(uuid, timestamp with time zone)') $$,
  'A3: exactly these eleven signatures');
SELECT hasnt_function('venue_cmd'::name, 'create_inventory_batch'::name, ARRAY['uuid','uuid','text','integer','integer','text']::name[],
  'A4: no create_inventory_batch wrapper (withheld until S2''s E-33 receipt)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_cmd' AND NOT p.prosecdef), 11,
  'A5: every function has prosecdef = false (SECURITY INVOKER) — counted positively, eleven');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND l.lanname = 'sql'), 11,
  'A6: every function is LANGUAGE sql (no logic can hide in a wrapper)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proconfig::text LIKE '%search_path=%'), 11,
  'A7: every function pins search_path');
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'venue_cmd'), 0,
  'A8: venue_cmd holds NO relation of any kind (no table, view, sequence, index)');
SELECT is((SELECT count(*)::int FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = 'venue_cmd'), 0,
  'A9: venue_cmd holds NO type (RETURNS TABLE creates none; an enum/domain/composite added later fails here)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
      WHERE n.nspname = 'venue_cmd' AND a.grantee <> n.nspowner $$,
  $$ VALUES ('authenticated:USAGE') $$,
  'A10: schema venue_cmd ACL is exactly USAGE to authenticated (no CREATE, no anon, no PUBLIC, no service_role)');
-- has_schema_privilege by oid (NULL-safe on the chain without 161: `not ok`, not an abort)
SELECT ok(coalesce((SELECT has_schema_privilege('authenticated', n.oid, 'USAGE') FROM pg_namespace n WHERE n.nspname = 'venue_cmd'), false),
  'A11: authenticated has USAGE on venue_cmd');
SELECT ok(NOT coalesce((SELECT has_schema_privilege('anon', n.oid, 'USAGE') FROM pg_namespace n WHERE n.nspname = 'venue_cmd'), true),
  'A12: anon has NO USAGE on venue_cmd');
SELECT ok(NOT coalesce((SELECT has_schema_privilege('service_role', n.oid, 'USAGE') FROM pg_namespace n WHERE n.nspname = 'venue_cmd'), true),
  'A13: service_role has NO USAGE on venue_cmd (no server-side caller of these verbs)');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd' AND a.grantee <> p.proowner $$,
  $$ VALUES ('create_ticket_type:authenticated:EXECUTE'), ('set_ticket_type_price:authenticated:EXECUTE'),
            ('set_ticket_type_visibility:authenticated:EXECUTE'), ('set_ticket_type_rank:authenticated:EXECUTE'),
            ('set_batch_capacity:authenticated:EXECUTE'), ('get_inventory_counters:authenticated:EXECUTE'),
            ('set_venue_timezone:authenticated:EXECUTE'), ('set_event_age_policy:authenticated:EXECUTE'),  -- 162
            ('set_session_sales_capacity:authenticated:EXECUTE'), ('set_ticket_type_sale_window:authenticated:EXECUTE'),
            ('ticket_type_on_sale:authenticated:EXECUTE') $$,
  'A14: the function ACL matrix is exactly EXECUTE to authenticated on each of the eleven (no PUBLIC, anon, service_role)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND has_function_privilege('authenticated', p.oid, 'EXECUTE')), 11,
  'A15: has_function_privilege(authenticated, EXECUTE) is true on all eleven');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
              AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')), 11,
  'A16: has_function_privilege(anon|service_role, EXECUTE) is false on all eleven');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proacl IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)), 11,
  'A17: no proacl is DEFAULTED and PUBLIC holds nothing on any of the eleven (the SEC-2/F2 failure mode cannot occur here)');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            JOIN pg_proc t ON t.proname = w.proname AND t.pronamespace IN ('venue'::regnamespace, 'catalog'::regnamespace)  -- 162: three wrappers target catalog.*
            WHERE n.nspname = 'venue_cmd'
              AND pg_get_function_identity_arguments(w.oid) = pg_get_function_identity_arguments(t.oid)), 11,
  'A18: each wrapper''s argument list (names and types) equals its venue/catalog target''s');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            JOIN pg_proc t ON t.proname = w.proname AND t.pronamespace IN ('venue'::regnamespace, 'catalog'::regnamespace)
            WHERE n.nspname = 'venue_cmd'
              AND pg_get_function_result(w.oid) = pg_get_function_result(t.oid)), 11,
  'A19: each wrapper''s result type equals its venue/catalog target''s');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace n ON n.oid = w.pronamespace
            WHERE n.nspname = 'venue_cmd' AND (w.prosrc LIKE '%venue.' || w.proname || '(%' OR w.prosrc LIKE '%catalog.' || w.proname || '(%')), 11,
  'A20: each wrapper delegates to venue.<same name> or catalog.<same name> (162)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_api'), 0,
  'A21: venue_api still holds no function (the transport did not land in the read schema; 226 A3 stays true)');
SELECT is((SELECT count(*)::int FROM pg_default_acl d JOIN pg_namespace n ON n.oid = d.defaclnamespace WHERE n.nspname = 'venue_cmd'), 0,
  'A22: no default-ACL row is scoped to venue_cmd (the migration stores none; A2/A5/A14/A16/A17 sweep whatever is added later)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd'
              AND p.provolatile = CASE WHEN p.proname IN ('get_inventory_counters','ticket_type_on_sale') THEN 's' ELSE 'v' END), 11,
  'A23: the two read wrappers (counters, ticket_type_on_sale) are STABLE and the nine command wrappers are VOLATILE');

-- ── Section B — behaviour as the caller ─────────────────────────────────────
SELECT tap.login('22800000-0000-4000-8000-000000000111');
SELECT is(venue_cmd.set_ticket_type_rank('22800000-0000-4000-8000-000000000011', 7::smallint, 'ck228-r-1'),
  jsonb_build_object('status','ok','ticket_type_id','22800000-0000-4000-8000-000000000011','display_rank',7),
  'B1: the manager ranks t11 through the WRAPPER — the definer''s result, unchanged');
SELECT is(venue.set_ticket_type_rank('22800000-0000-4000-8000-000000000012', 7::smallint, 'ck228-r-2'),
  jsonb_build_object('status','ok','ticket_type_id','22800000-0000-4000-8000-000000000012','display_rank',7),
  'B2: the same call DIRECT on t12 — same shape');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change'
            AND subject_id = '22800000-0000-4000-8000-000000000011'), 1,
  'B3: exactly one audit row for the wrapper call');
SELECT is((SELECT action || '|' || actor_identity::text || '|' || reason_code || '|' || before::text || '|' || after::text
             FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change' AND subject_id = '22800000-0000-4000-8000-000000000011'),
          (SELECT action || '|' || actor_identity::text || '|' || reason_code || '|' || before::text || '|' || after::text
             FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change' AND subject_id = '22800000-0000-4000-8000-000000000012'),
  'B4: the wrapper''s audit row equals the direct call''s in action, actor, reason, before and after (the definer wrote both as the same caller)');
SELECT is((SELECT actor_identity FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change' AND subject_id = '22800000-0000-4000-8000-000000000011'),
          '22800000-0000-4000-8000-000000000111'::uuid,
  'B5: the audited actor is the caller (auth.uid() seen through SECURITY INVOKER + the definer), not the wrapper''s owner');
SELECT tap.login('22800000-0000-4000-8000-000000000111');
SELECT is((venue_cmd.set_ticket_type_visibility('22800000-0000-4000-8000-000000000012', 'public', 'launch', 'ck228-v-1') ->> 'visibility'), 'public',
  'B6: set_ticket_type_visibility through the wrapper');
SELECT is((venue_cmd.set_ticket_type_price('22800000-0000-4000-8000-000000000011', 2600, 'demand', 'ck228-p-1') ->> 'price_minor'), '2600',
  'B7: set_ticket_type_price through the wrapper');
SELECT is((venue_cmd.set_batch_capacity('22800000-0000-4000-8000-0000000000c1', 350, 'expansion', 'ck228-c-1') ->> 'capacity'), '350',
  'B8: set_batch_capacity through the wrapper');
SELECT tap._store228('wtt',
  (venue_cmd.create_ticket_type('22800000-0000-4000-8000-0000000000e1', 'admission', 'Wrapped GA 228', 2000, 'hidden', 'ck228-t-1') ->> 'ticket_type_id'));
SELECT ok((SELECT count(*) = 1 FROM venue.ticket_type WHERE ticket_type_id = tap._fetch228('wtt')::uuid AND name = 'Wrapped GA 228'),
  'B9: create_ticket_type through the wrapper creates the row');
SELECT is((SELECT string_agg(batch_id::text || '|' || capacity || '|' || held || '|' || sold || '|' || remaining, ';' ORDER BY batch_id)
             FROM venue_cmd.get_inventory_counters('22800000-0000-4000-8000-0000000000e1')),
          (SELECT string_agg(batch_id::text || '|' || capacity || '|' || held || '|' || sold || '|' || remaining, ';' ORDER BY batch_id)
             FROM venue.get_inventory_counters('22800000-0000-4000-8000-0000000000e1')),
  'B10: get_inventory_counters through the wrapper equals the direct rows');
SELECT is((SELECT string_agg(batch_id::text || '|' || capacity || '|' || held || '|' || sold || '|' || remaining, ';' ORDER BY batch_id)
             FROM venue_cmd.get_inventory_counters('22800000-0000-4000-8000-0000000000e1')),
  '22800000-0000-4000-8000-0000000000c1|350|6|120|224',
  'B11: …and equals the raw constants after B8 (350 - 6 - 120 = 224)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.visibility_change' AND subject_id = '22800000-0000-4000-8000-000000000012'), 1,
  'B12: one visibility_change audit row for B6');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.price_change' AND subject_id = '22800000-0000-4000-8000-000000000011'), 1,
  'B13: one price_change audit row for B7');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'inventory.capacity.change' AND subject_id = '22800000-0000-4000-8000-0000000000c1'), 1,
  'B14: one capacity.change audit row for B8');
SELECT is((SELECT count(*)::int FROM venue.inventory_movement WHERE batch_id = '22800000-0000-4000-8000-0000000000c1' AND movement_kind = 'capacity_change'), 1,
  'B15: …and its C27 capacity_change ledger row');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.create' AND subject_id = tap._fetch228('wtt')::uuid), 1,
  'B16: one ticket_type.create audit row for B9');
-- refusals propagate unchanged
SELECT tap.login('22800000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_rank('22800000-0000-4000-8000-000000000011', 1::smallint, 'ck228-x-1')$$,
  '42501', NULL, 'B17: a fan through the wrapper: 42501 (the definer''s refusal, unchanged)');
SELECT throws_ok($$SELECT venue_cmd.create_ticket_type('22800000-0000-4000-8000-0000000000e1', 'admission', 'Fan GA', 2000, 'public', 'ck228-x-2')$$,
  '42501', NULL, 'B18: a fan through create_ticket_type: 42501');
SELECT throws_ok($$SELECT * FROM venue_cmd.get_inventory_counters('22800000-0000-4000-8000-0000000000e1')$$,
  'P0002', NULL, 'B19: a fan through get_inventory_counters: the same P0002 as an unknown event');
SELECT tap.logout();
SELECT tap.login('22800000-0000-4000-8000-000000000111');
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_rank('22800000-0000-4000-8000-0000000000ff', 1::smallint, 'ck228-x-3')$$,
  'P0002', NULL, 'B20: an unknown tier through the wrapper: P0002');
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_visibility('22800000-0000-4000-8000-000000000021', 'hidden', 'x', 'ck228-x-4')$$,
  'P0001', 'precondition_failed: event_terminal', 'B21: a completed event through the wrapper: the exact precondition message');
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_price('22800000-0000-4000-8000-000000000011', 2700, 'demand', '')$$,
  'P0001', 'precondition_failed: command key required', 'B22: an empty command key through the wrapper: the exact message');
SELECT throws_like($$SELECT venue_cmd.set_batch_capacity('22800000-0000-4000-8000-0000000000c1', 100, 'shrink', 'ck228-x-6')$$,
  '%below_committed%', 'B23: the C27 floor through the wrapper: below_committed (100 < 6 + 120)');
SELECT throws_ok($$SELECT * FROM venue_cmd.get_inventory_counters('22800000-0000-4000-8000-0000000000ee')$$,
  'P0002', NULL, 'B24: an unknown event through the counters wrapper: P0002');
SELECT tap.logout();
SELECT tap.login('22800000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT venue_cmd.create_ticket_type('22800000-0000-4000-8000-0000000000e5', 'admission', 'Former GA', 4100, 'public', 'ck228-x-7')$$,
  '42501', NULL, 'B25: E-76 through the wrapper — the former-operator manager is refused on Org A''s event at Room V2 (now Org B)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_rank('22800000-0000-4000-8000-000000000011', 1::smallint, 'ck228-x-8')$$,
  '42501', NULL, 'B26: anon is refused at the schema wall (no USAGE on venue_cmd)');
SELECT tap.logout();
SELECT throws_ok($$SELECT venue_cmd.set_ticket_type_rank('22800000-0000-4000-8000-000000000011', 1::smallint, 'ck228-x-9')$$,
  '42501', NULL, 'B27: no auth.uid() through the wrapper: insufficient_privilege (authentication required)');

SELECT * FROM finish();
ROLLBACK;
