-- D witness read — READ ONLY. No writes, no DDL. B2 window.
select jsonb_pretty(jsonb_build_object(
  'at', now(),
  'identity_guard', (select count(*) from supabase_migrations.schema_migrations) between 130 and 141
                    and to_regnamespace('ops') is null and to_regproc('public.sandbox_gucs') is not null,
  'ledger_rows', (select count(*) from supabase_migrations.schema_migrations),
  'versions_gt_109', (select coalesce(jsonb_agg(version order by version),'[]') from supabase_migrations.schema_migrations where version ~ '^1[1-9][0-9]$' or version ~ '^202609'),
  'census_public', (select count(*) from pg_tables where schemaname='public')||'|'||
                   (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')||'|'||
                   (select count(*) from pg_policies where schemaname='public')||'|'||
                   (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal),
  'INV1_vault_names', (select coalesce(string_agg(name,',' order by name),'(none)') from vault.secrets),
  'INV1_vault_count', (select count(*) from vault.secrets),
  'INV4_prod_host_in_routines', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname in ('public','kernel','notify','venue','catalog') and p.prokind in ('f','p') and pg_get_functiondef(p.oid) like '%hqycwntpfoztoinemqns%'),
  'INV4_prod_host_in_cron', (select count(*) from cron.job where command like '%hqycwntpfoztoinemqns%'),
  'cron_jobs', (select count(*) from cron.job),
  'cron_names', (select coalesce(string_agg(jobname,',' order by jobname),'(none)') from cron.job),
  'net_queue_rows', (select count(*) from net.http_request_queue),
  'net_response_rows', (select count(*) from net._http_response),
  'auth_sessions_triggers', (select coalesce(string_agg(t.tgname,',' order by t.tgname),'(none)')
       from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
       where n.nspname='auth' and c.relname='sessions' and not t.tgisinternal),
  'push_tokens_rows', (select count(*) from public.push_tokens),
  'push_tokens_has_session_id', (select count(*) from information_schema.columns where table_schema='public' and table_name='push_tokens' and column_name='session_id'),
  'objects_expected_absent', (select jsonb_object_agg(k,v) from (values
      ('131 revoke_all_push_bindings', to_regproc('public.revoke_all_push_bindings') is not null),
      ('132 checkout_group_claim', to_regclass('public.checkout_group_claim') is not null),
      ('135 push_token_challenges', to_regclass('notify.push_token_challenges') is not null),
      ('135 confirm_push_token_challenge', to_regproc('public.confirm_push_token_challenge') is not null)) t(k,v)),
  'counts', jsonb_build_object('listings',(select count(*) from public.listings),'payments',(select count(*) from public.payments),
            'transfers',(select count(*) from public.transfers),'bids',(select count(*) from public.bids),
            'payments_pending',(select count(*) from public.payments where status='pending'),
            'listings_reserved',(select count(*) from public.listings where status='reserved')),
  'L1_refunded_null_at', (select count(*) from public.payments where status='refunded' and refunded_at is null),
  'kernel_tickets', (select count(*) from kernel.tickets),
  'kernel_signing_key', (select count(*) from kernel.signing_key),
  'flags_native', (select coalesce(jsonb_object_agg(key,value),'{}') from catalog.platform_config where key like 'feature.native_%')
)) as v0;
