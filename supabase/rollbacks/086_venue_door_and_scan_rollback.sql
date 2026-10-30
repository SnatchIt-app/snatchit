-- ============================================================================
-- ROLLBACK for 086_venue_door_and_scan.sql
-- POSTURE: CLEAN-WHILE-EMPTY, then forward-fix. Refuses once any door/scan row
-- exists (a manifest episode, a scan, a door session, a comp/guest row, a
-- holder-mix snapshot). Restores post-085 state EXACTLY:
--   - venue.append_door_manifest_delta → its 083 no-op stub (SEAM-2 F-5)
--   - kernel.on_identity_erased_door   → its 077 no-op stub (SEAM-2 F-5)
--   - kernel.revoke_signing_key is DROPPED (it is NEW in 086 per PFA-17; it did
--     not exist post-085 — 083 shipped provision+rotate only)
-- 076-085 otherwise untouched.
-- ============================================================================

begin;

-- PART 0 — refusal guard (row_security off: several door tables are deny-all
-- zero-policy, so a non-BYPASSRLS runner would under-count).
do $$
declare
  v_dp bigint:=0; v_ds bigint:=0; v_sd bigint:=0; v_sc bigint:=0; v_ca bigint:=0;
  v_gl bigint:=0; v_ge bigint:=0; v_dm bigint:=0; v_de bigint:=0; v_dd bigint:=0;
  v_hs bigint:=0; v_hb bigint:=0;
begin
  set local row_security = off;
  if to_regclass('venue.door_pin')            is not null then execute 'select count(*) from venue.door_pin'            into v_dp; end if;
  if to_regclass('venue.door_session')        is not null then execute 'select count(*) from venue.door_session'        into v_ds; end if;
  if to_regclass('venue.scan_device')         is not null then execute 'select count(*) from venue.scan_device'         into v_sd; end if;
  if to_regclass('venue.scan')                is not null then execute 'select count(*) from venue.scan'                into v_sc; end if;
  if to_regclass('venue.comp_allocation')     is not null then execute 'select count(*) from venue.comp_allocation'     into v_ca; end if;
  if to_regclass('venue.guest_list')          is not null then execute 'select count(*) from venue.guest_list'          into v_gl; end if;
  if to_regclass('venue.guest_entry')         is not null then execute 'select count(*) from venue.guest_entry'         into v_ge; end if;
  if to_regclass('venue.door_manifest')       is not null then execute 'select count(*) from venue.door_manifest'       into v_dm; end if;
  if to_regclass('venue.door_manifest_entry') is not null then execute 'select count(*) from venue.door_manifest_entry' into v_de; end if;
  if to_regclass('venue.door_manifest_delta') is not null then execute 'select count(*) from venue.door_manifest_delta' into v_dd; end if;
  if to_regclass('venue.holder_mix_snapshot') is not null then execute 'select count(*) from venue.holder_mix_snapshot' into v_hs; end if;
  if to_regclass('venue.holder_mix_bucket')   is not null then execute 'select count(*) from venue.holder_mix_bucket'   into v_hb; end if;
  if v_dp+v_ds+v_sd+v_sc+v_ca+v_gl+v_ge+v_dm+v_de+v_dd+v_hs+v_hb > 0 then
    raise exception 'REFUSED: 086 holds door/scan rows (pin=%,session=%,device=%,scan=%,comp=%,guest_list=%,guest_entry=%,manifest=%,entry=%,delta=%,mix=%,bucket=%). CLEAN-WHILE-EMPTY only.',
      v_dp,v_ds,v_sd,v_sc,v_ca,v_gl,v_ge,v_dm,v_de,v_dd,v_hs,v_hb;
  end if;
end $$;

-- PART 1 — cron.
select cron.unschedule('sweep-expired-door-sessions') where exists (select 1 from cron.job where jobname='sweep-expired-door-sessions');
select cron.unschedule('sweep-expired-door-overrides') where exists (select 1 from cron.job where jobname='sweep-expired-door-overrides');
select cron.unschedule('sweep-implicit-door-freezes')  where exists (select 1 from cron.job where jobname='sweep-implicit-door-freezes');
select cron.unschedule('refresh-holder-mix')           where exists (select 1 from cron.job where jobname='refresh-holder-mix');
select cron.unschedule('reconcile-holder-mix')         where exists (select 1 from cron.job where jobname='reconcile-holder-mix');

