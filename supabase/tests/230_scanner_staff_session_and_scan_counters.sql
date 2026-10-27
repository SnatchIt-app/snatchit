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
--   Section D  shape + ACL of PART B (DROPPABLE): venue.record_scan_staff (definer
--              plpgsql), venue_cmd.record_scan / validate_ticket_online (sql,
--              prosecdef=false, same argument lists and results as their
--              targets, no device parameter); 086/108 grants unchanged;
--              228's "every venue_cmd function is LANGUAGE sql + invoker"
--              survives over the whole schema.
--   Section H  venue.filter_staff_scan_meta, the allow-list tested DIRECTLY as the
--              owner (zero grants; IMMUTABLE): NULL/{} -> {}; the three legal keys
--              pass unchanged; occurred_at is STRIPPED (A+E ruling); device_id is
--              refused with B's exact X-5 text; unknown key / bad label / non-object
--              refused by name; the 64-char boundary passes. Needs no flag.
--   Section E  PART B with the flag OFF (as seeded): the same refusals through the
--              wrapper with their exact texts; command key required; NULL / '{}' /
--              a legal meta / a meta carrying occurred_at reach the flag gate and get the SAME
--              feature_disabled text as the direct venue.record_scan call (the
--              gate is inside); a fan gets feature_disabled too (flag before
--              role, 108's order — no new oracle); validate_ticket_online wrapper
--              = direct; nothing is written while dark.
--   Section F  PART B with the flag ON (version-2 row inserted as postgres):
--              scanner admits through the wrapper; the row is actor-attributed
--              (actor = caller, device NULL), server-stamped; the atom is
--              scanned; the counters move; a second identical call never admits
--              twice (one admitted+in row — the invariant 183 keeps; the result
--              value today is 'invalid', 183 makes it 'duplicate'+prior, so only
--              the invariant is pinned and the value is diag'd); wrong session ->
--              'invalid' and the counters of the other session show it; fan /
--              cross-venue scanner / anon refused INSIDE the definer chain
--              (42501); venue_manager admits; STATUS QUO pin: the former-operator
--              manager admits through venue.record_scan (no E-76 in 086/108 —
--              A/B to rule); validate wrapper = direct; a client occurred_at of
--              2000-01-01 admits and the ledger row carries the SERVER's now().
--   Section G  the pass-through proof (LAST, a test double inside this rolled-
--              back transaction): venue.record_scan is replaced by a spy that
--              records its arguments; the wrapper's legal meta arrives UNCHANGED,
--              the device argument is NULL, the command key is verbatim, a NULL
--              meta arrives as '{}', occurred_at never arrives. (venue.scan has no
--              device_label column on this chain — 183 adds it — so the argument is
--              the only observable of the label.) G2b (A's #163 review) pins
--              scan_meta.credential_version and scan_meta.key_id by name: both reach
--              venue.record_scan UNCHANGED beside device_label, and nothing else does.
--   (Section I — the credential_stale refusal B's 183 adds — is NOT in this file on
--              this chain: B's 183 is not beneath this stack, CI's mask gate bans the
--              conditional-masking pattern, and B's pgTAP 253 (PR #163) pins the refusal on
--              the 183 chain. A tracked follow-up re-adds the three assertions live; see the
--              note where Section I stood, before Section G.)
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
-- aborts the transaction; B2-G4 are not emitted. Predicted RED run: 21 emitted
-- = 20 not ok + 1 ok; plan 134 unmet.
-- ============================================================================
BEGIN;
SELECT plan(135);

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
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue'), 96,
  -- 2026-10-26 (registry 162, S2, stacked under 163): 94 -> 96 (+set_ticket_type_sale_window, ticket_type_on_sale).
  'A19: venue holds NINETY-SIX functions — 92 (160 + 162) + 163''s get_session_scan_counters, list_session_scan_counters, record_scan_staff, filter_staff_scan_meta (144 A15 / 145 A4 / 148 B5 / 179 A8 / 180 A5 / 227 A12 / 229 A23 move with it; 148 B2 / 156 A20 / 157 A46 / 179 A9 / 180 A6 move 313 -> 317; 94 / 315 if PART B is dropped)');
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

-- ── Section D — shape + ACL of PART B (DROPPABLE) ────────────────────────────
SELECT has_function('venue'::name, 'record_scan_staff'::name, ARRAY['uuid','uuid','jsonb','text']::name[],
  'D1: venue.record_scan_staff(uuid, uuid, jsonb, text) exists');
SELECT has_function('venue_cmd'::name, 'record_scan'::name, ARRAY['uuid','uuid','jsonb','text']::name[],
  'D2: venue_cmd.record_scan(uuid, uuid, jsonb, text) exists — FOUR arguments, no device');
SELECT has_function('venue_cmd'::name, 'validate_ticket_online'::name, ARRAY['uuid','uuid']::name[],
  'D3: venue_cmd.validate_ticket_online(uuid, uuid) exists');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue' AND p.proname = 'record_scan_staff'
              AND p.prosecdef AND l.lanname = 'plpgsql' AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 'v'), 1,
  'D4: record_scan_staff is SECURITY DEFINER plpgsql, search_path pinned, VOLATILE (a write)');
