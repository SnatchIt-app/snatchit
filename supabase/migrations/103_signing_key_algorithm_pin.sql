-- ============================================================================
-- 103_signing_key_algorithm_pin.sql — PFA-PT-8: pin the signature algorithm
-- per trusted signing key so a token can NEVER choose its own verification
-- algorithm merely by declaring `alg` in its header.
--
-- WHAT THIS MIGRATION IS. DARK / unapplied / undeployed. Production is at
-- ledger 107 (through 092); 093-102 are authored, NOT applied. 093-102 are
-- IMMUTABLE — this migration touches kernel.signing_key ADDITIVELY (one new
-- column) and re-creates two functions via CREATE OR REPLACE (the 083
-- immutability guard and the 102 signing-context authority). No DROP, no
-- column/table change to anything 093-102 owns, no public-schema object, no
-- new config key. Next migration after 102.
--
-- THE DEFECT (PFA-PT-8, from the package-102 adversarial pass). The credential
-- token's protected header carries `alg`, and it is inside the SIGNED bytes so
-- it cannot be altered without breaking the signature — but kernel.signing_key
-- has NO algorithm column (083:49-70), so the trusted keyring cannot itself
-- state which algorithm a given key must be verified under. The reference
-- verifier therefore selected the verify primitive from the TOKEN-HEADER `alg`.
-- That is BOUNDED today (verifying an ES256 header against an Ed25519 SPKI, or
-- vice-versa, fails on key-type mismatch inside the primitive), but relying on
-- the primitive to reject a mismatch is weaker than pinning. Owner direction
-- (PFA-PT-8): the header alg is INFORMATIONAL; verification AUTHORITY is the
-- trusted key's own algorithm. `trusted_key.algorithm == token.header.alg` or
-- REFUSE. No fallback, no "try EdDSA then ES256", no `none`, no key-type or
-- symmetric confusion.
--
-- SOURCES READ, NOT ASSUMED: 083:49-125 (kernel.signing_key DDL, the
-- guard_signing_key_immutable trigger, and the column-fenced authenticated
-- grant — public_key/window/status are distributed, kms_handle_ref is not);
-- 102:136-248 (kernel.get_ticket_signing_context, reproduced verbatim below
-- except the algorithm resolution); EDGE_FUNCTION_SPEC §5.1 (Ed25519 preferred,
-- ECDSA-P256 acceptable), §5.4.2 (M1 manifest is a projection of the
-- world-readable kernel.signing_key columns — so the algorithm must be a
-- GRANTED, distributable column for a door to pin it), §5.4.3
-- OFFLINE-VERIFY-v1 (conjunct 2 verifies the signature; PFA-PT-8 binds the
-- algorithm that verification runs under); PRODUCTION_SIGNING_KMS_CEREMONY.md
-- D2 (algorithm is a ceremony decision — Ed25519 where the provider offers it,
-- ECDSA-P256 (SHA-256) the ratified fallback; AWS KMS offers no Ed25519).
-- ============================================================================

begin;

-- ============================================================================
-- PART 1 — the algorithm column. ADDITIVE, NOT NULL with a default so the
-- ALTER is safe against any existing row (production has zero signing keys;
-- test fixtures that do not name it inherit the §5.1-preferred default). A
-- constrained two-value enum — never an arbitrary string, never RSA (the
-- architecture does not sanction it), never a symmetric name, never `none`.
-- The ceremony sets the value EXPLICITLY to match the key material it creates
-- (ES256 on AWS KMS, EdDSA on a provider that offers Ed25519) — the default is
-- only a safe fallback for un-named inserts, never a substitute for the
-- ceremony stating the truth.
-- ============================================================================
alter table kernel.signing_key
  add column if not exists algorithm text not null default 'EdDSA'
    check (algorithm in ('EdDSA','ES256'));

comment on column kernel.signing_key.algorithm is
  'PFA-PT-8: the signature algorithm this key signs and is verified under. Immutable after creation (guard_signing_key_immutable). PUBLIC verification metadata — distributed in the M1 key manifest alongside public_key/window/status, granted to authenticated; it is NOT private material. A verifier MUST pin THIS value and refuse a token whose header alg disagrees. Default EdDSA (§5.1 preferred); the KMS ceremony sets ES256 explicitly when the provider offers no Ed25519 (D2).';

