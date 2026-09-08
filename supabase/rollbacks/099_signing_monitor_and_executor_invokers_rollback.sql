-- ============================================================================
-- 099_signing_monitor_and_executor_invokers_rollback.sql
--   REVERSES supabase/migrations/099_signing_monitor_and_executor_invokers.sql
-- ----------------------------------------------------------------------------
-- Unschedules the three cron rows this package created and drops
-- kernel.check_signing_key_invariants(). Nothing else in the database is
-- touched — this package created no table, no trigger, no other function.
--
-- THE FIVE CONFIG SEEDS CANNOT BE REMOVED. catalog.platform_config (078) has
-- no UPDATE or DELETE path for ANY role, including superuser
-- (tg_platform_config_append_only) — the same reason 093/H2's
-- deletion.post_event_hold_hours orphan survives a rollback of the
-- migration that seeded it (see supabase/tests/142's D4 comment, and 095's
-- own rollback header for the same posture on its objects). After this
-- rollback runs, signing.monitor_enabled, signing.expected_key_fingerprint,
-- signing.expected_max_not_after, refund.executor_enabled and
-- payout.executor_enabled all remain in catalog.platform_config at version
-- 1 (false/null), but read by NOTHING — the checker is dropped and both
-- tick crons are unscheduled, so the rows are inert orphans, not a live
-- gate anyone can still arm into behaviour. A re-application of 099 after
-- this rollback re-inserts nothing for these five keys (`on conflict (key,
-- version) do nothing`) and recreates the function/cron rows around the
-- same orphaned seeds — replay-safe in both directions.
--
-- Second run: NOTICE, no-op.
-- ============================================================================
begin;

do $$
begin
  if to_regprocedure('kernel.check_signing_key_invariants()') is null
     and not exists (
       select 1 from cron.job
        where jobname in ('monitor-signing-key-invariants', 'refund-execute-tick', 'payout-execute-tick')
     ) then
    raise notice '099 rollback: already rolled back (function absent, no 099 cron rows) — no-op';
  end if;
end $$;

select cron.unschedule(jobname)
  from cron.job
 where jobname in ('monitor-signing-key-invariants', 'refund-execute-tick', 'payout-execute-tick');

drop function if exists kernel.check_signing_key_invariants();

commit;