SELECT set_eq(
  $$ SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname = 'record_scan_staff' AND a.grantee <> p.proowner $$,
  $$ VALUES ('authenticated:EXECUTE') $$,
  'D5: record_scan_staff grants EXECUTE to authenticated and to NOBODY else');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'record_scan'
              AND NOT p.prosecdef AND l.lanname = 'sql' AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 'v'
              AND p.prosrc LIKE '%venue.record_scan_staff(%'), 1,
  'D6: venue_cmd.record_scan is SECURITY INVOKER, LANGUAGE sql, search_path pinned, VOLATILE and delegates to venue.record_scan_staff (the NC4 target)');
SELECT ok(coalesce(pg_get_function_identity_arguments(to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'))
                 = 'p_atom_id uuid, p_session_id uuid, p_scan_meta jsonb, p_command_key text'
           AND pg_get_function_identity_arguments(to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'))
                 = pg_get_function_identity_arguments(to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)'))
           AND pg_get_function_result(to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)')) = 'jsonb'
           AND pg_get_function_result(to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)')) = 'jsonb', false),
  'D7: the record_scan wrapper''s argument list is exactly (p_atom_id, p_session_id, p_scan_meta, p_command_key) = its target''s; both return jsonb; no p_actor_device_id');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd' AND p.proname = 'validate_ticket_online'
              AND NOT p.prosecdef AND l.lanname = 'sql' AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 's'
              AND p.prosrc LIKE '%venue.validate_ticket_online(%'), 1,
  'D8: venue_cmd.validate_ticket_online is SECURITY INVOKER, LANGUAGE sql, search_path pinned, STABLE (a read) and delegates to venue.validate_ticket_online');
SELECT ok(coalesce(pg_get_function_identity_arguments(to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)'))
                 = pg_get_function_identity_arguments(to_regprocedure('venue.validate_ticket_online(uuid, uuid)'))
           AND pg_get_function_result(to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)'))
                 = pg_get_function_result(to_regprocedure('venue.validate_ticket_online(uuid, uuid)')), false),
  'D9: the validate wrapper''s argument list and result type equal venue.validate_ticket_online''s');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue_cmd' AND p.proname IN ('record_scan','validate_ticket_online') AND a.grantee <> p.proowner $$,
  $$ VALUES ('record_scan:authenticated:EXECUTE'), ('validate_ticket_online:authenticated:EXECUTE') $$,
  'D10: the two wrappers grant EXECUTE to authenticated and to NOBODY else — no anon, PUBLIC or service_role (the NC5 target)');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)'), 'EXECUTE'), false),
  'D11: has_function_privilege — anon and service_role false, authenticated true, on all three PART B functions');
