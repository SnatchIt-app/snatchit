-- D: after a support unbind, how does the ORIGINAL owner's own device recover?
-- Decides the severity of a socially-engineered unbind during the D-135-6 interim.
\set ON_ERROR_STOP 0
BEGIN;
CREATE FUNCTION pg_temp.sess(p uuid) RETURNS uuid LANGUAGE plpgsql AS $f$ DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id,user_id,created_at,updated_at,aal) VALUES (v,p,now()-interval '1 hour',now()-interval '1 hour','aal1'); RETURN v; END $f$;
CREATE FUNCTION pg_temp.login(p uuid, s uuid) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM tap.login(p);
  PERFORM set_config('request.jwt.claims',(coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb||jsonb_build_object('session_id',s::text))::text,true); END $f$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $f$ DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r,'ok');
EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE||': '||left(SQLERRM,70); END $f$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text) TO authenticated;
INSERT INTO auth.users (id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
VALUES ('d1370000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','victim@d137.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('d.s', pg_temp.sess('d1370000-0000-4000-8000-000000000001')::uuid::text, false);
SELECT pg_temp.login('d1370000-0000-4000-8000-000000000001', current_setting('d.s')::uuid);
SELECT 'U1.owner_registers', public.register_push_token('ExponentPushToken[d137]','ios','victim-secret-00000000','Victim iPhone')->>'outcome';
SELECT tap.logout();
SET LOCAL ROLE service_role;
SELECT 'U2.support_unbinds', public.unbind_push_token('ExponentPushToken[d137]')::text;
RESET ROLE;
-- the victim's own app re-registers on next open, same account, SAME session
SELECT pg_temp.login('d1370000-0000-4000-8000-000000000001', current_setting('d.s')::uuid);
SELECT 'U3.victim_same_session_recovers', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d137]','ios','victim-secret-00000000','Victim iPhone')->>'outcome'$q$);
SELECT tap.logout();
SELECT 'U3.row', (SELECT (SELECT email FROM auth.users WHERE id=t.user_id)||'|active='||t.is_active||'|reason='||coalesce(t.revoked_reason,'-')||'|hash='||coalesce(left(t.device_secret_hash,8),'-') FROM public.push_tokens t WHERE t.token='ExponentPushToken[d137]');
-- and from a NEW session (the ordinary case: the app was reopened after a sign-in)
SELECT set_config('d.s2', pg_temp.sess('d1370000-0000-4000-8000-000000000001')::uuid::text, false);
SET LOCAL ROLE service_role;
SELECT public.unbind_push_token('ExponentPushToken[d137]');
RESET ROLE;
SELECT pg_temp.login('d1370000-0000-4000-8000-000000000001', current_setting('d.s2')::uuid);
SELECT 'U4.victim_new_session_recovers', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[d137]','ios','victim-secret-00000000','Victim iPhone')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK;
