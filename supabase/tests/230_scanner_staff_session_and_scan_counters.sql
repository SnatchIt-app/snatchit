-- ============================================================================
-- 230_scanner_staff_session_and_scan_counters.sql — migration 20261026110000
-- (registry 163).
--
-- Registry 163 / pgTAP 230 — assigned by Claude A 2026-10-26 (CONTRACTS.md §4;
-- C7 amendment 2026-10-26). A reviews before this leaves draft. DARK: applied
-- nowhere; venue_api / venue_cmd are not exposed (owner setting); the
-- native-scanning flag is flipped ONLY inside this rolled-back transaction, on
-- a local clone, the way 174 does (a version-2 catalog.platform_config row).
--
-- The CI grant gates read `public` only, so THIS FILE is the gate for 163's
-- objects (228 sweeps the venue_cmd schema, 226 + the 163 hunk the venue_api
-- schema): shape, prosecdef, search_path, volatility, the EXECUTE matrix for
-- anon / authenticated / service_role / PUBLIC via has_function_privilege and an
-- exact aclexplode matrix, the view's columns / options / ACL / owner, and the
-- behaviour of every caller label.
--
--   Section A  shape + ACL of PART A: venue.get_session_scan_counters,
--              venue.list_session_scan_counters, venue_cmd.get_session_scan_counters,
--              venue_api.session_admissions; result types pinned exactly (the
--              NC3 target); explicit column lists (no '*' in any body — B's
--              condition, 183 adds a venue.scan column); census pins.
--   Section B  the single-session read: exact counts and last_admitted_at for
--              venue_scanner, venue_manager (bound), org_owner, org_admin of the
--              EVENT's org; the 'out' admitted row never counts; `invalid` folds
--              frozen/fraud_review; last_admitted_at is max(server_receipt_at),
--              not the phone's occurred_at (a 2031 occurred_at row proves it);
--              zero scans = one row of zeros; eight
--              refused labels (venue_finance, box_office, marketing, cross-venue
--              scanner, former-operator manager, fan, Org B's owner on Org A's
--              event at V1 and at the re-operated V2) -> the SAME P0002 text as
--              an unknown session; anon and unauthenticated 42501; wrapper =
--              direct.
--   Section C  the list function and the view: a scanner sees only their venue's
--              sessions; org_owner sees every session of the org's events
--              (including the one at the re-operated room); Org B's owner sees
--              only Org B's; former-operator manager / finance / fan /
--              unauthenticated -> zero rows and NO raise; anon -> 42501 at the
--              schema wall; the view equals the function, row for row.
--   Sections D/H/E/F/G (PART B — the staff-session wrappers, the scan_meta filter,
--              the flag-OFF/ON behaviour and the pass-through spy) ride with the
--              DROPPABLE wrapper commit, which appends them and raises the plan.
--
-- Fixture: 227 style, tag 23000000-…, inserted as postgres and rolled back.
-- Org A (owner, admin) / Room V1 (manager, finance, box_office, scanner,
-- marketing) with event e1 (sessions f1 = scans, f2 = none); Room V2 created
-- under Org A, its event e5 stamped Org A, then moved to Org B (the former-
-- operator manager); Room V3 (Org B) with e6 and the cross-venue scanner; Org
-- B's owner; a ticket holder; a fan. kernel.tickets rows are inserted directly
-- (with their ownership-log rows) and venue.scan rows are inserted directly as
-- postgres with device_id NULL and actor_identity_id set (scan_attribution_ck):
-- issuance and scanning are flag-gated on this chain, and the counters must be
-- pinned independently of either flag; server_receipt_at is set explicitly on
-- every fixture row so the expected timestamps are constants. The f1 rows
-- include an admitted row with direction='out' (never counts; the latest receipt
-- of any admitted row, so last_admitted_at proves it is ignored), an admitted+in
-- row whose occurred_at is a phone clock in 2031 while its server_receipt_at is
-- the EARLIEST (last_admitted_at must read 20:02, not 2031 — E's pin), a frozen
-- row and a fraud_review row (fold into invalid). One active global signing key (the bootstrap key_id, a throwaway
-- P-256 SPKI PEM and an all-zero-account ARN, as 176's fixture) satisfies the
-- kernel.tickets FK and the 110 insert guard; no signing_key row is ever read.
--
-- Expected on 160/161 WITHOUT 163 (RED, predicted before the first run; the
-- reconciliation is in the evidence dir): A1-A19 and A21 fail (20: the four
-- objects are absent, venue holds 90 not 94, venue_api eight views; A5-A18 are
-- NULL-safe so they read `not ok` instead of aborting); A20 passes (1, by
-- vacuity). Then B1 — the first call of a missing function — raises 42883 and
-- aborts the transaction; B2-C17 are not emitted. Predicted RED run: 21 emitted
-- = 20 not ok + 1 ok; plan 60 unmet.
-- ============================================================================
BEGIN;
SELECT plan(60);

CREATE TABLE tap.memo_230 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store230(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_230 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch230(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_230 WHERE k = $1 $m$;
-- one text per counters row: session|admitted|duplicate|invalid|last_admitted_at(UTC) with '-' for NULL
CREATE FUNCTION tap._fmt230(s uuid, a integer, d integer, i integer, t timestamptz) RETURNS text
LANGUAGE sql IMMUTABLE AS
$m$ SELECT substr(s::text, 35) || ':' || a || '|' || d || '|' || i || '|' || coalesce(to_char(t AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS'), '-') $m$;
-- definer raw reads of venue.scan for the "equals the raw rows" checks (the counters are the only client route)
CREATE FUNCTION tap._raw230(s uuid, r text) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT count(x.scan_id)::integer FROM venue.scan x WHERE x.event_session_id = s AND x.result = r $m$;
CREATE FUNCTION tap._rawmax230(s uuid) RETURNS timestamptz LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT max(x.server_receipt_at) FROM venue.scan x WHERE x.event_session_id = s AND x.result = 'admitted' $m$;
CREATE FUNCTION tap._rawmaxocc230(s uuid) RETURNS timestamptz LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT max(x.occurred_at) FROM venue.scan x WHERE x.event_session_id = s AND x.result = 'admitted' AND x.direction = 'in' $m$;
GRANT EXECUTE ON FUNCTION tap._store230(text, text), tap._fetch230(text), tap._fmt230(uuid, integer, integer, integer, timestamptz),
                          tap._raw230(uuid, text), tap._rawmax230(uuid), tap._rawmaxocc230(uuid) TO authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('23000000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.a.230@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin.a.230@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v1.230@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000112', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fin.v1.230@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000113', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'box.v1.230@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000114', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v1.230@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000115', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mkt.v1.230@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000121', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mgr.v2.former.230@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000131', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'scan.v3.cross.230@test.local',  '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000190', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'holder.230@test.local',         '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.230@test.local',            '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('23000000-0000-4000-8000-000000000201', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner.b.230@test.local',        '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('23000000-0000-4000-8000-00000000000a', 'Org A 230', 'Org A 230', 'active'),
  ('23000000-0000-4000-8000-00000000000b', 'Org B 230', 'Org B 230', 'active');
INSERT INTO kernel.org_member (org_id, identity_id, role) VALUES
  ('23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000101', 'org_owner'),
  ('23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000102', 'org_admin'),
  ('23000000-0000-4000-8000-00000000000b', '23000000-0000-4000-8000-000000000201', 'org_owner');
-- V2 is created under Org A (its event e5 is stamped Org A below), then moved.
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, approval_status) VALUES
  ('23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-00000000000a', 'Room V1 230', 'wynwood',  'approved'),
  ('23000000-0000-4000-8000-0000000000a2', '23000000-0000-4000-8000-00000000000a', 'Room V2 230', 'brickell', 'approved'),
  ('23000000-0000-4000-8000-0000000000b3', '23000000-0000-4000-8000-00000000000b', 'Room V3 230', 'midtown',  'approved');
INSERT INTO venue.staff_role (venue_id, identity_id, role) VALUES
  ('23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-000000000111', 'venue_manager'),
  ('23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-000000000112', 'venue_finance'),
  ('23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-000000000113', 'venue_box_office'),
  ('23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-000000000114', 'venue_scanner'),
  ('23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-000000000115', 'venue_marketing'),
  ('23000000-0000-4000-8000-0000000000a2', '23000000-0000-4000-8000-000000000121', 'venue_manager'),
  ('23000000-0000-4000-8000-0000000000b3', '23000000-0000-4000-8000-000000000131', 'venue_scanner');
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('23000000-0000-4000-8000-0000000000e1', '23000000-0000-4000-8000-0000000000a1', '23000000-0000-4000-8000-00000000000a', 'V1 on sale 230',   'on_sale'),
  ('23000000-0000-4000-8000-0000000000e5', '23000000-0000-4000-8000-0000000000a2', '23000000-0000-4000-8000-00000000000a', 'V2 (A event) 230', 'on_sale'),
  ('23000000-0000-4000-8000-0000000000e6', '23000000-0000-4000-8000-0000000000b3', '23000000-0000-4000-8000-00000000000b', 'V3 (B event) 230', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-0000000000e1', now() + interval '3 days',  'scheduled'),
  ('23000000-0000-4000-8000-0000000000f2', '23000000-0000-4000-8000-0000000000e1', now() + interval '4 days',  'scheduled'),
  ('23000000-0000-4000-8000-0000000000f5', '23000000-0000-4000-8000-0000000000e5', now() + interval '7 days',  'scheduled'),
  ('23000000-0000-4000-8000-0000000000f6', '23000000-0000-4000-8000-0000000000e6', now() + interval '10 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility) VALUES
  ('23000000-0000-4000-8000-000000000011', '23000000-0000-4000-8000-0000000000e1', 'admission', 'GA 230',    2500, 'public'),
  ('23000000-0000-4000-8000-000000000051', '23000000-0000-4000-8000-0000000000e5', 'admission', 'GA V2 230', 4000, 'public'),
  ('23000000-0000-4000-8000-000000000061', '23000000-0000-4000-8000-0000000000e6', 'admission', 'GA V3 230', 3000, 'public');
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('23000000-0000-4000-8000-0000000000c1', '23000000-0000-4000-8000-000000000011', '23000000-0000-4000-8000-0000000000f1', 'public_sale', 300, 0, 10),
  ('23000000-0000-4000-8000-0000000000c2', '23000000-0000-4000-8000-000000000011', '23000000-0000-4000-8000-0000000000f2', 'public_sale', 300, 0, 0),
  ('23000000-0000-4000-8000-0000000000c5', '23000000-0000-4000-8000-000000000051', '23000000-0000-4000-8000-0000000000f5', 'public_sale', 200, 0, 2),
  ('23000000-0000-4000-8000-0000000000c6', '23000000-0000-4000-8000-000000000061', '23000000-0000-4000-8000-0000000000f6', 'public_sale', 200, 0, 2);
-- the re-operation of Room V2 (Org A -> Org B); e5 keeps org_id = A (catalog.update_venue does not re-stamp events)
UPDATE catalog.venue SET org_id = '23000000-0000-4000-8000-00000000000b'
 WHERE venue_id = '23000000-0000-4000-8000-0000000000a2';
-- the bootstrap global signing key (110 guard: key_id b0, ES256, key ARN, 91-byte P-256 SPKI; 176's throwaway PEM). Never read back.
INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, status, not_before, algorithm) VALUES
  ('00000000-0000-0000-0000-0000000000b0', 'global', NULL, NULL,
   E'-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS\nOF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==\n-----END PUBLIC KEY-----\n',
   'arn:aws:kms:us-east-1:000000000000:key/00000000-0000-0000-0000-000000000000', 'active', now() - interval '1 day', 'ES256');
-- atoms, inserted directly (issuance is flag-gated); a01-a06 / a51 / a61-a62 already scanned (the fixture rows below), a07-a10 / a52 active
INSERT INTO kernel.tickets (ticket_atom_id, event_session_id, org_id, ticket_type_id, serial_no, current_owner_id, state, signing_key_id)
SELECT ('23000000-0000-4000-8000-000000000a' || x.sfx)::uuid, x.sess::uuid, x.org::uuid, x.tt::uuid, x.ser, '23000000-0000-4000-8000-000000000190', x.st, '00000000-0000-0000-0000-0000000000b0'
  FROM (VALUES
    ('01', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 1,  'scanned'),
    ('02', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 2,  'scanned'),
    ('03', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 3,  'scanned'),
    ('04', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 4,  'scanned'),
    ('05', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 5,  'active'),
    ('06', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 6,  'active'),
    ('07', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 7,  'active'),
    ('08', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 8,  'active'),
    ('09', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 9,  'active'),
    ('10', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 10, 'active'),
    ('11', '23000000-0000-4000-8000-0000000000f1', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000011', 11, 'active'),
    ('51', '23000000-0000-4000-8000-0000000000f5', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000051', 1,  'scanned'),
    ('52', '23000000-0000-4000-8000-0000000000f5', '23000000-0000-4000-8000-00000000000a', '23000000-0000-4000-8000-000000000051', 2,  'active'),
    ('61', '23000000-0000-4000-8000-0000000000f6', '23000000-0000-4000-8000-00000000000b', '23000000-0000-4000-8000-000000000061', 1,  'scanned'),
    ('62', '23000000-0000-4000-8000-0000000000f6', '23000000-0000-4000-8000-00000000000b', '23000000-0000-4000-8000-000000000061', 2,  'scanned')
  ) AS x(sfx, sess, org, tt, ser, st);
-- one custody row per atom (the deferred head=tail trigger would require it at COMMIT; this file rolls back)
INSERT INTO kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref, actor_identity, command_idempotency_key, credential_version_after, state_transition)
SELECT t.ticket_atom_id, 1, NULL, t.current_owner_id, 'issue', gen_random_uuid(), t.current_owner_id, 'ck230-issue-' || t.serial_no::text || '-' || substr(t.event_session_id::text, 35), 0, '{"from":null,"to":"issued"}'::jsonb
  FROM kernel.tickets t WHERE t.ticket_atom_id::text LIKE '23000000-0000-4000-8000-000000000a%';
-- the admission ledger rows (actor-attributed, device NULL — scan_attribution_ck); server_receipt_at set explicitly; T0 in the past so a live scan is always the latest
INSERT INTO venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, direction, scan_type, result, occurred_at, server_receipt_at) VALUES
  ('23000000-0000-4000-8000-000000000a01', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'admitted',     '2026-10-20 20:00:00+00', '2026-10-20 20:00:00+00'),
  ('23000000-0000-4000-8000-000000000a02', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'admitted',     '2026-10-20 20:01:00+00', '2026-10-20 20:01:00+00'),
  ('23000000-0000-4000-8000-000000000a03', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'admitted',     '2026-10-20 20:02:00+00', '2026-10-20 20:02:00+00'),  -- latest RECEIPT among admitted+in
  ('23000000-0000-4000-8000-000000000a04', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'admitted',     '2031-01-01 00:00:00+00', '2026-10-20 19:59:00+00'),  -- phone clock in 2031; earliest receipt — must not move last_admitted_at
  ('23000000-0000-4000-8000-000000000a01', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'out', 'pass_out',  'admitted',     '2026-10-20 20:10:00+00', '2026-10-20 20:10:00+00'),  -- never counts; latest admitted receipt of any direction
  ('23000000-0000-4000-8000-000000000a01', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'duplicate',    '2026-10-20 20:03:00+00', '2026-10-20 20:03:00+00'),
  ('23000000-0000-4000-8000-000000000a02', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'duplicate',    '2026-10-20 20:04:00+00', '2026-10-20 20:04:00+00'),
  ('23000000-0000-4000-8000-000000000a05', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'invalid',      '2026-10-20 20:05:00+00', '2026-10-20 20:05:00+00'),
  ('23000000-0000-4000-8000-000000000a05', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'frozen',       '2026-10-20 20:06:00+00', '2026-10-20 20:06:00+00'),
  ('23000000-0000-4000-8000-000000000a06', '23000000-0000-4000-8000-0000000000f1', NULL, '23000000-0000-4000-8000-000000000114', 'in',  'admission', 'fraud_review', '2026-10-20 20:07:00+00', '2026-10-20 20:07:00+00'),
  ('23000000-0000-4000-8000-000000000a51', '23000000-0000-4000-8000-0000000000f5', NULL, '23000000-0000-4000-8000-000000000121', 'in',  'admission', 'admitted',     '2026-10-20 21:00:00+00', '2026-10-20 21:00:00+00'),
  ('23000000-0000-4000-8000-000000000a52', '23000000-0000-4000-8000-0000000000f5', NULL, '23000000-0000-4000-8000-000000000121', 'in',  'admission', 'invalid',      '2026-10-20 21:01:00+00', '2026-10-20 21:01:00+00'),
  ('23000000-0000-4000-8000-000000000a61', '23000000-0000-4000-8000-0000000000f6', NULL, '23000000-0000-4000-8000-000000000131', 'in',  'admission', 'admitted',     '2026-10-20 22:00:00+00', '2026-10-20 22:00:00+00'),
  ('23000000-0000-4000-8000-000000000a62', '23000000-0000-4000-8000-0000000000f6', NULL, '23000000-0000-4000-8000-000000000131', 'in',  'admission', 'admitted',     '2026-10-20 22:01:00+00', '2026-10-20 22:01:00+00');
-- expected rows: f1 = 4|2|3|20:02 (receipt) · f2 = 0|0|0|- · f5 = 1|0|1|21:00 · f6 = 2|0|0|22:01

-- ── Section A — shape + ACL of PART A ────────────────────────────────────────
SELECT has_function('venue'::name, 'get_session_scan_counters'::name, ARRAY['uuid']::name[],
  'A1: venue.get_session_scan_counters(uuid) exists');
SELECT has_function('venue'::name, 'list_session_scan_counters'::name, '{}'::name[],
  'A2: venue.list_session_scan_counters() exists');
SELECT has_function('venue_cmd'::name, 'get_session_scan_counters'::name, ARRAY['uuid']::name[],
  'A3: venue_cmd.get_session_scan_counters(uuid) exists');
SELECT has_view('venue_api'::name, 'session_admissions'::name, 'A4: venue_api.session_admissions exists');
-- the exact result types (the NC3 target: one extra per-atom column fails here)
SELECT is(pg_get_function_result(to_regprocedure('venue.get_session_scan_counters(uuid)')),
  'TABLE(session_id uuid, admitted integer, duplicate integer, invalid integer, last_admitted_at timestamp with time zone)',
  'A5: get_session_scan_counters returns EXACTLY (session_id, admitted, duplicate, invalid, last_admitted_at) — no name, no atom, no actor, no device');
SELECT is(pg_get_function_result(to_regprocedure('venue.list_session_scan_counters()')),
  'TABLE(session_id uuid, admitted integer, duplicate integer, invalid integer, last_admitted_at timestamp with time zone)',
  'A6: list_session_scan_counters returns the same five columns');
SELECT ok(coalesce(pg_get_function_identity_arguments(to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'))
                 = pg_get_function_identity_arguments(to_regprocedure('venue.get_session_scan_counters(uuid)'))
           AND pg_get_function_result(to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'))
                 = pg_get_function_result(to_regprocedure('venue.get_session_scan_counters(uuid)')), false),
  'A7: the venue_cmd wrapper''s argument list and result type equal the venue target''s');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname IN ('get_session_scan_counters','list_session_scan_counters')
              AND p.prosecdef AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 's'), 2,
  'A8: both counters functions are SECURITY DEFINER, search_path pinned (066 invariant) and STABLE');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'get_session_scan_counters'
              AND NOT p.prosecdef AND l.lanname = 'sql' AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 's'
              AND p.prosrc LIKE '%venue.get_session_scan_counters(%'), 1,
  'A9: the wrapper is SECURITY INVOKER, LANGUAGE sql, search_path pinned, STABLE and delegates to venue.get_session_scan_counters');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname IN ('get_session_scan_counters','list_session_scan_counters') AND a.grantee <> p.proowner $$,
  $$ VALUES ('get_session_scan_counters:authenticated:EXECUTE'), ('list_session_scan_counters:authenticated:EXECUTE') $$,
  'A10: the two venue functions grant EXECUTE to authenticated and to NOBODY else (no PUBLIC, anon, service_role)');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.get_session_scan_counters(uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.list_session_scan_counters()'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.get_session_scan_counters(uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.list_session_scan_counters()'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.get_session_scan_counters(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.list_session_scan_counters()'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'), 'EXECUTE'), false),
  'A11: has_function_privilege — anon and service_role false, authenticated true, on all three PART A functions');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd' AND p.proname = 'get_session_scan_counters' AND a.grantee <> p.proowner AND p.proacl IS NOT NULL $$,
  $$ VALUES ('authenticated:EXECUTE') $$,
  'A12: the wrapper''s ACL is exactly EXECUTE to authenticated and is not DEFAULTED (no PUBLIC row)');
SELECT is((SELECT string_agg(a.attname, ',' ORDER BY a.attnum) FROM pg_attribute a
            WHERE a.attrelid = to_regclass('venue_api.session_admissions') AND a.attnum > 0 AND NOT a.attisdropped),
  'session_id,admitted,duplicate,invalid,last_admitted_at',
  'A13: the view projects exactly session_id, admitted, duplicate, invalid, last_admitted_at in that order');
SELECT is((SELECT count(*)::int FROM pg_class c CROSS JOIN LATERAL unnest(c.reloptions) o
            WHERE c.oid = to_regclass('venue_api.session_admissions') AND o IN ('security_invoker=true','security_barrier=true')), 2,
  'A14: the view is security_invoker AND security_barrier (159''s form)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      WHERE c.oid = to_regclass('venue_api.session_admissions') AND a.grantee <> c.relowner $$,
  $$ VALUES ('authenticated:SELECT') $$,
  'A15: the view''s ACL is exactly SELECT to authenticated (no write, no anon, no PUBLIC, no service_role)');
SELECT ok(coalesce((SELECT c.relowner = n.nspowner FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                     WHERE c.oid = to_regclass('venue_api.session_admissions')), false),
  'A16: the view''s owner is venue_api''s owner (the migration runner, as 159''s eight)');
SELECT ok(coalesce((SELECT pg_get_viewdef(c.oid) LIKE '%venue.list_session_scan_counters()%' AND position('*' IN pg_get_viewdef(c.oid)) = 0
                     FROM pg_class c WHERE c.oid = to_regclass('venue_api.session_admissions')), false),
  'A17: the view is defined over venue.list_session_scan_counters() with an explicit column list (no SELECT *)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'venue' AND p.proname IN ('get_session_scan_counters','list_session_scan_counters')
              AND position('*' IN p.prosrc) = 0), 2,
  'A18: neither counters body contains a ''*'' — every venue.scan column is named (B: 183 adds device_label; no select * / scan.*)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue'), 92,
  'A19: venue holds NINETY-TWO functions — 90 (160) + 163''s get_session_scan_counters, list_session_scan_counters (144 A15 / 145 A4 / 148 B5 / 180 A5 / 227 A12 move with it; 148 B2 / 157 A46 / 180 A6 move 308 -> 310)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue_api'), 0,
  'A20: venue_api still holds no function (226 A3 stays true: the definer bodies live in venue)');
