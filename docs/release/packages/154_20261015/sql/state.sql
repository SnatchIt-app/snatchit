-- state.sql — read-only state for the 154/155/156 package. One text column, `key=value` rows.
-- Copied from ../152_20261013/sql/state.sql (method unchanged): safe in every state (objects absent or
-- present) because object references go through to_regclass / to_regprocedure / catalog lookups.
-- Census = the ci.yml Gate-2 queries. Function keys carry md5(pg_get_functiondef) and md5(prosrc).
-- grants_anon_authenticated differs from 152's key: routine rows are name(argtypes) from proacl, not specific_name.
-- Every ordered aggregate sorts COLLATE "C", so a local rehearsal and production hash the same order.
-- 154 additions:
--   * pol_<table>.<policy> for every policy on listings, bids and listing_visibility: cmd|roles|md5(qual)|md5(with_check);
--   * lv_* : listing_visibility existence, RLS, policies, grants and row count; listings_rows; live_listings;
--   * FIXED HASHES (count|md5 over to_jsonb rows, ordered by their text) of payments, transfers,
--     payment_refunds, payment_refund_state, payout_attempts, payout_decisions, disputes, bids, and
--     listings minus updated_at (and minus 156's three waiver columns, so 156 adding them is not a
--     "listing state change"). pre == post on these proves no money or listing state moved.
--   The anon / non-party visible counts are a SEPARATE request (sql/state_anon.sql): they need SET LOCAL ROLE.
-- Review-fix additions (2026-10-15, after the 154/155 review):
--   * is_public(listings) and set_listing_ends_at_from_duration() in the fn/exec keys; 155's trigger in triggers_154_156;
--   * rls_<table> (owner|RLS|FORCE) for listings, bids, payments, transfers, listing_visibility; owner_role (the owner of
--     listings: super / bypassrls); fnown_<reader> (owner | owns-like-listings | bypasses RLS) for listing_is_public,
--     listing_private_party and is_public: the 42P17 no-recursion guarantee, read back instead of assumed;
--   * hidden_open_or_held: hidden rows that are OPEN (what reserve_buy_now accepts) or under a live Buy Now hold (must be 0).
-- The two SET LOCAL lines pin the rendering (TimeZone inside to_jsonb timestamps; search_path inside deparsed
-- policy quals) for the one implicit transaction this request runs in (pkg.py probe: same_txn=true).
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone = 'UTC';
SET LOCAL search_path = public, extensions;
with
fn as (
  select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as sig,
         md5(pg_get_functiondef(p.oid)) as d, md5(p.prosrc) as s, p.prosecdef as secdef, p.proconfig as cfg
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.prokind = 'f'
     and (n.nspname, p.proname) in (
       -- new in 154 / 156
       ('public','listing_is_public'), ('public','listing_private_party'), ('public','guard_hidden_listing_not_live'),
       ('public','is_public'), ('public','set_listing_ends_at_from_duration'),
       ('public','guard_listing_proof_waiver'), ('public','current_user_is_admin'),
       -- redefined by 154
       ('public','get_profile_trust_stats'),
       -- must not change (live-state checks the invariant relies on; listings guards)
       ('public','reserve_buy_now'), ('public','validate_and_apply_bid'), ('public','finalize_auction'),
       ('public','auto_finalize_expired_auctions'), ('public','admin_relist_listing'),
       ('public','cleanup_expired_reservations'), ('public','release_reservation'),
       ('public','complete_auction_payment'), ('public','mark_listing_sold'), ('public','settle_listing_for_payment'),
       ('public','guard_listing_insert_columns'), ('public','guard_listing_state_columns'), ('public','guard_proof_status'),
       ('public','guard_listing_content'), ('public','guard_listing_reservation_parties'))
),
nf(sig) as (values ('public.listing_is_public(uuid)'), ('public.listing_private_party(uuid)'),
                   ('public.guard_hidden_listing_not_live()'), ('public.guard_listing_proof_waiver()'),
                   ('public.current_user_is_admin()'), ('public.get_profile_trust_stats(uuid)'),
                   ('public.is_public(public.listings)'), ('public.set_listing_ends_at_from_duration()')),
