-- ============================================================================
-- 168_credential_signing_context_and_saleable.sql — package 102 suite.
--
-- Frozen sources: DESIGN_102 §1 (orchestrator design) · EDGE_FUNCTION_SPEC
-- §3.2/§5 (credential-sign contract, C33) · 081:899 (catalog.publish_event) ·
-- 093:3960-4110 (venue.create_primary_checkout's G2/G2b/A5 static ladder,
-- mirrored not duplicated) · 093:6544 (catalog.set_platform_config, v_dual) ·
-- 099:75-77 (signing.% config keys). Owner direction A8a' (2026-09-03) and
-- owner §21 (signing trust-root dual control), both 2026-09-03. Convention:
-- BEGIN … plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(49);

SELECT tap.seed_core();

CREATE TABLE tap.memo_168 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store168(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_168 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch168(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_168 WHERE k = $1 $m$;

-- ============================================================================
-- SECTION A — kernel.get_ticket_signing_context
-- ============================================================================
SELECT has_function('kernel'::name, 'get_ticket_signing_context'::name, ARRAY['uuid']::name[],
  'A0: kernel.get_ticket_signing_context(uuid) is authored');
SELECT ok(has_function_privilege('authenticated', 'kernel.get_ticket_signing_context(uuid)', 'EXECUTE'),
  'A0a: authenticated may EXECUTE');
SELECT ok(NOT has_function_privilege('anon', 'kernel.get_ticket_signing_context(uuid)', 'EXECUTE'),
  'A0b: anon has NO EXECUTE (revoked)');

-- ---- fixture: org -> venue -> event -> session -> ticket_type -> batch -----
SELECT tap.login(tap.seller());
SELECT tap._store168('org', (kernel.create_organization('SC Co','SC Co','ck168-o-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved' WHERE org_id = tap._fetch168('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store168('venue', (catalog.create_venue(tap._fetch168('org')::uuid,'SC Hall','wynwood',NULL,'ck168-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch168('venue')::uuid,'approved','sc_gate','ck168-a-1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store168('event', (catalog.create_event(tap._fetch168('venue')::uuid,'SC Night',
  jsonb_build_object('starts_at',(now()+interval '20 days')::text,'ends_at',(now()+interval '20 days 5 hours')::text),'ck168-e-1') ->> 'event_id'));
SELECT tap._store168('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch168('event')::uuid));
SELECT tap._store168('tt', (venue.create_ticket_type(tap._fetch168('event')::uuid,'admission','GA',5000,'public','ck168-tt-1') ->> 'ticket_type_id'));
SELECT tap._store168('batch', (venue.create_inventory_batch(tap._fetch168('tt')::uuid, tap._fetch168('session')::uuid, 'comp', 100, 0, 'ck168-b-1') ->> 'batch_id'));
SELECT tap.logout();

WITH insk AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch168('event')::uuid, 'PUBKEY-168', 'kms-handle-168', 'active', now())
  RETURNING key_id
)
SELECT tap._store168('key', (SELECT key_id::text FROM insk));

-- mint one atom, owned by the buyer, pinned to the key above.
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
SELECT tap._store168('atom', (kernel.issue_ticket_atoms(jsonb_build_object(
    'session_id', tap._fetch168('session')::uuid, 'org_id', tap._fetch168('org')::uuid,
    'ticket_type_id', tap._fetch168('tt')::uuid, 'batch_id', tap._fetch168('batch')::uuid,
    'owner_id', tap.buyer(), 'quantity', 1, 'cause', 'comp', 'cause_ref', gen_random_uuid(),
    'signing_key_id', tap._fetch168('key')::uuid), 'ck168-m-1') -> 'atom_ids' ->> 0));

-- ---- A1: owner reads the context: 'ok', every documented key present ------
SELECT tap.login(tap.buyer());
SELECT tap._store168('ctx1', (kernel.get_ticket_signing_context(tap._fetch168('atom')::uuid))::text);
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'status'), 'ok', 'A1: the owner gets status=ok');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'ticket_atom_id'), tap._fetch168('atom'), 'A2: ticket_atom_id echoes the atom');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'session_id'), tap._fetch168('session'), 'A3: session_id = event_session_id');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'credential_version'), '0', 'A4: credential_version = 0 (freshly minted)');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'key_id'), tap._fetch168('key'), 'A5: key_id = the pinned signing_key_id');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'kms_handle_ref'), 'kms-handle-168', 'A6: kms_handle_ref is the KMS handle (never key material — C33)');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'public_key'), 'PUBKEY-168', 'A7: public_key is the verify key');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'domain'), 'SNATCHIT-TICKET-CRED-V1', 'A8: domain is the frozen constant');
SELECT is((tap._fetch168('ctx1')::jsonb ->> 'ttl_seconds'), '14400', 'A9: ttl_seconds = 14400 (credential.app_ttl_interval = "4 hours")');
SELECT ok((tap._fetch168('ctx1')::jsonb ->> 'issued_at') IS NOT NULL AND (tap._fetch168('ctx1')::jsonb ->> 'exp') IS NOT NULL,
  'A10: issued_at and exp are both present');
