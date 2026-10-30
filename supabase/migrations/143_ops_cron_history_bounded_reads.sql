-- ============================================================================
-- 143_ops_cron_history_bounded_reads.sql — ops.job_health() and ops.detect_jobs() read cron.job_run_details
-- through its runid primary key, bounded to the window they report on, instead of reading the whole table.
--
-- WHY. cron.job_run_details has only its runid primary key and grows ~13k rows a day (no retention). The applied
-- bodies (116, 117) read all of it:
--   * job_health(): three correlated subqueries per cron job, each a full read (≈3 × jobs full reads per call);
--     it has exceeded the 8 s statement timeout in production since 2026-09-08 (454,675 rows then);
--   * detect_jobs(): a full read to build a 7-day CTE, then five correlated re-reads of it per job, every 5 minutes
--     through ops.run_all_detectors() (production: mean 11.7 s, ≈99% of the database's block reads, 2026-09-19).
--
-- WHAT. Only the two function bodies change (CREATE OR REPLACE, same signatures, SECURITY DEFINER, search_path,
-- volatility, owner and grants). No new object, no index, no schedule change, no retention, no data change.
--
-- WHY THE RUNID FLOOR IS COMPLETE (nothing the old full read saw is skipped). pg_cron (src/pg_cron.c,
-- ManageCronTask) allocates a run's runid from cron.runid_seq, in the scheduler's order, when the task leaves
-- WAITING, and inserts the row with status 'starting' and start_time NULL. start_time is written later:
--   * libpq mode (the default): when the command is sent, which must happen before task->startDeadline =
--     allocation time + CronTaskStartTimeout (10 s), or the run fails 'job startup timeout' with start_time NULL;
--   * background-worker mode: after the worker has started, while the launcher waits (WaitForBackgroundWorkerStartup)
--     before allocating any later runid.
-- So for runids a < b: start_time(a) <= allocation(a) + 10 s <= allocation(b) + 10 s <= start_time(b) + 10 s.
-- The floor is a run whose start_time <= (window start − 1 hour), found by binary search over runid (about 20
-- primary-key probes); every run with a smaller runid started at most 10 s after it, i.e. more than 1 hour − 10 s
-- before the window, so every run that started inside the window lies above the floor. Runs above the floor that
-- have not started yet (start_time NULL) are above it too. The 1-hour margin is 360 × pg_cron's bound; the only
-- thing that could defeat it is the database host's clock stepping backwards by more than ~1 hour. A floor that
-- is too low is always safe (more rows are read); only one that is too high could omit a run. Runs with
-- start_time NULL never matched the old window predicates and do not match the new ones.
--
-- WHAT THE BOUNDED READ STILL FINDS (the owner's condition: nothing silently omitted).
--   * job_health's newest run per job: a job never runs concurrently with itself (pg_cron queues its next run
--     until the current one ends), so its newest run is its largest runid. Jobs with no run above the floor
--     (a hung run, an inactive job, a job whose last run is older than the window, a job that never ran) are
--     looked up exactly, walking the older runs newest-first until every such job is found.
--   * detect_jobs: exactly the runs the old 7-day CTE held (start_time inside 7 days), ranked per job by runid
--     (= by start_time for one job), so the last-2 / last-5 / last-success / last-error values are the same.
--   * Reads go in slices of at most 5000 runids, so no sort or hash handles more than 5000 rows whatever the
--     planner estimates. Production's statistics for this table are not established (no vacuum or analyse is
--     recorded, but those counters reset) and work_mem is 2 MB; measured both without and with statistics.
--
-- THE ONE DELIBERATE DIFFERENCE. The applied job_health picked a job's last run with
-- `order by start_time desc limit 1`; DESC sorts NULLs first, so a job that EVER had a startup-timeout run
-- (start_time NULL) showed that run as its last run for ever, hiding newer runs, including a hung one. 143 shows
-- the newest run (largest runid). Every 24-hour count is identical. pgTAP 210 pins both statements (B1, B2, C10).
--
-- MEASURED (local, synthetic history without statistics, work_mem 2 MB, 3 runs each; 37 d = 457,591 rows,
-- 74 d = 915,059 rows): job_health 2.6 s → 4 ms (37 d) and 5.3 s → 4 ms (74 d); detect_jobs 0.80 s → 65 ms and
-- 0.88 s → 66 ms. Blocks per call: job_health 1.43 M / 2.86 M → ~720; detect_jobs 19.9 k / 39.7 k → ~4.3 k (the
-- 7-day window itself). Both are now independent of history length. Worst case: a job with no run in the last
-- 25 hours (e.g. one that never ran) makes job_health walk older history in slices, one pass over the table at most
-- (37 d + such jobs: 3.8 s → 80 ms). With statistics (37 d, analysed): job_health 2.5 s → 4 ms (~1.0 k blocks),
-- detect_jobs 0.87 s → 66 ms (~6.6 k blocks). No sequential scan, temp file or external sort in any new plan.
-- Local timings are warm-cache; blocks, temp and plan shape are what transfer to production.
--
-- ROLLBACK: supabase/rollbacks/143_ops_cron_history_bounded_reads_rollback.sql restores the 116/117 bodies verbatim.
-- VERIFY (read-only): select md5(pg_get_functiondef('ops.job_health()'::regprocedure)),
--                            md5(pg_get_functiondef('ops.detect_jobs()'::regprocedure));  -- compare with the review
-- FAILURE BEHAVIOUR: a function body that fails to compile rolls the migration back; on success the old bodies are
-- gone until the rollback runs. Neither function writes cron data; detect_jobs writes ops cases/alerts as before.
-- OWNER APPROVAL POINT: production apply only by the owner-gated path (DEPLOYMENT_PATHS.md); production's applied
-- bodies must first be confirmed equal to 116/117 (read-only md5 check, owner-authorised).
-- ============================================================================

