-- ============================================================================
-- ROLLBACK for 081_venue_inventory.sql
-- POSTURE: CLEAN-WHILE-EMPTY (plan §8/081). Refuses once any inventory row
-- exists (a live capacity counter / hold is forward-fix territory).
--
-- Drop order: hold, movement, shard, batch, ticket_type (shard cascades with
-- batch anyway; explicit for clarity). Functions first (they read the tables).
-- The cron entry is unscheduled with an existence guard.
--
-- Preserves the post-080 state exactly: HARDENING-1, the 079 BP-1 body, the 080
-- on_identity_erased_staff body, PFA-10 discharge, E-27, PFA-13/E-22/E-23 are
-- all untouched — 081 replaced no SEAM-2 stub and altered no earlier object.
-- catalog.publish_event is 081-authored (it did not exist post-080), so it is
-- dropped; catalog.update_event / update_event_session / cancel_event are NOT
-- touched.
-- ============================================================================

begin;

-- PART 0 — refusal guard
do $$
declare
  v_tt bigint := 0; v_b bigint := 0; v_h bigint := 0; v_m bigint := 0;
begin
  -- Count authoritatively regardless of the executing role. inventory_movement
  -- and inventory_batch_shard are deny-all (RLS on, zero policies); a
  -- non-BYPASSRLS runner would count 0 there and undercount the policy-scoped
  -- tables, so the guard could false-negative and drop the AO ledger while it
  -- holds rows. With row_security off, the owner/BYPASSRLS runner gets the true
  -- count and a non-privileged runner ERRORS here and aborts the rollback —
  -- fail-safe either way (red-team E, PR #35).
  set local row_security = off;
  if to_regclass('venue.ticket_type')      is not null then execute 'select count(*) from venue.ticket_type'      into v_tt; end if;
  if to_regclass('venue.inventory_batch')  is not null then execute 'select count(*) from venue.inventory_batch'  into v_b;  end if;
  if to_regclass('venue.inventory_hold')   is not null then execute 'select count(*) from venue.inventory_hold'   into v_h;  end if;
  if to_regclass('venue.inventory_movement') is not null then execute 'select count(*) from venue.inventory_movement' into v_m; end if;
  if v_tt > 0 or v_b > 0 or v_h > 0 or v_m > 0 then
    raise exception 'REFUSED: inventory holds rows (ticket_type=%, batch=%, hold=%, movement=%). CLEAN-WHILE-EMPTY only (plan §8/081) — a live capacity counter is forward-fix territory.',
      v_tt, v_b, v_h, v_m;
  end if;
end $$;

-- PART 1 — cron (register row 081), tolerant of an absent job
do $$
begin
  if exists (select 1 from cron.job where jobname = 'sweep-expired-inventory-holds') then
    perform cron.unschedule('sweep-expired-inventory-holds');
  end if;
end $$;

-- PART 2 — functions (081-authored; publish_event included, it did not exist post-080)
drop function if exists catalog.publish_event(uuid, text, text);
drop function if exists venue.sweep_expired_inventory_holds(int);
drop function if exists venue.release_inventory_hold(uuid, text);
drop function if exists venue.create_inventory_hold(uuid, integer, text, text);
drop function if exists venue.reserve_primary_inventory(uuid, integer, text);
drop function if exists venue.set_batch_capacity(uuid, integer, text, text);
drop function if exists venue.create_inventory_batch(uuid, uuid, text, integer, integer, text);
drop function if exists venue.set_ticket_type_price(uuid, integer, text, text);
drop function if exists venue.create_ticket_type(uuid, text, text, integer, text, text);

-- PART 3 — tables (children first; shard cascades with batch)
drop table if exists venue.inventory_hold;
drop table if exists venue.inventory_movement;
drop table if exists venue.inventory_batch_shard;
drop table if exists venue.inventory_batch;
drop table if exists venue.ticket_type;

commit;
