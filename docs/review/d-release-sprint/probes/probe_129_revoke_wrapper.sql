-- D attack on 129 public.revoke_push_token (A's working tree). Local clone DB; BEGIN…ROLLBACK.
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d1290000-0000-4000-8000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w1@test.local','{"provider":"email"}','{}',now(),now()),
 ('d1290000-0000-4000-8000-0000000000b2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','w2@test.local','{"provider":"email"}','{}',now(),now());
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO anon, authenticated;
SELECT tap.login('d1290000-0000-4000-8000-0000000000a1');
SELECT public.register_push_token('ExponentPushToken[w1]','ios','w1-secret-000000000000','x');
SELECT tap.logout();
SELECT tap.login('d1290000-0000-4000-8000-0000000000b2');
SELECT public.register_push_token('ExponentPushToken[w2]','ios','w2-secret-000000000000','x');
-- IDOR: user 2 revokes user 1's token by string
INSERT INTO o(k,v) SELECT 'idor.user2_revokes_user1_token', public.revoke_push_token('ExponentPushToken[w1]')::text;
-- own token
INSERT INTO o(k,v) SELECT 'own.user2_revokes_own', public.revoke_push_token('ExponentPushToken[w2]')::text;
INSERT INTO o(k,v) SELECT 'own.repeat_is_idempotent', public.revoke_push_token('ExponentPushToken[w2]')::text;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT 'state.user1_row', concat_ws('|', is_active, revoked_at IS NULL, coalesce(revoked_reason,'<null>'), device_secret_hash IS NOT NULL) FROM public.push_tokens WHERE token='ExponentPushToken[w1]';
INSERT INTO o(k,v) SELECT 'state.user2_row', concat_ws('|', is_active, revoked_at IS NULL, coalesce(revoked_reason,'<null>'), device_secret_hash IS NOT NULL) FROM public.push_tokens WHERE token='ExponentPushToken[w2]';
-- anon
SELECT tap.login_anon();
SAVEPOINT a; SELECT public.revoke_push_token('ExponentPushToken[w1]'); ROLLBACK TO SAVEPOINT a;
SELECT tap.logout();
-- service_role through the wrapper
SELECT tap.login_service();
SAVEPOINT s; SELECT public.revoke_push_token('ExponentPushToken[w1]'); ROLLBACK TO SAVEPOINT s;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT 'grants anon|authenticated|service_role|public', concat_ws('|', has_function_privilege('anon','public.revoke_push_token(text)','EXECUTE'), has_function_privilege('authenticated','public.revoke_push_token(text)','EXECUTE'), has_function_privilege('service_role','public.revoke_push_token(text)','EXECUTE'), (SELECT coalesce(array_to_string(proacl,','),'') FROM pg_proc WHERE oid='public.revoke_push_token(text)'::regprocedure));
INSERT INTO o(k,v) SELECT 'definer|search_path', (SELECT prosecdef::text||'|'||coalesce(array_to_string(proconfig,','),'') FROM pg_proc WHERE oid='public.revoke_push_token(text)'::regprocedure);
-- the revoked own row is NOT rule-5 claimable by a token-knower (post-128 row, hashed)
SELECT tap.login('d1290000-0000-4000-8000-0000000000a1');
SAVEPOINT r5; INSERT INTO o(k,v) SELECT 'rule5.user1_claims_user2_signed_out_row', public.register_push_token('ExponentPushToken[w2]','ios','guess-secret-0000000000','x')::text; ROLLBACK TO SAVEPOINT r5;
SELECT tap.logout();
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
