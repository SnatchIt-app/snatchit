-- ============================================================================
-- 120_ops_console_refund_semantics_rollback.sql — mechanical reversal of 120.
-- MECHANICAL-REVERSIBILITY REHEARSAL ONLY (production is forward-only; see
-- docs/admin-console/RUNBOOK.md §5). Drops the normaliser and restores
-- latest_summary to the plain 116 body. build_daily_summary keeps its 120
-- body (a strict-superset shape); rewritten summary rows are NOT reverted —
-- they are derived data and the uncertain shape is the honest one. Idempotent.
-- ============================================================================
begin;
create or replace function ops.latest_summary()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
begin
  perform ops.assert_reader();
  return (select to_jsonb(s) from ops.daily_summary s order by s.summary_date desc limit 1);
end;
$ops$;
revoke all on function ops.latest_summary() from public, anon, authenticated;
grant execute on function ops.latest_summary() to authenticated;
drop function if exists ops.normalize_summary_body(jsonb);
commit;