SELECT set_eq(
  $$ SELECT p.proname || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type
       FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      WHERE n.nspname = 'venue' AND p.proname IN ('record_scan','record_scan_door','_record_scan_core','validate_ticket_online') AND a.grantee <> p.proowner $$,
  $$ VALUES ('record_scan:authenticated:EXECUTE'), ('record_scan_door:service_role:EXECUTE'), ('validate_ticket_online:authenticated:EXECUTE') $$,
  'D12: the 086/108 grants are UNCHANGED — record_scan authenticated, record_scan_door service_role, _record_scan_core nobody (the door path is not touched)');
SELECT ok((SELECT count(*) = 21 AND count(*) FILTER (WHERE NOT p.prosecdef AND l.lanname = 'sql') = 21  -- 2026-10-27 (registry 164): 14 -> 21 (+164's seven wrappers; pgTAP 231). 2026-10-26 (registry 162, S2, stacked under 163): 9 -> 14 (+162's five wrappers)
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue_cmd'),
  'D13: venue_cmd holds TWENTY-ONE functions (161''s six + 162''s five + 163''s three + 164''s seven) and EVERY one is LANGUAGE sql + SECURITY INVOKER (228''s invariant survives 162, 163 and 164; 19 if 163''s PART B is dropped)');
SELECT ok((SELECT p.prosrc LIKE '%venue.record_scan(p_atom_id, p_session_id, null::uuid, v_meta, p_command_key)%'
                  AND p.prosrc LIKE '%venue.filter_staff_scan_meta(p_scan_meta)%' AND position('*' IN p.prosrc) = 0
             FROM pg_proc p WHERE p.oid = to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)')),
  'D14: record_scan_staff''s body filters the meta through venue.filter_staff_scan_meta and calls venue.record_scan with a literal NULL device (text pin; no ''*'')');

-- ── Section H — venue.filter_staff_scan_meta, the allow-list tested directly (as the owner; no flag needed) ─
SELECT has_function('venue'::name, 'filter_staff_scan_meta'::name, ARRAY['jsonb']::name[], 'H1: venue.filter_staff_scan_meta(jsonb) exists');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = 'venue' AND p.proname = 'filter_staff_scan_meta'
              AND p.provolatile = 'i' AND NOT p.prosecdef AND l.lanname = 'plpgsql' AND p.proconfig::text LIKE '%search_path=%'
              AND pg_get_function_result(p.oid) = 'jsonb'), 1,
  'H2: the filter is IMMUTABLE, SECURITY INVOKER, plpgsql, search_path pinned, returns jsonb');
SELECT ok(coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee <> p.proowner)
                     FROM pg_proc p WHERE p.oid = to_regprocedure('venue.filter_staff_scan_meta(jsonb)')), false),
  'H3: the filter grants EXECUTE to NOBODY but its owner (not DEFAULTED: PUBLIC holds nothing) — reachable only through the definer venue.record_scan_staff');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('venue.filter_staff_scan_meta(jsonb)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('authenticated', to_regprocedure('venue.filter_staff_scan_meta(jsonb)'), 'EXECUTE'), true)
      AND NOT coalesce(has_function_privilege('service_role', to_regprocedure('venue.filter_staff_scan_meta(jsonb)'), 'EXECUTE'), true),
  'H4: has_function_privilege is false for anon, authenticated and service_role (outside 140 #27''s caller-authorized sweep)');
SELECT is(venue.filter_staff_scan_meta(NULL::jsonb), '{}'::jsonb, 'H5: NULL -> {}');
SELECT is(venue.filter_staff_scan_meta('{}'::jsonb), '{}'::jsonb, 'H6: {} -> {}');
SELECT is(venue.filter_staff_scan_meta('{"device_label":"Door A","credential_version":3,"key_id":"00000000-0000-0000-0000-0000000000b0"}'::jsonb),
          '{"device_label":"Door A","credential_version":3,"key_id":"00000000-0000-0000-0000-0000000000b0"}'::jsonb,
  'H7: the legal three keys pass UNCHANGED (credential_version and key_id as given)');