-- ============================================================================
-- PART 2 — immutability. algorithm joins public_key/kms_handle_ref/scope/
-- target/not_before as immutable after creation: a key's algorithm is a
-- property of its key material and can never be re-labelled (re-labelling
-- would let an operator silently point the verifier at the wrong primitive).
-- Body-only re-create of 083's guard; every other clause is byte-identical.
-- ============================================================================
create or replace function kernel.guard_signing_key_immutable()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.public_key <> old.public_key or new.kms_handle_ref <> old.kms_handle_ref
     or new.scope <> old.scope
     or new.event_id is distinct from old.event_id or new.venue_id is distinct from old.venue_id
     or new.not_before <> old.not_before
     or new.algorithm <> old.algorithm then
    raise exception 'append_only: signing_key identity/target/public_key/kms_handle/algorithm is immutable after creation'
      using errcode = 'P0001';
  end if;
  -- forward-only status: active -> rotating|revoked ; rotating -> active|revoked ; revoked terminal
  if old.status = 'revoked' and new.status <> 'revoked' then
    raise exception 'append_only: signing_key status is forward-only (revoked is terminal)' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

-- ============================================================================
-- PART 3 — grant. algorithm is public verification metadata, so it joins the
-- distributable column projection (NOT kms_handle_ref, which stays fenced). A
-- door that caches the M1 manifest reads algorithm from exactly this grant to
-- pin it. Additive column grant; the 083 grant is otherwise untouched.
-- ============================================================================
grant select (algorithm) on kernel.signing_key to authenticated;

-- ============================================================================
-- PART 4 — kernel.get_ticket_signing_context returns the REAL algorithm.
-- Body-only re-create of 102:136-248; the ONLY changes are: declare
-- v_algorithm, read k.algorithm alongside the other key columns, and return it
-- in place of the literal null 102 shipped (102 returned null because the
-- column did not exist yet). Every other line — the auth check, ownership
-- gate, terminal gate, pinned-key resolution, TTL, admin_audit rows, grants —
-- is byte-identical to 102. The credential-sign edge and its buildHeader then
-- stamp the token header `alg` from THIS value rather than a client/default
-- guess, and the verifier pins the same value from the trusted key.
-- ============================================================================
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
  v_algorithm    text;
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

  if v_owner is null or v_owner <> v_uid then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'not_owner',
            null, jsonb_build_object('outcome', 'not_owner'));
    return jsonb_build_object('status', 'refused', 'code', 'not_owner');
  end if;

  if v_state in ('voided', 'scanned', 'expired') then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'atom_terminal',
            null, jsonb_build_object('outcome', 'atom_terminal', 'state', v_state));
    return jsonb_build_object('status', 'refused', 'code', 'atom_terminal');
  end if;

  select k.status, k.not_before, k.not_after, k.public_key, k.kms_handle_ref, k.algorithm
    into v_key_status, v_not_before, v_not_after, v_public_key, v_kms_ref, v_algorithm
    from kernel.signing_key k
   where k.key_id = v_pinned_key;

  if v_key_status is null or v_key_status <> 'active'
     or v_not_before > now() or (v_not_after is not null and v_not_after <= now()) then
    insert into kernel.admin_audit (actor_identity, action, subject_kind, subject_id, reason_code, before, after)
    values (v_uid, 'credential.sign_context', 'ticket_atom', p_ticket_atom_id, 'signing_key_unavailable',
            null, jsonb_build_object('outcome', 'signing_key_unavailable', 'key_id', v_pinned_key));
    return jsonb_build_object('status', 'refused', 'code', 'signing_key_unavailable');
  end if;

  select (c.value #>> '{}')::interval into v_ttl
    from catalog.platform_config c
   where c.key = 'credential.app_ttl_interval'
   order by c.version desc limit 1;

  v_issued_at := now();
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
    'algorithm', v_algorithm,
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
  'The credential-sign edge''s ONLY source of signing facts (EDGE_FUNCTION_SPEC §3.2/§5). Owner-gated (current_owner_id=auth.uid(), else refused not_owner — indistinguishable from a nonexistent atom); atom_terminal on voided/scanned/expired; resolves the atom''s PINNED signing_key_id only (§5.2), refusing signing_key_unavailable if that key is missing/inactive/out-of-window. Returns the key''s pinned ALGORITHM (PFA-PT-8, migration 103) so the signer stamps and the verifier pins the same value. Writes no custody; the one write is an optional non-secret admin_audit row. NEVER returns private key material — kms_handle_ref is a KMS handle, not a key.';

commit;
