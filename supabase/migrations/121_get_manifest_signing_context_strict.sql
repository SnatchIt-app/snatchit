-- ============================================================================
-- 121_get_manifest_signing_context_strict.sql — PFA-18C defensive hardening of
-- venue.get_manifest_signing_context(): explicit missing-row handling on the
-- active-global row read (C4 package §5.2b D1, "review before C6").
--
-- WHAT THIS IS — AND IS NOT. This is NOT a demonstrated production defect.
-- The 114 function is STABLE, and every statement inside a STABLE PL/pgSQL
-- function reads the CALLING query's snapshot: the `count(*)` pre-check and the
-- subsequent `select * into v_k` see the same rows, so a status flip (e.g. a
-- 106 revoke) committing between them is NOT visible to the second read. The
-- concurrent-revoke race described in the first draft of this header is
-- therefore not reachable in the current function (Claude A review of PR #58,
-- 2026-09-10, with a concurrent STABLE/VOLATILE experiment; reproduced by
-- Claude B on a local replica: with a `pg_sleep` between count and read and a
-- concurrent status flip, the STABLE variant returned the original row, the
-- VOLATILE variant returned an ok payload of NULLs — i.e. the exposure would
-- exist only if the function were ever made VOLATILE or its reads split across
-- statements/snapshots).
--
-- WHY HARDEN ANYWAY. The 114 body still expresses "exactly one row" only via
-- the pre-check count; the row read itself is non-STRICT, so its correctness
-- depends on the STABLE snapshot property staying true through future edits
-- (a later body-only re-create marking it VOLATILE, or moving the read into a
-- separate query, would silently reintroduce an ok-of-NULLs path). Making the
-- read STRICT and mapping `no_data_found` / `too_many_rows` to the stable
-- `unavailable` codes states the invariant in the code and fails closed by
-- construction, independent of volatility. It changes no observable result of
-- the current function (suite 180 unchanged; suite 189 pins the contract).
--
-- EFFECT ON THE DARK DEPLOYMENT (C6). None required for correctness today; the
-- door-manifest edge already receives the stable codes and, in the non-reachable
-- NULL case, the E2 signer would fail closed. 121 is recommended before C6 as
-- hardening, not as a blocker. Sibling: kernel.get_ticket_signing_context
-- (102/103) already fails closed through its explicit null guard — no
-- deployment blocker there (Claude A).
--
-- THE CHANGE. Body-only re-create of the same function: `select * into STRICT
-- v_k` inside a nested block whose handlers map `no_data_found` →
-- {unavailable, no_active_global_key} and `too_many_rows` →
-- {unavailable, ambiguous_active_global_key}. Signature, STABLE, SECURITY
-- DEFINER, search_path = '', the count pre-checks, the window and algorithm
-- checks, the ok payload, the grants (service_role only) and the comment
-- (extended by one sentence) are unchanged. Census: 0. Applied migration 114
-- is NOT edited. Rollback: supabase/rollbacks/121_….sql restores the 114 body
-- verbatim (definition md5 b14d938e… = production).
--
-- SOURCES READ, NOT ASSUMED: 114:108-137 (the body reproduced below with the
-- one change); PostgreSQL docs, "Function Volatility Categories" (STABLE
-- functions use the snapshot of the calling query); 083:77-78
-- (signing_key_active_global_uq — why too_many_rows is unreachable but still
-- fails closed); Claude A's PR #58 review; the local STABLE/VOLATILE
-- reproduction recorded in docs/release/PHASE2_PFA18C_121_FORWARD_FIX_PACKAGE.md.
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
  -- 121: STRICT (defensive hardening). This function is STABLE, so the count
  -- above and this read share the calling query's snapshot and a concurrent
  -- status flip cannot make them disagree today. STRICT states the "exactly
  -- one row" invariant in the code so it fails closed by construction even if
  -- the function were ever made VOLATILE or the reads split across snapshots.
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
  'The door-manifest edge''s ONLY source of the manifest-signing key identity (DOOR-MANIFEST-SIG-v1 signature.key_id): the single active global kernel.signing_key row — key_id, kms_handle_ref (a KMS handle per runbook D4, NOT key material; never returned to a client), algorithm (must be ES256), public_key (the edge verifies every signature under it before responding), window. Stable unavailable codes: no_active_global_key | ambiguous_active_global_key | key_window | algorithm_not_es256. service_role only. Closes P2-MANIFEST-KEY. 121: the row read is STRICT (no_data_found/too_many_rows map to the stable unavailable codes) — defensive hardening that states the exactly-one-row invariant in the code; the function is STABLE, so both reads already share one snapshot.';
revoke all on function venue.get_manifest_signing_context() from public, anon, authenticated;
grant execute on function venue.get_manifest_signing_context() to service_role;

commit;
