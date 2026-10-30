-- ============================================================================
-- 115_ops_console_foundation_rollback.sql — mechanical reversal of migration 115
-- (Operating Console foundation). MECHANICAL-REVERSIBILITY REHEARSAL ONLY —
-- production is forward-only; ops.audit / ops.case_note / ops.case_event are
-- append-only records of operator actions and dropping them destroys the
-- audit trail. Run only on a database where 116/117 have already been rolled
-- back (they own objects inside the same schema; `cascade` would take them
-- too, which is why the guard below refuses when they are present).
--
-- Touches nothing in public.*, kernel.*, catalog.*, market.*, venue.*, notify.*.
-- Idempotent.
-- ============================================================================
begin;

do $$
begin
  if to_regprocedure('ops.list_orders(jsonb,text,integer)') is not null
     or to_regprocedure('ops.run_job(text,text)') is not null then
    raise exception 'rollback_refused: roll back 117 and 116 before 115 (ops read API / automation still installed)';
  end if;
end $$;

drop schema if exists ops cascade;

commit;