SELECT ok(((tap._fetch168('ctx1')::jsonb ->> 'exp')::timestamptz - (tap._fetch168('ctx1')::jsonb ->> 'issued_at')::timestamptz) = interval '4 hours',
  'A11: exp - issued_at = the TTL, exactly');
SELECT is((SELECT count(*)::int FROM kernel.tickets WHERE ticket_atom_id = tap._fetch168('atom')::uuid AND credential_version = 0), 1,
  'A12: the read wrote NO custody mutation (credential_version unchanged)');

-- ---- A13: a non-owner is refused not_owner, and gets NO key material ------
SELECT tap.login(tap.other_user());
SELECT tap._store168('ctx2', (kernel.get_ticket_signing_context(tap._fetch168('atom')::uuid))::text);
SELECT is((tap._fetch168('ctx2')::jsonb ->> 'status'), 'refused', 'A13: a non-owner gets status=refused');
SELECT is((tap._fetch168('ctx2')::jsonb ->> 'code'), 'not_owner', 'A14: …code=not_owner');
SELECT is((tap._fetch168('ctx2')::jsonb -> 'kms_handle_ref'), NULL, 'A15: …and NO kms_handle_ref anywhere in the refusal');
SELECT tap.logout();

-- ---- A16: a nonexistent atom, as an authenticated buyer, is ALSO not_owner
-- (existence is not leaked — same code, same shape, as a real wrong-owner atom).
SELECT tap.login(tap.buyer());
SELECT tap._store168('ctx3', (kernel.get_ticket_signing_context(gen_random_uuid()))::text);
SELECT is((tap._fetch168('ctx3')::jsonb ->> 'status'), 'refused', 'A16: a nonexistent atom_id is refused too');
SELECT is((tap._fetch168('ctx3')::jsonb ->> 'code'), 'not_owner', 'A17: …with the SAME code as a wrong-owner atom (no existence leak)');
SELECT tap.logout();

-- ---- A18-A20: terminal states refuse atom_terminal; listed/locked still sign
UPDATE kernel.tickets SET state = 'voided' WHERE ticket_atom_id = tap._fetch168('atom')::uuid;
SELECT tap.login(tap.buyer());
SELECT tap._store168('ctx4', (kernel.get_ticket_signing_context(tap._fetch168('atom')::uuid))::text);
SELECT is((tap._fetch168('ctx4')::jsonb ->> 'status'), 'refused', 'A18: a voided atom is refused');
SELECT is((tap._fetch168('ctx4')::jsonb ->> 'code'), 'atom_terminal', 'A19: …code=atom_terminal');
SELECT tap.logout();
UPDATE kernel.tickets SET state = 'active', resale_state = 'listed' WHERE ticket_atom_id = tap._fetch168('atom')::uuid;
SELECT tap.login(tap.buyer());
SELECT tap._store168('ctx5', (kernel.get_ticket_signing_context(tap._fetch168('atom')::uuid))::text);
SELECT is((tap._fetch168('ctx5')::jsonb ->> 'status'), 'ok',
  'A20: a listed (resale_state) atom STILL signs — EDGE_FUNCTION_SPEC §3.2 (the door rejects listed at scan, not signing)');