SELECT is(venue.filter_staff_scan_meta('{"device_label":"Door A","occurred_at":"2000-01-01T00:00:00Z"}'::jsonb), '{"device_label":"Door A"}'::jsonb,
  'H8: occurred_at is STRIPPED silently (A+E ruling 2026-10-26) — the server stamps the ledger; the key stays reserved for offline reconcile batches');
SELECT is(venue.filter_staff_scan_meta('{"occurred_at":"2000-01-01T00:00:00Z"}'::jsonb), '{}'::jsonb, 'H9: an occurred_at-only meta becomes {}');
SELECT throws_ok($$SELECT venue.filter_staff_scan_meta('{"device_label":"Door A","device_id":"23000000-0000-4000-8000-0000000000d1"}'::jsonb)$$,
  'P0001', 'invalid_input: scan_meta.device_id is not accepted', 'H10: device_id is REFUSED with the exact text (B''s X-5 parity with record_scan_door), even beside a legal key');
SELECT throws_ok($$SELECT venue.filter_staff_scan_meta('{"foo":1}'::jsonb)$$,
  'P0001', 'invalid_input: scan_meta key not accepted: foo', 'H11: any other key is refused by name');
SELECT throws_ok(format($$SELECT venue.filter_staff_scan_meta(%L::jsonb)$$, jsonb_build_object('device_label', repeat('x', 65))::text),
  'P0001', 'invalid_input: scan_meta.device_label must be 1-64 chars', 'H12: a 65-char device_label is refused');
SELECT throws_ok($$SELECT venue.filter_staff_scan_meta('{"device_label":""}'::jsonb)$$,
  'P0001', 'invalid_input: scan_meta.device_label must be 1-64 chars', 'H13: an empty device_label is refused');
SELECT throws_ok($$SELECT venue.filter_staff_scan_meta('{"device_label":42}'::jsonb)$$,
  'P0001', 'invalid_input: scan_meta.device_label must be 1-64 chars', 'H14: a non-string device_label is refused with the same text');
SELECT throws_ok($$SELECT venue.filter_staff_scan_meta('[1]'::jsonb)$$,
  'P0001', 'invalid_input: scan_meta must be a JSON object', 'H15: a non-object is refused by name (not by jsonb_object_keys'' own error)');
SELECT is(length(venue.filter_staff_scan_meta(jsonb_build_object('device_label', repeat('x', 64))) ->> 'device_label'), 64,
  'H16: a 64-char device_label passes (the boundary)');

-- ── Section E — PART B with the flag OFF (seeded false; 078:1523) ────────────
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"device_label":"Door A"}'::jsonb, 'ck230-e1')$$,
  'P0001', 'precondition_failed: feature_disabled — native scanning is dark',
  'E1: the scanner through the wrapper while dark -> the definer chain''s feature_disabled, exact text');
SELECT throws_ok($$SELECT venue.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', NULL::uuid, '{"device_label":"Door A"}'::jsonb, 'ck230-e2')$$,
  'P0001', 'precondition_failed: feature_disabled — native scanning is dark',
  'E2: the DIRECT venue.record_scan call -> the same text (the gate is inside venue.record_scan, not in the wrapper)');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"device_label":"Door A","device_id":"23000000-0000-4000-8000-0000000000d1"}'::jsonb, 'ck230-e3')$$,
  'P0001', 'invalid_input: scan_meta.device_id is not accepted',
  'E3: scan_meta.device_id is refused with the exact text (even beside a legal key)');
SELECT throws_like($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"occurred_at":"2000-01-01T00:00:00Z"}'::jsonb, 'ck230-e4')$$,
  '%feature_disabled%',
  'E4: a client occurred_at is STRIPPED, not refused — the call passes the allow-list and reaches the flag gate (H8/H9, F19/F20 and G5 pin the strip)');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"foo":1}'::jsonb, 'ck230-e5')$$,
  'P0001', 'invalid_input: scan_meta key not accepted: foo',
  'E5: any other key is refused by name');
