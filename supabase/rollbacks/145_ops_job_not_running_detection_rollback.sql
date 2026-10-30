-- ROLLBACK for 145_ops_job_not_running_detection.sql. Restores 143's ops.detect_jobs (the body that lands immediately
-- before 145 in the order 143 → 144 → 145; if anything else redefines detect_jobs first, restore THAT body instead),
-- drops ops.cron_expected_gap_minutes and deletes the first-seen row.
--
-- It never deletes case history. Cases 145 opened stay exactly as they are: they are ordinary job_failure cases, and
-- support closes them as usual. What changes is only what happens next — with 143's body back, a job that is not
-- running drops out of detection after seven days again and the sweep resolves its case, which is the defect 145
-- exists to fix. Re-applying 145 restores the detection; the first-seen map starts empty again, so a job that has
-- never run gets a fresh grace period.
begin;
set local lock_timeout = '3s';

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

drop function if exists ops.cron_expected_gap_minutes(text);
delete from ops.setting where key = 'cron_job_first_seen';
commit;
