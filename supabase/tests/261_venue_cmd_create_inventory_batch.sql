-- ============================================================================
-- 261_venue_cmd_create_inventory_batch.sql — migration 20261029170000 (registry 192).
--
-- Registry 192 (stem allocated by Claude A 2026-10-29, closeout board P2.2); pgTAP
-- 261 is the next free number (A to confirm). E reviews the exact head. DARK:
-- applied nowhere. The CI grant gates read `public` only, so THIS FILE (with 228's
-- schema-wide venue_cmd sweep) is the gate for the wrapper and for the claim that
-- 192 changed nothing on its target.
--
--   Section A  shape + ACL: exactly one venue_cmd.create_inventory_batch with the
--              target's identity arguments and result type; prosecdef = false,
--              LANGUAGE sql, VOLATILE, search_path = ''; the body is exactly
--              `select venue.create_inventory_batch(<same arguments>)` and hashes
--              to 192's md5; EXECUTE exactly owner + authenticated (anon /
--              service_role / PUBLIC none, no DEFAULTED proacl); the TARGET's ACL
--              still exactly owner + authenticated; venue_cmd USAGE unchanged.
--   Section B  allowed callers through the wrapper, as `authenticated` (tap.login):
--              the org_owner creates a public_sale batch (the row lands as asked;
--              the body's audit row names the CALLER — the invoker identity flows
--              through); the result shape equals the body's; the bound
--              venue_manager of the room creates a comp batch.
--   Section E  the body's refusals propagate verbatim through the wrapper: bad
--              release_kind, sharding_deferred, bad_capacity,
--              type_session_event_mismatch, session_capacity_exceeded (162's pool
--              guard), unknown ticket type (P0002).
--   Section R  refused callers get the body's 42501: the room's venue_scanner (a
--              non-manager label), org_finance, a cross-venue manager, a fan.
--   Section N  anon: 42501 at the schema wall (no USAGE on venue_cmd); the
--              authenticated role with no subject: the body's 'authentication
--              required'.
--   Section C  the wrapper adds NO privilege: with EXECUTE on the target revoked
--              from authenticated (inside this transaction) the org_owner gets
--              'permission denied for function create_inventory_batch', then the
--              grant is restored and re-pinned.
--
-- Positive-path calls go through tap._val261 (the call's text, or
-- {"error": "<SQLSTATE>|<SQLERRM>"}), so a wrongful refusal reads `not ok` instead
-- of aborting the file (the 232/234 pattern).
--
-- Fixture: 231 style (synthetic rows as postgres, fixed ids, tag 26100000-…, read
-- back as each caller through tap.login, rolled back). Org A: owner 101, finance
-- 103. Room V1 (Org A): manager 111, scanner 114. Room V3 (Org B): manager 131
-- (the cross-venue manager). Fan 199. Event e01 at V1 (draft): sessions f01 (no
-- pool) and f02 (pool 5, already allocated 5 by batch c02); tiers t01 (GA), t02
-- (Pool). Event e03 at V3 with session f03 (the mismatch target).
--
-- Expected on the gate tip WITHOUT 192 (RED, predicted before the first run): A1-A7
-- fail (no wrapper — every A probe counts pg_proc rows or aclexplodes a filtered
-- set, so it reads `not ok` instead of aborting); A8 and A9 pass (the target's ACL
-- and the schema USAGE are already what 192 must leave untouched). B0 passes; B1
-- fails, because tap._val261 catches the 42883 into {"error": …}; B2-B4 then fail
-- (no row, no audit, no shape); B5a passes, B5 fails. E1-E6, R1/R3/R5/R7 and C2 are
-- throws_ok / throws_like calls of a missing function: each sees 42883 instead of
-- its code and fails without aborting. R0/R2/R4/R6 pins, N1 and N3's role setup pass;
-- N2 (anon at the schema wall) PASSES on RED too (42501 permission denied for
-- schema venue_cmd comes before the function lookup); N3 fails (42883). C1 fails
-- (the wrapper count is 0, not 1); C3 passes (the target grant is restored).
-- Predicted RED run: all 36 emitted, nothing aborts — 11 ok (A8 A9 B0 B5a R0 R2 R4 R6
-- N1 N2 C3) + 25 not ok.
-- ============================================================================
BEGIN;
SELECT plan(36);

