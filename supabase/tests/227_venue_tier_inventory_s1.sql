-- ============================================================================
-- 227_venue_tier_inventory_s1.sql — migration 20261022100000 (registry 160).
--
-- Registry 160 / pgTAP 227 — assigned by Claude A 2026-10-22 (registry 573850a4).
-- A reviews before this leaves draft. DARK: applied nowhere; venue_api/venue_cmd
-- are not exposed; nothing here changes a flag or a config key.
--
-- Covers 160: (a) venue.ticket_type.display_rank (smallint NULL, CHECK 0..999);
-- (b) venue.set_ticket_type_visibility and (c) venue.set_ticket_type_rank — the
-- tier setters the dashboard copy promises but no 081 RPC delivered; (d)
-- venue.get_inventory_counters — the staff read E-29 intended (081:1011-1018:
-- capacity/held/sold are withheld from every client role; staff read them
-- through an RPC RESULT, never a table SELECT); (e) the E-76 current-operator
-- binding on the venue arm of the four 081 writers (create_ticket_type 081:175,
-- set_ticket_type_price 081:246, create_inventory_batch 081:320,
-- set_batch_capacity 081:408), body-only replaces at the exact signatures;
-- (f) venue_api.ticket_types re-created with display_rank appended last.
--
-- Fixture style: 226/246 (synthetic rows inserted as postgres with fixed ids,
-- tag 22700000-…, read back as each caller through tap.login, rolled back).
-- One identity per label: org_owner, org_admin, org_finance of Org A; Room V1
-- (Org A, never moved) venue_manager / venue_finance / venue_box_office /
-- venue_scanner / venue_marketing; Room V3 (Org B) venue_manager = the
-- CROSS-venue manager; Room V2 = the RE-OPERATED room: created under Org A, its
-- event e5 stamped Org A (as catalog.create_event stamps), then moved to Org B
-- (the stand-in for catalog.update_venue's platform_admin tenancy move,
-- 078:684-704, which does not re-stamp existing events) — its venue_manager is
-- the FORMER-OPERATOR manager; Org B's org_owner; a fan with no grant; anon.
-- Events at V1: e1 draft, e2 on_sale (two tiers, two batches), e3 completed,
-- e4 cancelled. e5 at V2 (Org A's event on a room Org B now operates). e6 at V3
-- (Org B's own event, the cross-venue manager's positive control).
--
--   Section A  shape: the three functions exist with the exact ACL (EXECUTE to
--              authenticated only; nothing for anon/PUBLIC/service_role),
--              SECURITY DEFINER + search_path=''; counters STABLE; display_rank
--              column + CHECK; venue holds 90 functions (87 + 3: the 145 A4 /
--              180 A5 pins move with it); the E-76 conjunct is in all four 081
--              bodies; venue_api.ticket_types carries display_rank LAST with
--              its ACL unchanged; venue_api still holds no function; E-29 column
--              grants unchanged.
--   Section B  the four 081 writers: former-operator manager REFUSED by all four
--              (the E-76 NEGATIVE control, B1-B4); bound V1 manager ACCEPTED by
--              all four (POSITIVE control, B5-B8); the org arm on the re-operated
--              room (B9/B10 — R3, flipped by 162: the EVENT's org, A's ruling);
--              grants and definer posture unchanged (B11/B12); cross-venue and
--              cross-org refusals unchanged (B13-B15). Placed before C on purpose:
--              every assertion that needs no new function runs before the first
--              unavoidable abort of the RED run (see below).
--   Section C  set_ticket_type_visibility: the authority matrix (3 allowed, 8
--              refused 42501, anon, unauthenticated), input rules, terminal
--              refusal, exactly one audit row with before/after, same-value noop
--              with no audit row.
--   Section D  set_ticket_type_rank: the same matrix, 0..999 bounds, NULL clears
--              the rank, audit, noop.
--   Section E  get_inventory_counters: values equal the raw rows for the ruled
--              readers (org_owner/org_admin/org_finance + venue_manager/
--              venue_finance — the conservative intersection, an OWNER decision
--              item); box_office, scanner, marketing, cross-venue, former-operator,
--              fan, Org B's owner on Org A's event: the SAME P0002 as an unknown
--              event; remaining = capacity - held - sold; the oversell CHECK still
--              aborts a planted held+sold>capacity write; the column stays
--              unreadable to a manager (the RPC result is the only route).
--   Section F  display_rank through venue_api.ticket_types: NULL by default,
--              readable by the owner, readable by a fan on a PUBLIC tier (the
--              081:988 table grant covers the new column — as 160's header says).
--
-- Expected on bfc5cf97 + 159 WITHOUT 160 (RED, predicted before the first run;
-- the reconciliation against the actual run is in the evidence dir):
--   A1-A14 fail (the functions, the column, the conjunct text, the 90 count and
--   the tenth view column are absent: 87 functions, nine columns); A15-A18 pass.
--   B1-B4 fail (the former-operator manager is ACCEPTED by all four writers);
--   B5-B15 pass. Then C1 — the first direct call of a missing function — raises
--   42883 and aborts the transaction, so C2-F5 (78 assertions) are never
--   emitted. Predicted RED run: 33 emitted = 18 not ok + 15 ok; plan 111 unmet.
--   A9/A11 use to_regprocedure, not a ::regprocedure cast, so they read `not ok`
--   instead of aborting the file before Section B.
-- ============================================================================
BEGIN;
SELECT plan(111);

CREATE TABLE tap.memo_227 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store227(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_227 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch227(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_227 WHERE k = $1 $m$;
-- definer read of the raw counters, for the "values equal the raw rows" checks
-- (E-29: no client role may SELECT them; this stands in for a postgres read
-- inside a logged-in step).
CREATE FUNCTION tap._raw227(b uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT capacity::text || '|' || held::text || '|' || sold::text || '|' || remaining::text
      FROM venue.inventory_batch WHERE batch_id = b $m$;
GRANT EXECUTE ON FUNCTION tap._store227(text, text), tap._fetch227(text), tap._raw227(uuid) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('22700000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.227@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.a.227@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.227@test.local',     '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.227@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.v1.227@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'box.v1.227@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000114', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v1.227@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000115', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v1.227@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.227@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v3.cross.227@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.227@test.local',       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('22700000-0000-4000-8000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.b.227@test.local',   '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('22700000-0000-4000-8000-00000000000a', 'Org A 227', 'Org A 227', 'active'),
  ('22700000-0000-4000-8000-00000000000b', 'Org B 227', 'Org B 227', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('22700000-0000-4000-8000-00000000000a', '22700000-0000-4000-8000-000000000101', 'org_owner'),
  ('22700000-0000-4000-8000-00000000000a', '22700000-0000-4000-8000-000000000102', 'org_admin'),
  ('22700000-0000-4000-8000-00000000000a', '22700000-0000-4000-8000-000000000103', 'org_finance'),
  ('22700000-0000-4000-8000-00000000000b', '22700000-0000-4000-8000-000000000201', 'org_owner');
-- V2 is created under Org A (its event e5 is stamped Org A below), then moved.
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-00000000000a', 'Room V1 227', 'wynwood',  'approved'),
  ('22700000-0000-4000-8000-0000000000a2', '22700000-0000-4000-8000-00000000000a', 'Room V2 227', 'brickell', 'approved'),
  ('22700000-0000-4000-8000-0000000000b3', '22700000-0000-4000-8000-00000000000b', 'Room V3 227', 'midtown',  'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-000000000111', 'venue_manager'),
  ('22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-000000000112', 'venue_finance'),
  ('22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-000000000113', 'venue_box_office'),
  ('22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-000000000115', 'venue_marketing'),
  ('22700000-0000-4000-8000-0000000000a2', '22700000-0000-4000-8000-000000000121', 'venue_manager'),
  ('22700000-0000-4000-8000-0000000000b3', '22700000-0000-4000-8000-000000000131', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('22700000-0000-4000-8000-0000000000e1', '22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-00000000000a', 'V1 draft 227',     'draft'),
  ('22700000-0000-4000-8000-0000000000e2', '22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-00000000000a', 'V1 on sale 227',   'on_sale'),
  ('22700000-0000-4000-8000-0000000000e3', '22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-00000000000a', 'V1 completed 227', 'completed'),
  ('22700000-0000-4000-8000-0000000000e4', '22700000-0000-4000-8000-0000000000a1', '22700000-0000-4000-8000-00000000000a', 'V1 cancelled 227', 'cancelled'),
  ('22700000-0000-4000-8000-0000000000e5', '22700000-0000-4000-8000-0000000000a2', '22700000-0000-4000-8000-00000000000a', 'V2 (A event) 227', 'on_sale'),
  ('22700000-0000-4000-8000-0000000000e6', '22700000-0000-4000-8000-0000000000b3', '22700000-0000-4000-8000-00000000000b', 'V3 (B event) 227', 'draft');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('22700000-0000-4000-8000-0000000000f1', '22700000-0000-4000-8000-0000000000e1', now() + interval '30 days', 'scheduled'),
  ('22700000-0000-4000-8000-0000000000f2', '22700000-0000-4000-8000-0000000000e2', now() + interval '3 days',  'scheduled'),
  ('22700000-0000-4000-8000-0000000000f3', '22700000-0000-4000-8000-0000000000e3', now() - interval '3 days',  'completed'),
  ('22700000-0000-4000-8000-0000000000f4', '22700000-0000-4000-8000-0000000000e4', now() + interval '5 days',  'cancelled'),
  ('22700000-0000-4000-8000-0000000000f5', '22700000-0000-4000-8000-0000000000e5', now() + interval '7 days',  'scheduled'),
  ('22700000-0000-4000-8000-0000000000f6', '22700000-0000-4000-8000-0000000000e6', now() + interval '9 days',  'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('22700000-0000-4000-8000-000000000011', '22700000-0000-4000-8000-0000000000e1', 'admission', 'GA draft 227',     2500, 'hidden'),
  ('22700000-0000-4000-8000-000000000021', '22700000-0000-4000-8000-0000000000e2', 'admission', 'GA on sale 227',   3000, 'public'),
  ('22700000-0000-4000-8000-000000000022', '22700000-0000-4000-8000-0000000000e2', 'table',     'Door table 227',   1500, 'door_only'),
  ('22700000-0000-4000-8000-000000000031', '22700000-0000-4000-8000-0000000000e3', 'admission', 'GA completed 227', 2700, 'public'),
  ('22700000-0000-4000-8000-000000000041', '22700000-0000-4000-8000-0000000000e4', 'admission', 'GA cancelled 227', 2800, 'public'),
  ('22700000-0000-4000-8000-000000000051', '22700000-0000-4000-8000-0000000000e5', 'admission', 'GA V2 227',        4000, 'public'),
  ('22700000-0000-4000-8000-000000000061', '22700000-0000-4000-8000-0000000000e6', 'admission', 'GA V3 227',        3300, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('22700000-0000-4000-8000-0000000000c1', '22700000-0000-4000-8000-000000000011', '22700000-0000-4000-8000-0000000000f1', 'public_sale', 100, 5, 20),
  ('22700000-0000-4000-8000-0000000000c2', '22700000-0000-4000-8000-000000000021', '22700000-0000-4000-8000-0000000000f2', 'public_sale', 300, 6, 120),
  ('22700000-0000-4000-8000-0000000000c3', '22700000-0000-4000-8000-000000000022', '22700000-0000-4000-8000-0000000000f2', 'door',        100, 0, 100),
  ('22700000-0000-4000-8000-0000000000c4', '22700000-0000-4000-8000-000000000031', '22700000-0000-4000-8000-0000000000f3', 'public_sale', 150, 0, 150),
  ('22700000-0000-4000-8000-0000000000c5', '22700000-0000-4000-8000-000000000041', '22700000-0000-4000-8000-0000000000f4', 'public_sale', 150, 0, 0),
  ('22700000-0000-4000-8000-0000000000c6', '22700000-0000-4000-8000-000000000051', '22700000-0000-4000-8000-0000000000f5', 'public_sale', 200, 0, 15),
  ('22700000-0000-4000-8000-0000000000c7', '22700000-0000-4000-8000-000000000061', '22700000-0000-4000-8000-0000000000f6', 'public_sale', 120, 0, 0);
-- THE RE-OPERATION: Room V2 moves from Org A to Org B. e5 keeps org_id = A, as
-- catalog.update_venue's tenancy move leaves it (078:684-704 does not re-stamp).
UPDATE catalog.venue SET org_id = '22700000-0000-4000-8000-00000000000b'
 WHERE venue_id = '22700000-0000-4000-8000-0000000000a2';

-- ── Section A — shape ────────────────────────────────────────────────────────
SELECT has_function('venue'::name, 'set_ticket_type_visibility'::name, ARRAY['uuid','text','text','text']::name[],
  'A1: venue.set_ticket_type_visibility(uuid, text, text, text) exists');
SELECT has_function('venue'::name, 'set_ticket_type_rank'::name, ARRAY['uuid','smallint','text']::name[],
  'A2: venue.set_ticket_type_rank(uuid, smallint, text) exists');
SELECT has_function('venue'::name, 'get_inventory_counters'::name, ARRAY['uuid']::name[],
  'A3: venue.get_inventory_counters(uuid) exists');
SELECT col_type_is('venue'::name, 'ticket_type'::name, 'display_rank'::name, 'smallint',
  'A4: venue.ticket_type.display_rank is smallint');
SELECT col_is_null('venue'::name, 'ticket_type'::name, 'display_rank'::name,
  'A5: display_rank is nullable (NULL = unranked)');
SELECT throws_ok($$UPDATE venue.ticket_type SET display_rank = 1000 WHERE ticket_type_id = '22700000-0000-4000-8000-000000000011'$$,
  '23514', NULL, 'A6: CHECK — display_rank 1000 is refused at the table');
SELECT throws_ok($$UPDATE venue.ticket_type SET display_rank = -1 WHERE ticket_type_id = '22700000-0000-4000-8000-000000000011'$$,
  '23514', NULL, 'A7: CHECK — display_rank -1 is refused at the table');
-- the exact EXECUTE surface of the three new functions (CI's grant manifest reads public only; this is the gate)
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname IN ('set_ticket_type_visibility','set_ticket_type_rank','get_inventory_counters')
        AND a.grantee <> p.proowner $$,
  $$ VALUES ('set_ticket_type_visibility:authenticated:EXECUTE'), ('set_ticket_type_rank:authenticated:EXECUTE'),
            ('get_inventory_counters:authenticated:EXECUTE') $$,
  'A8: the three new functions grant EXECUTE to authenticated and to NOBODY else (no PUBLIC, anon, service_role)');
-- to_regprocedure (not a ::regprocedure cast) so that on the chain WITHOUT 160 this reads as a
-- plain `not ok` instead of raising 42883 and aborting the whole file.
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.set_ticket_type_visibility(uuid, text, text, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.set_ticket_type_rank(uuid, smallint, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.get_inventory_counters(uuid)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.set_ticket_type_visibility(uuid, text, text, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.set_ticket_type_rank(uuid, smallint, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.get_inventory_counters(uuid)'), 'EXECUTE'), false),
  'A9: anon has no EXECUTE on any of the three; authenticated has it on all three');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname IN ('set_ticket_type_visibility','set_ticket_type_rank','get_inventory_counters')
              AND p.prosecdef AND p.proconfig::text LIKE '%search_path=%'), 3,
  'A10: all three are SECURITY DEFINER with a pinned search_path (066 invariant)');
SELECT is((SELECT p.provolatile FROM pg_proc p WHERE p.oid = to_regprocedure('venue.get_inventory_counters(uuid)')), 's',
  'A11: get_inventory_counters is STABLE (a read)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue'), 96,
  -- 2026-10-26 (registry 163): 92 -> 96 (+get_session_scan_counters, list_session_scan_counters, record_scan_staff, filter_staff_scan_meta; 94 if 163''s PART B is dropped).
  -- 2026-10-26 (registry 162, S2): 90 -> 92 (+set_ticket_type_sale_window, ticket_type_on_sale).
  'A12: venue holds NINETY-SIX functions — 87 (144 A15 / 145 A4 / 148 B5 / 179 A8 / 180 A5 move with it; 148 B2 / 156 A20 / 157 A46 / 179 A9 / 180 A6 move 308 -> 317) + 160''s three + 162''s two + 163''s four');
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN ('venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure,
                            'venue.set_ticket_type_price(uuid, integer, text, text)'::regprocedure,
                            'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure,
                            'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
              AND p.prosrc LIKE '%and exists (select 1 from catalog.venue v where v.venue_id = v_venue and v.org_id = v_org_id)%'), 4,
  'A13: all four 081 writer bodies carry the E-76 conjunct text on the venue arm');
SELECT is((SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = 'venue_api.ticket_types'::regclass AND a.attnum > 0 AND NOT a.attisdropped),
  'ticket_type_id,event_id,kind,name,price_minor,currency,visibility,created_at,updated_at,display_rank,sale_starts_at,sale_ends_at,on_sale_now',
  -- 2026-10-26 (registry 162, S2): + sale_starts_at, sale_ends_at, on_sale_now appended after display_rank.
  'A14: venue_api.ticket_types projects 159''s nine columns in order, display_rank (160), then 162''s sale_starts_at, sale_ends_at, on_sale_now LAST');
SELECT ok((SELECT bool_and(o IN ('security_invoker=true','security_barrier=true')) AND count(*) = 2
             FROM pg_class c CROSS JOIN LATERAL unnest(c.reloptions) o WHERE c.oid = 'venue_api.ticket_types'::regclass),
  'A15: the re-created view is still security_invoker AND security_barrier');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE c.oid = 'venue_api.ticket_types'::regclass AND a.grantee <> c.relowner $$,
  $$ VALUES ('authenticated:SELECT') $$,
  'A16: venue_api.ticket_types ACL is still exactly SELECT to authenticated');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_api'), 0,
  'A17: venue_api still holds no function (226 A3 stays true: the definer bodies live in venue)');
SELECT ok(NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'capacity', 'SELECT')
      AND NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'held', 'SELECT')
      AND NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'sold', 'SELECT')
      AND NOT has_column_privilege('anon', 'venue.inventory_batch', 'capacity', 'SELECT'),
  'A18: E-29 unchanged — capacity/held/sold are not client-selectable (160 adds NO column grant on inventory_batch)');

-- ── Section B — the four 081 writers: E-76 on the venue arm ──────────────────
-- NEGATIVE control: the former-operator manager on Org A's event at the room Org B now operates.
SELECT tap.login('22700000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT venue.create_ticket_type('22700000-0000-4000-8000-0000000000e5', 'admission', 'Former GA', 4100, 'public', 'ck227-d-1')$$,
  '42501', NULL, 'B1: E-76 — create_ticket_type REFUSES the former-operator manager (venue.org_id = B, event.org_id = A)');
SELECT throws_ok($$SELECT venue.set_ticket_type_price('22700000-0000-4000-8000-000000000051', 4500, 'demand', 'ck227-d-2')$$,
  '42501', NULL, 'B2: E-76 — set_ticket_type_price REFUSES the former-operator manager');
SELECT throws_ok($$SELECT venue.create_inventory_batch('22700000-0000-4000-8000-000000000051', '22700000-0000-4000-8000-0000000000f5', 'public_sale', 50, 0, 'ck227-d-3')$$,
  '42501', NULL, 'B3: E-76 — create_inventory_batch REFUSES the former-operator manager');
SELECT throws_ok($$SELECT venue.set_batch_capacity('22700000-0000-4000-8000-0000000000c6', 250, 'expansion', 'ck227-d-4')$$,
  '42501', NULL, 'B4: E-76 — set_batch_capacity REFUSES the former-operator manager');
SELECT tap.logout();
-- POSITIVE control: the bound manager of Room V1 (Org A, never moved) on Org A's event e1.
SELECT tap.login('22700000-0000-4000-8000-000000000111');
SELECT tap._store227('d5_tt',
  (venue.create_ticket_type('22700000-0000-4000-8000-0000000000e1', 'admission', 'B5 tier 227', 2000, 'hidden', 'ck227-d-5') ->> 'ticket_type_id'));
SELECT ok((SELECT count(*) = 1 FROM venue.ticket_type WHERE ticket_type_id = tap._fetch227('d5_tt')::uuid AND name = 'B5 tier 227'),
  'B5: create_ticket_type ACCEPTS the bound venue_manager (the venue arm still works where venue.org_id = event.org_id)');
SELECT is((venue.set_ticket_type_price('22700000-0000-4000-8000-000000000011', 2600, 'demand', 'ck227-d-6') ->> 'price_minor'), '2600',
  'B6: set_ticket_type_price ACCEPTS the bound venue_manager');
SELECT tap._store227('d7_batch',
  (venue.create_inventory_batch(tap._fetch227('d5_tt')::uuid, '22700000-0000-4000-8000-0000000000f1', 'presale', 40, 0, 'ck227-d-7') ->> 'batch_id'));
SELECT is(tap._raw227(tap._fetch227('d7_batch')::uuid), '40|0|0|40',
  'B7: create_inventory_batch ACCEPTS the bound venue_manager (capacity 40, held/sold 0, remaining 40)');
SELECT is((venue.set_batch_capacity('22700000-0000-4000-8000-0000000000c1', 150, 'expansion', 'ck227-d-8') ->> 'capacity'), '150',
  'B8: set_batch_capacity ACCEPTS the bound venue_manager');
SELECT tap.logout();
-- R3 (A's ruling 2026-10-26, registry 162): the org arm binds to the EVENT's org (kernel.has_org_role on event.org_id,
-- the 088:1629 cancel_event helper), no longer the venue's CURRENT operator. Pre-162 these two pinned the 081/160 status
-- quo the other way round (A refused, B accepted); 162 flips them. On a chain without 162 both read `not ok`.
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT is((venue.set_ticket_type_price('22700000-0000-4000-8000-000000000051', 4200, 'demand', 'ck227-d-9') ->> 'price_minor'), '4200',
  'B9: R3 (162) — the event''s OWN org_owner (A) is ACCEPTED on e5 although Room V2 now belongs to Org B: the org arm is the event''s org');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000201');
SELECT throws_ok($$SELECT venue.set_ticket_type_price('22700000-0000-4000-8000-000000000051', 4300, 'demand', 'ck227-d-10')$$,
  '42501', NULL, 'B10: R3 (162) — the NEW operator''s org_owner (B) is REFUSED on Org A''s event e5');
SELECT tap.logout();
SELECT ok(has_function_privilege('authenticated', 'venue.create_ticket_type(uuid, text, text, integer, text, text)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'venue.set_ticket_type_price(uuid, integer, text, text)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'venue.set_batch_capacity(uuid, integer, text, text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.create_ticket_type(uuid, text, text, integer, text, text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.set_ticket_type_price(uuid, integer, text, text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'venue.set_batch_capacity(uuid, integer, text, text)', 'EXECUTE'),
  'B11: the four writers'' EXECUTE grants are unchanged (authenticated yes, anon no)');
SELECT is((SELECT count(*)::int FROM pg_proc p
            WHERE p.oid IN ('venue.create_ticket_type(uuid, text, text, integer, text, text)'::regprocedure,
                            'venue.set_ticket_type_price(uuid, integer, text, text)'::regprocedure,
                            'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure,
                            'venue.set_batch_capacity(uuid, integer, text, text)'::regprocedure)
              AND p.prosecdef AND p.proconfig::text LIKE '%search_path=%'), 4,
  'B12: the four writers stay SECURITY DEFINER with the pinned search_path');
SELECT tap.login('22700000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT venue.create_ticket_type('22700000-0000-4000-8000-0000000000e1', 'admission', 'Cross GA', 2000, 'public', 'ck227-d-13')$$,
  '42501', NULL, 'B13: the cross-venue manager (Room V3) is refused on Room V1''s event (081 behaviour, unchanged)');
SELECT is((venue.create_ticket_type('22700000-0000-4000-8000-0000000000e6', 'admission', 'V3 own GA', 2000, 'public', 'ck227-d-13b') ->> 'status'), 'ok',
  'B14: …and accepted on its OWN room''s event e6 (Org B room, Org B event: bound)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT throws_ok($$SELECT venue.create_ticket_type('22700000-0000-4000-8000-0000000000e6', 'admission', 'A on B', 2000, 'public', 'ck227-d-15')$$,
  '42501', NULL, 'B15: Org A''s owner is refused on Org B''s event at Org B''s room (cross-org, unchanged)');
SELECT tap.logout();

-- ── Section C — set_ticket_type_visibility ───────────────────────────────────
-- allowed: org_owner, org_admin, bound venue_manager (each call changes the value)
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT is(venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'launch', 'ck227-v-1'),
  jsonb_build_object('status','ok','ticket_type_id','22700000-0000-4000-8000-000000000011','visibility','public'),
  'C1: org_owner flips the draft''s hidden tier to public — {status ok, id, visibility}');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000102');
SELECT is((venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'door_only', 'door_list', 'ck227-v-2') ->> 'visibility'),
  'door_only', 'C2: org_admin sets door_only');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000111');
SELECT is((venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'hidden', 'hold_back', 'ck227-v-3') ->> 'visibility'),
  'hidden', 'C3: the BOUND venue_manager (Room V1, Org A, never moved) sets hidden');
SELECT tap.logout();
SELECT is((SELECT visibility FROM venue.ticket_type WHERE ticket_type_id = '22700000-0000-4000-8000-000000000011'), 'hidden',
  'C4: the value is persisted on venue.ticket_type');
-- refused 42501: org_finance, venue_finance, box_office, scanner, marketing, cross-venue manager, former-operator manager, fan
SELECT tap.login('22700000-0000-4000-8000-000000000103');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r1')$$,
  '42501', NULL, 'C5: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r2')$$,
  '42501', NULL, 'C6: venue_finance is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r3')$$,
  '42501', NULL, 'C7: venue_box_office is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r4')$$,
  '42501', NULL, 'C8: venue_scanner is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r5')$$,
  '42501', NULL, 'C9: venue_marketing is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r6')$$,
  '42501', NULL, 'C10: the CROSS-venue manager (Room V3) is refused on Room V1''s tier');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000051', 'hidden', 'x', 'ck227-v-r7')$$,
  '42501', NULL, 'C11: E-76 — the FORMER-OPERATOR manager (Room V2, now Org B) is refused on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r8')$$,
  '42501', NULL, 'C12: a fan is refused');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r9')$$,
  '42501', NULL, 'C13: anon has no EXECUTE (and no USAGE on venue)');
