-- ============================================================================
-- 128_register_push_token_secure_rebind.sql — F7: a device may claim its own
-- push token; knowing a token string may NOT claim someone else's.
--
-- CONTRACT VERSION 2. Every reply carries `contract_version`; the client pins it.
--
-- THE DEFECT (F7, reproduced in the sandbox 2026-09-14). `usePushToken` selects
-- `public.push_tokens` by token, RLS hides another account's row, so the client
-- falls through to INSERT and `UNIQUE (token)` rejects it with 409. The device's
-- token stays bound to whoever registered it first: that phone keeps receiving
-- the OTHER account's notifications and none of its own.
--
-- WHY NOT notify.register_push_token. It rebinds on
-- `on conflict (token) do update set user_id = auth.uid()` — token knowledge
-- alone. This migration revokes it from `authenticated` (§4) rather than leaving
-- its unreachability resting on the PostgREST exposed-schema setting.
--
-- THE RULE. Rebinding requires proof of the DEVICE. The client keeps a random
-- secret in SecureStore; only its SHA-256 is stored.
--
--   1. no row for the token          -> bind to the caller, store the hash
--   2. row already the caller's      -> refresh; adopt a hash ONLY if it has
--                                       none. The stored hash is NEVER replaced
--                                       (PLANT-THEN-CLAIM below).
--   3. another's, hash matches       -> REBIND (the caller holds the device)
--   4. another's, hash does not match-> 42501, nothing written
--   5. another's, no hash            -> REBIND only under ALL of §2's
--                                       conditions. This is transitional, not a
--                                       standing door.
--
-- ── PLANT-THEN-CLAIM — why rule 2 must never REPLACE a stored hash ───────────
-- An earlier revision made rule 2 assign the presented hash unconditionally, to
-- let an owner rotate a lost secret. Adversarial review showed that converts
-- momentary session access into permanent, silent device capture: someone
-- briefly holding the victim's session plants a secret of their choosing (the
-- row stays victim-owned and active, and nothing surfaces the hash), then claims
-- the token later from their OWN account through rule 3. It survives password
-- reset and session revocation, because nothing clears the column. The lost-
-- secret case needs no rotation: the owner holds RLS DELETE on their own row, so
-- deleting and re-registering restores a working binding. Recovery by deletion.
--
-- ── §2 WHY RULE 5 IS GATED FOUR WAYS (review finding V2) ─────────────────────
-- Rule 5 was written as "the migration path", on three premises that were all
-- false in this deployment:
--   * "rows without a hash predate 128" — the shipping client does not call this
--     verb, so it keeps writing hash-less rows indefinitely;
--   * "a revoke means the owner released the device" — sign-out is the normal
--     end of EVERY session, and revoked rows are never purged;
--   * "is_active = false is a user act" — `notify.record_delivery_result` sets
--     it from a PROVIDER signal (`device_not_registered`), with no user
--     involved.
-- Left as it was, rule 5 was reachable with token knowledge alone: verbatim the
-- harm this migration exists to prevent. It now requires ALL of:
--   (a) `created_at < ` the epoch recorded when 128 first applied — so a
--       hash-less row written AFTER 128 (i.e. by the legacy client path) is
--       never claimable, which is what makes rule 5 transitional;
--   (b) `revoked_reason = 'signed_out'` — a sign-out, not a provider signal.
--       ONE spelling: `notify.revoke_push_token` is the only server writer and it
--       writes 'signed_out'. An earlier revision also accepted 'sign_out' for an
--       unshipped client helper; re-review found no writer of it in this tree, and
--       a second accepted value that only a client can author is surface for
--       nothing. The client helper is being changed to match.
--   (c) revoked within the last 30 days — a long-dead row is not a handover;
--   (d) `is_active` still false;
--   (e) SUNSET (V12): the whole rule stops working 90 days after the epoch.
--       Without it "transitional" was untrue — `revoked_at` is re-armed by EVERY
--       sign-out, and the pre-128 cohort never shrinks, so the door re-opened at
--       every sign-out indefinitely.
--
-- ── §3 WHAT THIS MIGRATION CANNOT CLOSE (review finding V3, recorded) ────────
-- Rule 1 binds an UNCLAIMED token with no proof, because no proof exists: the
-- database cannot tell who physically holds a token nobody has registered. So a
-- caller can squat a token they do not hold and lock the real device out. This
-- migration adds `public.unbind_push_token` (service_role only) so support can
-- recover a squatted token. NOTE, corrected by re-review: the rate limit inside
-- this verb is NOT a mitigation, because the shipping client squats through the
-- direct table INSERT it already uses, which never reaches this function. Do not
-- cite rate limiting as the defence. A real fix needs provider-side proof, which is
-- outside the database.
-- ============================================================================
begin;