SELECT throws_ok(format($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', %L::jsonb, 'ck230-e6')$$,
                        jsonb_build_object('device_label', repeat('x', 65))::text),
  'P0001', 'invalid_input: scan_meta.device_label must be 1-64 chars',
  'E6: a 65-char device_label is refused');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"device_label":""}'::jsonb, 'ck230-e7')$$,
  'P0001', 'invalid_input: scan_meta.device_label must be 1-64 chars',
  'E7: an empty device_label is refused');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"device_label":42}'::jsonb, 'ck230-e8')$$,
  'P0001', 'invalid_input: scan_meta.device_label must be 1-64 chars',
  'E8: a non-string device_label is refused with the same text');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '[1]'::jsonb, 'ck230-e9')$$,
  'P0001', 'invalid_input: scan_meta must be a JSON object',
  'E9: a non-object scan_meta is refused by name (not by jsonb_object_keys'' own error)');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, '')$$,
  'P0001', 'precondition_failed: command key required', 'E10: an empty command key is refused');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, NULL)$$,
  'P0001', 'precondition_failed: command key required', 'E11: a NULL command key is refused');
SELECT throws_like($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', NULL::jsonb, 'ck230-e12')$$,
  '%feature_disabled%', 'E12: a NULL scan_meta passes the allow-list and reaches the flag gate');
SELECT throws_like($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-e13')$$,
  '%feature_disabled%', 'E13: an empty object passes the allow-list and reaches the flag gate');
SELECT throws_like($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{"device_label":"Door A","credential_version":3,"key_id":"00000000-0000-0000-0000-0000000000b0"}'::jsonb, 'ck230-e14')$$,
  '%feature_disabled%', 'E14: the legal {device_label, credential_version, key_id} meta passes the allow-list and reaches the flag gate');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000199');
SELECT throws_like($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-e15')$$,
  '%feature_disabled%', 'E15: a fan while dark -> feature_disabled too (108: flag before role, no new oracle — status quo, unchanged by the wrapper)');
SELECT throws_ok($$SELECT venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1')$$,
  '42501', NULL, 'E17: validate_ticket_online through the wrapper as a fan -> 42501 (the definer''s gate)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT ok(venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1')
          = venue.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1')
      AND venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1') ->> 'ticket_state' = 'active',
  'E16: validate_ticket_online through the wrapper = the direct call (a read; not flag-gated) and sees the active atom');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-e18')$$,
  '42501', NULL, 'E18: anon -> 42501 at the schema wall (no USAGE on venue_cmd)');
SELECT tap.logout();
SELECT is(tap._raw230('23000000-0000-4000-8000-0000000000f1', 'admitted') + tap._raw230('23000000-0000-4000-8000-0000000000f1', 'duplicate')
          + tap._raw230('23000000-0000-4000-8000-0000000000f1', 'invalid') + tap._raw230('23000000-0000-4000-8000-0000000000f1', 'frozen')
          + tap._raw230('23000000-0000-4000-8000-0000000000f1', 'fraud_review'), 10,
  'E19: nothing was written to venue.scan while dark (f1 still holds its ten fixture rows)');

