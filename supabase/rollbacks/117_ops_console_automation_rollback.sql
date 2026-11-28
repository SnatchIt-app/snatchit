-- ============================================================================
-- 117_ops_console_automation_rollback.sql — mechanical reversal of migration 117
-- (Operating Console automation). MECHANICAL-REVERSIBILITY REHEARSAL ONLY —
-- production is forward-only.
--
-- Unschedules the two cron jobs and drops every FUNCTION 117 created. The
-- tables (ops.job_run / job_state / alert / daily_summary / metric_snapshot
-- and their rows) belong to 115 and are deliberately left in place — they
-- are the durable record of what the automation did; 115's own rollback
-- takes the schema. The 13 ops.job_state seed rows stay for the same reason.
--
-- Safe to run before or after 116's rollback (no shared objects). Touches
-- nothing in public.*, kernel.*, catalog.*, market.*, venue.*, notify.*.
-- Idempotent.
-- ============================================================================
begin;

select cron.unschedule(jobname) from cron.job where jobname = 'ops-detect-tick';
select cron.unschedule(jobname) from cron.job where jobname = 'ops-daily-summary';

-- entry points
drop function if exists ops.run_all_detectors();
drop function if exists ops.run_job(text,text);

-- job bodies
drop function if exists ops.build_daily_summary(date);
drop function if exists ops.refresh_metrics();
drop function if exists ops.detect_reconciliation();
drop function if exists ops.detect_notifications();
drop function if exists ops.detect_jobs();
drop function if exists ops.detect_webhooks();
drop function if exists ops.detect_reports();
drop function if exists ops.detect_payout_review();
drop function if exists ops.detect_disputes();
drop function if exists ops.detect_refunds();
drop function if exists ops.detect_release_stuck();
drop function if exists ops.detect_transfer_deadlines();
drop function if exists ops.detect_paid_unsettled();

-- helpers
drop function if exists ops.cron_interval_minutes(text);
drop function if exists ops.detect_sweep(text,text[]);
drop function if exists ops.detect_case(text,text,uuid,text,text,text,text,timestamptz,text);
drop function if exists ops.alert_recover_stale(text,text[]);
drop function if exists ops.alert_recover(text);
drop function if exists ops.alert_fire(text,text,jsonb);
drop function if exists ops.setting_bool(text,boolean);
drop function if exists ops.setting_int(text,integer);

commit;