SELECT tap.logout();
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', 'ck227-v-r10')$$,
  '42501', NULL, 'C14: no auth.uid() -> insufficient_privilege (authentication required)');
-- input rules (as the owner)
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT throws_like($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'secret', 'x', 'ck227-v-i1')$$,
  'invalid_input: bad visibility%', 'C15: a visibility outside {hidden,public,door_only} is invalid_input');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', 'x', '   ')$$,
  'P0001', 'precondition_failed: command key required', 'C16: an empty command key is refused (081:194-196 rule)');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000011', 'public', NULL, 'ck227-v-i3')$$,
  'P0001', 'precondition_failed: reason_required', 'C17: a visibility change requires a reason code (the set_ticket_type_price rule)');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-0000000000ff', 'public', 'x', 'ck227-v-i4')$$,
  'P0002', NULL, 'C18: an unknown ticket type is not_found');
-- terminal events
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000031', 'hidden', 'x', 'ck227-v-t1')$$,
  'P0001', 'precondition_failed: event_terminal', 'C19: refused on a COMPLETED event');
SELECT throws_ok($$SELECT venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000041', 'hidden', 'x', 'ck227-v-t2')$$,
  'P0001', 'precondition_failed: event_terminal', 'C20: refused on a CANCELLED event');
SELECT is((venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000022', 'public', 'open_table', 'ck227-v-4') ->> 'status'), 'ok',
  'C21: allowed on an ON_SALE event (door_only -> public)');
-- same-value call: noop, no audit row
SELECT is(venue.set_ticket_type_visibility('22700000-0000-4000-8000-000000000022', 'public', 'again', 'ck227-v-5'),
  jsonb_build_object('status','noop','ticket_type_id','22700000-0000-4000-8000-000000000022','visibility','public'),
  'C22: the same value returns {status noop}');
SELECT tap.logout();
-- audit: exactly one row per real change, before/after, reason, actor
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.visibility_change'
            AND subject_kind = 'ticket_type' AND subject_id = '22700000-0000-4000-8000-000000000022'), 1,
  'C23: exactly ONE audit row for the on-sale tier (C21 wrote it; the noop C22 did not)');
