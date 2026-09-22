-- ============================================================================
-- 210_ops_cron_history_bounded_reads.sql — migration 143 (bounded reads of cron.job_run_details in
-- ops.job_health() and ops.detect_jobs()).
--   Section A: fixture. Synthetic pg_cron history built inside this transaction, following pg_cron's own rules
--     (runid allocated before start_time; start within the 10 s startup deadline; one job never runs concurrently
--     with itself). Runids sit contiguously BELOW any real pg_cron row and the history ends before the first one,
--     so on CI's real pg_cron the combined table still obeys those rules; REPEATABLE READ keeps the scheduler's new rows out of the snapshot.
--     Edge fixtures: failures exactly at the 24 h and 7 d window edges and 1 µs either side; a runid/start_time
--     inversion across each edge inside the startup deadline; hung runs that started before the floor; an inactive
--     job, a never-run job, a daily job; a startup-timeout row (start_time NULL) older than the job's newest run.
--   Section B: equivalence with the applied 116/117 bodies (verbatim copies under t210_old), in ONE transaction.
--   Section C: job_health against a brute-force oracle (the definition, by full read).
--   Section D: detect_jobs edge outcomes.
--   Section E: catalog — security definer, search_path, volatility, owner and grants unchanged.
-- ============================================================================
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT plan(25);
SELECT tap.seed_core();
INSERT INTO public.admin_users (user_id, label) VALUES (tap.admin_user(), 'TEST ADMIN') ON CONFLICT (user_id) DO NOTHING;
CREATE FUNCTION tap._aal2_210() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;

-- ── Section A — fixture ──────────────────────────────────────────────────────
-- A1: pg_cron's own run-history table (present on CI's real pg_cron; the local plain-PostgreSQL harness has none)
DO $$ begin
  if to_regclass('cron.job_run_details') is null then
    create sequence if not exists cron.runid_seq;
    create table cron.job_run_details (
      jobid bigint, runid bigint primary key default pg_catalog.nextval('cron.runid_seq'), job_pid integer,
      database text, username text, command text, status text, return_message text,
      start_time timestamptz, end_time timestamptz);
  end if;
end $$;

-- A2: the applied bodies, verbatim, for comparison
CREATE SCHEMA t210_old;
GRANT USAGE ON SCHEMA t210_old TO authenticated;
create or replace function t210_old.job_health()
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
revoke all on function t210_old.job_health() from public, anon, authenticated;
grant execute on function t210_old.job_health() to authenticated;

create or replace function t210_old.job_health_by_runid()
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
                            where d.jobid = j.jobid order by d.runid desc limit 1) lr on true
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
revoke all on function t210_old.job_health_by_runid() from public, anon, authenticated;
grant execute on function t210_old.job_health_by_runid() to authenticated;

create or replace function t210_old.detect_jobs()
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
revoke all on function t210_old.detect_jobs() from public, anon, authenticated, service_role;

-- A3: jobs, through pg_cron's own API
CREATE TEMP TABLE t210_jobs (name text PRIMARY KEY, jobid bigint) ON COMMIT DROP;
INSERT INTO t210_jobs SELECT v.n, cron.schedule(v.n, v.s, 'select 1 /* t210 */') FROM (VALUES
  ('t210-f1','*/2 * * * *'), ('t210-f2','*/2 * * * *'), ('t210-f3','*/2 * * * *'), ('t210-f4','*/2 * * * *'),
  ('t210-f5','*/2 * * * *'), ('t210-f6','*/2 * * * *'), ('t210-f7','*/2 * * * *'), ('t210-f8','*/2 * * * *'),
  ('t210-daily','17 4 * * *'), ('t210-hung30','*/2 * * * *'), ('t210-hung8d','*/5 * * * *'),
  ('t210-inactive','*/10 * * * *'), ('t210-never','*/15 * * * *'), ('t210-last2','*/4 * * * *'),
  ('t210-stale','*/2 * * * *'), ('t210-rank5','*/3 * * * *'), ('t210-quirk','*/3 * * * *'),
  ('t210-e24in','*/20 * * * *'), ('t210-e24eq','*/20 * * * *'), ('t210-e24out','*/20 * * * *'), ('t210-inv24','*/20 * * * *'),
  ('t210-e7in','*/20 * * * *'), ('t210-e7eq','*/20 * * * *'), ('t210-e7out','*/20 * * * *'), ('t210-inv7','*/20 * * * *')) v(n, s);
