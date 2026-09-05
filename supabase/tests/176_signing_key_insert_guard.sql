-- ============================================================================
-- 176_signing_key_insert_guard.sql — migration 110 (M6, PFA-18C pre-issuance).
--   The BEFORE INSERT guard on kernel.signing_key admits ONLY the ratified global
--   ES256 bootstrap lineage: positive §6.1-shaped bootstrap; scoped rows,
--   non-active status, wrong/defaulted algorithm, malformed ARN, malformed/wrong-
--   type/compressed PEM, private material, duplicate key_id, a second active
--   global, a first row that is not the ruling-B key_id, and ANY insert after a
--   revoke (recovery parked, fail closed) are refused with named codes. The
--   immutable UPDATE guard and the parked lifecycle functions are unchanged.
--   Rollback/replay is exercised on a savepoint (the file-level rollback +
--   re-apply is rehearsed by the harness, see the execution record).
--
--   This suite deliberately does NOT call tap.seed_core(): seed_core disables
--   this guard for legacy fixture inserts (rehearsal-only harness plumbing,
--   000_helpers.sql), and here the guard must be LIVE. Every insert below runs
--   as the rehearsal superuser — the exact principal the bare-INSERT threat
--   model is about.
-- ============================================================================
BEGIN;
SELECT plan(51);

-- ── fixtures (throwaway public keys generated with openssl for this suite) ───
CREATE FUNCTION tap._pem176_p256() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==
-----END PUBLIC KEY-----
$p$ $f$;
CREATE FUNCTION tap._pem176_p256_compressed() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MDkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDIgADo7hfdCPypem8qEenAzd0mmD0GgSS
OF3URrfCTerouHQ=
-----END PUBLIC KEY-----
$p$ $f$;
CREATE FUNCTION tap._pem176_ed25519() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT $p$-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAOXCGAFeE94Hf0fMjmKfqtS+CKCvauv8AZOs8mUiMc7U=
-----END PUBLIC KEY-----
$p$ $f$;
CREATE FUNCTION tap._arn176() RETURNS text LANGUAGE sql IMMUTABLE AS $f$ SELECT 'arn:aws:kms:us-east-1:652872010073:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b' $f$;
CREATE FUNCTION tap._b0() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '00000000-0000-0000-0000-0000000000b0'::uuid $f$;
CREATE FUNCTION tap._b1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT '00000000-0000-0000-0000-0000000000b1'::uuid $f$;

-- The §6.1-shaped INSERT (explicit column list, explicit algorithm). Parameters
-- let each case perturb exactly one thing.
CREATE FUNCTION tap._ins176(p_key uuid, p_scope text, p_event uuid, p_venue uuid, p_pem text, p_arn text, p_alg text, p_status text)
RETURNS void LANGUAGE sql AS $f$
  INSERT INTO kernel.signing_key (key_id, scope, event_id, venue_id, public_key, kms_handle_ref, algorithm, status, not_before, not_after)
  VALUES (p_key, p_scope, p_event, p_venue, p_pem, p_arn, p_alg, p_status, now(), null)
$f$;
-- Same, but WITHOUT the algorithm column — lets the 103 default apply.
CREATE FUNCTION tap._ins176_default_alg(p_key uuid) RETURNS void LANGUAGE sql AS $f$
  INSERT INTO kernel.signing_key (key_id, scope, public_key, kms_handle_ref, status, not_before)
  VALUES (p_key, 'global', tap._pem176_p256(), tap._arn176(), 'active', now())
$f$;

-- ── A. structure ─────────────────────────────────────────────────────────────
SELECT has_function('kernel'::name, 'guard_signing_key_insert'::name, 'A1: kernel.guard_signing_key_insert() exists (110)');
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_insert_guard' AND NOT tgisinternal), 1,
  'A2: tg_signing_key_insert_guard exists on kernel.signing_key');
SELECT ok((SELECT (t.tgtype & 2) = 2 AND (t.tgtype & 4) = 4 AND (t.tgtype & 1) = 1 FROM pg_trigger t WHERE t.tgrelid = 'kernel.signing_key'::regclass AND t.tgname = 'tg_signing_key_insert_guard'),
  'A3: it is BEFORE INSERT … FOR EACH ROW');
SELECT is((SELECT tgenabled FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_insert_guard'), 'O',
  'A4: the guard is ENABLED (origin) as shipped — this suite runs against the live guard');
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_immutable' AND NOT tgisinternal), 1,
  'A5: the 083/103 immutable BEFORE UPDATE guard is still present (110 touches only INSERT)');
SELECT ok(NOT has_function_privilege('anon', 'kernel.guard_signing_key_insert()', 'EXECUTE')
       AND NOT has_function_privilege('authenticated', 'kernel.guard_signing_key_insert()', 'EXECUTE')
       AND NOT has_function_privilege('service_role', 'kernel.guard_signing_key_insert()', 'EXECUTE'),
  'A6: zero-grant — anon/authenticated/service_role cannot execute the guard directly');
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 0, 'A7: precondition — the rehearsal keyring is empty');