SELECT is((SELECT before::text || ' -> ' || after::text || ' / ' || reason_code || ' / ' || actor_identity::text
             FROM kernel.admin_audit WHERE action = 'ticket_type.visibility_change'
              AND subject_id = '22700000-0000-4000-8000-000000000022'),
  '{"visibility": "door_only"} -> {"visibility": "public"} / open_table / 22700000-0000-4000-8000-000000000101',
  'C24: the audit row carries before/after visibility, the reason code and the actor');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.visibility_change'
            AND subject_id = '22700000-0000-4000-8000-000000000011'), 3,
  'C25: three audit rows for the draft tier — C1, C2, C3; none for the eight refusals');

-- ── Section D — set_ticket_type_rank ─────────────────────────────────────────
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT is(venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 10::smallint, 'ck227-r-1'),
  jsonb_build_object('status','ok','ticket_type_id','22700000-0000-4000-8000-000000000011','display_rank',10),
  'D1: org_owner ranks the draft tier 10 — {status ok, id, display_rank}');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000102');
SELECT is((venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 20::smallint, 'ck227-r-2') ->> 'display_rank'), '20',
  'D2: org_admin re-ranks to 20');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000111');
SELECT is((venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 30::smallint, 'ck227-r-3') ->> 'display_rank'), '30',
  'D3: the BOUND venue_manager re-ranks to 30');
