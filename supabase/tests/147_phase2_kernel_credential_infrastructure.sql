-- ============================================================================
-- 147_phase2_kernel_credential_infrastructure.sql — Phase-2 package 083 suite.
--
-- Frozen sources: plan §8/083 · schema §1.7 + WALLET §11.1-§11.6 · RPC §7.1 (mint),
-- §17.13 (delta stub), §17.23 + §20.7.3-4 (lifecycle) · RLS §7.7/§16.8 · dsm §2 BP-2 ·
-- ODR16 #19 · OR-17. Owner rulings PFA-16 (anon key-read fail-closed to authenticated),
-- PFA-17 (revoke_signing_key → 086), PFA-18/18A (credential dual-control PARKED —
-- approval_request can't represent it), PFA-20 (wallet token crypto PARKED). C33: no
-- key material on any row. Native issuance + Wallet stay DARK. Convention: BEGIN …
-- plan(N) … finish() … ROLLBACK.
-- ============================================================================
BEGIN;
SELECT plan(53);

SELECT tap.seed_core();

CREATE TABLE tap.memo_147 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store147(k text, v text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ INSERT INTO tap.memo_147 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v RETURNING v $m$;
CREATE FUNCTION tap._fetch147(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS
$m$ SELECT v FROM tap.memo_147 WHERE k = $1 $m$;
-- definer reads of deny-all tables (wallet_pass etc. are zero-policy)
CREATE FUNCTION tap._sk_count(p_key uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.signing_key WHERE key_id = p_key $m$;
CREATE FUNCTION tap._wp_status(p_atom uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT status FROM kernel.wallet_pass WHERE ticket_atom_id = p_atom ORDER BY generation DESC LIMIT 1 $m$;
CREATE FUNCTION tap._tickets_for(p_session uuid) RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path='' AS
$m$ SELECT count(*)::int FROM kernel.tickets WHERE event_session_id = p_session $m$;
GRANT EXECUTE ON FUNCTION tap._sk_count(uuid), tap._wp_status(uuid), tap._tickets_for(uuid) TO authenticated;

-- ============================================================================
-- SECTION A — THE 083 CLOSED WORLD
-- ============================================================================
SELECT is((SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='kernel' AND c.relkind='r'), 22,
  'A1: kernel holds 22 tables — 17 post-082 + the 5 of 083 (signing_key, pass_type_cert, 3 wallet)');
SELECT has_table('kernel'::name,'signing_key'::name, 'A2: kernel.signing_key');
SELECT has_table('kernel'::name,'pass_type_cert'::name, 'A3: kernel.pass_type_cert');
SELECT has_table('kernel'::name,'wallet_pass'::name, 'A4: kernel.wallet_pass');
SELECT has_table('kernel'::name,'wallet_pass_device'::name, 'A5: kernel.wallet_pass_device');
SELECT has_table('kernel'::name,'wallet_pass_push_log'::name, 'A6: kernel.wallet_pass_push_log (AO)');
SELECT has_function('kernel'::name,'issue_ticket_atoms'::name, ARRAY['jsonb','text']::name[], 'A7: the mint engine issue_ticket_atoms is authored HERE (C114/R2B)');
SELECT has_function('kernel'::name,'mint_wallet_pass'::name, ARRAY['uuid','text']::name[], 'A8: mint_wallet_pass');
SELECT has_function('venue'::name,'append_door_manifest_delta'::name, ARRAY['uuid','uuid[]','text','uuid']::name[], 'A9: the append_door_manifest_delta SEAM-2 stub');
-- PFA-17: revoke_signing_key is NOT here (→ 086)
SELECT hasnt_function('kernel'::name,'revoke_signing_key'::name, 'A10: PFA-17 — revoke_signing_key is NOT authored here (→ 086)');
-- forward objects absent
SELECT hasnt_function('venue'::name,'finalize_primary_order'::name, 'A11: finalize is NOT here (085)');
SELECT hasnt_table('kernel'::name,'payment_native'::name, 'A12: kernel.payment_native is NOT here (085)');
SELECT hasnt_function('kernel'::name,'transfer_ticket_ownership'::name, 'A13: the transfer engine is NOT here (088)');
-- the .pkpass private bucket + zero policies
SELECT is((SELECT public::text FROM storage.buckets WHERE id='pkpass'), 'false', 'A14: the .pkpass bucket exists and is PRIVATE (public=false)');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname='kernel'
            AND tablename IN ('pass_type_cert','wallet_pass','wallet_pass_device','wallet_pass_push_log')), 0,
  'A15: the four wallet/cert tables are deny-all with ZERO policies');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname='kernel' AND tablename='signing_key'), 1,
  'A16: signing_key has exactly one policy (the public projection)');
-- the structural half of the Wallet non-negotiable: one live pass per atom
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='kernel' AND tablename='wallet_pass'
                   AND indexdef LIKE '%status%issued%'),
  'A17: wallet_pass has the partial UNIQUE(ticket_atom_id) WHERE status=issued (≤1 live pass per atom)');