-- ── B. refusals that fire BEFORE any existence check (empty keyring) ────────
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'per_event', gen_random_uuid(), null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%scoped_key_parked%', 'B1: per_event insert refused — scoped keys are parked (fires before the scope_target FK/CHECK)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'per_venue', null, gen_random_uuid(), tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%scoped_key_parked%', 'B2: per_venue insert refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'rotating') $q$,
  '%status_must_be_active%', 'B3: status rotating refused (rotation is parked)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'revoked') $q$,
  '%status_must_be_active%', 'B4: status revoked refused (terminal state is never inserted)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'EdDSA', 'active') $q$,
  '%algorithm_not_es256%', 'B5: explicit EdDSA refused — ratified contract is ES256, no override');
SELECT throws_like($q$ SELECT tap._ins176_default_alg(tap._b0()) $q$,
  '%algorithm_not_es256%', 'B6: OMITTED algorithm (103 default EdDSA) refused — P1-ALGO-DEFAULT closed');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), '1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active') $q$,
  '%kms_handle_not_key_arn%', 'B7: bare key id refused (D4 requires the full ARN)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), 'arn:aws:kms:us-east-1:652872010073:alias/snatchit-signer', 'ES256', 'active') $q$,
  '%kms_handle_not_key_arn%', 'B8: alias ARN refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), 'arn:aws:kms:us-east-1:65287201007:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active') $q$,
  '%kms_handle_not_key_arn%', 'B9: 11-digit account refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), 'arn:aws:kms:US-EAST-1:652872010073:key/1b2c3d4e-5f60-4718-8a9b-0c1d2e3f4a5b', 'ES256', 'active') $q$,
  '%kms_handle_not_key_arn%', 'B10: malformed region refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), 'arn:aws:kms:us-east-1:652872010073:key/not-a-uuid', 'ES256', 'active') $q$,
  '%kms_handle_not_key_arn%', 'B11: non-UUID key id refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, 'PUBKEY-PLACEHOLDER', tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_spki_pem%', 'B12: placeholder public_key refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSSOF3URrfCTerouHSWiARzxx7TdWySJhKwFvhcdh8MkgdjmysEJXFDVa8Nuw==', tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_spki_pem%', 'B13: bare base64 (no PEM armor) refused — D3 is PEM');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, regexp_replace(tap._pem176_p256(), '-----END PUBLIC KEY-----', ''), tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_spki_pem%', 'B14: PEM missing END line refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, replace(tap._pem176_p256(), 'PUBLIC KEY', 'CERTIFICATE'), tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_spki_pem%', 'B15: other PEM label refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256() || tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_spki_pem%', 'B16: two concatenated PEM blocks refused (exactly one block)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, E'-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo7hfdCPypem8qEenAzd0mmD0GgSSx\n-----END PUBLIC KEY-----\n', tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_p256_uncompressed%', 'B17: PEM whose body is base64-charset but not decodable (bad length) is refused — the decode error is caught and the refusal is named');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, E'-----BEGIN PUBLIC KEY-----\n!!!!not base64!!!!\n-----END PUBLIC KEY-----\n', tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_spki_pem%', 'B17b: a PEM body outside the base64 charset never reaches decode — refused as not an SPKI PEM block');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_ed25519(), tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_p256_uncompressed%', 'B18: Ed25519 SPKI PEM refused under ES256 (algorithm pinned to the key bytes)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256_compressed(), tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_not_p256_uncompressed%', 'B19: compressed-point P-256 SPKI refused (only the canonical 91-byte uncompressed form)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, E'-----BEGIN PRIVATE KEY-----\nMIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg\n-----END PRIVATE KEY-----\n', tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_private_material%', 'B20: a PRIVATE KEY PEM is refused as private material (before any PEM parsing)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256() || E'-----BEGIN EC PRIVATE KEY-----\nabc\n-----END EC PRIVATE KEY-----\n', tap._arn176(), 'ES256', 'active') $q$,
  '%public_key_private_material%', 'B21: a valid public block followed by private material is refused');
