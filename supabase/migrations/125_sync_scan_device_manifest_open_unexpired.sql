-- ============================================================================
-- 125_sync_scan_device_manifest_open_unexpired.sql — 086↔112/113 scanning-
-- contract correction: `venue.sync_scan_device_manifest` binds a scan device
-- only to the episode the M2 read contract itself reports as open.
--
-- WHAT THIS MIGRATION IS. Body-only `create or replace` of ONE existing
-- function (086:1040-1068). Same signature, same VOLATILE / SECURITY DEFINER /
-- search_path='' shape, same grants (preserved by create-or-replace), same
-- authorization (device-venue role gate in-body; session-venue role gate inside
-- venue.get_door_manifest, exactly as 086 already invoked it). Adds no object,
-- census 0, Gate-2 untouched. Applied migrations 086/112/113 are NOT edited.
-- Numbered 125 per docs/release/MIGRATION_NUMBER_REGISTRY.md (formerly reserved
-- as 122; reassigned 2026-09-12 on the owner's sequencing approval); companion
-- pgTAP 190; rollback supabase/rollbacks/125_…_rollback.sql restores the 086
-- body verbatim (definition md5 666422e5fe0c7e96c267ad259d7ef50a = production
-- 2026-09-14). NOT applied anywhere by this file; production is forward-only
-- and applies it only under its own owner authorization.
--
-- ── THE DRIFT (docs/release/PHASE2_PFA18C_REMAINING_PATH_AND_HANDOFF.md §1.6) ─
-- 086 selected the device's episode with `status = 'open'` ONLY, bound the
-- device row (manifest_id / manifest_version / last_sync_at) to it, and then
-- returned `venue.get_door_manifest(p_session_id, 0)`. Migration 112 (and 113's
-- shared core) re-defined the M2 read on the door §7.5 precondition
-- `status = 'open' AND not_after > now()`: an episode past its STORED
-- `not_after` is reported `open:false` (no header, no entries). For such an
-- expired-but-still-'open' episode 086 therefore wrote a binding
-- (device "holds manifest vN, synced now") while the payload it returned in the
-- same call said no open episode — the device row and the M2 contract disagreed,
-- and any reader of scan_device.manifest_id/manifest_version (device liveness
-- projections, VD §12.3 / RN §10.2 counts) would count the device as synced to
-- an episode the door plane refuses. A second, smaller inconsistency came from
-- the two independent reads inside a VOLATILE function: an episode closed
-- between the bind and the return produced a bound row plus a no-episode payload.
--
-- ── THE CORRECTION ────────────────────────────────────────────────────────────
-- ONE read, the contract read: the function now calls venue.get_door_manifest
-- FIRST and binds the device from that payload, and only when it reports
-- `open:true`. Consequences, all fail-closed:
--   • expired-but-open episode  → payload open:false, device row UNTOUCHED
--     (086 would have bound it);
--   • no episode / closed        → payload open:false, device row untouched
--     (unchanged from 086);
--   • open, unexpired episode    → bound to EXACTLY the manifest_id /
--     manifest_version returned (unchanged result; now consistent by
--     construction, no second read);
--   • the door_manifest row is never written (not_after stays immutable;
--     guard 086 unchanged); no audit row (RPC §20.4.4: a poll is not a
--     privileged mutation).
-- p_known_manifest_version is still the per-session EPISODE counter and is
-- still NOT a delta cursor (086's fail-safe full sync is preserved: the payload
-- is the complete current manifest with all deltas).
--
-- ── NOT IN THIS MIGRATION (explicitly open; recorded, not silently changed) ──
-- RPC §20.4.4 specifies more than 086 ever implemented: a p_device_boot_id
-- parameter, a `device_wrong_venue` precondition (device venue = session venue),
-- an `up_to_date` short-circuit with a cursor-only result, monotonic
-- manifest_version on the device row, and the service_role door path. Those are
-- contract-conformance work with signature and result-shape consequences
-- (edge + scanner consumers), not part of the 086↔112/113 correction, and are
-- left for a separately reviewed migration. `venue.get_door_manifest`'s own
-- authorization is unchanged (113 staff path).
--
-- SOURCES READ, NOT ASSUMED: 086:1040-1068 (the body replaced), 086:273-318
-- (immutability guard: not_after never rewritten), 112:66-102 and 113:52-100
-- (the `status='open' and not_after > now()` precondition and the open:false
-- result), docs/architecture/PHASE_2_RPC_FUNCTION_CONTRACTS.md §20.4.4,
-- docs/architecture/PHASE_2_DOOR_LIFECYCLE_SPEC.md §7.5, production definition
-- md5 read 2026-09-14 (read-only).
-- ============================================================================
begin;

create or replace function venue.sync_scan_device_manifest(p_device_id uuid, p_session_id uuid, p_known_manifest_version integer)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_row venue.scan_device%rowtype; v_res jsonb;
begin
  select * into v_row from venue.scan_device where device_id = p_device_id for update;
  if not found then raise exception 'not_found: device %', p_device_id using errcode = 'P0002'; end if;
  if not kernel.has_venue_role(v_row.venue_id, array['venue_scanner','venue_manager']) then
    raise exception 'insufficient_privilege' using errcode = '42501';
  end if;
  -- 125: ONE read — the M2 contract read (112/113: status='open' AND not_after > now();
  -- an expired-but-open episode is open:false). The session-venue role gate inside
  -- get_door_manifest is evaluated here exactly as 086 evaluated it on return.
  -- FAIL-SAFE full sync preserved: p_known_manifest_version is the per-session
  -- EPISODE counter, NOT a delta-seq cursor, so the complete manifest is returned.
  v_res := venue.get_door_manifest(p_session_id, 0);
  -- bind the device ONLY to the episode the contract reports open, and to exactly
  -- the manifest it returned — never to a row the read refuses.
  if coalesce((v_res ->> 'open')::boolean, false) then
    update venue.scan_device
       set manifest_version = (v_res ->> 'manifest_version')::integer,
           manifest_id      = (v_res ->> 'manifest_id')::uuid,
           last_sync_at     = now(), updated_at = now()
     where device_id = p_device_id;
  end if;
  return v_res;
end;
$$;

comment on function venue.sync_scan_device_manifest(uuid, uuid, integer) is
  'Manifest-sync (RPC §20.4.4 as implemented by 086). 125: the device is bound (manifest_id/manifest_version/last_sync_at) only to the episode venue.get_door_manifest reports open:true — i.e. status=open AND not_after > now() (112/113, door §7.5) — and to exactly the manifest returned; an expired-but-open, closed or absent episode leaves the device row untouched and returns open:false. Authorization unchanged from 086 (device-venue venue_scanner/venue_manager gate, then the session-venue gate inside get_door_manifest). Never writes door_manifest; no audit row.';

commit;
