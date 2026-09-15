-- D attacks on 131 @ 38c4d8d. Certified-harness DB (auth.sessions stand-in); BEGIN…ROLLBACK.
-- Sessions are auth.sessions rows; claims carry session_id like a Supabase access token.
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO anon, authenticated, service_role;
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $$ SELECT ('d1310000-0000-4000-8000-00000000000'||i)::uuid $$;
CREATE FUNCTION pg_temp.sess(p_uid uuid, p_made timestamptz, p_not_after timestamptz DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at, not_after, aal) VALUES (v, p_uid, p_made, p_made, p_not_after, 'aal1'); RETURN v; END $$;
CREATE FUNCTION pg_temp.login(p_uid uuid, p_sid uuid) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims', (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || jsonb_build_object('session_id', p_sid::text))::text, true); END $$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid) TO authenticated;
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','v131@test.local','old-hash','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','a131@test.local','a-hash','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(3),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','d131@test.local','d-hash','{"provider":"email"}','{}',now(),now());
SELECT set_config('d.vs', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '1 hour')::text, true);   -- victim's phone session
SELECT set_config('d.as_v', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '30 minutes')::text, true); -- attacker's stolen victim session
SELECT set_config('d.a', pg_temp.sess(pg_temp.u(2), clock_timestamp() - interval '1 hour')::text, true);    -- attacker's own session

-- setup: victim phone registers; attacker (with victim's session) forwards to own phone and plants on a hash-less victim row
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.vs')::uuid);
SELECT public.register_push_token('ExponentPushToken[v131-phone]','ios','v131-secret-000000000000','iPhone');
INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (pg_temp.u(1),'ExponentPushToken[v131-legacy]','android',true);
SELECT tap.logout();
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.as_v')::uuid);
INSERT INTO o(k,v) SELECT 'setup.plant_on_legacy', public.register_push_token('ExponentPushToken[v131-legacy]','android','attacker-plant-0000000000','x')::text;
INSERT INTO o(k,v) SELECT 'setup.forward_attacker_phone', public.register_push_token('ExponentPushToken[a131-phone]','ios','attacker-phone-00000000000','x')::text;
SELECT tap.logout();
-- completed redirect (X1): victim row deleted with the stolen session, token bound to attacker's account
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.as_v')::uuid);
SELECT public.register_push_token('ExponentPushToken[v131-tablet]','ios','v131-tablet-secret-000000','iPad');
DELETE FROM public.push_tokens WHERE token='ExponentPushToken[v131-tablet]';
SELECT tap.logout();
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.a')::uuid);
INSERT INTO o(k,v) SELECT 'setup.redirect_tablet_to_attacker', public.register_push_token('ExponentPushToken[v131-tablet]','ios','attacker-tablet-0000000000','x')::text;
SELECT tap.logout();

-- P1: password change (GoTrue-shaped UPDATE)
UPDATE auth.users SET encrypted_password = 'new-hash', updated_at = now() WHERE id = pg_temp.u(1);
INSERT INTO o(k,v) SELECT 'P1.victim_rows', string_agg(token||':'||is_active||':'||(device_secret_hash IS NULL)||':'||coalesce(revoked_reason,'-'), ' ' ORDER BY token) FROM public.push_tokens WHERE user_id = pg_temp.u(1);
INSERT INTO o(k,v) SELECT 'P1.epoch_set', (push_binding_epoch IS NOT NULL)::text FROM kernel.identity_ext WHERE identity_id = pg_temp.u(1);

-- S3/X2: the stolen old session after the change
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.as_v')::uuid);
SAVEPOINT a1; SELECT public.register_push_token('ExponentPushToken[a131-phone]','ios','attacker-phone-00000000000','x'); ROLLBACK TO SAVEPOINT a1;
SAVEPOINT a2; INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (pg_temp.u(1),'ExponentPushToken[a131-phone-2]','ios',true); ROLLBACK TO SAVEPOINT a2;
SAVEPOINT a3; UPDATE public.push_tokens SET is_active = true WHERE token='ExponentPushToken[v131-phone]'; ROLLBACK TO SAVEPOINT a3;
SAVEPOINT a4; DELETE FROM public.push_tokens WHERE token='ExponentPushToken[v131-phone]'; ROLLBACK TO SAVEPOINT a4;
SAVEPOINT a5; WITH i AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (pg_temp.u(1),'ExponentPushToken[a131-inactive]','ios',false) RETURNING 1) INSERT INTO o(k,v) SELECT 'S3.old_session_insert_inactive_rows', count(*)::text FROM i; ROLLBACK TO SAVEPOINT a5;
INSERT INTO o(k,v) SELECT 'S2f.revoke_all_from_old_session', public.revoke_all_push_bindings()::text;
SELECT tap.logout();

