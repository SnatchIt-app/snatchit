-- state.sql — read-only state for the 150/151 package. One text column, `key=value` rows.
-- Safe in every state (objects absent or present): every object reference is guarded by
-- to_regclass / to_regprocedure / catalog lookups, so the query never errors on absence.
-- Census queries are the gate ci.yml Gate-2 queries (lines 605-608), verbatim in substance.
with
fn as (
  select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig,
         md5(p.prosrc) as m, p.prosecdef as secdef, p.proconfig as cfg, p.oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname, p.proname) in (('public','record_payment_refund'), ('public','record_refund_state'),
                                    ('public','guard_payment_refund_state_columns'),
                                    ('public','payment_refund_state_log_append_only'),
                                    ('ops','detect_refunds'), ('ops','detect_release_stuck'))
),
rs as (select to_regprocedure('public.record_refund_state(text,text,text,integer,text,text,text)') as oid),
st as (select to_regclass('public.payment_refund_state') as t1, to_regclass('public.payment_refund_state_log') as t2),
cols as (
  select a.attname, a.attnotnull, pg_get_expr(d.adbin, d.adrelid) as def
    from pg_attribute a left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attrelid = 'public.payments'::regclass and not a.attisdropped
     and a.attname in ('refund_requested_cents','refund_succeeded_cents','refund_failed_cents')
)
select 'ledger_count=' || (select count(*) from supabase_migrations.schema_migrations)
union all select 'ledger_max=' || coalesce((select max(version) from supabase_migrations.schema_migrations), '-')
union all select 'ledger_150=' || coalesce((select coalesce(name,'') || '|' || coalesce(created_by,'') || '|' || coalesce(array_length(statements,1),0)
                                       from supabase_migrations.schema_migrations where version = '20260925000000'), 'absent')
union all select 'ledger_151=' || coalesce((select coalesce(name,'') || '|' || coalesce(created_by,'') || '|' || coalesce(array_length(statements,1),0)
                                       from supabase_migrations.schema_migrations where version = '20260925010000'), 'absent')
union all select 'census=' || (select count(*) from pg_tables where schemaname = 'public') || '|'
          || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public') || '|'
          || (select count(*) from pg_policies where schemaname = 'public') || '|'
          || (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and not t.tgisinternal)
union all select 'fn_' || sig || '=' || m || '|secdef=' || secdef || '|cfg=' || coalesce(array_to_string(cfg, ','), '-') from fn
union all select 'record_refund_state_exec=' || case when (select oid from rs) is null then 'absent' else
          'anon:' || has_function_privilege('anon', (select oid from rs), 'EXECUTE')
          || ',authenticated:' || has_function_privilege('authenticated', (select oid from rs), 'EXECUTE')
          || ',service_role:' || has_function_privilege('service_role', (select oid from rs), 'EXECUTE') end
union all select 'detect_release_stuck_exec=' || case when to_regprocedure('ops.detect_release_stuck()') is null then 'absent' else
          'anon:' || has_function_privilege('anon', 'ops.detect_release_stuck()', 'EXECUTE')
          || ',authenticated:' || has_function_privilege('authenticated', 'ops.detect_release_stuck()', 'EXECUTE')
          || ',service_role:' || has_function_privilege('service_role', 'ops.detect_release_stuck()', 'EXECUTE') end
union all select 'tbl_payment_refund_state=' || case when (select t1 from st) is null then 'absent' else
          'rls:' || (select relrowsecurity from pg_class where oid = (select t1 from st))
          || ',anon_any:' || (has_table_privilege('anon', (select t1 from st), 'SELECT') or has_table_privilege('anon', (select t1 from st), 'INSERT'))
          || ',authenticated_any:' || (has_table_privilege('authenticated', (select t1 from st), 'SELECT') or has_table_privilege('authenticated', (select t1 from st), 'INSERT'))
          || ',service_role_select:' || has_table_privilege('service_role', (select t1 from st), 'SELECT') end
union all select 'tbl_payment_refund_state_log=' || case when (select t2 from st) is null then 'absent' else
          'rls:' || (select relrowsecurity from pg_class where oid = (select t2 from st))
          || ',anon_any:' || (has_table_privilege('anon', (select t2 from st), 'SELECT') or has_table_privilege('anon', (select t2 from st), 'INSERT'))
          || ',authenticated_any:' || (has_table_privilege('authenticated', (select t2 from st), 'SELECT') or has_table_privilege('authenticated', (select t2 from st), 'INSERT'))
          || ',service_role_select:' || has_table_privilege('service_role', (select t2 from st), 'SELECT') end
union all select 'payments_refund_cols=' || coalesce((select string_agg(attname || ':' || attnotnull || ':' || coalesce(def, '-'), ',' order by attname) from cols), 'absent')
union all select 'payments_refund_cols_nonzero=' || case when (select count(*) from cols) = 0 then 'absent' else
          (select count(*) from public.payments where (to_jsonb(payments) ->> 'refund_requested_cents')::int <> 0
                                                     or (to_jsonb(payments) ->> 'refund_succeeded_cents')::int <> 0
                                                     or (to_jsonb(payments) ->> 'refund_failed_cents')::int <> 0)::text end
union all select 'triggers_150=' || coalesce((select string_agg(tgname, ',' order by tgname) from pg_trigger
                                       where not tgisinternal and tgname in ('trg_guard_payment_refund_state_columns','trg_payment_refund_state_log_append_only')), 'none')
union all select 'setting_refund_state_detection_enabled=' || coalesce((select value::text from ops.setting where key = 'refund_state_detection_enabled'), 'absent')
union all select 'setting_refund_state_pending_hours=' || coalesce((select value::text from ops.setting where key = 'refund_state_pending_hours'), 'absent')
union all select 'setting_detectors_enabled=' || coalesce((select value::text from ops.setting where key = 'detectors_enabled'), 'absent')
union all select 'ops_setting_rows=' || (select count(*) from ops.setting);
