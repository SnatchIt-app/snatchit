-- ============================================================================
-- 121_get_manifest_signing_context_strict_rollback.sql — restores the 114 body
-- of venue.get_manifest_signing_context() verbatim (114:108-137), re-opening
-- the 114 L121 non-STRICT read. Body-only; grants and comment restored to the
-- 114 text; census 0. Production is forward-only by policy — this is an
-- emergency measure requiring its own authorization.
-- ============================================================================
begin;

create or replace function venue.get_manifest_signing_context()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_k kernel.signing_key%rowtype; v_n integer;
begin
  select count(*) into v_n from kernel.signing_key k where k.scope = 'global' and k.status = 'active';
  if v_n = 0 then
    return jsonb_build_object('status', 'unavailable', 'code', 'no_active_global_key');
  end if;
  if v_n > 1 then
    -- unreachable under signing_key_active_global_uq; fail closed rather than pick one.
    return jsonb_build_object('status', 'unavailable', 'code', 'ambiguous_active_global_key');
  end if;
  select * into v_k from kernel.signing_key k where k.scope = 'global' and k.status = 'active';
  if v_k.not_before > now() or (v_k.not_after is not null and v_k.not_after <= now()) then
    return jsonb_build_object('status', 'unavailable', 'code', 'key_window', 'key_id', v_k.key_id);
  end if;
  if v_k.algorithm <> 'ES256' then
    return jsonb_build_object('status', 'unavailable', 'code', 'algorithm_not_es256', 'key_id', v_k.key_id);
  end if;
  return jsonb_build_object(
    'status', 'ok', 'key_id', v_k.key_id, 'scope', v_k.scope,
    'kms_handle_ref', v_k.kms_handle_ref, 'algorithm', v_k.algorithm, 'public_key', v_k.public_key,
    'key_status', v_k.status, 'not_before', v_k.not_before, 'not_after', v_k.not_after);
end;
$$;
comment on function venue.get_manifest_signing_context() is
  'The door-manifest edge''s ONLY source of the manifest-signing key identity (DOOR-MANIFEST-SIG-v1 signature.key_id): the single active global kernel.signing_key row — key_id, kms_handle_ref (a KMS handle per runbook D4, NOT key material; never returned to a client), algorithm (must be ES256), public_key (the edge verifies every signature under it before responding), window. Stable unavailable codes: no_active_global_key | ambiguous_active_global_key | key_window | algorithm_not_es256. service_role only. Closes P2-MANIFEST-KEY.';
revoke all on function venue.get_manifest_signing_context() from public, anon, authenticated;
grant execute on function venue.get_manifest_signing_context() to service_role;

commit;