-- PART 2 — restore the SEAM-2 stub bodies VERBATIM (F-5).
create or replace function venue.append_door_manifest_delta(
  p_session_id uuid, p_atoms uuid[], p_op text, p_cause_ref uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;   -- no-op stub; real body 086

create or replace function kernel.on_identity_erased_door(p_identity uuid)
returns void language sql volatile security definer set search_path = ''
as $$ select $$;              -- INV #29-#31; real body 086

-- PART 3 — the ledger-head trigger on catalog.event_session, then 086 functions.
drop trigger if exists tg_door_open_at_is_ledger_head on catalog.event_session;
drop function if exists catalog.tg_door_open_at_is_ledger_head();
drop function if exists catalog.engage_door_freeze(uuid, timestamptz);
drop function if exists catalog.set_session_door_schedule(uuid, timestamptz, text, text);
drop function if exists catalog.sweep_implicit_door_freezes(integer);
drop function if exists market.on_door_freeze_engaged(uuid, uuid);
drop function if exists market.door_freeze_drain_preview(uuid);
drop function if exists kernel.assert_door_session(uuid, uuid, uuid, text);
drop function if exists kernel.grant_door_freeze_override(uuid, uuid, text, timestamptz, integer, text);
drop function if exists kernel.revoke_door_freeze_override(uuid, text);
drop function if exists kernel.sweep_expired_door_overrides();
drop function if exists kernel.revoke_signing_key(uuid, text, integer, text);
drop function if exists venue.create_door_pin(uuid, uuid, text, text, timestamptz, text);
drop function if exists venue.revoke_door_pin(uuid, text);
drop function if exists venue.register_scan_device(uuid, text, text);
drop function if exists venue.set_scan_device_status(uuid, text, text, text);
drop function if exists venue.sync_scan_device_manifest(uuid, uuid, integer);
drop function if exists venue.record_scan(uuid, uuid, uuid, jsonb, text);
drop function if exists venue.reconcile_offline_scans(uuid, uuid, jsonb, text);
drop function if exists venue.validate_ticket_online(uuid, uuid);
drop function if exists venue.allocate_comp(uuid, uuid, integer, text, text);
drop function if exists venue.issue_comp(uuid, uuid, integer, text);
drop function if exists venue.create_guest_list(uuid, text, text);
drop function if exists venue.upsert_guest_entry(uuid, uuid, text, integer, text);
drop function if exists venue.remove_guest_entry(uuid, text, text);
drop function if exists venue.check_in_guest_entry(uuid, uuid, text, text);
drop function if exists venue.open_door_manifest(uuid, text, text);
drop function if exists venue.close_door_manifest(uuid, text, text);
drop function if exists venue.get_door_manifest(uuid, integer);
drop function if exists venue.preview_door_open_impact(uuid);
drop function if exists venue.get_live_device_count(uuid);
drop function if exists venue.get_holder_mix(uuid, text);
drop function if exists venue.revoke_door_session(uuid, text, text);
drop function if exists venue.mint_door_session(uuid, uuid, uuid, text, text);
drop function if exists venue.sweep_expired_door_sessions();
drop function if exists venue.refresh_holder_mix(uuid);
drop function if exists venue.reconcile_holder_mix();
drop function if exists venue.unpublish_holder_mix(uuid);
drop function if exists venue.unpublish_all_holder_mix();

-- PART 4 — tables (children first). Dropping each removes its triggers/policies.
drop table if exists venue.holder_mix_bucket;
drop table if exists venue.holder_mix_snapshot;
drop table if exists venue.door_manifest_delta;
drop table if exists venue.door_manifest_entry;
-- scan/scan_device carry FKs to door_manifest → drop scan/device manifest FKs' tables after door_manifest? No:
-- scan & scan_device REFERENCE door_manifest, so they must be dropped BEFORE door_manifest.
drop table if exists venue.scan;                  -- references door_manifest + scan_device
drop table if exists venue.guest_entry;
drop table if exists venue.guest_list;
drop table if exists venue.comp_allocation;
drop table if exists venue.door_session;          -- references door_pin + scan_device
drop table if exists venue.scan_device;           -- references door_manifest; now unreferenced
drop table if exists venue.door_manifest;         -- now unreferenced (scan/scan_device gone)
drop table if exists venue.door_pin;              -- referenced only by door_session (gone)

-- PART 5 — the guard trigger fn (its table is gone).
drop function if exists venue.guard_door_manifest_transition();

commit;