DO $$ declare v_id bigint := (SELECT jobid FROM t210_jobs WHERE name = 't210-inactive'); begin
  if to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') is not null then
    perform cron.alter_job(v_id, active => false);
  else
    update cron.job set active = false where jobid = v_id;
  end if;
end $$;

-- A4: the synthetic history ends one minute before any real pg_cron row, so runid order stays start order
CREATE TEMP TABLE t210_now ON COMMIT DROP AS
  SELECT now() AS t0,
         least(now(), coalesce((SELECT min(d.start_time) FROM cron.job_run_details d WHERE d.start_time IS NOT NULL), now()))
           - interval '1 minute' AS anchor;
CREATE TEMP TABLE t210_g (jobid bigint, name text, alloc timestamptz, st timestamptz, et timestamptz,
                          status text DEFAULT 'succeeded', msg text DEFAULT 'SELECT 1', rn_desc integer) ON COMMIT DROP;
INSERT INTO t210_g (jobid, name, alloc)
SELECT j.jobid, j.name, t
  FROM t210_jobs j, t210_now n,
       LATERAL generate_series(
         CASE j.name WHEN 't210-inactive' THEN n.anchor - interval '21 days' ELSE n.anchor - interval '9 days' END,
         CASE j.name WHEN 't210-hung30' THEN n.anchor - interval '30 hours'
                     WHEN 't210-hung8d' THEN n.anchor - interval '8 days'
                     WHEN 't210-inactive' THEN n.anchor - interval '20 days'
                     ELSE n.anchor END,
         CASE j.name WHEN 't210-daily' THEN interval '1 day'     WHEN 't210-hung8d' THEN interval '5 minutes'
                     WHEN 't210-inactive' THEN interval '10 minutes' WHEN 't210-last2' THEN interval '4 minutes'
                     WHEN 't210-rank5' THEN interval '3 minutes' WHEN 't210-quirk' THEN interval '3 minutes'
                     ELSE interval '2 minutes' END) t
 WHERE j.name NOT IN ('t210-never','t210-e24in','t210-e24eq','t210-e24out','t210-inv24',
                      't210-e7in','t210-e7eq','t210-e7out','t210-inv7');
UPDATE t210_g g SET rn_desc = x.rn
  FROM (SELECT ctid AS c, row_number() OVER (PARTITION BY jobid ORDER BY alloc DESC) AS rn FROM t210_g) x WHERE g.ctid = x.c;
UPDATE t210_g SET st = alloc + make_interval(secs => (extract(epoch FROM alloc)::bigint % 5) * 0.08);
UPDATE t210_g SET et = st + interval '300 milliseconds';
UPDATE t210_g SET status = 'running', msg = NULL, et = NULL WHERE name IN ('t210-hung30','t210-hung8d') AND rn_desc = 1;
UPDATE t210_g SET status = 'failed', msg = 'ERROR:  t210 last two' WHERE name = 't210-last2' AND rn_desc <= 2;
UPDATE t210_g SET status = 'failed', msg = 'ERROR:  t210 stale' FROM t210_now n
 WHERE name = 't210-stale' AND alloc > n.anchor - interval '2 days';
UPDATE t210_g SET status = 'failed', msg = 'ERROR:  t210 rank ' || rn_desc WHERE name = 't210-rank5' AND rn_desc IN (1, 2, 5, 6);
-- a startup-timeout row (start_time NULL) three days ago, older than t210-quirk's newest run
INSERT INTO t210_g (jobid, name, alloc, st, et, status, msg)
SELECT j.jobid, j.name, n.anchor - interval '3 days' + interval '11 seconds', NULL,
       n.anchor - interval '3 days' + interval '21 seconds', 'failed', 'job startup timeout'
  FROM t210_jobs j, t210_now n WHERE j.name = 't210-quirk';
