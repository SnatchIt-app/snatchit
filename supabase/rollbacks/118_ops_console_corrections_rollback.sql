-- ============================================================================
-- 118_ops_console_corrections_rollback.sql — mechanical reversal of 118.
-- MECHANICAL-REVERSIBILITY REHEARSAL ONLY (production is forward-only; see
-- docs/admin-console/RUNBOOK.md §5 for production containment, which never
-- drops ops objects). Restores the 115/116/117 function bodies by re-running
-- those files' definitions is NOT done here (they are immutable files); this
-- script drops only what 118 ADDED and leaves the re-created functions at
-- their 118 bodies, which are strict supersets of the previous behaviour.
-- Idempotent.
-- ============================================================================
begin;

drop policy if exists "proof-docs operator read" on storage.objects;
drop function if exists ops.evidence_access(text,uuid,text);
drop function if exists ops.evidence_operator_may_read();
drop function if exists ops.evidence_path_is_referenced(text);
drop function if exists ops.executor_claim(uuid,integer);
drop function if exists ops.assert_actions_enabled();
-- execute_action / approve_action reference assert_actions_enabled at runtime;
-- neutralise the pause instead of leaving a dangling call.
create or replace function ops.assert_actions_enabled()
returns void language sql stable security definer set search_path = '' as $ops$ select null::void $ops$;
revoke all on function ops.assert_actions_enabled() from public, anon, authenticated;
delete from ops.setting where key = 'actions_enabled';
alter table ops.action drop column if exists claimed_until;
alter table ops.action drop column if exists attempt;

commit;
