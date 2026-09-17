-- ============================================================================
-- 103_signing_key_algorithm_pin_rollback.sql — REVERSES 103.
--
-- POSTURE: forward-fix preferred. This restores kernel.get_ticket_signing_
-- context to its 102 body (algorithm returned as literal null), restores
-- kernel.guard_signing_key_immutable to its 083 body (no algorithm clause),
-- and DROPS kernel.signing_key.algorithm. Safe: production has zero signing
-- keys, and the column is additive with a default — dropping it loses only the
-- pinned-algorithm metadata, reverting the verifier to token-header-alg
-- (BOUNDED-safe, the pre-103 state). Order matters: the function must stop
-- reading k.algorithm BEFORE the column is dropped.
-- ============================================================================
begin;

-- 1. restore get_ticket_signing_context to the 102 body (stops reading k.algorithm).
create or replace function kernel.get_ticket_signing_context(p_ticket_atom_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid          uuid;
  v_owner        uuid;
  v_state        text;
  v_session      uuid;
  v_cred_ver     integer;
  v_pinned_key   uuid;
  v_key_status   text;
  v_not_before   timestamptz;
  v_not_after    timestamptz;
  v_public_key   text;
  v_kms_ref      text;
  v_ttl          interval;
  v_issued_at    timestamptz;
  v_exp          timestamptz;
  v_code         text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;

  select t.current_owner_id, t.state, t.event_session_id,
         t.credential_version, t.signing_key_id
    into v_owner, v_state, v_session, v_cred_ver, v_pinned_key
    from kernel.tickets t
   where t.ticket_atom_id = p_ticket_atom_id;

  -- OWNERSHIP GATE — a nonexistent atom (v_owner null) and a real atom owned
  -- by someone else both refuse `not_owner`; the caller learns nothing about
  -- whether the id exists.
  if v_owner is null or v_owner <> v_uid then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'not_owner',
            null, jsonb_build_object('outcome', 'not_owner'));
    return jsonb_build_object('status', 'refused', 'code', 'not_owner');
  end if;

  -- TERMINAL GATE — voided/scanned/expired are dead; listed/locked/
  -- refund_hold/dispute_hold still sign (the door refuses admission, not this
  -- function — see the header note).
  if v_state in ('voided', 'scanned', 'expired') then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'atom_terminal',
            null, jsonb_build_object('outcome', 'atom_terminal', 'state', v_state));
    return jsonb_build_object('status', 'refused', 'code', 'atom_terminal');
  end if;

  -- PINNED-KEY RESOLUTION — the atom's OWN signing_key_id, not a fresh scope
  -- lookup (§5.2). Missing/inactive/out-of-window all collapse to the same
  -- ops-critical refusal.
  select k.status, k.not_before, k.not_after, k.public_key, k.kms_handle_ref
    into v_key_status, v_not_before, v_not_after, v_public_key, v_kms_ref
    from kernel.signing_key k
   where k.key_id = v_pinned_key;

  if v_key_status is null or v_key_status <> 'active'
     or v_not_before > now() or (v_not_after is not null and v_not_after <= now()) then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'signing_key_unavailable',
            null, jsonb_build_object('outcome', 'signing_key_unavailable', 'key_id', v_pinned_key));
    return jsonb_build_object('status', 'refused', 'code', 'signing_key_unavailable');
  end if;

  -- TTL — credential.app_ttl_interval (078:1530, seeded '"4 hours"', public;
  -- the highest-version-wins idiom used throughout this corpus).
  select (c.value #>> '{}')::interval into v_ttl
    from catalog.platform_config c
   where c.key = 'credential.app_ttl_interval'
   order by c.version desc limit 1;

  v_issued_at := now();
  -- v_ttl is guaranteed non-null: 078 seeds credential.app_ttl_interval with a
  -- real value at version 1 (not an owner-STOP null seed) and
  -- catalog.platform_config is append-only, so no reachable post-078 state
  -- leaves it unset. No fallback default is invented here on that basis.
  v_exp := v_issued_at + v_ttl;

  insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
  values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'ok',
          null, jsonb_build_object('outcome', 'ok', 'credential_version', v_cred_ver, 'key_id', v_pinned_key));

  return jsonb_build_object(
    'status', 'ok',
    'ticket_atom_id', p_ticket_atom_id,
    'session_id', v_session,
    'credential_version', v_cred_ver,
    'key_id', v_pinned_key,
    'kms_handle_ref', v_kms_ref,
    'public_key', v_public_key,
    'algorithm', null,
    'not_before', v_not_before,
    'not_after', v_not_after,
    'issued_at', v_issued_at,
    'ttl_seconds', extract(epoch from v_ttl)::integer,
    'exp', v_exp,
    'domain', 'SNATCHIT-TICKET-CRED-V1'
  );
end;
$$;

comment on function kernel.get_ticket_signing_context(uuid) is
  'The credential-sign edge''s ONLY source of signing facts (EDGE_FUNCTION_SPEC §3.2/§5). Owner-gated; atom_terminal on voided/scanned/expired; resolves the atom''s PINNED signing_key_id only (§5.2). NEVER returns private key material.';

-- 2. restore the 083 immutability guard (drops the algorithm-immutable clause).
create or replace function kernel.guard_signing_key_immutable()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.public_key <> old.public_key or new.kms_handle_ref <> old.kms_handle_ref
     or new.scope <> old.scope
     or new.event_id is distinct from old.event_id or new.venue_id is distinct from old.venue_id
     or new.not_before <> old.not_before then
    raise exception 'append_only: signing_key identity/target/public_key/kms_handle is immutable after creation'
      using errcode = 'P0001';
  end if;
  if old.status = 'revoked' and new.status <> 'revoked' then
    raise exception 'append_only: signing_key status is forward-only (revoked is terminal)' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- 3. drop the column (its authenticated grant drops with it).
alter table kernel.signing_key drop column if exists algorithm;

commit;