SELECT tap.logout();
UPDATE kernel.tickets SET resale_state = 'none' WHERE ticket_atom_id = tap._fetch168('atom')::uuid;

-- ---- A21-A22: the pinned key is missing/inactive -> signing_key_unavailable
-- (a ROTATING key that exists does not satisfy the pin — never re-resolve).
UPDATE kernel.signing_key SET status = 'rotating' WHERE key_id = tap._fetch168('key')::uuid;
SELECT tap.login(tap.buyer());
SELECT tap._store168('ctx6', (kernel.get_ticket_signing_context(tap._fetch168('atom')::uuid))::text);
SELECT is((tap._fetch168('ctx6')::jsonb ->> 'status'), 'refused', 'A21: a rotating pinned key is refused');
SELECT is((tap._fetch168('ctx6')::jsonb ->> 'code'), 'signing_key_unavailable', 'A22: …code=signing_key_unavailable (never silently re-resolved to another key)');
SELECT tap.logout();
UPDATE kernel.signing_key SET status = 'active' WHERE key_id = tap._fetch168('key')::uuid;

-- ---- A23: unauthenticated (no JWT) raises, does not return a refusal jsonb
SELECT tap.login_anon();
SELECT throws_ok($$SELECT kernel.get_ticket_signing_context(gen_random_uuid())$$, '42501', NULL,
  'A23: anon has no EXECUTE grant at all — refused before the body ever runs');
SELECT tap.logout();

-- ---- A24: the optional audit trail — an 'ok' AND a 'not_owner' outcome both
-- recorded, no secret in either (atom_id/credential_version/key_id/outcome only)
-- TWO ok-outcome rows so far: A1's initial read and A20's listed-still-signs read.
SELECT is((SELECT count(*)::int FROM kernel.admin_audit
            WHERE action = 'credential.sign_context' AND subject_id = tap._fetch168('atom')::uuid AND reason_code = 'ok'), 2,
  'A24: two ok-outcome audit rows so far (A1''s read + A20''s listed-still-signs read)');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit
            WHERE action = 'credential.sign_context' AND subject_id = tap._fetch168('atom')::uuid AND reason_code = 'not_owner'), 1,
  'A25: one not_owner-outcome audit row for the non-owner attempt');
SELECT ok(NOT EXISTS (SELECT 1 FROM kernel.admin_audit
            WHERE action = 'credential.sign_context' AND (after::text LIKE '%kms-handle%' OR after::text LIKE '%PUBKEY%')),
  'A26: no audit row ever carries the key handle or the public key material');

-- ============================================================================
-- SECTION B — catalog.publish_event: the A8a' SALEABLE gate ladder
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store168('borg', (kernel.create_organization('SB Co','SB Co','ck168-o-2') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved' WHERE org_id = tap._fetch168('borg')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store168('bvenue', (catalog.create_venue(tap._fetch168('borg')::uuid,'SB Hall','wynwood',NULL,'ck168-v-2') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch168('bvenue')::uuid,'approved','sb_gate','ck168-a-2');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store168('bevent', (catalog.create_event(tap._fetch168('bvenue')::uuid,'SB Night',
  jsonb_build_object('starts_at',(now()+interval '25 days')::text,'ends_at',(now()+interval '25 days 5 hours')::text),'ck168-e-2') ->> 'event_id'));