create or replace function ops.job_health()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_cron   jsonb;
  v_avail  boolean := to_regclass('cron.job_run_details') is not null;
  -- 143: bounded, sliced read of cron.job_run_details
  v_floor   bigint;
  v_lo      bigint;
  v_hi      bigint;
  v_a       bigint;
  v_b       bigint;
  v_m       bigint;
  v_pr      bigint;
  v_ps      timestamptz;
  v_up      bigint;
  v_wjob    bigint[] := array[]::bigint[];
  v_wruns   bigint[] := array[]::bigint[];
  v_wfail   bigint[] := array[]::bigint[];
  v_wlatest bigint[] := array[]::bigint[];
  v_missing bigint[] := array[]::bigint[];
  v_fjob    bigint[] := array[]::bigint[];
  v_flatest bigint[] := array[]::bigint[];
  v_older   bigint[] := array[]::bigint[];
begin
  perform ops.assert_reader();

  if v_avail then
    -- 143: bounded read of cron.job_run_details, in slices of at most 5000 runids so that no sort or hash depends
    -- on planner estimates (production's statistics for the table are not established). See the migration header.
    -- (1) Floor, for the 24-hour window with a 1-hour margin: every run that started inside the window has a larger
    --     runid.
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
        if v_pr is null or v_ps <= now() - interval '24 hours' - interval '1 hour' then
          v_a := v_m;
          if v_pr is not null then v_floor := greatest(v_floor, v_pr); end if;
        else
          v_b := v_m;
        end if;
      end loop;
      execute $q$ select d.runid, d.start_time from cron.job_run_details d
                   where d.runid <= $1 and d.start_time is not null order by d.runid desc limit 1 $q$
        into v_pr, v_ps using v_b;
      if v_pr is not null and v_ps <= now() - interval '24 hours' - interval '1 hour' then v_floor := greatest(v_floor, v_pr); end if;
    end if;

    -- (2) One pass over the runs above the floor: the 24-hour counts and each job's newest run. A job never runs
    --     concurrently with itself, so its newest run is its largest runid.
    execute $q$
      with slices as (
        select s as lo, least(s + 5000, h.hi) as up
          from (select coalesce(max(d.runid), 0) as hi from cron.job_run_details d) h,
               generate_series($1, h.hi - 1, 5000) s
      ),
      part as (
        select p.*
          from slices sl
          cross join lateral (
            select d.jobid,
                   count(*) filter (where d.start_time > now() - interval '24 hours') as runs_24h,
                   count(*) filter (where d.start_time > now() - interval '24 hours' and d.status = 'failed') as failures_24h,
                   max(d.runid) as latest
              from cron.job_run_details d
             where d.runid > sl.lo and d.runid <= sl.up
             group by d.jobid) p
      ),
      agg as (
        select x.jobid, sum(x.runs_24h)::bigint as runs_24h, sum(x.failures_24h)::bigint as failures_24h,
               max(x.latest) as latest
          from part x group by x.jobid
      )
      select coalesce(array_agg(a.jobid), array[]::bigint[]), coalesce(array_agg(a.runs_24h), array[]::bigint[]),
             coalesce(array_agg(a.failures_24h), array[]::bigint[]), coalesce(array_agg(a.latest), array[]::bigint[])
        from agg a
    $q$ into v_wjob, v_wruns, v_wfail, v_wlatest using v_floor;

    -- (3) Jobs with no run above the floor (their newest run is older than the window, or they never ran): found
    --     exactly by walking the older runs newest-first, slice by slice, stopping once every such job is found.
    --     A hung run, an inactive job's last run and any job's last run older than the window are all found here.
    select coalesce(array_agg(j.jobid), array[]::bigint[]) into v_missing
      from cron.job j where not (j.jobid = any(v_wjob));
    v_up := v_floor;
    while cardinality(v_missing) > 0 and v_up >= v_lo loop
      execute $q$
        select coalesce(array_agg(x.jobid), array[]::bigint[]), coalesce(array_agg(x.latest), array[]::bigint[])
          from (select d.jobid, max(d.runid) as latest from cron.job_run_details d
                 where d.runid > $1 and d.runid <= $2 and d.jobid = any($3)
                 group by d.jobid) x
      $q$ into v_fjob, v_flatest using greatest(v_up - 5000, v_lo - 1), v_up, v_missing;
      v_older   := v_older || v_flatest;
      v_missing := array(select m from unnest(v_missing) m where not (m = any(v_fjob)));
      v_up := v_up - 5000;
    end loop;

    -- (4) Assemble, reading each job's newest run by primary key.
    execute $q$
      with win as (
        select * from unnest($1::bigint[], $2::bigint[], $3::bigint[]) as w(jobid, runs_24h, failures_24h)
      ),
      latest as (
        select d.jobid, d.status, d.end_time, d.return_message
          from cron.job_run_details d
         where d.runid = any($4::bigint[] || $5::bigint[])
      )
      select coalesce(jsonb_agg(jsonb_build_object(
               'jobid', j.jobid, 'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active,
               'last_status', lr.status, 'last_end', lr.end_time, 'last_message', left(lr.return_message, 300),
               'runs_24h', coalesce(w.runs_24h, 0),
               'failures_24h', coalesce(w.failures_24h, 0))
               order by j.jobname), '[]'::jsonb)
        from cron.job j
        left join win w on w.jobid = j.jobid
        left join latest lr on lr.jobid = j.jobid
    $q$ into v_cron using v_wjob, v_wruns, v_wfail, v_wlatest, v_older;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'jobid', j.jobid, 'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active,
             'last_status', null, 'last_end', null, 'last_message', null, 'runs_24h', null, 'failures_24h', null)
             order by j.jobname), '[]'::jsonb)
      into v_cron
      from cron.job j;
  end if;

  return jsonb_build_object(
    'generated_at', now(),
    'cron_jobs', jsonb_build_object('available', v_avail, 'items', v_cron,
                   'note', case when v_avail then null else 'cron.job_run_details is not present on this database; run history unavailable' end),
    'ops_jobs', coalesce((select jsonb_agg(to_jsonb(js) || jsonb_build_object(
                             'recent_runs', coalesce((select jsonb_agg(to_jsonb(jr) order by jr.started_at desc) from (
                                               select * from ops.job_run where job_name = js.job_name order by started_at desc limit 5) jr), '[]'::jsonb))
                             order by js.job_name)
                            from ops.job_state js), '[]'::jsonb),
    'webhook_backlog', (select jsonb_build_object(
                           'unprocessed', count(*) filter (where w.failed_at is null),
                           'failed',      count(*) filter (where w.failed_at is not null),
                           'oldest_unprocessed_at', min(w.received_at) filter (where w.failed_at is null),
                           'oldest_unprocessed_event_id', (select w2.event_id from public.stripe_webhook_events w2
                                                            where w2.processed_at is null and w2.failed_at is null
                                                            order by w2.received_at asc limit 1))
                          from public.stripe_webhook_events w where w.processed_at is null),
    'notify', jsonb_build_object(
                'delivery', coalesce((select jsonb_object_agg(d.state, d.n) from (
                               select state, count(*) n from notify.delivery group by state) d), '{}'::jsonb),
                'outbox',   coalesce((select jsonb_object_agg(o.state, o.n) from (
                               select state, count(*) n from notify.outbox group by state) o), '{}'::jsonb),
                'note', 'notify.* has no dispatch adapter yet (parked); counts are informational'),
    'alerts', coalesce((select jsonb_agg(to_jsonb(al) order by al.last_fired_at desc) from ops.alert al where al.state = 'firing'), '[]'::jsonb));
end;
$ops$;
revoke all on function ops.job_health() from public, anon, authenticated;
grant execute on function ops.job_health() to authenticated;

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
revoke all on function ops.detect_jobs() from public, anon, authenticated, service_role;