rd(sig) as (values ('public.listing_is_public(uuid)'), ('public.listing_private_party(uuid)'), ('public.is_public(public.listings)')),
tb(t) as (values ('listings'), ('bids'), ('payments'), ('transfers'), ('listing_visibility')),
pol as (
  select tablename || '.' || policyname as k,
         cmd || '|' || roles::text || '|' || md5(coalesce(qual, '')) || '|' || md5(coalesce(with_check, '')) as v
    from pg_policies where schemaname = 'public' and tablename in ('listings', 'bids', 'listing_visibility')
),
trg as (
  select c.relname || '.' || t.tgname || ':' || t.tgenabled::text || ':' || t.tgtype::text || ':' || t.tgfoid::regprocedure::text as line
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
     and c.relname in ('listings', 'bids', 'listing_visibility')
),
grants as (
  select 'T:' || table_schema || '.' || table_name || ':' || grantee || ':' || privilege_type as g
    from information_schema.role_table_grants
   where grantee in ('anon','authenticated') and table_schema in ('public','ops','kernel','notify','market','venue','catalog')
  union all
  -- routines keyed by name(argtypes), never specific_name (which embeds the OID and would make a new
  -- function's grant row unpredictable); explicit ACL entries for anon/authenticated only
  select 'R:' || n.nspname || '.' || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || '):' || r.rolname || ':' || a.privilege_type
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(p.proacl) a
    join pg_roles r on r.oid = a.grantee
   where r.rolname in ('anon','authenticated') and n.nspname in ('public','ops','kernel','notify','market','venue','catalog')
)
select 'ledger_count=' || (select count(*) from supabase_migrations.schema_migrations)
union all select 'ledger_max=' || coalesce((select max(version) from supabase_migrations.schema_migrations), '-')
union all select 'ledger_' || m.n || '=' || coalesce((select coalesce(name,'') || '|' || coalesce(created_by,'') || '|' || coalesce(array_length(statements,1),0)
                                                       || '|' || coalesce(md5(statements[1]),'-') || '|' || coalesce(octet_length(statements[1]),0)
                                                  from supabase_migrations.schema_migrations where version = m.v), 'absent')
            from (values ('154','20261015000000'), ('155','20261015000100'), ('156','20261015000200')) m(n, v)
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
union all select 'pol_' || k || '=' || v from pol
union all select 'policies_listings_bids_lv=' || (select count(*) from pol)
union all select 'triggers_listings_bids_lv=' || coalesce((select md5(string_agg(line, ',' order by line COLLATE "C")) || '|' || count(*) from trg), 'none')
union all select 'triggers_154_156=' || coalesce((select string_agg(line, ',' order by line COLLATE "C") from trg
                                                   where line ~ '(trg_hidden_listing_not_live|trg_listing_visibility_not_live|trg_listing_ends_at_from_duration|trg_guard_listing_proof_waiver):'), 'none')
union all select 'duration_check=' || coalesce((select pg_get_constraintdef(oid) from pg_constraint
                                                where conrelid = 'public.listings'::regclass and conname = 'listings_duration_hours_check'), 'absent')
union all select 'waiver_checks=' || coalesce((select string_agg(conname || ':' || md5(pg_get_constraintdef(oid)), ',' order by conname COLLATE "C") from pg_constraint
                                               where conrelid = 'public.listings'::regclass and conname like 'listings_proof_waive%'), 'none')
union all select 'listings_columns=' || (select count(*) || '|' || md5(string_agg(column_name || ':' || data_type || ':' || is_nullable, ',' order by column_name COLLATE "C"))
                                           from information_schema.columns where table_schema = 'public' and table_name = 'listings')
union all select 'lv_table=' || coalesce((select relrowsecurity::text || '|policies:' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'listing_visibility')
                                                 || '|grants:' || coalesce((select string_agg(grantee || ':' || privilege_type, ',' order by grantee COLLATE "C", privilege_type COLLATE "C")
                                                                             from information_schema.role_table_grants
                                                                            where table_schema = 'public' and table_name = 'listing_visibility'
                                                                              and grantee in ('anon','authenticated','service_role','PUBLIC')), '-')
                                            from pg_class where oid = to_regclass('public.listing_visibility')), 'absent')
