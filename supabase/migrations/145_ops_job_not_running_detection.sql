-- ============================================================================
-- 145_ops_job_not_running_detection.sql — a scheduled job that STOPS RUNNING stays detected. Today it disappears from
-- ops.detect_jobs after seven days and its open case is auto-resolved as "condition no longer detected".
--
-- WHY (the defect, proved by D on 2026-09-19 and again by pgTAP 212 J-2). ops.detect_jobs (117, bounded by 143) only
-- considers a job that has runs in the last 7 days:  `where runs_7d > 0 and (...)`. So for an ACTIVE pg_cron job that
-- stops running altogether:
--   * days 0-7  : its failures are detected, a p2 job_failure case is open, the job_failure:<name> alert fires;
--   * after 7 d : the job leaves the result entirely, its dedupe key leaves the active set, and ops.detect_sweep
--                 resolves the case with "auto: condition no longer detected" and recovers the alert —
--                 while the job is still active and still not running. The longer the outage, the quieter it gets.
-- A job that never ran at all was never detected in the first place.
--
-- WHAT.
--   * ops.cron_expected_gap_minutes(text) (new): how long a schedule should leave between runs. ops.cron_interval_minutes
--     returns 1500 for everything that is not `*/n`, which would make an hourly job look healthy for 75 hours. This
--     parses `*/n`, `m * * * *` (hourly), `m h * * *` (daily), `m h * * d` (weekly), `m h d * *` (monthly) and keeps
--     1500 as the fallback. ops.cron_interval_minutes is NOT changed: it still drives the existing failure rule, whose
--     alert meaning stays exactly as it is.
--   * ops.detect_jobs (143 body + this): every ACTIVE job is now considered, whether or not it ran in the window.
--     A job is reported NOT RUNNING when  now() > last_run + greatest(3 × expected gap, 15 minutes), where last_run is
--     its newest run at ANY age (found through the runid key, 143's floor plus an older-slice walk) or, for a job that
--     has never run, the first time this detector saw it.
--     The case's TITLE is kept honest as the condition changes (ops.case_upsert only ever refreshes the summary), so a
--     case opened while the job was merely failing does not keep saying "failing" after the job stopped running.
--     It uses the SAME case type and dedupe key as a failing job (job_failure / job:<jobname>), so:
--       - a job that was failing and then stops running keeps its case open instead of having it swept away;
--       - one job never produces two cases;
--       - when the job runs again the condition really is gone, and the existing sweep resolves it (recovery).
--     An INACTIVE job is not reported: `where j.active` is unchanged, and disabling a job resolves its case, which is
--     an operator's own act, not a silent loss.
--   * ops.setting 'cron_job_first_seen' (new row, seeded '{}'): a jsonb map jobname → first time the detector saw the
--     job. It is detector STATE, not configuration; it is what lets a never-run job be judged at all, and it gives a
--     newly scheduled job its grace period instead of an immediate case.
--   No new table, no index, no schedule change, no public object (Gate-2 census and the grant manifests are unchanged).
--
-- SEPARATE FROM #82/143 (owner, 2026-09-19). 143 only bounds the reads; this changes what is detected. 145 is built on
-- 143's body and therefore sorts and merges after it (A's order: 143 → 138 → 144 → 145).
--
-- WHAT THIS DOES NOT DO. It does not page anyone: an ops.alert row is still only visible in the console (mapped by D,
-- 2026-09-19 — nothing delivers it). Delivery is a separate change.
--
-- ROLLBACK: supabase/rollbacks/145_ops_job_not_running_detection_rollback.sql restores 143's ops.detect_jobs, drops
-- ops.cron_expected_gap_minutes and deletes the setting row. Cases already opened are NOT touched (they are history);
-- with 143's body back, a stalled job's case is swept as before.
-- VERIFY (read-only): md5(pg_get_functiondef('ops.detect_jobs()'::regprocedure)) against the review;
--   select value from ops.setting where key = 'cron_job_first_seen';
-- FAILURE BEHAVIOUR: one transaction. The detector writes one ops.setting row per run at most (the first-seen map) and
-- otherwise only the case/alert writes it already made. A failure inside a detector run is recorded by ops.run_job as a
-- failed job_run, as before; it does not raise into the cron tick.
-- OWNER APPROVAL POINT: local build only. No PR, apply or schedule change without the owner. Once applied this detector
-- opens cases for jobs that are genuinely not running — that is the point — so apply it when someone can act on them.
-- ============================================================================

begin;
set local lock_timeout = '3s';

insert into ops.setting (key, value) values ('cron_job_first_seen', '{}'::jsonb) on conflict (key) do nothing;