SELECT tap.logout();
SELECT is((SELECT display_rank FROM venue.ticket_type WHERE ticket_type_id = '22700000-0000-4000-8000-000000000011'), 30::smallint,
  'D4: the rank is persisted');
SELECT tap.login('22700000-0000-4000-8000-000000000103');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x1')$$,
  '42501', NULL, 'D5: org_finance is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x2')$$,
  '42501', NULL, 'D6: venue_finance is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x3')$$,
  '42501', NULL, 'D7: venue_box_office is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x4')$$,
  '42501', NULL, 'D8: venue_scanner is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x5')$$,
  '42501', NULL, 'D9: venue_marketing is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x6')$$,
  '42501', NULL, 'D10: the CROSS-venue manager is refused');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000051', 1::smallint, 'ck227-r-x7')$$,
  '42501', NULL, 'D11: E-76 — the FORMER-OPERATOR manager is refused on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x8')$$,
  '42501', NULL, 'D12: a fan is refused');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x9')$$,
  '42501', NULL, 'D13: anon has no EXECUTE');
SELECT tap.logout();
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, 'ck227-r-x10')$$,
  '42501', NULL, 'D14: no auth.uid() -> insufficient_privilege');
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT throws_like($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1000::smallint, 'ck227-r-i1')$$,
  'invalid_input: bad display_rank%', 'D15: 1000 is outside 0..999 -> invalid_input (before the CHECK)');
