-- D review of the 129 DESIGN (no 129 SQL yet): does §2e's invalidation reach a redirect COMPLETED during the compromise?
-- Runs on 128 @ f22c1a3 and applies §2e's stated effect for the victim by hand (as the definer would).
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d1290000-0000-4000-8000-00000000000f','00000000-0000-0000-0000-000000000000','authenticated','authenticated','v129@test.local','{"provider":"email"}','{}',now(),now()),
 ('d1290000-0000-4000-8000-00000000000a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','a129@test.local','{"provider":"email"}','{}',now(),now());
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO authenticated;
-- victim device registers properly (hashed)
SELECT tap.login('d1290000-0000-4000-8000-00000000000f');
INSERT INTO o(k,v) SELECT 'r1.victim_register', public.register_push_token('ExponentPushToken[v129]','ios','v129-secret-0000000000','iPhone')::text;
-- during the compromise: attacker deletes the victim's row with the victim's session…
WITH d AS (DELETE FROM public.push_tokens WHERE token='ExponentPushToken[v129]' RETURNING 1) INSERT INTO o(k,v) SELECT 'r2.delete_as_victim', count(*)::text FROM d;
SELECT tap.logout();
-- …and binds the victim's token to the attacker's own account
SELECT tap.login('d1290000-0000-4000-8000-00000000000a');
INSERT INTO o(k,v) SELECT 'r3.register_as_attacker', public.register_push_token('ExponentPushToken[v129]','ios','a129-secret-0000000000','x')::text;
SELECT tap.logout();
-- victim changes password → §2e for the VICTIM: revoke the victim's rows, clear hashes (by hand, as the design specifies)
SELECT set_config('app.push_token_verb','on',true);
UPDATE public.push_tokens SET is_active=false, revoked_at=now(), revoked_reason='password_changed', device_secret_hash=NULL WHERE user_id='d1290000-0000-4000-8000-00000000000f';
SELECT set_config('app.push_token_verb','',true);
INSERT INTO o(k,v) SELECT 'r4.after_invalidation_binding', concat_ws('|', user_id, is_active, device_secret_hash IS NOT NULL) FROM public.push_tokens WHERE token='ExponentPushToken[v129]';
-- victim's legitimate device on a NEW session re-registers
SELECT tap.login('d1290000-0000-4000-8000-00000000000f');
SAVEPOINT s; INSERT INTO o(k,v) SELECT 'r5.victim_new_session_register', public.register_push_token('ExponentPushToken[v129]','ios','v129-secret-0000000000','iPhone')::text; ROLLBACK TO SAVEPOINT s;
SELECT tap.logout();
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
