-- Registry 213. Run only on an isolated test database: fixture changes roll back.
-- Exercise the actual detector, including its dynamic SQL and 5000-runid slices.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT plan(32);
-- Match 210: create the history shape only when pg_cron has not provided it.
DO $$ BEGIN
 IF to_regclass('cron.job_run_details') IS NULL THEN
  CREATE TABLE cron.job_run_details(jobid bigint,runid bigint primary key,job_pid integer,database text,username text,command text,status text,return_message text,start_time timestamptz,end_time timestamptz);
 END IF;
 -- Fixture runids precede real rows. A fresh test DB has only recent real runs,
 -- so all real started rows remain on the same side of both seven-day cutoffs.
 IF EXISTS(SELECT 1 FROM cron.job_run_details WHERE start_time <= now()-interval '7 days') THEN
  RAISE EXCEPTION '281 requires a fresh test database with no old real cron history';
 END IF;
END $$;
CREATE TEMP TABLE j281(name text primary key, jobid bigint);
INSERT INTO j281 SELECT n, cron.schedule('t281_' || n, '*/5 * * * *', 'select 1 /* t281 */')
 FROM unnest(ARRAY['inside','edge','margin','floor','below','mixed','never','disabled','slice','failing','fresh']) n;
DO $$ DECLARE v_id bigint := (SELECT jobid FROM j281 WHERE name='disabled'); BEGIN
 IF to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') IS NOT NULL THEN
  PERFORM cron.alter_job(v_id, active => false);
 ELSE
  UPDATE cron.job SET active=false WHERE jobid=v_id;
 END IF;
END $$;
-- Reachable even when seed_core or earlier tests removed the setting row.
INSERT INTO ops.setting(key, value)
 VALUES ('cron_job_first_seen', jsonb_build_object('t281_never', (now() - interval '2 days')::text))
 ON CONFLICT(key) DO UPDATE SET value = excluded.value;
CREATE TEMP TABLE f281(name text, age interval, status text);
INSERT INTO f281 VALUES
 ('margin', NULL,'failed'),
 ('failing', interval '3 minutes','failed'),
 ('failing', interval '1 minute','failed'),
 ('inside', interval '7 days' - interval '1 microsecond','succeeded'),
 ('edge', interval '7 days','failed'),
 ('margin', interval '7 days 30 minutes','failed'),
 ('floor', interval '7 days 1 hour','succeeded'),
 ('below', interval '8 days','succeeded'),
 ('mixed', interval '7 days 30 minutes','failed'),
 ('mixed', interval '7 days','failed'),
 ('mixed', interval '4 minutes','succeeded'),
 ('mixed', interval '2 minutes','succeeded'),
 ('disabled', interval '7 days 30 minutes','failed'),
 ('slice', interval '7 days 59 minutes','failed');
-- Force multiple slices, with chronological runids and one job spanning slices.
INSERT INTO f281 SELECT 'slice', interval '7 days 50 minutes' - make_interval(secs => g::double precision / 10), 'succeeded'
 FROM generate_series(1,5001) g;
INSERT INTO cron.job_run_details(jobid,runid,job_pid,database,username,command,status,return_message,start_time,end_time)
 SELECT j.jobid, row_number() over(order by f.age desc, f.name)
 + coalesce((SELECT min(runid) FROM cron.job_run_details),1) - (SELECT count(*) FROM f281) - 1,
 0, current_database(), current_user,
 'select 1 /* t281 */', f.status, CASE WHEN f.status='failed' THEN 't281 old failure' END,
 now()-f.age, now()-f.age+interval '1 microsecond'
 FROM f281 f JOIN j281 j USING(name);
