-- ============================================================================
-- ROLLBACK for 079_kernel_ticket_atom_and_ownership_log.sql
--
-- POSTURE: FORWARD-FIX ONLY FROM FIRST ROW (plan §8/079). The custody ledger is
-- permanent and is never dropped once it holds real atoms. This DROP script
-- serves ONLY the pre-go-live window, and refuses to run otherwise.
--
-- OR-17 rider (F-5): this script CREATE OR REPLACEs kernel.deletion_blockers_
-- custody back to its 077 stub body — a rolled-back replacer must never leave a
-- body referencing dropped tables live under the 2-minute sweep (the
-- settlement_royalty_lines 42P01 class).
--
-- HARDENING-1: this script DOES NOT TOUCH kernel.sweep_deletion_pending. The
-- 078-carried isolation guard survives this rollback verbatim.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- PART 0 — REFUSAL GUARD
-- ---------------------------------------------------------------------------
do $$
declare
  v_atoms bigint := 0;
  v_log   bigint := 0;
  v_ovr   bigint := 0;
begin
  if to_regclass('kernel.tickets') is not null then
    execute 'select count(*) from kernel.tickets' into v_atoms;
  end if;
  if to_regclass('kernel.ticket_ownership_log') is not null then
    execute 'select count(*) from kernel.ticket_ownership_log' into v_log;
  end if;
  if to_regclass('kernel.door_freeze_override') is not null then
    execute 'select count(*) from kernel.door_freeze_override' into v_ovr;
  end if;
  if v_atoms > 0 or v_log > 0 or v_ovr > 0 then
    raise exception 'REFUSED: custody objects hold rows (tickets=%, ownership_log=%, door_freeze_override=%). The custody ledger is permanent from its first row — FORWARD-FIX ONLY (plan §8/079).',
      v_atoms, v_log, v_ovr;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- PART 1 — cron entry (register row 079)
-- ---------------------------------------------------------------------------
do $$
begin
  -- tolerate the (unreachable-in-supported-flows) absent-job state rather than
  -- letting an availability error mask the rollback (red-team E, PR #33)
  if exists (select 1 from cron.job where jobname = 'sweep-expired-ticket-atoms') then
    perform cron.unschedule('sweep-expired-ticket-atoms');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- PART 2 — OR-17 rider F-5: restore the 077 stub body VERBATIM (SEAM-2a)
-- ---------------------------------------------------------------------------
create or replace function kernel.deletion_blockers_custody(p_identity uuid)
returns text language sql volatile security definer set search_path = ''
as $$ select null::text $$;   -- BP-1; real body 079 (kernel.tickets)

-- ---------------------------------------------------------------------------
-- PART 3 — functions authored by 079 (catalog.update_event_session included:
-- it did not exist before this package)
-- ---------------------------------------------------------------------------
drop function if exists catalog.update_event_session(uuid, jsonb, text);
drop function if exists kernel.sweep_expired_ticket_atoms(int);
drop function if exists kernel.mark_ticket_scanned(uuid, uuid, jsonb);
drop function if exists kernel.unlock_ticket(uuid, text);
drop function if exists kernel.lock_ticket(uuid, text, text);
drop function if exists kernel.is_transfer_frozen(uuid);

-- ---------------------------------------------------------------------------
-- PART 4 — tables (children first), their triggers and trigger functions
-- ---------------------------------------------------------------------------
drop table if exists kernel.ticket_ownership_log;
drop table if exists kernel.door_freeze_override;
drop table if exists kernel.tickets;

drop function if exists kernel.tg_custody_head_is_ledger_tail();
drop function if exists kernel.raise_override_forward_only();

commit;
