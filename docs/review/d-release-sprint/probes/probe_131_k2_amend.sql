-- D: A-131-K2 amendment (131 @ f72e2d3) — session_id stamp integrity, legacy rule-5 exposure, expired-session cleanup.
-- Local certified-harness DB; BEGIN…ROLLBACK; results SELECTed as they happen.
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $$ SELECT ('d1330000-0000-4000-8000-00000000000'||i)::uuid $$;
CREATE FUNCTION pg_temp.sess(p_uid uuid, p_made timestamptz, p_not_after timestamptz DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at, not_after, aal) VALUES (v, p_uid, p_made, p_made, p_not_after, 'aal1'); RETURN v; END $$;
CREATE FUNCTION pg_temp.login(p_uid uuid, p_sid uuid) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims', (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || jsonb_build_object('session_id', p_sid::text))::text, true); END $$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE||': '||SQLERRM; END $$;
CREATE FUNCTION pg_temp.st(p_token text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT (SELECT email FROM auth.users WHERE id = t.user_id)||'|active='||t.is_active||'|hash='||(t.device_secret_hash IS NOT NULL)||'|reason='||coalesce(t.revoked_reason,'-')
                     FROM public.push_tokens t WHERE t.token = p_token), 'absent') $$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text), pg_temp.st(text), pg_temp.u(int) TO authenticated, service_role;
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','victim@k2a.local','h1','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','other@k2a.local','h2','{"provider":"email"}','{}',now(),now());
SELECT set_config('d.old', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '1 hour')::text, true);   -- old-build device
SELECT set_config('d.keep', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '1 hour')::text, true);  -- another device stays in
SELECT set_config('d.two', pg_temp.sess(pg_temp.u(2), clock_timestamp() - interval '1 hour')::text, true);

-- A. stamp integrity (client paths)
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.old')::uuid);
SELECT 'A1.client_insert_naming_session_id', pg_temp.try($q$WITH x AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active, session_id) VALUES (auth.uid(), 'ExponentPushToken[k2a-forge]', 'ios', true, gen_random_uuid()) RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'A2.client_insert_without_session_id', pg_temp.try($q$WITH x AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (auth.uid(), 'ExponentPushToken[k2a-plain]', 'ios', true) RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'A3.client_select_session_id', pg_temp.try($q$SELECT session_id::text FROM public.push_tokens WHERE token = 'ExponentPushToken[k2a-plain]'$q$);
SELECT 'A4.client_update_session_id', pg_temp.try($q$WITH x AS (UPDATE public.push_tokens SET session_id = gen_random_uuid() WHERE token = 'ExponentPushToken[k2a-plain]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT tap.logout();
SELECT 'A1b.forged_value_overwritten_with_caller_session', ((SELECT session_id FROM public.push_tokens WHERE token = 'ExponentPushToken[k2a-forge]') = current_setting('d.old')::uuid)::text;
SELECT 'A5.stamped_with_caller_session', ((SELECT session_id FROM public.push_tokens WHERE token = 'ExponentPushToken[k2a-plain]') = current_setting('d.old')::uuid)::text;

-- B. legacy (pre-128, hash-less) row: does a per-session revocation make it rule-5 claimable by another account?
--    Shape: a row created before the 128 epoch, revoked earlier, re-activated by an OLD client's direct UPDATE (no verb, no hash).
SET LOCAL session_replication_role = replica;   -- fixture only: back-date created_at (local superuser harness)
INSERT INTO public.push_tokens (user_id, token, platform, is_active, created_at, revoked_at, revoked_reason)
VALUES (pg_temp.u(1), 'ExponentPushToken[k2a-legacy]', 'android', false, (SELECT applied_at FROM public.push_token_rebind_epoch) - interval '10 days', now() - interval '1 day', 'device_not_registered');
SET LOCAL session_replication_role = origin;
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.old')::uuid);
SELECT 'B1.old_client_reactivates_legacy_row', pg_temp.try($q$WITH x AS (UPDATE public.push_tokens SET is_active = true WHERE token = 'ExponentPushToken[k2a-legacy]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT tap.logout();
SELECT 'B1.legacy_before', pg_temp.st('ExponentPushToken[k2a-legacy]');
DELETE FROM auth.sessions WHERE id = current_setting('d.old')::uuid;             -- that device's session ends (another stays live)
SELECT 'B2.legacy_after_session_delete', pg_temp.st('ExponentPushToken[k2a-legacy]');
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.two')::uuid);
SELECT 'B3.other_account_claims_by_token_knowledge', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2a-legacy]','android','attacker-secret-0000000000','x')->>'outcome'$q$);
SELECT tap.logout();
SELECT 'B4.legacy_final', pg_temp.st('ExponentPushToken[k2a-legacy]');

-- C. expired-session cleanup (not_after in the past) of a device's own session while another is live
SELECT set_config('d.exp', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '2 hours', clock_timestamp() + interval '1 hour')::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.exp')::uuid);
SELECT 'C1.register_on_timeboxed_session', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2a-exp]','ios','k2a-exp-secret-000000000','x')->>'outcome'$q$);
SELECT tap.logout();
UPDATE auth.sessions SET not_after = clock_timestamp() - interval '1 minute' WHERE id = current_setting('d.exp')::uuid;   -- timebox passes
DELETE FROM auth.sessions WHERE id = current_setting('d.exp')::uuid;                                                       -- cleanup
SELECT 'C2.binding_after_expired_cleanup', pg_temp.st('ExponentPushToken[k2a-exp]');
ROLLBACK;