-- ── 1. The epoch, and the device's proof ────────────────────────────────────
-- The epoch is deliberately NOT dropped by the rollback: after a rollback and
-- re-apply every stored hash is gone, and if the epoch moved with it, every
-- revoked row would become claimable again (review finding V5). Keeping the
-- FIRST epoch means rows created after it stay closed, and each device re-binds
-- its own hash on its next registration through rule 2.
create table if not exists public.push_token_rebind_epoch (
  singleton  boolean     primary key default true check (singleton),
  applied_at timestamptz not null    default now()
);
insert into public.push_token_rebind_epoch (singleton) values (true)
  on conflict (singleton) do nothing;

-- V11 (re-review, CRITICAL): a table created in `public` inherits the default
-- ACL that grants anon/authenticated DML, and `public` is the PostgREST-exposed
-- schema. Without this the epoch — the ONLY thing making rule 5 transitional —
-- was writable with the anon key: push `applied_at` into the future and every
-- hash-less row becomes claimable on token knowledge alone, which is V2 restored.
-- The repo's own CI gate (supabase/ci/assert_public_table_grant_decisions.sql)
-- fails on any public table with no recorded decision; this one is no-client-access.
alter table public.push_token_rebind_epoch enable row level security;
revoke all on public.push_token_rebind_epoch from public, anon, authenticated;
-- Explicit, not inherited: a CI replay has no Supabase default ACL, so without
-- this the privilege-parity step saw service_role holding only REFERENCES,
-- TRIGGER, TRUNCATE and failed the build (run 34926241630). The trigger below
-- still makes the row immutable at runtime; this is what the manifest's
-- no-client-access ("service_role only") and expected_grants.txt both state.
grant delete, insert, references, select, trigger, truncate, update
  on public.push_token_rebind_epoch to service_role;

-- Third-review residual, closed structurally: if the epoch ROW were deleted and
-- this file re-applied, the `on conflict do nothing` insert above would mint a
-- NEW epoch = now(), and every revoked hash-less row created in between would
-- become claimable under rule 5 for another 90 days. Clients cannot delete it
-- (REVOKEd above); this closes the operator path too. The row is immutable:
-- no UPDATE, DELETE or TRUNCATE by anyone short of dropping the trigger, which
-- is a deliberate act that a rollback does not perform (see the rollback header).
create or replace function public.guard_push_token_rebind_epoch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'push_token_rebind_epoch is immutable: moving or removing the epoch would reopen the legacy rebind path (128). Restore from the ledger instead.'
    using errcode = '42501';
end;
$$;

drop trigger if exists trg_guard_push_token_rebind_epoch on public.push_token_rebind_epoch;
create trigger trg_guard_push_token_rebind_epoch
  before update or delete or truncate on public.push_token_rebind_epoch
  for each statement execute function public.guard_push_token_rebind_epoch();

comment on table public.push_token_rebind_epoch is
  '128: when the device-proof rule first applied. Rule 5 (claiming a hash-less binding) is allowed only for rows created BEFORE this instant, which is what makes it transitional. Survives the 128 rollback on purpose — see the rollback header.';

alter table public.push_tokens
  add column if not exists device_secret_hash text;

