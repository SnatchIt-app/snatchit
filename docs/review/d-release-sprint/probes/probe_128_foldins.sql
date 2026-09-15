-- D-R128 fold-in probes (cf73d7b). Local rehearsal DB only; BEGIN…ROLLBACK; states via the real verb.
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d1280000-0000-4000-8000-00000000000a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','d128a@test.local','{"provider":"email"}','{}',now(),now()),
 ('d1280000-0000-4000-8000-00000000000b','00000000-0000-0000-0000-000000000000','authenticated','authenticated','d128b@test.local','{"provider":"email"}','{}',now(),now());
CREATE TEMP TABLE o (k text, v text) ON COMMIT DROP; GRANT ALL ON o TO authenticated, service_role, anon;

-- G1: the write-guard is re-armed after the verb returns (same transaction)
SELECT tap.login('d1280000-0000-4000-8000-00000000000a');
INSERT INTO o SELECT 'G1.register', public.register_push_token('ExponentPushToken[d128-fold-a]','ios','fold-secret-0123456789','iPhone')::text;
INSERT INTO o SELECT 'G1.guc_after_return', coalesce(nullif(current_setting('app.push_token_verb', true), ''), '<empty>');
SAVEPOINT s1;
UPDATE public.push_tokens SET device_secret_hash = 'attacker-chosen' WHERE token = 'ExponentPushToken[d128-fold-a]';
ROLLBACK TO SAVEPOINT s1;
-- G2: equality oracle — UPDATE with the TRUE hash passes the guard (row count), a wrong one raises
SAVEPOINT s2;
WITH u AS (UPDATE public.push_tokens SET device_secret_hash = encode(sha256(convert_to('fold-secret-0123456789','utf8')),'hex')
            WHERE token = 'ExponentPushToken[d128-fold-a]' RETURNING 1) INSERT INTO o SELECT 'G2.update_with_true_hash_rows', count(*)::text FROM u;
RELEASE SAVEPOINT s2;
SAVEPOINT s3;
UPDATE public.push_tokens SET device_secret_hash = encode(sha256(convert_to('wrong-guess-0123456789','utf8')),'hex') WHERE token = 'ExponentPushToken[d128-fold-a]';
ROLLBACK TO SAVEPOINT s3;
SELECT tap.logout();

-- G3: rule 3 rebind by another account holding the device secret heals THAT caller
SELECT tap.login('d1280000-0000-4000-8000-00000000000b');
INSERT INTO o SELECT 'G3.rebind', public.register_push_token('ExponentPushToken[d128-fold-a]','ios','fold-secret-0123456789','iPhone')::text;
SELECT tap.logout();
-- G4: epoch immutability as service_role
SELECT tap.login_service();
SAVEPOINT e1; UPDATE public.push_token_rebind_epoch SET applied_at = now() + interval '1 year'; ROLLBACK TO SAVEPOINT e1;
SAVEPOINT e2; DELETE FROM public.push_token_rebind_epoch; ROLLBACK TO SAVEPOINT e2;
SAVEPOINT e3; TRUNCATE public.push_token_rebind_epoch; ROLLBACK TO SAVEPOINT e3;
SAVEPOINT e4; INSERT INTO public.push_token_rebind_epoch (singleton, applied_at) VALUES (true, now()); ROLLBACK TO SAVEPOINT e4;
SELECT tap.logout();
-- G5: client reads of the epoch
SELECT tap.login('d1280000-0000-4000-8000-00000000000a');
SAVEPOINT c1; SELECT * FROM public.push_token_rebind_epoch; ROLLBACK TO SAVEPOINT c1;
SELECT tap.logout();
INSERT INTO o SELECT 'G6.epoch_row_count_unchanged', count(*)::text FROM public.push_token_rebind_epoch;
SELECT k, v FROM o ORDER BY k;
ROLLBACK;
