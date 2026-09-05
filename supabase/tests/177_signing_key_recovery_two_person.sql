-- ============================================================================
-- 177_signing_key_recovery_two_person.sql — migration 111 (E4, PFA-18C maturity
--   trigger). The gated TWO-PERSON post-revoke recovery: approval table (append-
--   only, no client access), approve (platform_admin+aal2, distinct identities,
--   30-minute window, idempotent), execute (approver-only, fingerprint-bound,
--   ES256 explicit), the re-created 110 guard (rule 10 ⇒ two approvals),
--   preconditions (zero active, exactly one revoked, unused key_id), initial-
--   bootstrap immunity, PFA-18A parking + PFA-18B revoke unchanged, transaction
--   rollback on refusal, and savepoint rollback/replay of 111.
--
--   seed_core() is needed for identities but DISABLES the insert guard for
--   legacy fixtures — so this suite RE-ENABLES it immediately after seeding and
--   asserts that it did (A0). Everything then runs against the LIVE guard.
-- ============================================================================
BEGIN;
SELECT plan(67);
SELECT tap.seed_core();
ALTER TABLE kernel.signing_key ENABLE TRIGGER tg_signing_key_insert_guard;
SELECT is((SELECT tgenabled FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_insert_guard'), 'O',
  'A0: the insert guard is LIVE for this suite');

-- ── fixtures ────────────────────────────────────────────────────────────────
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || jsonb_build_object('aal','aal2','session_id', gen_random_uuid()::text))::text, true); end $f$;
CREATE FUNCTION tap._pem177_a() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;
-- a SECOND real P-256 key (the recovery key)
CREATE FUNCTION tap._pem177_b() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE0gPaCYVWHrimb0J/hVIv6tmi27iX
G3AdA/KtRQeQFmFZgPBs+yuiaIKGGaPcCq/n4FS1pF8RvGmSaqvjmjSHUQ==
-----END PUBLIC KEY-----
$p$ $f$;
CREATE FUNCTION tap._pem177_ed() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAOXCGAFeE94Hf0fMjmKfqtS+CKCvauv8AZOs8mUiMc7U=
-----END PUBLIC KEY-----
$p$ $f$;
CREATE FUNCTION tap._arn177() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT 'arn:aws:kms:us-east-1:652872010073:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b' $f$;
CREATE FUNCTION tap._arn177_b() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT 'arn:aws:kms:us-east-1:652872010073:key/2c3d4e5f-6071-4829-9bac-1d2e3f4a5b6c' $f$;
CREATE FUNCTION tap._b0() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '00000000-0000-0000-0000-0000000000b0'::uuid $f$;
CREATE FUNCTION tap._b1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '00000000-0000-0000-0000-0000000000b1'::uuid $f$;
-- SECURITY DEFINER: the helper is zero-grant (A9); tests evaluate this wrapper while logged in as `authenticated`.
CREATE FUNCTION tap._fp_b() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER AS $f$ SELECT kernel.signing_key_p256_pem_fingerprint(tap._pem177_b()) $f$;
-- second + third platform admins: other_user via kernel.platform_role (the 077 arm), buyer via public.admin_users
INSERT INTO kernel.platform_role (identity_id, role) VALUES (tap.other_user(), 'platform_admin') ON CONFLICT DO NOTHING;
INSERT INTO public.admin_users (user_id, label) VALUES (tap.buyer(), 'TEST ADMIN 3') ON CONFLICT DO NOTHING;
-- SECURITY DEFINER readers: the approval table has NO client grants (A7); assertions that run while logged in read through these.
CREATE FUNCTION tap._approvals177(p_key uuid) RETURNS int LANGUAGE sql STABLE SECURITY DEFINER AS $f$ SELECT count(*)::int FROM kernel.signing_key_recovery_approval WHERE key_id = p_key $f$;
CREATE FUNCTION tap._sessions177(p_key uuid) RETURNS int LANGUAGE sql STABLE SECURITY DEFINER AS $f$ SELECT count(DISTINCT approver_session)::int FROM kernel.signing_key_recovery_approval WHERE key_id = p_key $f$;
CREATE FUNCTION tap._bootstrap177() RETURNS void LANGUAGE sql AS $f$
  INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES (tap._b0(), 'global', null, null, tap._pem177_a(), tap._arn177(), 'ES256', 'active', now(), null)
$f$;