-- ============================================================================
-- SECTION B — C33: NO PRIVATE KEY MATERIAL + secret-column custody
-- ============================================================================
-- signing_key public projection is granted to AUTHENTICATED (PFA-16), never anon;
-- kms_handle_ref is withheld from the column grant.
SELECT ok(has_column_privilege('authenticated','kernel.signing_key','public_key','SELECT')
       AND NOT has_column_privilege('authenticated','kernel.signing_key','kms_handle_ref','SELECT'),
  'B1: authenticated reads public_key but NOT kms_handle_ref (col-scoped; C33)');
SELECT ok(NOT has_schema_privilege('anon','kernel','USAGE'),
  'B2: PFA-16 — anon has NO kernel schema USAGE (076 wall unchanged; anon verify via 086 manifest)');
SELECT ok(NOT has_column_privilege('authenticated','kernel.wallet_pass','auth_token_enc','SELECT')
       AND NOT has_column_privilege('authenticated','kernel.wallet_pass','auth_token_hash','SELECT'),
  'B3: no client SELECT on the wallet bearer-token columns (service_role only)');
SELECT ok(NOT has_table_privilege('authenticated','kernel.pass_type_cert','SELECT'),
  'B4: pass_type_cert has no client access at all (doors never verify the Apple signature)');
-- push_log is AO — structural + grant-layer (the empty ledger can't fire a per-row
-- guard; its P0001 raise is exercised on populated tables by F/G immutability tests).
SELECT ok(
  (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE n.nspname='kernel' AND c.relname='wallet_pass_push_log'
      AND p.proname='raise_append_only' AND NOT t.tgisinternal) = 1
  AND NOT has_table_privilege('service_role','kernel.wallet_pass_push_log','UPDATE')
  AND NOT has_table_privilege('service_role','kernel.wallet_pass_push_log','DELETE'),
  'B5: the push-log ledger is append-only — raise_append_only guard attached AND service_role holds no UPDATE/DELETE');

