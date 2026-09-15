-- D independent READ-ONLY read-back of the shared sandbox after A's stopped marketplace phase. No writes.
select jsonb_build_object(
  'ledger_rows', (select count(*) from supabase_migrations.schema_migrations),
  'ledger_max', (select max(version) from supabase_migrations.schema_migrations),
  'versions_110_130', (select coalesce(jsonb_agg(version order by version), '[]') from supabase_migrations.schema_migrations where version ~ '^[0-9]{3}$' and version >= '110' and version <= '132'),
  'versions_timestamped_2026_09', (select coalesce(jsonb_agg(version order by version), '[]') from supabase_migrations.schema_migrations where version like '202609%'),
  'schemas', (select jsonb_agg(nspname order by nspname) from pg_namespace where nspname in ('ops','kernel','venue','venue_api','notify','catalog')),
  'fn_refund_facts', to_regprocedure('ops.refund_facts(timestamptz,timestamptz)') is not null,
  'fn_release_reservation_for_payment', exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='release_reservation_for_payment'),
  'fn_public_register_push_token', exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='register_push_token'),
  'fn_public_revoke_push_token', exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='revoke_push_token'),
  'fn_claim_checkout_supersede', exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='claim_checkout_supersede'),
  'tbl_push_token_rebind_epoch', to_regclass('public.push_token_rebind_epoch') is not null,
  'bids_bidder_fk', (select pg_get_constraintdef(oid) from pg_constraint where conname='bids_bidder_id_fkey'),
  'sync_scan_md5', (select left(md5(pg_get_functiondef(p.oid)),8) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue' and p.proname='sync_scan_device_manifest' limit 1),
  'counts', jsonb_build_object('listings',(select count(*) from public.listings),'payments',(select count(*) from public.payments),'transfers',(select count(*) from public.transfers),'bids',(select count(*) from public.bids),
            'listings_reserved',(select count(*) from public.listings where status='reserved'),'payments_pending',(select count(*) from public.payments where status='pending'),'push_tokens',(select count(*) from public.push_tokens)),
  'kernel_tickets', (select case when to_regclass('kernel.tickets') is null then null else (select count(*) from kernel.tickets) end),
  'kernel_signing_key', (select case when to_regclass('kernel.signing_key') is null then null else (select count(*) from kernel.signing_key) end),
  'db_pre_request', (select setting from pg_settings where name='pgrst.db_pre_request'),
  'authenticator_config', (select array_to_string(rolconfig, ' | ') from pg_roles where rolname='authenticator')
) as readback;
