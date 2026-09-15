-- D: K-2 server invalidation contract on 131 @ f102ce2 (owner approved: ordinary "Sign out" = this device's session only;
-- separate "Sign out of all devices"). Certified-harness DB with auth.sessions stand-in; BEGIN…ROLLBACK.
-- GoTrue's logout is emulated by its SQL effect: scope=local deletes the current session row, scope=global deletes all of the
-- user's session rows in ONE statement, scope=others deletes all but the current one. Password change = UPDATE encrypted_password.
\set ON_ERROR_STOP 0
BEGIN;
SELECT tap.seed_core();
-- results are SELECTed as they happen (rows inserted inside a savepoint would be rolled back)
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $$ SELECT ('d1320000-0000-4000-8000-00000000000'||i)::uuid $$;
CREATE FUNCTION pg_temp.sess(p_uid uuid, p_made timestamptz) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id, user_id, created_at, updated_at, not_after, aal) VALUES (v, p_uid, p_made, p_made, NULL, 'aal1'); RETURN v; END $$;
CREATE FUNCTION pg_temp.login(p_uid uuid, p_sid uuid) RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  PERFORM tap.login(p_uid);
  PERFORM set_config('request.jwt.claims', (coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb || jsonb_build_object('session_id', p_sid::text))::text, true); END $$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r, 'ok'); EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE||': '||SQLERRM; END $$;
CREATE FUNCTION pg_temp.st(p_token text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT (SELECT email FROM auth.users WHERE id = t.user_id)||'|active='||t.is_active||'|hash='||(t.device_secret_hash IS NOT NULL)||'|reason='||coalesce(t.revoked_reason,'-')
                     FROM public.push_tokens t WHERE t.token = p_token), 'absent') $$;
CREATE FUNCTION pg_temp.ep(p_uid uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT push_binding_epoch::text FROM kernel.identity_ext WHERE identity_id = p_uid), 'NULL') $$;
CREATE FUNCTION pg_temp.deliverable(p_uid uuid) RETURNS text LANGUAGE sql AS $$   -- the send path's selection: is_active
  SELECT coalesce(string_agg(token, ',' ORDER BY token), '-') FROM public.push_tokens WHERE user_id = p_uid AND is_active $$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text), pg_temp.st(text), pg_temp.ep(uuid), pg_temp.deliverable(uuid), pg_temp.u(int) TO authenticated, service_role;
INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','one@k2.local','h1','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','two@k2.local','h2','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(3),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','solo@k2.local','h3','{"provider":"email"}','{}',now(),now());
SELECT set_config('d.p', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '1 hour')::text, true);  -- account one: phone
SELECT set_config('d.t', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '1 hour')::text, true);  -- account one: tablet
SELECT set_config('d.w', pg_temp.sess(pg_temp.u(1), clock_timestamp() - interval '1 hour')::text, true);  -- account one: web (no push)
SELECT set_config('d.two', pg_temp.sess(pg_temp.u(2), clock_timestamp() - interval '1 hour')::text, true); -- account two, same phone install
SELECT set_config('d.solo', pg_temp.sess(pg_temp.u(3), clock_timestamp() - interval '1 hour')::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.p')::uuid);
SELECT 'setup.phone', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-phone]','ios','k2-phone-install-secret-00','iPhone')->>'outcome'$q$);
SELECT tap.logout();
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.t')::uuid);
SELECT 'setup.tablet', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT tap.logout();
SELECT pg_temp.login(pg_temp.u(3), current_setting('d.solo')::uuid);
SELECT 'setup.solo', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-solo]','android','k2-solo-install-secret-000','Pixel')->>'outcome'$q$);
SELECT tap.logout();

-- ── K1  ordinary sign-out, revoke call succeeds (phone) ─────────────────────────────────────────────────
SAVEPOINT k1;
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.p')::uuid);
SELECT 'K1.revoke_push_token(phone)', pg_temp.try($q$SELECT public.revoke_push_token('ExponentPushToken[k2-phone]')::text$q$);
SELECT tap.logout();
DELETE FROM auth.sessions WHERE id = current_setting('d.p')::uuid;                     -- GoTrue scope=local
SELECT * FROM (VALUES ('K1.phone', pg_temp.st('ExponentPushToken[k2-phone]')), ('K1.tablet', pg_temp.st('ExponentPushToken[k2-tablet]')),
  ('K1.deliverable(one)', pg_temp.deliverable(pg_temp.u(1))), ('K1.epoch(one)', pg_temp.ep(pg_temp.u(1)))) v(k,v);
