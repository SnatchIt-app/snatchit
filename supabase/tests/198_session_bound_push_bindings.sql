-- 198_session_bound_push_bindings.sql — migration 131: a push binding lives no
-- longer than the credentials that created it. Every state below is produced
-- the way production produces it (the verb, the direct client path, a password
-- change on auth.users, session rows deleted the way GoTrue deletes them); no
-- assertion passes for the wrong reason — each has a negative control against
-- a 130-only database (run this file there: sections C–K must fail).
-- Runs as postgres inside BEGIN … ROLLBACK. Sessions are auth.sessions rows
-- inserted as postgres (the harness stand-in; GoTrue writes them on hosted) and
-- named in request.jwt.claims.session_id exactly as a Supabase access token
-- carries it.
BEGIN;
SELECT plan(45);
SELECT tap.seed_core();

-- ── helpers (test-local; dropped by the ROLLBACK) ───────────────────────────
CREATE TABLE tap.kv198 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._s198(k text, v text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO tap.kv198 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $$;
CREATE FUNCTION tap._g198(k text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM tap.kv198 WHERE kv198.k = _g198.k $$;
CREATE FUNCTION tap._u198(k text) RETURNS uuid LANGUAGE sql AS $$ SELECT v::uuid FROM tap.kv198 WHERE kv198.k = _u198.k $$;
-- a session for a user, created at a chosen instant; returns its id.
-- A "fresh login after a credential change" is modelled honestly: wait out the
-- X4 margin on the real clock, then create the row at clock_timestamp() —
-- never at a fabricated future instant, which would collide with LATER epochs
-- inside this one frozen-now() transaction.
CREATE FUNCTION tap._fresh198(p_uid uuid) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_sleep(2.2);
  RETURN tap._sess198(p_uid, clock_timestamp());
END $$;
CREATE FUNCTION tap._sess198(p_uid uuid, p_made timestamptz, p_not_after timestamptz DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at, not_after, aal) VALUES (v, p_uid, p_made, p_made, p_not_after, 'aal1');
  RETURN v;
END $$;
-- sign in as a user ON a session: claims carry session_id as the access token does
CREATE FUNCTION tap._login198(p_uid uuid, p_sid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims',
    (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || jsonb_build_object('session_id', p_sid::text))::text, true);
END $$;
CREATE FUNCTION tap._epoch198(p_uid uuid) RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE v timestamptz;
BEGIN
  -- dynamic so this file also RUNS on a 130-only database (the negative control)
  EXECUTE 'SELECT push_binding_epoch FROM kernel.identity_ext WHERE identity_id = $1' INTO v USING p_uid;
  RETURN v;
EXCEPTION WHEN undefined_column THEN
  RETURN NULL;
END $$;
CREATE FUNCTION tap._h198(s text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT encode(pg_catalog.sha256(pg_catalog.convert_to(s, 'utf8')), 'hex') $$;
CREATE FUNCTION tap._row198(t text) RETURNS public.push_tokens LANGUAGE sql AS $$
  SELECT * FROM public.push_tokens WHERE token = t $$;
-- run one statement as the current role and report the SQLSTATE (or 'ok')
CREATE FUNCTION tap._try198(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE stmt; RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLSTATE || ' ' || SQLERRM;
END $$;

-- ── A. shape and grants ─────────────────────────────────────────────────────
SELECT has_column('kernel', 'identity_ext', 'push_binding_epoch', 'A1: the credential epoch column exists');
SELECT has_trigger('auth', 'users', 'trg_push_bindings_on_password_change', 'A2: password change is watched on auth.users');
SELECT has_trigger('auth', 'sessions', 'trg_push_bindings_on_sessions_gone', 'A3: session deletion is watched on auth.sessions');
SELECT has_trigger('public', 'push_tokens', 'trg_guard_push_token_session_stmt', 'A4: the statement-level lock guard is on push_tokens');
SELECT has_trigger('public', 'push_tokens', 'trg_guard_push_token_session_row', 'A5: the row-level session guard is on push_tokens');
-- OID form throughout section A: a missing function yields NULL → "not ok", never an abort,
-- so the same file discriminates on a 130-only database (the negative control).
SELECT ok(has_function_privilege('authenticated', to_regprocedure('public.revoke_all_push_bindings()'), 'EXECUTE')
      AND NOT has_function_privilege('anon', to_regprocedure('public.revoke_all_push_bindings()'), 'EXECUTE')
      AND NOT has_function_privilege('service_role', to_regprocedure('public.revoke_all_push_bindings()'), 'EXECUTE'),
  'A6: revoke_all_push_bindings — EXECUTE authenticated only');
SELECT ok(to_regprocedure('public.guard_push_token_session_stmt()') IS NOT NULL
      AND NOT has_function_privilege('authenticated', to_regprocedure('public.guard_push_token_session_stmt()'), 'EXECUTE')
      AND NOT has_function_privilege('authenticated', to_regprocedure('public.guard_push_token_session_row()'), 'EXECUTE')
      AND NOT has_function_privilege('authenticated', to_regprocedure('kernel.invalidate_push_bindings_for(uuid, text, timestamptz)'), 'EXECUTE')
      AND NOT has_function_privilege('authenticated', to_regprocedure('kernel.push_session_predates_epoch(uuid)'), 'EXECUTE')
      AND NOT has_function_privilege('anon', to_regprocedure('kernel.invalidate_push_bindings_for(uuid, text, timestamptz)'), 'EXECUTE')
      AND NOT has_function_privilege('service_role', to_regprocedure('kernel.invalidate_push_bindings_for(uuid, text, timestamptz)'), 'EXECUTE'),
  'A7: the guards and the kernel routines are not client-executable (nor service_role for the invalidator)');
SELECT ok(has_function_privilege('authenticated', to_regprocedure('public.register_push_token(text, text, text, text)'), 'EXECUTE')
      AND NOT has_function_privilege('anon', to_regprocedure('public.register_push_token(text, text, text, text)'), 'EXECUTE'),
  'A8: register_push_token keeps contract v2''s grant');

-- ── B. before any credential change: nothing changes for the client ─────────
SELECT tap._s198('S1', tap._sess198(tap.buyer(), now() - interval '1 hour')::text);
SELECT tap._login198(tap.buyer(), tap._u198('S1'));
SELECT is((public.register_push_token('ExponentPushToken[198-buyer-aaaaaaaaaaaa]', 'ios', 'secret-198-buyer-0123456789', 'iPhone') ->> 'outcome'),
  'registered', 'B1: a device registers on an ordinary session');
SELECT lives_ok($$ UPDATE public.push_tokens SET last_used = now() WHERE token = 'ExponentPushToken[198-buyer-aaaaaaaaaaaa]' $$,
  'B2: the shipped client''s own write still works');
SELECT tap.logout();
SELECT is(tap._epoch198(tap.buyer()), NULL, 'B3: no credential change yet — the epoch is NULL');

-- ── C. password change (P1): every binding revoked, every proof cleared ─────
UPDATE auth.users SET encrypted_password = 'x131-new-hash', updated_at = now() WHERE id = tap.buyer();
SELECT ok(NOT (tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).is_active, 'C1: the binding is inactive after a password change');
SELECT is((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).revoked_reason, 'password_changed', 'C2: ...with reason password_changed (never signed_out — rule 5 cannot hand it over)');
SELECT is((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).device_secret_hash, NULL, 'C3: ...and the device proof is CLEARED');
SELECT ok((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).revoked_at IS NOT NULL, 'C4: ...revoked_at set — the notify send path''s authoritative predicate');
SELECT ok(tap._epoch198(tap.buyer()) > (SELECT created_at FROM auth.sessions WHERE id = tap._u198('S1')), 'C5: the epoch now postdates the old session');

-- ── D. the old session cannot recreate anything (P3, X2) ────────────────────
SELECT tap._login198(tap.buyer(), tap._u198('S1'));
SELECT throws_ok($$ SELECT public.register_push_token('ExponentPushToken[198-buyer-aaaaaaaaaaaa]', 'ios', 'secret-198-buyer-0123456789', 'iPhone') $$,
  '42501', 'insufficient_privilege: session predates a credential change', 'D1: the verb refuses a session older than the epoch, in the contract''s words');
SELECT throws_ok($$ INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES ('$$ || tap.buyer() || $$', 'ExponentPushToken[198-buyer-bbbbbbbbbbbb]', 'ios', true) $$,
  '42501', NULL, 'D2: the direct INSERT path (old clients) is refused from the old session');
SELECT throws_ok($$ UPDATE public.push_tokens SET is_active = true WHERE token = 'ExponentPushToken[198-buyer-aaaaaaaaaaaa]' $$,
  '42501', NULL, 'D3: re-activating by direct UPDATE is refused from the old session');
SELECT throws_ok($$ DELETE FROM public.push_tokens WHERE token = 'ExponentPushToken[198-buyer-aaaaaaaaaaaa]' $$,
  '42501', NULL, 'D4 (X2): DELETE is refused from the old session — no delete-then-rebind after a credential change');
SELECT lives_ok($$ UPDATE public.push_tokens SET last_used = now() WHERE token = 'ExponentPushToken[198-buyer-aaaaaaaaaaaa]' $$,
  'D5: a write that neither creates, activates nor deletes is not gated');
SELECT tap.logout();

-- ── E. a new session works and re-proves the device (P7) ────────────────────
SELECT tap._s198('S2', tap._fresh198(tap.buyer())::text);
SELECT tap._login198(tap.buyer(), tap._u198('S2'));
SELECT is((public.register_push_token('ExponentPushToken[198-buyer-aaaaaaaaaaaa]', 'ios', 'secret-198-buyer-0123456789', 'iPhone') ->> 'outcome'),
  'refreshed', 'E1: a session created after the epoch registers');
SELECT tap.logout();
SELECT is((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).device_secret_hash, tap._h198('secret-198-buyer-0123456789'),
  'E2: ...and the device''s GENUINE proof is adopted onto the cleared row');
SELECT ok((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).is_active, 'E3: ...active again');

-- ── F. a dormant planted proof dies at the credential change (P4) ───────────
-- A legacy hash-less row the attacker plants on from the victim's session.
INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (tap.buyer(), 'ExponentPushToken[198-legacy-cccccccccccc]', 'ios', true);
SELECT tap._login198(tap.buyer(), tap._u198('S2'));
SELECT is((public.register_push_token('ExponentPushToken[198-legacy-cccccccccccc]', 'ios', 'attacker-secret-0123456789', 'iPhone') ->> 'outcome'),
  'refreshed', 'F1: the attacker, holding the victim''s session, plants a proof on the legacy row');
SELECT tap.logout();
SELECT is((tap._row198('ExponentPushToken[198-legacy-cccccccccccc]')).device_secret_hash, tap._h198('attacker-secret-0123456789'), 'F1b: ...the planted hash is stored (the dormant capture)');
UPDATE auth.users SET encrypted_password = 'x131-newer-hash', updated_at = now() WHERE id = tap.buyer();
SELECT is((tap._row198('ExponentPushToken[198-legacy-cccccccccccc]')).device_secret_hash, NULL, 'F2: the password change clears the plant');
SELECT tap._s198('SA', tap._sess198(tap.other_user(), now() - interval '1 hour')::text);
SELECT tap._login198(tap.other_user(), tap._u198('SA'));
SELECT throws_ok($$ SELECT public.register_push_token('ExponentPushToken[198-legacy-cccccccccccc]', 'ios', 'attacker-secret-0123456789', 'Pixel') $$,
  '42501', 'insufficient_privilege: token is bound to another account', 'F3: the attacker cannot activate the plant from their own account — the capture never fires');
SELECT tap.logout();

-- ── G. forwarding dies and cannot be re-established from the old session (P5)
SELECT tap._s198('S3', tap._fresh198(tap.buyer())::text);
SELECT tap._login198(tap.buyer(), tap._u198('S3'));
SELECT is((public.register_push_token('ExponentPushToken[198-attacker-phone-dddd]', 'android', 'attacker-phone-secret-0123456789', 'Pixel') ->> 'outcome'),
  'registered', 'G1: the attacker binds their own phone to the victim (forwarding)');
SELECT tap.logout();
UPDATE auth.users SET encrypted_password = 'x131-third-hash', updated_at = now() WHERE id = tap.buyer();
SELECT ok(NOT (tap._row198('ExponentPushToken[198-attacker-phone-dddd]')).is_active, 'G2: the forwarding binding is revoked by the credential change');
SELECT tap._login198(tap.buyer(), tap._u198('S3'));
SELECT throws_ok($$ SELECT public.register_push_token('ExponentPushToken[198-attacker-phone-dddd]', 'android', 'attacker-phone-secret-0123456789', 'Pixel') $$,
  '42501', 'insufficient_privilege: session predates a credential change', 'G3: ...and the compromised session cannot re-establish it');
SELECT tap.logout();

-- ── H. revoke_all succeeds from ANY session (§4f), bumps the epoch ──────────
SELECT tap._s198('E_before', tap._epoch198(tap.buyer())::text);
SELECT tap._login198(tap.buyer(), tap._u198('S3'));                   -- S3 is now an OLD session
SELECT is(tap._try198('SELECT public.revoke_all_push_bindings()'), 'ok', 'H1: revoke_all_push_bindings works from a session older than the epoch (§4f)');
SELECT is((public.revoke_push_token('ExponentPushToken[198-buyer-aaaaaaaaaaaa]') ->> 'revoked') IS NOT NULL, true, 'H2: the ordinary revoke verb (129) also works from an old session — revocation only reduces exposure');
SELECT tap.logout();
SELECT ok(tap._epoch198(tap.buyer()) > tap._g198('E_before')::timestamptz, 'H3: revoke_all bumped the epoch again');

-- ── I. global sign-out: the LAST live session gone invalidates; cleanup does not (X5, S13)
SELECT tap._s198('S4', tap._fresh198(tap.buyer())::text);
SELECT tap._s198('S5', tap._sess198(tap.buyer(), clock_timestamp())::text);
-- the earlier sessions are gone the way they would be after their own sign-outs;
-- S4 and S5 remain live, so this delete must NOT invalidate (asserted in I2's spirit by I1 passing after it)
DELETE FROM auth.sessions WHERE user_id = tap.buyer() AND id NOT IN (tap._u198('S4'), tap._u198('S5'));
SELECT tap._login198(tap.buyer(), tap._u198('S4'));
SELECT is((public.register_push_token('ExponentPushToken[198-buyer-aaaaaaaaaaaa]', 'ios', 'secret-198-buyer-0123456789', 'iPhone') ->> 'outcome'),
  'refreshed', 'I1: re-registered on a fresh session (precondition)');
SELECT tap.logout();
DELETE FROM auth.sessions WHERE id = tap._u198('S4');
SELECT ok((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).is_active, 'I2: one device signing out while another session is live does NOT revoke');
SELECT tap._s198('E_i', tap._epoch198(tap.buyer())::text);
DELETE FROM auth.sessions WHERE id = tap._u198('S5');
SELECT is((tap._row198('ExponentPushToken[198-buyer-aaaaaaaaaaaa]')).revoked_reason, 'signed_out_everywhere', 'I3: the last live session gone = sign-out-everywhere → every binding revoked');
SELECT ok(tap._epoch198(tap.buyer()) > tap._g198('E_i')::timestamptz, 'I4: ...and the epoch bumped');
SELECT tap._s198('E_j', tap._epoch198(tap.buyer())::text);
SELECT tap._s198('S6', tap._sess198(tap.buyer(), now() - interval '2 days', now() - interval '1 day')::text);   -- expired
DELETE FROM auth.sessions WHERE id = tap._u198('S6');
SELECT is(tap._epoch198(tap.buyer()), tap._g198('E_j')::timestamptz, 'I5: expired-session cleanup is NOT a sign-out — the epoch does not move');

-- ── J. fail closed without a session claim, only once an epoch exists ───────
SELECT tap.login(tap.buyer());                                          -- claims without session_id
SELECT throws_ok($$ SELECT public.register_push_token('ExponentPushToken[198-buyer-aaaaaaaaaaaa]', 'ios', 'secret-198-buyer-0123456789', 'iPhone') $$,
  '42501', 'insufficient_privilege: session predates a credential change', 'J1: a token with no session_id is refused once the account has an epoch (fail closed)');
SELECT tap.logout();
SELECT tap.login(tap.other_user());                                     -- other_user: no epoch ever
SELECT is((public.register_push_token('ExponentPushToken[198-other-eeeeeeeeeeee]', 'ios', 'secret-198-other-0123456789', 'Pixel') ->> 'outcome'),
  'registered', 'J2: an account with no credential change is untouched by 131, session claim or not');

-- ── K. ordinary sign-out is unchanged (P6) ──────────────────────────────────
SELECT is((public.revoke_push_token('ExponentPushToken[198-other-eeeeeeeeeeee]') ->> 'revoked'), '1', 'K1: the ordinary per-device revoke still works');
SELECT tap.logout();
SELECT is(tap._epoch198(tap.other_user()), NULL, 'K2: ...and it does not touch the epoch — other devices keep their bindings');

-- ── L. account deletion still works (D, F-131-1) ─────────────────────────────
-- DELETE auth.users cascades to auth.sessions, which fires the invalidator for a
-- user who is mid-deletion. At 38c4d8d the invalidator INSERTed identity_ext for
-- that user and the FK aborted the WHOLE delete: a user with a live session and
-- no identity_ext row (077 creates it lazily — many users) could not be deleted
-- by GoTrue's admin API or the Dashboard. identity_ext rows themselves block a
-- delete pre-131 (ON DELETE RESTRICT), so the fixture user must have none.
INSERT INTO auth.users (id, email) VALUES ('11111111-1111-1111-1111-000000000198', 'del198@example.test');
SELECT tap._s198('SD', tap._sess198('11111111-1111-1111-1111-000000000198', now() - interval '1 hour')::text);
SELECT is((SELECT count(*)::int FROM kernel.identity_ext WHERE identity_id = '11111111-1111-1111-1111-000000000198'), 0,
  'L1: the fixture user has a live session and no identity_ext row (the failing shape)');
SELECT lives_ok($$ DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-000000000198' $$,
  'L2: deleting that user succeeds — the cascade-fired invalidator does not insert an epoch for a user being deleted');

SELECT * FROM finish();
ROLLBACK;