-- P4/P5: dormant plant and forwarding are dead; attacker claim from own account
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.a')::uuid);
SAVEPOINT b1; INSERT INTO o(k,v) SELECT 'P4.attacker_claims_planted_legacy', public.register_push_token('ExponentPushToken[v131-legacy]','android','attacker-plant-0000000000','x')::text; ROLLBACK TO SAVEPOINT b1;
SAVEPOINT b2; INSERT INTO o(k,v) SELECT 'P5.attacker_reclaims_forwarded_phone', public.register_push_token('ExponentPushToken[a131-phone]','ios','attacker-phone-00000000000','x')::text; ROLLBACK TO SAVEPOINT b2;
SELECT tap.logout();
-- X1 still UNCLOSED
INSERT INTO o(k,v) SELECT 'X1.tablet_binding_after_victim_P1', concat_ws('|', CASE WHEN user_id=pg_temp.u(2) THEN 'ATTACKER' ELSE user_id::text END, is_active) FROM public.push_tokens WHERE token='ExponentPushToken[v131-tablet]';

-- P7: legitimate new session (after the margin) re-registers the phone
SELECT pg_sleep(2.3);
SELECT set_config('d.vnew', pg_temp.sess(pg_temp.u(1), clock_timestamp())::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.vnew')::uuid);
INSERT INTO o(k,v) SELECT 'P7.new_session_phone', (public.register_push_token('ExponentPushToken[v131-phone]','ios','v131-secret-000000000000','iPhone') ->> 'outcome');
SAVEPOINT c1; INSERT INTO o(k,v) SELECT 'X1.victim_new_session_tablet', public.register_push_token('ExponentPushToken[v131-tablet]','ios','v131-tablet-secret-000000','iPad')::text; ROLLBACK TO SAVEPOINT c1;
SELECT tap.logout();

-- X5 edge cases on user 3
SELECT set_config('d.d1', pg_temp.sess(pg_temp.u(3), clock_timestamp() - interval '1 hour')::text, true);
SELECT set_config('d.d2', pg_temp.sess(pg_temp.u(3), clock_timestamp() - interval '1 hour')::text, true);
SELECT set_config('d.dx', pg_temp.sess(pg_temp.u(3), clock_timestamp() - interval '2 days', now() - interval '1 day')::text, true);
SELECT pg_temp.login(pg_temp.u(3), current_setting('d.d1')::uuid);
SELECT public.register_push_token('ExponentPushToken[d131]','ios','d131-secret-00000000000000','x');
SELECT tap.logout();
DELETE FROM auth.sessions WHERE id = current_setting('d.dx')::uuid;
INSERT INTO o(k,v) SELECT 'X5.expired_only_deleted_epoch', coalesce((SELECT push_binding_epoch IS NOT NULL FROM kernel.identity_ext WHERE identity_id=pg_temp.u(3))::text,'no-row');
DELETE FROM auth.sessions WHERE id = current_setting('d.d2')::uuid;
INSERT INTO o(k,v) SELECT 'X5.one_of_two_live_deleted_active', is_active::text FROM public.push_tokens WHERE token='ExponentPushToken[d131]';
DELETE FROM auth.sessions WHERE id = current_setting('d.d1')::uuid;
INSERT INTO o(k,v) SELECT 'X5.last_live_deleted_active|hash_null', concat_ws('|', is_active, device_secret_hash IS NULL) FROM public.push_tokens WHERE token='ExponentPushToken[d131]';

-- A17: deleting a user that still has a live session and bindings (cascade + session trigger)
SELECT set_config('d.a2', pg_temp.sess(pg_temp.u(2), clock_timestamp())::text, true);
SAVEPOINT del; DELETE FROM auth.users WHERE id = pg_temp.u(2);
INSERT INTO o(k,v) SELECT 'A17.user_delete_ok_rows_left', (SELECT count(*)::text FROM public.push_tokens WHERE user_id = pg_temp.u(2));
ROLLBACK TO SAVEPOINT del;
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