-- K1b same install, different account, after an ordinary sign-out: the kept proof hands the device over (rule 3)
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.two')::uuid);
SELECT 'K1b.account_two_same_install', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-phone]','ios','k2-phone-install-secret-00','iPhone')->>'outcome'$q$);
SELECT tap.logout();
SELECT * FROM (VALUES ('K1b.phone', pg_temp.st('ExponentPushToken[k2-phone]'))) v(k,v);
-- K1c account one signs back in on the phone (new session) after the hand-over: refused, the device belongs to account two now
SELECT set_config('d.p2', pg_temp.sess(pg_temp.u(1), clock_timestamp())::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.p2')::uuid);
SELECT 'K1c.account_one_back_on_phone', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-phone]','ios','k2-phone-install-secret-00','iPhone')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK TO SAVEPOINT k1;

-- ── K2  ordinary sign-out, revoke call FAILS / times out / pre-129 client (tablet); other sessions live ──
SAVEPOINT k2;
DELETE FROM auth.sessions WHERE id = current_setting('d.t')::uuid;                     -- GoTrue scope=local, no revoke first
SELECT * FROM (VALUES ('K2.tablet_after_local_signout_without_revoke', pg_temp.st('ExponentPushToken[k2-tablet]')),
  ('K2.deliverable(one)', pg_temp.deliverable(pg_temp.u(1))), ('K2.epoch(one)', pg_temp.ep(pg_temp.u(1)))) v(k,v);
-- K2b the signed-out tablet's binding can still be written by nobody on the tablet (its session is gone), and outlives it
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.t')::uuid);
SELECT 'K2b.gone_session_revoke', pg_temp.try($q$SELECT public.revoke_push_token('ExponentPushToken[k2-tablet]')::text$q$);
SELECT 'K2b.gone_session_register', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK TO SAVEPOINT k2;

-- ── K3  sign out of all devices (client: revoke_all_push_bindings, then scope=global) ─────────────────────
SAVEPOINT k3;
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.p')::uuid);
SELECT 'K3.revoke_all_push_bindings', pg_temp.try($q$SELECT public.revoke_all_push_bindings()::text$q$);
SELECT tap.logout();
DELETE FROM auth.sessions WHERE user_id = pg_temp.u(1);                               -- GoTrue scope=global, one statement
SELECT * FROM (VALUES ('K3.phone', pg_temp.st('ExponentPushToken[k2-phone]')), ('K3.tablet', pg_temp.st('ExponentPushToken[k2-tablet]')),
  ('K3.deliverable(one)', pg_temp.deliverable(pg_temp.u(1))), ('K3.epoch_set(one)', (pg_temp.ep(pg_temp.u(1)) <> 'NULL')::text),
  ('K3.other_account_untouched(solo)', pg_temp.st('ExponentPushToken[k2-solo]'))) v(k,v);