SELECT is((SELECT count(*)::int FROM pg_views WHERE schemaname = 'venue_api'), 9,
  'A21: venue_api holds NINE views — 159''s eight + session_admissions (226 A2 / F1 / F5 / F6 move with it — F''s hunk)');

-- ── Section B — the single-session read ──────────────────────────────────────
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'f1:4|2|3|2026-10-20 20:02:00',
  'B1: venue_scanner reads f1 — admitted 4 (in only), duplicate 2, invalid 3 (invalid+frozen+fraud_review), last_admitted_at = the latest RECEIPT of an admitted+in row');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f2') c),
  'f2:0|0|0|-',
  'B2: a session with no scan is ONE row of zeros with a NULL last_admitted_at (never zero rows)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000111');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'f1:4|2|3|2026-10-20 20:02:00', 'B3: the bound venue_manager reads the same row');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000101');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'f1:4|2|3|2026-10-20 20:02:00', 'B4: org_owner of the event''s org reads the same row');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f5') c),
  'f5:1|0|1|2026-10-20 21:00:00',
  'B6: the event''s OWN org_owner (A) reads e5''s session at the re-operated room (the org arm binds to the EVENT''s org)');
SELECT is((SELECT c.invalid FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
          tap._raw230('23000000-0000-4000-8000-0000000000f1', 'invalid')
          + tap._raw230('23000000-0000-4000-8000-0000000000f1', 'frozen')
          + tap._raw230('23000000-0000-4000-8000-0000000000f1', 'fraud_review'),
  'B7: `invalid` = raw invalid + raw frozen + raw fraud_review rows (1 + 1 + 1 — the fold is pinned against the raw ledger)');
SELECT ok((SELECT c.admitted = 4 AND tap._raw230('23000000-0000-4000-8000-0000000000f1', 'admitted') = 5
                  AND c.last_admitted_at < tap._rawmax230('23000000-0000-4000-8000-0000000000f1')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'B8: the ''out'' admitted row never counts — 5 admitted rows in the ledger, 4 counted — and last_admitted_at ignores it (20:02 < the 20:10 pass-out receipt)');
SELECT ok((SELECT c.last_admitted_at = '2026-10-20 20:02:00+00'::timestamptz
                  AND tap._rawmaxocc230('23000000-0000-4000-8000-0000000000f1') = '2031-01-01 00:00:00+00'::timestamptz
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'B22: last_admitted_at is max(server_receipt_at) over admitted+in rows (20:02), NOT max(occurred_at) (the 2031 phone-clock row) — E''s pin: a client clock never moves the dashboard');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000102');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'f1:4|2|3|2026-10-20 20:02:00', 'B5: org_admin reads the same row');
SELECT tap.logout();
-- unknown and unauthorized: the SAME text, the SAME code (no existence oracle)
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000ff')$$,
  'P0002', 'not_found: session 23000000-0000-4000-8000-0000000000ff', 'B9: an unknown session -> not_found (P0002), as the scanner');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000112');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', 'not_found: session 23000000-0000-4000-8000-0000000000f1', 'B10: venue_finance -> the SAME not_found text on a real session');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000113');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', NULL, 'B11: venue_box_office -> P0002');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000115');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', NULL, 'B12: venue_marketing -> P0002');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', NULL, 'B13: the cross-venue scanner (V3) -> P0002 on V1''s session');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000121');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f5')$$,
  'P0002', NULL, 'B14: E-76 — the former-operator manager of Room V2 -> P0002 on Org A''s event e5 (venue.org_id <> event.org_id)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', 'not_found: session 23000000-0000-4000-8000-0000000000f1', 'B15: a fan -> P0002, byte-identical to an unknown session');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000201');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', NULL, 'B16: Org B''s owner -> P0002 on Org A''s session at V1');
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f5')$$,
  'P0002', NULL, 'B17: Org B''s owner -> P0002 on Org A''s event e5 at the room B now operates (the org arm binds to the EVENT''s org)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  '42501', NULL, 'B18: anon has no EXECUTE (and no USAGE on venue)');