-- ── A. structure / access ───────────────────────────────────────────────────
SELECT has_table('kernel'::name, 'signing_key_recovery_approval'::name, 'A1: kernel.signing_key_recovery_approval exists (111)');
SELECT has_function('kernel'::name, 'approve_signing_key_recovery'::name, 'A2: approve_signing_key_recovery exists');
SELECT has_function('kernel'::name, 'execute_signing_key_recovery'::name, 'A3: execute_signing_key_recovery exists');
SELECT has_function('kernel'::name, 'signing_key_p256_pem_fingerprint'::name, 'A4: fingerprint helper exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'kernel.signing_key_recovery_approval'::regclass), 'A5: RLS enabled on the approval table');
SELECT is((SELECT count(*)::int FROM pg_policies WHERE schemaname = 'kernel' AND tablename = 'signing_key_recovery_approval'), 0, 'A6: zero policies — no client path by construction');
SELECT ok(NOT has_table_privilege('anon','kernel.signing_key_recovery_approval','SELECT')
       AND NOT has_table_privilege('authenticated','kernel.signing_key_recovery_approval','SELECT')
       AND NOT has_table_privilege('authenticated','kernel.signing_key_recovery_approval','INSERT')
       AND NOT has_table_privilege('service_role','kernel.signing_key_recovery_approval','SELECT')
       AND NOT has_table_privilege('service_role','kernel.signing_key_recovery_approval','INSERT')
       AND NOT has_table_privilege('service_role','kernel.signing_key_recovery_approval','UPDATE')
       AND NOT has_table_privilege('service_role','kernel.signing_key_recovery_approval','DELETE'),
  'A7: anon / authenticated / service_role hold NO privilege of any kind on the approval table');
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid WHERE t.tgrelid = 'kernel.signing_key_recovery_approval'::regclass AND p.proname = 'raise_append_only' AND NOT t.tgisinternal), 1,
  'A8: append-only guard (076 raise_append_only) attached');
SELECT ok(NOT has_function_privilege('service_role', 'kernel.approve_signing_key_recovery(uuid,text,text,text)', 'EXECUTE')
       AND NOT has_function_privilege('anon', 'kernel.approve_signing_key_recovery(uuid,text,text,text)', 'EXECUTE')
       AND has_function_privilege('authenticated', 'kernel.approve_signing_key_recovery(uuid,text,text,text)', 'EXECUTE')
       AND NOT has_function_privilege('service_role', 'kernel.execute_signing_key_recovery(uuid,text,text,text,text)', 'EXECUTE')
       AND NOT has_function_privilege('authenticated', 'kernel.signing_key_p256_pem_fingerprint(text)', 'EXECUTE'),
  'A9: approve/execute are authenticated-callable definers (authz inside); service_role/anon cannot call them; the helper is zero-grant');
SELECT is(kernel.signing_key_p256_pem_fingerprint(tap._pem177_a()), '08ec5757ea9e0f694a0e4e59c0c2b98d2da9cde838659cd707167b36cc5e7174', 'A10: helper reproduces the openssl D5 fingerprint');
SELECT ok(kernel.signing_key_p256_pem_fingerprint(tap._pem177_ed()) IS NULL AND kernel.signing_key_p256_pem_fingerprint('junk') IS NULL
       AND kernel.signing_key_p256_pem_fingerprint(E'-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----') IS NULL,
  'A11: helper is NULL for Ed25519 / junk / private material (never raises)');

-- ── B. cannot be used for initial bootstrap ─────────────────────────────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-b1') $q$,
  '%recovery_not_applicable%', 'B1: on an EMPTY keyring approve is refused — the initial bootstrap is the §6.1 ceremony');
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-b2') $q$,
  '%recovery_not_applicable%', 'B2: execute is refused on an empty keyring');
SELECT tap.logout();
SELECT lives_ok($q$ SELECT tap._bootstrap177() $q$, 'B3: the §6.1 bootstrap row is still the only way to create the first key (guard rule 11)');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-b4') $q$,
  '%active_global_exists%', 'B4: with an ACTIVE global key, approve is refused (recovery only after a revoke)');
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b0(), tap._fp_b(), 'incident', 'ck177-b5') $q$,
  '%duplicate_key_id%', 'B5: approving a key_id that already exists (the bootstrap id) is refused');
SELECT tap.logout();

