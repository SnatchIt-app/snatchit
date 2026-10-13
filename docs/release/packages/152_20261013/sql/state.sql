-- state.sql — read-only state for the 152 package. One text column, `key=value` rows.
-- Safe in every state (objects absent or present): object references go through to_regclass /
-- to_regprocedure / catalog lookups, so the query never errors on absence. Census = the ci.yml Gate-2
-- queries, as in the 150/151 package. Function keys carry md5(pg_get_functiondef) (the hash D and the
-- RC3 package pin) and md5(prosrc) (separates a rendering difference from real drift, the 148 precedent).
with
fn as (
  select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig,
         md5(pg_get_functiondef(p.oid)) as d, md5(p.prosrc) as s, p.prosecdef as secdef, p.proconfig as cfg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.prokind = 'f'
     and (n.nspname, p.proname) in (
       -- new in 152
       ('public','assert_marketplace_parties'), ('public','guard_bid_parties'),
       ('public','guard_listing_reservation_parties'), ('public','guard_listing_content'),
       ('public','listing_prohibited_term'),
       -- redefined by 152
       ('ops','action_dispatch'), ('public','can_create_listing'),
       -- must not change
       ('public','reserve_buy_now'), ('public','complete_auction_payment'), ('public','mark_listing_sold'),
       ('public','settle_listing_for_payment'), ('public','validate_and_apply_bid'),
       ('public','release_reservation'), ('public','cleanup_expired_reservations'),
       ('ops','execute_action'), ('ops','action_allowed_roles'))
),
nf(sig) as (values ('public.assert_marketplace_parties(uuid,uuid)'), ('public.guard_bid_parties()'),
                   ('public.guard_listing_reservation_parties()'), ('public.guard_listing_content()'),
                   ('public.listing_prohibited_term(text[])')),
trg as (
  select c.relname || '.' || t.tgname || ':' || t.tgenabled::text || ':' || t.tgtype::text || ':' || t.tgfoid::regprocedure::text as line
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal
     and t.tgname in ('before_bid_guard_parties','trg_guard_listing_reservation_parties','trg_guard_listing_content')
),
grants as (
  select 'T:' || table_schema || '.' || table_name || ':' || grantee || ':' || privilege_type as g
    from information_schema.role_table_grants
   where grantee in ('anon','authenticated') and table_schema in ('public','ops','kernel','notify','market','venue','catalog')
  union all
  select 'R:' || routine_schema || '.' || specific_name || ':' || grantee || ':' || privilege_type
    from information_schema.role_routine_grants
   where grantee in ('anon','authenticated') and routine_schema in ('public','ops','kernel','notify','market','venue','catalog')
)
select 'ledger_count=' || (select count(*) from supabase_migrations.schema_migrations)
union all select 'ledger_max=' || coalesce((select max(version) from supabase_migrations.schema_migrations), '-')
union all select 'ledger_152=' || coalesce((select coalesce(name,'') || '|' || coalesce(created_by,'') || '|' || coalesce(array_length(statements,1),0)
                                                   || '|' || coalesce(md5(statements[1]),'-') || '|' || coalesce(octet_length(statements[1]),0)
                                              from supabase_migrations.schema_migrations where version = '20261013000000'), 'absent')
union all select 'ledger_unauthorised_121_125_126=' || coalesce((select string_agg(version, ',' order by version) from supabase_migrations.schema_migrations
                                                                 where version in ('121','125','126')), 'none')
union all select 'census=' || (select count(*) from pg_tables where schemaname = 'public') || '|'
          || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public') || '|'
          || (select count(*) from pg_policies where schemaname = 'public') || '|'
          || (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public' and not t.tgisinternal)
union all select 'fn_' || sig || '=def:' || d || '|src:' || s || '|secdef=' || secdef || '|cfg=' || coalesce(array_to_string(cfg, ','), '-') from fn
union all select 'exec_' || sig || '=' || case when to_regprocedure(sig) is null then 'absent' else
          'anon:' || has_function_privilege('anon', to_regprocedure(sig), 'EXECUTE')
          || ',authenticated:' || has_function_privilege('authenticated', to_regprocedure(sig), 'EXECUTE')
          || ',service_role:' || has_function_privilege('service_role', to_regprocedure(sig), 'EXECUTE') end from nf
union all select 'triggers_152=' || coalesce((select string_agg(line, ',' order by line) from trg), 'none')
union all select 'bids_first_trigger=' || coalesce((select min(t.tgname) from pg_trigger t where t.tgrelid = 'public.bids'::regclass and not t.tgisinternal), 'none')
union all select 'kind_check=' || coalesce((select pg_get_constraintdef(oid) from pg_constraint
                                            where conrelid = 'ops.user_restriction'::regclass and conname = 'user_restriction_kind_check'), 'absent')
union all select 'user_restriction_rows=' || (select count(*) from ops.user_restriction)
union all select 'user_blocks_rows=' || (select count(*) from public.user_blocks)
union all select 'user_blocks_rls=' || (select relrowsecurity from pg_class where oid = 'public.user_blocks'::regclass) || '|'
          || coalesce((select string_agg(policyname || ':' || cmd, ',' order by policyname) from pg_policies
                        where schemaname = 'public' and tablename = 'user_blocks'), 'none')
union all select 'grants_anon_authenticated=' || (select count(*) from grants) || '|' || md5(coalesce((select string_agg(g, ';' order by g) from grants), ''))
union all select 'ops_setting=' || (select count(*) from ops.setting) || '|'
          || md5(coalesce((select string_agg(key || '=' || value::text, ';' order by key) from ops.setting), ''));
