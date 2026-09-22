-- ============================================================================
-- 212_ops_job_not_running_detection.sql — migration 145: a scheduled job that STOPS RUNNING stays detected.
--   Section W: the defect itself, demonstrated with 143's own body (t212_old) on the same fixture — the case is
--     auto-resolved as "condition no longer detected" while the job is active and not running — and then with 145's
--     body, where it stays open. This is the owner's "tests must demonstrate the reported failure".
--   Section J: never-run jobs (in grace and past it), an intentionally disabled job, old failures, a genuinely missed
--     schedule, recovery, the unchanged failure rule, idempotency, and the first-seen map.
--   Section P: ops.cron_expected_gap_minutes, and that ops.cron_interval_minutes is untouched.
-- Fixture runs are inserted into cron.job_run_details directly, as 210 does, with runids ASCENDING in time:
-- pg_cron allocates them that way and every 'newest run' rule here reads the largest runid.
-- ============================================================================
BEGIN;
SELECT plan(25);
SELECT tap.seed_core();

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
CREATE FUNCTION tap._run212(p_job text DEFAULT 'jobs') RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v jsonb; begin perform tap.login_service(); v := ops.run_job(p_job, 'cron'); perform tap.logout(); return v; end $f$;

-- pg_cron may be absent locally; 210 creates the same shape.
DO $mk$
BEGIN
  IF to_regclass('cron.job_run_details') IS NULL THEN
    CREATE TABLE cron.job_run_details (
      jobid bigint not null, runid bigint primary key, job_pid integer, database text, username text,
      command text, status text, return_message text, start_time timestamptz, end_time timestamptz);
  END IF;
END $mk$;

-- 143's body, verbatim from the migration, under t212_old: the behaviour 145 changes, run on the same fixtures.
CREATE SCHEMA IF NOT EXISTS t212_old;
create or replace function t212_old.detect_jobs()
returns jsonb language plpgsql security definer set search_path = ''
as $ops$
declare
  v_keys    text[]  := array[]::text[];
  v_refs    text[]  := array[]::text[];
  v_scanned integer := 0;
  v_opened  integer := 0;
  r         record;
  v_res     jsonb;
  v_cron_available boolean := to_regclass('cron.job_run_details') is not null and to_regclass('cron.job') is not null;
  -- 143: floor search for the bounded read of cron.job_run_details
  v_floor   bigint;
  v_lo      bigint;
  v_hi      bigint;
  v_a       bigint;
  v_b       bigint;
  v_m       bigint;
  v_pr      bigint;
  v_ps      timestamptz;