-- ── C. revoke (PFA-18B semantics: status flip, terminal) ────────────────────
SELECT lives_ok($q$ UPDATE kernel.signing_key SET status = 'revoked' WHERE key_id = tap._b0() $q$, 'C1: bootstrap key revoked');
SELECT is((SELECT count(*)::int FROM kernel.signing_key WHERE status = 'active'), 0, 'C2: zero active keys');

-- ── D. approvals — authz, distinctness, window, idempotency ─────────────────
SELECT tap.login(tap.seller());
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-d1') $q$,
  '%insufficient_privilege%', 'D1: a non-platform identity cannot approve');
SELECT tap.login(tap.admin_user());   -- platform_admin, aal1 (no aal claim)
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-d2') $q$,
  '%step_up_unavailable%', 'D2: platform_admin without an aal claim cannot approve');
SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), 'not-a-fingerprint', 'incident', 'ck177-d3') $q$,
  '%invalid_input%', 'D3: fingerprint must be 64 lowercase hex');
SELECT is((kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-A1')) ->> 'status', 'approved', 'D4: admin A approves (1/2)');
SELECT is((kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-A1')) ->> 'status', 'noop_replay', 'D5: replay of the same command_key is a no-op');
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-A2') $q$,
  '%duplicate_approver%', 'D6: the SAME identity cannot approve twice (new command_key)');
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery(tap._b1(), repeat('a', 64), 'incident', 'ck177-A1') $q$,
  '%command_key_reused%', 'D7: a command_key cannot be re-pointed at a different proposal');
SELECT is(tap._approvals177(tap._b1()), 1, 'D8: exactly one approval row so far');
-- one approval is NOT enough — execute by A refused; a bare INSERT refused by the guard
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-X0') $q$,
  '%post_revoke_recovery_unapproved%', 'D9: execute with ONE approval is refused');
SELECT tap.logout();
SELECT throws_like($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES (tap._b1(), 'global', null, null, tap._pem177_b(), tap._arn177_b(), 'ES256', 'active', now(), null) $q$,
  '%post_revoke_recovery_unapproved%', 'D10: a bare superuser INSERT with one approval is refused by the guard');
-- second approver: other_user via kernel.platform_role, aal2, its own session
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is((kernel.approve_signing_key_recovery(tap._b1(), tap._fp_b(), 'incident', 'ck177-B1')) ->> 'approvals', '2', 'D11: admin B approves — two distinct approvals');
SELECT is(tap._sessions177(tap._b1()), 2, 'D12: two distinct sessions recorded as evidence');
SELECT tap.logout();

-- ── E. execute — refusals then success ──────────────────────────────────────
SELECT tap.login(tap.buyer()); SELECT tap._aal2();   -- platform_admin (admin_users) but NOT an approver
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-C1') $q$,
  '%executor_not_approver%', 'E1: a third platform_admin who did not approve cannot execute');
SELECT tap.login(tap.other_user());   -- approver B, but aal1
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-B2') $q$,
  '%step_up_unavailable%', 'E2: an approver on a non-aal2 session cannot execute');
SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_a(), tap._arn177_b(), 'incident', 'ck177-B3') $q$,
  '%fingerprint_mismatch%', 'E3: a different (valid) public key than the approved fingerprint is refused');
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_ed(), tap._arn177_b(), 'incident', 'ck177-B4') $q$,
  '%public_key_not_p256_spki_pem%', 'E4: an Ed25519 PEM is refused before any approval lookup');
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), 'alias/snatchit', 'incident', 'ck177-B5') $q$,
  '%kms_handle_not_key_arn%', 'E5: a non-ARN handle is refused');
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b0(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-B6') $q$,
  '%duplicate_key_id%', 'E6: re-using the revoked key_id is refused');
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 1, 'E7: nothing written by any refused execute');
SELECT is((kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-B7')) ->> 'status', 'recovered',
  'E8: approver B executes — the recovery key is inserted through the live guard');
SELECT is((kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-B7')) ->> 'status', 'noop_replay',
  'E9: replaying the same execute command is a no-op');
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery(tap._b1(), tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-B8') $q$,
  '%duplicate_key_id%', 'E10: a second execute with a new command_key is refused (key exists)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM kernel.signing_key WHERE scope = 'global' AND status = 'active'), 1, 'E11: exactly one active global key');
SELECT is((SELECT algorithm FROM kernel.signing_key WHERE key_id = tap._b1()), 'ES256', 'E12: recovered key is ES256');
SELECT is(kernel.signing_key_p256_pem_fingerprint((SELECT public_key FROM kernel.signing_key WHERE key_id = tap._b1())), tap._fp_b(), 'E13: stored PEM matches the approved fingerprint');
SELECT is((SELECT status FROM kernel.signing_key WHERE key_id = tap._b0()), 'revoked', 'E14: the revoked bootstrap row is untouched (append-only lineage)');
SELECT is((SELECT count(*)::int FROM kernel.admin_audit WHERE action IN ('signing_key.recovery_approve','signing_key.recovery_execute') AND subject_id = tap._b1()), 3,
  'E15: two approve audits + one execute audit');

-- ── F. after recovery: parking + guard + revoke behaviour unchanged ─────────
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery('00000000-0000-0000-0000-0000000000b2', tap._fp_b(), 'incident', 'ck177-F1') $q$,
  '%active_global_exists%', 'F1: with the recovered key active, no further approval can be recorded');
SELECT throws_like($q$ SELECT kernel.provision_signing_key('global', null, 'x', 'x', now(), 'r', 'ck177-p') $q$,
  '%dual_control_unavailable%', 'F2: PFA-18A provision still parked');
SELECT throws_like($q$ SELECT kernel.rotate_signing_key(tap._b1(), 'x', 'x', 'r', 'ck177-r') $q$,
  '%dual_control_unavailable%', 'F3: PFA-18A rotate still parked');
SELECT lives_ok($q$ SELECT kernel.revoke_signing_key(tap._b1(), 'incident', 0, 'ck177-rv') $q$, 'F4a: PFA-18B revoke of the recovered key runs (single-control emergency, untouched by 111)');
SELECT is((SELECT status FROM kernel.signing_key WHERE key_id = tap._b1()), 'revoked', 'F4b: …and the recovered key is now revoked');
SELECT tap.logout();
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery('00000000-0000-0000-0000-0000000000b2', tap._fp_b(), 'incident', 'ck177-F5') $q$,
  '%insufficient_privilege%', 'F5: (logged out) approve still requires an authenticated platform_admin');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.approve_signing_key_recovery('00000000-0000-0000-0000-0000000000b2', tap._fp_b(), 'incident', 'ck177-F6') $q$,
  '%recovery_lineage_exceeded%', 'F6: TWO revoked globals ⇒ a second-generation recovery is refused (beyond the ratified lineage)');
SELECT tap.logout();
SELECT throws_like($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES ('00000000-0000-0000-0000-0000000000b2', 'global', null, null, tap._pem177_b(), tap._arn177_b(), 'ES256', 'active', now(), null) $q$,
  '%recovery_lineage_exceeded%', 'F7: …and the guard refuses the bare INSERT for the same reason');
SELECT throws_like($q$ UPDATE kernel.signing_key_recovery_approval SET expires_at = now() + interval '1 year' $q$,
  '%append_only%', 'F8: approvals are append-only (no UPDATE)');
SELECT throws_like($q$ DELETE FROM kernel.signing_key_recovery_approval $q$,
  '%append_only%', 'F9: approvals are append-only (no DELETE)');

-- ── G. expiry window + guard-level checks on a fresh lineage (savepoint) ────
SAVEPOINT fresh;
-- reset keyring to "exactly one revoked" by removing the recovered row as superuser via a savepoint-scoped detour:
ALTER TABLE kernel.signing_key DISABLE TRIGGER tg_signing_key_immutable;
DELETE FROM kernel.signing_key WHERE key_id = tap._b1();
ALTER TABLE kernel.signing_key ENABLE TRIGGER tg_signing_key_immutable;
SELECT is((SELECT count(*)::int FROM kernel.signing_key WHERE status = 'revoked'), 1, 'G1: (fixture) exactly one revoked global again');
-- two approvals for a NEW key_id, one of them EXPIRED (inserted as superuser with a past window)
ALTER TABLE kernel.signing_key_recovery_approval DISABLE TRIGGER tg_signing_key_recovery_approval_append_only;
INSERT INTO kernel.signing_key_recovery_approval (key_id, public_key_fingerprint, approver_identity, approver_aal, reason_code, command_key, approved_at, expires_at)
VALUES ('00000000-0000-0000-0000-0000000000b3', tap._fp_b(), tap.admin_user(), 'aal2', 'incident', 'ck177-G-old', now() - interval '40 minutes', now() - interval '10 minutes'),
       ('00000000-0000-0000-0000-0000000000b3', tap._fp_b(), tap.other_user(), 'aal2', 'incident', 'ck177-G-new', now(), now() + interval '30 minutes');
