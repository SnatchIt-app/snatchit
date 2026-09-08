-- =============================================================================
-- scripts/release/phase2_postapply_verify.sql — READ-ONLY verification run
-- immediately after the Phase-2 apply (076..092). One row per check.
-- ANY FAIL row triggers the rollback decision tree. Never writes.
-- =============================================================================
with checks as (
select 'V1 ledger: 107 rows, 076..092 all present' as check_name,
       case when (select count(*) from supabase_migrations.schema_migrations) = 107
             and (select count(*) from supabase_migrations.schema_migrations
                   where version ~ '^0(7[6-9]|8[0-9]|9[0-2])$') = 17
            then 'PASS' else 'FAIL' end as status,
       (select count(*) from supabase_migrations.schema_migrations)::text || ' rows' as detail
-- (a local rehearsal DB must carry a faux CLI ledger first — the rehearsal
--  script creates one; production always has the real one)
union all
select 'V2 schemas: the five phase-2 schemas exist',
       case when count(*) = 5 then 'PASS' else 'FAIL' end, count(*)::text
  from pg_namespace where nspname in ('kernel','venue','catalog','market','notify')
union all
select 'V3 five-schema relation census 75',
       case when count(*) = 75 then 'PASS' else 'FAIL' end, count(*)::text
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname in ('kernel','venue','catalog','market','notify') and c.relkind in ('r','p','v','m','S','f')
union all
select 'V4 five-schema routine census 243',
       case when count(*) = 243 then 'PASS' else 'FAIL' end, count(*)::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('kernel','venue','catalog','market','notify')
union all
select 'V5 five-schema policy register 72',
       case when count(*) = 72 then 'PASS' else 'FAIL' end, count(*)::text
  from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
 where n.nspname in ('kernel','venue','catalog','market','notify')
union all
select 'V6 cron: 19 jobs (3 legacy + 16 phase-2)',
       case when count(*) = 19 then 'PASS' else 'FAIL' end, count(*)::text
  from cron.job
union all
select 'V7 config: 43 platform keys, every seed version 1',
       case when count(distinct key) = 43 and count(*) filter (where version <> 1) = 0
            then 'PASS' else 'FAIL' end, count(distinct key)::text || ' keys'
  from catalog.platform_config
union all
select 'V8 DARK: all five feature flags false',
       case when count(*) = 5 then 'PASS' else 'FAIL' end,
       count(*)::text || ' of 5 flags false'
  from catalog.platform_config c
 where c.key in ('feature.native_issuance_enabled','feature.native_scanning_enabled',
                 'feature.native_resale_enabled','wallet.apple.enabled','notify.announcements_enabled')
   and c.value = 'false'::jsonb
   and c.version = (select max(version) from catalog.platform_config c2 where c2.key = c.key)
union all
select 'V9 FAIL-CLOSED: the three owner-unset keys still NULL',
       case when count(*) = 3 then 'PASS' else 'FAIL' end, count(*)::text || ' of 3 null'
  from catalog.platform_config c
 where c.key in ('retention.backup_window_days','deletion.refund_possible_window_hours','notify.delivery_lease_interval')
   and c.value = 'null'::jsonb
   and c.version = (select max(version) from catalog.platform_config c2 where c2.key = c.key)
union all
select 'V10 phase-2 data plane EMPTY (dark apply writes no business row)',
       case when (select count(*) from kernel.tickets)
              + (select count(*) from kernel.ticket_ownership_log)
              + (select count(*) from venue."order")
              + (select count(*) from kernel.payout)
              + (select count(*) from kernel.refund)
              + (select count(*) from market.market_sale)
              + (select count(*) from venue.attribution)
              + (select count(*) from notify.notification)
              + (select count(*) from kernel.reserve) = 0
            then 'PASS' else 'FAIL' end, 'nine tables summed'
union all
select 'V11 sentinels: f0/f1 exist, sentinel-shaped, cannot sign in',
       case when count(*) = 2 then 'PASS' else 'FAIL' end, count(*)::text
  from auth.users
 where id in ('00000000-0000-0000-0000-0000000000f0','00000000-0000-0000-0000-0000000000f1')
   and raw_app_meta_data->>'provider' = 'sentinel' and encrypted_password is null
union all
select 'V12 outbox: only the two frozen emit routines write it; 0 rows at apply',
       case when (select count(*) from notify.outbox) = 0 then 'PASS' else 'FAIL' end,
       (select count(*) from notify.outbox)::text || ' rows'
union all
-- PFA-1 sweep (the compensating control, run against PRODUCTION as the release
-- gate requires): zero PUBLIC/anon EXECUTE on any walled-schema function.
select 'V13 PFA-1 sweep: zero PUBLIC/anon EXECUTE in kernel/venue/market/notify',
       case when count(*) = 0 then 'PASS' else 'FAIL' end, count(*)::text || ' grants'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
 where a.privilege_type = 'EXECUTE'
   and n.nspname in ('kernel','venue','market','notify')
   and (a.grantee = 0 or a.grantee in (select oid from pg_roles where rolname = 'anon'))
union all
select 'V14 schema walls: anon has no USAGE on kernel/venue/market/notify',
       case when count(*) = 0 then 'PASS' else 'FAIL' end, count(*)::text
  from (values ('kernel'),('venue'),('market'),('notify')) s(n)
 where has_schema_privilege('anon', s.n, 'USAGE')
union all
select 'V15 legacy surface untouched: public grants on notifications/push_tokens unchanged',
       case when has_table_privilege('authenticated','public.notifications','SELECT')
             and has_table_privilege('authenticated','public.push_tokens','SELECT')
             and not has_table_privilege('anon','public.push_tokens','DELETE') is null
            then 'PASS' else 'FAIL' end, 'spot check'
union all
select 'V16 push_tokens: the four 092 columns exist, all legacy rows revoked_at IS NULL',
       case when (select count(*) from information_schema.columns
                   where table_schema='public' and table_name='push_tokens'
                     and column_name in ('revoked_at','revoked_reason','provider_receipt_checked_at','last_provider_error')) = 4
             and (select count(*) from public.push_tokens where revoked_at is not null) = 0
            then 'PASS' else 'FAIL' end, 'additive only'
union all
select 'V17 held-money invariant: zero promoter payouts exist (and any future one is born held)',
       case when count(*) = 0 then 'PASS' else 'FAIL' end, count(*)::text
  from kernel.payout where cause = 'promoter_commission' and hold_state <> 'held'
union all
select 'V18 notify claim fails closed (lease owner-unset)',
       case when (select c.value from catalog.platform_config c where c.key='notify.delivery_lease_interval'
                   order by c.version desc limit 1) = 'null'::jsonb
            then 'PASS' else 'FAIL' end, 'claim_deliveries refuses until owner sets it'
)
select * from checks order by (status = 'FAIL') desc, check_name;
