-- =============================================================================
-- 135_push_token_proof_of_possession.sql — b2: a push binding changes owner
-- only after the push provider proves the registering device holds the token.
-- Contract: docs/release/PUSH_TOKEN_CONTRACT_V3.md (D-reviewed 2026-09-16).
-- Owner decision 2026-09-16 (b2, build shape i). Numbered: it owns its objects
-- and redefines only 128/131 bodies (both numbered). Applied nowhere by this
-- file; sandbox application needs the owner's package approval.
--
-- What changes
--   1. notify.push_token_challenges — the pending claim lives HERE, never on
--      public.push_tokens (C4: a claim never touches the live row).
--   2. notify.issue_push_token_challenge — generates the nonce (silent: 32
--      CSPRNG bytes base64url; visible: 6 CSPRNG digits), stores only its hash,
--      dispatches ONE post to send-push through pg_net with 133's Vault
--      project_url (guarded no-op without it). An exhausted or expired open
--      challenge is consumed and a fresh one issued (D, P3-1).
--   3. public.register_push_token v3 — the cross-account branches of 128/131
--      (rules 3/5 and the 42501) become `challenge_required`; `registered` /
--      `refreshed` unchanged and stamped contract_version 2 (D, V3-1: the shipped
--      v2 client treats any other version as terminal); challenge replies 3.
--   4. public.request_push_token_challenge — the client's fallback (visible code),
--      carrying the device secret (D, V3-3).
--   5. public.confirm_push_token_challenge — the atomic bind: same user AND
--      session (C3), unexpired, unconsumed, hash match; proof superseded by the
--      proving device's (C5); previous owner notified in-app (never push);
--      a nonce mismatch RETURNS an outcome (so the attempt count persists), the
--      fifth mismatch consumes the challenge.
--   6. Client DELETE on push_tokens becomes a revoke with history (C2) — rows are
--      never removed by clients, so a later fresh bind by another account is
--      `challenge_required`, never `registered`.
--   6b. public.unbind_push_token revokes + tombstones instead of deleting (D, RB-1).
--   7. notify.record_push_token_challenge_delivery — send-push records delivery
--      (outcomes 'sent' | 'rejected' | 'error', B's vocabulary).
--   6c. notify.get_push_token_challenge — send-push's token-addressed read (no table grant).
--   8. notification_type + in_app template `security_device_rebound` (never push; no email, N1).
-- Census (public, as CI asserts it): functions +3, triggers +1, tables +0,
-- policies +0. Five-schema routines +3 (notify). Rollback restores the 131 verb
-- byte-for-byte and drops everything above.
-- =============================================================================
begin;

-- ── 1. the pending claim ────────────────────────────────────────────────────
create table if not exists notify.push_token_challenges (
  id                  uuid primary key default gen_random_uuid(),
  token_id            uuid not null references public.push_tokens(id) on delete cascade,
  requesting_user     uuid not null,
  requesting_session  uuid not null,
  nonce_hash          text not null,
  prev_nonce_hash     text,                 -- the superseded nonce, kept one generation: a stale echo is free (D)
  mode                text not null check (mode in ('silent', 'visible')),
  purpose             text not null default 'rebind',
  secret_hash         text not null,
  platform            text not null check (platform in ('ios', 'android')),
  device_name         text,
  expires_at          timestamptz not null,
  attempts            integer not null default 0,
  confirmed_at        timestamptz,
  consumed_at         timestamptz,
  dispatched_at       timestamptz,
  delivery_outcome    text,
  provider_message_id text,
  delivery_error      text,
  created_at          timestamptz not null default now()
);
comment on table notify.push_token_challenges is
  '135 (b2): a pending cross-account push binding claim. The live public.push_tokens row is untouched until confirm_push_token_challenge proves the device holds the token. Only the nonce hash is stored. One open (consumed_at null) row per (token, requesting user).';
create unique index if not exists push_token_challenges_open_uq
  on notify.push_token_challenges (token_id, requesting_user) where consumed_at is null;
create index if not exists push_token_challenges_expires_idx on notify.push_token_challenges (expires_at) where consumed_at is null;
alter table notify.push_token_challenges enable row level security;
revoke all on notify.push_token_challenges from public, anon, authenticated;
-- no table grants at all (notify discipline: service_role's wall is the grant wall); send-push reads through the verb below

-- ── 2. issue (internal) ─────────────────────────────────────────────────────
create or replace function notify.issue_push_token_challenge(
  p_token_id uuid, p_uid uuid, p_sid uuid, p_secret_hash text, p_platform text, p_device_name text, p_mode text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_id      uuid;
  v_nonce   text;
  v_hash    text;
  v_url     text;
  v_expires timestamptz := now() + interval '5 minutes';
begin
  if p_mode not in ('silent', 'visible') then
    raise exception 'precondition_failed: challenge mode must be silent or visible' using errcode = 'P0001';
  end if;
  -- nonce by mode (contract §5): silent = 32 CSPRNG bytes base64url; visible = 6 CSPRNG digits (the code IS the nonce)
  if p_mode = 'silent' then
    v_nonce := translate(rtrim(encode(extensions.gen_random_bytes(32), 'base64'), '='), '+/', '-_');
  else
    v_nonce := lpad((abs(('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::int) % 1000000)::text, 6, '0');
  end if;
  v_hash := encode(pg_catalog.sha256(pg_catalog.convert_to(v_nonce, 'utf8')), 'hex');

  -- an open challenge that is exhausted or expired is CONSUMED and replaced (D, P3-1);
  -- a live open one is re-issued in place (fresh nonce, attempts kept, expiry refreshed, mode as requested)
  update notify.push_token_challenges
     set consumed_at = now()
   where token_id = p_token_id and requesting_user = p_uid and consumed_at is null
     and (attempts >= 5 or expires_at <= now());

  select id into v_id from notify.push_token_challenges
   where token_id = p_token_id and requesting_user = p_uid and consumed_at is null
   for update;
  if v_id is null then
    insert into notify.push_token_challenges
      (token_id, requesting_user, requesting_session, nonce_hash, mode, secret_hash, platform, device_name, expires_at, dispatched_at)
    values (p_token_id, p_uid, p_sid, v_hash, p_mode, p_secret_hash, p_platform, left(p_device_name, 120), v_expires, now())
    returning id into v_id;
  else
    update notify.push_token_challenges
       set prev_nonce_hash = nonce_hash, nonce_hash = v_hash, mode = p_mode, requesting_session = p_sid, secret_hash = p_secret_hash,
           platform = p_platform, device_name = left(p_device_name, 120), expires_at = v_expires, dispatched_at = now(),
           delivery_outcome = null, provider_message_id = null, delivery_error = null
     where id = v_id;
  end if;

  -- ONE dispatch through pg_net (133 pattern): configured base URL, Vault service-role bearer; no URL ⇒ no post
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url' order by created_at desc limit 1;
  if v_url is not null then
    begin
      perform net.http_post(
        url     := v_url || '/functions/v1/send-push',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || coalesce((select decrypted_secret from vault.decrypted_secrets
                                                   where name = 'service_role_key' order by created_at desc limit 1), ''),
          'Content-Type', 'application/json'),
        body    := jsonb_build_object('kind', 'push_token_challenge', 'challenge_id', v_id, 'nonce', v_nonce, 'user_id', p_uid));
    exception when others then
      -- never fail the verb because delivery could not be queued; the client's fallback re-requests
      update notify.push_token_challenges set delivery_error = left(sqlerrm, 200) where id = v_id;
    end;
  end if;

  return jsonb_build_object('id', v_id, 'mode', p_mode, 'expires_in_s', 300);
end;
$$;
revoke execute on function notify.issue_push_token_challenge(uuid, uuid, uuid, text, text, text, text) from public, anon, authenticated, service_role;

-- ── 3. register_push_token v3 ───────────────────────────────────────────────
-- Body = 131 @ f3963a3 with the cross-account branches replaced: rules 3 (hash
-- match), 5 (legacy re-adoption) and the 42501 all become `challenge_required`.
-- `registered` / `refreshed` are byte-for-byte 128/131 and stamp contract_version 2.
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
  v_row_id     uuid;
  v_row_user   uuid;
  v_row_hash   text;
  v_row_active boolean;
  v_row_made   timestamptz;
  v_row_reason text;
  v_row_revoked timestamptz;
  v_id         uuid;
  v_outcome    text;
  v_sid        uuid;
  v_challenge  jsonb;
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

  perform pg_advisory_xact_lock(hashtext('push_bindings:' || v_uid::text));
  if kernel.push_session_predates_epoch(v_uid) then
    raise exception 'insufficient_privilege: session predates a credential change'
      using errcode = '42501';
  end if;

  begin
    v_sid := (auth.jwt() ->> 'session_id')::uuid;
  exception when others then
    v_sid := null;
  end;

  v_hash  := encode(pg_catalog.sha256(pg_catalog.convert_to(p_device_secret, 'utf8')), 'hex');
  select applied_at into v_epoch from public.push_token_rebind_epoch;

  perform set_config('app.push_token_verb', 'on', true);

  loop
    select id, user_id, device_secret_hash, is_active, created_at, revoked_reason, revoked_at
      into v_row_id, v_row_user, v_row_hash, v_row_active, v_row_made, v_row_reason, v_row_revoked
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

  else
    -- [135] the row is another account's (with or without proof, active or revoked) —
    -- nothing changes on it; the device must prove possession first (C1, C4).
    perform set_config('app.push_token_verb', '', true);
    if v_sid is null then
      raise exception 'insufficient_privilege: session predates a credential change' using errcode = '42501';   -- no session claim: fail closed
    end if;
    if not public.check_rate_limit(v_uid, 'push_challenge_user', 5, 600)
       or not public.check_rate_limit(v_uid, 'push_challenge_token:' || v_row_id::text, 3, 600) then
      raise exception 'precondition_failed: too many challenge requests' using errcode = 'P0001';
    end if;
    v_challenge := notify.issue_push_token_challenge(v_row_id, v_uid, v_sid, v_hash, p_platform, p_device_name, 'silent');
    return jsonb_build_object('token_id', v_row_id, 'outcome', 'challenge_required',
                              'platform', p_platform, 'contract_version', 3, 'challenge', v_challenge);
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
  'Contract v3 (135): registers this device''s push token. `registered` (no history) and `refreshed` (own row) are unchanged from 128/131 and stamp contract_version 2. A token whose row belongs to another account answers `challenge_required` (contract_version 3) with a challenge the device must confirm by echoing a nonce the push provider delivered to that token (confirm_push_token_challenge). Nothing changes on the row until then. 42501 when the caller''s session predates a credential change (131). notify.register_push_token stays revoked from authenticated (128).';

-- ── 4. the client's fallback (visible code) ─────────────────────────────────
create or replace function public.request_push_token_challenge(p_token text, p_device_secret text, p_mode text default 'visible')
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); v_sid uuid; v_hash text; v_row_id uuid; v_row_user uuid; v_platform text; v_device text;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_token is null or length(p_token) < 8 or length(p_token) > 4096 then
    raise exception 'precondition_failed: token length' using errcode = 'P0001';
  end if;
  if p_device_secret is null or length(p_device_secret) < 16 or length(p_device_secret) > 512 then
    raise exception 'precondition_failed: device secret length' using errcode = 'P0001';
  end if;
  if p_mode not in ('silent', 'visible') then
    raise exception 'precondition_failed: challenge mode must be silent or visible' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('push_bindings:' || v_uid::text));
  if kernel.push_session_predates_epoch(v_uid) then
    raise exception 'insufficient_privilege: session predates a credential change' using errcode = '42501';
  end if;
  begin v_sid := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sid := null; end;
  if v_sid is null then
    raise exception 'insufficient_privilege: session predates a credential change' using errcode = '42501';
  end if;
  select id, user_id, platform, device_name into v_row_id, v_row_user, v_platform, v_device
    from public.push_tokens where token = p_token for share;
  if v_row_id is null then
    raise exception 'precondition_failed: no binding to challenge — register instead' using errcode = 'P0001';
  end if;
  if v_row_user = v_uid then
    raise exception 'precondition_failed: the caller already owns this binding — register instead' using errcode = 'P0001';
  end if;
  if not public.check_rate_limit(v_uid, 'push_challenge_user', 5, 600)
     or not public.check_rate_limit(v_uid, 'push_challenge_token:' || v_row_id::text, 3, 600) then
    raise exception 'precondition_failed: too many challenge requests' using errcode = 'P0001';
  end if;
  v_hash := encode(pg_catalog.sha256(pg_catalog.convert_to(p_device_secret, 'utf8')), 'hex');
  return jsonb_build_object('token_id', v_row_id, 'outcome', 'challenge_required', 'contract_version', 3,
                            'challenge', notify.issue_push_token_challenge(v_row_id, v_uid, v_sid, v_hash, v_platform, v_device, p_mode));
end;
$$;
comment on function public.request_push_token_challenge(text, text, text) is
  '135: (re-)issues the possession challenge for a token bound to another account, in silent or visible (6-digit code) mode; carries the device secret so a confirm always stores a proof. Refuses when the caller already owns the row or no row exists (register instead). Rate-limited per user and per (token, user).';

-- ── 5. confirm — the atomic bind ────────────────────────────────────────────
create or replace function public.confirm_push_token_challenge(p_challenge_id uuid, p_nonce text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); v_sid uuid; c record; v_prev_owner uuid; v_token text; v_attempts int;
begin
  if v_uid is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  begin v_sid := (auth.jwt() ->> 'session_id')::uuid; exception when others then v_sid := null; end;
  perform pg_advisory_xact_lock(hashtext('push_bindings:' || v_uid::text));

  select * into c from notify.push_token_challenges where id = p_challenge_id for update;
  if c.id is null then
    raise exception 'precondition_failed: challenge not found' using errcode = 'P0001';
  end if;
  if c.requesting_user <> v_uid or v_sid is null or c.requesting_session <> v_sid then
    raise exception 'insufficient_privilege: challenge belongs to another session' using errcode = '42501';   -- C3
  end if;
  if c.consumed_at is not null then
    raise exception 'precondition_failed: challenge consumed' using errcode = 'P0001';
  end if;
  if c.expires_at <= now() then
    raise exception 'precondition_failed: challenge expired' using errcode = 'P0001';
  end if;
  if c.attempts >= 5 then
    raise exception 'precondition_failed: challenge attempts exhausted' using errcode = 'P0001';
  end if;
  if kernel.push_session_predates_epoch(v_uid) then
    raise exception 'insufficient_privilege: session predates a credential change' using errcode = '42501';
  end if;

  if p_nonce is not null and c.prev_nonce_hash is not null
     and encode(pg_catalog.sha256(pg_catalog.convert_to(p_nonce, 'utf8')), 'hex') = c.prev_nonce_hash then
    -- a late push from before a re-issue: stale, free (no attempt counted, no bind) — the client waits for the current one
    return jsonb_build_object('outcome', 'stale_nonce', 'token_id', c.token_id, 'contract_version', 3);
  end if;
  if p_nonce is null or encode(pg_catalog.sha256(pg_catalog.convert_to(p_nonce, 'utf8')), 'hex') <> c.nonce_hash then
    -- a mismatch RETURNS (never raises) so the attempt count persists; the fifth consumes the challenge
    update notify.push_token_challenges set attempts = attempts + 1,
           consumed_at = case when attempts + 1 >= 5 then now() else null end
     where id = c.id returning attempts into v_attempts;
    if v_attempts >= 5 then
      return jsonb_build_object('outcome', 'challenge_consumed', 'token_id', c.token_id, 'contract_version', 3);
    end if;
    return jsonb_build_object('outcome', 'nonce_mismatch', 'attempts_left', 5 - v_attempts, 'token_id', c.token_id, 'contract_version', 3);
  end if;

  -- proof holds: bind atomically (C5 — the stored proof is superseded by the proving device's)
  perform set_config('app.push_token_verb', 'on', true);
  select user_id, token into v_prev_owner, v_token from public.push_tokens where id = c.token_id for update;
  if v_token is null then
    perform set_config('app.push_token_verb', '', true);
    raise exception 'precondition_failed: binding no longer exists' using errcode = 'P0001';
  end if;
  update public.push_tokens
     set user_id            = v_uid,
         platform           = c.platform,
         device_name        = c.device_name,
         last_used          = now(),
         is_active          = true,
         revoked_at         = null,
         revoked_reason     = null,
         device_secret_hash = c.secret_hash,
         session_id         = v_sid,
         last_provider_error = null
   where id = c.token_id;
  update notify.push_token_challenges set confirmed_at = now(), consumed_at = now() where id = c.id;
  update notify.identity_channel_state s
     set state = 'ok', since = now(), reason = 'token_registered'
   where s.identity_id = v_uid and s.channel = 'push' and s.state = 'unreachable';
  perform set_config('app.push_token_verb', '', true);

  -- the previous owner learns in the notification centre, never by push (their push is exactly what moved); deduped per token per day
  if v_prev_owner is not null and v_prev_owner <> v_uid then
    perform notify.enqueue(v_prev_owner, 'security_device_rebound', 'account_security', c.token_id,
                           jsonb_build_object('device_name', coalesce(c.device_name, 'a device'), 'at', now()),
                           'security_device_rebound:' || c.token_id::text || ':' || to_char(now() at time zone 'utc', 'YYYY-MM-DD'));
  end if;

  return jsonb_build_object('outcome', 'rebound', 'token_id', c.token_id, 'contract_version', 3);
end;
$$;
comment on function public.confirm_push_token_challenge(uuid, text) is
  '135: the device echoes the nonce the push provider delivered to the token; only the requesting user AND session may confirm; on match the binding moves to the caller with the proving device''s secret as proof and the previous owner is emailed; a mismatch returns nonce_mismatch/attempts_left (the fifth consumes the challenge); expired/consumed/foreign challenges are refused.';

revoke execute on function public.request_push_token_challenge(text, text, text) from public, anon, service_role;
grant  execute on function public.request_push_token_challenge(text, text, text) to authenticated;
revoke execute on function public.confirm_push_token_challenge(uuid, text) from public, anon, service_role;
grant  execute on function public.confirm_push_token_challenge(uuid, text) to authenticated;

-- ── 6. client DELETE → revoke with history (C2) ──────────────────────────────
create or replace function public.guard_push_token_client_delete()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if coalesce(current_setting('app.push_token_verb', true), '') = 'on' or auth.uid() is null then
    return old;                                                  -- verbs and service paths may delete
  end if;
  perform set_config('app.push_token_verb', 'on', true);
  update public.push_tokens
     set is_active = false, revoked_at = coalesce(revoked_at, now()), revoked_reason = 'deleted_by_client'
   where id = old.id;
  perform set_config('app.push_token_verb', '', true);
  return null;                                                   -- the delete itself is suppressed
end;
$$;
revoke execute on function public.guard_push_token_client_delete() from public, anon, authenticated, service_role;
drop trigger if exists trg_guard_push_token_client_delete on public.push_tokens;
create trigger trg_guard_push_token_client_delete
  before delete on public.push_tokens
  for each row execute function public.guard_push_token_client_delete();
comment on function public.guard_push_token_client_delete() is
  '135 (C2): a client DELETE on push_tokens becomes a revoke (deleted_by_client) and is suppressed, so token history survives and a later fresh bind by another account must prove possession.';

-- ── 6b. support unbind → revoke + tombstone, never delete (D, RB-1) ──────────
-- Under v3 the row's HISTORY is what forces a challenge; a support DELETE would
-- erase it and make the next bind `registered` with no proof — support as the
-- documented bypass of b2. The verb now revokes, clears the proof and keeps the
-- row (revoked_reason 'support_unbound'); the next binder must still prove
-- possession. A replacement handset has a different token and is unaffected.
create or replace function public.unbind_push_token(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  perform set_config('app.push_token_verb', 'on', true);
  update public.push_tokens
     set is_active = false, device_secret_hash = null, revoked_at = now(), revoked_reason = 'support_unbound', session_id = null
   where token = p_token;
  get diagnostics v_n = row_count;
  update notify.push_token_challenges set consumed_at = now()
   where consumed_at is null and token_id in (select id from public.push_tokens where token = p_token);
  perform set_config('app.push_token_verb', '', true);
  return jsonb_build_object('unbound', v_n, 'contract_version', 3);
end;
$$;
comment on function public.unbind_push_token(text) is
  '135 (RB-1): support unbind revokes the binding, clears its proof, consumes open challenges and KEEPS the row (revoked_reason support_unbound) so token history survives and the next binder must prove possession. service_role only. Returns {unbound, contract_version: 3}.';
revoke execute on function public.unbind_push_token(text) from public, anon, authenticated;
grant  execute on function public.unbind_push_token(text) to service_role;

-- ── 6c. send-push's read: the challenge by id, token-addressed, no requester identity ──
create or replace function notify.get_push_token_challenge(p_challenge_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', c.id, 'token', t.token, 'platform', t.platform, 'mode', c.mode,
                            'expires_at', c.expires_at, 'confirmed_at', c.confirmed_at, 'consumed_at', c.consumed_at,
                            'attempts', c.attempts, 'dispatched_at', c.dispatched_at)
    from notify.push_token_challenges c join public.push_tokens t on t.id = c.token_id
   where c.id = p_challenge_id
$$;
revoke execute on function notify.get_push_token_challenge(uuid) from public, anon, authenticated;
grant  execute on function notify.get_push_token_challenge(uuid) to service_role;
comment on function notify.get_push_token_challenge(uuid) is
  '135: send-push''s read of a challenge by id — the token to address, its mode/expiry/attempts/state; NO requester or owner identity (the push is token-addressed). service_role only.';

-- ── 7. delivery result (send-push → challenge row) ──────────────────────────
create or replace function notify.record_push_token_challenge_delivery(p_challenge_id uuid, p_outcome text, p_provider_message_id text, p_error text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_n int;
begin
  update notify.push_token_challenges
     set delivery_outcome = left(p_outcome, 40), provider_message_id = left(p_provider_message_id, 200), delivery_error = left(p_error, 200)
   where id = p_challenge_id;
  get diagnostics v_n = row_count;
  return jsonb_build_object('recorded', v_n = 1);
end;
$$;
revoke execute on function notify.record_push_token_challenge_delivery(uuid, text, text, text) from public, anon, authenticated;
grant  execute on function notify.record_push_token_challenge_delivery(uuid, text, text, text) to service_role;

-- ── 8. the previous owner's notice: email, never push ────────────────────────
insert into notify.notification_type
  (type_key, delivery_class, allowed_channels, default_channels, target_kind, template_key, group_label, display_label, description, mandatory_reason)
values
  ('security_device_rebound', 'mandatory', '{}', '{}', 'account_security', 'security_device_rebound', 'Security',
   'Device re-registered to another account',
   'A device that received your notifications was registered to another account.',
   'Account security: you must learn when a device stops receiving your notifications because another account claimed it.')
on conflict (type_key) do nothing;
-- in_app only (the notification centre always renders it; never push — the push is what moved; no email row: N1)
insert into notify.template (template_key, locale, channel, version, subject, body) values
  ('security_device_rebound', 'en-US', 'in_app', 1,
   'A device was re-registered to another account',
   'A device that was receiving your notifications ({{device_name}}) was just registered to another account. If that was you switching accounts on your own phone, nothing to do. If not, sign in on that phone to take it back, then change your password.')
on conflict do nothing;

-- ── 9. sanity inside the migration ──────────────────────────────────────────
do $chk$
begin
  if not has_function_privilege('authenticated', 'public.confirm_push_token_challenge(uuid, text)', 'execute')
     or has_function_privilege('anon', 'public.confirm_push_token_challenge(uuid, text)', 'execute')
     or has_function_privilege('authenticated', 'notify.issue_push_token_challenge(uuid, uuid, uuid, text, text, text, text)', 'execute') then
    raise exception '135: grant decisions are not as declared';
  end if;
end $chk$;

commit;