union all select 'lv_rows=' || coalesce((xpath('/row/c/text()', query_to_xml(
                   'select count(*) as c from public.listing_visibility', false, true, '')))[1]::text, 'absent')
            where to_regclass('public.listing_visibility') is not null
union all select 'lv_rows=absent' where to_regclass('public.listing_visibility') is null
union all select 'listings_rows=' || (select count(*) from public.listings)
union all select 'live_listings=' || (select count(*) from public.listings where status = 'active' and auction_status = 'active' and ends_at > now())
union all select 'hidden_open_or_held=' || coalesce((xpath('/row/c/text()', query_to_xml(
                   'select count(*) as c from public.listing_visibility v join public.listings l on l.id = v.listing_id '
                   'where (l.status in (''active'',''reserved'') and l.auction_status <> ''cancelled'' and l.ends_at >= now()) '
                   'or (l.status = ''reserved'' and not coalesce(l.reserved_until <= now(), false))', false, true, '')))[1]::text, 'absent')
            where to_regclass('public.listing_visibility') is not null
union all select 'hidden_open_or_held=absent' where to_regclass('public.listing_visibility') is null
union all select 'rls_' || tb.t || '=' || coalesce((select pg_get_userbyid(c.relowner) || '|rls=' || c.relrowsecurity || '|force=' || c.relforcerowsecurity
                                                     from pg_class c where c.oid = to_regclass('public.' || tb.t)), 'absent') from tb
union all select 'owner_role=' || (select r.rolname || '|super=' || r.rolsuper || '|bypassrls=' || r.rolbypassrls
                                     from pg_class c join pg_roles r on r.oid = c.relowner where c.oid = 'public.listings'::regclass)
union all select 'fnown_' || rd.sig || '=' || coalesce((select pg_get_userbyid(p.proowner) || '|owner_of_listings=' || (p.proowner = c.relowner)
                                                               || '|bypasses_rls=' || (r.rolbypassrls or r.rolsuper)
                                                          from pg_proc p join pg_roles r on r.oid = p.proowner
                                                          cross join (select relowner from pg_class where oid = 'public.listings'::regclass) c
                                                         where p.oid = to_regprocedure(rd.sig)), 'absent') from rd
union all select 'hash_listings_minus_updated_at=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), ''))
          from (select (to_jsonb(l) - 'updated_at' - 'proof_waived_at' - 'proof_waived_by' - 'proof_waiver_reason')::text as x from public.listings l) q)
union all select 'hash_bids=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.bids t) q)
union all select 'hash_payments=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.payments t) q)
union all select 'hash_transfers=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.transfers t) q)
union all select 'hash_payment_refunds=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.payment_refunds t) q)
union all select 'hash_payment_refund_state=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.payment_refund_state t) q)
union all select 'hash_payout_attempts=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.payout_attempts t) q)
union all select 'hash_payout_decisions=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.payout_decisions t) q)
union all select 'hash_disputes=' || (select count(*) || '|' || md5(coalesce(string_agg(x, E'\n' order by x COLLATE "C"), '')) from (select to_jsonb(t)::text as x from public.disputes t) q)
union all select 'grants_anon_authenticated=' || (select count(*) from grants) || '|' || md5(coalesce((select string_agg(g, ';' order by g COLLATE "C") from grants), ''))
union all select 'storage_policies=' || (select count(*) || '|' || md5(coalesce(string_agg(policyname || ':' || cmd || ':' || roles::text || ':' || coalesce(qual,'') || ':' || coalesce(with_check,''), ';' order by policyname COLLATE "C"), ''))
                                           from pg_policies where schemaname = 'storage');
