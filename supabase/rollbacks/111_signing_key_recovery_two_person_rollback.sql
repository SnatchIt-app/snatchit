-- ============================================================================
-- 111_signing_key_recovery_two_person_rollback.sql — mechanical reversal of
-- migration 111 (E4 two-person post-revoke recovery). MECHANICAL-REVERSIBILITY
-- REHEARSAL ONLY (production is forward-only). Drops the approval table and the
-- three E4 functions, then RE-CREATES migration 110's guard body VERBATIM (this
-- text is generated from 110_signing_key_insert_guard.sql, not hand-copied) so
-- rule 10 returns to `post_revoke_recovery_parked` (fail closed). Idempotent.
-- ============================================================================
begin;

drop function if exists kernel.execute_signing_key_recovery(uuid,text,text,text,text);
drop function if exists kernel.approve_signing_key_recovery(uuid,text,text,text);
drop table if exists kernel.signing_key_recovery_approval;
drop function if exists kernel.signing_key_p256_pem_fingerprint(text);

-- migration 110's guard, verbatim:
create or replace function kernel.guard_signing_key_insert()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  c_bootstrap_key constant uuid  := '00000000-0000-0000-0000-0000000000b0';
  -- SEQUENCE(89){ AlgorithmIdentifier{ id-ecPublicKey, prime256v1 }, BIT STRING(66, 0 unused) }
  c_p256_prefix   constant bytea := decode('3059301306072a8648ce3d020106082a8648ce3d030107034200', 'hex');
  v_body text;
  v_der  bytea;
begin
  -- 1 scope — only global rows can be inserted while provision/rotate are parked.
  if new.scope is distinct from 'global' then
    raise exception 'signing_key_insert_refused: scoped_key_parked — per_event/per_venue keys are written only by kernel.provision_signing_key / rotate_signing_key, which are parked (PFA-18A); a scoped row would shadow the global key at the next mint (093 resolver), so no scoped INSERT path exists'
      using errcode = 'P0001';
  end if;

  -- 2 status — an inserted key is born active; 'rotating' is rotation (parked), 'revoked' is a terminal state reached only by revoke.
  if new.status is distinct from 'active' then
    raise exception 'signing_key_insert_refused: status_must_be_active — a signing key is inserted active; rotating/revoked are lifecycle states written by the (parked) lifecycle functions'
      using errcode = 'P0001';
  end if;

  -- 3 algorithm — the ratified ES256 contract (D2). The 103 column default 'EdDSA'
  --   can never survive an INSERT; there is deliberately NO override of any kind.
  if new.algorithm is distinct from 'ES256' then
    raise exception 'signing_key_insert_refused: algorithm_not_es256 — the ratified bootstrap contract is AWS KMS / ES256 (D2, PFA-PT-8); algorithm must be supplied explicitly as ES256'
      using errcode = 'P0001';
  end if;

  -- 4 kms_handle_ref — a FULL AWS KMS key ARN (D4): region, 12-digit account, key UUID. Never an alias, bare id, or placeholder.
  if new.kms_handle_ref !~ '^arn:aws:kms:[a-z]{2}(-[a-z]+)+-[0-9]:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    raise exception 'signing_key_insert_refused: kms_handle_not_key_arn — kms_handle_ref must be a full AWS KMS key ARN (arn:aws:kms:<region>:<12-digit account>:key/<uuid>)'
      using errcode = 'P0001';
  end if;

  -- 5 private material — never, under any label.
  if position('PRIVATE KEY' in new.public_key) > 0 then
    raise exception 'signing_key_insert_refused: public_key_private_material — public_key contains PRIVATE KEY material; stop the ceremony'
      using errcode = 'P0001';
  end if;

  -- 6 public_key — exactly one SPKI PUBLIC KEY PEM block (D3) whose DER is the
  --   91-byte uncompressed P-256 SubjectPublicKeyInfo (what AWS KMS GetPublicKey
  --   and openssl emit). The D5 fingerprint is defined over exactly these bytes.
  v_body := substring(new.public_key from '^[[:space:]]*-----BEGIN PUBLIC KEY-----\r?\n([A-Za-z0-9+/=\r\n]+)\r?\n-----END PUBLIC KEY-----[[:space:]]*$');
  if v_body is null then
    raise exception 'signing_key_insert_refused: public_key_not_spki_pem — public_key must be exactly one -----BEGIN PUBLIC KEY----- … -----END PUBLIC KEY----- block (SPKI PEM, D3)'
      using errcode = 'P0001';
  end if;
  begin
    v_der := decode(regexp_replace(v_body, '[\r\n]', '', 'g'), 'base64');
  exception when others then
    v_der := null;
  end;
  if v_der is null or length(v_der) <> 91
     or substring(v_der from 1 for 26) <> c_p256_prefix
     or get_byte(v_der, 26) <> 4 then
    raise exception 'signing_key_insert_refused: public_key_not_p256_uncompressed — the PEM must decode to the 91-byte uncompressed P-256 SubjectPublicKeyInfo (id-ecPublicKey / prime256v1 / 0x04 point) that ES256 verification pins'
      using errcode = 'P0001';
  end if;

  -- 7 serialize all global inserts (see CONCURRENCY above).
  perform pg_advisory_xact_lock(hashtext('kernel.signing_key:global_insert'));

  -- 8 duplicate key_id — an explicit, named refusal ahead of the PRIMARY KEY.
  if exists (select 1 from kernel.signing_key k where k.key_id = new.key_id) then
    raise exception 'signing_key_insert_refused: duplicate_key_id — a signing_key row with this key_id already exists (append-only: revoked rows are never re-used)'
      using errcode = 'P0001';
  end if;

  -- 9 exactly one active global — rotation (active→rotating overlap) is parked.
  if exists (select 1 from kernel.signing_key k where k.scope = 'global' and k.status in ('active','rotating')) then
    raise exception 'signing_key_insert_refused: active_global_exists — exactly one active global signing key is permitted; rotation/replacement of a live key is parked (PFA-18A) and revocation (PFA-18B) is the only lifecycle transition'
      using errcode = 'P0001';
  end if;

  -- 10 post-revoke recovery — FAIL CLOSED (no two-person mechanism exists yet).
  if exists (select 1 from kernel.signing_key k where k.scope = 'global' and k.status = 'revoked') then
    raise exception 'signing_key_insert_refused: post_revoke_recovery_parked — a global key has been revoked; re-bootstrap requires the gated TWO-PERSON recovery artifact (PFA-18C maturity trigger / E4), which is not yet ratified or built; this rule is replaced only by that migration'
      using errcode = 'P0001';
  end if;

  -- 11 lineage — the first-ever global row is the ruling-B bootstrap key_id.
  if new.key_id <> c_bootstrap_key then
    raise exception 'signing_key_insert_refused: bootstrap_key_id_required — the initial global trust root must carry the sanctioned bootstrap key_id (ruling B, ceremony §6.1); any other key_id is not the ratified lineage'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;
revoke all on function kernel.guard_signing_key_insert() from public, anon, authenticated, service_role;

commit;
