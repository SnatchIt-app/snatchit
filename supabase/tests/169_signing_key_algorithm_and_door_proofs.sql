-- ============================================================================
-- 169_signing_key_algorithm_and_door_proofs.sql — package 103 suite (PFA-PT-8)
-- + DB-side proofs for the old-owner screenshot currency mechanism, pinned-key
-- rotation and double-scan first-in-wins.
--
-- Frozen sources: 103_signing_key_algorithm_pin.sql (algorithm column, guard,
-- grant, kernel.get_ticket_signing_context re-create) · 083:47-125 (signing_key
-- DDL/guard/grant, unchanged except algorithm) · 088:609-742
-- (kernel.transfer_ticket_ownership — the sole custody-move engine) ·
-- 086:1070-1128 (venue.record_scan / venue.validate_ticket_online) ·
-- 079:408-447 (kernel.mark_ticket_scanned — the single-writer scan choke
-- point) · 086:141-143 (scan_admitted_in_uq — C41 first-in-wins). Convention:
-- BEGIN … plan(N) … finish() … ROLLBACK.
--
-- WHAT THIS FILE PROVES, section by section:
--   A — migration 103's schema/authority surface: the algorithm column
--       itself, its immutability, its column grant, and that
--       get_ticket_signing_context returns the REAL pinned algorithm.
--   B — the old-owner screenshot currency mechanism (DB half): a transfer
--       bumps credential_version by exactly one and the old owner loses
--       signing access entirely — the fact that makes a screenshotted old
--       credential detectably stale is sourced HERE, in kernel.tickets.
--   C — pinned-key rotation: a minted atom's signing_key_id is FROZEN at
--       mint time and is never silently re-resolved to the scope's current
--       active key, even across a rotation and even after the pinned key is
--       later revoked.
--   D — double-scan first-in-wins: the sequential (single-connection) proof
--       that a second scan of an already-scanned atom never produces a
--       second 'admitted' row, plus the structural proof of the partial
--       unique index that is the actual concurrency guarantee (a true
--       concurrent race needs two connections, which pgTAP cannot drive).
--
-- Non-regression: 166 (G4), 167 (G5) and 168 (A8a') are NOT re-asserted here
-- (this file owns none of their objects) — they are confirmed green by the
-- full-suite run alongside this file; see docs/phase2/_impl/KDBPROOFS.md.
-- ============================================================================
BEGIN;
SELECT plan(34);

SELECT tap.seed_core();

CREATE TABLE tap.memo_169 (k text PRIMARY KEY, v text);
-- RETURNS void (not text): a bare `SELECT tap._store169(...)` must emit
-- NOTHING to stdout, or a stored value like 'ok' prints a phantom line
-- pg_prove could misparse (150's rule; belt-and-braces here too).
CREATE FUNCTION tap._store169(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_169 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch169(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_169 WHERE k=$1 $m$;

-- flip the two feature flags this file needs ON, once, up front (078 seeds
-- both false). Both are 'public' per the 078 seed row.
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_scanning_enabled', 2, 'true'::jsonb, 'public');

-- ============================================================================
-- FIXTURE — one org -> one venue (seller granted venue_manager) shared by
-- every section; each section gets its OWN event/session/ticket_type/batch
-- (signing_key's one-active-per-event-scope unique index means independent
-- sections need independent event scopes to mint/rotate without colliding).
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store169('org', (kernel.create_organization('P103 Co','P103 Co','ck169-o-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved' WHERE org_id = tap._fetch169('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store169('venue', (catalog.create_venue(tap._fetch169('org')::uuid,'P103 Hall','wynwood',NULL,'ck169-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch169('venue')::uuid,'approved','p103_gate','ck169-a-1');
SELECT tap.logout();
-- the seller is also this venue's venue_manager (needed by validate_ticket_online,
-- record_scan and register_scan_device in sections B/D below).
INSERT INTO venue.staff_role (venue_id, identity_id, role, granted_by)
VALUES (tap._fetch169('venue')::uuid, tap.seller(), 'venue_manager', tap.admin_user()) ON CONFLICT DO NOTHING;

-- a tiny helper: org -> event -> session -> ticket_type -> comp batch, under
-- the shared venue, given a distinguishing label for the command keys/names.
CREATE FUNCTION tap._mkevent169(p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.login(tap.seller());
  PERFORM tap._store169(p_label || '_event', (catalog.create_event(tap._fetch169('venue')::uuid, 'P103 ' || p_label,
    jsonb_build_object('starts_at',(now()+interval '20 days')::text,'ends_at',(now()+interval '20 days 5 hours')::text),
    'ck169-e-' || p_label) ->> 'event_id'));
  PERFORM tap._store169(p_label || '_session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch169(p_label || '_event')::uuid));
  PERFORM tap._store169(p_label || '_tt', (venue.create_ticket_type(tap._fetch169(p_label || '_event')::uuid,'admission','GA',5000,'public','ck169-tt-' || p_label) ->> 'ticket_type_id'));
  PERFORM tap._store169(p_label || '_batch', (venue.create_inventory_batch(tap._fetch169(p_label || '_tt')::uuid, tap._fetch169(p_label || '_session')::uuid, 'comp', 100, 0, 'ck169-b-' || p_label) ->> 'batch_id'));
  PERFORM tap.logout();
END $$;

SELECT tap._mkevent169('a');   -- section A: default-algorithm round trip
SELECT tap._mkevent169('a2');  -- section A: explicit ES256 round trip
SELECT tap._mkevent169('b');   -- section B: old-owner currency
SELECT tap._mkevent169('c');   -- section C: rotation
SELECT tap._mkevent169('d');   -- section D: double-scan

-- ============================================================================
-- SECTION A — migration 103: the algorithm column, its immutability/grant,
-- and get_ticket_signing_context returning the REAL pinned algorithm.
-- ============================================================================
SELECT has_column('kernel'::name,'signing_key'::name,'algorithm'::name, 'A1: kernel.signing_key.algorithm exists (103)');
SELECT col_not_null('kernel'::name,'signing_key'::name,'algorithm'::name, 'A2: algorithm is NOT NULL');
SELECT col_default_is('kernel'::name,'signing_key'::name,'algorithm'::name, 'EdDSA', 'A3: default is EdDSA (§5.1-preferred; the ceremony sets ES256 explicitly when needed)');
SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'kernel.signing_key'::regclass AND conname = 'signing_key_algorithm_check'),
  $ck$CHECK ((algorithm = ANY (ARRAY['EdDSA'::text, 'ES256'::text])))$ck$,
  'A4: the CHECK enumerates EXACTLY EdDSA|ES256 — no RSA, no symmetric name, no none');

-- GRANT: algorithm joins the distributable projection; kms_handle_ref never does.
SELECT ok(has_column_privilege('authenticated','kernel.signing_key','algorithm','SELECT'),
  'A5: authenticated reads algorithm (103 grant — a door pins it from the M1 manifest projection)');
SELECT ok(NOT has_column_privilege('authenticated','kernel.signing_key','kms_handle_ref','SELECT'),
  'A6: authenticated still has NO SELECT on kms_handle_ref (103 does not touch that fence)');

-- IMMUTABLE: algorithm joins public_key/kms_handle_ref/scope/target/not_before
-- in the 103-recreated guard_signing_key_immutable body.
WITH insp AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch169('a_event')::uuid, 'PUBKEY-169-PROBE', 'kms-169-probe', 'active', now())
  RETURNING key_id
)
SELECT tap._store169('probe_key', (SELECT key_id::text FROM insp));
SELECT throws_ok(format($$UPDATE kernel.signing_key SET algorithm='ES256' WHERE key_id=%L$$, tap._fetch169('probe_key')),
  'P0001', NULL, 'A7: algorithm is immutable after creation — an UPDATE raises append_only via the 103-recreated guard');

-- forward-only status STILL holds post-103 (the guard's status clause is
-- byte-identical to 083; re-verify it survived the body-only re-create).
SELECT lives_ok(format($$UPDATE kernel.signing_key SET status='revoked' WHERE key_id=%L$$, tap._fetch169('probe_key')),
  'A8: active -> revoked is a legal forward transition (guard unaffected by 103)');
SELECT throws_ok(format($$UPDATE kernel.signing_key SET status='active' WHERE key_id=%L$$, tap._fetch169('probe_key')),
  'P0001', NULL, 'A9: revoked is STILL terminal — a revoked key can never be re-activated (guard unaffected by 103)');

-- the round trip: get_ticket_signing_context returns the PINNED key's real
-- algorithm, not a literal null (102's gap) and not a hardcoded constant.
WITH insa AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch169('a_event')::uuid, 'PUBKEY-169-A', 'kms-169-a', 'active', now())
  RETURNING key_id
)
SELECT tap._store169('a_key', (SELECT key_id::text FROM insa));
-- issue_ticket_atoms is MACHINE-ONLY (083's v_svc grant; 093's re-create keeps
-- the frozen ACL) — called at ambient/service level, no tap.login active.
SELECT tap._store169('a_atom', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch169('a_session')::uuid, 'org_id', tap._fetch169('org')::uuid,
    'ticket_type_id', tap._fetch169('a_tt')::uuid, 'batch_id', tap._fetch169('a_batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch169('a_key')::uuid), 'ck169-m-a') -> 'atom_ids' ->> 0));
SELECT tap.login(tap.buyer());
SELECT is((kernel.get_ticket_signing_context(tap._fetch169('a_atom')::uuid) ->> 'algorithm'), 'EdDSA',
  'A10: the DEFAULT-algorithm key round-trips EdDSA through get_ticket_signing_context');
SELECT tap.logout();

WITH insa2 AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch169('a2_event')::uuid, 'PUBKEY-169-A2', 'kms-169-a2', 'active', now(), 'ES256')
  RETURNING key_id
)
SELECT tap._store169('a2_key', (SELECT key_id::text FROM insa2));
SELECT tap._store169('a2_atom', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch169('a2_session')::uuid, 'org_id', tap._fetch169('org')::uuid,
    'ticket_type_id', tap._fetch169('a2_tt')::uuid, 'batch_id', tap._fetch169('a2_batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch169('a2_key')::uuid), 'ck169-m-a2') -> 'atom_ids' ->> 0));
SELECT tap.login(tap.buyer());
-- A11 (kept as the file's last A-section id, see below) is the EXPLICIT-ES256
-- round trip the brief calls for explicitly.
SELECT is((kernel.get_ticket_signing_context(tap._fetch169('a2_atom')::uuid) ->> 'algorithm'), 'ES256',
  'A11: a key explicitly provisioned with algorithm=ES256 round-trips ES256, never silently coerced to the default');
SELECT tap.logout();

-- ============================================================================
-- SECTION B — the old-owner screenshot currency mechanism (DB half). The
-- offline vitest proves a stale-version credential is rejected client-side;
-- THIS proves the DB fact that makes it stale: transfer bumps
-- credential_version by exactly one and the old owner loses signing access.
-- ============================================================================
WITH insb AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch169('b_event')::uuid, 'PUBKEY-169-B', 'kms-169-b', 'active', now())
  RETURNING key_id
)
SELECT tap._store169('b_key', (SELECT key_id::text FROM insb));
SELECT tap._store169('b_atom', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch169('b_session')::uuid, 'org_id', tap._fetch169('org')::uuid,
    'ticket_type_id', tap._fetch169('b_tt')::uuid, 'batch_id', tap._fetch169('b_batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch169('b_key')::uuid), 'ck169-m-b') -> 'atom_ids' ->> 0));
-- validate_ticket_online (the C37 live read) is a venue-staff surface (seller
-- holds venue_manager on this venue).
SELECT tap.login(tap.seller());
SELECT tap._store169('b_ctx0', (venue.validate_ticket_online(tap._fetch169('b_atom')::uuid, tap._fetch169('b_session')::uuid))::text);
SELECT tap.logout();
SELECT is((tap._fetch169('b_ctx0')::jsonb ->> 'credential_version'), '0', 'B1: freshly minted, credential_version=0 (owner A = buyer)');

-- A -> B custody move (admin_action: resale_state='none' is the sanctioned
-- overlay for it). Called with NO login active (ambient trusted/service path,
-- matching kernel.transfer_ticket_ownership's service_role-only grant).
SELECT tap._store169('b_cref', gen_random_uuid()::text);
SELECT tap._store169('b_xfer', (kernel.transfer_ticket_ownership(
    tap._fetch169('b_atom')::uuid, tap.other_user(), 'admin_action', tap._fetch169('b_cref')::uuid, NULL, 'ck169-tr-b1'))::text);
SELECT is((tap._fetch169('b_xfer')::jsonb ->> 'status'), 'ok', 'B2: the A->B custody move executes');
SELECT ok((SELECT t.current_owner_id = tap.other_user() AND t.credential_version = 1 AND t.resale_state = 'none'
             FROM kernel.tickets t WHERE t.ticket_atom_id = tap._fetch169('b_atom')::uuid),
  'B3: the head now reads owner=B, credential_version incremented by EXACTLY one (0->1), resale_state=none');

SELECT tap.login(tap.seller());
SELECT tap._store169('b_ctx1', (venue.validate_ticket_online(tap._fetch169('b_atom')::uuid, tap._fetch169('b_session')::uuid))::text);
SELECT tap.logout();
SELECT is((tap._fetch169('b_ctx1')::jsonb ->> 'credential_version'), '1', 'B4: validate_ticket_online now returns the NEW version (1)');
SELECT isnt((tap._fetch169('b_ctx0')::jsonb ->> 'credential_version'), (tap._fetch169('b_ctx1')::jsonb ->> 'credential_version'),
  'B5: OLD version != NEW version — the DB-side currency source that makes a screenshotted old token stale');

-- owner A (buyer) can no longer get a signing context; owner B (other_user) can.
SELECT tap.login(tap.buyer());
SELECT is((kernel.get_ticket_signing_context(tap._fetch169('b_atom')::uuid) ->> 'code'), 'not_owner',
  'B6: the OLD owner A is refused not_owner — no signing context for a stale-owned atom');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT tap._store169('b_ctxB', (kernel.get_ticket_signing_context(tap._fetch169('b_atom')::uuid))::text);
SELECT tap.logout();
SELECT is((tap._fetch169('b_ctxB')::jsonb ->> 'status'), 'ok', 'B7: the NEW owner B gets a signing context');
SELECT is((tap._fetch169('b_ctxB')::jsonb ->> 'credential_version'), '1', 'B8: …carrying the NEW credential_version (1)');

-- ============================================================================
-- SECTION C — pinned-key rotation: a mint's signing_key_id is FROZEN, never
-- re-resolved to the scope's current active key, even across rotation and
-- even after the pinned key is later revoked.
-- ============================================================================
WITH insk1 AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch169('c_event')::uuid, 'PUBKEY-169-K1', 'kms-169-k1', 'active', now(), 'ES256')
  RETURNING key_id
)
SELECT tap._store169('c_k1', (SELECT key_id::text FROM insk1));
SELECT tap._store169('c_t1', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch169('c_session')::uuid, 'org_id', tap._fetch169('org')::uuid,
    'ticket_type_id', tap._fetch169('c_tt')::uuid, 'batch_id', tap._fetch169('c_batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch169('c_k1')::uuid), 'ck169-m-c1') -> 'atom_ids' ->> 0));

-- baseline, BEFORE any rotation: T1's context is ok and pinned to K1.
SELECT tap.login(tap.buyer());
SELECT ok((SELECT (kernel.get_ticket_signing_context(tap._fetch169('c_t1')::uuid) ->> 'status') = 'ok'
       AND (kernel.get_ticket_signing_context(tap._fetch169('c_t1')::uuid) ->> 'key_id') = tap._fetch169('c_k1')),
  'C1: BEFORE rotation, get_ticket_signing_context(T1) is ok and pinned to K1');
SELECT tap.logout();

-- rotate: K1 -> rotating (frees the one-active-per-event slot), THEN K2 active
-- for the SAME event — sequential statements inside this one BEGIN…ROLLBACK
-- transaction, so the partial unique index sees K1 already non-active by the
-- time K2 is inserted (no CTE trick needed; ordinary read-your-own-writes).
SELECT lives_ok(format($$UPDATE kernel.signing_key SET status='rotating' WHERE key_id=%L$$, tap._fetch169('c_k1')),
  'C2: K1 active -> rotating (frees the one-active-per-event-scope slot)');
WITH insk2 AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  VALUES ('per_event', tap._fetch169('c_event')::uuid, 'PUBKEY-169-K2', 'kms-169-k2', 'active', now(), 'EdDSA')
  RETURNING key_id
)
SELECT tap._store169('c_k2', (SELECT key_id::text FROM insk2));
SELECT ok(tap._fetch169('c_k2') IS NOT NULL, 'C3: K2 inserts ACTIVE for the same event — the rotation succeeded (one-active-per-scope respected)');

SELECT tap._store169('c_t2', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch169('c_session')::uuid, 'org_id', tap._fetch169('org')::uuid,
    'ticket_type_id', tap._fetch169('c_tt')::uuid, 'batch_id', tap._fetch169('c_batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch169('c_k2')::uuid), 'ck169-m-c2') -> 'atom_ids' ->> 0));

SELECT is((SELECT signing_key_id::text FROM kernel.tickets WHERE ticket_atom_id = tap._fetch169('c_t1')::uuid), tap._fetch169('c_k1'),
  'C4: T1.signing_key_id is STILL K1 — never re-pinned by the rotation');
SELECT is((SELECT signing_key_id::text FROM kernel.tickets WHERE ticket_atom_id = tap._fetch169('c_t2')::uuid), tap._fetch169('c_k2'),
  'C5: T2.signing_key_id is K2 — the NEW mint pins the NEW active key');

-- the ACTUAL "never a fresh scope lookup" proof: with K1 pinned-but-no-longer-
-- active, T1 is refused outright — NOT silently handed K2's material. A
-- resolver that fell back to "the scope's current active key" would instead
-- return status=ok/key_id=K2 here, which is exactly the bug this RPC must not
-- have (086:1121-ish precedent, 168 A21/A22: a rotating pinned key refuses).
SELECT tap.login(tap.buyer());
SELECT is((kernel.get_ticket_signing_context(tap._fetch169('c_t1')::uuid) ->> 'code'), 'signing_key_unavailable',
  'C6: AFTER rotation, T1''s owner is refused signing_key_unavailable — K1 is pinned but no longer active, and it is NEVER silently re-resolved to K2');
SELECT is((kernel.get_ticket_signing_context(tap._fetch169('c_t2')::uuid) ->> 'key_id'), tap._fetch169('c_k2'),
  'C7: get_ticket_signing_context(T2) returns key_id=K2 — its own pinned (and still active) key, unaffected by T1''s state');
SELECT tap.logout();

-- revoke K1. A revoked pinned key stays refused for T1 — this is a
-- signer-lifecycle fact, not a verify-trust one: verification trust for an
-- ALREADY-issued credential lives in the M1 manifest, not this RPC.
SELECT lives_ok(format($$UPDATE kernel.signing_key SET status='revoked' WHERE key_id=%L$$, tap._fetch169('c_k1')),
  'C8: K1 rotating -> revoked is a legal forward transition');
SELECT tap.login(tap.buyer());
SELECT ok((SELECT (kernel.get_ticket_signing_context(tap._fetch169('c_t1')::uuid) ->> 'code') = 'signing_key_unavailable'
       AND (kernel.get_ticket_signing_context(tap._fetch169('c_t2')::uuid) ->> 'status') = 'ok'),
  'C9: post-revoke, T1 stays refused signing_key_unavailable while T2 is wholly UNAFFECTED — K1''s revocation never touches K2');
SELECT tap.logout();

-- ============================================================================
-- SECTION D — double-scan first-in-wins (C41): the sequential proof that a
-- repeat scan is never a second admit, plus the structural constraint that
-- IS the concurrency guarantee (a true race needs two live connections,
-- which single-connection pgTAP cannot drive — documented, not simulated).
-- ============================================================================
SELECT ok((SELECT i.indisunique AND pg_get_indexdef(i.indexrelid) LIKE '%(ticket_atom_id, event_session_id)%'
                  AND pg_get_indexdef(i.indexrelid) LIKE '%result = ''admitted''%'
                  AND pg_get_indexdef(i.indexrelid) LIKE '%direction = ''in''%'
             FROM pg_index i JOIN pg_class c ON c.oid=i.indexrelid
             JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='venue' AND c.relname='scan_admitted_in_uq'),
  'D1: scan_admitted_in_uq IS UNIQUE on (ticket_atom_id, event_session_id) WHERE admitted+in — THE concurrency guarantee (first-in-wins under ANY interleaving, not just the sequential case below)');

WITH insd AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch169('d_event')::uuid, 'PUBKEY-169-D', 'kms-169-d', 'active', now())
  RETURNING key_id
)
SELECT tap._store169('d_key', (SELECT key_id::text FROM insd));
SELECT tap._store169('d_atom', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch169('d_session')::uuid, 'org_id', tap._fetch169('org')::uuid,
    'ticket_type_id', tap._fetch169('d_tt')::uuid, 'batch_id', tap._fetch169('d_batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch169('d_key')::uuid), 'ck169-m-d') -> 'atom_ids' ->> 0));
SELECT tap.login(tap.seller());
SELECT tap._store169('d_dev', (venue.register_scan_device(tap._fetch169('venue')::uuid, 'scanner-169', 'ck169-dev-1') ->> 'device_id'));

SELECT tap._store169('d_s1', (venue.record_scan(tap._fetch169('d_atom')::uuid, tap._fetch169('d_session')::uuid, tap._fetch169('d_dev')::uuid, '{}'::jsonb, 'ck169-sc-1'))::text);
SELECT is((tap._fetch169('d_s1')::jsonb ->> 'result'), 'admitted', 'D2: the FIRST scan admits');

-- the SECOND scan of the SAME atom/session: mark_ticket_scanned refuses
-- not_active (state is now 'scanned', not 'active') BEFORE the unique index
-- is ever reached — record_scan maps that refusal to result='invalid'. A
-- TRUE race (two txns both reading state='active' before either commits)
-- would instead hit the unique_violation arm and map to 'duplicate'; either
-- way the invariant below (exactly one admitted row) holds.
SELECT tap._store169('d_s2', (venue.record_scan(tap._fetch169('d_atom')::uuid, tap._fetch169('d_session')::uuid, tap._fetch169('d_dev')::uuid, '{}'::jsonb, 'ck169-sc-2'))::text);
SELECT is((tap._fetch169('d_s2')::jsonb ->> 'result'), 'invalid',
  'D3: the SECOND (sequential) scan is NOT a second admit — mark_ticket_scanned refuses not_active, mapped to result=invalid');
SELECT tap.logout();

SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id = tap._fetch169('d_atom')::uuid
             AND event_session_id = tap._fetch169('d_session')::uuid AND result='admitted' AND direction='in'), 1,
  'D4: exactly ONE admitted/in scan row for this (atom,session) — first-in-wins holds');
SELECT is((SELECT count(*)::int FROM venue.scan WHERE ticket_atom_id = tap._fetch169('d_atom')::uuid
             AND event_session_id = tap._fetch169('d_session')::uuid), 2,
  'D5: two scan rows total (admitted + invalid) — the repeat scan appended a row, it was never silently dropped');
SELECT is((SELECT state FROM kernel.tickets WHERE ticket_atom_id = tap._fetch169('d_atom')::uuid), 'scanned',
  'D6: the atom''s lifecycle state moved exactly once (scanned), unaffected by the refused repeat');

SELECT * FROM finish();
ROLLBACK;
