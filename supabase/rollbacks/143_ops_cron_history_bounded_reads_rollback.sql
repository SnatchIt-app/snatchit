-- ============================================================================
-- 143 rollback: restores ops.job_health() (116) and ops.detect_jobs() (117) exactly as applied, with their grants.
-- ============================================================================
create or replace function ops.job_health()
returns jsonb language plpgsql stable security definer set search_path = ''
as $ops$
declare
  v_cron   jsonb;
  v_avail  boolean := to_regclass('cron.job_run_details') is not null;
begin
  perform ops.assert_reader();

  if v_avail then
    execute $q$
      select coalesce(jsonb_agg(jsonb_build_object(
               'jobid', j.jobid, 'jobname', j.jobname, 'schedule', j.schedule, 'active', j.active,
               'last_status', lr.status, 'last_end', lr.end_time, 'last_message', left(lr.return_message, 300),
               'runs_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '24 hours'),
               'failures_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.start_time > now() - interval '24 hours' and d.status = 'failed'))
               order by j.jobname), '[]'::jsonb)
        from cron.job j
        left join lateral (select d.status, d.end_time, d.return_message from cron.job_run_details d
                            where d.jobid = j.jobid order by d.start_time desc limit 1) lr on true
    $q$ into v_cron;
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
begin
  if v_cron_available then
    for r in execute $q$
      with recent as (
        select d.jobid, d.status, d.start_time, d.end_time, d.return_message,
               row_number() over (partition by d.jobid order by d.start_time desc) as rn
          from cron.job_run_details d
         where d.start_time > now() - interval '7 days'
      ),
      per_job as (
        select j.jobid, j.jobname, j.schedule,
               ops.cron_interval_minutes(j.schedule) as interval_min,
               (select count(*) from recent x where x.jobid = j.jobid) as runs_7d,
               (select bool_and(x.status = 'failed') from recent x where x.jobid = j.jobid and x.rn <= 2) as last2_failed,
               (select count(*) from recent x where x.jobid = j.jobid and x.rn <= 5 and x.status = 'failed') as failed_of_last5,
               (select max(x.start_time) from recent x where x.jobid = j.jobid and x.status = 'succeeded') as last_success,
               (select x.return_message from recent x where x.jobid = j.jobid and x.status = 'failed' order by x.start_time desc limit 1) as last_error
          from cron.job j
         where j.active
      )
      select * from per_job
       where runs_7d > 0
         and (coalesce(last2_failed, false)
              or last_success is null
              or last_success < now() - make_interval(mins => 3 * interval_min))
    $q$
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
