-- ROLLBACK for 135_push_token_proof_of_possession.sql — restores the 131 @ f3963a3 verb
-- and comment byte-for-byte and drops every object 135 added. The notification type and
-- template rows are removed (no notification of that type exists before 135).
begin;

drop trigger  if exists trg_guard_push_token_client_delete on public.push_tokens;
drop function if exists public.guard_push_token_client_delete();
drop function if exists public.confirm_push_token_challenge(uuid, text);
drop function if exists public.request_push_token_challenge(text, text, text);
drop function if exists notify.record_push_token_challenge_delivery(uuid, text, text, text);
drop function if exists notify.get_push_token_challenge(uuid);
drop function if exists notify.issue_push_token_challenge(uuid, uuid, uuid, text, text, text, text);
drop table    if exists notify.push_token_challenges;
delete from notify.template where template_key = 'security_device_rebound';
delete from notify.notification_type where type_key = 'security_device_rebound';

create or replace function public.register_push_token(
  p_token         text,
  p_platform      text,
  p_device_secret text,
  p_device_name   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_hash       text;
  v_epoch      timestamptz;
  v_row_user   uuid;
  v_row_hash   text;
  v_row_active boolean;
  v_row_made   timestamptz;
  v_row_reason text;
  v_row_revoked timestamptz;
  v_id         uuid;
  v_outcome    text;
  v_sid        uuid;                                             -- [A-131-K2]
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) < 8 or length(p_token) > 4096 then
    raise exception 'precondition_failed: token length' using errcode = 'P0001';
  end if;
  if p_platform is null or p_platform not in ('ios', 'android') then
    raise exception 'precondition_failed: platform must be ios or android' using errcode = 'P0001';
  end if;
  if p_device_secret is null or length(p_device_secret) < 16 or length(p_device_secret) > 512 then
    raise exception 'precondition_failed: device secret length' using errcode = 'P0001';
  end if;
  if not public.check_rate_limit(v_uid, 'register_push_token', 20, 600) then
    raise exception 'precondition_failed: too many registration attempts' using errcode = 'P0001';
  end if;

  -- [131] one lock order everywhere; then the credential-epoch check, before
  -- any write and before anything about the row is disclosed.
  perform pg_advisory_xact_lock(hashtext('push_bindings:' || v_uid::text));
  if kernel.push_session_predates_epoch(v_uid) then
    raise exception 'insufficient_privilege: session predates a credential change'
      using errcode = '42501';
  end if;

  begin                                                          -- [A-131-K2] the session this binding belongs to
    v_sid := (auth.jwt() ->> 'session_id')::uuid;
  exception when others then
    v_sid := null;
  end;

  v_hash  := encode(pg_catalog.sha256(pg_catalog.convert_to(p_device_secret, 'utf8')), 'hex');
  select applied_at into v_epoch from public.push_token_rebind_epoch;

  perform set_config('app.push_token_verb', 'on', true);

  loop
    select user_id, device_secret_hash, is_active, created_at, revoked_reason, revoked_at
      into v_row_user, v_row_hash, v_row_active, v_row_made, v_row_reason, v_row_revoked
      from public.push_tokens
     where token = p_token
       for update;
    exit when found;

    insert into public.push_tokens
      (user_id, token, platform, device_name, last_used, is_active, device_secret_hash, session_id)
    values (v_uid, p_token, p_platform, left(p_device_name, 120), now(), true, v_hash, v_sid)
    on conflict (token) do nothing
    returning id into v_id;

    if v_id is not null then
      v_outcome := 'registered';
      exit;
    end if;
  end loop;

  if v_outcome = 'registered' then
    null;
  elsif v_row_user = v_uid then
    update public.push_tokens
       set platform           = p_platform,
           device_name        = left(p_device_name, 120),
           last_used          = now(),
           is_active          = true,
           revoked_at         = null,
           revoked_reason     = null,
           device_secret_hash = coalesce(device_secret_hash, v_hash),
           session_id         = v_sid
     where token = p_token
     returning id into v_id;
    v_outcome := 'refreshed';

  elsif v_row_hash is not null and v_row_hash = v_hash then
    update public.push_tokens
       set user_id            = v_uid,
           platform           = p_platform,
           device_name        = left(p_device_name, 120),
           last_used          = now(),
           is_active          = true,
           revoked_at         = null,
           revoked_reason     = null,
           device_secret_hash = v_hash,
           session_id         = v_sid
     where token = p_token
     returning id into v_id;
    v_outcome := 'rebound';

  elsif v_row_hash is null
        and v_row_active is not true
        and v_row_made   <  v_epoch
        and v_row_reason = 'signed_out'
        and v_row_revoked is not null
        and v_row_revoked > now() - interval '30 days'
        and now() < v_epoch + interval '90 days' then
    update public.push_tokens
       set user_id            = v_uid,
           platform           = p_platform,
           device_name        = left(p_device_name, 120),
           last_used          = now(),
           is_active          = true,
           revoked_at         = null,
           revoked_reason     = null,
           device_secret_hash = v_hash,
           session_id         = v_sid
     where token = p_token
     returning id into v_id;
    v_outcome := 'rebound_legacy';

  else
    perform set_config('app.push_token_verb', '', true);
    raise exception 'insufficient_privilege: token is bound to another account'
      using errcode = '42501';
  end if;

  update public.push_tokens
     set last_provider_error = null
   where id = v_id and last_provider_error is not null;
  update notify.identity_channel_state s
     set state = 'ok', since = now(), reason = 'token_registered'
   where s.identity_id = v_uid and s.channel = 'push' and s.state = 'unreachable';

  perform set_config('app.push_token_verb', '', true);

  return jsonb_build_object('token_id', v_id, 'outcome', v_outcome,
                            'platform', p_platform, 'contract_version', 2);
end;
$$;
comment on function public.register_push_token(text, text, text, text) is
  '128 v2 (F7) + 131: registers or rebinds this device''s push token. Rebinding requires the device-held secret, never mere knowledge of the token string. A hash-less binding is claimable only when it predates the 128 epoch, was revoked by a SIGN-OUT (not a provider signal) within 30 days, and is still inactive. [131] Refused with 42501 "session predates a credential change" when the caller''s session was created before the account''s last password change / sign-out-everywhere, or no longer exists. Raises 42501 otherwise, writing nothing. Every success clears last_provider_error and heals the caller''s push channel. notify.register_push_token is revoked from authenticated by 128.';

create or replace function public.unbind_push_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  -- No set_config here (V15): the write guard is BEFORE INSERT OR UPDATE and this
  -- only DELETEs, so setting it would merely disarm the guard for the rest of the
  -- caller's transaction.
  delete from public.push_tokens where token = p_token;
  get diagnostics v_n = row_count;
  return jsonb_build_object('unbound', v_n, 'contract_version', 2);
end;
$$;
comment on function public.unbind_push_token(text) is
  '128 v2: releases a push token binding so the genuine device can register again. The remedy for a squatted token, which the database cannot prevent (it cannot tell who physically holds an unclaimed token). service_role only — support/operator path, never a client verb.';
revoke execute on function public.unbind_push_token(text) from public, anon, authenticated;

commit;
