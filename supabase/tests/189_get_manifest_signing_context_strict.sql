-- ============================================================================
-- 189_get_manifest_signing_context_strict.sql — migration 121 (PFA-18C forward
-- fix for 114 L121). Focused regression: the row read inside
-- venue.get_manifest_signing_context() is STRICT with no_data_found /
-- too_many_rows mapped to the stable unavailable codes; the non-STRICT form is
-- gone; signature, definer/search_path shape, grants and the 0-row / 1-row /
-- rotated behaviours are unchanged from 114 (suite 180 still passes). The race
-- itself (a status flip between the count and the read) cannot be interleaved
-- inside one pgTAP transaction; STRICT semantics are Postgres-guaranteed, so the
-- regression pins the definition (A) and the observable contract (C).
-- ============================================================================
BEGIN;
SELECT plan(19);
SELECT tap.seed_core();

CREATE TABLE tap.memo_189 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store189(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_189 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._fetch189(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_189 WHERE k=$1 $m$;
SELECT tap._store189('def', pg_get_functiondef('venue.get_manifest_signing_context()'::regprocedure));

-- ── A. definition ────────────────────────────────────────────────────────────
SELECT has_function('venue'::name, 'get_manifest_signing_context'::name, '{}'::name[], 'A1: venue.get_manifest_signing_context() exists');
SELECT ok(tap._fetch189('def') ~ 'select \* into strict v_k from kernel\.signing_key', 'A2: the row read is STRICT (121)');
SELECT ok(tap._fetch189('def') !~ 'select \* into v_k from kernel\.signing_key', 'A3: the 114 non-STRICT read is gone');
SELECT ok(tap._fetch189('def') ~ 'when no_data_found then' AND tap._fetch189('def') ~ 'no_active_global_key', 'A4: no_data_found maps to no_active_global_key');
SELECT ok(tap._fetch189('def') ~ 'when too_many_rows then' AND tap._fetch189('def') ~ 'ambiguous_active_global_key', 'A5: too_many_rows maps to ambiguous_active_global_key');

-- ── B. shape and grants unchanged ────────────────────────────────────────────
SELECT ok(has_function_privilege('service_role', 'venue.get_manifest_signing_context()', 'EXECUTE'), 'B1: service_role keeps EXECUTE');
SELECT ok(NOT has_function_privilege('authenticated', 'venue.get_manifest_signing_context()', 'EXECUTE'), 'B2: authenticated has no EXECUTE');
SELECT ok(NOT has_function_privilege('anon', 'venue.get_manifest_signing_context()', 'EXECUTE'), 'B3: anon has no EXECUTE');
SELECT ok((SELECT p.prosecdef AND p.proconfig::text LIKE '%search_path=%' AND p.provolatile = 's' AND (p.prorettype::regtype)::text = 'jsonb'
             FROM pg_proc p WHERE p.oid = 'venue.get_manifest_signing_context()'::regprocedure),
  'B4: SECURITY DEFINER, search_path pinned, STABLE, returns jsonb (unchanged)');

-- ── C. observable contract (fixture as in 180: guard disabled by seed_core; placeholder PEM) ──
SELECT tap.login_service();
SELECT tap._store189('ctx0', venue.get_manifest_signing_context()::text);
SELECT tap.logout();
SELECT is((tap._fetch189('ctx0')::jsonb ->> 'status'), 'unavailable', 'C1: no active global key → unavailable');
SELECT is((tap._fetch189('ctx0')::jsonb ->> 'code'), 'no_active_global_key', 'C2: …stable code no_active_global_key');

WITH k AS (INSERT INTO kernel.signing_key (scope, public_key, kms_handle_ref, status, not_before, not_after, algorithm)
  VALUES ('global', 'PEM-G-189', 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b89', 'active', now() - interval '1 hour', NULL, 'ES256') RETURNING key_id)
SELECT tap._store189('g', (SELECT key_id::text FROM k));
SELECT tap.login_service();
SELECT tap._store189('ctx1', venue.get_manifest_signing_context()::text);
SELECT tap.logout();
SELECT is((tap._fetch189('ctx1')::jsonb ->> 'status'), 'ok', 'C3: one active global key → ok');
SELECT is((tap._fetch189('ctx1')::jsonb ->> 'key_id'), tap._fetch189('g'), 'C4: key_id = that row');
SELECT is((tap._fetch189('ctx1')::jsonb ->> 'kms_handle_ref'), 'arn:aws:kms:us-east-1:000000000000:key/0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b89', 'C5: kms_handle_ref from the same row');
SELECT is((tap._fetch189('ctx1')::jsonb ->> 'algorithm'), 'ES256', 'C6: algorithm ES256');
SELECT is((tap._fetch189('ctx1')::jsonb ->> 'public_key'), 'PEM-G-189', 'C7: public_key from the same row');

UPDATE kernel.signing_key SET status = 'rotating' WHERE key_id = tap._fetch189('g')::uuid;
SELECT tap.login_service();
SELECT tap._store189('ctx2', venue.get_manifest_signing_context()::text);
SELECT tap.logout();
SELECT is((tap._fetch189('ctx2')::jsonb ->> 'status') || '/' || (tap._fetch189('ctx2')::jsonb ->> 'code'), 'unavailable/no_active_global_key',
  'C8: after the status flip the context is unavailable with the stable code, never an ok payload of NULLs');

-- ── D. census / identity ─────────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'venue' AND p.proname = 'get_manifest_signing_context'), 1,
  'D1: exactly one venue.get_manifest_signing_context (body-only replace; census 0)');
SELECT ok(obj_description('venue.get_manifest_signing_context()'::regprocedure, 'pg_proc') LIKE '%121: the row read is STRICT%',
  'D2: the comment records the 121 change');

SELECT * FROM finish();
ROLLBACK;
