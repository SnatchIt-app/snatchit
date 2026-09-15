-- ============================================================================
-- 131_session_bound_push_bindings.sql — a push binding lives no longer than the
-- credentials that created it.
--
-- WHY (owner decision O-3 = option b, 2026-09-15). With the victim's SESSION an
-- attacker can redirect the victim's push to their own phone, forward the
-- victim's notifications to attacker devices, or plant a dormant device proof
-- to claim later — and, before this migration, all of it survived a password
-- reset and "sign out everywhere", because nothing tied push_tokens to
-- auth.sessions. The owner does not accept that residual for production.
-- Design and D's two adversarial passes: docs/release/SESSION_BOUND_PUSH_BINDINGS_131_DESIGN.md.
--
-- WHAT. (1) a per-user credential epoch, kernel.identity_ext.push_binding_epoch;
-- (2) one invalidator that revokes every binding, CLEARS every device proof
-- and bumps the epoch; (3) it fires from a
-- DB trigger on auth.users when encrypted_password changes (server-
-- authoritative, not a hosted auth hook) and from a statement-level trigger on
-- auth.sessions when a user's LAST live session is deleted (a global sign-out,
-- from any client version — expired-session cleanup does not qualify); (4) a
-- client verb public.revoke_all_push_bindings() as the fast path before
-- "sign out everywhere"; (5) a write-time guard on public.push_tokens: a client
-- session that predates its user's epoch — or that no longer exists — cannot
-- create, activate or delete a binding, on the verb AND on the direct table
-- path old clients use; (6) register_push_token (128, contract v2) gains the
-- same check with the contract's error text. Reply shapes unchanged;
-- contract_version stays 2 (the new refusal is additive).
--
-- LOCKING — D's X3/S4. Every writer takes the per-user advisory lock
-- pg_advisory_xact_lock(hashtext('push_bindings:'||uid)) BEFORE any row lock:
-- the invalidator first thing; client statements in a BEFORE STATEMENT
-- trigger (before the executor locks any row); the verb right after auth. One
-- lock order everywhere → no cycle, and a client write racing a credential
-- change either commits before the invalidator (which then revokes it under
-- the lock) or waits and reads the committed epoch (and is refused).
--
-- WHAT THIS CANNOT CLOSE (D, X1 — stated, not softened): a redirect COMPLETED
-- during the compromise lives in a row the attacker now owns; the victim's
-- epoch never touches it. Recovery is support unbind_push_token and the
-- client's terminal "contact support" state; prevention is provider-side
-- proof (client v3). Also out of scope: an attacker who knows the NEW password.
--
-- Hosted note (D, S12): this file creates a trigger on auth.users and on
-- auth.sessions and reads auth.sessions from postgres-owned definers. The
-- pattern is the documented handle_new_user one; the harness's auth tables are
-- postgres-owned, so hosted privilege is proven only by the sandbox apply.
--
-- Census (public): +3 functions (revoke_all_push_bindings,
-- guard_push_token_session_stmt, guard_push_token_session_row), +2 triggers on
-- push_tokens → 99 / 37. Four kernel routines (157 A46 → 300). auth objects
-- are not counted. Applied nowhere.
-- ============================================================================
begin;

-- ── 1. the epoch ──────────────────────────────────────────────────────────────
alter table kernel.identity_ext
  add column if not exists push_binding_epoch timestamptz;
comment on column kernel.identity_ext.push_binding_epoch is
  '131: the instant of this identity''s last credential change (password change / sign-out-everywhere). A session created before it may not create, activate or delete a push binding. NULL = never bumped.';

