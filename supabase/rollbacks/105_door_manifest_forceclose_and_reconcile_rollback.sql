-- ============================================================================
-- 105_..._rollback.sql — REVERSES 105. Restores venue.reconcile_offline_scans
-- to its 086:1130-1149 body ({status,reconciled}, array order, no session
-- cross-check) and DROPS kernel.force_close_key_manifests. Break-glass only;
-- otherwise forward-fix. Native scanning is dark, so no live exposure either
-- way. Dropping the helper is safe — it has zero grants and no live caller
-- (revoke stays parked).
-- ============================================================================
begin;

create or replace function venue.reconcile_offline_scans(
  p_session_id uuid, p_actor_device_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_venue uuid; v_item jsonb; v_n integer := 0;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  for v_item in select value from jsonb_array_elements(coalesce(p_batch, '[]'::jsonb)) loop
    perform venue.record_scan((v_item->>'ticket_atom_id')::uuid, p_session_id, p_actor_device_id, v_item,
              p_command_key || ':' || (v_item->>'ticket_atom_id'));
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('status','ok','reconciled', v_n);
end;
$$;

drop function if exists kernel.force_close_key_manifests(uuid,text);

commit;