CREATE TABLE tap.memo_261 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store261(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_261 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch261(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_261 WHERE k = $1 $m$;
-- the text a statement returns AS THE CALLER, or {"error": "<SQLSTATE>|<SQLERRM>"} (a JSON object either way)
CREATE FUNCTION tap._val261(q text) RETURNS text
LANGUAGE plpgsql AS
$m$ DECLARE v text; BEGIN EXECUTE q INTO v; RETURN v; EXCEPTION WHEN OTHERS THEN RETURN jsonb_build_object('error', SQLSTATE || '|' || SQLERRM)::text; END $m$;
GRANT EXECUTE ON FUNCTION tap._store261(text, text), tap._fetch261(text), tap._val261(text) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('26100000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.261@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26100000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.261@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26100000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.261@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26100000-0000-4000-8000-000000000114', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v1.261@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26100000-0000-4000-8000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v3.261@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('26100000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.261@test.local',      '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('26100000-0000-4000-8000-00000000000a', 'Org A 261', 'Org A 261', 'active'),
  ('26100000-0000-4000-8000-00000000000b', 'Org B 261', 'Org B 261', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('26100000-0000-4000-8000-00000000000a', '26100000-0000-4000-8000-000000000101', 'org_owner'),
  ('26100000-0000-4000-8000-00000000000a', '26100000-0000-4000-8000-000000000103', 'org_finance');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('26100000-0000-4000-8000-0000000000a1', '26100000-0000-4000-8000-00000000000a', 'Room V1 261', 'wynwood', 'approved'),
  ('26100000-0000-4000-8000-0000000000b3', '26100000-0000-4000-8000-00000000000b', 'Room V3 261', 'midtown', 'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('26100000-0000-4000-8000-0000000000a1', '26100000-0000-4000-8000-000000000111', 'venue_manager'),
  ('26100000-0000-4000-8000-0000000000a1', '26100000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('26100000-0000-4000-8000-0000000000b3', '26100000-0000-4000-8000-000000000131', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('26100000-0000-4000-8000-00000000e001', '26100000-0000-4000-8000-0000000000a1', '26100000-0000-4000-8000-00000000000a', 'e01 V1 261', 'draft'),
  ('26100000-0000-4000-8000-00000000e003', '26100000-0000-4000-8000-0000000000b3', '26100000-0000-4000-8000-00000000000b', 'e03 V3 261', 'draft');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, status, door_open_at, sales_capacity) VALUES
  ('26100000-0000-4000-8000-00000000f001', '26100000-0000-4000-8000-00000000e001', NULL, '2027-02-01 01:00:00+00', 'scheduled', NULL, NULL),
  ('26100000-0000-4000-8000-00000000f002', '26100000-0000-4000-8000-00000000e001', NULL, '2027-02-02 01:00:00+00', 'scheduled', NULL, 5),
  ('26100000-0000-4000-8000-00000000f003', '26100000-0000-4000-8000-00000000e003', NULL, '2027-02-03 01:00:00+00', 'scheduled', NULL, NULL);
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000e001', 'admission', 'GA 261',   2500, 'public'),
  ('26100000-0000-4000-8000-00000000d002', '26100000-0000-4000-8000-00000000e001', 'admission', 'Pool 261', 3000, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('26100000-0000-4000-8000-00000000c002', '26100000-0000-4000-8000-00000000d002', '26100000-0000-4000-8000-00000000f002', 'public_sale', 5, 0, 0);

-- ── Section A — shape + ACL (NULL-safe: counts / filtered sets, no casts) ──────
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch'
              AND pg_get_function_identity_arguments(p.oid) = 'p_ticket_type_id uuid, p_session_id uuid, p_release_kind text, p_capacity integer, p_shard_count integer, p_command_key text'), 1,
  'A1: exactly one venue_cmd.create_inventory_batch(p_ticket_type_id uuid, p_session_id uuid, p_release_kind text, p_capacity integer, p_shard_count integer, p_command_key text)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch'
              AND NOT p.prosecdef AND l.lanname = 'sql' AND p.provolatile = 'v'
              AND 'search_path=""' = ANY (coalesce(p.proconfig, '{}')) AND pg_get_function_result(p.oid) = 'jsonb'), 1,
  'A2: it is SECURITY INVOKER, LANGUAGE sql, VOLATILE, search_path = '''', returning jsonb');
SELECT is((SELECT count(*)::int FROM pg_proc w JOIN pg_namespace wn ON wn.oid = w.pronamespace,
                  pg_proc t JOIN pg_namespace tn ON tn.oid = t.pronamespace
            WHERE wn.nspname = 'venue_cmd' AND w.proname = 'create_inventory_batch'
              AND tn.nspname = 'venue'     AND t.proname = 'create_inventory_batch'
              AND pg_get_function_identity_arguments(w.oid) = pg_get_function_identity_arguments(t.oid)
              AND pg_get_function_arguments(w.oid) = pg_get_function_arguments(t.oid)
              AND pg_get_function_result(w.oid) = pg_get_function_result(t.oid)), 1,
  'A3: its arguments (names, types) and result type are the target''s');
SELECT is((SELECT regexp_replace(btrim(p.prosrc, E' \n\t\r'), '\s+', ' ', 'g') FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch'),
  'select venue.create_inventory_batch(p_ticket_type_id, p_session_id, p_release_kind, p_capacity, p_shard_count, p_command_key)',
  'A4: the body is exactly one SELECT of venue.create_inventory_batch with the same six arguments in order (no logic)');
SELECT is((SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch'),
  'd6d48059afcfc50c9746c298a48a4a24', 'A5: the body hashes to 192''s md5 (the pre-flight / rollback G1 anchor)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch' $$,
  $$ VALUES ('postgres:EXECUTE'), ('authenticated:EXECUTE') $$,
  'A6: EXECUTE on the wrapper is exactly owner (postgres) + authenticated');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch' AND p.proacl IS NOT NULL
              AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
              AND NOT has_function_privilege('anon', p.oid, 'EXECUTE')
              AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
              AND NOT has_function_privilege('public', p.oid, 'EXECUTE')), 1,
  'A7: anon, service_role and PUBLIC hold no EXECUTE, authenticated does, and the proacl is not DEFAULTED');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname = 'create_inventory_batch' $$,
  $$ VALUES ('postgres:EXECUTE'), ('authenticated:EXECUTE') $$,
  'A8: the TARGET venue.create_inventory_batch keeps exactly owner + authenticated (081 PART 16) — 192 granted and revoked nothing on it');
SELECT is(has_schema_privilege('authenticated', 'venue_cmd', 'USAGE')::text || '|' || has_schema_privilege('anon', 'venue_cmd', 'USAGE')::text,
  'true|false', 'A9: venue_cmd USAGE unchanged (161): authenticated yes, anon no');

-- ── Section B — allowed callers through the wrapper ─────────────────────────
SELECT tap.login('26100000-0000-4000-8000-000000000101');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|26100000-0000-4000-8000-000000000101',
  'B0: the org_owner block runs as authenticated with its own auth.uid()');
SELECT tap._store261('b1', tap._val261($q$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 10, NULL, 'ck261-b1')::text$q$));
SELECT is(tap._fetch261('b1')::jsonb ->> 'status', 'ok',
  'B1: the org_owner creates a public_sale batch of 10 through venue_cmd.create_inventory_batch');
SELECT tap.logout();
SELECT is((SELECT b.ticket_type_id::text || '|' || b.event_session_id::text || '|' || b.release_kind || '|' || b.capacity || '|' || b.held || '|' || b.sold
             FROM venue.inventory_batch b WHERE b.batch_id::text = tap._fetch261('b1')::jsonb ->> 'batch_id'),
  '26100000-0000-4000-8000-00000000d001|26100000-0000-4000-8000-00000000f001|public_sale|10|0|0',
  'B2: the batch landed as asked — tier t01, session f01, public_sale, capacity 10, held 0, sold 0');
SELECT is((SELECT a.actor_identity::text || '|' || a.action || '|' || a.subject_kind FROM kernel.admin_audit a
            WHERE a.subject_id::text = tap._fetch261('b1')::jsonb ->> 'batch_id'),
  '26100000-0000-4000-8000-000000000101|inventory.batch.create|inventory_batch',
  'B3: the body''s audit row names the CALLER as actor — the invoker identity flows through the wrapper');
SELECT is((SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(tap._fetch261('b1')::jsonb) k),
  'batch_id,capacity,is_sharded,status', 'B4: the result is the body''s own shape {status, batch_id, capacity, is_sharded}');
SELECT tap.login('26100000-0000-4000-8000-000000000111');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|26100000-0000-4000-8000-000000000111',
  'B5a: the room''s venue_manager block runs as authenticated with its own auth.uid()');
SELECT is(tap._val261($q$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'comp', 3, NULL, 'ck261-b5') ->> 'status'$q$), 'ok',
  'B5: the bound venue_manager of Room V1 creates a comp batch through the wrapper (162''s venue-role arm; the room''s operator is the event''s org)');
SELECT tap.logout();

-- ── Section E — the body's refusals propagate through the wrapper ───────────
SELECT tap.login('26100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'vip', 1, NULL, 'ck261-e1')$$,
  'P0001', 'invalid_input: bad release_kind vip', 'E1: a bad release_kind is refused by the body, verbatim');
SELECT throws_like($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, 2, 'ck261-e2')$$,
  'precondition_failed: sharding_deferred%', 'E2: p_shard_count > 0 is refused sharding_deferred (E-32)');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 0, NULL, 'ck261-e3')$$,
  'P0001', 'precondition_failed: bad_capacity', 'E3: capacity 0 is refused bad_capacity');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f003', 'public_sale', 1, NULL, 'ck261-e4')$$,
  'P0001', 'precondition_failed: type_session_event_mismatch', 'E4: a tier of e01 on a session of another event is refused type_session_event_mismatch');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d002', '26100000-0000-4000-8000-00000000f002', 'public_sale', 1, NULL, 'ck261-e5')$$,
  'P0001', 'precondition_failed: session_capacity_exceeded (allocated=5 + new=1 > sales_capacity=5)',
  'E5: 162''s shared-pool guard holds through the wrapper — pool 5 already allocated, one more seat refused');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000dfff', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-e6')$$,
  'P0002', 'not_found: ticket type 26100000-0000-4000-8000-00000000dfff', 'E6: an unknown ticket type is P0002 not_found');
SELECT tap.logout();

-- ── Section R — refused callers get the body's 42501 ────────────────────────
SELECT tap.login('26100000-0000-4000-8000-000000000114');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|26100000-0000-4000-8000-000000000114', 'R0: the venue_scanner block runs as authenticated');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-r1')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R1: the room''s venue_scanner (a non-manager label) is refused');
SELECT tap.logout();
SELECT tap.login('26100000-0000-4000-8000-000000000103');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|26100000-0000-4000-8000-000000000103', 'R2: the org_finance block runs as authenticated');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-r3')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R3: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('26100000-0000-4000-8000-000000000131');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|26100000-0000-4000-8000-000000000131', 'R4: the cross-venue manager block runs as authenticated');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-r5')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R5: Room V3''s manager is refused on Room V1''s event');
SELECT tap.logout();
SELECT tap.login('26100000-0000-4000-8000-000000000199');
SELECT is(current_user::text || '|' || auth.uid()::text, 'authenticated|26100000-0000-4000-8000-000000000199', 'R6: the fan block runs as authenticated');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-r7')$$,
  '42501', 'insufficient_privilege: venue_manager or org_owner/org_admin required', 'R7: a fan is refused');
SELECT tap.logout();

-- ── Section N — anon and the unauthenticated path ───────────────────────────
SELECT tap.login_anon();
SELECT is(current_user::text || '|' || coalesce(auth.uid()::text, 'no-uid'), 'anon|no-uid', 'N1: the anon block runs as anon with no auth.uid()');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-n2')$$,
  '42501', 'permission denied for schema venue_cmd', 'N2: anon is refused at the schema wall (no USAGE on venue_cmd)');
SELECT tap.logout();
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000d001', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-n3')$$,
  '42501', 'insufficient_privilege: authentication required', 'N3: the authenticated role with no subject gets the body''s authentication-required refusal');
SELECT tap.logout();

-- ── Section C — the wrapper adds NO privilege ───────────────────────────────
-- Inside this transaction only: take EXECUTE on the target away from authenticated.
-- The call names an UNKNOWN tier, so a wrapper that leaked privilege would reach
-- the body and answer P0002 instead of 42501.
REVOKE EXECUTE ON FUNCTION venue.create_inventory_batch(uuid, uuid, text, integer, integer, text) FROM authenticated;
SELECT is((SELECT count(*) FILTER (WHERE n.nspname = 'venue_cmd' AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))::text || '|'
                  || count(*) FILTER (WHERE n.nspname = 'venue' AND has_function_privilege('authenticated', p.oid, 'EXECUTE'))::text
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname IN ('venue_cmd','venue') AND p.proname = 'create_inventory_batch'),
  '1|0', 'C1: during the subtraction authenticated holds EXECUTE on the wrapper and not on the body');
SELECT tap.login('26100000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue_cmd.create_inventory_batch('26100000-0000-4000-8000-00000000dfff', '26100000-0000-4000-8000-00000000f001', 'public_sale', 1, NULL, 'ck261-c2')$$,
  '42501', 'permission denied for function create_inventory_batch',
  'C2: the org_owner loses the wrapper with the body (the body''s permission error, not P0002) — no privilege added');
SELECT tap.logout();
GRANT EXECUTE ON FUNCTION venue.create_inventory_batch(uuid, uuid, text, integer, integer, text) TO authenticated;
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname = 'create_inventory_batch' $$,
  $$ VALUES ('postgres:EXECUTE'), ('authenticated:EXECUTE') $$,
  'C3: the target''s grant is restored — exactly owner + authenticated again');

SELECT * FROM finish();
ROLLBACK;