-- ============================================================================
-- SECTION C — FEATURE DARKNESS (native issuance + Wallet both OFF)
-- ============================================================================
SELECT is((SELECT (value #>> '{}')::text FROM catalog.platform_config WHERE key='feature.native_issuance_enabled' ORDER BY version DESC LIMIT 1),
  'false', 'C1: native issuance is DARK (078 seed)');
SELECT is((SELECT (value #>> '{}')::text FROM catalog.platform_config WHERE key='wallet.apple.enabled' ORDER BY version DESC LIMIT 1),
  'false', 'C2: Wallet is DARK (078 seed)');

-- ============================================================================
-- SECTION D — CREDENTIAL LIFECYCLE FAIL-CLOSED (PFA-18A): dual-control unavailable
-- ============================================================================
SELECT throws_ok($$SELECT kernel.provision_signing_key('per_event', gen_random_uuid(), 'pk','kms','2026-01-01'::timestamptz,'r','ck')$$,
  NULL, 'precondition_failed: dual_control_unavailable — credential dual-control mechanism not yet ratified (PFA-18A); provisioning is parked, no key is activated',
  'D1: provision_signing_key FAILS CLOSED (dual_control_unavailable)');
SELECT throws_ok($$SELECT kernel.rotate_signing_key(gen_random_uuid(),'pk','kms','r','ck')$$,
  NULL, NULL, 'D2: rotate_signing_key fails closed');
SELECT throws_ok($$SELECT kernel.provision_pass_type_cert('pass.x','TEAM','c','w','kms','2026-01-01'::timestamptz,'2027-01-01'::timestamptz,'r','ck')$$,
  NULL, NULL, 'D3: provision_pass_type_cert fails closed');
SELECT throws_ok($$SELECT kernel.rotate_pass_type_cert(gen_random_uuid(),'c','w','kms','2026-01-01'::timestamptz,'2027-01-01'::timestamptz,'r','ck')$$,
  NULL, NULL, 'D4: rotate_pass_type_cert fails closed');
SELECT throws_ok($$SELECT kernel.revoke_pass_type_cert(gen_random_uuid(),'r','ck')$$,
  NULL, NULL, 'D5: revoke_pass_type_cert fails closed');
-- ZERO credential mutation on the parked path
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 0, 'D6: PFA-18A — the parked lifecycle activated NO signing key (zero mutation)');
SELECT is((SELECT count(*)::int FROM kernel.pass_type_cert), 0, 'D7: …and NO pass_type_cert (zero mutation)');

-- ============================================================================
-- SECTION E — WALLET TOKEN-CRYPTO FAIL-CLOSED (PFA-20)
-- ============================================================================
SELECT throws_ok($$SELECT kernel.mint_wallet_pass(gen_random_uuid(),'ck')$$,
  NULL, 'precondition_failed: wallet_disabled', 'E1: mint_wallet_pass refuses wallet_disabled while dark (kill switch)');
SELECT throws_ok($$SELECT kernel.get_wallet_pass_build_context('serial','tok')$$,
  NULL, 'precondition_failed: wallet_disabled', 'E2: the serve route refuses wallet_disabled while dark');
SELECT throws_ok($$SELECT kernel.register_wallet_pass_device('serial','tok','dev','push')$$,
  NULL, NULL, 'E3: register fails closed');
-- flip the wallet flag: mint now parks on token_encryption_unavailable (PFA-20), NOT a token
SELECT tap.logout();
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('wallet.apple.enabled', 2, 'true'::jsonb, 'restricted');
SELECT throws_ok($$SELECT kernel.mint_wallet_pass(gen_random_uuid(),'ck')$$,
  NULL, 'precondition_failed: token_encryption_unavailable — wallet bearer-token crypto mechanism not yet ratified (PFA-20); mint is parked, no token is generated/hashed/encrypted',
  'E4: PFA-20 — even with the kill switch flipped, mint parks on token_encryption_unavailable (no token generated)');
SELECT is((SELECT count(*)::int FROM kernel.wallet_pass), 0, 'E5: …and NO wallet_pass / token was written (zero mutation)');

-- ============================================================================
-- FIXTURE — org → venue → event → session → ticket_type → batch (for the mint)
-- ============================================================================
SELECT tap.login(tap.seller());
SELECT tap._store147('org', (kernel.create_organization('Cred Co','Cred Co','ck-o-1') ->> 'org_id'));
SELECT tap.logout();
UPDATE kernel.organization SET status='approved' WHERE org_id = tap._fetch147('org')::uuid;
SELECT tap.login(tap.seller());
SELECT tap._store147('venue', (catalog.create_venue(tap._fetch147('org')::uuid,'Hall','wynwood',NULL,'ck-v-1') ->> 'venue_id'));
SELECT tap.logout();
SELECT tap.login(tap.admin_user());
SELECT catalog.approve_venue(tap._fetch147('venue')::uuid,'approved','miami_gate','ck-a-1');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT tap._store147('event', (catalog.create_event(tap._fetch147('venue')::uuid,'Cred Night',
  jsonb_build_object('starts_at',(now()+interval '20 days')::text,'ends_at',(now()+interval '20 days 5 hours')::text),'ck-e-1') ->> 'event_id'));
SELECT tap._store147('session', (SELECT session_id::text FROM catalog.event_session WHERE event_id = tap._fetch147('event')::uuid));
SELECT tap._store147('tt', (venue.create_ticket_type(tap._fetch147('event')::uuid,'admission','GA',5000,'public','ck-tt-1') ->> 'ticket_type_id'));
SELECT tap._store147('batch', (venue.create_inventory_batch(tap._fetch147('tt')::uuid, tap._fetch147('session')::uuid, 'comp', 100, 0, 'ck-b-1') ->> 'batch_id'));
SELECT tap.logout();

-- ============================================================================
-- SECTION F — issue_ticket_atoms: ACTIVATION BOUNDARY + happy path (C27 backstop)
-- ============================================================================
-- while native issuance is dark, the mint refuses feature_disabled
SELECT throws_ok(format($$SELECT kernel.issue_ticket_atoms(jsonb_build_object('session_id',%L,'org_id',%L,'ticket_type_id',%L,'batch_id',%L,'owner_id',%L,'quantity',2,'cause','comp','cause_ref',gen_random_uuid(),'signing_key_id',gen_random_uuid()),'ck-m-0')$$,
    tap._fetch147('session'), tap._fetch147('org'), tap._fetch147('tt'), tap._fetch147('batch'), tap.buyer()),
  NULL, 'precondition_failed: feature_disabled', 'F1: the mint refuses feature_disabled while native issuance is dark');
-- flip native issuance ON. ACTIVATION BOUNDARY: still fails closed — no active signing key.
INSERT INTO catalog.platform_config (key, version, value, visibility) VALUES ('feature.native_issuance_enabled', 2, 'true'::jsonb, 'public');
SELECT throws_ok(format($$SELECT kernel.issue_ticket_atoms(jsonb_build_object('session_id',%L,'org_id',%L,'ticket_type_id',%L,'batch_id',%L,'owner_id',%L,'quantity',2,'cause','comp','cause_ref',gen_random_uuid(),'signing_key_id',%L),'ck-m-1')$$,
    tap._fetch147('session'), tap._fetch147('org'), tap._fetch147('tt'), tap._fetch147('batch'), tap.buyer(), gen_random_uuid()),
  NULL, 'precondition_failed: no_active_signing_key — an active signing key must resolve for the event scope before any atom is minted',
  'F2: ACTIVATION BOUNDARY — with the flag ON but no active signing key, the mint fails closed (never auto-creates a key)');
-- provision a signing key DIRECTLY (the lifecycle is parked; a test bypasses it) and mint.
WITH ins AS (
  INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before)
  VALUES ('per_event', tap._fetch147('event')::uuid, 'PUBKEY', 'kms-handle-opaque', 'active', now())
  RETURNING key_id
)
SELECT tap._store147('key', (SELECT key_id::text FROM ins));
SELECT is((kernel.issue_ticket_atoms(jsonb_build_object('session_id',tap._fetch147('session')::uuid,'org_id',tap._fetch147('org')::uuid,
    'ticket_type_id',tap._fetch147('tt')::uuid,'batch_id',tap._fetch147('batch')::uuid,'owner_id',tap.buyer(),
    'quantity',2,'cause','comp','cause_ref',gen_random_uuid(),'signing_key_id',tap._fetch147('key')::uuid),'ck-m-2') ->> 'status'),
  'ok', 'F3: with an active key + the flag on, the mint DRAWS — the engine works end to end');
SELECT is(tap._tickets_for(tap._fetch147('session')::uuid), 2, 'F4: two atoms minted into kernel.tickets');
SELECT is((SELECT count(*)::int FROM kernel.ticket_ownership_log l JOIN kernel.tickets t ON t.ticket_atom_id=l.ticket_atom_id
            WHERE t.event_session_id=tap._fetch147('session')::uuid AND l.cause='issue' AND l.sequence=1 AND l.from_identity IS NULL), 2,
  'F5: two ownership-log mint rows (sequence=1, from NULL, cause=issue)');
SELECT is((SELECT sold::int FROM venue.inventory_batch WHERE batch_id=tap._fetch147('batch')::uuid), 2,
  'F6: the batch counter converted sold += 2 (C27 held+sold<=capacity backstop)');
SELECT is((SELECT signing_key_id FROM kernel.tickets WHERE event_session_id=tap._fetch147('session')::uuid LIMIT 1), tap._fetch147('key')::uuid,
  'F7: every minted atom pins the active signing_key_id (C33 — the key ref, never key material)');
-- idempotency: a replay returns the original atoms, mints no more
SELECT is((SELECT count(*)::int FROM kernel.tickets WHERE event_session_id=tap._fetch147('session')::uuid), 2, 'F8: still exactly 2 atoms (no double-mint)');
-- oversell backstop: a mint that would exceed capacity aborts (23514)
SELECT throws_ok(format($$UPDATE venue.inventory_batch SET sold=101 WHERE batch_id=%L$$, tap._fetch147('batch')),
  '23514', NULL, 'F9: C27 — a direct over-write of the counter beyond capacity is rejected (oversell CHECK)');

-- ============================================================================
-- SECTION G — deletion_blockers_wallet (SEAM-2 body; BP-2) + non-crypto wallet RPCs
-- ============================================================================
SELECT ok(pg_get_functiondef('kernel.deletion_blockers_wallet(uuid)'::regprocedure) LIKE '%wallet_pass%',
  'G1: deletion_blockers_wallet now reads kernel.wallet_pass (BP-2 body; the 077 stub returned null)');
SELECT is(kernel.deletion_blockers_wallet(tap.buyer()), NULL, 'G2: no live wallet pass → no BP-2 block');
-- insert a live wallet pass directly (mint is parked) to exercise BP-2 + the non-crypto lifecycle
WITH insc AS (
  INSERT INTO kernel.pass_type_cert (pass_type_identifier, team_identifier, certificate_pem, wwdr_cert_pem, kms_handle_ref, status, not_before, not_after)
  VALUES ('pass.com.snatchit.ticket','TEAMID','CERT','WWDR','kms-cert', 'active', now(), now()+interval '1 year')
  RETURNING pass_type_cert_id
)
SELECT tap._store147('cert', (SELECT pass_type_cert_id::text FROM insc));
WITH insw AS (
  INSERT INTO kernel.wallet_pass (ticket_atom_id, holder_identity_id, generation, serial_no_opaque, pass_type_cert_id,
      auth_token_enc, auth_token_hash, credential_version_at_build, signing_key_id, status, command_idempotency_key)
  SELECT t.ticket_atom_id, tap.buyer(), 1, 'SERIAL-OPAQUE-0000001', tap._fetch147('cert')::uuid, '\x00'::bytea, 'hash', 0,
         tap._fetch147('key')::uuid, 'issued', 'ck-wp-1'
    FROM kernel.tickets t WHERE t.event_session_id=tap._fetch147('session')::uuid LIMIT 1
  RETURNING ticket_atom_id
)
SELECT tap._store147('atom', (SELECT ticket_atom_id::text FROM insw));
SELECT isnt(kernel.deletion_blockers_wallet(tap.buyer()), NULL, 'G3: BP-2 — a live issued wallet pass blocks tombstone entry');
-- supersede (outbox-consumer path) → issued becomes superseded, BP-2 clears
SELECT is((kernel.supersede_wallet_passes_for_atom(tap._fetch147('atom')::uuid, 'transferred') ->> 'superseded'), '1',
  'G4: supersede_wallet_passes_for_atom marks the live pass superseded');
SELECT is(tap._wp_status(tap._fetch147('atom')::uuid), 'superseded', 'G5: …the pass is now superseded');
SELECT is(kernel.deletion_blockers_wallet(tap.buyer()), NULL, 'G6: …and BP-2 no longer blocks (no issued pass)');
-- touch + record_push are buildable (no crypto)
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
            WHERE n.nspname='kernel' AND p.proname='sweep_wallet_pass_lifecycle'), 1, 'G7: sweep_wallet_pass_lifecycle exists (cron, non-crypto)');
-- SEAM-2 stub is a no-op (returns void, writes nothing) — asserted before venue.door_manifest exists
SELECT lives_ok(format($$SELECT venue.append_door_manifest_delta(%L, ARRAY[gen_random_uuid()], 'add', gen_random_uuid())$$, tap._fetch147('session')),
  'G8: append_door_manifest_delta is a silent no-op at 083 (body 086)');

SELECT finish();
ROLLBACK;