-- ── Section F — PART B with the flag ON (a version-2 row, as 174; rolled back) ─
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');
SELECT tap.login('23000000-0000-4000-8000-000000000114');
-- F1's claims are the atom's REAL ones (credential_version 0 = the kernel.tickets default for these
-- fixture atoms; key b0 = their signing_key_id): with B's 183 beneath, venue._record_scan_core checks
-- supplied claims against the row (BLOCK A) and a mismatch is invalid/credential_stale (A's N10, 2026-10-27).
SELECT is((venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1',
             '{"device_label":"Door A","credential_version":0,"key_id":"00000000-0000-0000-0000-0000000000b0"}'::jsonb, 'ck230-f1') ->> 'result'), 'admitted',
  'F1: the scanner admits an active atom through the wrapper (its claims equal the atom''s credential_version and signing key)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM venue.scan s
            WHERE s.ticket_atom_id = '23000000-0000-4000-8000-000000000a07' AND s.event_session_id = '23000000-0000-4000-8000-0000000000f1'
              AND s.result = 'admitted' AND s.direction = 'in' AND s.device_id IS NULL
              AND s.actor_identity_id = '23000000-0000-4000-8000-000000000114'), 1,
  'F2: exactly one admitted+in row — actor-attributed to the CALLER, device_id NULL (scan_attribution_ck holds; the device is never settable from this path)');
SELECT ok((SELECT s.occurred_at = now() AND s.server_receipt_at = now() FROM venue.scan s WHERE s.ticket_atom_id = '23000000-0000-4000-8000-000000000a07' AND s.result = 'admitted'),
  'F3: occurred_at AND server_receipt_at are the SERVER''s clock (the client cannot supply either — E4)');
SELECT is((SELECT t.state FROM kernel.tickets t WHERE t.ticket_atom_id = '23000000-0000-4000-8000-000000000a07'), 'scanned',
  'F4: the atom is scanned (kernel.mark_ticket_scanned, the single-writer choke point)');
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f1') c),
  'f1:5|2|3|' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS'),
  'F5: the counters move with the wrapper''s write — admitted 5, last_admitted_at = this scan''s server receipt');
SELECT tap._store230('f6', (venue_cmd.record_scan('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1',
             '{"device_label":"Door A"}'::jsonb, 'ck230-f1') ->> 'result'));
SELECT ok(tap._fetch230('f6') <> 'admitted'
      AND (SELECT count(*) FROM venue.scan s WHERE s.ticket_atom_id = '23000000-0000-4000-8000-000000000a07'
             AND s.event_session_id = '23000000-0000-4000-8000-0000000000f1' AND s.result = 'admitted' AND s.direction = 'in') = 1,
  'F6: a second identical call NEVER admits twice — still exactly one admitted+in row (the invariant 183 keeps; the result value is diag''d, 183 makes it duplicate+prior)');
SELECT diag('F6 observed result of the sequential repeat on this chain: ' || coalesce(tap._fetch230('f6'), '<null>'));
SELECT is((venue_cmd.record_scan('23000000-0000-4000-8000-000000000a08', '23000000-0000-4000-8000-0000000000f2', '{}'::jsonb, 'ck230-f7') ->> 'result'), 'invalid',
  'F7: an f1 atom presented at session f2 -> invalid (wrong_session inside the core)');
SELECT is((SELECT string_agg(tap._fmt230(c.session_id, c.admitted, c.duplicate, c.invalid, c.last_admitted_at), ';')
             FROM venue.get_session_scan_counters('23000000-0000-4000-8000-0000000000f2') c),
  'f2:0|0|1|-', 'F8: …and f2''s counters show that invalid attempt (0 admitted, 1 invalid, no last_admitted_at)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000199');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a09', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-f9')$$,
  '42501', NULL, 'F9: a fan through the wrapper -> 42501 from INSIDE venue.record_scan (the wrapper added no authority)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000131');
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a09', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-f10')$$,
  '42501', NULL, 'F10: the V3 scanner through the wrapper on V1''s session -> 42501');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$SELECT venue_cmd.record_scan('23000000-0000-4000-8000-000000000a09', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-f11')$$,
  '42501', NULL, 'F11: anon with the flag ON -> still 42501 at the schema wall');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000111');
SELECT is((venue_cmd.record_scan('23000000-0000-4000-8000-000000000a09', '23000000-0000-4000-8000-0000000000f1', '{"device_label":"Manager phone"}'::jsonb, 'ck230-f12') ->> 'result'), 'admitted',
  'F12: the venue_manager admits through the wrapper (the 086 gate is venue_scanner OR venue_manager)');
