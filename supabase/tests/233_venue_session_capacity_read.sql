-- ============================================================================
-- 233_venue_session_capacity_read.sql — migration 20261027015000 (registry 166).
--
-- Registry 166 / pgTAP 233 — assigned by Claude A 2026-10-26 (registry 166/233).
-- A reviews before this leaves draft. DARK: applied nowhere; venue_api /
-- venue_cmd are not exposed (owner setting).
--
-- The CI grant gates read `public` only, so THIS FILE is the gate for 166's
-- objects (228 sweeps the venue_cmd schema, 226 the venue_api schema): shape,
-- prosecdef, search_path, volatility, language, the EXECUTE / SELECT matrix for
-- anon / authenticated / service_role / PUBLIC via has_function_privilege /
-- has_table_privilege and an exact aclexplode matrix, the view's columns /
-- options / ACL / owner, the absence of '*' in every body, the authority matrix
-- and the arithmetic.
--
--   Section A  shape + ACL: venue.get_session_capacity (plpgsql definer),
--              venue.list_session_capacity (sql definer), venue_cmd.
--              get_session_capacity (sql invoker; the NC3 target),
--              venue_api.session_capacity (the NC4 target); result types pinned
--              exactly (identity-free: five numbers, no batch, no held/sold).
--   Section B  THE AUTHORITY MATRIX, RUN AS AUTHENTICATED OPERATORS (tap.login)
--              through venue_cmd.get_session_capacity and venue_api.
--              session_capacity. Every read goes through a SECURITY INVOKER
--              helper that returns '<current_user>|<row>' or '<current_user>|
--              <sqlstate>|<message>', so every assertion also proves it ran as
--              `authenticated` (a postgres run bypasses every ACL and proves
--              nothing). org_owner / org_admin of the EVENT's org and the bound
--              venue_manager read; org_finance, venue_finance, box_office,
--              scanner, marketing, the cross-venue manager, Org B's owner and a
--              fan get P0002 byte-identical to an unknown session and see zero
--              view rows; a caller with the authenticated role but no uid gets
--              42501 from the body; anon gets 42501 at the ACL (no USAGE on
--              venue_cmd / venue_api / venue). UNCHANGED BY 165 (venue-role-arm
--              conjunct, 088 / 162 shape): on the re-operated room the read
--              answers exactly as 162's setter does, side by side.
--   Section C  ARITHMETIC = THE SETTER'S, proved at each boundary with values
--              TAKEN FROM THE READ (and pinned as literals): fixture capacity_hint
--              60, pool 50, batches 30 (public_sale) + 10 (comp) -> allocated 40,
--              remaining_to_allocate 10, capacity_hint 60; (i) pool := allocated -
--              1 refused below_allocated (the setter's own message names the same
--              allocated), pool := allocated accepted; (ii) pool := capacity_hint
--              + 1 refused above_venue_capacity, := capacity_hint accepted; (iii)
--              a batch of remaining_to_allocate + 1 refused
--              session_capacity_exceeded, of remaining_to_allocate accepted
--              (re-read: remaining 0); (iv) pool NULL -> sales_capacity NULL and
--              remaining_to_allocate NULL.
--
-- Fixture: 230 style, tag 23300000-…, inserted as postgres and rolled back.
-- Org A (owner 101, admin 102, org_finance 103) / Room V1 (capacity_hint 60;
-- manager 111, venue_finance 112, box_office 113, scanner 114, marketing 115)
-- with e1 on_sale (sessions f1 = the arithmetic room, pool 50 / 30 public_sale +
-- 10 comp; f2 pool NULL / 25) and e3 completed (f3 pool 20 / 20, sold out); Room
-- V2 created under Org A with Org A's event e5 (f5 pool 200 / 120) and its
-- venue_manager 121; THEN the re-operation of V2 to Org B, modelled with a DIRECT
-- `UPDATE catalog.venue SET org_id` AS POSTGRES — the RPC path (catalog.
-- update_venue's org_id patch) is frozen, Decision C ('operatorship_transfer_
-- frozen'), so this is the only way to reach the state; then Org B's own event e9
-- at V2 (f9 pool NULL / 40); Room V3 (Org B, capacity_hint 100; manager 131 = the
-- cross-venue manager) with e6 (f6 pool 80 / 50); Org B's owner 201; a fan 199.
-- Only f1 carries non-public_sale batches (comp; Section C adds a door batch), so
-- the NC2 mutant (public_sale-only `allocated`) moves f1's numbers and nothing
-- else.
-- Expected rows (sales_capacity|allocated|remaining_to_allocate|capacity_hint, '-' = NULL):
--   f1 50|40|10|60 · f2 -|25|-|60 · f3 20|20|0|60 · f5 200|120|80|- · f6 80|50|30|100 · f9 -|40|-|-
--
-- Expected on the 182 tree WITHOUT 166 (RED, predicted before the first run; the
-- reconciliation is in D's evidence dir, EVIDENCE-166.md): every 166 object is
-- reached only through the error-catching helpers, so nothing aborts and all 89
-- assertions are emitted. 12 pass: A25 (venue_api holds no function — vacuous),
-- B1 / B34 / C1 (current_user), B35-B38 (anon's 42501 is the SCHEMA wall, which
-- predates 166), B40 / B42 / B44 / B46 (162's setter halves of the status-quo
-- pairs — 166 does not touch the setter). 77 fail: A1-A24, B2-B33 except B1,
-- B39 / B41 / B43 / B45, C2-C18. Predicted RED run: 89 emitted = 77 not ok + 12 ok.
-- ============================================================================
BEGIN;
SELECT plan(89);

CREATE TABLE tap.memo_233 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store233(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_233 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch233(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_233 WHERE k = $1 $m$;
-- one text per capacity row: <session suffix>:sales_capacity|allocated|remaining_to_allocate|capacity_hint, '-' for NULL
CREATE FUNCTION tap._fmt233(s uuid, sc integer, al integer, rm integer, h integer) RETURNS text
LANGUAGE sql IMMUTABLE AS
$m$ SELECT substr(s::text, 35) || ':' || coalesce(sc::text, '-') || '|' || coalesce(al::text, '-') || '|' || coalesce(rm::text, '-') || '|' || coalesce(h::text, '-') $m$;
-- The 166 readers, called AS THE CALLER (SECURITY INVOKER, plpgsql: validated at first call, so the file runs on
-- the tree without 166). Each returns '<current_user>|<rows>' or '<current_user>|<sqlstate>|<message>' and never raises.
CREATE FUNCTION tap._cap233(p_s uuid) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text;
BEGIN
  SELECT string_agg(tap._fmt233(c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint), ';')
    INTO v FROM venue_cmd.get_session_capacity(p_s) c;
  RETURN current_user || '|' || coalesce(v, '<no row>');
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
CREATE FUNCTION tap._capd233(p_s uuid) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text;
BEGIN
  SELECT string_agg(tap._fmt233(c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint), ';')
    INTO v FROM venue.get_session_capacity(p_s) c;
  RETURN current_user || '|' || coalesce(v, '<no row>');
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
CREATE FUNCTION tap._capv233(p_s uuid) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text;
BEGIN
  SELECT string_agg(tap._fmt233(c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint), ';')
    INTO v FROM venue_api.session_capacity c WHERE c.session_id = p_s;
  RETURN current_user || '|' || coalesce(v, '<no row>');
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
-- the whole view, ordered by session_id ('' = zero rows)
CREATE FUNCTION tap._listv233() RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text;
BEGIN
  SELECT string_agg(tap._fmt233(c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint), ';' ORDER BY c.session_id)
    INTO v FROM venue_api.session_capacity c;
  RETURN current_user || '|' || coalesce(v, '');
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
-- the list function in ITS OWN order (WITH ORDINALITY numbers the rows as the function returns them)
CREATE FUNCTION tap._listf233() RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text;
BEGIN
  SELECT string_agg(tap._fmt233(c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint), ';' ORDER BY c.n)
    INTO v FROM venue.list_session_capacity() WITH ORDINALITY AS c(session_id, sales_capacity, allocated, remaining_to_allocate, capacity_hint, n);
  RETURN current_user || '|' || coalesce(v, '');
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
-- every view row compared with the single-session wrapper's row for the same session
CREATE FUNCTION tap._viewdiff233() RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE n integer; d integer;
BEGIN
  SELECT count(v.session_id)::integer,
         count(v.session_id) FILTER (WHERE tap._fmt233(v.session_id, v.sales_capacity, v.allocated, v.remaining_to_allocate, v.capacity_hint)
                                IS DISTINCT FROM (SELECT tap._fmt233(c.session_id, c.sales_capacity, c.allocated, c.remaining_to_allocate, c.capacity_hint)
                                                    FROM venue_cmd.get_session_capacity(v.session_id) c))::integer
    INTO n, d FROM venue_api.session_capacity v;
  RETURN current_user || '|rows=' || n || ' mismatched=' || d;
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
-- one number from the wrapper, as the caller (NULL when the read fails) — the boundary inputs of Section C come from HERE
CREATE FUNCTION tap._val233(p_s uuid, p_col text) RETURNS integer LANGUAGE plpgsql AS
$m$ DECLARE v integer;
BEGIN
  SELECT CASE p_col WHEN 'pool' THEN c.sales_capacity WHEN 'allocated' THEN c.allocated
                    WHEN 'remaining' THEN c.remaining_to_allocate WHEN 'hint' THEN c.capacity_hint END
    INTO v FROM venue_cmd.get_session_capacity(p_s) c;
  RETURN v;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END $m$;
-- run one statement AS THE CALLER and return '<current_user>|<result text>' or '<current_user>|<sqlstate>|<message>'
CREATE FUNCTION tap._exec233(q text) RETURNS text LANGUAGE plpgsql AS
$m$ DECLARE v text;
BEGIN
  EXECUTE q INTO v;
  RETURN current_user || '|' || coalesce(v, '<null>');
EXCEPTION WHEN OTHERS THEN
  RETURN current_user || '|' || SQLSTATE || '|' || SQLERRM;
END $m$;
-- the authenticated ROLE with NO uid in the claims (auth.uid() NULL behind the ACL)
CREATE FUNCTION tap._login_nouid233() RETURNS void LANGUAGE plpgsql AS
$m$ BEGIN
  PERFORM set_config('request.jwt.claims', '{"role":"authenticated"}', true);
  PERFORM set_config('role', 'authenticated', true);
END $m$;
-- definer raw reads of venue.inventory_batch (capacity is withheld from every client role, 081 E-29)
CREATE FUNCTION tap._alloc233(s uuid) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT coalesce(sum(b.capacity), 0)::integer FROM venue.inventory_batch b WHERE b.event_session_id = s $m$;
CREATE FUNCTION tap._allocps233(s uuid) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT coalesce(sum(b.capacity), 0)::integer FROM venue.inventory_batch b WHERE b.event_session_id = s AND b.release_kind = 'public_sale' $m$;
CREATE FUNCTION tap._kinds233(s uuid) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT count(DISTINCT b.release_kind)::integer FROM venue.inventory_batch b WHERE b.event_session_id = s $m$;
GRANT EXECUTE ON FUNCTION tap._store233(text, text), tap._fetch233(text), tap._fmt233(uuid, integer, integer, integer, integer),
                          tap._cap233(uuid), tap._capd233(uuid), tap._capv233(uuid), tap._listv233(), tap._listf233(),
                          tap._viewdiff233(), tap._val233(uuid, text), tap._exec233(text), tap._login_nouid233(),
                          tap._alloc233(uuid), tap._allocps233(uuid), tap._kinds233(uuid) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('23300000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.233@test.local',       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.a.233@test.local',       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000103', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.a.233@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.233@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.v1.233@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'box.v1.233@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000114', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v1.233@test.local',       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000115', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v1.233@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.233@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v3.cross.233@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.233@test.local',           '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23300000-0000-4000-8000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.b.233@test.local',       '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('23300000-0000-4000-8000-00000000000a', 'Org A 233', 'Org A 233', 'active'),
  ('23300000-0000-4000-8000-00000000000b', 'Org B 233', 'Org B 233', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('23300000-0000-4000-8000-00000000000a', '23300000-0000-4000-8000-000000000101', 'org_owner'),
  ('23300000-0000-4000-8000-00000000000a', '23300000-0000-4000-8000-000000000102', 'org_admin'),
  ('23300000-0000-4000-8000-00000000000a', '23300000-0000-4000-8000-000000000103', 'org_finance'),
  ('23300000-0000-4000-8000-00000000000b', '23300000-0000-4000-8000-000000000201', 'org_owner');
-- V2 is created under Org A (its event e5 is stamped Org A below), then moved. V1 carries capacity_hint 60, V3 100.
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status, capacity_hint) VALUES
  ('23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-00000000000a', 'Room V1 233', 'wynwood',  'approved', 60),
  ('23300000-0000-4000-8000-0000000000a2', '23300000-0000-4000-8000-00000000000a', 'Room V2 233', 'brickell', 'approved', NULL),
  ('23300000-0000-4000-8000-0000000000b3', '23300000-0000-4000-8000-00000000000b', 'Room V3 233', 'midtown',  'approved', 100);
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-000000000111', 'venue_manager'),
  ('23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-000000000112', 'venue_finance'),
  ('23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-000000000113', 'venue_box_office'),
  ('23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-000000000115', 'venue_marketing'),
  ('23300000-0000-4000-8000-0000000000a2', '23300000-0000-4000-8000-000000000121', 'venue_manager'),
  ('23300000-0000-4000-8000-0000000000b3', '23300000-0000-4000-8000-000000000131', 'venue_manager');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23300000-0000-4000-8000-0000000000e1', '23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-00000000000a', 'V1 on sale 233',   'on_sale'),
  ('23300000-0000-4000-8000-0000000000e3', '23300000-0000-4000-8000-0000000000a1', '23300000-0000-4000-8000-00000000000a', 'V1 completed 233', 'completed'),
  ('23300000-0000-4000-8000-0000000000e5', '23300000-0000-4000-8000-0000000000a2', '23300000-0000-4000-8000-00000000000a', 'V2 (A event) 233', 'on_sale'),
  ('23300000-0000-4000-8000-0000000000e6', '23300000-0000-4000-8000-0000000000b3', '23300000-0000-4000-8000-00000000000b', 'V3 (B event) 233', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status, sales_capacity) VALUES
  ('23300000-0000-4000-8000-0000000000f1', '23300000-0000-4000-8000-0000000000e1', now() + interval '3 days', 'scheduled', 50),
  ('23300000-0000-4000-8000-0000000000f2', '23300000-0000-4000-8000-0000000000e1', now() + interval '4 days', 'scheduled', NULL),
  ('23300000-0000-4000-8000-0000000000f3', '23300000-0000-4000-8000-0000000000e3', now() - interval '3 days', 'completed', 20),
  ('23300000-0000-4000-8000-0000000000f5', '23300000-0000-4000-8000-0000000000e5', now() + interval '7 days', 'scheduled', 200),
  ('23300000-0000-4000-8000-0000000000f6', '23300000-0000-4000-8000-0000000000e6', now() + interval '9 days', 'scheduled', 80);
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('23300000-0000-4000-8000-000000000011', '23300000-0000-4000-8000-0000000000e1', 'admission', 'GA 233',        2500, 'public'),
  ('23300000-0000-4000-8000-000000000012', '23300000-0000-4000-8000-0000000000e1', 'admission', 'Comp 233',      1000, 'hidden'),
  ('23300000-0000-4000-8000-000000000031', '23300000-0000-4000-8000-0000000000e3', 'admission', 'GA done 233',   2700, 'public'),
  ('23300000-0000-4000-8000-000000000051', '23300000-0000-4000-8000-0000000000e5', 'admission', 'GA V2 233',     4000, 'public'),
  ('23300000-0000-4000-8000-000000000061', '23300000-0000-4000-8000-0000000000e6', 'admission', 'GA V3 233',     3300, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('23300000-0000-4000-8000-0000000000c1', '23300000-0000-4000-8000-000000000011', '23300000-0000-4000-8000-0000000000f1', 'public_sale', 30, 0, 5),
  ('23300000-0000-4000-8000-0000000000c2', '23300000-0000-4000-8000-000000000012', '23300000-0000-4000-8000-0000000000f1', 'comp',        10, 0, 0),
  ('23300000-0000-4000-8000-0000000000c3', '23300000-0000-4000-8000-000000000011', '23300000-0000-4000-8000-0000000000f2', 'public_sale', 25, 0, 0),
  ('23300000-0000-4000-8000-0000000000c4', '23300000-0000-4000-8000-000000000031', '23300000-0000-4000-8000-0000000000f3', 'public_sale', 20, 0, 20),
  ('23300000-0000-4000-8000-0000000000c5', '23300000-0000-4000-8000-000000000051', '23300000-0000-4000-8000-0000000000f5', 'public_sale', 120, 0, 15),
  ('23300000-0000-4000-8000-0000000000c6', '23300000-0000-4000-8000-000000000061', '23300000-0000-4000-8000-0000000000f6', 'public_sale', 50, 0, 2);
-- THE RE-OPERATION of Room V2 (Org A -> Org B), modelled with a DIRECT UPDATE AS POSTGRES: catalog.update_venue's
-- org_id patch is frozen (Decision C, 'operatorship_transfer_frozen'), so no RPC reaches this state. e5 keeps
-- org_id = A (a tenancy move does not re-stamp events); 121's venue_manager row (granted under Org A) survives.
UPDATE catalog.venue SET org_id = '23300000-0000-4000-8000-00000000000b'
 WHERE venue_id = '23300000-0000-4000-8000-0000000000a2';
-- Org B's own event at the room it now operates (created after the move)
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23300000-0000-4000-8000-0000000000e9', '23300000-0000-4000-8000-0000000000a2', '23300000-0000-4000-8000-00000000000b', 'V2 (B event) 233', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status, sales_capacity) VALUES
  ('23300000-0000-4000-8000-0000000000f9', '23300000-0000-4000-8000-0000000000e9', now() + interval '11 days', 'scheduled', NULL);
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('23300000-0000-4000-8000-000000000091', '23300000-0000-4000-8000-0000000000e9', 'admission', 'GA V2 B 233', 3500, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('23300000-0000-4000-8000-0000000000c9', '23300000-0000-4000-8000-000000000091', '23300000-0000-4000-8000-0000000000f9', 'public_sale', 40, 0, 0);
-- expected rows: f1 50|40|10|60 · f2 -|25|-|60 · f3 20|20|0|60 · f5 200|120|80|- · f6 80|50|30|100 · f9 -|40|-|-

-- ── Section A — shape + ACL (NULL-safe: `not ok`, never an abort, on the tree without 166) ──
SELECT has_function('venue'::name, 'get_session_capacity'::name, ARRAY['uuid']::name[],
  'A1: venue.get_session_capacity(uuid) exists');
SELECT has_function('venue'::name, 'list_session_capacity'::name, '{}'::name[],
  'A2: venue.list_session_capacity() exists');
SELECT has_function('venue_cmd'::name, 'get_session_capacity'::name, ARRAY['uuid']::name[],
  'A3: venue_cmd.get_session_capacity(uuid) exists');
SELECT has_view('venue_api'::name, 'session_capacity'::name, 'A4: venue_api.session_capacity exists');
SELECT is(pg_get_function_result(to_regprocedure('venue.get_session_capacity(uuid)')),
  'TABLE(session_id uuid, sales_capacity integer, allocated integer, remaining_to_allocate integer, capacity_hint integer)',
  'A5: get_session_capacity returns EXACTLY (session_id, sales_capacity, allocated, remaining_to_allocate, capacity_hint) — identity-free: no batch, no held, no sold');
SELECT is(pg_get_function_result(to_regprocedure('venue.list_session_capacity()')),
  'TABLE(session_id uuid, sales_capacity integer, allocated integer, remaining_to_allocate integer, capacity_hint integer)',
  'A6: list_session_capacity returns the same five columns');
SELECT ok(coalesce(pg_get_function_identity_arguments(to_regprocedure('venue_cmd.get_session_capacity(uuid)'))
                 = pg_get_function_identity_arguments(to_regprocedure('venue.get_session_capacity(uuid)'))
           AND pg_get_function_result(to_regprocedure('venue_cmd.get_session_capacity(uuid)'))
                 = pg_get_function_result(to_regprocedure('venue.get_session_capacity(uuid)')), false),
  'A7: the venue_cmd wrapper''s argument list and result type equal the venue target''s');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname IN ('get_session_capacity','list_session_capacity')
              AND p.prosecdef AND 'search_path=""' = ANY (p.proconfig) AND p.provolatile = 's'), 2,
  'A8: both venue reads are SECURITY DEFINER, search_path pinned to '''' (066 invariant) and STABLE');
SELECT is((SELECT string_agg(p.proname || '=' || l.lanname, ',' ORDER BY p.proname) FROM pg_proc p
             JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue' AND p.proname IN ('get_session_capacity','list_session_capacity')),
  'get_session_capacity=plpgsql,list_session_capacity=sql',
  'A9: get_session_capacity is plpgsql (it raises), list_session_capacity is LANGUAGE sql (it omits)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'get_session_capacity'
              AND NOT p.prosecdef AND l.lanname = 'sql' AND 'search_path=""' = ANY (p.proconfig) AND p.provolatile = 's'
              AND p.prosrc LIKE '%venue.get_session_capacity(%'), 1,
  'A10: the wrapper is SECURITY INVOKER (prosecdef = false), LANGUAGE sql, search_path pinned, STABLE and delegates to venue.get_session_capacity (the NC3 target)');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname IN ('get_session_capacity','list_session_capacity') AND a.grantee <> p.proowner $$,
  $$ VALUES ('get_session_capacity:authenticated:EXECUTE'), ('list_session_capacity:authenticated:EXECUTE') $$,
  'A11: the two venue reads grant EXECUTE to authenticated and to NOBODY else (aclexplode: no PUBLIC, anon, service_role)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd' AND p.proname = 'get_session_capacity' AND a.grantee <> p.proowner AND p.proacl IS NOT NULL $$,
  $$ VALUES ('authenticated:EXECUTE') $$,
  'A12: the wrapper''s ACL is exactly EXECUTE to authenticated and is not DEFAULTED (no PUBLIC row)');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.get_session_capacity(uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.list_session_capacity()'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue_cmd.get_session_capacity(uuid)'), 'EXECUTE'), true),
  'A13: has_function_privilege(anon, EXECUTE) is false on all three');
SELECT ok(NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.get_session_capacity(uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.list_session_capacity()'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue_cmd.get_session_capacity(uuid)'), 'EXECUTE'), true),
  'A14: has_function_privilege(service_role, EXECUTE) is false on all three (explicit REVOKE; no server-side caller)');
SELECT ok(NOT coalesce(has_function_privilege('public', to_regprocedure('venue.get_session_capacity(uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('public', to_regprocedure('venue.list_session_capacity()'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('public', to_regprocedure('venue_cmd.get_session_capacity(uuid)'), 'EXECUTE'), true),
  'A15: has_function_privilege(PUBLIC, EXECUTE) is false on all three');
SELECT ok(coalesce(has_function_privilege('authenticated', to_regprocedure('venue.get_session_capacity(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.list_session_capacity()'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue_cmd.get_session_capacity(uuid)'), 'EXECUTE'), false),
  'A16: has_function_privilege(authenticated, EXECUTE) is true on all three');
SELECT is((SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = to_regclass('venue_api.session_capacity') AND a.attnum > 0 AND NOT a.attisdropped),
  'session_id,sales_capacity,allocated,remaining_to_allocate,capacity_hint',
  'A17: the view projects exactly session_id, sales_capacity, allocated, remaining_to_allocate, capacity_hint in that order');
SELECT is((SELECT count(*)::int FROM pg_class c CROSS JOIN LATERAL unnest(c.reloptions) o
            WHERE c.oid = to_regclass('venue_api.session_capacity') AND o IN ('security_invoker=true','security_barrier=true')), 2,
  'A18: the view is security_invoker AND security_barrier (159''s form)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE c.oid = to_regclass('venue_api.session_capacity') AND a.grantee <> c.relowner $$,
  $$ VALUES ('authenticated:SELECT') $$,
  'A19: the view''s ACL is exactly SELECT to authenticated (aclexplode: no write, no anon, no PUBLIC, no service_role — the NC4 target)');
SELECT ok(NOT coalesce(has_table_privilege('anon', to_regclass('venue_api.session_capacity'), 'SELECT'), true)
      AND NOT coalesce(has_table_privilege('service_role', to_regclass('venue_api.session_capacity'), 'SELECT'), true)
      AND NOT coalesce(has_table_privilege('public', to_regclass('venue_api.session_capacity'), 'SELECT'), true),
  'A20: has_table_privilege(anon | service_role | PUBLIC, SELECT) is false on the view');
SELECT ok(coalesce(has_table_privilege('authenticated', to_regclass('venue_api.session_capacity'), 'SELECT'), false)
      AND NOT coalesce(has_table_privilege('authenticated', to_regclass('venue_api.session_capacity'), 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER'), true),
  'A21: has_table_privilege(authenticated): SELECT true, every write privilege false');
SELECT ok(coalesce((SELECT c.relowner = n.nspowner AND c.relowner::regrole::text = 'postgres'
                      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                     WHERE c.oid = to_regclass('venue_api.session_capacity')), false),
  'A22: the view''s owner is postgres = venue_api''s owner (the migration runner, as 159''s eight and 163''s session_admissions)');
SELECT ok(coalesce((SELECT pg_get_viewdef(c.oid) LIKE '%venue.list_session_capacity()%' AND position('*' IN pg_get_viewdef(c.oid)) = 0
                      FROM pg_class c WHERE c.oid = to_regclass('venue_api.session_capacity')), false),
  'A23: the view is defined over venue.list_session_capacity() with an explicit column list (no SELECT *)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE ((n.nspname = 'venue' AND p.proname IN ('get_session_capacity','list_session_capacity'))
                   OR (n.nspname = 'venue_cmd' AND p.proname = 'get_session_capacity'))
              AND position('*' IN p.prosrc) = 0), 3,
  'A24: none of the three bodies contains a ''*'' — every column is named (no select *, no b.*)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_api'), 0,
  'A25: venue_api still holds no function (226 A3: the definer bodies live in venue)');

-- ── Section B — the authority matrix, AS AUTHENTICATED OPERATORS ─────────────
SELECT tap.login('23300000-0000-4000-8000-000000000101');
SELECT is(current_user::text, 'authenticated',
  'B1: the matrix runs AS authenticated (tap.login) — a postgres run would bypass every ACL and prove nothing; every helper below also returns current_user');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:50|40|10|60',
  'B2: org_owner of the EVENT''s org reads f1 through venue_cmd — pool 50, allocated 40 (30 public_sale + 10 comp), remaining 10, capacity_hint 60');
SELECT is(tap._listv233(), 'authenticated|f1:50|40|10|60;f2:-|25|-|60;f3:20|20|0|60;f5:200|120|80|-',
  'B3: venue_api.session_capacity as org_owner A = every session of Org A''s events (incl. the completed f3 and e5''s f5 at the re-operated room), none of Org B''s');
SELECT is(tap._listf233(), 'authenticated|f3:20|20|0|60;f1:50|40|10|60;f2:-|25|-|60;f5:200|120|80|-',
  'B4: venue.list_session_capacity() returns them in starts_at order (f3 in the past first)');
SELECT is(tap._capd233('23300000-0000-4000-8000-0000000000f1'), tap._cap233('23300000-0000-4000-8000-0000000000f1'),
  'B5: the venue_cmd wrapper returns the direct definer''s row');
SELECT is(tap._viewdiff233(), 'authenticated|rows=4 mismatched=0',
  'B6: every view row equals venue_cmd.get_session_capacity''s row for the same session (view row = function row)');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000102');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f2'), 'authenticated|f2:-|25|-|60',
  'B7: org_admin reads f2 — pool NULL (unlimited) -> remaining_to_allocate NULL; allocated still counted (25)');
SELECT is(tap._listv233(), 'authenticated|f1:50|40|10|60;f2:-|25|-|60;f3:20|20|0|60;f5:200|120|80|-',
  'B8: the view as org_admin A = the same four sessions');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000111');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:50|40|10|60',
  'B9: the bound venue_manager of V1 reads f1');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f3'), 'authenticated|f3:20|20|0|60',
  'B10: a COMPLETED event''s session is readable (the read refuses nothing but authority; the setter refuses to change it)');
SELECT is(tap._listv233(), 'authenticated|f1:50|40|10|60;f2:-|25|-|60;f3:20|20|0|60',
  'B11: the view as V1''s manager = V1''s three sessions only');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000ff'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000ff',
  'B12: an unknown session -> not_found (P0002), even for an authorized operator');
SELECT tap.logout();
-- refused labels: the SAME P0002 text as an unknown session on a REAL session, and zero view rows
SELECT tap.login('23300000-0000-4000-8000-000000000103');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B13: org_finance of the event''s org -> P0002 (the setter refuses it; no number to plan with)');
SELECT is(tap._listv233(), 'authenticated|', 'B14: org_finance sees zero view rows');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000112');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B15: venue_finance -> P0002');
SELECT is(tap._listv233(), 'authenticated|', 'B16: venue_finance sees zero view rows');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000113');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B17: venue_box_office -> P0002');
SELECT is(tap._listv233(), 'authenticated|', 'B18: venue_box_office sees zero view rows');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000114');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B19: venue_scanner -> P0002');
SELECT is(tap._listv233(), 'authenticated|', 'B20: venue_scanner sees zero view rows');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000115');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B21: venue_marketing -> P0002');
SELECT is(tap._listv233(), 'authenticated|', 'B22: venue_marketing sees zero view rows');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000131');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B23: the CROSS-venue manager (V3) -> P0002 on V1''s session');
SELECT is(tap._listv233(), 'authenticated|f6:80|50|30|100',
  'B24: the view as the V3 manager = V3''s f6 only (nothing of V1 or V2)');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f6'), 'authenticated|f6:80|50|30|100',
  'B25: …and the same manager reads its own room''s f6 (positive control: the persona is a working manager)');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000199');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B26: a fan -> P0002');
SELECT is(tap._listv233(), 'authenticated|', 'B27: the view as a fan = zero rows');
SELECT ok(tap._cap233('23300000-0000-4000-8000-0000000000f1') LIKE 'authenticated|P0002|%'
          AND replace(tap._cap233('23300000-0000-4000-8000-0000000000f1'), '23300000-0000-4000-8000-0000000000f1', '<id>')
            = replace(tap._cap233('23300000-0000-4000-8000-0000000000ff'), '23300000-0000-4000-8000-0000000000ff', '<id>'),
  'B28: no existence oracle — the fan''s refusal on a REAL session is byte-identical to an unknown session''s (same SQLSTATE, same text but the id)');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000201');
SELECT is(tap._listv233(), 'authenticated|f6:80|50|30|100;f9:-|40|-|-',
  'B29: the view as Org B''s owner = Org B''s events only (f6 at V3, f9 at V2) — not e5''s f5, Org A''s event at the room B now operates');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f1',
  'B30: Org B''s owner -> P0002 on Org A''s session at V1');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000121');
SELECT is(tap._listv233(), 'authenticated|f9:-|40|-|-',
  'B31: the view as V2''s former-operator manager = f9 only (Org B''s event at V2) — e5''s f5 is omitted (E-76)');
SELECT tap.logout();
SELECT tap._login_nouid233();
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|42501|insufficient_privilege: authentication required',
  'B32: the authenticated ROLE with no uid in its claims passes the ACL and is refused by the body: 42501 authentication required, never a row');
SELECT is(tap._listv233(), 'authenticated|', 'B33: …and sees zero view rows (the set-returning read omits; it does not raise)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT is(current_user::text, 'anon', 'B34: anon persona (tap.login_anon)');
SELECT throws_ok($$SELECT * FROM venue_cmd.get_session_capacity('23300000-0000-4000-8000-0000000000f1')$$,
  '42501', 'permission denied for schema venue_cmd', 'B35: anon -> 42501 AT THE ACL (no USAGE on venue_cmd), not the body''s authentication refusal');
SELECT throws_ok($$SELECT * FROM venue_api.session_capacity$$,
  '42501', 'permission denied for schema venue_api', 'B36: anon -> 42501 at the ACL on the view (no USAGE on venue_api)');
SELECT throws_ok($$SELECT * FROM venue.get_session_capacity('23300000-0000-4000-8000-0000000000f1')$$,
  '42501', 'permission denied for schema venue', 'B37: anon -> 42501 at the ACL on the definer (no USAGE on venue, 076/E-30)');
SELECT throws_ok($$SELECT * FROM venue.list_session_capacity()$$,
  '42501', 'permission denied for schema venue', 'B38: anon -> 42501 at the ACL on the list definer');
SELECT tap.logout();
-- UNCHANGED BY 165: the re-operated Room V2 (moved Org A -> Org B by the direct UPDATE above). The read answers
-- exactly as 162's setter does — each pair asserts the read and the setter (venue_cmd.set_session_sales_capacity)
-- for the same caller and session. 165 (2026-10-27) put the E-76 conjunct on the VENUE-ROLE arm of the four catalog
-- event bodies — the rule 162's setter and this read already apply — and left the org arm alone (088 / 162 precedent),
-- so none of these pairs moves; the labels say so. A later change to this rule must still flip setter and read together.
SELECT tap.login('23300000-0000-4000-8000-000000000121');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f5'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f5',
  'B39: UNCHANGED BY 165 — the former-operator manager on Org A''s event e5 at the re-operated V2: read REFUSED (E-76: venue.org_id B <> event.org_id A)');
SELECT is(tap._exec233($q$SELECT venue_cmd.set_session_sales_capacity('23300000-0000-4000-8000-0000000000f5', 200, 'x', 'ck233-sq-1')::text$q$),
  'authenticated|42501|insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required',
  'B40: UNCHANGED BY 165 — …and 162''s setter refuses the same caller on the same session today (42501): read = setter');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f9'), 'authenticated|f9:-|40|-|-',
  'B41: UNCHANGED BY 165 — the former-operator manager on Org B''s (the NEW operator''s) event e9 at V2: read ACCEPTED (his V2 role row outlived the move; venue.org_id = event.org_id)');
SELECT is(tap._exec233($q$SELECT venue_cmd.set_session_sales_capacity('23300000-0000-4000-8000-0000000000f9', NULL, 'x', 'ck233-sq-2')::text$q$),
  'authenticated|' || jsonb_build_object('status','noop','session_id','23300000-0000-4000-8000-0000000000f9'::uuid,'sales_capacity',NULL::integer,'allocated',40)::text,
  'B42: UNCHANGED BY 165 — …and the setter accepts him there today (authority passed; same value = noop): read = setter');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000201');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f5'), 'authenticated|P0002|not_found: session 23300000-0000-4000-8000-0000000000f5',
  'B43: UNCHANGED BY 165 — the NEW operator''s (Org B''s) owner on Org A''s event e5 at the room B now operates: read REFUSED (the org arm binds to the EVENT''s org)');
SELECT is(tap._exec233($q$SELECT venue_cmd.set_session_sales_capacity('23300000-0000-4000-8000-0000000000f5', 200, 'x', 'ck233-sq-3')::text$q$),
  'authenticated|42501|insufficient_privilege: venue_manager (current operator) or org_owner/org_admin required',
  'B44: UNCHANGED BY 165 — …and the setter refuses Org B''s owner there today (42501): read = setter');
SELECT tap.logout();
SELECT tap.login('23300000-0000-4000-8000-000000000101');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f5'), 'authenticated|f5:200|120|80|-',
  'B45: UNCHANGED BY 165 — the event''s OWN org_owner (A) on e5 at the room Org B now operates: read ACCEPTED (capacity_hint of V2 is NULL)');
SELECT is(tap._exec233($q$SELECT venue_cmd.set_session_sales_capacity('23300000-0000-4000-8000-0000000000f5', 200, 'x', 'ck233-sq-4')::text$q$),
  'authenticated|' || jsonb_build_object('status','noop','session_id','23300000-0000-4000-8000-0000000000f5'::uuid,'sales_capacity',200,'allocated',120)::text,
  'B46: UNCHANGED BY 165 — …and the setter accepts Org A''s owner there today (same value = noop; allocated 120 = the read''s): read = setter');
SELECT tap.logout();

-- ── Section C — the arithmetic IS the setter's (f1: capacity_hint 60, pool 50, 30 public_sale + 10 comp) ──
-- Every boundary input below is TAKEN FROM THE READ (tap._val233 through venue_cmd, as the bound manager) and
-- stored before use, so the statement order is explicit; the literals pin the same numbers independently.
SELECT tap.login('23300000-0000-4000-8000-000000000111');
SELECT is(current_user::text, 'authenticated', 'C1: Section C runs AS authenticated (the bound venue_manager of V1)');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:50|40|10|60',
  'C2: the read before any edit: sales_capacity 50, allocated 40, remaining_to_allocate 10, capacity_hint 60');
SELECT ok(tap._val233('23300000-0000-4000-8000-0000000000f1', 'allocated') = tap._alloc233('23300000-0000-4000-8000-0000000000f1')
          AND tap._allocps233('23300000-0000-4000-8000-0000000000f1') = 30 AND tap._kinds233('23300000-0000-4000-8000-0000000000f1') = 2,
  'C3: allocated (40) = the raw SUM over EVERY release_kind (public_sale 30 + comp 10) — a public_sale-only sum would read 30');
-- (i) the lower boundary: the read's allocated
SELECT tap._store233('alloc0', tap._val233('23300000-0000-4000-8000-0000000000f1', 'allocated')::text);
SELECT is(tap._exec233(format('SELECT venue_cmd.set_session_sales_capacity(%L, %s, %L, %L)::text',
                              '23300000-0000-4000-8000-0000000000f1', tap._fetch233('alloc0')::integer - 1, 'shrink', 'ck233-c-4')),
          format('authenticated|P0001|precondition_failed: below_allocated (new=%s < allocated=%s)',
                 tap._fetch233('alloc0')::integer - 1, tap._fetch233('alloc0')::integer),
  'C4: (i) pool := the read''s allocated - 1 (39) is REFUSED below_allocated, and the setter''s own message names allocated = the read''s allocated (40)');
SELECT is(tap._exec233(format('SELECT venue_cmd.set_session_sales_capacity(%L, %s, %L, %L)::text',
                              '23300000-0000-4000-8000-0000000000f1', tap._fetch233('alloc0')::integer, 'fit', 'ck233-c-5')),
          'authenticated|' || jsonb_build_object('status','ok','session_id','23300000-0000-4000-8000-0000000000f1'::uuid,
                                                 'sales_capacity', tap._fetch233('alloc0')::integer, 'allocated', tap._fetch233('alloc0')::integer)::text,
  'C5: (i) pool := the read''s allocated (40) is ACCEPTED — the read predicts the lowest pool the setter takes, exactly');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:40|40|0|60',
  'C6: re-read: pool 40, allocated 40, remaining_to_allocate 0');
-- (ii) the upper boundary: the read's capacity_hint
SELECT tap._store233('hint0', tap._val233('23300000-0000-4000-8000-0000000000f1', 'hint')::text);
SELECT is(tap._exec233(format('SELECT venue_cmd.set_session_sales_capacity(%L, %s, %L, %L)::text',
                              '23300000-0000-4000-8000-0000000000f1', tap._fetch233('hint0')::integer + 1, 'grow', 'ck233-c-7')),
          format('authenticated|P0001|precondition_failed: above_venue_capacity (new=%s > capacity_hint=%s)',
                 tap._fetch233('hint0')::integer + 1, tap._fetch233('hint0')::integer),
  'C7: (ii) pool := the read''s capacity_hint + 1 (61) is REFUSED above_venue_capacity, the setter naming the same capacity_hint (60)');
SELECT is(tap._exec233(format('SELECT venue_cmd.set_session_sales_capacity(%L, %s, %L, %L)::text',
                              '23300000-0000-4000-8000-0000000000f1', tap._fetch233('hint0')::integer, 'room_size', 'ck233-c-8')),
          'authenticated|' || jsonb_build_object('status','ok','session_id','23300000-0000-4000-8000-0000000000f1'::uuid,
                                                 'sales_capacity', tap._fetch233('hint0')::integer, 'allocated', 40)::text,
  'C8: (ii) pool := the read''s capacity_hint (60) is ACCEPTED');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:60|40|20|60',
  'C9: re-read: pool 60, remaining_to_allocate 20');
SELECT is(tap._exec233($q$SELECT venue_cmd.set_session_sales_capacity('23300000-0000-4000-8000-0000000000f1', 50, 'room_size', 'ck233-c-10')::text$q$),
          'authenticated|' || jsonb_build_object('status','ok','session_id','23300000-0000-4000-8000-0000000000f1'::uuid,'sales_capacity',50,'allocated',40)::text,
  'C10: the pool goes back to 50 for (iii)');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:50|40|10|60',
  'C11: re-read: pool 50, allocated 40, remaining_to_allocate 10');
-- (iii) the batch boundary: the read's remaining_to_allocate
SELECT tap._store233('rem0',   tap._val233('23300000-0000-4000-8000-0000000000f1', 'remaining')::text);
SELECT tap._store233('alloc1', tap._val233('23300000-0000-4000-8000-0000000000f1', 'allocated')::text);
SELECT tap._store233('pool1',  tap._val233('23300000-0000-4000-8000-0000000000f1', 'pool')::text);
SELECT is(tap._exec233(format('SELECT venue.create_inventory_batch(%L, %L, %L, %s, 0, %L)::text',
                              '23300000-0000-4000-8000-000000000011', '23300000-0000-4000-8000-0000000000f1', 'door',
                              tap._fetch233('rem0')::integer + 1, 'ck233-c-12')),
          format('authenticated|P0001|precondition_failed: session_capacity_exceeded (allocated=%s + new=%s > sales_capacity=%s)',
                 tap._fetch233('alloc1')::integer, tap._fetch233('rem0')::integer + 1, tap._fetch233('pool1')::integer),
  'C12: (iii) a door batch of the read''s remaining_to_allocate + 1 (11) is REFUSED session_capacity_exceeded, the writer naming the read''s allocated (40) and pool (50)');
SELECT is(tap._exec233(format('SELECT (venue.create_inventory_batch(%L, %L, %L, %s, 0, %L) - %L)::text',
                              '23300000-0000-4000-8000-000000000011', '23300000-0000-4000-8000-0000000000f1', 'door',
                              tap._fetch233('rem0')::integer, 'ck233-c-13', 'batch_id')),
          'authenticated|' || jsonb_build_object('status','ok','capacity', tap._fetch233('rem0')::integer,'is_sharded',false)::text,
  'C13: (iii) a door batch of the read''s remaining_to_allocate (10) is ACCEPTED — the read predicts the largest batch the writer takes, exactly');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:50|50|0|60',
  'C14: re-read: allocated 50, remaining_to_allocate 0');
SELECT ok(tap._val233('23300000-0000-4000-8000-0000000000f1', 'allocated') = tap._alloc233('23300000-0000-4000-8000-0000000000f1')
          AND tap._kinds233('23300000-0000-4000-8000-0000000000f1') = 3,
  'C15: allocated (50) = the raw SUM over public_sale + comp + door (three release kinds)');
-- (iv) unlimited
SELECT is(tap._exec233($q$SELECT venue_cmd.set_session_sales_capacity('23300000-0000-4000-8000-0000000000f1', NULL, 'unlimited', 'ck233-c-16')::text$q$),
          'authenticated|' || jsonb_build_object('status','ok','session_id','23300000-0000-4000-8000-0000000000f1'::uuid,'sales_capacity',NULL::integer,'allocated',50)::text,
  'C16: (iv) pool := NULL (unlimited) is accepted');
SELECT is(tap._cap233('23300000-0000-4000-8000-0000000000f1'), 'authenticated|f1:-|50|-|60',
  'C17: (iv) re-read: sales_capacity NULL and remaining_to_allocate NULL; allocated still 50, capacity_hint still 60');
SELECT is(tap._capv233('23300000-0000-4000-8000-0000000000f1'), tap._cap233('23300000-0000-4000-8000-0000000000f1'),
  'C18: the view''s f1 row equals the wrapper''s after the edits');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