-- window edges (relative to this transaction's now()), all failures
INSERT INTO t210_g (jobid, name, alloc, st, et, status, msg)
SELECT j.jobid, j.name, e.st - interval '1 second', e.st, e.st + interval '300 milliseconds', 'failed', 'ERROR:  t210 edge ' || j.name
  FROM t210_jobs j, t210_now n,
       LATERAL (SELECT CASE j.name
                  WHEN 't210-e24in'  THEN n.t0 - interval '24 hours' + interval '1 microsecond'
                  WHEN 't210-e24eq'  THEN n.t0 - interval '24 hours'
                  WHEN 't210-e24out' THEN n.t0 - interval '24 hours' - interval '1 microsecond'
                  WHEN 't210-e7in'   THEN n.t0 - interval '7 days' + interval '1 microsecond'
                  WHEN 't210-e7eq'   THEN n.t0 - interval '7 days'
                  WHEN 't210-e7out'  THEN n.t0 - interval '7 days' - interval '1 microsecond' END AS st) e
 WHERE j.name IN ('t210-e24in','t210-e24eq','t210-e24out','t210-e7in','t210-e7eq','t210-e7out');
-- inversions across each edge, inside pg_cron's 10 s startup deadline: X (allocated first, started 9 s later,
-- INSIDE the window) and Y (allocated 1 s after X, started 1 s later, OUTSIDE the window)
INSERT INTO t210_g (jobid, name, alloc, st, et, status, msg)
SELECT j.jobid, j.name, e.b + x.da, e.b + x.ds, e.b + x.ds + interval '300 milliseconds', x.status, x.msg
  FROM t210_now n,
       LATERAL (VALUES ('t210-inv24', 't210-f1', n.t0 - interval '24 hours'),
                       ('t210-inv7',  't210-f2', n.t0 - interval '7 days')) e(xname, yname, b),
       LATERAL (VALUES (e.xname, interval '-8 seconds', interval '1 second',  'failed',    'ERROR:  t210 inversion X'),
                       (e.yname, interval '-7 seconds', interval '-6 seconds', 'succeeded', 'SELECT 1')) x(name, da, ds, status, msg)
  JOIN t210_jobs j ON j.name = x.name;

