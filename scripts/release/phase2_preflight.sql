-- =============================================================================
-- scripts/release/phase2_preflight.sql — READ-ONLY production preflight for the
-- Phase-2 apply (076..092). Returns one row per check: check | status | detail.
-- PASS/WARN/FAIL only — this script never writes. Run as the migration role
-- (postgres) immediately before T-1H and again at T-15M. ANY FAIL row aborts
-- the apply. Authored at the 2026-09-02 release-readiness pass.
-- =============================================================================
with checks as (

-- (run against PRODUCTION; the four L-checks require the CLI ledger table)
-- 1. Ledger shape: every expected pre-apply version present, none of 076..092.
select 'L1 ledger: 076..092 not yet applied' as check_name,
       case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
       coalesce(string_agg(version, ',' order by version), 'none applied yet') as detail
  from supabase_migrations.schema_migrations
 where version ~ '^0(7[6-9]|8[0-9]|9[0-2])$'
union all
select 'L2 ledger: expected row count (90 pre-apply)',
       case when count(*) = 90 then 'PASS' else 'FAIL' end,
       count(*)::text || ' rows'
  from supabase_migrations.schema_migrations
union all
select 'L3 ledger: 043 correctly ABSENT (staged rollout, 042''s own note)',
       case when count(*) = 0 then 'PASS' else 'FAIL' end, count(*)::text
  from supabase_migrations.schema_migrations where version = '043'
union all
select 'L4 ledger: drift migration 20260902003623 present (repo carries its reconstruction)',
       case when count(*) = 1 then 'PASS' else 'FAIL' end, count(*)::text
  from supabase_migrations.schema_migrations where version = '20260902003623'

-- 2. Platform substrate
union all
select 'X1 pg_cron installed',
       case when count(*) = 1 then 'PASS' else 'FAIL' end, coalesce(min(extversion), 'absent')
  from pg_extension where extname = 'pg_cron'
union all
select 'X2 pg_net installed',
       case when count(*) = 1 then 'PASS' else 'FAIL' end, coalesce(min(extversion), 'absent')
  from pg_extension where extname = 'pg_net'
union all
select 'X3 supabase_vault installed',
       case when count(*) = 1 then 'PASS' else 'FAIL' end, coalesce(min(extversion), 'absent')
  from pg_extension where extname = 'supabase_vault'
union all
select 'X4 vault: service_role_key secret exists (crm/edge ticks; NAME check only)',
       case when count(*) >= 1 then 'PASS' else 'FAIL' end, count(*)::text
  from vault.secrets where name = 'service_role_key'
union all
select 'X5 cron: exactly the 3 legacy jobs before apply',
       case when count(*) = 3 then 'PASS' else 'WARN' end,
       string_agg(jobname, ',' order by jobname)
  from cron.job

-- 3. Sentinel prerequisites (078 inserts f0/f1; 019's zero-sentinel must exist)
union all
select 'S1 019 sentinel (0000..0000) exists in auth.users',
       case when count(*) = 1 then 'PASS' else 'FAIL' end, count(*)::text
  from auth.users where id = '00000000-0000-0000-0000-000000000000'
union all
select 'S2 SN-VOID uuid (0000..00f0) free or already sentinel-shaped',
       case when count(*) filter (where raw_app_meta_data->>'provider' is distinct from 'sentinel') = 0
            then 'PASS' else 'FAIL' end, count(*)::text || ' rows'
  from auth.users where id = '00000000-0000-0000-0000-0000000000f0'
union all
select 'S3 system uuid (0000..00f1) free or already sentinel-shaped',
       case when count(*) filter (where raw_app_meta_data->>'provider' is distinct from 'sentinel') = 0
            then 'PASS' else 'FAIL' end, count(*)::text || ' rows'
  from auth.users where id = '00000000-0000-0000-0000-0000000000f1'

-- 4. Legacy-state validity the apply depends on
union all
select 'P1 push_tokens: platform domain already ios|android (092 adds cols, no CHECK on old rows)',
       case when count(*) = 0 then 'PASS' else 'WARN' end, count(*)::text || ' out-of-domain rows'
  from public.push_tokens where platform not in ('ios','android')
union all
select 'P2 no phase-2 schema name is already taken',
       case when count(*) = 0 then 'PASS' else 'FAIL' end,
       coalesce(string_agg(nspname, ','), 'clear')
  from pg_namespace where nspname in ('kernel','venue','catalog','market','notify')

-- 5. Legacy money reconciliation (live rail — the apply must not disturb it,
--    and the release gate wants the impossible-state scan on record)
union all
select 'M1 payments: succeeded rows all carry a Stripe PI ref',
       case when count(*) = 0 then 'PASS' else 'WARN' end, count(*)::text || ' violations'
  from public.payments where status = 'succeeded' and stripe_payment_intent_id is null
union all
select 'M2 transfers: every transfer''s listing exists',
       case when count(*) = 0 then 'PASS' else 'FAIL' end, count(*)::text || ' orphans'
  from public.transfers t where not exists (select 1 from public.listings l where l.id = t.listing_id)
union all
select 'M3 payments: every payment''s listing exists',
       case when count(*) = 0 then 'PASS' else 'FAIL' end, count(*)::text || ' orphans'
  from public.payments p where not exists (select 1 from public.listings l where l.id = p.listing_id)
union all
select 'M4 payments: total = amount + buyer_fee where all three present',
       case when count(*) = 0 then 'PASS' else 'WARN' end, count(*)::text || ' mismatches'
  from public.payments where total is not null and amount is not null and buyer_fee is not null
   and total <> amount + buyer_fee
union all
select 'M5 listings: no row simultaneously reserved and cancelled',
       case when count(*) = 0 then 'PASS' else 'WARN' end, count(*)::text
  from public.listings where auction_status = 'cancelled' and reserved_by is not null

-- 6. Deletion-surface preconditions (077 release train)
union all
select 'D1 profiles trigger on_auth_user_created present (078 sentinel-label upsert accounts for it)',
       case when count(*) >= 1 then 'PASS' else 'WARN' end, count(*)::text
  from pg_trigger where tgname = 'on_auth_user_created'
union all
select 'D2 delete_account_cleanup exists (retired by the edge switch, never by DDL)',
       case when count(*) = 1 then 'PASS' else 'WARN' end, count(*)::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'delete_account_cleanup'
)
select * from checks order by (status = 'FAIL') desc, (status = 'WARN') desc, check_name;
