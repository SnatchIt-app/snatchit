-- ============================================================================
-- 252_primary_buyer_reads.sql — migration 20261026200000 (registry 182): the
-- four `public` buyer reads (A's C1 discovery + C5 owner-scoped reads).
--
-- Registry 182 / pgTAP 252 — CONFIRMED by Claude A 2026-10-26 (CONTRACTS.md §4).
-- A reviews before this leaves draft; C consumes. DARK: applied nowhere; this
-- file flips no flag outside its own rolled-back transaction.
--
-- Fixture style: 227/229 (synthetic rows inserted as postgres with fixed ids,
-- tag 25200000-…, read back as each caller through tap.login / tap.login_anon,
-- everything rolled back). Identities: buyer B1 (…0101), buyer B2 (…0102), a
-- fan with nothing (…0199), anon, and the "authenticated role with no subject"
-- persona. Rooms: V1 (approved, timezone America/Chicago), V2 (approval
-- 'pending'). Events at V1: e1 draft · e2 on_sale (public GA rank 2 / public
-- Early-bird rank 1 with an open window / hidden / door_only tiers; on session
-- f2 the GA tier holds two public_sale batches plus a comp and a door batch) ·
-- e3 completed · e4 cancelled (session cancelled) · e5 announced · e6 live ·
-- e7 on_sale with ONLY hidden/door_only tiers · e8 on_sale whose public tier's
-- window opens in 10 days · e9 on_sale whose session is completed · e11 on_sale
-- with age_policy 21_plus. e10 on_sale at the pending room V2.
--
-- ISSUANCE FIXTURE — THE REAL PATH (brief §4): feature.native_issuance_enabled
-- is set true as a NEW VERSION of the catalog.platform_config row (the 174/230
-- pattern; append-only table, rolled back with the file); the global ES256
-- bootstrap key is inserted THROUGH THE LIVE 110 INSERT GUARD (B's recipe:
-- ruling-B key_id …b0, the throwaway P-256 SPKI PEM of suite 176, the all-zero
-- account ARN) — tap.seed_core() is NOT called, so the guard stays live; then
-- venue.finalize_primary_order(order, payment, key) runs as the rehearsal
-- superuser for B1's order O1 (3 × GA, hold on batch b21) and B2's order O7
-- (1 × GA, hold on batch b21b): finalize mints through kernel.issue_ticket_atoms
-- with cause_ref = order_item.id, writes kernel.payment_native and marks the
-- orders paid — exactly the production chain after payment_intent.succeeded.
-- Two of B1's atoms are then moved as postgres (state 'scanned'; state 'voided'
-- + credential_version 1 with its paired ledger row) so the raw projections are
-- pinned truthfully. The payment_state matrix (O3-O6) uses direct
-- kernel.payment_native + public.payments rows (as postgres) because
-- finalize only ever links a 'succeeded' payment.
--
--   Section A  shape + ACL (NULL-safe on the chain without 182): the four
--              functions exist, SECURITY DEFINER, search_path='', STABLE; the
--              exact EXECUTE ACL (list/detail: anon + authenticated, explicit,
--              no PUBLIC; atoms/orders: anon revoked, authenticated; service_role
--              EXECUTE on all four by 182's EXPLICIT grant (PART 5) — the
--              get_my_tickets posture, no longer inherited from a default ACL;
--              pinned not assumed);
--              output column lists verbatim; forbidden names absent; public
--              census 130 (pgtap-excluded, the tests/162 P2 query); comments.
--   Section L  list_primary_sessions_on_sale: exactly {f2, f6, f11}; draft /
--              announced / cancelled / completed event / completed session /
--              no public tier on sale / future window / pending room never
--              listed; projections (title, venue, neighborhood, doors_at,
--              status = event status, age_restriction); starts_at order; the
--              fan sees the same; approving V2 lists f10 (the approval rule);
--              the appended timezone / starts_at_local / doors_at_local
--              (L17 hard-coded for f2; L18 every listed row equals AT TIME
--              ZONE of its base row, read by a definer oracle; L19 the strings
--              do not move under session TimeZone Asia/Tokyo).
--   Section P  get_primary_session: 0 rows for unknown / draft / announced /
--              cancelled / pending room; f2 one row; ticket_types = the two
--              public tiers only (hidden, door_only absent); remaining = the
--              public_sale-only sum (136 = (100-0-3)+(50-0-11) after issuance;
--              comp 30 and door 20 excluded) both hard-coded and against a
--              definer oracle; capacity/held/sold keys ABSENT; element / session
--              / event / venue key sets exact; on_sale_now follows 162's helper
--              (true now, false for the future window and the completed event);
--              *_local via the room's timezone; '[]' when no public tier; the
--              completed event and the completed session stay readable.
--   Section T  get_my_ticket_atoms: B1 3 / B2 1 / forged 0 / fan 0; B2 never
--              sees B1's atoms; anon 42501; NULL uid 28000; raw states
--              {active, scanned, voided}; credential_version 1 on the bumped
--              atom; serials 1..3; tier name; the atoms carry the sequence-1
--              'issue' ledger rows with cause_ref = order_item (the real link).
--   Section O  get_my_primary_orders: B1 6 / B2 1 / forged 0 / fan 0; B2 never
--              sees B1's orders; anon 42501; NULL uid 28000; O1 paid /
--              atoms_issued 3 / succeeded; O2 pending / 0 / none (no link —
--              the structural limitation, pinned as it is); failed /
--              processing / refunded→succeeded / pending→processing; the other
--              session's order excluded; newest first; payment_native exists
--              for O1 (written by finalize); charge_total_minor = the linked
--              payments.total (O1 9000) and NULL with no link (O2).
--   Section F  buyer_fee_minor / all_in_price_minor against the REAL checkout
--              (runs last: it creates the fan's orders and a new event, so no
--              earlier count moves). Fixture as postgres: event ec (on_sale,
--              V1) / session fc with three public tiers — 2500, 1005 (fee
--              lands on .5 cent at 1000 bps), 1004 — each with a public_sale
--              batch and the fan's active holds (inserted as rows, batch held
--              raised to match, the O1/O7 pattern); the 252 org made payable
--              (Connect ref + transfers active, the 146 scaffolding UPDATE);
--              the live-guarded b0 key above already resolves. Every rate is a
--              NEW VERSION of the append-only catalog.platform_config row
--              (174/230 pattern), rolled back with the file. HOW THE CHECKOUT
--              IS CALLED: venue.create_primary_checkout(fc, [{tier, qty}],
--              [hold], key) as the fan through tap.login (it requires
--              auth.uid(); EXECUTE is granted to authenticated, 082/093), its
--              jsonb result stored via tap._store252, then compared with what
--              get_primary_session returns to anon in the SAME transaction —
--              same rows, same rate version, same now().
--              F1/F2 rate unset (JSON null on top) → both NULL, and checkout
--              refuses service_fee_unset; F3/F4 10001 → NULL, checkout refuses
--              service_fee_out_of_range; then 1000 bps: F5-F7 the 2500 tier —
--              all_in = checkout charge_total_minor, fee = checkout
--              buyer_fee_minor = all_in − price; F8/F9 the 1005 tier —
--              (101, 1106) both hard-coded (100.5 rounds half-up; half-even or
--              truncation would give 100) and equal to checkout; F10/F11 1004
--              → (100, 1104) = checkout (100.4 rounds down: round, not ceil);
--              F12 two units of the 1005 tier — checkout charges 2211, not
--              2 × 1106: the fee is rounded per ORDER, which is why the read
--              is a quantity-1 figure only (header of 182). F13-F15 the order
--              read's charge_total_minor end to end: a payments row written
--              exactly as the primary-checkout edge writes it from the 2500
--              checkout's return (amount = face, buyer_fee, total = charge),
--              succeeded, then the real finalize → get_my_primary_orders shows
--              total_minor 2500 and charge_total_minor 2750 = checkout's
--              charge = payments.total; the three pending orders read NULL
--              although a rate is set (never recomputed). F16/F17 LAST:
--              non-numeric text on top → the read is NULL and does not raise,
--              checkout raises 22P02 (last because checkout casts every
--              historical row of the key on a seq-scan plan — see the note
--              above F16 and EVIDENCE-182b).
--
-- Expected on 159+176+160+161+162 WITHOUT 182 (RED, predicted before the first
-- run; reconciled in EVIDENCE-182.md §1): the fixture (tables and the real
-- finalize path only) succeeds; A1-A18 all `not ok` (functions absent — every
-- probe is NULL-safe via to_regprocedure / coalesce; the census reads 126, not
-- 130); L1 is the first direct call of a 182 function, raises 42883 and aborts
-- the transaction, so L2 onward is never emitted. Predicted RED run: 18
-- emitted = 18 not ok + 0 ok; plan unmet; psql reports the 42883.
-- Expected against the PRE-FOLD-IN 182 (4e45fbc9's body; EVIDENCE-182b §1):
-- A1-A11 ok, A12 not ok (nine columns, not twelve), A13-A15 ok, A16 not ok
-- (seven columns, no charge_total_minor), A17-A18 ok, L1-L16 ok, L17
-- references l.timezone and raises 42703, aborting the run: 34 emitted =
-- 32 ok + 2 not ok; plan (113) unmet.
-- ============================================================================
BEGIN;
SELECT plan(113);

CREATE TABLE tap.memo_252 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store252(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_252 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch252(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_252 WHERE k = $1 $m$;
-- definer oracle for P12: the public_sale-only remaining of (tier, session), read
-- as postgres (E-29: no client role may SELECT capacity/held/sold).
CREATE FUNCTION tap._rem252(tt uuid, s uuid) RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT coalesce(sum(capacity - held - sold), 0)::integer FROM venue.inventory_batch
     WHERE ticket_type_id = tt AND event_session_id = s AND release_kind = 'public_sale' $m$;
-- definer oracle for L18: (timezone, starts_at_local, doors_at_local) of a session computed
-- from its BASE rows (catalog.event_session x catalog.venue) as postgres.
CREATE FUNCTION tap._loc252(sid uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = '' AS
$m$ SELECT (v.timezone, to_char(s.starts_at AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI'),
                         to_char(s.doors_at  AT TIME ZONE v.timezone, 'YYYY-MM-DD HH24:MI'))::text
      FROM catalog.event_session s JOIN catalog.event e ON e.event_id = s.event_id JOIN catalog.venue v ON v.venue_id = e.venue_id
     WHERE s.session_id = sid $m$;
-- throwaway P-256 SPKI PEM (suite 176's; generated with openssl, no private half anywhere)
CREATE FUNCTION tap._pem252() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;
GRANT EXECUTE ON FUNCTION tap._store252(text, text), tap._fetch252(text), tap._rem252(uuid, uuid), tap._loc252(uuid) TO anon, authenticated;

-- ── Fixture (synthetic; never a migration) ─────────────────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, email_confirmed_at, created_at, updated_at) VALUES
  ('25200000-0000-4000-8000-000000000101', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'buyer1.252@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('25200000-0000-4000-8000-000000000102', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'buyer2.252@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now(), now()),
  ('25200000-0000-4000-8000-000000000199', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'fan.252@test.local',    '{"provider":"email","providers":["email"]}', '{}', now(), now(), now())
ON CONFLICT (id) DO NOTHING;
-- SN-SYSTEM (the mint's actor when auth.uid() is NULL — 093:4904); present on every chain, inserted only if a bare clone lacks it.
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
  ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'sn-system.252@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now())
ON CONFLICT (id) DO NOTHING;
INSERT INTO kernel.organization (org_id, legal_name, display_name, status) VALUES
  ('25200000-0000-4000-8000-00000000000a', 'Org A 252', 'Org A 252', 'active');
INSERT INTO catalog.venue (venue_id, org_id, name, neighborhood, address, approval_status) VALUES
  ('25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'Room V1 252', 'wynwood',  '1 Test St', 'approved'),
  ('25200000-0000-4000-8000-0000000000a2', '25200000-0000-4000-8000-00000000000a', 'Room V2 252', 'brickell', NULL,        'pending');
UPDATE catalog.venue SET timezone = 'America/Chicago' WHERE venue_id = '25200000-0000-4000-8000-0000000000a1';
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status, description, category, age_policy) VALUES
  ('25200000-0000-4000-8000-0000000000e1', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 draft 252',          'draft',     NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e2', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 on sale 252',        'on_sale',   'Opening night', 'nightlife', NULL),
  ('25200000-0000-4000-8000-0000000000e3', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 completed 252',      'completed', NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e4', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 cancelled 252',      'cancelled', NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e5', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 announced 252',      'announced', NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e6', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 live 252',           'live',      NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e7', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 no public tier 252', 'on_sale',   NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e8', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 future window 252',  'on_sale',   NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000e9', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 session done 252',   'on_sale',   NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000ea', '25200000-0000-4000-8000-0000000000a2', '25200000-0000-4000-8000-00000000000a', 'V2 pending room 252',   'on_sale',   NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000eb', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 21 plus 252',        'on_sale',   NULL, NULL, '21_plus');
INSERT INTO catalog.event_session (session_id, event_id, session_label, starts_at, ends_at, doors_at, status) VALUES
  ('25200000-0000-4000-8000-0000000000f1', '25200000-0000-4000-8000-0000000000e1', NULL,   now() + interval '30 days', NULL, NULL, 'scheduled'),
  ('25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-0000000000e2', 'Main', '2026-12-05 03:00:00+00', '2026-12-05 07:00:00+00', '2026-12-05 02:00:00+00', 'scheduled'),
  ('25200000-0000-4000-8000-0000000000f3', '25200000-0000-4000-8000-0000000000e3', NULL,   now() - interval '3 days',  NULL, NULL, 'completed'),
  ('25200000-0000-4000-8000-0000000000f4', '25200000-0000-4000-8000-0000000000e4', NULL,   now() + interval '5 days',  NULL, NULL, 'cancelled'),
  ('25200000-0000-4000-8000-0000000000f5', '25200000-0000-4000-8000-0000000000e5', NULL,   now() + interval '11 days', NULL, NULL, 'scheduled'),
  ('25200000-0000-4000-8000-0000000000f6', '25200000-0000-4000-8000-0000000000e6', NULL,   now() + interval '1 hour',  NULL, NULL, 'live'),
  ('25200000-0000-4000-8000-0000000000f7', '25200000-0000-4000-8000-0000000000e7', NULL,   now() + interval '12 days', NULL, NULL, 'scheduled'),
  ('25200000-0000-4000-8000-0000000000f8', '25200000-0000-4000-8000-0000000000e8', NULL,   now() + interval '20 days', NULL, NULL, 'scheduled'),
  ('25200000-0000-4000-8000-0000000000f9', '25200000-0000-4000-8000-0000000000e9', NULL,   now() - interval '2 days',  NULL, NULL, 'completed'),
  ('25200000-0000-4000-8000-0000000000fa', '25200000-0000-4000-8000-0000000000ea', NULL,   now() + interval '6 days',  NULL, NULL, 'scheduled'),
  ('25200000-0000-4000-8000-0000000000fb', '25200000-0000-4000-8000-0000000000eb', NULL,   now() + interval '45 days', NULL, NULL, 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility, display_rank, sale_starts_at, sale_ends_at) VALUES
  ('25200000-0000-4000-8000-000000000011', '25200000-0000-4000-8000-0000000000e1', 'admission', 'GA draft 252',      2500, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000021', '25200000-0000-4000-8000-0000000000e2', 'admission', 'GA',                3000, 'public',    2,    NULL, NULL),
  ('25200000-0000-4000-8000-000000000022', '25200000-0000-4000-8000-0000000000e2', 'admission', 'Hidden 252',        1800, 'hidden',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000023', '25200000-0000-4000-8000-0000000000e2', 'table',     'Door table 252',    1500, 'door_only', NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000024', '25200000-0000-4000-8000-0000000000e2', 'admission', 'Early bird',        2500, 'public',    1,    now() - interval '1 day', now() + interval '1 day'),
  ('25200000-0000-4000-8000-000000000031', '25200000-0000-4000-8000-0000000000e3', 'admission', 'GA completed 252',  2700, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000041', '25200000-0000-4000-8000-0000000000e4', 'admission', 'GA cancelled 252',  2800, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000051', '25200000-0000-4000-8000-0000000000e5', 'admission', 'GA announced 252',  3100, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000061', '25200000-0000-4000-8000-0000000000e6', 'admission', 'GA live 252',       3200, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000071', '25200000-0000-4000-8000-0000000000e7', 'admission', 'Hidden only 252',   1000, 'hidden',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000072', '25200000-0000-4000-8000-0000000000e7', 'table',     'Door only 252',     1200, 'door_only', NULL, NULL, NULL),
  ('25200000-0000-4000-8000-000000000081', '25200000-0000-4000-8000-0000000000e8', 'admission', 'GA future 252',     3300, 'public',    NULL, now() + interval '10 days', NULL),
  ('25200000-0000-4000-8000-000000000091', '25200000-0000-4000-8000-0000000000e9', 'admission', 'GA done 252',       3400, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-0000000000ea', 'admission', 'GA pending 252',    3500, 'public',    NULL, NULL, NULL),
  ('25200000-0000-4000-8000-0000000000b1', '25200000-0000-4000-8000-0000000000eb', 'admission', 'GA 21 plus 252',    3600, 'public',    NULL, NULL, NULL);
-- b21 / b21b: the GA tier's two PUBLIC_SALE batches on f2 (held 3 / 1 = the two buyers' holds below, converted by finalize);
-- b21c comp and b21d door: NOT buyer inventory, excluded from `remaining`; b22 / b23: hidden / door_only tiers, never serialised.
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('25200000-0000-4000-8000-0000000000c1', '25200000-0000-4000-8000-000000000011', '25200000-0000-4000-8000-0000000000f1', 'public_sale', 100, 0, 0),
  ('25200000-0000-4000-8000-0000000000c2', '25200000-0000-4000-8000-000000000021', '25200000-0000-4000-8000-0000000000f2', 'public_sale', 100, 3, 0),
  ('25200000-0000-4000-8000-0000000000c3', '25200000-0000-4000-8000-000000000021', '25200000-0000-4000-8000-0000000000f2', 'public_sale',  50, 1, 10),
  ('25200000-0000-4000-8000-0000000000c4', '25200000-0000-4000-8000-000000000021', '25200000-0000-4000-8000-0000000000f2', 'comp',         30, 0, 0),
  ('25200000-0000-4000-8000-0000000000c5', '25200000-0000-4000-8000-000000000021', '25200000-0000-4000-8000-0000000000f2', 'door',         20, 0, 5),
  ('25200000-0000-4000-8000-0000000000c6', '25200000-0000-4000-8000-000000000022', '25200000-0000-4000-8000-0000000000f2', 'public_sale', 500, 0, 0),
  ('25200000-0000-4000-8000-0000000000c7', '25200000-0000-4000-8000-000000000023', '25200000-0000-4000-8000-0000000000f2', 'door',         40, 0, 0),
  ('25200000-0000-4000-8000-0000000000c8', '25200000-0000-4000-8000-000000000024', '25200000-0000-4000-8000-0000000000f2', 'public_sale',  10, 0, 2),
  ('25200000-0000-4000-8000-0000000000c9', '25200000-0000-4000-8000-000000000031', '25200000-0000-4000-8000-0000000000f3', 'public_sale', 150, 0, 150),
  ('25200000-0000-4000-8000-0000000000ca', '25200000-0000-4000-8000-000000000041', '25200000-0000-4000-8000-0000000000f4', 'public_sale', 150, 0, 0),
  ('25200000-0000-4000-8000-0000000000cb', '25200000-0000-4000-8000-000000000051', '25200000-0000-4000-8000-0000000000f5', 'public_sale', 120, 0, 0),
  ('25200000-0000-4000-8000-0000000000cc', '25200000-0000-4000-8000-000000000061', '25200000-0000-4000-8000-0000000000f6', 'public_sale',  80, 0, 20),
  ('25200000-0000-4000-8000-0000000000cd', '25200000-0000-4000-8000-000000000071', '25200000-0000-4000-8000-0000000000f7', 'public_sale',  70, 0, 0),
  ('25200000-0000-4000-8000-0000000000ce', '25200000-0000-4000-8000-000000000081', '25200000-0000-4000-8000-0000000000f8', 'public_sale',  60, 0, 0),
  ('25200000-0000-4000-8000-0000000000cf', '25200000-0000-4000-8000-000000000091', '25200000-0000-4000-8000-0000000000f9', 'public_sale',  90, 0, 90),
  ('25200000-0000-4000-8000-0000000000d0', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-0000000000fa', 'public_sale',  55, 0, 0),
  ('25200000-0000-4000-8000-0000000000d1', '25200000-0000-4000-8000-0000000000b1', '25200000-0000-4000-8000-0000000000fb', 'public_sale',  65, 0, 0);

-- ── Orders — all born 'pending' (082: items are immutable once the order leaves pending), O3/O5 moved below
--    (B1: O1 paid-via-finalize, O2 pending/no payment, O3 cancelled/failed, O4 pending/processing,
--            O5 refunded, O6 pending/pending-payment, O8 on the OTHER session f6; B2: O7 paid-via-finalize) ──
INSERT INTO venue."order" (order_id, buyer_id, event_session_id, org_id, status, source, total_minor, currency, command_idempotency_key, created_at) VALUES
  ('25200000-0000-4000-8000-000000000301', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 9000, 'USD', 'o1-252', '2026-10-20 10:00:00+00'),
  ('25200000-0000-4000-8000-000000000302', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 2500, 'USD', 'o2-252', '2026-10-20 11:00:00+00'),
  ('25200000-0000-4000-8000-000000000303', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 3000, 'USD', 'o3-252', '2026-10-20 12:00:00+00'),
  ('25200000-0000-4000-8000-000000000304', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 3000, 'USD', 'o4-252', '2026-10-20 13:00:00+00'),
  ('25200000-0000-4000-8000-000000000305', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 3000, 'USD', 'o5-252', '2026-10-20 14:00:00+00'),
  ('25200000-0000-4000-8000-000000000306', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 3000, 'USD', 'o6-252', '2026-10-20 15:00:00+00'),
  ('25200000-0000-4000-8000-000000000307', '25200000-0000-4000-8000-000000000102', '25200000-0000-4000-8000-0000000000f2', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 3000, 'USD', 'o7-252', '2026-10-20 16:00:00+00'),
  ('25200000-0000-4000-8000-000000000308', '25200000-0000-4000-8000-000000000101', '25200000-0000-4000-8000-0000000000f6', '25200000-0000-4000-8000-00000000000a', 'pending',  'app', 3200, 'USD', 'o8-252', '2026-10-20 17:00:00+00');
INSERT INTO venue.order_item (id, order_id, ticket_type_id, quantity, unit_price_minor) VALUES
  ('25200000-0000-4000-8000-000000000401', '25200000-0000-4000-8000-000000000301', '25200000-0000-4000-8000-000000000021', 3, 3000),
  ('25200000-0000-4000-8000-000000000402', '25200000-0000-4000-8000-000000000302', '25200000-0000-4000-8000-000000000024', 1, 2500),
  ('25200000-0000-4000-8000-000000000403', '25200000-0000-4000-8000-000000000303', '25200000-0000-4000-8000-000000000021', 1, 3000),
  ('25200000-0000-4000-8000-000000000404', '25200000-0000-4000-8000-000000000304', '25200000-0000-4000-8000-000000000021', 1, 3000),
  ('25200000-0000-4000-8000-000000000405', '25200000-0000-4000-8000-000000000305', '25200000-0000-4000-8000-000000000021', 1, 3000),
  ('25200000-0000-4000-8000-000000000406', '25200000-0000-4000-8000-000000000306', '25200000-0000-4000-8000-000000000021', 1, 3000),
  ('25200000-0000-4000-8000-000000000407', '25200000-0000-4000-8000-000000000307', '25200000-0000-4000-8000-000000000021', 1, 3000),
  ('25200000-0000-4000-8000-000000000408', '25200000-0000-4000-8000-000000000308', '25200000-0000-4000-8000-000000000061', 1, 3200);
-- O3 / O5 reach their terminal statuses AFTER their items exist (082 tg_order_item_immutable refuses an item on a non-pending order)
UPDATE venue."order" SET status = 'cancelled' WHERE order_id = '25200000-0000-4000-8000-000000000303';
UPDATE venue."order" SET status = 'refunded'  WHERE order_id = '25200000-0000-4000-8000-000000000305';
-- the buyers' reservations (finalize names each item's batch through the buyer's hold and converts it)
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('25200000-0000-4000-8000-000000000501', '25200000-0000-4000-8000-0000000000c2', '25200000-0000-4000-8000-000000000101', 3, 'active', now() + interval '1 hour', 'h1-252'),
  ('25200000-0000-4000-8000-000000000507', '25200000-0000-4000-8000-0000000000c3', '25200000-0000-4000-8000-000000000102', 1, 'active', now() + interval '1 hour', 'h7-252');
-- payments (direct rail: mode native_primary, listing_id / seller_id NULL — 093 payments_rail_pairing_ck)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at) VALUES
  ('25200000-0000-4000-8000-000000000601', NULL, '25200000-0000-4000-8000-000000000101', NULL, 9000, 0, 0, 9000, 'pi_252_o1', 'succeeded',  'native_primary', now()),
  ('25200000-0000-4000-8000-000000000603', NULL, '25200000-0000-4000-8000-000000000101', NULL, 3000, 0, 0, 3000, 'pi_252_o3', 'failed',     'native_primary', NULL),
  ('25200000-0000-4000-8000-000000000604', NULL, '25200000-0000-4000-8000-000000000101', NULL, 3000, 0, 0, 3000, 'pi_252_o4', 'processing', 'native_primary', NULL),
  ('25200000-0000-4000-8000-000000000605', NULL, '25200000-0000-4000-8000-000000000101', NULL, 3000, 0, 0, 3000, 'pi_252_o5', 'refunded',   'native_primary', now()),
  ('25200000-0000-4000-8000-000000000606', NULL, '25200000-0000-4000-8000-000000000101', NULL, 3000, 0, 0, 3000, 'pi_252_o6', 'pending',    'native_primary', NULL),
  ('25200000-0000-4000-8000-000000000607', NULL, '25200000-0000-4000-8000-000000000102', NULL, 3000, 0, 0, 3000, 'pi_252_o7', 'succeeded',  'native_primary', now());
-- the payment_state matrix: links finalize would never write (it links only a succeeded payment) — pinned as rows
INSERT INTO kernel.payment_native (payment_id, order_id, amount_minor) VALUES
  ('25200000-0000-4000-8000-000000000603', '25200000-0000-4000-8000-000000000303', 3000),
  ('25200000-0000-4000-8000-000000000604', '25200000-0000-4000-8000-000000000304', 3000),
  ('25200000-0000-4000-8000-000000000605', '25200000-0000-4000-8000-000000000305', 3000),
  ('25200000-0000-4000-8000-000000000606', '25200000-0000-4000-8000-000000000306', 3000);

-- ── THE REAL ISSUANCE PATH (as the rehearsal superuser; auth.uid() NULL → actor SN-SYSTEM) ──
-- flag: a new version of the append-only config row (174/230 pattern); rolled back with the file
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'feature.native_issuance_enabled', coalesce(max(version), 0) + 1, 'true'::jsonb, 'public'
  FROM catalog.platform_config WHERE key = 'feature.native_issuance_enabled';
-- the global ES256 bootstrap key THROUGH THE LIVE 110 GUARD (B's recipe: ruling-B key_id, throwaway P-256 PEM, all-zero ARN)
INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, algorithm, status, not_before)
VALUES ('00000000-0000-0000-0000-0000000000b0', 'global', tap._pem252(),
        'arn:aws:kms:us-east-1:000000000000:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active', now());
SELECT tap._store252('fin_o1', venue.finalize_primary_order('25200000-0000-4000-8000-000000000301', '25200000-0000-4000-8000-000000000601', 'ck252-o1', NULL)::text);
SELECT tap._store252('fin_o7', venue.finalize_primary_order('25200000-0000-4000-8000-000000000307', '25200000-0000-4000-8000-000000000607', 'ck252-o7', NULL)::text);
-- raw-state fixtures on B1's atoms (serials 1..3): #2 scanned; #3 voided + credential_version 1 with its paired ledger row
UPDATE kernel.tickets SET state = 'scanned'
 WHERE event_session_id = '25200000-0000-4000-8000-0000000000f2' AND current_owner_id = '25200000-0000-4000-8000-000000000101' AND serial_no = 2;
UPDATE kernel.tickets SET state = 'voided', credential_version = 1
 WHERE event_session_id = '25200000-0000-4000-8000-0000000000f2' AND current_owner_id = '25200000-0000-4000-8000-000000000101' AND serial_no = 3;
INSERT INTO kernel.ticket_ownership_log (ticket_atom_id, sequence, from_identity, to_identity, cause, cause_ref, actor_identity, command_idempotency_key, credential_version_after, state_transition)
SELECT t.ticket_atom_id, 2, t.current_owner_id, t.current_owner_id, 'admin_action', '25200000-0000-4000-8000-000000000999', '00000000-0000-0000-0000-0000000000f1', 'ck252-void:' || t.ticket_atom_id::text, 1,
       jsonb_build_object('from', 'active', 'to', 'voided')
  FROM kernel.tickets t
 WHERE t.event_session_id = '25200000-0000-4000-8000-0000000000f2' AND t.current_owner_id = '25200000-0000-4000-8000-000000000101' AND t.serial_no = 3;

-- ── Section A — shape + ACL + census (NULL-safe) ─────────────────────────────
SELECT has_function('public'::name, 'list_primary_sessions_on_sale'::name, ARRAY[]::name[], 'A1: public.list_primary_sessions_on_sale() exists');
SELECT has_function('public'::name, 'get_primary_session'::name, ARRAY['uuid']::name[], 'A2: public.get_primary_session(uuid) exists');
SELECT has_function('public'::name, 'get_my_ticket_atoms'::name, ARRAY['uuid']::name[], 'A3: public.get_my_ticket_atoms(uuid) exists');
SELECT has_function('public'::name, 'get_my_primary_orders'::name, ARRAY['uuid']::name[], 'A4: public.get_my_primary_orders(uuid) exists');
SELECT ok(coalesce((SELECT bool_and(p.prosecdef) AND count(*) = 4 FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.list_primary_sessions_on_sale()'), to_regprocedure('public.get_primary_session(uuid)'),
           to_regprocedure('public.get_my_ticket_atoms(uuid)'), to_regprocedure('public.get_my_primary_orders(uuid)'))), false),
  'A5: all four are SECURITY DEFINER');
SELECT ok(coalesce((SELECT bool_and(p.proconfig = ARRAY['search_path=""']) AND count(*) = 4 FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.list_primary_sessions_on_sale()'), to_regprocedure('public.get_primary_session(uuid)'),
           to_regprocedure('public.get_my_ticket_atoms(uuid)'), to_regprocedure('public.get_my_primary_orders(uuid)'))), false),
  'A6: all four pin search_path = ''''');
SELECT ok(coalesce((SELECT bool_and(p.provolatile::text = 's') AND count(*) = 4 FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.list_primary_sessions_on_sale()'), to_regprocedure('public.get_primary_session(uuid)'),
           to_regprocedure('public.get_my_ticket_atoms(uuid)'), to_regprocedure('public.get_my_primary_orders(uuid)'))), false),
  'A7: all four are STABLE');
SELECT ok(coalesce(has_function_privilege('anon', to_regprocedure('public.list_primary_sessions_on_sale()'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.list_primary_sessions_on_sale()'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.list_primary_sessions_on_sale()'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.list_primary_sessions_on_sale()')), false),
  'A8: list — EXECUTE anon + authenticated (explicit grant, non-NULL proacl, no PUBLIC entry); service_role EXECUTE by an explicit grant (182 PART 5; the get_my_tickets posture)');
SELECT ok(coalesce(has_function_privilege('anon', to_regprocedure('public.get_primary_session(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.get_primary_session(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.get_primary_session(uuid)'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_primary_session(uuid)')), false),
  'A9: detail — EXECUTE anon + authenticated (explicit, non-NULL proacl, no PUBLIC); service_role EXECUTE by an explicit grant (182 PART 5)');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('public.get_my_ticket_atoms(uuid)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.get_my_ticket_atoms(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.get_my_ticket_atoms(uuid)'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_my_ticket_atoms(uuid)')), false),
  'A10: atoms — anon revoked, authenticated EXECUTE, no PUBLIC; service_role EXECUTE by an explicit grant (182 PART 5; auth.uid() NULL -> 28000 for it)');
SELECT ok(NOT coalesce(has_function_privilege('anon', to_regprocedure('public.get_my_primary_orders(uuid)'), 'EXECUTE'), true)
      AND coalesce(has_function_privilege('authenticated', to_regprocedure('public.get_my_primary_orders(uuid)'), 'EXECUTE'), false)
      AND coalesce(has_function_privilege('service_role', to_regprocedure('public.get_my_primary_orders(uuid)'), 'EXECUTE'), false)
      AND coalesce((SELECT p.proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0)
                      FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_my_primary_orders(uuid)')), false),
  'A11: orders — anon revoked, authenticated EXECUTE, no PUBLIC; service_role EXECUTE by an explicit grant (182 PART 5; auth.uid() NULL -> 28000 for it)');
SELECT is((SELECT p.proargnames || (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(p.proallargtypes) WITH ORDINALITY u(t, o))
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.list_primary_sessions_on_sale()')),
  ARRAY['event_id','session_id','title','venue_name','neighborhood','starts_at','doors_at','age_restriction','status','timezone','starts_at_local','doors_at_local',
        'uuid','uuid','text','text','text','timestamp with time zone','timestamp with time zone','text','text','text','text','text']::text[],
  'A12: list returns exactly (event_id, session_id, title, venue_name, neighborhood, starts_at, doors_at, age_restriction, status, timezone, starts_at_local, doors_at_local) with those types — the three local-time columns appended LAST');
SELECT is((SELECT p.proargnames || (SELECT array_agg(format_type(t, NULL) ORDER BY o) FROM unnest(p.proallargtypes) WITH ORDINALITY u(t, o))
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_primary_session(uuid)')),
  ARRAY['p_session_id','session','event','venue','ticket_types','uuid','jsonb','jsonb','jsonb','jsonb']::text[],
  'A13: detail returns exactly (session jsonb, event jsonb, venue jsonb, ticket_types jsonb)');
SELECT is((SELECT p.proargnames FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_my_ticket_atoms(uuid)')),
  ARRAY['p_event_session_id','ticket_atom_id','serial_no','ticket_type_id','ticket_type_name','state','resale_state','credential_version','issued_at']::text[],
  'A14: atoms returns exactly (ticket_atom_id, serial_no, ticket_type_id, ticket_type_name, state, resale_state, credential_version, issued_at)');
SELECT ok(coalesce((SELECT bool_and(NOT (p.proargnames && ARRAY['signing_key_id','current_owner_id','owner_id','org_id','seat_ref','unit_row_id','external_seat_ref','home_region','kms_handle_ref','buyer_id','stripe_payment_intent_id']::text[])) AND count(*) = 2
                      FROM pg_proc p WHERE p.oid IN (to_regprocedure('public.get_my_ticket_atoms(uuid)'), to_regprocedure('public.get_my_primary_orders(uuid)'))), false),
  'A15: neither owner read names signing_key_id / owner ids / org_id / seat refs / KMS or Stripe references');
SELECT is((SELECT p.proargnames FROM pg_proc p WHERE p.oid = to_regprocedure('public.get_my_primary_orders(uuid)')),
  ARRAY['p_event_session_id','order_id','status','total_minor','currency','created_at','atoms_issued','payment_state','charge_total_minor']::text[],
  'A16: orders returns exactly (order_id, status, total_minor, currency, created_at, atoms_issued, payment_state, charge_total_minor)');
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')), 130,
  'A17: GATE-2 public functions = 130 (126 + the four 182 reads; pgtap excluded — the tests/162 P2 query)');
SELECT ok(coalesce((SELECT count(*) = 4 AND bool_and(length(obj_description(p.oid, 'pg_proc')) > 40) FROM pg_proc p WHERE p.oid IN (
           to_regprocedure('public.list_primary_sessions_on_sale()'), to_regprocedure('public.get_primary_session(uuid)'),
           to_regprocedure('public.get_my_ticket_atoms(uuid)'), to_regprocedure('public.get_my_primary_orders(uuid)'))), false),
  'A18: every function carries a comment');

-- ── Section L — list_primary_sessions_on_sale (anon first) ───────────────────
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.title LIKE '%252'), 3,
  'L1: anon — exactly three 252 sessions are listed');
SELECT set_eq($$SELECT l.session_id FROM public.list_primary_sessions_on_sale() l WHERE l.title LIKE '%252'$$,
  ARRAY['25200000-0000-4000-8000-0000000000f2','25200000-0000-4000-8000-0000000000f6','25200000-0000-4000-8000-0000000000fb']::uuid[],
  'L2: the set is {f2 on_sale, f6 live, fb 21_plus}');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f1'), 0, 'L3: a DRAFT event is never listed');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f5'), 0, 'L4: an ANNOUNCED event is never listed');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f4'), 0, 'L5: a cancelled event / cancelled session is never listed');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f3'), 0, 'L6: a COMPLETED event is never listed');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f9'), 0, 'L7: an on_sale event whose SESSION is completed is not listed');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f7'), 0, 'L8: an on_sale event with only hidden / door_only tiers is not listed (no public tier on sale)');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f8'), 0, 'L9: an on_sale event whose public tier''s window opens in 10 days is not listed (162 helper)');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000fa'), 0, 'L10: an on_sale event at a non-approved room is not listed (RLS parity with catalog_venue_sel_anon)');
SELECT is((SELECT (l.event_id::text, l.title, l.venue_name, l.neighborhood, l.doors_at::text, l.status, l.age_restriction IS NULL)::text
             FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f2'),
  ('25200000-0000-4000-8000-0000000000e2', 'V1 on sale 252', 'Room V1 252', 'wynwood', '2026-12-05 02:00:00+00'::timestamptz::text, 'on_sale', true)::text,
  'L11: the f2 row projects event_id, title, venue_name, neighborhood, doors_at, status = event status, age_restriction NULL (not specified)');
SELECT is((SELECT l.age_restriction FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000fb'), '21_plus',
  'L12: age_restriction = catalog.event.age_policy (21_plus)');
SELECT is((SELECT l.status FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f6'), 'live',
  'L13: a LIVE event is listed with status live');
SELECT is((SELECT array_agg(l.session_id) FROM (SELECT * FROM public.list_primary_sessions_on_sale()) l),
          (SELECT array_agg(l.session_id ORDER BY l.starts_at ASC, l.session_id ASC) FROM public.list_primary_sessions_on_sale() l),
  'L14: rows are ordered by starts_at asc (session_id tie-break)');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.title LIKE '%252'), 3,
  'L15: an authenticated fan sees the same three sessions');
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'approved' WHERE venue_id = '25200000-0000-4000-8000-0000000000a2';
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000fa'), 1,
  'L16: once the room is approved the same on_sale event IS listed (the approval rule, positively)');
SELECT tap.logout();
UPDATE catalog.venue SET approval_status = 'pending' WHERE venue_id = '25200000-0000-4000-8000-0000000000a2';
SELECT tap._store252('tz0', current_setting('TimeZone'));
SELECT tap.login_anon();
SELECT is((SELECT (l.timezone, l.starts_at_local, l.doors_at_local)::text FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f2'),
  ('America/Chicago', '2026-12-04 21:00', '2026-12-04 20:00')::text,
  'L17: the f2 row carries timezone America/Chicago and the local strings (03:00Z -> 21:00 and 02:00Z -> 20:00 the day before), the get_primary_session format');
SELECT is((SELECT count(*)::int FROM public.list_primary_sessions_on_sale() l
            WHERE l.title LIKE '%252' AND (l.timezone, l.starts_at_local, l.doors_at_local)::text IS NOT DISTINCT FROM tap._loc252(l.session_id)), 3,
  'L18: every listed 252 row equals (venue.timezone, to_char(starts_at AT TIME ZONE tz), to_char(doors_at AT TIME ZONE tz)) of its base row (NULL doors -> NULL doors_at_local)');
SELECT set_config('TimeZone', 'Asia/Tokyo', true);
SELECT is((SELECT (l.timezone, l.starts_at_local, l.doors_at_local, (SELECT l2.doors_at_local IS NULL FROM public.list_primary_sessions_on_sale() l2 WHERE l2.session_id = '25200000-0000-4000-8000-0000000000fb'))::text
             FROM public.list_primary_sessions_on_sale() l WHERE l.session_id = '25200000-0000-4000-8000-0000000000f2'),
  ('America/Chicago', '2026-12-04 21:00', '2026-12-04 20:00', true)::text,
  'L19: under session TimeZone Asia/Tokyo the strings are unchanged (zone-local, not session-local); fb (no doors) reads doors_at_local NULL');
SELECT set_config('TimeZone', tap._fetch252('tz0'), true);
SELECT tap.logout();

-- ── Section P — get_primary_session (anon) ──────────────────────────────────
SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-00000000dead')), 0, 'P1: an unknown id yields ZERO rows (no error, no not_found row)');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f1')), 0, 'P2: a DRAFT event''s session yields zero rows (no existence leak)');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f5')), 0, 'P3: an ANNOUNCED event''s session yields zero rows');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f4')), 0, 'P4: a cancelled session yields zero rows');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fa')), 0, 'P5: a session at a non-approved room yields zero rows');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2')), 1, 'P6: the on_sale session f2 yields exactly one row');
SELECT is((SELECT jsonb_array_length(g.ticket_types) FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g), 2,
  'P7: ticket_types holds exactly the two PUBLIC tiers');
SELECT set_eq($$SELECT (e ->> 'ticket_type_id')::uuid FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e$$,
  ARRAY['25200000-0000-4000-8000-000000000021','25200000-0000-4000-8000-000000000024']::uuid[],
  'P8: they are GA and Early bird');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000022'), 0,
  'P9: the HIDDEN tier never appears');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000023'), 0,
  'P10: the DOOR_ONLY tier never appears');
SELECT is((SELECT (e ->> 'remaining')::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000021'), 136,
  'P11: GA remaining = (100-0-3) + (50-0-11) = 136 over the two public_sale batches after issuance — the comp (30) and door (20-0-5) batches are excluded');
SELECT is((SELECT (e ->> 'remaining')::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000021'),
          tap._rem252('25200000-0000-4000-8000-000000000021', '25200000-0000-4000-8000-0000000000f2'),
  'P12: GA remaining equals the definer oracle SUM(capacity-held-sold) over public_sale batches of (tier, session)');
SELECT is((SELECT (e ->> 'remaining')::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000024'), 8,
  'P13: Early bird remaining = 10-0-2 = 8');
SELECT ok((SELECT bool_and(NOT (e ? 'capacity') AND NOT (e ? 'held') AND NOT (e ? 'sold')) FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e),
  'P14: capacity / held / sold keys are ABSENT from every ticket_types element (081 E-29)');
SELECT ok((SELECT bool_and((SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(e) k) =
                           ARRAY['all_in_price_minor','buyer_fee_minor','currency','display_rank','name','on_sale_now','price_minor','remaining','sale_ends_at','sale_starts_at','ticket_type_id','visibility'])
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e),
  'P15: every element carries exactly {ticket_type_id, name, price_minor, currency, visibility, display_rank, sale_starts_at, sale_ends_at, on_sale_now, remaining, buyer_fee_minor, all_in_price_minor}');
SELECT ok((SELECT bool_and((e ->> 'on_sale_now')::boolean) FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e),
  'P16: on_sale_now is true for both f2 tiers (GA open; Early bird inside its window)');
SELECT is((SELECT (count(*)::int, bool_and(NOT (e ->> 'on_sale_now')::boolean), sum((e ->> 'remaining')::int)::int)::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f8') g, jsonb_array_elements(g.ticket_types) e),
  (1, true, 60)::text,
  'P17: f8 (window opens in 10 days) — one row, its tier on_sale_now = false (162 helper), remaining 60');
SELECT is((SELECT (count(*)::int, min(g.ticket_types::text))::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f7') g), (1, '[]')::text,
  'P18: f7 (only hidden / door_only tiers) — one row with ticket_types = []');
SELECT is((SELECT (count(*)::int, bool_and(NOT (e ->> 'on_sale_now')::boolean))::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f3') g, jsonb_array_elements(g.ticket_types) e), (1, true)::text,
  'P19: a COMPLETED event stays readable (anon-visible in catalog) and its tier answers on_sale_now = false');
SELECT is((SELECT count(*)::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f9')), 1,
  'P20: a completed SESSION of an on_sale event stays readable (only cancelled is withheld)');
SELECT is((SELECT (g.session ->> 'timezone', g.session ->> 'starts_at_local', g.session ->> 'doors_at_local', g.session ->> 'ends_at_local')::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g),
  ('America/Chicago', '2026-12-04 21:00', '2026-12-04 20:00', '2026-12-05 01:00')::text,
  'P21: *_local = the instants in the room''s timezone (162 catalog.venue.timezone; 03:00Z -> 21:00 Chicago the day before)');
SELECT is((SELECT (g.event ->> 'age_restriction') FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fb') g), '21_plus',
  'P22: event.age_restriction = catalog.event.age_policy');
SELECT is((SELECT (g.event ->> 'age_restriction' IS NULL, g.event ->> 'title', g.event ->> 'status', g.venue ->> 'name', g.venue ->> 'neighborhood', g.session ->> 'session_label')::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g),
  (true, 'V1 on sale 252', 'on_sale', 'Room V1 252', 'wynwood', 'Main')::text,
  'P23: event / venue / session projections (age NULL = not specified)');
SELECT is((SELECT array_agg(e ->> 'name' ORDER BY o) FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) WITH ORDINALITY x(e, o)),
  ARRAY['Early bird','GA'], 'P24: ticket_types ordered by display_rank (Early bird rank 1 before GA rank 2)');
SELECT is((SELECT (e ->> 'price_minor', e ->> 'currency', e ->> 'visibility', e ->> 'display_rank')::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g, jsonb_array_elements(g.ticket_types) e WHERE e ->> 'name' = 'GA'),
  ('3000', 'USD', 'public', '2')::text, 'P25: GA projects price_minor 3000, currency USD, visibility public, display_rank 2');
SELECT ok((SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(g.session) k) = ARRAY['doors_at','doors_at_local','ends_at','ends_at_local','event_id','session_id','session_label','starts_at','starts_at_local','status','timezone']
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g),
  'P26: session carries exactly its eleven contracted keys');
SELECT ok((SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(g.event) k) = ARRAY['age_restriction','category','description','event_id','genre_tags','hero_image_ref','status','title']
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g),
  'P27: event carries exactly its eight contracted keys (no org_id)');
SELECT ok((SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(g.venue) k) = ARRAY['address','name','neighborhood','timezone','venue_id']
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g),
  'P28: venue carries exactly its five contracted keys (no org_id, no capacity_hint, no approval_status)');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT is((SELECT (count(*)::int, min(jsonb_array_length(g.ticket_types)))::text FROM public.get_primary_session('25200000-0000-4000-8000-0000000000f2') g), (1, 2)::text,
  'P29: an authenticated fan reads the same row and the same two tiers');
SELECT tap.logout();

-- ── Section T — get_my_ticket_atoms ──────────────────────────────────────────
SELECT ok((tap._fetch252('fin_o1')::jsonb ->> 'status') = 'ok' AND jsonb_array_length(tap._fetch252('fin_o1')::jsonb -> 'atom_ids') = 3
      AND (tap._fetch252('fin_o7')::jsonb ->> 'status') = 'ok' AND jsonb_array_length(tap._fetch252('fin_o7')::jsonb -> 'atom_ids') = 1,
  'T0: fixture — venue.finalize_primary_order minted 3 atoms for O1 and 1 for O7 through the real path (flag on, live-guarded bootstrap key)');
SELECT tap.login('25200000-0000-4000-8000-000000000101');
SELECT is((SELECT count(*)::int FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2')), 3, 'T1: B1 sees her three atoms on f2');
SELECT is((SELECT count(*)::int FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-00000000dead')), 0, 'T2: a forged session id yields 0 rows (not an error)');
SELECT is((SELECT count(*)::int FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f6')), 0, 'T3: B1 on f6 (no atoms there) yields 0 rows');
SELECT is((SELECT array_agg(a.serial_no ORDER BY a.serial_no) FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a), ARRAY[1,2,3],
  'T4: serial_no projected, the session-scoped serials 1..3, ascending');
SELECT is((SELECT array_agg(a.state ORDER BY a.serial_no) FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a), ARRAY['active','scanned','voided'],
  'T5: raw states projected truthfully (active, scanned, voided)');
SELECT is((SELECT array_agg(a.credential_version ORDER BY a.serial_no) FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a), ARRAY[0,0,1],
  'T6: credential_version projected (the voided atom was bumped to 1)');
SELECT ok((SELECT bool_and(a.ticket_type_name = 'GA' AND a.ticket_type_id = '25200000-0000-4000-8000-000000000021' AND a.resale_state = 'none' AND a.issued_at IS NOT NULL)
             FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a),
  'T7: ticket_type_id / ticket_type_name / resale_state none / issued_at projected');
SELECT tap._store252('b1_atoms', (SELECT array_agg(a.ticket_atom_id::text ORDER BY a.serial_no)::text FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a));
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000102');
SELECT is((SELECT count(*)::int FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2')), 1, 'T8: B2 sees exactly his one atom on the same session');
SELECT is((SELECT count(*)::int FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a WHERE a.ticket_atom_id::text = ANY (tap._fetch252('b1_atoms')::text[])), 0,
  'T9: B2 never sees any of B1''s atoms (owner scoping is auth.uid(), not the argument)');
SELECT is((SELECT (count(*)::int, min(a.serial_no), min(a.state), min(a.credential_version))::text FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') a), (1, 4, 'active', 0)::text,
  'T10: B2''s one atom is serial 4, active, credential_version 0');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2')), 0, 'T11: a fan with no tickets gets an empty set (success, not an error)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') $$, '42501', NULL, 'T12: anon has no EXECUTE (denied at the ACL, never served empty)');
SELECT tap.logout();
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$ SELECT * FROM public.get_my_ticket_atoms('25200000-0000-4000-8000-0000000000f2') $$, '28000', 'tickets_unauthenticated', 'T13: authenticated role with no subject -> 28000 tickets_unauthenticated');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log l WHERE l.sequence = 1 AND l.cause = 'issue' AND l.cause_ref = '25200000-0000-4000-8000-000000000401'), 3,
  'T14: the real link — three sequence-1 issue ledger rows carry cause_ref = O1''s order_item id (085:2050)');

-- ── Section O — get_my_primary_orders ────────────────────────────────────────
SELECT tap.login('25200000-0000-4000-8000-000000000101');
SELECT is((SELECT count(*)::int FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2')), 6, 'O1: B1 sees her six orders on f2 (O8 on f6 excluded)');
SELECT is((SELECT count(*)::int FROM public.get_my_primary_orders('25200000-0000-4000-8000-00000000dead')), 0, 'O2: a forged session id yields 0 rows');
SELECT is((SELECT (o.status, o.total_minor, o.currency, o.created_at::text, o.atoms_issued, o.payment_state, o.charge_total_minor)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o WHERE o.order_id = '25200000-0000-4000-8000-000000000301'),
  ('paid', 9000, 'USD', '2026-10-20 10:00:00+00'::timestamptz::text, 3, 'succeeded', 9000)::text,
  'O3: O1 (finalized) — paid, 9000 USD, atoms_issued 3, payment_state succeeded, charge_total_minor 9000 = its linked payments.total (kernel.payment_native written by finalize)');
SELECT is((SELECT (o.status, o.atoms_issued, o.payment_state, o.charge_total_minor IS NULL)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o WHERE o.order_id = '25200000-0000-4000-8000-000000000302'),
  ('pending', 0, 'none', true)::text,
  'O4: O2 pending with no payment link — atoms_issued 0, payment_state none, charge_total_minor NULL (no link exists before finalize; see the header)');
SELECT is((SELECT (o.status, o.payment_state)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o WHERE o.order_id = '25200000-0000-4000-8000-000000000303'),
  ('cancelled', 'failed')::text, 'O5: payments.failed -> failed');
SELECT is((SELECT (o.status, o.payment_state)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o WHERE o.order_id = '25200000-0000-4000-8000-000000000304'),
  ('pending', 'processing')::text, 'O6: payments.processing -> processing');
SELECT is((SELECT (o.status, o.payment_state)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o WHERE o.order_id = '25200000-0000-4000-8000-000000000305'),
  ('refunded', 'succeeded')::text, 'O7: payments.refunded -> succeeded (the ORDER status tells the refund story)');
SELECT is((SELECT (o.status, o.payment_state)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o WHERE o.order_id = '25200000-0000-4000-8000-000000000306'),
  ('pending', 'processing')::text, 'O8: payments.pending -> processing');
SELECT is((SELECT array_agg(o.order_id::text ORDER BY rn) FROM (SELECT o.order_id, row_number() OVER () rn FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o) o),
  ARRAY['25200000-0000-4000-8000-000000000306','25200000-0000-4000-8000-000000000305','25200000-0000-4000-8000-000000000304','25200000-0000-4000-8000-000000000303','25200000-0000-4000-8000-000000000302','25200000-0000-4000-8000-000000000301'],
  'O9: newest first (created_at desc)');
SELECT is((SELECT (count(*)::int, min(o.order_id::text), min(o.payment_state))::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f6') o),
  (1, '25200000-0000-4000-8000-000000000308', 'none')::text, 'O10: B1 on f6 sees only O8 (pending, no link -> none)');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000102');
SELECT is((SELECT (count(*)::int, min(o.order_id::text), min(o.status), min(o.atoms_issued), min(o.payment_state))::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') o),
  (1, '25200000-0000-4000-8000-000000000307', 'paid', 1, 'succeeded')::text,
  'O11: B2 sees only his O7 — paid, atoms_issued 1, succeeded; none of B1''s six orders');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT is((SELECT count(*)::int FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2')), 0, 'O12: a fan with no orders gets an empty set');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') $$, '42501', NULL, 'O13: anon has no EXECUTE');
SELECT tap.logout();
SELECT set_config('role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok($$ SELECT * FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000f2') $$, '28000', 'orders_unauthenticated', 'O14: authenticated role with no subject -> 28000 orders_unauthenticated');
SELECT tap.logout();
SELECT is((SELECT (count(*)::int, min(pn.amount_minor))::text FROM kernel.payment_native pn WHERE pn.order_id = '25200000-0000-4000-8000-000000000301'), (1, 9000)::text,
  'O15: fixture — finalize wrote the kernel.payment_native link for O1 (the payment_state source)');

-- ── Section F — all-in price / buyer fee against the REAL checkout (runs last) ──
-- fixture (postgres): event ec / session fc, three public tiers 2500 / 1005 / 1004, one public_sale batch
-- each, the fan's active holds (rows; batch held raised to match); the 252 org made payable (146 scaffolding).
INSERT INTO catalog.event (event_id, venue_id, org_id, title, status) VALUES
  ('25200000-0000-4000-8000-0000000000ec', '25200000-0000-4000-8000-0000000000a1', '25200000-0000-4000-8000-00000000000a', 'V1 fee 252', 'on_sale');
INSERT INTO catalog.event_session (session_id, event_id, starts_at, status) VALUES
  ('25200000-0000-4000-8000-0000000000fc', '25200000-0000-4000-8000-0000000000ec', now() + interval '40 days', 'scheduled');
INSERT INTO venue.ticket_type (ticket_type_id, event_id, kind, name, price_minor, visibility, display_rank) VALUES
  ('25200000-0000-4000-8000-000000000f01', '25200000-0000-4000-8000-0000000000ec', 'admission', 'Fee std 252',   2500, 'public', 1),
  ('25200000-0000-4000-8000-000000000f02', '25200000-0000-4000-8000-0000000000ec', 'admission', 'Fee half 252',  1005, 'public', 2),
  ('25200000-0000-4000-8000-000000000f03', '25200000-0000-4000-8000-0000000000ec', 'admission', 'Fee below 252', 1004, 'public', 3);
INSERT INTO venue.inventory_batch (batch_id, ticket_type_id, event_session_id, release_kind, capacity, held, sold) VALUES
  ('25200000-0000-4000-8000-000000000f11', '25200000-0000-4000-8000-000000000f01', '25200000-0000-4000-8000-0000000000fc', 'public_sale', 50, 1, 0),
  ('25200000-0000-4000-8000-000000000f12', '25200000-0000-4000-8000-000000000f02', '25200000-0000-4000-8000-0000000000fc', 'public_sale', 50, 3, 0),
  ('25200000-0000-4000-8000-000000000f13', '25200000-0000-4000-8000-000000000f03', '25200000-0000-4000-8000-0000000000fc', 'public_sale', 50, 1, 0);
INSERT INTO venue.inventory_hold (hold_id, batch_id, identity_id, quantity, status, expires_at, command_idempotency_key) VALUES
  ('25200000-0000-4000-8000-000000000f21', '25200000-0000-4000-8000-000000000f11', '25200000-0000-4000-8000-000000000199', 1, 'active', now() + interval '1 hour', 'hf1-252'),
  ('25200000-0000-4000-8000-000000000f22', '25200000-0000-4000-8000-000000000f12', '25200000-0000-4000-8000-000000000199', 1, 'active', now() + interval '1 hour', 'hf2-252'),
  ('25200000-0000-4000-8000-000000000f23', '25200000-0000-4000-8000-000000000f13', '25200000-0000-4000-8000-000000000199', 1, 'active', now() + interval '1 hour', 'hf3-252'),
  ('25200000-0000-4000-8000-000000000f24', '25200000-0000-4000-8000-000000000f12', '25200000-0000-4000-8000-000000000199', 2, 'active', now() + interval '1 hour', 'hf4-252');
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_252FEETEST', connect_transfers_active = true
 WHERE org_id = '25200000-0000-4000-8000-00000000000a';
-- the rate: explicitly UNSET on top (a new JSON-null version — whatever the base chain carries)
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'fee.buyer_service_bps', coalesce(max(version), 0) + 1, 'null'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'fee.buyer_service_bps';
SELECT tap.login_anon();
SELECT is((SELECT (count(*)::int, bool_and(e -> 'buyer_fee_minor' = 'null'::jsonb AND e -> 'all_in_price_minor' = 'null'::jsonb))::text
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e), (3, true)::text,
  'F1: rate UNSET (JSON null on top) — buyer_fee_minor and all_in_price_minor are null on every tier (never a default, never 0)');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT throws_ok($$ SELECT venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f01","quantity":1}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f21']::uuid[], 'ck252-fee-unset') $$,
  'P0001', 'precondition_failed: service_fee_unset — fee.buyer_service_bps has no value; selling cannot be activated until the owner sets it',
  'F2: …and in the same state create_primary_checkout refuses service_fee_unset (null display = no quote)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'fee.buyer_service_bps', max(version) + 1, '10001'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'fee.buyer_service_bps';
SELECT tap.login_anon();
SELECT is((SELECT (count(*)::int, bool_and(e -> 'buyer_fee_minor' = 'null'::jsonb AND e -> 'all_in_price_minor' = 'null'::jsonb))::text
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e), (3, true)::text,
  'F3: rate 10001 (out of range) — both null on every tier');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT throws_ok($$ SELECT venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f01","quantity":1}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f21']::uuid[], 'ck252-fee-oor') $$,
  'P0001', 'precondition_failed: service_fee_out_of_range — fee.buyer_service_bps must be an integer 0..10000, got 10001',
  'F4: …and checkout refuses service_fee_out_of_range on the same value');
SELECT tap.logout();
-- the rate SET: 1000 bps (10%) as the next version
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'fee.buyer_service_bps', max(version) + 1, '1000'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'fee.buyer_service_bps';
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT tap._store252('chk_f01', venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f01","quantity":1}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f21']::uuid[], 'ck252-fee-f01')::text);
SELECT tap._store252('chk_f02', venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f02","quantity":1}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f22']::uuid[], 'ck252-fee-f02')::text);
SELECT tap._store252('chk_f03', venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f03","quantity":1}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f23']::uuid[], 'ck252-fee-f03')::text);
SELECT tap._store252('chk_f02x2', venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f02","quantity":2}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f24']::uuid[], 'ck252-fee-f02x2')::text);
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', (j ->> 'total_minor')::int, (j ->> 'buyer_fee_minor')::int, (j ->> 'charge_total_minor')::int)::text FROM (SELECT tap._fetch252('chk_f01')::jsonb j) x),
  ('ok', 2500, 250, 2750)::text,
  'F5: the real checkout at 1000 bps for ONE unit of the 2500 tier (as the fan, with her hold) — status ok, total_minor 2500 = face, buyer_fee_minor 250, charge_total_minor 2750');
SELECT tap.login_anon();
SELECT is((SELECT (e ->> 'all_in_price_minor')::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e
            WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000f01'),
          (tap._fetch252('chk_f01')::jsonb ->> 'charge_total_minor')::int,
  'F6: all_in_price_minor of the 2500 tier = what create_primary_checkout actually charged for quantity 1 (charge_total_minor, same clone, same transaction)');
SELECT is((SELECT ((e ->> 'buyer_fee_minor')::int, (e ->> 'all_in_price_minor')::int - (e ->> 'price_minor')::int)::text
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e
            WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000f01'),
          ((tap._fetch252('chk_f01')::jsonb ->> 'buyer_fee_minor')::int, (tap._fetch252('chk_f01')::jsonb ->> 'buyer_fee_minor')::int)::text,
  'F7: buyer_fee_minor = checkout''s buyer_fee_minor = all_in_price_minor - price_minor');
SELECT tap.logout();
SELECT is((SELECT (j ->> 'status', (j ->> 'buyer_fee_minor')::int, (j ->> 'charge_total_minor')::int)::text FROM (SELECT tap._fetch252('chk_f02')::jsonb j) x),
  ('ok', 101, 1106)::text,
  'F8: the real checkout for ONE unit of the 1005 tier — 1005 x 1000 / 10000 = 100.5 is charged as 101 (half-up), total 1106');
SELECT tap.login_anon();
SELECT is((SELECT ((e ->> 'buyer_fee_minor')::int, (e ->> 'all_in_price_minor')::int)::text
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e
            WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000f02'),
          (101, 1106)::text,
  'F9: the .5-cent boundary — the read shows (101, 1106), half-up exactly as checkout charged (half-even or truncation would show 100 / 1105)');
SELECT is((SELECT ((e ->> 'buyer_fee_minor')::int, (e ->> 'all_in_price_minor')::int)::text
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e
            WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000f03'),
          ((tap._fetch252('chk_f03')::jsonb ->> 'buyer_fee_minor')::int, (tap._fetch252('chk_f03')::jsonb ->> 'charge_total_minor')::int)::text,
  'F10: the 1004 tier — (buyer_fee_minor, all_in_price_minor) = checkout''s (buyer_fee_minor, charge_total_minor) for quantity 1');
SELECT tap.logout();
SELECT is((SELECT ((j ->> 'buyer_fee_minor')::int, (j ->> 'charge_total_minor')::int)::text FROM (SELECT tap._fetch252('chk_f03')::jsonb j) x),
  (100, 1104)::text,
  'F11: …and that is (100, 1104): 100.4 rounds DOWN — round(), not ceil()');
SELECT is((SELECT ((j ->> 'charge_total_minor')::int, 2 * (SELECT (e ->> 'all_in_price_minor')::int FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e
                                                            WHERE e ->> 'ticket_type_id' = '25200000-0000-4000-8000-000000000f02'))::text
             FROM (SELECT tap._fetch252('chk_f02x2')::jsonb j) x),
  (2211, 2212)::text,
  'F12: TWO units of the 1005 tier — checkout charges 2010 + round(201.0) = 2211, not 2 x 1106 = 2212: the fee is rounded per ORDER, so all_in_price_minor is a quantity-1 figure only');
-- charge_total_minor on the order read, end to end: the payments row EXACTLY as the primary-checkout edge writes it
-- from the RPC's return (index.ts:1196-1210: amount = total_minor face, buyer_fee = buyer_fee_minor, total =
-- charge_total_minor), moved to succeeded as the webhook would, then the real finalize (as postgres, the 252 O1 path).
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
SELECT '25200000-0000-4000-8000-000000000f31', NULL, '25200000-0000-4000-8000-000000000199', NULL,
       (j ->> 'total_minor')::int, (j ->> 'buyer_fee_minor')::int, 0, (j ->> 'charge_total_minor')::int, 'pi_252_fee_f01', 'succeeded', 'native_primary', now()
  FROM (SELECT tap._fetch252('chk_f01')::jsonb j) x;
SELECT tap._store252('fin_f01', venue.finalize_primary_order((tap._fetch252('chk_f01')::jsonb ->> 'order_id')::uuid, '25200000-0000-4000-8000-000000000f31', 'ck252-fin-f01', NULL)::text);
SELECT is((SELECT (j ->> 'status', jsonb_array_length(j -> 'atom_ids'))::text FROM (SELECT tap._fetch252('fin_f01')::jsonb j) x), ('ok', 1)::text,
  'F13: fixture — the fan''s one-unit 2500 order finalized through the real path against the edge-shaped payments row (one atom minted)');
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT is((SELECT (o.status, o.total_minor, o.charge_total_minor, o.payment_state)::text FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000fc') o
            WHERE o.order_id = (tap._fetch252('chk_f01')::jsonb ->> 'order_id')::uuid),
          ('paid', 2500, (tap._fetch252('chk_f01')::jsonb ->> 'charge_total_minor')::int, 'succeeded')::text,
  'F14: the finalized order reads total_minor 2500 (face) and charge_total_minor = what create_primary_checkout quoted and the payments row charged (2750)');
SELECT is((SELECT (count(*)::int, bool_and(o.status = 'pending' AND o.charge_total_minor IS NULL AND o.payment_state = 'none'))::text
             FROM public.get_my_primary_orders('25200000-0000-4000-8000-0000000000fc') o
            WHERE o.order_id <> (tap._fetch252('chk_f01')::jsonb ->> 'order_id')::uuid), (3, true)::text,
  'F15: the fan''s three PENDING orders read charge_total_minor NULL (no payment linked) — never recomputed from the current 1000 bps rate');
SELECT tap.logout();

-- LAST, deliberately: a non-numeric value stays in the append-only history for the rest of the transaction, and
-- create_primary_checkout casts EVERY historical row of the key before its ORDER BY / LIMIT on a seq-scan plan
-- (EVIDENCE-182b: checkout_cast_plan_dependence.txt) — any checkout after this point could raise 22P02 even under
-- a valid top version. 182's read casts only the top row, so it is unaffected.
INSERT INTO catalog.platform_config (key, version, value, visibility)
SELECT 'fee.buyer_service_bps', max(version) + 1, '"ten percent"'::jsonb, 'restricted' FROM catalog.platform_config WHERE key = 'fee.buyer_service_bps';
SELECT tap.login_anon();
SELECT is((SELECT (count(*)::int, bool_and(e -> 'buyer_fee_minor' = 'null'::jsonb AND e -> 'all_in_price_minor' = 'null'::jsonb))::text
             FROM public.get_primary_session('25200000-0000-4000-8000-0000000000fc') g, jsonb_array_elements(g.ticket_types) e), (3, true)::text,
  'F16: a non-numeric rate ("ten percent") — both null and the detail read does NOT raise');
SELECT tap.logout();
SELECT tap.login('25200000-0000-4000-8000-000000000199');
SELECT throws_ok($$ SELECT venue.create_primary_checkout('25200000-0000-4000-8000-0000000000fc', '[{"ticket_type_id":"25200000-0000-4000-8000-000000000f01","quantity":1}]'::jsonb, ARRAY['25200000-0000-4000-8000-000000000f21']::uuid[], 'ck252-fee-nan') $$,
  '22P02', NULL,
  'F17: …while checkout''s ::numeric cast raises 22P02 on it (it refuses to quote either way)');
SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
