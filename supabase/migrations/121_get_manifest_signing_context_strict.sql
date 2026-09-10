-- ============================================================================
-- 121_get_manifest_signing_context_strict.sql — PFA-18C forward fix for the
-- 114 L121 defect (C4 package §5.2b D1; recorded "before C6").
--
-- THE DEFECT (114:121). venue.get_manifest_signing_context() counts the active
-- global rows (v_n), returns a stable `unavailable` code when v_n is 0 or > 1,
-- and then re-reads the row with a NON-STRICT `select * into v_k`. The two
-- statements run under separate READ COMMITTED snapshots inside a STABLE
-- function, so a revoke (106: status → 'revoked') or any status flip that
-- commits between the count and the select makes the second read return no
-- row. A non-STRICT `select into` does not raise on zero rows: v_k is filled
-- with NULLs, every subsequent comparison (`not_before > now()`,
-- `algorithm <> 'ES256'`) is NULL and therefore not true, and the function
-- returns {status:'ok', key_id:null, kms_handle_ref:null, public_key:null, …}
-- instead of {status:'unavailable', code:'no_active_global_key'}.
--
-- EFFECT ON THE DARK DEPLOYMENT (C6). The door-manifest edge treats
-- status='ok' as "sign with this identity". With null key_id/kms_handle_ref/
-- public_key the E2 signer fails closed (aws_sts_config_invalid / kms handle
-- scope / signature verify), so no bad manifest is served — but the failure
-- surfaces as a signer error class, not as the stable `unavailable` code the
-- edge maps to a clean 503, and the log line carries key_id=null. The contract
-- promised by 114's comment ("stable unavailable codes") is violated exactly in
-- the revoke race, i.e. during an incident. This migration closes that gap.
--
-- THE FIX. Body-only re-create of the same function: `select * into STRICT v_k`
-- inside a nested block whose exception handlers map `no_data_found` →
-- {unavailable, no_active_global_key} and `too_many_rows` →
-- {unavailable, ambiguous_active_global_key}. Everything else — signature,
-- STABLE, SECURITY DEFINER, search_path = '', the count pre-checks, the window
-- and algorithm checks, the ok payload, the comment (extended), the grants
-- (service_role only) — is unchanged. Census: 0 (no object added or removed).
-- Applied migration 114 is NOT edited. Rollback: supabase/rollbacks/121_….sql
-- restores the 114 body verbatim.
--
-- SOURCES READ, NOT ASSUMED: 114:108-137 (the body reproduced below with the
-- one change); 106:174-177 (revoke sets status only); 083:77-78
-- (signing_key_active_global_uq — why too_many_rows is unreachable but still
-- fails closed); PHASE2_PFA18C_C4_MIGRATIONS_110_114_EXECUTION_PACKAGE.md §5.2b
-- D1; supabase/functions/door-manifest/index.ts (status mapping).
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
  -- 121: STRICT. The count above and this select run under separate snapshots;
  -- a status flip committing between them must yield the stable unavailable
  -- code, never an ok payload of NULLs (114 L121 defect).
  begin
    select * into strict v_k from kernel.signing_key k where k.scope = 'global' and k.status = 'active';
  exception
    when no_data_found then
      return jsonb_build_object('status', 'unavailable', 'code', 'no_active_global_key');
    when too_many_rows then
      return jsonb_build_object('status', 'unavailable', 'code', 'ambiguous_active_global_key');
  end;
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
  'The door-manifest edge''s ONLY source of the manifest-signing key identity (DOOR-MANIFEST-SIG-v1 signature.key_id): the single active global kernel.signing_key row — key_id, kms_handle_ref (a KMS handle per runbook D4, NOT key material; never returned to a client), algorithm (must be ES256), public_key (the edge verifies every signature under it before responding), window. Stable unavailable codes: no_active_global_key | ambiguous_active_global_key | key_window | algorithm_not_es256. service_role only. Closes P2-MANIFEST-KEY. 121: the row read is STRICT (no_data_found/too_many_rows map to the stable unavailable codes) so a status flip between the count and the read can never yield an ok payload of NULLs.';
revoke all on function venue.get_manifest_signing_context() from public, anon, authenticated;
grant execute on function venue.get_manifest_signing_context() to service_role;

commit;
