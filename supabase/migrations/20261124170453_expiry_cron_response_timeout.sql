-- Registry215: only the existing expiry cron HTTP observation budget changes.
-- Live Nov24: three5s net timeouts while the same workers completed normally
-- after8–13s. Match the primary-lapse job's bounded20s observation budget.
-- Preserve job identity, cadence, active state, database, role, URL, headers,
-- body and vault lookups. No request is executed by this migration.
-- Pinned CLI2.115.0 batches this first statement, the DO block and its
-- migration-ledger INSERT in one transaction. A concurrent cron-row update
-- must abort this snapshot instead of overwriting a newer command.
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
DO $expiry215$
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
$expiry215$;
