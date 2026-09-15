-- D O-3 comparison: the same outcome as plant-then-claim WITHOUT a plant (delete as victim, register as attacker).
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d0310000-0000-4000-8000-00000000000f','00000000-0000-0000-0000-000000000000','authenticated','authenticated','victim2@test.local','{"provider":"email"}','{}',now(),now()),
 ('d0310000-0000-4000-8000-00000000000a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','attacker2@test.local','{"provider":"email"}','{}',now(),now());
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO authenticated;
SELECT tap.login('d0310000-0000-4000-8000-00000000000f');
INSERT INTO o(k,v) SELECT '3a.victim_registers_with_real_secret', public.register_push_token('ExponentPushToken[victim2-phone]','ios','victim2-secret-S_v-00','iPhone')::text;
-- attacker holds V's session: deletes V's own row (RLS owner DELETE)
WITH d AS (DELETE FROM public.push_tokens WHERE token='ExponentPushToken[victim2-phone]' RETURNING 1) INSERT INTO o(k,v) SELECT '3b.delete_as_victim_rows', count(*)::text FROM d;
SELECT tap.logout();
SELECT tap.login('d0310000-0000-4000-8000-00000000000a');
INSERT INTO o(k,v) SELECT '3c.register_as_attacker', public.register_push_token('ExponentPushToken[victim2-phone]','ios','attacker2-secret-S_a-0','x')::text;
SELECT tap.logout();
SELECT tap.login('d0310000-0000-4000-8000-00000000000f');
SAVEPOINT s; INSERT INTO o(k,v) SELECT '3d.victim_cold_launch', public.register_push_token('ExponentPushToken[victim2-phone]','ios','victim2-secret-S_v-00','iPhone')::text; ROLLBACK TO SAVEPOINT s;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT '3e.binding_now', user_id::text FROM public.push_tokens WHERE token='ExponentPushToken[victim2-phone]';
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
