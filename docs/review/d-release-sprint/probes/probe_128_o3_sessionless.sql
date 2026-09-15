-- D O-3 §3 challenge: any session-less way to plant a hash or seize a victim's row? (anon role, no JWT subject)
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d0320000-0000-4000-8000-00000000000f','00000000-0000-0000-0000-000000000000','authenticated','authenticated','victim3@test.local','{"provider":"email"}','{}',now(),now());
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO anon, authenticated;
SELECT tap.login('d0320000-0000-4000-8000-00000000000f');
INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES ('d0320000-0000-4000-8000-00000000000f','ExponentPushToken[victim3-legacy]','ios',true);
SELECT tap.logout();
SELECT tap.login_anon();
SAVEPOINT a1; INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES ('d0320000-0000-4000-8000-00000000000f','ExponentPushToken[anon-insert]','ios',true); ROLLBACK TO SAVEPOINT a1;
SAVEPOINT a2; WITH d AS (DELETE FROM public.push_tokens WHERE token='ExponentPushToken[victim3-legacy]' RETURNING 1) INSERT INTO o(k,v) SELECT 'anon.delete_rows', count(*)::text FROM d; RELEASE SAVEPOINT a2;
SAVEPOINT a3; WITH u AS (UPDATE public.push_tokens SET is_active=false WHERE token='ExponentPushToken[victim3-legacy]' RETURNING 1) INSERT INTO o(k,v) SELECT 'anon.update_rows', count(*)::text FROM u; RELEASE SAVEPOINT a3;
SAVEPOINT a4; SELECT public.register_push_token('ExponentPushToken[victim3-legacy]','ios','anon-secret-0000000000','x'); ROLLBACK TO SAVEPOINT a4;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT 'victim_row_after_anon', concat_ws('|', user_id, is_active, coalesce(device_secret_hash,'<null>')) FROM public.push_tokens WHERE token='ExponentPushToken[victim3-legacy]';
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