-- ── 2. the invalidator (kernel, definer; the only writer of the epoch) ────────
create or replace function kernel.invalidate_push_bindings_for(p_uid uuid, p_reason text, p_epoch timestamptz default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_n     integer;
  v_epoch timestamptz;
begin
  if p_uid is null then return 0; end if;
  -- lock FIRST (see the header): everything that writes this user's bindings
  -- serializes here, in one order.
  perform pg_advisory_xact_lock(hashtext('push_bindings:' || p_uid::text));

  -- X4: GoTrue's clock (auth.users.updated_at, passed by the trigger) and ours
  -- can disagree; take the later one plus a small margin. A legitimate re-login
  -- inside the margin retries (client behaviour, contract §2.7 delta).
  v_epoch := greatest(coalesce(p_epoch, '-infinity'::timestamptz), clock_timestamp()) + interval '2 seconds';

  perform set_config('app.push_token_verb', 'on', true);          -- write guard bypass, definer path
  update public.push_tokens
     set is_active          = false,
         revoked_at         = coalesce(revoked_at, now()),
         revoked_reason     = p_reason,
         device_secret_hash = null
   where user_id = p_uid
     and (is_active or device_secret_hash is not null or revoked_reason is distinct from p_reason);
  get diagnostics v_n = row_count;
  perform set_config('app.push_token_verb', '', true);

  update kernel.identity_ext
     set push_binding_epoch = greatest(coalesce(push_binding_epoch, '-infinity'::timestamptz), v_epoch)
   where identity_id = p_uid;
  if not found then
    insert into kernel.identity_ext (identity_id, push_binding_epoch) values (p_uid, v_epoch);
  end if;

  -- S9: every send path selects push_tokens with is_active = true (the legacy
  -- supabase/functions/send-push reader and notify's claim path), so the
  -- revocation above is what stops delivery. The identity's channel state is
  -- deliberately NOT written from here: 092's seam rule (157 A48) allows no
  -- routine outside `notify` to touch notify's tables, and a revoked device
  -- needs no channel marker — the next failed send records it, and the next
  -- registration heals it.

  return v_n;
end;
$$;
revoke execute on function kernel.invalidate_push_bindings_for(uuid, text, timestamptz) from public, anon, authenticated, service_role;

-- ── 3. triggers on auth: password change; last live session gone ─────────────
create or replace function kernel.trg_push_bindings_on_password_change()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform kernel.invalidate_push_bindings_for(new.id, 'password_changed', new.updated_at);
  return new;
end;
$$;
revoke execute on function kernel.trg_push_bindings_on_password_change() from public, anon, authenticated, service_role;
drop trigger if exists trg_push_bindings_on_password_change on auth.users;
create trigger trg_push_bindings_on_password_change
  after update of encrypted_password on auth.users
  for each row
  when (old.encrypted_password is distinct from new.encrypted_password)
  execute function kernel.trg_push_bindings_on_password_change();

-- X5 (D): statement-level with a transition table, because GoTrue's global
-- sign-out deletes a user's sessions in one statement and the "none live
-- remain" test must see the whole statement's deletes. Only LIVE sessions
-- count (not_after null or future): expired-session cleanup deletes dead rows
-- and must not revoke a dormant user's bindings.
create or replace function kernel.trg_push_bindings_on_sessions_gone()
returns trigger language plpgsql security definer set search_path = '' as $$
declare r record;
begin
  for r in
    select distinct d.user_id
      from old_table d
     where d.not_after is null or d.not_after > now()
  loop
    if not exists (
      select 1 from auth.sessions s
       where s.user_id = r.user_id
         and (s.not_after is null or s.not_after > now())
    ) then
      perform kernel.invalidate_push_bindings_for(r.user_id, 'signed_out_everywhere');
    end if;
  end loop;
  return null;
end;
$$;
revoke execute on function kernel.trg_push_bindings_on_sessions_gone() from public, anon, authenticated, service_role;
drop trigger if exists trg_push_bindings_on_sessions_gone on auth.sessions;
create trigger trg_push_bindings_on_sessions_gone
  after delete on auth.sessions
  referencing old table as old_table
  for each statement
  execute function kernel.trg_push_bindings_on_sessions_gone();

-- ── 4. the session-age predicate (§2d; scope §4f: creating/activating acts only)
create or replace function kernel.push_session_predates_epoch(p_uid uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_epoch timestamptz;
  v_sid   uuid;
  v_made  timestamptz;
begin
  select push_binding_epoch into v_epoch from kernel.identity_ext where identity_id = p_uid;
  if v_epoch is null then return false; end if;                  -- never bumped: nothing to predate
  begin
    v_sid := (auth.jwt() ->> 'session_id')::uuid;
  exception when others then
    v_sid := null;
  end;
  if v_sid is null then return true; end if;                     -- no session claim: fail closed
  select created_at into v_made from auth.sessions where id = v_sid;
  if v_made is null then return true; end if;                    -- session gone (revoked): fail closed
  return v_made < v_epoch;
end;
$$;
revoke execute on function kernel.push_session_predates_epoch(uuid) from public, anon, authenticated, service_role;

-- ── 5. the client verb for "sign out everywhere" (fast path; §4f: no age check)
create or replace function public.revoke_all_push_bindings()
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_n integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  v_n := kernel.invalidate_push_bindings_for(v_uid, 'signed_out_everywhere');
  return jsonb_build_object('revoked', v_n, 'contract_version', 2);
end;
$$;
comment on function public.revoke_all_push_bindings() is
  '131: the caller revokes every push binding of their own account, clears every device proof and bumps their credential epoch — the client calls it immediately before signOut({scope: global}). Succeeds from ANY authenticated session (revocation only reduces exposure). Returns {revoked, contract_version: 2}.';
revoke execute on function public.revoke_all_push_bindings() from public, anon, service_role;
grant  execute on function public.revoke_all_push_bindings() to authenticated;

-- ── 6. the write-time guard on push_tokens (client roles only) ───────────────
-- Statement-level: take the per-user lock BEFORE the executor locks any row
-- (the X3 cycle was a row lock held while asking for the advisory lock).
create or replace function public.guard_push_token_session_stmt()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  if coalesce(current_setting('app.push_token_verb', true), '') = 'on' then return null; end if;
  v_uid := auth.uid();
  if v_uid is null then return null; end if;                     -- service_role / definers: not a client
  perform pg_advisory_xact_lock(hashtext('push_bindings:' || v_uid::text));
  return null;
end;
$$;
-- Row-level: the check, after the lock, under the statement's snapshot.
create or replace function public.guard_push_token_session_row()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_uid uuid;
begin
  if coalesce(current_setting('app.push_token_verb', true), '') = 'on' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if auth.uid() is null then                                     -- not a client path
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  v_uid := case when tg_op = 'DELETE' then old.user_id else new.user_id end;
  if tg_op = 'DELETE' or new.is_active then                      -- creating/activating/deleting only
    if kernel.push_session_predates_epoch(v_uid) then
      raise exception 'insufficient_privilege: session predates a credential change'
        using errcode = '42501';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke execute on function public.guard_push_token_session_stmt() from public, anon, authenticated, service_role;
revoke execute on function public.guard_push_token_session_row()  from public, anon, authenticated, service_role;
drop trigger if exists trg_guard_push_token_session_stmt on public.push_tokens;
create trigger trg_guard_push_token_session_stmt
  before insert or update or delete on public.push_tokens
  for each statement execute function public.guard_push_token_session_stmt();
drop trigger if exists trg_guard_push_token_session_row on public.push_tokens;
create trigger trg_guard_push_token_session_row
  before insert or update or delete on public.push_tokens
  for each row execute function public.guard_push_token_session_row();

-- ── 7. register_push_token: the same check, in the contract's words ──────────
-- Body = 128 @ f22c1a3 (contract v2) with two additions marked [131]: the
-- per-user lock after auth, and the session-age refusal before any write.
-- Everything else — rules 1/2/3/5, the heal, the flag reset, reply shape — is
-- byte-for-byte 128's.
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
    null;
  elsif v_row_user = v_uid then
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
           device_secret_hash = v_hash
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

commit;
