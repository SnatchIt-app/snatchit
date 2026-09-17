-- ============================================================================
-- 104_scan_session_status_gate_rollback.sql — REVERSES 104.
--
-- POSTURE: BREAK-GLASS. Restores venue.record_scan to its 086:1070-1109 body,
-- which REMOVES the session-status gate and REINTRODUCES door P0-1: a
-- cancelled/completed session's still-active atoms become admissible again.
-- Run only if 104 itself is found wrong; otherwise forward-fix. Native scanning
-- is dark, so there is no live exposure either way. Body-only create-or-replace;
-- no object dropped.
-- ============================================================================
begin;

create or replace function venue.record_scan(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_venue uuid; v_res jsonb; v_result text; v_scan_id uuid;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  begin
    v_res := kernel.mark_ticket_scanned(p_atom_id, p_session_id, coalesce(p_scan_meta, '{}'::jsonb));
    v_result := 'admitted';
  exception when others then
    v_result := case when sqlerrm like '%not_active%' or sqlerrm like '%wrong_session%' then 'invalid'
                     when sqlerrm like '%listed_locked%' then 'invalid'
                     else 'invalid' end;
  end;
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, auth.uid(), v_result,
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', v_result);
exception when unique_violation then
  insert into venue.scan (ticket_atom_id, event_session_id, device_id, actor_identity_id, result, occurred_at)
  values (p_atom_id, p_session_id, p_actor_device_id, auth.uid(), 'duplicate',
          coalesce((p_scan_meta->>'occurred_at')::timestamptz, now()))
  returning scan_id into v_scan_id;
  return jsonb_build_object('status','ok','scan_id', v_scan_id, 'result', 'duplicate');
end;
$$;

commit;
