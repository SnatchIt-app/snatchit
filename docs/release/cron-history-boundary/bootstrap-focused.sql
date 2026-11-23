-- Private focused proof only. Dependency doubles are explicit: this is not a
-- Supabase migration-chain replay or end-to-end case/alert authorization test.
CREATE EXTENSION pgtap;
CREATE SCHEMA ops;
CREATE SCHEMA cron;
CREATE TABLE cron.job(jobid bigserial primary key,jobname text unique,schedule text,command text,active boolean default true);
CREATE TABLE cron.job_run_details(jobid bigint,runid bigint primary key,job_pid integer,database text,username text,command text,status text,return_message text,start_time timestamptz,end_time timestamptz);
CREATE FUNCTION cron.schedule(text,text,text) RETURNS bigint LANGUAGE sql AS $$ INSERT INTO cron.job(jobname,schedule,command) VALUES($1,$2,$3) RETURNING jobid $$;
CREATE TABLE ops.setting(key text primary key,value jsonb,updated_at timestamptz default now());
CREATE TABLE ops.job_state(job_name text,consecutive_failures integer,last_error text,last_success_at timestamptz,backoff_until timestamptz);
CREATE TABLE ops."case"(id uuid default gen_random_uuid(),subject_ref text unique,title text,summary text,status text default 'open',version integer default 0,created_at timestamptz default now());
CREATE FUNCTION ops.detect_case(text,text,uuid,text,text,text,text,timestamptz,text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE cid uuid; opened boolean;
BEGIN
 SELECT id INTO cid FROM ops."case" WHERE subject_ref=$4;
 opened := cid IS NULL;
 INSERT INTO ops."case"(subject_ref,title,summary) VALUES($4,$5,$6) ON CONFLICT(subject_ref) DO UPDATE SET summary=excluded.summary,status='open' RETURNING id INTO cid;
 RETURN jsonb_build_object('dedupe_key',$4,'case_id',cid,'opened',opened);
END $$;
CREATE FUNCTION ops.alert_fire(text,text,jsonb) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION ops.alert_recover_stale(text,text[]) RETURNS void LANGUAGE sql AS $$ SELECT $$;
CREATE FUNCTION ops.detect_sweep(text,text[]) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer; BEGIN UPDATE ops."case" SET status='resolved' WHERE NOT(subject_ref=ANY($2)) AND status='open'; GET DIAGNOSTICS n=ROW_COUNT; RETURN n; END $$;
create or replace function ops.cron_interval_minutes(p_schedule text)
returns integer language sql immutable
as $ops$
  select case when p_schedule ~ '^\*/[0-9]+ \* \* \* \*$'
              then substring(p_schedule from '^\*/([0-9]+)')::integer
              else 25 * 60 end;
$ops$;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role; END IF;
END $$;