INSERT INTO cron.job_run_details (jobid, runid, job_pid, database, username, command, status, return_message, start_time, end_time)
SELECT g.jobid,
       -- contiguous runids just below any real pg_cron row (production's runids are contiguous too)
       row_number() OVER (ORDER BY g.alloc, g.jobid)
         + coalesce((SELECT min(d.runid) FROM cron.job_run_details d), 1) - (SELECT count(*) FROM t210_g) - 1,
       4242, current_database(), current_user, 'select 1 /* t210 */', g.status, g.msg, g.st, g.et
  FROM t210_g g;

SELECT cmp_ok((SELECT count(*) FROM cron.job_run_details WHERE command = 'select 1 /* t210 */')::int, '>', 60000,
  'T1: the synthetic history is loaded (more than 60 000 runs, several 5000-runid slices per window)');

-- ── Section B — equivalence with the applied bodies, in this one transaction ─────────────────────────────────
SELECT set_config('request.jwt.claims',
  json_build_object('sub', tap.admin_user(), 'role', 'authenticated', 'aal', 'aal2')::text, true);
CREATE TEMP TABLE t210_jh ON COMMIT DROP AS
  SELECT ops.job_health() - 'generated_at' AS new_j,
         t210_old.job_health() - 'generated_at' AS old_j,
         t210_old.job_health_by_runid() - 'generated_at' AS old_runid_j;

SELECT is((SELECT new_j FROM t210_jh), (SELECT old_runid_j FROM t210_jh),
  'B1: job_health equals the applied body with only its newest-run pick made by runid (the documented correction)');
SELECT is(
  (SELECT jsonb_agg(jsonb_build_object('j', i ->> 'jobname', 'r', i -> 'runs_24h', 'f', i -> 'failures_24h') ORDER BY i ->> 'jobname')
     FROM t210_jh, jsonb_array_elements(new_j -> 'cron_jobs' -> 'items') i),
  (SELECT jsonb_agg(jsonb_build_object('j', i ->> 'jobname', 'r', i -> 'runs_24h', 'f', i -> 'failures_24h') ORDER BY i ->> 'jobname')
     FROM t210_jh, jsonb_array_elements(old_j -> 'cron_jobs' -> 'items') i),
  'B2: every job''s 24-hour run and failure counts equal the applied body''s, including every window edge');
SELECT is((SELECT new_j - 'cron_jobs' FROM t210_jh), (SELECT old_j - 'cron_jobs' FROM t210_jh),
  'B3: everything outside cron_jobs is unchanged');

CREATE FUNCTION t210_old.capture(p_new boolean) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare v_ret jsonb; v jsonb;
begin
  begin
    if p_new then v_ret := ops.detect_jobs(); else v_ret := t210_old.detect_jobs(); end if;
    v := jsonb_build_object('ret', v_ret,
      'cases', (select coalesce(jsonb_agg(jsonb_build_object('ref', c.subject_ref, 'key', c.dedupe_key, 'title', c.title,
                  'summary', c.summary, 'status', c.status, 'priority', c.priority, 'detector', c.detector)
                  order by c.dedupe_key), '[]'::jsonb) from ops."case" c where c.case_type = 'job_failure'),
      'alerts', (select coalesce(jsonb_agg(jsonb_build_object('key', a.alert_key, 'kind', a.kind, 'state', a.state,
                  'payload', a.payload) order by a.alert_key), '[]'::jsonb) from ops.alert a where a.alert_key like 'job_failure:%'));
    raise exception using errcode = 'T2100', message = v::text;   -- roll the detector's writes back, keep the capture
  exception when sqlstate 'T2100' then
    return sqlerrm::jsonb;
  end;
end $f$;
CREATE TEMP TABLE t210_dj ON COMMIT DROP AS SELECT t210_old.capture(false) AS old_c, t210_old.capture(true) AS new_c;

-- Amended 2026-09-19 (migration 145): 145 makes detect_jobs report ACTIVE jobs that are NOT RUNNING as well, so the
-- three equivalence assertions below now compare the part 145 does not change — the failing-job class — and the new
-- class is asserted in pgTAP 212. Everything 143 itself changed is still pinned here.
-- ISOLATION (2026-09-22): the counts in `ret` are GLOBAL — they include real cron jobs such as ops-detect-tick,
-- which in CI (live pg_cron, unlike the local shim) can fire and be swept between these two snapshots and move
-- `resolved`. So B4 compares the SHAPE (the key set, which is what it always claimed to check) and the scanned
-- floor, not the perturbable counts; B5/B6 below carry the content check, scoped to this fixture's own jobs.
SELECT ok((SELECT (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(new_c -> 'ret') k)
                = (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(old_c -> 'ret') k)
                  AND (new_c #>> '{ret,cron_run_details_available}')
                      IS NOT DISTINCT FROM (old_c #>> '{ret,cron_run_details_available}')
                  AND (new_c #>> '{ret,scanned}')::int >= (old_c #>> '{ret,scanned}')::int FROM t210_dj),
  'B4: detect_jobs returns the applied body''s shape and never scans fewer jobs (145 adds the not-running class)');
-- Nothing the applied body found is lost, and whatever 145 still calls "failing" keeps the applied body's exact text.
-- (Some jobs the applied body called failing are now reported as not running instead — that is 145's point, and 212
-- pins which is which.)
SELECT ok((SELECT (SELECT coalesce(array_agg(o ->> 'key' ORDER BY o ->> 'key'), '{}')
                     FROM jsonb_array_elements(old_c -> 'cases') o WHERE o ->> 'ref' LIKE 't210-%')
                  <@ (SELECT coalesce(array_agg(n ->> 'key' ORDER BY n ->> 'key'), '{}')
                        FROM jsonb_array_elements(new_c -> 'cases') n WHERE n ->> 'ref' LIKE 't210-%')
             FROM t210_dj)
      AND (SELECT coalesce(bool_and(n = o), true)
             FROM t210_dj, jsonb_array_elements(new_c -> 'cases') n
             JOIN LATERAL (SELECT o FROM t210_dj d2, jsonb_array_elements(d2.old_c -> 'cases') o
                            WHERE o ->> 'key' = n ->> 'key') j ON true
            WHERE n ->> 'ref' LIKE 't210-%' AND n ->> 'title' NOT LIKE '%is not running%'),
  'B5: every case the applied body opened is still opened, and each one 145 still calls failing has its exact text');
SELECT is((SELECT jsonb_agg(jsonb_set(x, '{payload}', (x -> 'payload') - 'not_running' - 'last_run') ORDER BY x ->> 'key')
             FROM t210_dj, jsonb_array_elements(new_c -> 'alerts') x
            WHERE (x ->> 'key') LIKE 'job_failure:t210-%'
              AND (x ->> 'key') IN (SELECT y ->> 'key' FROM t210_dj, jsonb_array_elements(old_c -> 'alerts') y)),
          (SELECT jsonb_agg(x ORDER BY x ->> 'key') FROM t210_dj, jsonb_array_elements(old_c -> 'alerts') x
            WHERE (x ->> 'key') LIKE 'job_failure:t210-%'),
  'B6: those jobs'' alerts are the applied body''s, with the same payloads (145 only adds not_running/last_run)');
-- B7 also guards the t210-% scoping added to B5/B6: jsonb_agg over an empty set is NULL, and is(NULL, NULL)
-- passes, so if that prefix ever stopped matching, B6 would go vacuously green. Assert the compared alert set is
-- non-empty here, where the plan already has an assertion for exactly this job.
SELECT ok((SELECT array_agg(x ->> 'ref') FROM t210_dj, jsonb_array_elements(new_c -> 'cases') x)
          @> array['t210-last2','t210-stale','t210-hung30','t210-e7in','t210-inv7','t210-rank5']
      AND (SELECT count(*) FROM t210_dj, jsonb_array_elements(old_c -> 'alerts') x
            WHERE (x ->> 'key') LIKE 'job_failure:t210-%') > 0,
  'B7 (witness): the comparison is not vacuous — the fixture''s failing jobs are flagged and their alerts are compared');

-- ── Section C — job_health against a brute-force oracle ──────────────────────────────────────────────────────
CREATE TEMP TABLE t210_items ON COMMIT DROP AS
  SELECT i ->> 'jobname' AS jobname, i FROM t210_jh, jsonb_array_elements(new_j -> 'cron_jobs' -> 'items') i;
SELECT is((SELECT i ->> 'last_status' FROM t210_items WHERE jobname = 't210-hung30'), 'running',
  'C1: a still-running run that started 30 h ago (below the floor) is the job''s newest run');
SELECT is((SELECT i ->> 'last_status' FROM t210_items WHERE jobname = 't210-hung8d'), 'running',
  'C2: a still-running run that started 8 days ago is found');
SELECT ok((SELECT i ->> 'last_status' = 'succeeded' AND (i ->> 'last_end')::timestamptz < now() - interval '19 days'
             FROM t210_items WHERE jobname = 't210-inactive'),
  'C3: an inactive job''s last run, 20 days old, is found');
SELECT ok((SELECT i -> 'last_status' = 'null'::jsonb AND (i ->> 'runs_24h')::int = 0 FROM t210_items WHERE jobname = 't210-never'),
  'C4: a job that never ran has no last run and no runs');
SELECT ok((SELECT (i ->> 'runs_24h')::int = 1 AND (i ->> 'failures_24h')::int = 1 FROM t210_items WHERE jobname = 't210-e24in'),
  'C5: a failure 1 µs inside the 24-hour edge counts');
SELECT ok((SELECT bool_and((i ->> 'runs_24h')::int = 0 AND (i ->> 'failures_24h')::int = 0)
             FROM t210_items WHERE jobname IN ('t210-e24eq', 't210-e24out')),
  'C6: a failure exactly at, or 1 µs outside, the 24-hour edge does not count');
SELECT is((SELECT (i ->> 'runs_24h')::int FROM t210_items WHERE jobname = 't210-inv24'), 1,
  'C7: a run allocated before, and started 1 s after, the 24-hour edge (inside the startup deadline) counts');
SELECT is(
  (SELECT jsonb_agg(jsonb_build_object('j', t.jobname, 'r', (t.i ->> 'runs_24h')::bigint, 'f', (t.i ->> 'failures_24h')::bigint) ORDER BY t.jobname)
     FROM t210_items t),
  (SELECT jsonb_agg(jsonb_build_object('j', j.jobname,
             'r', (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.start_time > now() - interval '24 hours'),
             'f', (SELECT count(*) FROM cron.job_run_details d WHERE d.jobid = j.jobid AND d.start_time > now() - interval '24 hours'
                                                               AND d.status = 'failed')) ORDER BY j.jobname)
     FROM cron.job j),
  'C8: every job''s counts equal a full read of the table (the definition)');
SELECT is(
  (SELECT jsonb_agg(jsonb_build_object('j', t.jobname, 's', t.i -> 'last_status', 'e', t.i -> 'last_end', 'm', t.i -> 'last_message') ORDER BY t.jobname)
     FROM t210_items t),
  (SELECT jsonb_agg(jsonb_build_object('j', j.jobname, 's', d.status, 'e', d.end_time, 'm', left(d.return_message, 300)) ORDER BY j.jobname)
     FROM cron.job j
     LEFT JOIN LATERAL (SELECT * FROM cron.job_run_details x WHERE x.jobid = j.jobid ORDER BY x.runid DESC LIMIT 1) d ON true),
  'C9: every job''s last run is its newest run (largest runid), by a full read of the table');
SELECT ok((SELECT o ->> 'last_status' = 'failed' AND o ->> 'last_message' = 'job startup timeout'
                  AND n ->> 'last_status' = 'succeeded'
             FROM t210_jh,
                  LATERAL (SELECT x FROM jsonb_array_elements(old_j -> 'cron_jobs' -> 'items') x WHERE x ->> 'jobname' = 't210-quirk') a(o),
                  LATERAL (SELECT x FROM jsonb_array_elements(new_j -> 'cron_jobs' -> 'items') x WHERE x ->> 'jobname' = 't210-quirk') b(n)),
  'C10: the correction, pinned — the applied body shows a 3-day-old startup timeout (start_time NULL sorts first) as the newest run; 143 shows the newest run');

-- ── Section D — detect_jobs edge outcomes ────────────────────────────────────────────────────────────────────
SELECT ok((SELECT coalesce(array_agg(x ->> 'ref'), '{}') FROM t210_dj, jsonb_array_elements(new_c -> 'cases') x) @> array['t210-e7in','t210-inv7']
      AND NOT (SELECT coalesce(array_agg(x ->> 'ref'), '{}') FROM t210_dj, jsonb_array_elements(new_c -> 'cases') x) && array['t210-e7eq','t210-e7out'],
  'D1: a failure 1 µs inside the 7-day edge, and one allocated before but started after it, are seen; at or outside the edge they are not');
SELECT ok((SELECT x ->> 'summary' LIKE '%: 3 of the last 5 runs failed;%'
             FROM t210_dj, jsonb_array_elements(new_c -> 'cases') x WHERE x ->> 'ref' = 't210-rank5'),
  'D2: failed_of_last5 counts exactly the 5 newest runs (failures at ranks 1, 2, 5 count; rank 6 does not)');
-- Amended 2026-09-19 (migration 145): this WAS the gap. Under 117/143 a job with no run in the last 7 days dropped
-- out of detection and its case was auto-resolved; 145 reports it as not running. pgTAP 212 W4-W6 demonstrate the old
-- behaviour with 143's own body, and W1-W3 the new one.
SELECT ok((SELECT coalesce(array_agg(x ->> 'ref'), '{}') FROM t210_dj, jsonb_array_elements(new_c -> 'cases') x) @> array['t210-hung8d']
      AND (SELECT x ->> 'title' LIKE '%is not running%' FROM t210_dj, jsonb_array_elements(new_c -> 'cases') x
            WHERE x ->> 'ref' = 't210-hung8d'),
  'D3: since 145, a job with no run started in the last 7 days IS a case, and it says the job is not running');

-- ── Section E — catalog unchanged ──────────────────────────────────────────────────────────────────────────
SELECT is((SELECT row(p.prosecdef, p.provolatile, p.proconfig::text,
                      pg_get_userbyid(p.proowner) = (SELECT pg_get_userbyid(q.proowner) FROM pg_proc q WHERE q.oid = 'ops.today()'::regprocedure))::text
             FROM pg_proc p WHERE p.oid = 'ops.job_health()'::regprocedure),
          row(true, 's', '{"search_path=\"\""}', true)::text,
  'E1: job_health stays SECURITY DEFINER, STABLE, search_path='''', owned like the rest of ops');
SELECT is((SELECT row(p.prosecdef, p.provolatile, p.proconfig::text,
                      pg_get_userbyid(p.proowner) = (SELECT pg_get_userbyid(q.proowner) FROM pg_proc q WHERE q.oid = 'ops.today()'::regprocedure))::text
             FROM pg_proc p WHERE p.oid = 'ops.detect_jobs()'::regprocedure),
          row(true, 'v', '{"search_path=\"\""}', true)::text,
  'E2: detect_jobs stays SECURITY DEFINER, VOLATILE, search_path='''', owned like the rest of ops');
SELECT ok(has_function_privilege('authenticated', 'ops.job_health()', 'EXECUTE')
          AND NOT has_function_privilege('anon', 'ops.job_health()', 'EXECUTE'),
  'E3: job_health grants unchanged — authenticated may execute, anon may not');
SELECT ok(NOT has_function_privilege('authenticated', 'ops.detect_jobs()', 'EXECUTE')
          AND NOT has_function_privilege('anon', 'ops.detect_jobs()', 'EXECUTE')
          AND NOT has_function_privilege('service_role', 'ops.detect_jobs()', 'EXECUTE'),
  'E4: detect_jobs grants unchanged — no client role may execute it');

SELECT * FROM finish();
ROLLBACK;