-- ── how long a schedule should leave between runs ───────────────────────────────────────────────────────────────────
create or replace function ops.cron_expected_gap_minutes(p_schedule text)
returns integer language sql immutable
as $ops$
  select case
           when p_schedule is null                              then 1500
           when p_schedule ~ '^\s*\*/\d+\s'                     then greatest((regexp_match(p_schedule, '^\s*\*/(\d+)'))[1]::integer, 1)
           when p_schedule ~ '^\s*\d+\s+\*\s+\*\s+\*\s+\*\s*$'  then 60      -- m * * * *  hourly
           when p_schedule ~ '^\s*\d+\s+\d+\s+\*\s+\*\s+\*\s*$' then 1440    -- m h * * *  daily
           when p_schedule ~ '^\s*\d+\s+\d+\s+\*\s+\*\s+\d+\s*$' then 10080  -- m h * * d  weekly
           when p_schedule ~ '^\s*\d+\s+\d+\s+\d+\s+\*\s+\*\s*$' then 44640  -- m h d * *  monthly
           else 1500                                                          -- unknown shape: the old fallback
         end;
$ops$;
revoke all on function ops.cron_expected_gap_minutes(text) from public, anon, authenticated, service_role;

-- ── ops.detect_jobs (143 body + 145: every ACTIVE job is judged, at any age) ───────────────────────────────────────
create or replace function ops.detect_jobs()
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
  -- 145: a job that STOPS running must stay detected
  v_first     jsonb;                      -- jobname -> when this detector first saw the job
  v_first_new jsonb;
  v_missing   bigint[] := array[]::bigint[];
  v_up        bigint;
  v_fjob      bigint[];
  v_flast     timestamptz[];
  v_gap       integer;
  v_since     timestamptz;
  v_stalled   boolean;
  v_failing   boolean;
