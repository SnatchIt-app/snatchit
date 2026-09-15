-- ============================================================================
-- 131_session_bound_push_bindings_rollback.sql — removes the credential epoch,
-- the auth triggers, the client verb, the push_tokens session guard, and
-- returns register_push_token to its 128 @ f22c1a3 body (contract v2).
--
-- WHAT THIS CANNOT UNDO, on the record (D, S11): bindings revoked and device
-- proofs CLEARED by the invalidator are not restored — the hashes are gone
-- and no record of them exists. Every affected device re-proves itself on its
-- next registration (rule 2 adopts its secret). That is the safe direction.
--
-- WHAT THIS RE-INTRODUCES: the production residual the owner rejected —
-- bindings and proofs survive password change and sign-out-everywhere; old
-- sessions can re-register. Production is forward-only by policy; this needs
-- its own authorization. Deploy order on the way back: a client that calls
-- revoke_all_push_bindings gets PGRST202 (never blocks its sign-out).
-- ============================================================================
begin;

drop trigger  if exists trg_guard_push_token_session_row  on public.push_tokens;
drop trigger  if exists trg_guard_push_token_session_stmt on public.push_tokens;
drop function if exists public.guard_push_token_session_row();
drop function if exists public.guard_push_token_session_stmt();
drop function if exists public.revoke_all_push_bindings();

drop trigger  if exists trg_push_bindings_on_sessions_gone on auth.sessions;
drop function if exists kernel.trg_push_bindings_on_sessions_gone();
drop trigger  if exists trg_push_bindings_on_password_change on auth.users;
drop function if exists kernel.trg_push_bindings_on_password_change();
drop function if exists kernel.push_session_predates_epoch(uuid);
drop function if exists kernel.invalidate_push_bindings_for(uuid, text, timestamptz);

alter table kernel.identity_ext drop column if exists push_binding_epoch;