SELECT throws_like($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', (-1)::smallint, 'ck227-r-i2')$$,
  'invalid_input: bad display_rank%', 'D16: -1 is outside 0..999 -> invalid_input');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000011', 1::smallint, '')$$,
  'P0001', 'precondition_failed: command key required', 'D17: an empty command key is refused');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-0000000000ff', 1::smallint, 'ck227-r-i4')$$,
  'P0002', NULL, 'D18: an unknown ticket type is not_found');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000031', 1::smallint, 'ck227-r-t1')$$,
  'P0001', 'precondition_failed: event_terminal', 'D19: refused on a COMPLETED event');
SELECT throws_ok($$SELECT venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000041', 1::smallint, 'ck227-r-t2')$$,
  'P0001', 'precondition_failed: event_terminal', 'D20: refused on a CANCELLED event');
SELECT is((venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000021', 0::smallint, 'ck227-r-4') ->> 'display_rank'), '0',
  'D21: allowed on an ON_SALE event; 0 is a valid rank');
SELECT is(venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000021', 0::smallint, 'ck227-r-5'),
  jsonb_build_object('status','noop','ticket_type_id','22700000-0000-4000-8000-000000000021','display_rank',0),
  'D22: the same rank returns {status noop}');
SELECT is((venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000021', NULL::smallint, 'ck227-r-6') ->> 'status'), 'ok',
  'D23: NULL clears the rank (unranked is a state, not an error)');
SELECT tap.logout();
SELECT ok((SELECT display_rank IS NULL FROM venue.ticket_type WHERE ticket_type_id = '22700000-0000-4000-8000-000000000021'),
  'D24: the cleared rank is NULL on the table');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change'
            AND subject_id = '22700000-0000-4000-8000-000000000021'), 2,
  'D25: exactly TWO audit rows for the on-sale tier — D21 and D23; the noop D22 wrote none');
