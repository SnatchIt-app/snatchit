-- ============================================================================
-- 091_kernel_reserve_stub_rollback.sql — REVERSES 091_kernel_reserve_stub.sql
-- ----------------------------------------------------------------------------
-- POSTURE (plan §8/091): REVERSIBLE — `DROP TABLE kernel.reserve` is always valid
-- because the table is always empty in MVP (no writer exists). The guard below
-- makes that a checked fact rather than an assumption: a row would mean a
-- Gate-M writer landed without this package being superseded — forward-fix, never
-- drop money state. A ROUTINE that references the table is refused the same way
-- (PL/pgSQL bodies carry no pg_depend edge; a drop would leave a compiling-but-
-- broken money function). Second run: NOTICE, no-op.
-- ORDERING WITH LATER PACKAGES: none (091 is the chain tip).
-- ============================================================================
begin;

do $$
declare v_rows bigint; v_refs bigint;
begin
  if to_regclass('kernel.reserve') is null then
    raise notice '091 rollback: already rolled back (kernel.reserve absent) — no-op';
    return;
  end if;
  -- row_security off: a deny-all zero-policy table would count 0 for a non-BYPASSRLS,
  -- non-owner runner and the guard would fail OPEN (the 081–087 house pattern; red-team S-1)
  set local row_security = off;
  lock table kernel.reserve in access exclusive mode;
  select count(*) into v_rows from kernel.reserve;
  select count(*) into v_refs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname not in ('pg_catalog','information_schema') and p.prosrc ~ '(kernel|"kernel")\s*\.\s*"?reserve"?\M';
  if v_rows > 0 or v_refs > 0 then
    raise exception 'rollback_refused: kernel.reserve holds % row(s) and % routine(s) reference it — the MVP stub must be empty and unreferenced; forward-fix instead', v_rows, v_refs;
  end if;
end $$;

drop table if exists kernel.reserve;   -- the trigger, RLS state and PK ride along

commit;
