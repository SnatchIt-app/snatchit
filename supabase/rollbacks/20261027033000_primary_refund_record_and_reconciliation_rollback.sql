-- ============================================================================
-- supabase/rollbacks/20261027033000_primary_refund_record_and_reconciliation_rollback.sql
-- Rollback for registry 189 (20261027033000). The applied predecessor of both functions is ABSENCE, so
-- the rollback DROPS them: ops.record_primary_refund(uuid, integer, text, text) and
-- ops.primary_reconciliation(date, date). No data is touched: kernel.refund rows, voided atoms and
-- kernel.admin_audit rows written THROUGH ops.record_primary_refund stay (they are the kernel's own
-- records, exactly as refund_primary_order writes them).
-- Guard: the pre-flight accepts, per function, only 189's body (rollback) or absence (idempotent re-run),
-- and refuses while any function or view outside 189 names either (plpgsql records no dependency).
--   ops.record_primary_refund   189 337a8f19d11a482e47437eb968dab40b -> absent
--   ops.primary_reconciliation  189 046dfce98f9e6714bb46a87e896e7763 -> absent
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT (inverse of 189's guard): each function must be EXACTLY 189's body (rollback) or already absent
-- (idempotent re-run); anything else is a later change this rollback must not destroy. Nothing outside 189
-- may call either function (a plpgsql body records no dependency, so DROP would succeed and leave the caller
-- broken) — a function or view that names one refuses the rollback. Nothing changes on a refusal.
do $pf$
declare
  v_r text := md5(pg_get_functiondef(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')));
  v_q text := md5(pg_get_functiondef(to_regprocedure('ops.primary_reconciliation(date, date)')));
  v_callers text;
begin
  if v_r is not null and v_r <> '337a8f19d11a482e47437eb968dab40b' then
    raise exception 'precondition_failed: 189 rollback refuses to drop an unexpected ops.record_primary_refund body (md5 %); nothing changed', v_r;
  end if;
  if v_q is not null and v_q <> '046dfce98f9e6714bb46a87e896e7763' then
    raise exception 'precondition_failed: 189 rollback refuses to drop an unexpected ops.primary_reconciliation body (md5 %); nothing changed', v_q;
  end if;
  select string_agg(x, ', ' order by x) into v_callers from (
    select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as x
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where p.prokind in ('f', 'p')
       and p.oid not in (coalesce(to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)')::oid, 0::oid), coalesce(to_regprocedure('ops.primary_reconciliation(date, date)')::oid, 0::oid))
       and n.nspname not in ('pg_catalog', 'information_schema')
       and p.prosrc ~ '(record_primary_refund|primary_reconciliation)'
    union all
    select n.nspname || '.' || c.relname
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('v', 'm')
       and n.nspname not in ('pg_catalog', 'information_schema')
       and pg_get_viewdef(c.oid) ~ '(record_primary_refund|primary_reconciliation)') s;
  if v_callers is not null then
    raise exception 'precondition_failed: 189 rollback refused — still called by %; nothing changed', v_callers;
  end if;
end $pf$;

drop function if exists ops.record_primary_refund(uuid, integer, text, text);
drop function if exists ops.primary_reconciliation(date, date);

-- ── POST-ROLLBACK SELF-CHECK: both functions are gone (no overload left behind).
do $pc$
begin
  if to_regprocedure('ops.record_primary_refund(uuid, integer, text, text)') is not null or to_regprocedure('ops.primary_reconciliation(date, date)') is not null
  or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'ops' and p.proname in ('record_primary_refund', 'primary_reconciliation')) then
    raise exception 'precondition_failed: 189 rollback self-check — a 189 function is still present';
  end if;
end $pc$;

commit;