SELECT tap.logout();
SELECT throws_ok($$SELECT * FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  '42501', NULL, 'B19: no auth.uid() -> insufficient_privilege (authentication required), never a row');
-- the venue_cmd wrapper
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue_cmd.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
          (SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'B20: the venue_cmd wrapper returns the direct function''s row');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT * FROM venue_cmd.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1')$$,
  'P0002', 'not_found: session 23000000-0000-4000-8000-0000000000f1', 'B21: a fan through the wrapper: the definer''s P0002, unchanged');
SELECT tap.logout();

-- ── Section C — the list function and venue_api.session_admissions ───────────
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.list_session_scan_counters() c),
  'f1:4|2|3|2026-10-20 20:02:00;f2:0|0|0|-',
  'C1: venue_scanner lists exactly V1''s two sessions (starts_at order), the zero-scan session as a row of zeros — nothing of V2 or V3');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000111');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.list_session_scan_counters() c),
  'f1:4|2|3|2026-10-20 20:02:00;f2:0|0|0|-', 'C2: the bound venue_manager lists the same two');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000101');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.list_session_scan_counters() c),
  'f1:4|2|3|2026-10-20 20:02:00;f2:0|0|0|-;f5:1|0|1|2026-10-20 21:00:00',
  'C3: org_owner A lists every session of Org A''s events — e1''s two and e5''s at the re-operated room — and none of Org B''s');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000102');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.list_session_scan_counters() c),
  'f1:4|2|3|2026-10-20 20:02:00;f2:0|0|0|-;f5:1|0|1|2026-10-20 21:00:00', 'C4: org_admin A lists the same three');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000201');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.list_session_scan_counters() c),
  'f6:2|0|0|2026-10-20 22:01:00',
  'C5: Org B''s owner lists only Org B''s event e6 — not e5, Org A''s event at the room B now operates');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000131');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.list_session_scan_counters() c),
  'f6:2|0|0|2026-10-20 22:01:00', 'C6: the V3 scanner lists only V3''s session');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000121');