SELECT tap._store168('bsession', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch168('bevent')::uuid));
SELECT tap._store168('btt', (venue.create_ticket_type(tap._fetch168('bevent')::uuid,'admission','GA',5000,'public','ck168-tt-2') ->> 'ticket_type_id'));
SELECT tap._store168('bbatch', (venue.create_inventory_batch(tap._fetch168('btt')::uuid, tap._fetch168('bsession')::uuid, 'comp', 100, 0, 'ck168-b-2') ->> 'batch_id'));
-- announce first (draft -> announced carries none of the SALEABLE gates)
SELECT is((catalog.publish_event(tap._fetch168('bevent')::uuid, 'announced', 'ck168-p-0') ->> 'status'), 'ok',
  'B0: draft -> announced carries none of the new gates');
SELECT tap.logout();

-- B1: empty_inventory is UNCHANGED (still runs, still first) — a second event with no batch.
SELECT tap.login(tap.seller());
SELECT tap._store168('bevent_empty', (catalog.create_event(tap._fetch168('bvenue')::uuid,'SB Empty',
  jsonb_build_object('starts_at',(now()+interval '26 days')::text,'ends_at',(now()+interval '26 days 5 hours')::text),'ck168-e-2b') ->> 'event_id'));
SELECT is((catalog.publish_event(tap._fetch168('bevent_empty')::uuid, 'announced', 'ck168-p-0b') ->> 'status'), 'ok', 'B1a: announce the empty event');
SELECT throws_ok(format($$SELECT catalog.publish_event(%L,'on_sale','ck168-p-0c')$$, tap._fetch168('bevent_empty')),
  NULL, 'precondition_failed: empty_inventory', 'B1: empty_inventory still refuses BEFORE any SALEABLE gate is reached');
SELECT tap.logout();

-- B2: gate 1 — org_not_saleable (org suspended)
UPDATE kernel.organization SET status = 'suspended' WHERE org_id = tap._fetch168('borg')::uuid;
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT catalog.publish_event(%L,'on_sale','ck168-p-1')$$, tap._fetch168('bevent')),
  NULL, 'precondition_failed: org_not_saleable — a suspended organization may not go on sale',
  'B2: gate 1 — a suspended org refuses org_not_saleable');
SELECT tap.logout();
UPDATE kernel.organization SET status = 'approved' WHERE org_id = tap._fetch168('borg')::uuid;

-- B3: gate 2 — connect_not_ready (org approved, Connect never bound)
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT catalog.publish_event(%L,'on_sale','ck168-p-2')$$, tap._fetch168('bevent')),
  NULL, 'precondition_failed: connect_not_ready',
  'B3: gate 2 — an unbound org refuses connect_not_ready (org itself is approved now)');
SELECT tap.logout();
UPDATE kernel.organization SET stripe_connect_account_ref = 'acct_SB168READY', connect_transfers_active = true
 WHERE org_id = tap._fetch168('borg')::uuid;

-- B4: gate 3 — signing_not_ready (Connect ready, no signing key resolves)
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT catalog.publish_event(%L,'on_sale','ck168-p-3')$$, tap._fetch168('bevent')),
  NULL, 'precondition_failed: signing_not_ready — an active signing key must resolve for the event scope before it can go on sale',
  'B4: gate 3 — no signing key resolves for this event/venue/global scope');
SELECT tap.logout();
INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
VALUES ('per_event', tap._fetch168('bevent')::uuid, 'PUBKEY-SB168', 'kms-handle-sb168', 'active', now());

-- B5: gate 4 — fee_policy_unset (signing ready, fee.buyer_service_bps unset by default)
SELECT tap.login(tap.seller());
SELECT throws_ok(format($$SELECT catalog.publish_event(%L,'on_sale','ck168-p-4')$$, tap._fetch168('bevent')),
  NULL, 'precondition_failed: fee_policy_unset — fee.buyer_service_bps has no value; this event cannot go on sale until the owner sets it',
  'B5: gate 4 — fee.buyer_service_bps is unset (093 seed: null)');
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('fee.buyer_service_bps', 2, '750'::jsonb, 'restricted');

