-- READ-ONLY preflight / baseline for venue slice-1 acceptance. One SELECT returning one json column `j`.
-- Safe at any time on any target; writes nothing. Ledger fields are null on a local replay (no
-- supabase_migrations schema there); they are evaluated dynamically so the file still parses.
select json_build_object(
  'captured_at', now(),
  'database', current_database(),
  'server_version', current_setting('server_version'),
  'ledger_count', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from supabase_migrations.schema_migrations$q$, false, true, '')))[1]::text::int end),
  'ledger_tip_timestamp', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select max(version) as v from supabase_migrations.schema_migrations where version ~ '^[0-9]{14}$'$q$, false, true, '')))[1]::text end),
  'ledger_dupes', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from (select version from supabase_migrations.schema_migrations group by 1 having count(*) > 1) d$q$, false, true, '')))[1]::text::int end),
  'ledger_076_092', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from supabase_migrations.schema_migrations where version between '076' and '092'$q$, false, true, '')))[1]::text::int end),
  'ledger_has_venue_api', (case when to_regclass('supabase_migrations.schema_migrations') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from supabase_migrations.schema_migrations where version = '20260910120000'$q$, false, true, '')))[1]::text::int end),
  'schemas_present', (select coalesce(json_agg(nspname order by nspname), '[]'::json) from pg_namespace where nspname in ('catalog','venue','kernel','ops','venue_api')),
  'venue_api_views', (select count(*) from pg_views where schemaname = 'venue_api'),
  'authenticator_pgrst', (select coalesce(json_agg(s order by s), '[]'::json) from (select unnest(setconfig) s from pg_db_role_setting r join pg_roles o on o.oid = r.setrole where o.rolname = 'authenticator') x where s like 'pgrst.%'),
  'pgcrypto', exists (select 1 from pg_extension where extname = 'pgcrypto'),
  'counts', json_build_object(
    'organizations', (select count(*) from kernel.organization),
    'venues', (select count(*) from catalog.venue),
    'events', (select count(*) from catalog.event),
    'sessions', (select count(*) from catalog.event_session),
    'ticket_types', (select count(*) from venue.ticket_type),
    'batches', (select count(*) from venue.inventory_batch),
    'staff_roles', (select count(*) from venue.staff_role),
    'org_members', (select count(*) from kernel.org_member),
    'auth_users', (select count(*) from auth.users)
  ),
  'fixture_id_collisions',
      (select count(*) from kernel.organization where org_id::text like '5a4d0b0e-%')
    + (select count(*) from catalog.venue where venue_id::text like '5a4d0b0e-%')
    + (select count(*) from catalog.event where event_id::text like '5a4d0b0e-%')
    + (select count(*) from catalog.event_session where session_id::text like '5a4d0b0e-%')
    + (select count(*) from venue.ticket_type where ticket_type_id::text like '5a4d0b0e-%')
    + (select count(*) from venue.inventory_batch where batch_id::text like '5a4d0b0e-%'),
  'acceptance_users', (select count(*) from auth.users where email like 'acceptance.venue-%@example.com'),
  'feature_flags', (select coalesce(json_agg(json_build_object('k', key, 'v', value) order by key), '[]'::json) from catalog.platform_config where key like 'feature.%')
) as j;
