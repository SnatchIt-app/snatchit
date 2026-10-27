-- ============================================================================
-- supabase/rollbacks/20261026210000_scan_sequential_duplicate_rollback.sql
-- Rollback for registry 183 (20261026210000). Restores the 108 PART 1 body of
-- venue._record_scan_core VERBATIM (sequential rescans go back to 'invalid',
-- no prior/reason, no credential-currency check, unknown atom raises FK again).
-- The nullable column venue.scan.device_label is LEFT IN PLACE on purpose: the
-- ledger is append-only and dropping a populated column would destroy
-- attendance attribution written while 183 was live; the restored body simply
-- never writes it. Verified: after this file the body's sha256 equals the
-- pre-183 chain's (planning/2026-10-26-launch/B/evidence/08-rollback-verify.log).
-- ============================================================================
begin;
-- ── PRE-FLIGHT (inverse of 183's guard): the body being restored over must be EXACTLY
-- 183's body (rollback) or already the 108 body (idempotent re-run); anything else is
-- a later change this rollback must not destroy — refuse.
do $pf$
declare v_md5 text := md5(pg_get_functiondef('venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text)'::regprocedure));
begin
  if v_md5 not in ('1b7e88e52a7a788081c7623fba62baf6',                         -- 183 body
                   '9ae362e02023cd0d45df43daef326b11') then -- 108 body (already rolled back)
    raise exception 'precondition_failed: 183 rollback refuses to overwrite an unexpected venue._record_scan_core body (md5 %)', v_md5;
  end if;
end $pf$;
create or replace function venue._record_scan_core(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_actor_identity_id uuid,
  p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_session_status text; v_res jsonb; v_result text; v_scan_id uuid;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  -- terminal-session gate (104): a cancelled/completed (or unknown) session must
  -- not admit. X-12 restrictive — a null status (vanished session) fails closed.
  select es.status into v_session_status
    from catalog.event_session es where es.session_id = p_session_id;
  if v_session_status is null or v_session_status in ('cancelled','completed') then
    raise exception 'precondition_failed: session_not_admitting (status=%)', coalesce(v_session_status,'missing');
  end if;
  -- lifecycle transition (single-writer choke point).
  begin
    v_res := kernel.mark_ticket_scanned(p_atom_id, p_session_id, coalesce(p_scan_meta, '{}'::jsonb));
    v_result := 'admitted';
  exception when others then
    v_result := case when sqlerrm like '%not_active%' or sqlerrm like '%wrong_session%' then 'invalid'
                     when sqlerrm like '%listed_locked%' then 'invalid'
                     else 'invalid' end;
  end;
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, p_actor_identity_id, v_result,
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result);
exception when unique_violation then
  -- C41 first-in-wins: a second admitted inbound scan is a duplicate.
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, p_actor_identity_id, 'duplicate',
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate');
end;
$$;
comment on function venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text) is
  'INTERNAL (zero grant): the authorization-free admission body (104 record_scan minus the role gate). Callers MUST pre-authorize (venue.record_scan role gate, or venue.record_scan_door via kernel.assert_door_session). Terminal-session gate + mark_ticket_scanned + first-in-wins; actor passed explicitly (NULL on the machine path -> device-attributed).';
revoke all on function venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text) from public, anon, authenticated, service_role;
-- ── POST-RESTORE SELF-CHECK (A review N6): the restored body must be EXACTLY the 108 body.
do $pc$
declare v_md5 text := md5(pg_get_functiondef('venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text)'::regprocedure));
begin
  if v_md5 <> '9ae362e02023cd0d45df43daef326b11' then
    raise exception 'precondition_failed: 183 rollback post-restore self-check — the restored body (md5 %) is not the 108 body; this file was modified', v_md5;
  end if;
end $pc$;
commit;