comment on column public.push_tokens.device_secret_hash is
  '128: SHA-256 (hex) of the device-held secret that proves possession of this token. Written ONLY by public.register_push_token (enforced by trg_guard_push_token_secret_hash). NULL on rows written before 128 and by the legacy client path. The raw secret is never stored.';

-- ── 2. The proof column is not client-writable (review finding V4) ───────────
-- `authenticated` holds UPDATE on the table, so without this a client could NULL
-- its own hash to manufacture a "hash-less, revoked" row on demand and forge the
-- very precondition rule 5 keys on, or insert a row with a hash of its choosing
-- and bypass the length floor entirely.
create or replace function public.guard_push_token_secret_hash()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Set transaction-locally by register_push_token, the one legitimate writer.
  -- Transaction-local is the right scope here because PostgREST runs each
  -- request in its own transaction, and no client can run raw SQL alongside
  -- the verb in one. A future server-side caller that batches other writes
  -- into the same transaction as this verb would bypass the guard for them.
  if coalesce(current_setting('app.push_token_verb', true), '') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' and new.device_secret_hash is not null then
    raise exception 'device_secret_hash is written only by public.register_push_token'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.device_secret_hash is distinct from old.device_secret_hash then
    raise exception 'device_secret_hash is written only by public.register_push_token'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_push_token_secret_hash on public.push_tokens;
create trigger trg_guard_push_token_secret_hash
  before insert or update on public.push_tokens
  for each row execute function public.guard_push_token_secret_hash();

-- ── 3. The registration / rebinding verb ────────────────────────────────────
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

comment on function public.register_push_token(text, text, text, text) is
  '128 v2 (F7): registers or rebinds this device''s push token. Rebinding requires the device-held secret, never mere knowledge of the token string. A hash-less binding is claimable only when it predates the 128 epoch, was revoked by a SIGN-OUT (not a provider signal) within 30 days, and is still inactive. Raises 42501 otherwise, writing nothing. Every success clears last_provider_error and heals the caller''s push channel (notify.identity_channel_state unreachable -> ok, §17.24), exactly as the legacy verb did. notify.register_push_token is revoked from authenticated by this migration — it rebinds on the token alone.';

-- ── 4. Support recovery for a squatted token (review finding V3) ────────────
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

-- ── 5. Grants (SEC-2: explicit REVOKE, then only the intended GRANT) ────────
revoke execute on function public.register_push_token(text, text, text, text) from public, anon, service_role;
grant  execute on function public.register_push_token(text, text, text, text) to authenticated;

revoke execute on function public.unbind_push_token(text) from public, anon, authenticated;
grant  execute on function public.unbind_push_token(text) to service_role;

revoke execute on function public.guard_push_token_secret_hash() from public, anon, authenticated, service_role;
revoke execute on function public.guard_push_token_rebind_epoch() from public, anon, authenticated, service_role;

-- Third-review residual: the proof column was client-READABLE. `push_tokens` is
-- client-dml, so `authenticated` held table-level SELECT and could read the
-- unsalted SHA-256 of a client-chosen secret from its own rows — an offline
-- guessing oracle if RLS ever widened or a secret were weak. Postgres column
-- privileges are additive, so the only way to withhold ONE column is to drop the
-- table-level SELECT and grant the rest by name. The shipped client selects only
-- `id` (src/hooks/usePushToken.ts:71-75); inserts and updates return minimal.
-- Table-level INSERT/UPDATE/DELETE are untouched: the write guard above covers
-- the column, and narrowing them is not this finding.
revoke select on public.push_tokens from anon, authenticated;
grant  select (id, user_id, token, platform, device_name, created_at, last_used, is_active,
               revoked_at, revoked_reason, provider_receipt_checked_at, last_provider_error)
  on public.push_tokens to authenticated;

-- The insecure verb this migration exists to replace. `authenticated` still held
-- EXECUTE on it plus USAGE on the schema (092:207, 092:1178); only the PostgREST
-- exposed-schema list kept it unreachable, and that is a Dashboard field, not in
-- git, not guarded by any migration — and exposing `notify` is already planned.
revoke execute on function notify.register_push_token(text, text, text, text) from authenticated;

commit;