-- register_push_token: 128 @ f22c1a3 body, verbatim (the [131] block removed).
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
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) < 8 or length(p_token) > 4096 then
    raise exception 'precondition_failed: token length' using errcode = 'P0001';
  end if;
  -- `not in` is NULL for a NULL platform, which would skip this guard entirely
  -- and surface a raw 23502 whose DETAIL dumps the failing row (finding V9).
  if p_platform is null or p_platform not in ('ios', 'android') then
    raise exception 'precondition_failed: platform must be ios or android' using errcode = 'P0001';
  end if;
  -- A guessable secret would defeat the rule, so a floor is enforced here rather
  -- than trusted to the client. The server cannot measure entropy of a value the
  -- client chose — see the recorded limitation in the release record.
  if p_device_secret is null or length(p_device_secret) < 16 or length(p_device_secret) > 512 then
    raise exception 'precondition_failed: device secret length' using errcode = 'P0001';
  end if;
  -- Squatting is not preventable in the database (§3); rate limiting makes it
  -- impractical at scale.
  if not public.check_rate_limit(v_uid, 'register_push_token', 20, 600) then
    raise exception 'precondition_failed: too many registration attempts' using errcode = 'P0001';
  end if;

  -- pg_catalog.sha256 rather than extensions.digest: identical value, and no
  -- pgcrypto dependency that would resolve only at call time (finding V10).
  v_hash  := encode(pg_catalog.sha256(pg_catalog.convert_to(p_device_secret, 'utf8')), 'hex');
  select applied_at into v_epoch from public.push_token_rebind_epoch;
  -- A NULL epoch (row deleted) makes every rule-5 comparison NULL, so the rule
  -- fails CLOSED. Verified by re-review; deleting it is a DoS on handover, not a bypass.

  perform set_config('app.push_token_verb', 'on', true);

  loop
    select user_id, device_secret_hash, is_active, created_at, revoked_reason, revoked_at
      into v_row_user, v_row_hash, v_row_active, v_row_made, v_row_reason, v_row_revoked
      from public.push_tokens
     where token = p_token
       for update;
    exit when found;

    -- Nothing to lock when the row does not exist, so the race is resolved by
    -- the unique index rather than by FOR UPDATE (finding V8): the loser gets no
    -- row back and loops round to be judged against the winner's committed row,
    -- instead of raising an unhandled 23505.
    insert into public.push_tokens
      (user_id, token, platform, device_name, last_used, is_active, device_secret_hash)
    values (v_uid, p_token, p_platform, left(p_device_name, 120), now(), true, v_hash)
    on conflict (token) do nothing
    returning id into v_id;

    if v_id is not null then
      v_outcome := 'registered';
      exit;
    end if;
  end loop;

  if v_outcome = 'registered' then
    -- 1. A fresh binding. Falls through to the heal below on purpose: after a
    -- DeviceNotRegistered the reinstalled app arrives with a NEW token, and
    -- binding it while leaving the channel unreachable would keep the user silenced.
    null;
  elsif v_row_user = v_uid then
    -- 2. Already ours. coalesce, NOT assignment — see PLANT-THEN-CLAIM.
    update public.push_tokens
       set platform           = p_platform,
           device_name        = left(p_device_name, 120),
           last_used          = now(),
           is_active          = true,
           revoked_at         = null,
           revoked_reason     = null,
           device_secret_hash = coalesce(device_secret_hash, v_hash)
     where token = p_token
     returning id into v_id;
    v_outcome := 'refreshed';

  elsif v_row_hash is not null and v_row_hash = v_hash then
    -- 3. Someone else's, but the caller holds the device.
    update public.push_tokens
       set user_id            = v_uid,
           platform           = p_platform,
           device_name        = left(p_device_name, 120),
           last_used          = now(),
           is_active          = true,
           revoked_at         = null,
           revoked_reason     = null,
           device_secret_hash = v_hash
     where token = p_token
     returning id into v_id;
    v_outcome := 'rebound';

  elsif v_row_hash is null
        and v_row_active is not true
        and v_row_made   <  v_epoch                                -- (a) transitional only
        and v_row_reason = 'signed_out'                             -- (b) a sign-out, not a provider signal
        and v_row_revoked is not null
        and v_row_revoked > now() - interval '30 days'              -- (c) a recent handover
        and now() < v_epoch + interval '90 days' then               -- (e) sunset
    -- 5. A pre-128 binding the previous owner signed out of, recently.
    update public.push_tokens
       set user_id            = v_uid,
           platform           = p_platform,
           device_name        = left(p_device_name, 120),
           last_used          = now(),
           is_active          = true,
           revoked_at         = null,
           revoked_reason     = null,
           device_secret_hash = v_hash
     where token = p_token
     returning id into v_id;
    v_outcome := 'rebound_legacy';

  else
    -- 4, and every rule-5 condition that failed. Knowing the token is not
    -- authority. Nothing is written, and nothing about the current owner — or
    -- about how close a guessed secret was — is disclosed.
    perform set_config('app.push_token_verb', '', true);
    raise exception 'insufficient_privilege: token is bound to another account'
      using errcode = '42501';
  end if;

  -- §17.24 HEAL (independent review, finding F1 — a HIGH functional regression
  -- three security-focused rounds missed). The legacy verb cleared the provider
  -- error and reset the identity's push channel to `ok` on every registration.
  -- notify.enqueue (092:462-467) suppresses EVERY push — mandatory included —
  -- while the channel is not `ok`, so a verb that binds the token but leaves
  -- the channel `unreachable` silences the user permanently after a single
  -- DeviceNotRegistered. Every success path heals the CALLER. The previous
  -- owner on rules 3/5 is deliberately not touched here: the legacy verb did not
  -- either, and record_delivery_result marks them unreachable on the next failed
  -- send — parity, not a new behaviour.
  update public.push_tokens
     set last_provider_error = null
   where id = v_id and last_provider_error is not null;
  update notify.identity_channel_state s
     set state = 'ok', since = now(), reason = 'token_registered'
   where s.identity_id = v_uid and s.channel = 'push' and s.state = 'unreachable';

  -- The write-guard bypass is transaction-local, and PostgREST cannot batch —
  -- but pg_graphql runs a multi-field mutation in ONE transaction, so a
  -- registerPushToken followed by a push_tokens update in the same request
  -- would have found the guard still disarmed. Disarm before every return.
  perform set_config('app.push_token_verb', '', true);

  return jsonb_build_object('token_id', v_id, 'outcome', v_outcome,
                            'platform', p_platform, 'contract_version', 2);
end;
$$;

commit;