-- K3a legitimate re-login on the phone: a session created after the epoch registers and re-establishes the proof
SELECT set_config('d.p3', pg_temp.sess(pg_temp.u(1), (SELECT push_binding_epoch FROM kernel.identity_ext WHERE identity_id = pg_temp.u(1)) + interval '1 millisecond')::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.p3')::uuid);
SELECT 'K3a.relogin_phone', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-phone]','ios','k2-phone-install-secret-00','iPhone')->>'outcome'$q$);
SELECT tap.logout();
SELECT * FROM (VALUES ('K3a.phone', pg_temp.st('ExponentPushToken[k2-phone]')), ('K3a.tablet_stays_revoked', pg_temp.st('ExponentPushToken[k2-tablet]'))) v(k,v);
-- K3b inside the 2 s margin (GoTrue clock skew allowance): refused, client retries
SELECT set_config('d.p4', pg_temp.sess(pg_temp.u(1), (SELECT push_binding_epoch FROM kernel.identity_ext WHERE identity_id = pg_temp.u(1)) - interval '1 second')::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.p4')::uuid);
SELECT 'K3b.session_inside_margin', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT tap.logout();
-- S-13 shared install after sign-out-everywhere: account two on the phone install (same install secret)
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.two')::uuid);
SELECT 'S13.account_two_on_tablet_after_global', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT tap.logout();
-- S-13 recovery r1: account one signs in on the tablet (new session), then signs out of this device (revoke keeps the proof); account two takes over
SELECT set_config('d.t2', pg_temp.sess(pg_temp.u(1), (SELECT push_binding_epoch FROM kernel.identity_ext WHERE identity_id = pg_temp.u(1)) + interval '5 milliseconds')::text, true);
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.t2')::uuid);
SELECT 'S13.r1.account_one_relogin_tablet', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT 'S13.r1.account_one_signout_this_device', pg_temp.try($q$SELECT public.revoke_push_token('ExponentPushToken[k2-tablet]')::text$q$);
SELECT tap.logout();
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.two')::uuid);
SELECT 'S13.r1.account_two_takes_tablet', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK TO SAVEPOINT k3;
-- S-13 recovery r2: support unbind (service_role), then account two registers
SAVEPOINT s13r2;
DELETE FROM auth.sessions WHERE user_id = pg_temp.u(1);
SET LOCAL ROLE service_role;
SELECT 'S13.r2.support_unbind', pg_temp.try($q$SELECT public.unbind_push_token('ExponentPushToken[k2-tablet]')::text$q$);
RESET ROLE;
SELECT pg_temp.login(pg_temp.u(2), current_setting('d.two')::uuid);
SELECT 'S13.r2.account_two_after_unbind', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK TO SAVEPOINT s13r2;

-- ── K3o  GoTrue scope=others (not offered by the client): other sessions deleted, current kept ────────────
SAVEPOINT k3o;
DELETE FROM auth.sessions WHERE user_id = pg_temp.u(1) AND id <> current_setting('d.w')::uuid;
SELECT * FROM (VALUES ('K3o.phone', pg_temp.st('ExponentPushToken[k2-phone]')), ('K3o.tablet', pg_temp.st('ExponentPushToken[k2-tablet]')), ('K3o.epoch(one)', pg_temp.ep(pg_temp.u(1)))) v(k,v);
ROLLBACK TO SAVEPOINT k3o;

-- ── K4  password change (GoTrue may or may not delete other sessions; worst case: none deleted) ───────────
SAVEPOINT k4;
UPDATE auth.users SET encrypted_password = 'h1-new', updated_at = now() WHERE id = pg_temp.u(1);
SELECT * FROM (VALUES ('K4.phone', pg_temp.st('ExponentPushToken[k2-phone]')), ('K4.tablet', pg_temp.st('ExponentPushToken[k2-tablet]')),
  ('K4.deliverable(one)', pg_temp.deliverable(pg_temp.u(1))), ('K4.epoch_set(one)', (pg_temp.ep(pg_temp.u(1)) <> 'NULL')::text)) v(k,v);
-- K5 an old session (created before the epoch, not deleted) cannot recreate a binding by verb, direct INSERT, re-activating UPDATE or DELETE
SELECT pg_temp.login(pg_temp.u(1), current_setting('d.t')::uuid);
SELECT 'K5.old_session_verb', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[k2-tablet]','ios','k2-tablet-install-secret-0','iPad')->>'outcome'$q$);
SELECT 'K5.old_session_direct_insert', pg_temp.try($q$INSERT INTO public.push_tokens (user_id, token, platform, is_active) VALUES (auth.uid(), 'ExponentPushToken[k2-new-by-old]', 'ios', true) RETURNING 'inserted'$q$);
SELECT 'K5.old_session_update_activate', pg_temp.try($q$WITH x AS (UPDATE public.push_tokens SET is_active = true WHERE token = 'ExponentPushToken[k2-tablet]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'K5.old_session_delete', pg_temp.try($q$WITH x AS (DELETE FROM public.push_tokens WHERE token = 'ExponentPushToken[k2-tablet]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT 'K5.old_session_revoke_still_allowed', pg_temp.try($q$SELECT public.revoke_push_token('ExponentPushToken[k2-tablet]')::text$q$);
SELECT tap.logout();
ROLLBACK TO SAVEPOINT k4;

-- ── K7  ordinary sign-out of a user's ONLY session = sign-out-everywhere semantics (trigger) ───────────────
SAVEPOINT k7;
DELETE FROM auth.sessions WHERE id = current_setting('d.solo')::uuid;
SELECT * FROM (VALUES ('K7.solo_after_local_signout_of_only_session', pg_temp.st('ExponentPushToken[k2-solo]')), ('K7.epoch_set(solo)', (pg_temp.ep(pg_temp.u(3)) <> 'NULL')::text)) v(k,v);
ROLLBACK TO SAVEPOINT k7;

ROLLBACK;
