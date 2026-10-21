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
  -- Out-of-scope surfaces the venue phases must never write (native tickets, checkout/payments, door/scan,
  -- resale). postflight requires every one of these counts to equal the baseline.
  'collateral', json_build_object(
    'kernel_tickets', (case when to_regclass('kernel.tickets') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.tickets$q$, false, true, '')))[1]::text::int end),
    'kernel_ticket_ownership_log', (case when to_regclass('kernel.ticket_ownership_log') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.ticket_ownership_log$q$, false, true, '')))[1]::text::int end),
    'kernel_wallet_pass', (case when to_regclass('kernel.wallet_pass') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.wallet_pass$q$, false, true, '')))[1]::text::int end),
    'kernel_payment_native', (case when to_regclass('kernel.payment_native') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.payment_native$q$, false, true, '')))[1]::text::int end),
    'kernel_refund', (case when to_regclass('kernel.refund') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.refund$q$, false, true, '')))[1]::text::int end),
    'kernel_payout', (case when to_regclass('kernel.payout') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.payout$q$, false, true, '')))[1]::text::int end),
    'kernel_org_invite', (case when to_regclass('kernel.org_invite') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.org_invite$q$, false, true, '')))[1]::text::int end),
    'kernel_admin_audit', (case when to_regclass('kernel.admin_audit') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from kernel.admin_audit$q$, false, true, '')))[1]::text::int end),
    'venue_order', (case when to_regclass('venue."order"') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue."order"$q$, false, true, '')))[1]::text::int end),
    'venue_order_item', (case when to_regclass('venue.order_item') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.order_item$q$, false, true, '')))[1]::text::int end),
    'venue_inventory_hold', (case when to_regclass('venue.inventory_hold') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.inventory_hold$q$, false, true, '')))[1]::text::int end),
    'venue_inventory_movement', (case when to_regclass('venue.inventory_movement') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.inventory_movement$q$, false, true, '')))[1]::text::int end),
    'venue_door_manifest', (case when to_regclass('venue.door_manifest') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.door_manifest$q$, false, true, '')))[1]::text::int end),
    'venue_door_session', (case when to_regclass('venue.door_session') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.door_session$q$, false, true, '')))[1]::text::int end),
    'venue_scan', (case when to_regclass('venue.scan') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.scan$q$, false, true, '')))[1]::text::int end),
    'venue_scan_device', (case when to_regclass('venue.scan_device') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from venue.scan_device$q$, false, true, '')))[1]::text::int end),
    'catalog_resale_policy', (case when to_regclass('catalog.resale_policy') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from catalog.resale_policy$q$, false, true, '')))[1]::text::int end),
    'public_listings', (case when to_regclass('public.listings') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.listings$q$, false, true, '')))[1]::text::int end),
    'public_payments', (case when to_regclass('public.payments') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.payments$q$, false, true, '')))[1]::text::int end),
    'public_transfers', (case when to_regclass('public.transfers') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.transfers$q$, false, true, '')))[1]::text::int end),
    'public_bids', (case when to_regclass('public.bids') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.bids$q$, false, true, '')))[1]::text::int end),
    'public_payment_refunds', (case when to_regclass('public.payment_refunds') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.payment_refunds$q$, false, true, '')))[1]::text::int end),
    'public_payout_attempts', (case when to_regclass('public.payout_attempts') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.payout_attempts$q$, false, true, '')))[1]::text::int end),
    'public_profiles', (case when to_regclass('public.profiles') is null then null else (xpath('/row/v/text()', query_to_xml($q$select count(*) as v from public.profiles$q$, false, true, '')))[1]::text::int end)
  ),
  'platform_config_digest', (select md5(coalesce(string_agg(key || '=' || value::text, ';' order by key), '')) from catalog.platform_config),
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
