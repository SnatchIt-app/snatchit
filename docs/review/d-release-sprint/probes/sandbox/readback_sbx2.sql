-- D independent READ-ONLY witness read-back of the shared sandbox after A's SBX-2 (127→130, path (b)). No writes.
select jsonb_build_object(
  'is_sandbox_guard', (select count(*) from supabase_migrations.schema_migrations) between 130 and 140
                      and to_regnamespace('ops') is null,
  'ledger_rows', (select count(*) from supabase_migrations.schema_migrations),
  'ledger_max', (select max(version) from supabase_migrations.schema_migrations),
  'versions_110_139', (select coalesce(jsonb_agg(version order by version), '[]') from supabase_migrations.schema_migrations where version ~ '^1[1-3][0-9]$'),
  'ledger_md5_127_130', (select jsonb_object_agg(version, name || ' ' || md5(array_to_string(statements,'')) || ' n=' || cardinality(statements)) from supabase_migrations.schema_migrations where version in ('127','128','129','130')),
  'schemas', (select jsonb_agg(nspname order by nspname) from pg_namespace where nspname in ('ops','kernel','venue','venue_api','notify','catalog')),
  'objects', (select jsonb_object_agg(k, v) from (values
      ('fn release_reservation_for_payment', to_regproc('public.release_reservation_for_payment') is not null),
      ('fn register_push_token', to_regproc('public.register_push_token') is not null),
      ('fn guard_push_token_rebind_epoch', to_regproc('public.guard_push_token_rebind_epoch') is not null),
      ('fn guard_push_token_secret_hash', to_regproc('public.guard_push_token_secret_hash') is not null),
      ('fn unbind_push_token', to_regproc('public.unbind_push_token') is not null),
      ('fn revoke_push_token', to_regproc('public.revoke_push_token') is not null),
      ('fn claim_checkout_supersede', to_regproc('public.claim_checkout_supersede') is not null),
      ('fn release_checkout_supersede', to_regproc('public.release_checkout_supersede') is not null),
      ('fn ops.refund_facts (126, must be absent)', to_regproc('ops.refund_facts') is not null),
      ('fn guard_listing_seller_not_blocked (119, known absent)', to_regproc('public.guard_listing_seller_not_blocked') is not null),
      ('fn revoke_all_push_bindings (131, must be absent)', to_regproc('public.revoke_all_push_bindings') is not null),
      ('tbl push_token_rebind_epoch', to_regclass('public.push_token_rebind_epoch') is not null)) t(k, v)),
  'epoch_rows', (select case when to_regclass('public.push_token_rebind_epoch') is null then null else (select count(*) from public.push_token_rebind_epoch) end),
  'payments_130_cols', (select jsonb_agg(column_name || ':' || data_type order by column_name) from information_schema.columns where table_schema='public' and table_name='payments' and column_name in ('supersede_claim_token','supersede_claimed_at')),
  'push_tokens_cols_128', (select jsonb_agg(column_name order by column_name) from information_schema.columns where table_schema='public' and table_name='push_tokens'),
  'push_tokens_table_privs', (select jsonb_object_agg(grantee, privs) from (select grantee, string_agg(privilege_type, ',' order by privilege_type) privs from information_schema.role_table_grants where table_schema='public' and table_name='push_tokens' and grantee in ('anon','authenticated','service_role') group by grantee) g),
  'push_tokens_col_privs', (select jsonb_object_agg(grantee || ':' || privilege_type, cols) from (select grantee, privilege_type, string_agg(column_name, ',' order by column_name) cols from information_schema.column_privileges where table_schema='public' and table_name='push_tokens' and grantee in ('anon','authenticated') group by grantee, privilege_type) c),
  'fn_acl_defs', (select jsonb_object_agg(p.oid::regprocedure::text, jsonb_build_object('acl', coalesce(p.proacl::text,'default'), 'definer', p.prosecdef, 'config', p.proconfig))
                    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
                   where n.nspname='public' and p.proname in ('release_reservation','release_reservation_for_payment','register_push_token','unbind_push_token','revoke_push_token','claim_checkout_supersede','release_checkout_supersede','guard_push_token_rebind_epoch','guard_push_token_secret_hash')),
  'census_public', jsonb_build_object(
      'tables', (select count(*) from pg_tables where schemaname='public'),
      'functions', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'),
      'policies', (select count(*) from pg_policies where schemaname='public'),
      'triggers', (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)),
  'flags_native', (select jsonb_object_agg(key, value) from catalog.platform_config where key like 'feature.native_%'),
  'counts', jsonb_build_object('listings',(select count(*) from public.listings),'payments',(select count(*) from public.payments),'transfers',(select count(*) from public.transfers),'bids',(select count(*) from public.bids),
            'listings_reserved',(select count(*) from public.listings where status='reserved'),'payments_pending',(select count(*) from public.payments where status='pending'),'push_tokens',(select count(*) from public.push_tokens),
            'payments_with_supersede_claim',(select count(*) from public.payments where supersede_claim_token is not null)),
  'l1_refunded_null_refunded_at', (select count(*) from public.payments where status='refunded' and refunded_at is null),
  'kernel_tickets', (select count(*) from kernel.tickets),
  'kernel_signing_key', (select count(*) from kernel.signing_key),
  'prod_ref_in_public_notify_fn_bodies', (select coalesce(jsonb_agg(p.oid::regprocedure::text), '[]') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','kernel','notify','venue','catalog') and p.prokind in ('f','p') and pg_get_functiondef(p.oid) like '%hqycwntpfoztoinemqns%'),
  'prod_ref_in_cron', (select count(*) from cron.job where command like '%hqycwntpfoztoinemqns%'),
  'cron_jobs', (select count(*) from cron.job),
  'db_pre_request', (select array_to_string(rolconfig, ' | ') from pg_roles where rolname='authenticator')
) as readback;
