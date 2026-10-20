-- ============================================================================
-- 125_sync_scan_device_manifest_open_unexpired_rollback.sql — restores the 086
-- body of venue.sync_scan_device_manifest(uuid,uuid,integer) verbatim
-- (086:1040-1068) and removes the 125 comment (086 set none), i.e. the
-- `status = 'open'`-only episode select that binds a device to an expired-but-
-- open episode while the returned payload reports open:false. Body-only;
-- grants preserved; census 0; definition md5 returns to
-- 666422e5fe0c7e96c267ad259d7ef50a. Production is forward-only by policy — this
-- is an emergency measure requiring its own authorization, and re-introduces
-- the 086↔112/113 inconsistency it reverts.
-- ============================================================================
begin;

create or replace function venue.sync_scan_device_manifest(p_device_id uuid, p_session_id uuid, p_known_manifest_version integer)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.scan_device%rowtype; v_m venue.door_manifest%rowtype;
begin
  select * into v_row from venue.scan_device where device_id = p_device_id for update;
  if not found then raise exception 'not_found: device %', p_device_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  select * into v_m from venue.door_manifest where session_id = p_session_id and status = 'open'
   order by manifest_version desc limit 1;
  if found then
    update venue.scan_device set manifest_version = v_m.manifest_version, manifest_id = v_m.manifest_id,
           last_sync_at = now(), updated_at = now() where device_id = p_device_id;
  end if;
  -- FAIL-SAFE full sync. p_known_manifest_version is the per-session EPISODE counter,
  -- NOT a delta-seq cursor (the per-manifest seq resets each episode). Passing it as
  -- get_door_manifest's p_since_delta_seq silently dropped deltas 1..N of the open
  -- episode (e.g. a revoke), so a device could keep admitting a revoked atom. Return
  -- the COMPLETE current manifest (all deltas) — incremental delta sync is a forward
  -- obligation (needs a real delta-seq parameter; native scanning is dark).
  return venue.get_door_manifest(p_session_id, 0);
end;
$$;

comment on function venue.sync_scan_device_manifest(uuid, uuid, integer) is null;

commit;
