-- ============================================================================
-- 108_door_machine_scan_authority_rollback.sql — revert migration 108.
-- Restores venue.record_scan (104 body) and venue.reconcile_offline_scans (105
-- body) as self-contained (no core delegation), then drops the four functions
-- 108 added. CLEAN-WHILE-EMPTY: 108 changed no data.
-- ============================================================================
begin;

-- restore record_scan (104:63-114 verbatim)
create or replace function venue.record_scan(
  p_atom_id uuid, p_session_id uuid, p_actor_device_id uuid, p_scan_meta jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_flag boolean; v_venue uuid; v_session_status text; v_res jsonb; v_result text; v_scan_id uuid;
begin
  select (c.value #>> '{}')::boolean into v_flag from catalog.platform_config c
   where c.key = 'feature.native_scanning_enabled' order by c.version desc limit 1;
  if not coalesce(v_flag, false) then
    raise exception 'precondition_failed: feature_disabled — native scanning is dark';
  end if;
  select ev.venue_id, es.status into v_venue, v_session_status
    from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  if v_session_status is null or v_session_status in ('cancelled','completed') then
    raise exception 'precondition_failed: session_not_admitting (status=%)', coalesce(v_session_status,'missing');
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

-- restore reconcile_offline_scans (105:168-233 verbatim)
create or replace function venue.reconcile_offline_scans(
  p_session_id uuid, p_actor_device_id uuid, p_batch jsonb, p_command_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_venue      uuid;
  v_item       jsonb;
  v_atom       uuid;
  v_item_sess  uuid;
  v_res        jsonb;
  v_result     text;
  v_admitted   integer := 0;
  v_duplicates integer := 0;
  v_conflicts  integer := 0;
begin
  select ev.venue_id into v_venue from catalog.event_session es join catalog.event ev on ev.event_id=es.event_id
   where es.session_id = p_session_id;
  if not kernel.has_venue_role(v_venue, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  for v_item in
    select elem
      from jsonb_array_elements(coalesce(p_batch, '[]'::jsonb)) elem
     order by (elem->>'server_receipt_at')::timestamptz nulls last,
              (elem->>'device_boot_id') nulls last,
              (elem->>'scan_sequence')::bigint nulls last,
              (elem->>'ticket_atom_id')
  loop
    v_atom := (v_item->>'ticket_atom_id')::uuid;
    begin
      v_item_sess := nullif(v_item->>'session_id','')::uuid;
      if v_item_sess is not null and v_item_sess <> p_session_id then
        raise exception 'precondition_failed: batch_session_mismatch — item session % is not the asserted session %', v_item_sess, p_session_id
          using errcode = 'P0001';
      end if;
      v_res := venue.record_scan(v_atom, p_session_id, p_actor_device_id, v_item, p_command_key || ':' || v_atom::text);
      v_result := v_res->>'result';
      if    v_result = 'admitted'  then v_admitted   := v_admitted + 1;
      elsif v_result = 'duplicate' then v_duplicates := v_duplicates + 1;
      else                              v_conflicts  := v_conflicts + 1;
      end if;
    exception when others then
      v_conflicts := v_conflicts + 1;
    end;
  end loop;
  return jsonb_build_object('status','ok','admitted', v_admitted,
                            'duplicates', v_duplicates, 'conflicts', v_conflicts);
end;
$$;

drop function if exists venue.record_scan_door(uuid,uuid,uuid,text,uuid,jsonb,text);
drop function if exists venue.reconcile_offline_scans_door(uuid,uuid,text,uuid,jsonb,text);
drop function if exists venue._reconcile_core(uuid,uuid,uuid,jsonb,text);
drop function if exists venue._record_scan_core(uuid,uuid,uuid,uuid,jsonb,text);

commit;