SELECT tap.logout();
SELECT is((SELECT s.actor_identity_id FROM venue.scan s WHERE s.ticket_atom_id = '23000000-0000-4000-8000-000000000a09' AND s.result = 'admitted'),
  '23000000-0000-4000-8000-000000000111'::uuid, 'F13: …attributed to the manager (auth.uid() seen through INVOKER + the two definers), device NULL');
SELECT tap.login('23000000-0000-4000-8000-000000000121');
SELECT is((venue_cmd.record_scan('23000000-0000-4000-8000-000000000a52', '23000000-0000-4000-8000-0000000000f5', '{}'::jsonb, 'ck230-f14') ->> 'result'), 'admitted',
  'F14: STATUS QUO (A/B to rule) — the former-operator manager of Room V2 ADMITS Org A''s e5 atom: venue.record_scan''s 086/108 gate carries no E-76 conjunct (the counters read refuses them; the write does not)');
SELECT tap.logout();
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is(venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1'),
          venue.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1'),
  'F15: validate_ticket_online through the wrapper = the direct call on the scanned atom');
SELECT ok(venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1') ->> 'ticket_state' = 'scanned'
      AND (venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000a07', '23000000-0000-4000-8000-0000000000f1') ->> 'admissible')::boolean = false,
  'F16: …and it reads ticket_state scanned, admissible false');
SELECT is(venue_cmd.validate_ticket_online('23000000-0000-4000-8000-000000000aff', '23000000-0000-4000-8000-0000000000f1'),
          '{"status":"not_found"}'::jsonb, 'F17: an unknown atom through the validate wrapper -> {status: not_found}, as the direct call');
SELECT is((SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(
             venue_cmd.record_scan('23000000-0000-4000-8000-000000000a10', '23000000-0000-4000-8000-0000000000f1', '{}'::jsonb, 'ck230-f18w')) k),
          (SELECT string_agg(k, ',' ORDER BY k) FROM jsonb_object_keys(
             venue.record_scan('23000000-0000-4000-8000-000000000a06', '23000000-0000-4000-8000-0000000000f1', NULL::uuid, '{}'::jsonb, 'ck230-f18d')) k),
  'F18: the wrapper''s result shape (result, scan_id, status) equals the direct venue.record_scan result shape');
SELECT is((venue_cmd.record_scan('23000000-0000-4000-8000-000000000a11', '23000000-0000-4000-8000-0000000000f1',
             '{"device_label":"Door A","occurred_at":"2000-01-01T00:00:00Z"}'::jsonb, 'ck230-f19') ->> 'result'), 'admitted',
  'F19: a legal meta carrying a client occurred_at still ADMITS (stripped, not refused)');
SELECT tap.logout();
SELECT ok((SELECT s.occurred_at = now() AND s.server_receipt_at = now() AND s.occurred_at > '2000-01-02 00:00:00+00'::timestamptz
             FROM venue.scan s WHERE s.ticket_atom_id = '23000000-0000-4000-8000-000000000a11' AND s.result = 'admitted'),
  'F20: …and that row''s occurred_at is the SERVER''s now(), never the client''s 2000-01-01 — a phone clock cannot reach venue.scan on this path');

-- ── Section I — credential_stale (B's 183): REMOVED on this chain ─────────────
-- credential_stale refusal is pinned by B's 253 (PR #163); re-add here as live assertions
-- when 183 is beneath this stack — CI bans the masking call (MASK_MAX_SKIP_CALLS=0), so a
-- presence-gated block cannot stand in for them. 230's three credential_stale assertions
-- are a tracked follow-up (re-add live in the first PR with 183 beneath): I1 result invalid,
-- I2 reason credential_stale, I3 no state transition / no admitted row, on a fresh atom at
-- kernel.tickets.credential_version 3 scanned with scan_meta.credential_version 2.
-- G2b below still pins that credential_version and key_id reach venue.record_scan unchanged.
-- Plan 138 -> 135.

-- ── Section G — the pass-through proof: a spy in place of venue.record_scan (LAST) ─
-- venue.scan has no device_label column on this chain (183 adds it), so the only
-- observable of "the meta reaches venue.record_scan unchanged" is the argument.
-- The replacement is DDL inside this transaction; the ROLLBACK restores 108's body.
CREATE OR REPLACE FUNCTION venue.record_scan(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_scan_meta jsonb, p_command_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $spy$
BEGIN
  PERFORM tap._store230('spy_atom',    p_atom_id::text);
  PERFORM tap._store230('spy_session', p_session_id::text);
  PERFORM tap._store230('spy_device',  coalesce(p_actor_device_id::text, '<null>'));
  PERFORM tap._store230('spy_meta',    coalesce(p_scan_meta::text, '<null>'));
  PERFORM tap._store230('spy_key',     p_command_key);
  RETURN jsonb_build_object('status', 'spy');
END $spy$;
SELECT tap.login('23000000-0000-4000-8000-000000000114');
SELECT is((venue_cmd.record_scan('23000000-0000-4000-8000-000000000a10', '23000000-0000-4000-8000-0000000000f1',
             '{"device_label":"Door A","credential_version":3,"key_id":"00000000-0000-0000-0000-0000000000b0"}'::jsonb, 'ck230-g1') ->> 'status'), 'spy',
  'G1: the wrapper reaches venue.record_scan (the spy answered)');
SELECT is(tap._fetch230('spy_meta')::jsonb, '{"device_label":"Door A","credential_version":3,"key_id":"00000000-0000-0000-0000-0000000000b0"}'::jsonb,
  'G2: the legal meta arrives UNCHANGED — the allow-list adds, drops and rewrites nothing');
SELECT is((tap._fetch230('spy_meta')::jsonb ->> 'credential_version') || '|' || (tap._fetch230('spy_meta')::jsonb ->> 'key_id')
          || '|' || (tap._fetch230('spy_meta')::jsonb ->> 'device_label')
          || '|keys=' || (SELECT count(*) FROM jsonb_object_keys(tap._fetch230('spy_meta')::jsonb))::text,
  '3|00000000-0000-0000-0000-0000000000b0|Door A|keys=3',
  'G2b: scan_meta.credential_version (3) and scan_meta.key_id reach venue.record_scan UNCHANGED beside device_label, and nothing else does (A''s #163 review)');
SELECT ok(tap._fetch230('spy_device') = '<null>' AND tap._fetch230('spy_key') = 'ck230-g1'
      AND tap._fetch230('spy_atom') = '23000000-0000-4000-8000-000000000a10' AND tap._fetch230('spy_session') = '23000000-0000-4000-8000-0000000000f1',
  'G3: the device argument is NULL, the command key is verbatim, atom and session are the caller''s');
SELECT tap._store230('g4', (venue_cmd.record_scan('23000000-0000-4000-8000-000000000a10', '23000000-0000-4000-8000-0000000000f1', NULL::jsonb, 'ck230-g4') ->> 'status'));
SELECT is(tap._fetch230('spy_meta')::jsonb, '{}'::jsonb, 'G4: a NULL meta arrives as an empty object (nothing the core would coalesce a client value from)');
SELECT tap._store230('g5', (venue_cmd.record_scan('23000000-0000-4000-8000-000000000a10', '23000000-0000-4000-8000-0000000000f1',
             '{"device_label":"Door A","occurred_at":"2000-01-01T00:00:00Z"}'::jsonb, 'ck230-g5') ->> 'status'));
SELECT is(tap._fetch230('spy_meta')::jsonb, '{"device_label":"Door A"}'::jsonb,
  'G5: occurred_at NEVER reaches venue.record_scan from this path (stripped before the call); the label does');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
