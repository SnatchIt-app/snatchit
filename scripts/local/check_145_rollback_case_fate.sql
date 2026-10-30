-- What happens to a job_not_running case that 145 opened, once 145 is rolled back?
-- A's plan v3 §8 claims: "145's open cases then auto-resolve as 'condition no longer detected',
-- which is history, not deletion." This checks that claim rather than reasoning about it.
-- Run OUTSIDE a transaction, against a replayed chain; the rollback is applied between the two halves.
-- Part 1 (this file): set up a genuinely-stalled job and let 145 open its case.
\set ON_ERROR_STOP on

create table if not exists cron.job_run_details (
  jobid bigint not null, runid bigint primary key, job_pid integer, database text, username text,
  command text, status text, return_message text, start_time timestamptz, end_time timestamptz);

-- a 5-minute job whose only runs are 8 days old: not failing, simply not running any more
select cron.schedule('c145_stalled', '*/5 * * * *', 'select 1 /* c145 */');

insert into cron.job_run_details (jobid, runid, database, username, command, status, start_time, end_time)
select j.jobid, 900001, current_database(), 'postgres', j.command, 'succeeded',
       now() - interval '8 days', now() - interval '8 days' + interval '1 second'
  from cron.job j where j.jobname = 'c145_stalled';
insert into cron.job_run_details (jobid, runid, database, username, command, status, start_time, end_time)
select j.jobid, 900002, current_database(), 'postgres', j.command, 'succeeded',
       now() - interval '8 days' + interval '5 minutes', now() - interval '8 days' + interval '5 minutes 1 second'
  from cron.job j where j.jobname = 'c145_stalled';

-- 145's body: the stalled job must be reported
select ops.detect_jobs();

select 'PART1 case_status=' || coalesce((select status from ops."case"
         where case_type = 'job_failure' and subject_ref = 'c145_stalled'), '(no case)')
    || ' title=' || coalesce((select title from ops."case"
         where case_type = 'job_failure' and subject_ref = 'c145_stalled'), '-')
    || ' alert=' || coalesce((select state from ops.alert where alert_key = 'job_failure:c145_stalled'), '(none)')
  as part1;
