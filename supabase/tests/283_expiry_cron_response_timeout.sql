-- Registry215. Isolated CI database only; every fixture change rolls back.
-- apply215/rollback215 contain the actual migration blocks, byte-for-byte.
-- scripts/verify-expiry-cron-timeout.py rejects any divergence of these copies.
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT plan(31);
CREATE TEMP TABLE baseline283 AS SELECT * FROM cron.job WHERE jobname='enforce-transfer-expiry';
CREATE FUNCTION pg_temp.cron_state283() RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT jsonb_agg(jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,
 'database',database,'username',username,'active',active,'command_md5',md5(command)) ORDER BY jobid) FROM cron.job
$fn$;
CREATE FUNCTION pg_temp.switch_state283() RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT jsonb_build_object('catalog',(SELECT jsonb_agg(to_jsonb(c) ORDER BY key,version) FROM catalog.platform_config c),
 'ops',(SELECT jsonb_agg(to_jsonb(s) ORDER BY key) FROM ops.setting s))
$fn$;
CREATE TEMP TABLE all_before283 AS SELECT pg_temp.cron_state283() AS jobs,pg_temp.switch_state283() AS switches;
CREATE FUNCTION pg_temp.apply215() RETURNS void LANGUAGE plpgsql AS $apply215$
DECLARE
 v_job record;
 v_count integer;
 v_command text;
BEGIN
 IF current_setting('transaction_isolation') IS DISTINCT FROM 'serializable' THEN
  RAISE EXCEPTION 'EXPIRY_215_SERIALIZABLE_REQUIRED';
 END IF;
 SELECT count(*) INTO v_count FROM cron.job WHERE jobname='enforce-transfer-expiry';
 IF v_count<>1 THEN
  RAISE EXCEPTION 'EXPIRY_215_EXPECTED_ONE_JOB';
 END IF;
 SELECT * INTO STRICT v_job FROM cron.job
  WHERE jobname='enforce-transfer-expiry';
 IF v_job.schedule IS DISTINCT FROM '*/2 * * * *'
 OR v_job.database IS DISTINCT FROM 'postgres'
 OR v_job.username IS DISTINCT FROM 'postgres' THEN
  RAISE EXCEPTION 'EXPIRY_215_JOB_SHAPE_CHANGED';
 END IF;
 IF md5(v_job.command)='95e15a08418aeedb7876cb0a95f6560c' THEN
  RETURN; -- Exact target already installed; do not upsert/reschedule a job.
 END IF;
 IF md5(v_job.command) IS DISTINCT FROM 'd8fd165ade2345bafb4e26a44f2bbdc8' THEN
  RAISE EXCEPTION 'EXPIRY_215_COMMAND_CHANGED';
 END IF;
 v_command:=replace(v_job.command,$before215$    body    := '{}'::jsonb
  )$before215$,$after215$    body    := '{}'::jsonb,
    timeout_milliseconds := 20000
  )$after215$);
 IF md5(v_command) IS DISTINCT FROM '95e15a08418aeedb7876cb0a95f6560c' THEN
  RAISE EXCEPTION 'EXPIRY_215_REPLACEMENT_MISMATCH';
 END IF;
 PERFORM cron.alter_job(job_id:=v_job.jobid,command:=v_command);
 IF (SELECT count(*) FROM cron.job WHERE jobname='enforce-transfer-expiry')<>1
 OR NOT EXISTS(SELECT FROM cron.job WHERE jobid=v_job.jobid
  AND jobname=v_job.jobname AND md5(command)='95e15a08418aeedb7876cb0a95f6560c'
  AND schedule IS NOT DISTINCT FROM v_job.schedule
  AND database IS NOT DISTINCT FROM v_job.database
  AND username IS NOT DISTINCT FROM v_job.username
  AND active IS NOT DISTINCT FROM v_job.active) THEN
  RAISE EXCEPTION 'EXPIRY_215_POSTCONDITION_FAILED';
 END IF;
END;
$apply215$;
CREATE FUNCTION pg_temp.rollback215() RETURNS void LANGUAGE plpgsql AS $rollback215$
DECLARE
 v_job record;
 v_count integer;
 v_command text;