begin
  if v_cron_available then
    -- 143: the same runs as before (those that started inside the last 7 days), found through the runid primary
    -- key instead of a full read, in slices of at most 5000 runids so that every sort or hash handles at most 5000
    -- rows whatever the planner estimates (production's statistics are not established). See the migration header.
    -- Floor, for the 7-day window with a 1-hour margin.
    -- Floor by binary search over runid (about 20 primary-key probes instead of a walk through the whole window).
    -- Any run whose start_time <= the target is a valid floor (see the migration header): every run with a smaller
    -- runid started at most 10 s after it, i.e. before the window. The search keeps the newest such run it finds.
    -- probe(m) = the newest run at or below runid m that has started; it is non-decreasing in m.
    execute $q$ select min(d.runid), max(d.runid) from cron.job_run_details d $q$ into v_lo, v_hi;
    v_floor := coalesce(v_lo, 1) - 1;                  -- no run starts before the target: the whole table is the window
    if v_hi is not null then
      v_a := v_lo - 1; v_b := v_hi;
      while v_b - v_a > 1 loop
        v_m := v_a + (v_b - v_a) / 2;
        execute $q$ select d.runid, d.start_time from cron.job_run_details d
                     where d.runid <= $1 and d.start_time is not null order by d.runid desc limit 1 $q$
          into v_pr, v_ps using v_m;
        if v_pr is null or v_ps <= now() - interval '7 days' - interval '1 hour' then
          v_a := v_m;
          if v_pr is not null then v_floor := greatest(v_floor, v_pr); end if;
        else
          v_b := v_m;
        end if;
      end loop;
      execute $q$ select d.runid, d.start_time from cron.job_run_details d
                   where d.runid <= $1 and d.start_time is not null order by d.runid desc limit 1 $q$
        into v_pr, v_ps using v_b;
      if v_pr is not null and v_ps <= now() - interval '7 days' - interval '1 hour' then v_floor := greatest(v_floor, v_pr); end if;
    end if;

    for r in execute $q$
      with bounds as (
        -- floor: from the search above (every run that started inside the window has a larger runid);
        -- hi: the newest runid, in this statement's snapshot.
        select $1::bigint as floor,
               coalesce((select max(d.runid) from cron.job_run_details d), 0) as hi
      ),
      slices as (
        select s as lo, least(s + 5000, b.hi) as up
          from bounds b, generate_series(b.floor, b.hi - 1, 5000) s
      ),
      -- per slice and job: the run count, newest success, newest failure, and the job's 5 largest runids with
      -- their statuses (a job never runs concurrently with itself, so its runid order is its start_time order)
      part as (
        select p.*
          from slices sl
          cross join lateral (
            select q.jobid, q.runid, q.status, q.rn, q.n, q.last_success, q.last_failed_runid
              from (select d.jobid, d.runid, d.status,
                           row_number() over w as rn,
                           count(*) over wj as n,
                           max(d.start_time) filter (where d.status = 'succeeded') over wj as last_success,
                           max(d.runid) filter (where d.status = 'failed') over wj as last_failed_runid
                      from cron.job_run_details d
                     where d.runid > sl.lo
                       and d.runid <= sl.up
                       and d.start_time > now() - interval '7 days'
                    window wj as (partition by d.jobid),
                           w  as (partition by d.jobid order by d.runid desc)) q
             where q.rn <= 5) p
      ),
      recent as (
        select x.jobid,
               (sum(x.n) filter (where x.rn = 1))::bigint as runs_7d,
               max(x.last_success) as last_success,
               max(x.last_failed_runid) as last_failed_runid
          from part x
         group by x.jobid
      ),
      last5 as (
        select x.jobid, x.status, row_number() over (partition by x.jobid order by x.runid desc) as rn
          from part x
      ),
      per_job as (
        select j.jobid, j.jobname, j.schedule,
               ops.cron_interval_minutes(j.schedule) as interval_min,
               coalesce(x.runs_7d, 0) as runs_7d,
               (select bool_and(l.status = 'failed') from last5 l where l.jobid = j.jobid and l.rn <= 2) as last2_failed,
               (select count(*) from last5 l where l.jobid = j.jobid and l.rn <= 5 and l.status = 'failed') as failed_of_last5,
               x.last_success,
               (select d.return_message from cron.job_run_details d where d.runid = x.last_failed_runid) as last_error
          from cron.job j
          left join recent x on x.jobid = j.jobid
         where j.active
      )
      select * from per_job
       where runs_7d > 0
         and (coalesce(last2_failed, false)
              or last_success is null
              or last_success < now() - make_interval(mins => 3 * interval_min))
    $q$ using v_floor
    loop
      v_scanned := v_scanned + 1;
      v_res := ops.detect_case('job_failure', 'job', null, r.jobname,
                 format('Cron job %s failing', r.jobname),
                 format('pg_cron job "%s" (%s): %s of the last 5 runs failed; last success %s%s.',
                        r.jobname, r.schedule, r.failed_of_last5,
                        coalesce(to_char(r.last_success at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'never in the last 7 days'),
                        case when r.last_error is not null then format('; last error: %s', left(r.last_error, 500)) else '' end),
                 'p2', null, 'jobs');
      v_keys := v_keys || (v_res ->> 'dedupe_key');
      v_refs := v_refs || r.jobname;
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
      perform ops.alert_fire('job_failure:' || r.jobname, 'job_failure',
                jsonb_build_object('source', 'pg_cron', 'jobname', r.jobname, 'failed_of_last5', r.failed_of_last5,
                                   'last_success', r.last_success));
    end loop;
  end if;

  for r in
    select s.job_name, s.consecutive_failures, s.last_error, s.last_success_at, s.backoff_until
      from ops.job_state s
     where s.consecutive_failures >= 3
  loop
    v_scanned := v_scanned + 1;
    v_res := ops.detect_case('job_failure', 'job', null, 'ops:' || r.job_name,
               format('Console job %s failing', r.job_name),
               format('ops job "%s" has failed %s times in a row (backing off until %s); last success %s%s.',
                      r.job_name, r.consecutive_failures,
                      coalesce(to_char(r.backoff_until at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'n/a'),
                      coalesce(to_char(r.last_success_at at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'never'),
                      case when r.last_error is not null then format('; last error: %s', left(r.last_error, 500)) else '' end),
               'p2', null, 'jobs');
    v_keys := v_keys || (v_res ->> 'dedupe_key');
    v_refs := v_refs || ('ops:' || r.job_name);
    if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
    perform ops.alert_fire('job_failure:ops:' || r.job_name, 'job_failure',
              jsonb_build_object('source', 'ops', 'job_name', r.job_name, 'consecutive_failures', r.consecutive_failures));
  end loop;

  perform ops.alert_recover_stale('job_failure:', v_refs);
  return jsonb_build_object('scanned', v_scanned, 'opened', v_opened,
                            'resolved', ops.detect_sweep('job_failure', v_keys),
                            'cron_run_details_available', v_cron_available);
end;
$ops$;

CREATE TABLE tap.j212 (name text PRIMARY KEY, jobid bigint);
CREATE FUNCTION tap._job(p_name text, p_schedule text DEFAULT '*/5 * * * *', p_active boolean DEFAULT true)
RETURNS bigint LANGUAGE plpgsql AS $f$
declare v_id bigint;
begin
  v_id := cron.schedule(p_name, p_schedule, 'select 1 /* t212 */');
  if not p_active then
    if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is not null then
      perform cron.alter_job(v_id, active => false);
    else
      update cron.job set active = false where jobid = v_id;
    end if;
  end if;
  insert into tap.j212 values (p_name, v_id) on conflict (name) do update set jobid = excluded.jobid;
  return v_id;
end $f$;
CREATE FUNCTION tap._jid(p_name text) RETURNS bigint LANGUAGE sql AS $f$ select jobid from tap.j212 where name = p_name $f$;
-- one run for a job, at a given age, with a status. Runids stay below any real row.
CREATE FUNCTION tap._run(p_name text, p_age interval, p_status text DEFAULT 'succeeded', p_msg text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $f$
declare v_next bigint;
begin
  -- runids ascend with time, as pg_cron allocates them: the detector reads "newest" as the largest runid
  select coalesce(max(runid), 0) + 1 into v_next from cron.job_run_details;
  insert into cron.job_run_details (jobid, runid, job_pid, database, username, command, status, return_message,
                                    start_time, end_time)
  values (tap._jid(p_name), v_next, 0, 'postgres', 'postgres', 'select 1 /* t212 */', p_status, p_msg,
          now() - p_age, now() - p_age + interval '1 second');
end $f$;
-- pg_cron allocates runids in start order, and every rule here reads "newest" as the largest runid. Fixtures that
-- back-date a run, or age one after later rows exist, would break that invariant — so renumber in start_time order
-- before each detector run, which is what a real history looks like.
CREATE FUNCTION tap._renumber() RETURNS void LANGUAGE plpgsql AS $f$
begin
  update cron.job_run_details set runid = runid + 1000000;
  with ordered as (select runid, row_number() over (order by start_time, runid) as rn from cron.job_run_details)
  update cron.job_run_details d set runid = o.rn from ordered o where d.runid = o.runid;
end $f$;
CREATE FUNCTION tap._case(p_name text) RETURNS ops."case" LANGUAGE sql AS $f$
  select c.* from ops."case" c where c.case_type = 'job_failure' and c.subject_ref = p_name order by c.created_at desc limit 1 $f$;
CREATE FUNCTION tap._age(p_name text, p_age interval) RETURNS void LANGUAGE sql AS $f$
  update cron.job_run_details set start_time = now() - p_age, end_time = now() - p_age + interval '1 second'
   where jobid = tap._jid(p_name) $f$;

-- ── Section P — the schedule parser ─────────────────────────────────────────
SELECT is(ops.cron_expected_gap_minutes('*/5 * * * *'), 5, 'P1: */5 is five minutes');
SELECT ok(ops.cron_expected_gap_minutes('7 * * * *') = 60 AND ops.cron_expected_gap_minutes('0 13 * * *') = 1440
          AND ops.cron_expected_gap_minutes('0 13 * * 1') = 10080 AND ops.cron_expected_gap_minutes('0 13 1 * *') = 44640,
  'P2: hourly, daily, weekly and monthly are read as themselves, not as the 1500-minute fallback');
SELECT ok(ops.cron_expected_gap_minutes('weird') = 1500 AND ops.cron_expected_gap_minutes(NULL) = 1500,
  'P3: an unknown shape keeps the old fallback');
SELECT ok(ops.cron_interval_minutes('7 * * * *') = 1500 AND ops.cron_interval_minutes('*/5 * * * *') = 5,
  'P4: ops.cron_interval_minutes is untouched — the existing failure rule keeps its timing');

-- ── Section W — the reported failure, then the fix ──────────────────────────
-- 143's body runs its own ops.detect_sweep over the job_failure type, so it would resolve cases opened by 145's
-- body. It therefore goes FIRST, on its own job, before any 145 case exists.
-- the same sequence under 143's body: the case is auto-resolved while the job is still active and not running
SELECT tap._job('t212x');
-- failing but still RUNNING: a 5-minute job whose last run was 3 minutes ago is not stalled
SELECT tap._run('t212x', interval '8 minutes', 'failed', 'boom');
SELECT tap._run('t212x', interval '3 minutes', 'failed', 'boom');
SELECT tap._renumber(); SELECT t212_old.detect_jobs();
SELECT ok((tap._case('t212x')).status = 'open' AND (tap._case('t212x')).title = 'Cron job t212x failing',
  'W4 (witness): 143''s body opens the case while the job is failing and still running');
SELECT tap._age('t212x', interval '8 days');
SELECT tap._renumber(); SELECT t212_old.detect_jobs();
SELECT ok((tap._case('t212x')).status = 'resolved'
          AND (tap._case('t212x')).resolution_note = 'auto: condition no longer detected',
  'W5 (the reported failure): under 143''s body the case is auto-resolved as "condition no longer detected"');
SELECT is((SELECT state FROM ops.alert WHERE alert_key = 'job_failure:t212x'), 'recovered',
  'W6: …and its alert is recovered, so nothing is left to see');


-- t212w: a job that was failing and then stopped running altogether. 143's body drops it after 7 days and the sweep
-- resolves its case; 145's body keeps it.
SELECT tap._job('t212w');
-- failing but still RUNNING: a 5-minute job whose last run was 3 minutes ago is not stalled
SELECT tap._run('t212w', interval '8 minutes', 'failed', 'boom');
SELECT tap._run('t212w', interval '3 minutes', 'failed', 'boom');
SELECT tap._renumber(); SELECT tap._run212();
SELECT ok((tap._case('t212w')).status = 'open' AND (tap._case('t212w')).title = 'Cron job t212w failing',
  'W1 (witness): while it is failing but still running, the existing rule opens the case and calls it failing');
SELECT tap._age('t212w', interval '8 days');
SELECT tap._renumber(); SELECT tap._run212();
SELECT ok((tap._case('t212w')).status = 'open' AND (tap._case('t212w')).title = 'Cron job t212w is not running',
  'W2 (the fix): once its runs age past 7 days the case STAYS open and says the job is not running');
SELECT ok((tap._case('t212w')).summary LIKE '%has not run since%' AND (tap._case('t212w')).summary LIKE '%ACTIVE%',
  'W3: the summary says when it last ran and that the job is still active');

-- ── Section J — the states the owner listed ─────────────────────────────────
SELECT tap._job('t212healthy');
SELECT tap._run('t212healthy', interval '2 minutes');
SELECT tap._job('t212missed');
SELECT tap._run('t212missed', interval '40 minutes');
SELECT tap._job('t212failing');
SELECT tap._run('t212failing', interval '8 minutes', 'failed', 'kaput');
SELECT tap._run('t212failing', interval '3 minutes', 'failed', 'kaput');
SELECT tap._job('t212disabled', '*/5 * * * *', false);
SELECT tap._run('t212disabled', interval '9 days');
SELECT tap._job('t212new');           -- never ran, first seen by this run
SELECT tap._job('t212old_new');       -- never ran, and this detector saw it two days ago
UPDATE ops.setting SET value = jsonb_build_object('t212old_new', to_jsonb((now() - interval '2 days')::text))
 WHERE key = 'cron_job_first_seen';
SELECT tap._renumber(); SELECT tap._run212();

SELECT ok(tap._case('t212healthy') IS NULL, 'J1: a job running on schedule has no case');
SELECT ok((tap._case('t212missed')).title = 'Cron job t212missed is not running',
  'J2: a 5-minute job whose last run was 40 minutes ago is reported not running');
SELECT ok((tap._case('t212failing')).title = 'Cron job t212failing failing'
          AND (tap._case('t212failing')).summary LIKE '%of the last 5 runs failed%',
  'J3: a job that IS running but failing keeps the existing rule, wording and case');
SELECT ok(tap._case('t212disabled') IS NULL,
  'J4: an intentionally disabled job is not reported, however long it has been idle');
SELECT ok(tap._case('t212new') IS NULL,
  'J5: a job that has never run and was just seen is inside its grace — no case');
SELECT ok((tap._case('t212old_new')).title = 'Cron job t212old_new is not running'
          AND (tap._case('t212old_new')).summary LIKE '%first seen by this detector%',
  'J6: a job that has never run since the detector first saw it two days ago IS reported');
SELECT ok((SELECT (value ? 't212healthy') AND (value ? 't212new') AND (value ->> 't212old_new') LIKE '%'
             FROM ops.setting WHERE key = 'cron_job_first_seen'),
  'J7: the first-seen map is maintained for every active job, and an existing entry is kept');
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'job_failure' AND subject_ref = 't212missed'), 1,
  'J8: one case per job');
SELECT tap._renumber(); SELECT tap._run212();
SELECT is((SELECT count(*)::int FROM ops."case" WHERE case_type = 'job_failure' AND subject_ref = 't212missed'), 1,
  'J9: a second run opens no duplicate');
SELECT is((SELECT state FROM ops.alert WHERE alert_key = 'job_failure:t212missed'), 'firing',
  'J10: the existing job_failure alert fires for a job that is not running');

-- recovery: the job runs again
SELECT tap._run('t212missed', interval '1 minute');
SELECT tap._renumber(); SELECT tap._run212();
SELECT is((tap._case('t212missed')).status, 'resolved',
  'J11: when the job runs again the condition really is gone — the existing sweep resolves it (recovery)');
SELECT is((SELECT state FROM ops.alert WHERE alert_key = 'job_failure:t212missed'), 'recovered',
  'J12: …and its alert recovers');
-- an operator disabling a job closes its case: their own act, not a silent loss
SELECT ok((tap._case('t212w')).status = 'open', 'J13 (witness): the stalled job''s case is still open');
DO $d$ begin
  if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is not null then
    perform cron.alter_job(tap._jid('t212w'), active => false);
  else
    update cron.job set active = false where jobid = tap._jid('t212w');
  end if;
end $d$;
SELECT tap._renumber(); SELECT tap._run212();
SELECT is((tap._case('t212w')).status, 'resolved',
  'J14: disabling the job closes its case — an operator''s act, unlike the seven-day disappearance');

-- ── the run's own accounting ────────────────────────────────────────────────
SELECT ok((SELECT (r #>> '{detail,scanned}')::int >= 1 AND (r ->> 'status') = 'succeeded'
             FROM (SELECT tap._run212() AS r) x),
  'J15: the detector still reports what it scanned and succeeds');

SELECT * FROM finish();
ROLLBACK;