SELECT throws_like($q$ SELECT tap._ins176(tap._b1(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%bootstrap_key_id_required%', 'B22: on an EMPTY keyring a valid row with a non-bootstrap key_id is refused (lineage)');
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 0, 'B23: nothing was written by any refused insert');

-- ── C. positive bootstrap (the §6.1 shape) ───────────────────────────────────
SELECT lives_ok($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  'C1: the sanctioned bootstrap row (key_id …b0, global, ES256, full ARN, P-256 SPKI PEM, active, not_after NULL) is ACCEPTED');
SELECT is((SELECT count(*)::int FROM kernel.signing_key WHERE scope = 'global' AND status = 'active'), 1, 'C2: exactly one active global row');
SELECT is((SELECT algorithm FROM kernel.signing_key WHERE key_id = tap._b0()), 'ES256', 'C3: stored algorithm is ES256');
SELECT is((SELECT encode(sha256(decode(regexp_replace(public_key, '-----(BEGIN|END) PUBLIC KEY-----|[[:space:]]', '', 'g'), 'base64')), 'hex') FROM kernel.signing_key WHERE key_id = tap._b0()),
  '08ec5757ea9e0f694a0e4e59c0c2b98d2da9cde838659cd707167b36cc5e7174',
  'C4: the stored PEM yields the D5 fingerprint openssl computed over the DER (the fingerprint contract is preserved)');

-- ── D. with an active global present ─────────────────────────────────────────
SELECT throws_like($q$ SELECT tap._ins176(tap._b1(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%active_global_exists%', 'D1: a second valid global row is refused by the guard (named), before the partial unique index');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%duplicate_key_id%', 'D2: re-inserting the bootstrap key_id is refused as duplicate_key_id (named, ahead of the PK)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b1(), 'per_event', gen_random_uuid(), null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%scoped_key_parked%', 'D3: a scoped row is still refused when a global is active (it would shadow it at the next mint)');
SELECT is((SELECT count(*)::int FROM kernel.signing_key), 1, 'D4: still exactly one row');

-- ── E. lifecycle parking + immutable UPDATE guard unchanged ─────────────────
SELECT throws_like($q$ SELECT kernel.provision_signing_key('global', null, 'x', 'x', now(), 'r', 'ck176-p') $q$,
  '%dual_control_unavailable%', 'E1: provision_signing_key still parked (083 body untouched)');
SELECT throws_like($q$ SELECT kernel.rotate_signing_key(tap._b0(), 'x', 'x', 'r', 'ck176-r') $q$,
  '%dual_control_unavailable%', 'E2: rotate_signing_key still parked');
SELECT throws_like($q$ UPDATE kernel.signing_key SET public_key = tap._pem176_ed25519() WHERE key_id = tap._b0() $q$,
  '%append_only%', 'E3: the immutable UPDATE guard still refuses a public_key change');
SELECT throws_like($q$ UPDATE kernel.signing_key SET algorithm = 'EdDSA' WHERE key_id = tap._b0() $q$,
  '%append_only%', 'E4: …and an algorithm re-label');

-- ── F. revoked global — recovery preconditions (FAIL CLOSED) ─────────────────
SELECT lives_ok($q$ UPDATE kernel.signing_key SET status = 'revoked' WHERE key_id = tap._b0() $q$,
  'F1: active → revoked is permitted by the UPDATE guard (what 106 revoke does)');
SELECT throws_like($q$ SELECT tap._ins176(tap._b1(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%post_revoke_recovery_parked%', 'F2: a structurally valid replacement row after a revoke is REFUSED — recovery is parked until the two-person artifact ships');
SELECT throws_like($q$ SELECT tap._ins176(tap._b0(), 'global', null, null, tap._pem176_p256(), tap._arn176(), 'ES256', 'active') $q$,
  '%duplicate_key_id%', 'F3: re-using the revoked key_id is refused as duplicate (append-only)');
SELECT throws_like($q$ UPDATE kernel.signing_key SET status = 'active' WHERE key_id = tap._b0() $q$,
  '%append_only%', 'F4: revoked is terminal (UPDATE guard)');
SELECT is((SELECT count(*)::int FROM kernel.signing_key WHERE status = 'active'), 0, 'F5: zero active keys remain — issuance would fail closed (no_active_signing_key)');

-- ── G. rollback/replay on a savepoint ────────────────────────────────────────
SAVEPOINT before_rollback;
DROP TRIGGER IF EXISTS tg_signing_key_insert_guard ON kernel.signing_key;
DROP FUNCTION IF EXISTS kernel.guard_signing_key_insert();
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_insert_guard'), 0,
  'G1: after the rollback statements the guard is gone');
SELECT lives_ok($q$ INSERT INTO kernel.signing_key (scope, event_id, public_key, kms_handle_ref, status, not_before, algorithm)
  SELECT 'per_event', e.event_id, 'PUBKEY-LEGACY', 'kms-legacy', 'active', now(), 'EdDSA' FROM catalog.event e LIMIT 0 $q$,
  'G2: with the guard rolled back, a legacy-shaped statement is accepted by the table again (0 rows here; the legacy fixtures in suites 143–175 prove the write path)');
ROLLBACK TO SAVEPOINT before_rollback;
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'kernel.signing_key'::regclass AND tgname = 'tg_signing_key_insert_guard'), 1,
  'G3: rolling the rollback back restores the guard (replay-safe: 110 uses create-or-replace + drop-if-exists)');

SELECT * FROM finish();
ROLLBACK;