SELECT is((SELECT count(*)::int FROM venue.list_session_scan_counters()), 0,
  'C7: E-76 — the former-operator manager lists ZERO rows (omitted, not raised)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000112');
SELECT is((SELECT count(*)::int FROM venue.list_session_scan_counters()), 0, 'C8: venue_finance lists zero rows');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM venue.list_session_scan_counters()), 0, 'C9: a fan lists zero rows');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.list_session_scan_counters()), 0,
  'C10: no auth.uid() -> zero rows, no raise (the set-returning read omits; the single-session read refuses)');
SELECT tap.login_anon();
SELECT throws_ok($$SELECT * FROM venue.list_session_scan_counters()$$, '42501', NULL,
  'C11: anon -> 42501 (no USAGE on venue, no EXECUTE)');
SELECT tap.logout();
-- the view (security_invoker: the caller's EXECUTE on the function and USAGE on venue apply)
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is((SELECT string_agg(tap._fmt230(v.session_id, v.admitted, v.duplicate, v.invalid, v.last_admitted_at), ';' ORDER BY v.session_id)
             FROM venue_api.session_admissions v),
  'f1:4|2|3|2026-10-20 20:02:00;f2:0|0|0|-',
  'C12: venue_api.session_admissions as the scanner = exactly V1''s two sessions');
SELECT is((SELECT tap._fmt230(v.session_id, v.admitted, v.duplicate, v.invalid, v.last_admitted_at)
             FROM venue_api.session_admissions v WHERE v.session_id = '23000000-0000-4000-8000-0000000000f1'),
          (SELECT tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at)
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'C14: the view''s f1 row equals the single-session function''s row');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM venue_api.session_admissions), 0, 'C13: the view as a fan = zero rows');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT * FROM venue_api.session_admissions$$, '42501', NULL,
  'C15: the view as anon -> 42501 at the schema wall (no USAGE on venue_api)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000101');
SELECT is((SELECT count(*)::int FROM venue_api.session_admissions), 3, 'C16: the view as org_owner A = three rows');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000121');
SELECT is((SELECT count(*)::int FROM venue_api.session_admissions), 0, 'C17: the view as the former-operator manager = zero rows (E-76 through the view)');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