begin
  if v_cron_available then
    -- 145: one row per ACTIVE job for this run. A temp table (not arrays) because the walk below fills in the newest
    -- run of any age for the jobs that have none in the window, before anything is decided.
    create temp table if not exists dj145 (
      jobid bigint primary key, jobname text, schedule text, interval_min integer, gap_min integer,
      runs_7d bigint, last2_failed boolean, failed_of_last5 bigint, last_success timestamptz,
      last_run timestamptz, last_error text
    ) on commit drop;
    delete from pg_temp.dj145;
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
            select q.jobid, q.runid, q.status, q.rn, q.n, q.last_success, q.last_failed_runid, q.last_run
              from (select d.jobid, d.runid, d.status,
                           row_number() over w as rn,
                           count(*) over wj as n,
                           max(d.start_time) filter (where d.status = 'succeeded') over wj as last_success,
                           max(d.start_time) over wj as last_run,
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
               max(x.last_run) as last_run,
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
               ops.cron_expected_gap_minutes(j.schedule) as gap_min,
               x.last_run,
               coalesce(x.runs_7d, 0) as runs_7d,
               (select bool_and(l.status = 'failed') from last5 l where l.jobid = j.jobid and l.rn <= 2) as last2_failed,
               (select count(*) from last5 l where l.jobid = j.jobid and l.rn <= 5 and l.status = 'failed') as failed_of_last5,
               x.last_success,
               (select d.return_message from cron.job_run_details d where d.runid = x.last_failed_runid) as last_error
          from cron.job j
          left join recent x on x.jobid = j.jobid
         where j.active
      )
      -- 145: EVERY active job, not only those with runs in the window. Which ones are reported is decided below,
      -- where a job with no run in the window has its newest run of any age looked up first.
      select * from per_job
    $q$ using v_floor
    loop
      insert into pg_temp.dj145 (jobid, jobname, schedule, interval_min, gap_min, runs_7d, last2_failed,
                                 failed_of_last5, last_success, last_run, last_error)
      values (r.jobid, r.jobname, r.schedule, r.interval_min, r.gap_min, r.runs_7d, r.last2_failed,
              r.failed_of_last5, r.last_success, r.last_run, r.last_error);
      if r.last_run is null then v_missing := v_missing || r.jobid; end if;
    end loop;

    -- 145: the newest run of any age for the jobs with none in the window — 143's walk, newest slice first, stopping
    -- as soon as every one of them is found. A job that never ran walks to the bottom; retention bounds that.
    v_up := v_floor;
    while cardinality(v_missing) > 0 and v_up >= v_lo loop
      execute $q$
        select coalesce(array_agg(x.jobid), array[]::bigint[]), coalesce(array_agg(x.last_run), array[]::timestamptz[])
          from (select d.jobid, max(d.start_time) as last_run from cron.job_run_details d
                 where d.runid > $1 and d.runid <= $2 and d.jobid = any($3) and d.start_time is not null
                 group by d.jobid) x
      $q$ into v_fjob, v_flast using greatest(v_up - 5000, v_lo - 1), v_up, v_missing;
      for v_m in 1 .. coalesce(cardinality(v_fjob), 0) loop
        update pg_temp.dj145 set last_run = v_flast[v_m] where jobid = v_fjob[v_m] and last_run is null;
      end loop;
      v_missing := array(select m from unnest(v_missing) m where not (m = any(v_fjob)));
      v_up := v_up - 5000;
    end loop;

    -- 145: first-seen, so a job that has never run can be judged at all, and a newly scheduled one gets its grace.
    select coalesce(s.value, '{}'::jsonb) into v_first from ops.setting s where s.key = 'cron_job_first_seen';
    v_first := coalesce(v_first, '{}'::jsonb);
    select coalesce(jsonb_object_agg(t.jobname, to_jsonb(coalesce(v_first ->> t.jobname, now()::text))), '{}'::jsonb)
      into v_first_new from pg_temp.dj145 t;
    if v_first_new is distinct from v_first then
      insert into ops.setting (key, value) values ('cron_job_first_seen', v_first_new)
      on conflict (key) do update set value = excluded.value, updated_at = now();
    end if;

    for r in select * from pg_temp.dj145 order by jobname
    loop
      -- 145: not running — judged from the newest run at any age, or from when this detector first saw the job.
      v_gap     := greatest(coalesce(r.gap_min, 1500), 1);
      v_since   := coalesce(r.last_run, nullif(v_first_new ->> r.jobname, '')::timestamptz);
      v_stalled := v_since is not null
                   and now() > v_since + greatest(make_interval(mins => 3 * v_gap), interval '15 minutes');
      -- the rule 117 already had, unchanged, for a job that IS running
      v_failing := coalesce(r.runs_7d, 0) > 0
                   and (coalesce(r.last2_failed, false)
                        or r.last_success is null
                        or r.last_success < now() - make_interval(mins => 3 * r.interval_min));
      continue when not v_stalled and not v_failing;

      v_scanned := v_scanned + 1;
      v_res := ops.detect_case('job_failure', 'job', null, r.jobname,
                 case when v_stalled then format('Cron job %s is not running', r.jobname)
                      else format('Cron job %s failing', r.jobname) end,
                 case when v_stalled then
                   format('pg_cron job "%s" (%s) is ACTIVE but has not run since %s (expected about every %s minutes). '
                          || 'Its case stays open until it runs again%s.',
                          r.jobname, r.schedule,
                          coalesce(to_char(r.last_run at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'),
                                   'ever — first seen by this detector at '
                                   || to_char(v_since at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"')),
                          v_gap,
                          case when r.last_error is not null then format('; last error: %s', left(r.last_error, 500)) else '' end)
                 else
                   format('pg_cron job "%s" (%s): %s of the last 5 runs failed; last success %s%s.',
                          r.jobname, r.schedule, r.failed_of_last5,
                          coalesce(to_char(r.last_success at time zone 'utc', 'YYYY-MM-DD HH24:MI"Z"'), 'never in the last 7 days'),
                          case when r.last_error is not null then format('; last error: %s', left(r.last_error, 500)) else '' end)
                 end,
                 'p2', null, 'jobs');
      -- 145: ops.case_upsert refreshes a case's summary but never its title, so a case opened while the job was
      -- merely failing would keep saying "failing" after the job stopped running altogether. Keep the title honest.
      update ops."case" c
         set title = case when v_stalled then format('Cron job %s is not running', r.jobname)
                          else format('Cron job %s failing', r.jobname) end,
             version = c.version + 1
       where c.id = (v_res ->> 'case_id')::uuid
         and c.title is distinct from (case when v_stalled then format('Cron job %s is not running', r.jobname)
                                            else format('Cron job %s failing', r.jobname) end);
      v_keys := v_keys || (v_res ->> 'dedupe_key');
      v_refs := v_refs || r.jobname;
      if (v_res ->> 'opened')::boolean then v_opened := v_opened + 1; end if;
      perform ops.alert_fire('job_failure:' || r.jobname, 'job_failure',
                jsonb_build_object('source', 'pg_cron', 'jobname', r.jobname, 'failed_of_last5', r.failed_of_last5,
                                   'last_success', r.last_success, 'not_running', v_stalled, 'last_run', r.last_run));
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
revoke all on function ops.detect_jobs() from public, anon, authenticated, service_role;

commit;