-- B8: the happy path — every SALEABLE prerequisite satisfied, on_sale executes.
SELECT tap.login(tap.seller());
SELECT is((catalog.publish_event(tap._fetch168('bevent')::uuid, 'on_sale', 'ck168-p-7') ->> 'status'), 'ok',
  'B8: with all four SALEABLE prerequisites satisfied, on_sale executes');
SELECT is((SELECT status FROM catalog.event WHERE event_id = tap._fetch168('bevent')::uuid), 'on_sale',
  'B9: the event row itself now reads on_sale');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action = 'event.status' AND subject_id = tap._fetch168('bevent')::uuid AND reason_code = 'publish'), 2,
  'B10: two event.status audit rows total (the B0 announce + this on_sale) — the existing audit trail is unchanged');

-- B11: live -> completed (a transition the SALEABLE gate never touches) still works untouched.
SELECT tap.login(tap.seller());
SELECT is((catalog.publish_event(tap._fetch168('bevent')::uuid, 'live', 'ck168-p-8') ->> 'status'), 'ok', 'B11: on_sale -> live (unaffected)');
SELECT is((catalog.publish_event(tap._fetch168('bevent')::uuid, 'completed', 'ck168-p-9') ->> 'status'), 'ok', 'B12: live -> completed (unaffected)');
SELECT tap.logout();

-- ============================================================================
-- SECTION C — catalog.set_platform_config: signing.% trust-root dual control
-- ============================================================================
SELECT tap.login(tap.admin_user());

-- C1-C3: the trust-root pair PARKS on its very first write (seeded null; v_dual
-- true, no polarity => always parks, exactly like ticket.% above it).
SELECT is((catalog.set_platform_config('signing.expected_key_fingerprint', to_jsonb(repeat('a',64)), 'ceremony', 'ck168-c-1') ->> 'status'),
  'parked', 'C1: SETTING signing.expected_key_fingerprint PARKS — the trust root needs a second platform_admin');
SELECT is((SELECT max(version) FROM catalog.platform_config WHERE key = 'signing.expected_key_fingerprint'), 1,
  'C2: …and inserts NO new version — the parked write did not land');
SELECT is((SELECT value FROM catalog.platform_config WHERE key = 'signing.expected_key_fingerprint' ORDER BY version DESC LIMIT 1), 'null'::jsonb,
  'C3: …and the value is still JSON-null');

SELECT is((catalog.set_platform_config('signing.expected_max_not_after', to_jsonb((now()+interval '400 days')::text), 'ceremony', 'ck168-c-2') ->> 'status'),
  'parked', 'C4: SETTING signing.expected_max_not_after PARKS too');
SELECT is((SELECT max(version) FROM catalog.platform_config WHERE key = 'signing.expected_max_not_after'), 1,
  'C5: …and inserts NO new version either');

-- C6: signing.monitor_enabled stays SINGLE-ADMIN in BOTH directions — the
-- emergency detection toggle, deliberately excluded from v_dual.
SELECT is((catalog.set_platform_config('signing.monitor_enabled', 'true'::jsonb, 'ops', 'ck168-c-3') ->> 'status'),
  'ok', 'C6: turning signing.monitor_enabled ON executes with ONE admin (not a trust-root change)');
SELECT is((SELECT max(version) FROM catalog.platform_config WHERE key = 'signing.monitor_enabled'), 2,
  'C7: …and DOES insert a new version (it actually wrote)');
SELECT is((catalog.set_platform_config('signing.monitor_enabled', 'false'::jsonb, 'incident', 'ck168-c-4') ->> 'status'),
  'ok', 'C8: turning it back OFF also executes with ONE admin — a kill switch that needs a quorum is not a kill switch');

SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
