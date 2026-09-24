select 'stmt_md5' k, (select md5(statements[1]) from supabase_migrations.schema_migrations where version='20260924120000') v
union all select 'claim148_prosrc_md5', (select md5(prosrc) from pg_proc where oid='public.claim_payout_attempt(uuid,text,interval)'::regprocedure)
union all select 'notify148_prosrc_md5', (select md5(prosrc) from pg_proc where oid='public.notify_transfer_state_inbox()'::regprocedure)