ALTER TABLE kernel.signing_key_recovery_approval ENABLE TRIGGER tg_signing_key_recovery_approval_append_only;
SELECT throws_like($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES ('00000000-0000-0000-0000-0000000000b3', 'global', null, null, tap._pem177_b(), tap._arn177_b(), 'ES256', 'active', now(), null) $q$,
  '%post_revoke_recovery_unapproved%', 'G2: one EXPIRED + one live approval do not satisfy the two-person window');
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT throws_like($q$ SELECT kernel.execute_signing_key_recovery('00000000-0000-0000-0000-0000000000b3', tap._pem177_b(), tap._arn177_b(), 'incident', 'ck177-G3') $q$,
  '%post_revoke_recovery_unapproved%', 'G3: execute is refused for the same reason');
SELECT tap.logout();
-- an EdDSA / scoped / wrong-fingerprint insert is still refused even with two live approvals
ALTER TABLE kernel.signing_key_recovery_approval DISABLE TRIGGER tg_signing_key_recovery_approval_append_only;
INSERT INTO kernel.signing_key_recovery_approval (key_id, public_key_fingerprint, approver_identity, approver_aal, reason_code, command_key, approved_at, expires_at)
VALUES ('00000000-0000-0000-0000-0000000000b3', tap._fp_b(), tap.buyer(), 'aal2', 'incident', 'ck177-G-third', now(), now() + interval '30 minutes');
ALTER TABLE kernel.signing_key_recovery_approval ENABLE TRIGGER tg_signing_key_recovery_approval_append_only;
SELECT throws_like($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES ('00000000-0000-0000-0000-0000000000b3', 'global', null, null, tap._pem177_b(), tap._arn177_b(), 'EdDSA', 'active', now(), null) $q$,
  '%algorithm_not_es256%', 'G4: two live approvals never let an EdDSA row through');
SELECT throws_like($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES ('00000000-0000-0000-0000-0000000000b3', 'per_event', gen_random_uuid(), null, tap._pem177_b(), tap._arn177_b(), 'ES256', 'active', now(), null) $q$,
  '%scoped_key_parked%', 'G5: …nor a scoped row');
SELECT throws_like($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES ('00000000-0000-0000-0000-0000000000b3', 'global', null, null, tap._pem177_a(), tap._arn177_b(), 'ES256', 'active', now(), null) $q$,
  '%post_revoke_recovery_unapproved%', 'G6: …nor a different public key than the one approved (fingerprint-bound)');
SELECT lives_ok($q$ INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES ('00000000-0000-0000-0000-0000000000b3', 'global', null, null, tap._pem177_b(), tap._arn177_b(), 'ES256', 'active', now(), null) $q$,
  'G7: with two LIVE distinct approvals the guard admits the approved key (the approvals ARE the control)');
ROLLBACK TO SAVEPOINT fresh;
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 2, 'G8: transaction rollback restored the two-row lineage (b0 revoked, b1 revoked)');

-- ── H. rollback/replay of 111 on a savepoint ────────────────────────────────
SAVEPOINT before_rollback;
DROP FUNCTION IF EXISTS kernel.execute_signing_key_recovery(uuid,text,text,text,text);
DROP FUNCTION IF EXISTS kernel.approve_signing_key_recovery(uuid,text,text,text);
DROP TABLE IF EXISTS kernel.signing_key_recovery_approval;
DROP FUNCTION IF EXISTS kernel.signing_key_p256_pem_fingerprint(text);
SELECT ok(to_regclass('kernel.signing_key_recovery_approval') IS NULL, 'H1: after the 111 rollback statements the approval table is gone');
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_insert_guard'), 1,
  'H2: the 110 guard trigger remains (the rollback file re-creates the 110 body — rehearsed file-level by the harness)');
ROLLBACK TO SAVEPOINT before_rollback;
SELECT ok(to_regclass('kernel.signing_key_recovery_approval') IS NOT NULL, 'H3: rolling the rollback back restores 111 (replay-safe DDL)');

SELECT * FROM finish();
ROLLBACK;