BEGIN
 IF current_setting('transaction_isolation') IS DISTINCT FROM 'serializable' THEN
  RAISE EXCEPTION 'EXPIRY_215_SERIALIZABLE_REQUIRED';
 END IF;
 SELECT count(*) INTO v_count FROM cron.job WHERE jobname='enforce-transfer-expiry';
 IF v_count<>1 THEN
  RAISE EXCEPTION 'EXPIRY_215_EXPECTED_ONE_JOB';
 END IF;
 SELECT * INTO STRICT v_job FROM cron.job
  WHERE jobname='enforce-transfer-expiry';
 IF v_job.schedule IS DISTINCT FROM '*/2 * * * *'
 OR v_job.database IS DISTINCT FROM 'postgres'
 OR v_job.username IS DISTINCT FROM 'postgres' THEN
  RAISE EXCEPTION 'EXPIRY_215_JOB_SHAPE_CHANGED';
 END IF;
 IF md5(v_job.command)='d8fd165ade2345bafb4e26a44f2bbdc8' THEN
  RETURN; -- Exact target already installed; do not upsert/reschedule a job.
 END IF;
 IF md5(v_job.command) IS DISTINCT FROM '95e15a08418aeedb7876cb0a95f6560c' THEN
  RAISE EXCEPTION 'EXPIRY_215_COMMAND_CHANGED';
 END IF;
 v_command:=replace(v_job.command,$before215$    body    := '{}'::jsonb,
    timeout_milliseconds := 20000
  )$before215$,$after215$    body    := '{}'::jsonb
  )$after215$);
 IF md5(v_command) IS DISTINCT FROM 'd8fd165ade2345bafb4e26a44f2bbdc8' THEN
  RAISE EXCEPTION 'EXPIRY_215_REPLACEMENT_MISMATCH';
 END IF;
 PERFORM cron.alter_job(job_id:=v_job.jobid,command:=v_command);
 IF (SELECT count(*) FROM cron.job WHERE jobname='enforce-transfer-expiry')<>1
 OR NOT EXISTS(SELECT FROM cron.job WHERE jobid=v_job.jobid
  AND jobname=v_job.jobname AND md5(command)='d8fd165ade2345bafb4e26a44f2bbdc8'
  AND schedule IS NOT DISTINCT FROM v_job.schedule
  AND database IS NOT DISTINCT FROM v_job.database
  AND username IS NOT DISTINCT FROM v_job.username
  AND active IS NOT DISTINCT FROM v_job.active) THEN
  RAISE EXCEPTION 'EXPIRY_215_POSTCONDITION_FAILED';
 END IF;
END;
$rollback215$;
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname='enforce-transfer-expiry'),1,'one existing targeted job');
SELECT is((SELECT md5(command) FROM baseline283),'95e15a08418aeedb7876cb0a95f6560c','installed exact20000ms command');
SELECT matches((SELECT command FROM baseline283),'timeout_milliseconds := 20000','explicit bounded timeout installed');
SELECT has_function('cron','alter_job',ARRAY['bigint','text','text','text','text','boolean'],'real cron alter interface exists');
SELECT lives_ok('SELECT pg_temp.apply215()','exact-target forward rerun is a no-op');
SELECT is(pg_temp.cron_state283(),(SELECT jobs FROM all_before283),'idempotency leaves every job identical');
SELECT is(pg_temp.switch_state283(),(SELECT switches FROM all_before283),'all switches unchanged');
DO $$ BEGIN PERFORM pg_temp.rollback215(); END $$;
SELECT is((SELECT md5(command) FROM cron.job WHERE jobname='enforce-transfer-expiry'),'d8fd165ade2345bafb4e26a44f2bbdc8','old5s behavior is the concrete negative control');
DO $$ BEGIN PERFORM cron.alter_job(job_id:=(SELECT jobid FROM baseline283),active:=false); END $$;
SELECT lives_ok('SELECT pg_temp.apply215()','actual old command receives only the timeout correction');
SELECT is((SELECT md5(command) FROM cron.job WHERE jobname='enforce-transfer-expiry'),'95e15a08418aeedb7876cb0a95f6560c','old→fixed exact command');
SELECT is((SELECT jobid FROM cron.job WHERE jobname='enforce-transfer-expiry'),(SELECT jobid FROM baseline283),'job id preserved; no new schedule');
SELECT is((SELECT schedule FROM cron.job WHERE jobname='enforce-transfer-expiry'),'*/2 * * * *','cadence preserved');
SELECT is((SELECT active FROM cron.job WHERE jobname='enforce-transfer-expiry'),false,'disabled job remains disabled');
SELECT is((SELECT database||'/'||username FROM cron.job WHERE jobname='enforce-transfer-expiry'),'postgres/postgres','database and execution role preserved');
SELECT is((SELECT count(*)::int FROM cron.job),(SELECT jsonb_array_length(jobs) FROM all_before283),'no duplicate job created');
SELECT lives_ok('SELECT pg_temp.rollback215()','rollback restores original command');
SELECT is((SELECT md5(command) FROM cron.job WHERE jobname='enforce-transfer-expiry'),'d8fd165ade2345bafb4e26a44f2bbdc8','rollback exactly restores original bytes');
SELECT lives_ok('SELECT pg_temp.rollback215()','rollback is idempotent');
DO $$ BEGIN
 PERFORM cron.alter_job(job_id:=(SELECT jobid FROM baseline283),command:=(SELECT command FROM cron.job WHERE jobname='enforce-transfer-expiry')||E'\n-- deliberate drift');