SELECT is((SELECT before::text || ' -> ' || after::text || ' / ' || reason_code || ' / ' || actor_identity::text
             FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change'
              AND subject_id = '22700000-0000-4000-8000-000000000021' AND after = '{"display_rank": 0}'::jsonb),
  '{"display_rank": null} -> {"display_rank": 0} / self_service / 22700000-0000-4000-8000-000000000101',
  'D26: the D21 audit row (selected by its after value: now() is frozen per transaction, so occurred_at cannot order the two rows) carries before NULL / after 0, reason self_service (no reason is required) and the actor');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'ticket_type.rank_change'
            AND subject_id = '22700000-0000-4000-8000-000000000011'), 3,
  'D27: three audit rows for the draft tier — D1, D2, D3; none for the refusals');

-- ── Section E — get_inventory_counters ───────────────────────────────────────
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT is((SELECT string_agg(batch_id::text || '|' || ticket_type_id::text || '|' || event_session_id::text || '|' || release_kind || '|'
                             || capacity || '|' || held || '|' || sold || '|' || remaining, ';' ORDER BY batch_id)
             FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')),
  '22700000-0000-4000-8000-0000000000c2|22700000-0000-4000-8000-000000000021|22700000-0000-4000-8000-0000000000f2|public_sale|300|6|120|174;'
  || '22700000-0000-4000-8000-0000000000c3|22700000-0000-4000-8000-000000000022|22700000-0000-4000-8000-0000000000f2|door|100|0|100|0',
  'E1: org_owner reads BOTH batches of the on-sale event with the raw capacity/held/sold/remaining (300|6|120|174 and 100|0|100|0 — the all-sold batch reads 0 remaining, never "unknown")');
SELECT is((SELECT capacity::text || '|' || held || '|' || sold || '|' || remaining FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')
            WHERE batch_id = '22700000-0000-4000-8000-0000000000c2'),
          tap._raw227('22700000-0000-4000-8000-0000000000c2'),
  'E2: the function''s row equals the raw venue.inventory_batch row read as the owner of the table');
SELECT ok((SELECT bool_and(remaining = capacity - held - sold) FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')),
  'E3: remaining = capacity - held - sold on every row');
SELECT is((SELECT count(*)::int FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e5')), 1,
  'E4: the event''s OWN org_owner (A) reads e5''s counters at the re-operated room (has_org_role_over_EVENT binds to the event''s org)');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000ee')$$,
  'P0002', NULL, 'E5: an unknown event is not_found (P0002)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000102');
SELECT is((SELECT count(*)::int FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')), 2,
  'E6: org_admin reads');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000103');
SELECT is((SELECT count(*)::int FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')), 2,
  'E7: org_finance reads');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000111');
SELECT is((SELECT count(*)::int FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')), 2,
  'E8: the bound venue_manager reads');
SELECT throws_ok($$SELECT capacity FROM venue.inventory_batch WHERE batch_id = '22700000-0000-4000-8000-0000000000c2'$$,
  '42501', NULL, 'E9: …while the same manager still cannot SELECT the raw column (E-29): the RPC result is the only route');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000112');
SELECT is((SELECT count(*)::int FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')), 2,
  'E10: venue_finance reads');
SELECT tap.logout();
-- unauthorized callers get the SAME P0002 as an unknown event (never zeros, never a role hint)
SELECT tap.login('22700000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  'P0002', NULL, 'E11: venue_box_office -> P0002 (excluded from the conservative default; owner decision item)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  'P0002', NULL, 'E12: venue_scanner -> P0002 (excluded from the conservative default; owner decision item)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  'P0002', NULL, 'E13: venue_marketing -> P0002');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  'P0002', NULL, 'E14: the cross-venue manager -> P0002');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e5')$$,
  'P0002', NULL, 'E15: E-76 — the former-operator manager -> P0002 on Org A''s event e5');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  'P0002', NULL, 'E16: a fan -> P0002, identical to an unknown event (no existence oracle)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000201');
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e5')$$,
  'P0002', NULL, 'E17: Org B''s owner -> P0002 on Org A''s event e5 (the counters read binds to the EVENT''s org, unlike the writers'' org arm)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  '42501', NULL, 'E18: anon has no EXECUTE');
SELECT tap.logout();
SELECT throws_ok($$SELECT * FROM venue.get_inventory_counters('22700000-0000-4000-8000-0000000000e2')$$,
  '42501', NULL, 'E19: no auth.uid() -> insufficient_privilege');
SELECT throws_ok($$UPDATE venue.inventory_batch SET held = 200, sold = 200 WHERE batch_id = '22700000-0000-4000-8000-0000000000c2'$$,
  '23514', NULL, 'E20: a planted held+sold>capacity write still aborts at the C27 oversell CHECK (160 touches no counter)');
SELECT ok(NOT has_column_privilege('authenticated', 'venue.inventory_batch', 'capacity', 'SELECT'),
  'E21: has_column_privilege(authenticated, venue.inventory_batch, capacity) stays false after 160');

-- ── Section F — display_rank through venue_api.ticket_types ─────────────────
SELECT is((SELECT count(*)::int FROM venue.ticket_type WHERE event_id IN ('22700000-0000-4000-8000-0000000000e3','22700000-0000-4000-8000-0000000000e4','22700000-0000-4000-8000-0000000000e5','22700000-0000-4000-8000-0000000000e6')
            AND display_rank IS NOT NULL), 0,
  'F1: display_rank is NULL by default on every untouched tier');
SELECT tap.login('22700000-0000-4000-8000-000000000101');
SELECT is((SELECT display_rank FROM venue_api.ticket_types WHERE ticket_type_id = '22700000-0000-4000-8000-000000000011'), 30::smallint,
  'F2: the org_owner reads the rank through venue_api.ticket_types (hidden tier, manager/org tier of 081 §9.1)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM venue_api.ticket_types WHERE ticket_type_id = '22700000-0000-4000-8000-000000000011'), 0,
  'F3: a fan still cannot see the hidden tier at all through venue_api (RLS unchanged by the appended column)');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000111');
SELECT is((venue.set_ticket_type_rank('22700000-0000-4000-8000-000000000021', 5::smallint, 'ck227-f-4') ->> 'display_rank'), '5',
  'F4: the manager ranks the on-sale PUBLIC tier 5');
SELECT tap.logout();
SELECT tap.login('22700000-0000-4000-8000-000000000199');
SELECT is((SELECT display_rank FROM venue_api.ticket_types WHERE ticket_type_id = '22700000-0000-4000-8000-000000000021'), 5::smallint,
  'F5: a fan reads display_rank of a PUBLIC tier through venue_api (081:988 table grant covers the new column; the dashboard sorts by it)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
