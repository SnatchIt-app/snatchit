-- READ-ONLY: the venue_api migration is present and shaped as reviewed. One json column `j`.
select json_build_object(
  'views', (select count(*) from pg_views where schemaname = 'venue_api'),
  'view_names', (select coalesce(json_agg(viewname order by viewname), '[]'::json) from pg_views where schemaname = 'venue_api'),
  'not_security_invoker', (select coalesce(json_agg(c.relname), '[]'::json) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'venue_api' and c.relkind = 'v'
        and not exists (select 1 from unnest(c.reloptions) o where o = 'security_invoker=true')),
  'not_security_barrier', (select coalesce(json_agg(c.relname), '[]'::json) from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'venue_api' and c.relkind = 'v'
        and not exists (select 1 from unnest(c.reloptions) o where o = 'security_barrier=true')),
  'anon_usage', has_schema_privilege('anon', 'venue_api', 'USAGE'),
  'authenticated_usage', has_schema_privilege('authenticated', 'venue_api', 'USAGE'),
  'authenticated_select_grants', (select count(*) from information_schema.role_table_grants
      where table_schema = 'venue_api' and grantee = 'authenticated' and privilege_type = 'SELECT'),
  'non_select_grants_to_clients', (select count(*) from information_schema.role_table_grants
      where table_schema = 'venue_api' and grantee in ('anon', 'authenticated', 'PUBLIC') and privilege_type <> 'SELECT'),
  'anon_or_public_grants', (select count(*) from information_schema.role_table_grants
      where table_schema = 'venue_api' and grantee in ('anon', 'PUBLIC')),
  'definer_functions_in_schema', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'venue_api' and p.prosecdef),
  'ledger_row_name', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select name as v from supabase_migrations.schema_migrations where version = '20260910120000'$q$, false, true, '')))[1]::text end),
  'ledger_row_statements', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select array_length(statements, 1) as v from supabase_migrations.schema_migrations where version = '20260910120000'$q$, false, true, '')))[1]::text::int end)
) as j;