SELECT ops.detect_jobs();
SELECT is((SELECT count(*)::int FROM pg_temp.dj145 WHERE jobname LIKE 't281_%'),10,'all ten active fixtures judged');
SELECT is((SELECT last_run FROM pg_temp.dj145 WHERE jobname='t281_inside'),now()-interval '7 days'+interval '1 microsecond','inside seven days retained');
SELECT is((SELECT runs_7d FROM pg_temp.dj145 WHERE jobname='t281_inside'),1::bigint,'inside seven days counted');
SELECT is((SELECT last_run FROM pg_temp.dj145 WHERE jobname='t281_edge'),now()-interval '7 days','exact seven-day run retained');
SELECT is((SELECT runs_7d FROM pg_temp.dj145 WHERE jobname='t281_edge'),0::bigint,'exact seven-day run excluded from count');
SELECT is((SELECT last_run FROM pg_temp.dj145 WHERE jobname='t281_margin'),now()-interval '7 days 30 minutes','margin run retained');
SELECT is((SELECT runs_7d FROM pg_temp.dj145 WHERE jobname='t281_margin'),0::bigint,'margin run excluded from count');
SELECT is((SELECT last_success FROM pg_temp.dj145 WHERE jobname='t281_floor'),NULL::timestamptz,'old success excluded from failure metric');
SELECT is((SELECT last_run FROM pg_temp.dj145 WHERE jobname='t281_floor'),now()-interval '7 days 1 hour','exact floor found by lower walk');
SELECT is((SELECT last_run FROM pg_temp.dj145 WHERE jobname='t281_below'),now()-interval '8 days','older history found by lower walk');
SELECT is((SELECT last_run FROM pg_temp.dj145 WHERE jobname='t281_slice'),(SELECT max(now()-age) FROM f281 WHERE name='slice'),'last_run across slices matches full-read oracle');
SELECT is((SELECT runs_7d FROM pg_temp.dj145 WHERE jobname='t281_slice'),0::bigint,'multiple margin slices count zero');
SELECT is((SELECT failed_of_last5 FROM pg_temp.dj145 WHERE jobname='t281_slice'),0::bigint,'multiple margin slices contribute no last5 failures');
SELECT is((SELECT runs_7d FROM pg_temp.dj145 WHERE jobname='t281_mixed'),2::bigint,'mixed history counts current runs only');
SELECT is((SELECT failed_of_last5 FROM pg_temp.dj145 WHERE jobname='t281_mixed'),0::bigint,'old failures excluded from last5');
SELECT is((SELECT last2_failed FROM pg_temp.dj145 WHERE jobname='t281_mixed'),false,'current successes determine last2');
SELECT is((SELECT last_error FROM pg_temp.dj145 WHERE jobname='t281_mixed'),NULL::text,'old failure message excluded');
SELECT is((SELECT last_success FROM pg_temp.dj145 WHERE jobname='t281_mixed'),now()-interval '2 minutes','current success unchanged');
SELECT is((SELECT title FROM ops."case" WHERE subject_ref='t281_margin' ORDER BY created_at DESC LIMIT 1),'Cron job t281_margin is not running','margin job opens stalled case immediately');
SELECT is((SELECT title FROM ops."case" WHERE subject_ref='t281_never' ORDER BY created_at DESC LIMIT 1),'Cron job t281_never is not running','upserted first-seen fixture opens never-run case');
SELECT ok(NOT EXISTS(SELECT 1 FROM ops."case" WHERE subject_ref='t281_disabled'),'inactive job ignored');
SELECT ok(NOT EXISTS(SELECT 1 FROM ops."case" WHERE subject_ref='t281_mixed'),'healthy mixed-history job ignored');
SELECT is((SELECT last2_failed FROM pg_temp.dj145 WHERE jobname='t281_margin'),NULL::boolean,'margin and null-start failures do not enter last2');
SELECT is((SELECT last_error FROM pg_temp.dj145 WHERE jobname='t281_margin'),NULL::text,'margin and null-start error messages excluded');
SELECT is((SELECT runs_7d FROM pg_temp.dj145 WHERE jobname='t281_failing'),2::bigint,'current failed runs counted');
SELECT is((SELECT last2_failed FROM pg_temp.dj145 WHERE jobname='t281_failing'),true,'current consecutive failures preserved');
SELECT is((SELECT failed_of_last5 FROM pg_temp.dj145 WHERE jobname='t281_failing'),2::bigint,'current last5 failures preserved');
SELECT is((SELECT title FROM ops."case" WHERE subject_ref='t281_failing' ORDER BY created_at DESC LIMIT 1),'Cron job t281_failing failing','running failed job retains failure wording');
SELECT ok(NOT EXISTS(SELECT 1 FROM ops."case" WHERE subject_ref='t281_fresh'),'fresh never-run job keeps grace');
SELECT is((SELECT last_success FROM pg_temp.dj145 WHERE jobname='t281_slice'),NULL::timestamptz,'margin successes excluded from last_success');
-- A repeated call neither loses the observed run nor creates another case.
SELECT ops.detect_jobs();
SELECT is((SELECT count(*)::int FROM ops."case" WHERE subject_ref='t281_margin'),1,'idempotent detection');
INSERT INTO cron.job_run_details(jobid,runid,status,start_time,end_time)
 SELECT jobid, (SELECT max(runid)+1 FROM cron.job_run_details), 'succeeded', now()-interval '1 minute', now()
 FROM j281 WHERE name='margin';
SELECT ops.detect_jobs();
SELECT is((SELECT status FROM ops."case" WHERE subject_ref='t281_margin' ORDER BY created_at DESC LIMIT 1),'resolved','new successful run recovers stalled case');
SELECT * FROM finish();
ROLLBACK;