END $$;
SELECT throws_ok('SELECT pg_temp.apply215()','P0001','EXPIRY_215_COMMAND_CHANGED','unknown command fails closed');
SELECT matches((SELECT command FROM cron.job WHERE jobname='enforce-transfer-expiry'),'deliberate drift','refusal leaves drift untouched');
DO $$ BEGIN
 PERFORM cron.alter_job(job_id:=(SELECT jobid FROM baseline283),command:=(SELECT command FROM baseline283),schedule:='*/3 * * * *');
END $$;
SELECT throws_ok('SELECT pg_temp.apply215()','P0001','EXPIRY_215_JOB_SHAPE_CHANGED','changed cadence fails closed even on installed command');
SELECT is((SELECT schedule FROM cron.job WHERE jobname='enforce-transfer-expiry'),'*/3 * * * *','refusal preserves changed cadence');
DO $$ BEGIN PERFORM cron.alter_job(job_id:=(SELECT jobid FROM baseline283),schedule:='*/2 * * * *'); END $$;
SAVEPOINT missing283;
SELECT cron.unschedule((SELECT jobid FROM baseline283));
SELECT throws_ok('SELECT pg_temp.apply215()','P0001','EXPIRY_215_EXPECTED_ONE_JOB','missing target fails closed');
ROLLBACK TO missing283;
-- The supported API enforces one job per owner/name; an impossible duplicate
-- made by privileged INSERT would hide the production caller's real boundary.
SELECT is(cron.schedule('enforce-transfer-expiry','*/2 * * * *',(SELECT command FROM baseline283)),(SELECT jobid FROM baseline283),'same-owner name reuses the existing job rather than creating a duplicate');
SELECT is((SELECT count(*)::int FROM cron.job WHERE jobname='enforce-transfer-expiry'),1,'supported API preserves one target');
DO $$ BEGIN
 PERFORM cron.alter_job(job_id:=(SELECT jobid FROM baseline283),command:=(SELECT command FROM baseline283),active:=(SELECT active FROM baseline283));
END $$;
SELECT is(pg_temp.cron_state283(),(SELECT jobs FROM all_before283),'other jobs and every target property restored');
SELECT is(pg_temp.switch_state283(),(SELECT switches FROM all_before283),'negative cases never change any operating switch');
SELECT throws_ok('SELECT cron.alter_job(job_id:=(SELECT jobid FROM baseline283),username:=''service_role'')','XX000','must be superuser to alter username','supported API refuses unauthorized execution-role changes');
SELECT throws_ok('DO $x$ BEGIN PERFORM cron.alter_job(job_id:=(SELECT jobid FROM baseline283),database:=''template1''); PERFORM pg_temp.apply215(); END; $x$','P0001','EXPIRY_215_JOB_SHAPE_CHANGED','changed database refused');
SELECT is(pg_temp.cron_state283(),(SELECT jobs FROM all_before283),'failed subtransactions leave all jobs identical');
SELECT is(pg_temp.switch_state283(),(SELECT switches FROM all_before283),'final operating state unchanged');
SELECT * FROM finish();
ROLLBACK;
