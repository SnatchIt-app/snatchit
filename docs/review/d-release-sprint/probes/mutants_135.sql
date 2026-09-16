-- D: negative controls for the 135 matrix @ 1cfc85c. Each mutant breaks ONE guard inside its own
-- BEGIN…ROLLBACK and re-runs the case that is supposed to catch it. A mutant that does not flip its
-- case means the case proves nothing. Local rehearsal DB only; nothing is committed.
\set ON_ERROR_STOP 0

-- ═══ MU1: confirm stops checking the SESSION (user only) — C3b must flip ═══
BEGIN;
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $f$ SELECT ('d1360000-0000-4000-8000-00000000000'||i)::uuid $f$;
CREATE FUNCTION pg_temp.sess(p uuid) RETURNS uuid LANGUAGE plpgsql AS $f$ DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id,user_id,created_at,updated_at,aal) VALUES (v,p,now()-interval '1 hour',now()-interval '1 hour','aal1'); RETURN v; END $f$;
CREATE FUNCTION pg_temp.login(p uuid, s uuid) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM tap.login(p);
  PERFORM set_config('request.jwt.claims',(coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb||jsonb_build_object('session_id',s::text))::text,true); END $f$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $f$ DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r,'ok');
EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE; END $f$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text), pg_temp.u(int) TO authenticated;
CREATE TEMP TABLE net_posts (id bigserial, body jsonb); GRANT SELECT ON net_posts TO authenticated;
CREATE OR REPLACE FUNCTION net.http_post(url text, headers jsonb default '{}', body jsonb default '{}') RETURNS bigint
  LANGUAGE plpgsql AS $f$ DECLARE n bigint; BEGIN INSERT INTO net_posts(body) VALUES (body) RETURNING id INTO n; RETURN n; END $f$;
INSERT INTO vault.decrypted_secrets (name, decrypted_secret) VALUES ('project_url','https://stub.local');
CREATE FUNCTION pg_temp.nonce_of(c uuid) RETURNS text LANGUAGE sql AS $f$ SELECT body->>'nonce' FROM net_posts WHERE (body->>'challenge_id')::uuid=c ORDER BY id DESC LIMIT 1 $f$;
GRANT EXECUTE ON FUNCTION pg_temp.nonce_of(uuid) TO authenticated;
INSERT INTO auth.users (id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','o@m.local','h','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c@m.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('m.s1', pg_temp.sess(pg_temp.u(1))::text, false);
SELECT set_config('m.s2', pg_temp.sess(pg_temp.u(2))::text, false);
SELECT set_config('m.s2b', pg_temp.sess(pg_temp.u(2))::text, false);
SELECT pg_temp.login(pg_temp.u(1), current_setting('m.s1')::uuid);
SELECT public.register_push_token('ExponentPushToken[mu-tok]','ios','owner-secret-0000000000','O');
SELECT tap.logout();
SELECT pg_temp.login(pg_temp.u(2), current_setting('m.s2')::uuid);
SELECT set_config('m.ch', (public.register_push_token('ExponentPushToken[mu-tok]','android','claim-secret-00000000000','C')->'challenge'->>'id'), false);
SELECT tap.logout();
-- the mutation: drop the session half of C3
CREATE OR REPLACE FUNCTION public.confirm_push_token_challenge(p_challenge_id uuid, p_nonce text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = '' AS $mu$
DECLARE v_uid uuid := auth.uid(); v_sid uuid; c record; v_prev_owner uuid; v_token text;
BEGIN
  begin v_sid := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sid := null; end;
  select * into c from notify.push_token_challenges where id = p_challenge_id for update;
  if c.requesting_user <> v_uid then raise exception 'insufficient_privilege' using errcode='42501'; end if;   -- session check REMOVED
  if encode(pg_catalog.sha256(pg_catalog.convert_to(p_nonce,'utf8')),'hex') <> c.nonce_hash then
    return jsonb_build_object('outcome','nonce_mismatch'); end if;
  perform set_config('app.push_token_verb','on',true);
  select user_id, token into v_prev_owner, v_token from public.push_tokens where id = c.token_id for update;
  update public.push_tokens set user_id = v_uid, device_secret_hash = c.secret_hash, session_id = v_sid, is_active = true where id = c.token_id;
  update notify.push_token_challenges set confirmed_at = now(), consumed_at = now() where id = c.id;
  perform set_config('app.push_token_verb','',true);
  return jsonb_build_object('outcome','rebound');
END $mu$;
SELECT pg_temp.login(pg_temp.u(2), current_setting('m.s2b')::uuid);
SELECT 'MU1.other_session_confirms_now', pg_temp.try(format($q$SELECT public.confirm_push_token_challenge(%L::uuid,%L)->>'outcome'$q$, current_setting('m.ch'), pg_temp.nonce_of(current_setting('m.ch')::uuid)));
SELECT tap.logout();
ROLLBACK;

-- ═══ MU2: the client-DELETE trigger is gone — C2b must flip (the row really disappears) ═══
BEGIN;
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $f$ SELECT ('d1360000-0000-4000-8000-00000000000'||i)::uuid $f$;
CREATE FUNCTION pg_temp.sess(p uuid) RETURNS uuid LANGUAGE plpgsql AS $f$ DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id,user_id,created_at,updated_at,aal) VALUES (v,p,now()-interval '1 hour',now()-interval '1 hour','aal1'); RETURN v; END $f$;
CREATE FUNCTION pg_temp.login(p uuid, s uuid) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM tap.login(p);
  PERFORM set_config('request.jwt.claims',(coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb||jsonb_build_object('session_id',s::text))::text,true); END $f$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $f$ DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r,'ok');
EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE; END $f$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text), pg_temp.u(int) TO authenticated;
INSERT INTO auth.users (id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','o@m.local','h','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c@m.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('m.s1', pg_temp.sess(pg_temp.u(1))::text, false);
SELECT set_config('m.s2', pg_temp.sess(pg_temp.u(2))::text, false);
DROP TRIGGER trg_guard_push_token_client_delete ON public.push_tokens;              -- the mutation
SELECT pg_temp.login(pg_temp.u(1), current_setting('m.s1')::uuid);
SELECT public.register_push_token('ExponentPushToken[mu-del]','ios','owner-secret-0000000000','O');
SELECT 'MU2.client_delete_rows_removed', pg_temp.try($q$WITH x AS (DELETE FROM public.push_tokens WHERE token='ExponentPushToken[mu-del]' RETURNING 1) SELECT count(*)::text FROM x$q$);
SELECT tap.logout();
SELECT 'MU2.row_after', coalesce((SELECT 'present' FROM public.push_tokens WHERE token='ExponentPushToken[mu-del]'), 'GONE');
SELECT pg_temp.login(pg_temp.u(2), current_setting('m.s2')::uuid);
SELECT 'MU2.next_binder_gets', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[mu-del]','android','claim-secret-00000000000','C')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK;

-- ═══ MU3: support unbind DELETES again (pre-RB-1) — C1d must flip to `registered` ═══
BEGIN;
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $f$ SELECT ('d1360000-0000-4000-8000-00000000000'||i)::uuid $f$;
CREATE FUNCTION pg_temp.sess(p uuid) RETURNS uuid LANGUAGE plpgsql AS $f$ DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id,user_id,created_at,updated_at,aal) VALUES (v,p,now()-interval '1 hour',now()-interval '1 hour','aal1'); RETURN v; END $f$;
CREATE FUNCTION pg_temp.login(p uuid, s uuid) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM tap.login(p);
  PERFORM set_config('request.jwt.claims',(coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb||jsonb_build_object('session_id',s::text))::text,true); END $f$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $f$ DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r,'ok');
EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE; END $f$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text), pg_temp.u(int) TO authenticated;
INSERT INTO auth.users (id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','o@m.local','h','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c@m.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('m.s1', pg_temp.sess(pg_temp.u(1))::text, false);
SELECT set_config('m.s2', pg_temp.sess(pg_temp.u(2))::text, false);
-- the mutation: 128's delete body
CREATE OR REPLACE FUNCTION public.unbind_push_token(p_token text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $mu$
DECLARE v_n integer; BEGIN
  perform set_config('app.push_token_verb','on',true);
  delete from public.push_tokens where token = p_token;
  get diagnostics v_n = row_count;
  perform set_config('app.push_token_verb','',true);
  return jsonb_build_object('unbound', v_n); END $mu$;
SELECT pg_temp.login(pg_temp.u(1), current_setting('m.s1')::uuid);
SELECT public.register_push_token('ExponentPushToken[mu-unb]','ios','owner-secret-0000000000','O');
SELECT tap.logout();
SET LOCAL ROLE service_role;
SELECT 'MU3.unbind', public.unbind_push_token('ExponentPushToken[mu-unb]')::text;
RESET ROLE;
SELECT 'MU3.row_after', coalesce((SELECT 'present' FROM public.push_tokens WHERE token='ExponentPushToken[mu-unb]'), 'GONE');
SELECT pg_temp.login(pg_temp.u(2), current_setting('m.s2')::uuid);
SELECT 'MU3.next_binder_gets', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[mu-unb]','android','claim-secret-00000000000','C')->>'outcome'$q$);
SELECT tap.logout();
ROLLBACK;

-- ═══ MU4: register's cross-account branch binds on a hash match again (128 rule 3) — C1a must flip ═══
BEGIN;
CREATE FUNCTION pg_temp.u(i int) RETURNS uuid LANGUAGE sql AS $f$ SELECT ('d1360000-0000-4000-8000-00000000000'||i)::uuid $f$;
CREATE FUNCTION pg_temp.sess(p uuid) RETURNS uuid LANGUAGE plpgsql AS $f$ DECLARE v uuid := gen_random_uuid(); BEGIN
  INSERT INTO auth.sessions (id,user_id,created_at,updated_at,aal) VALUES (v,p,now()-interval '1 hour',now()-interval '1 hour','aal1'); RETURN v; END $f$;
CREATE FUNCTION pg_temp.login(p uuid, s uuid) RETURNS void LANGUAGE plpgsql AS $f$ BEGIN PERFORM tap.login(p);
  PERFORM set_config('request.jwt.claims',(coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb||jsonb_build_object('session_id',s::text))::text,true); END $f$;
CREATE FUNCTION pg_temp.try(q text) RETURNS text LANGUAGE plpgsql AS $f$ DECLARE r text; BEGIN EXECUTE q INTO r; RETURN coalesce(r,'ok');
EXCEPTION WHEN others THEN RETURN 'ERR '||SQLSTATE; END $f$;
GRANT EXECUTE ON FUNCTION pg_temp.login(uuid,uuid), pg_temp.try(text), pg_temp.u(int) TO authenticated;
INSERT INTO auth.users (id,instance_id,aud,role,email,encrypted_password,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES
 (pg_temp.u(1),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','o@m.local','h','{"provider":"email"}','{}',now(),now()),
 (pg_temp.u(2),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c@m.local','h','{"provider":"email"}','{}',now(),now());
SELECT set_config('m.s1', pg_temp.sess(pg_temp.u(1))::text, false);
SELECT set_config('m.s2', pg_temp.sess(pg_temp.u(2))::text, false);
SELECT pg_temp.login(pg_temp.u(1), current_setting('m.s1')::uuid);
SELECT public.register_push_token('ExponentPushToken[mu-r3]','ios','shared-secret-0000000000','O');
SELECT tap.logout();
-- the mutation: a hash match hands the row over with no challenge (the v2 rule 3 this migration removes)
CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_platform text, p_device_secret text, p_device_name text default null)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $mu$
DECLARE v_uid uuid := auth.uid(); v_hash text; v_id uuid; BEGIN
  v_hash := encode(pg_catalog.sha256(pg_catalog.convert_to(p_device_secret,'utf8')),'hex');
  perform set_config('app.push_token_verb','on',true);
  update public.push_tokens set user_id = v_uid, is_active = true, platform = p_platform where token = p_token and device_secret_hash = v_hash returning id into v_id;
  perform set_config('app.push_token_verb','',true);
  if v_id is null then return jsonb_build_object('outcome','challenge_required'); end if;
  return jsonb_build_object('outcome','rebound_on_hash','token_id',v_id); END $mu$;
SELECT pg_temp.login(pg_temp.u(2), current_setting('m.s2')::uuid);
SELECT 'MU4.cross_account_with_same_secret', pg_temp.try($q$SELECT public.register_push_token('ExponentPushToken[mu-r3]','android','shared-secret-0000000000','C')->>'outcome'$q$);
SELECT tap.logout();
SELECT 'MU4.owner_now', (SELECT (SELECT email FROM auth.users WHERE id=t.user_id) FROM public.push_tokens t WHERE t.token='ExponentPushToken[mu-r3]');
ROLLBACK;
