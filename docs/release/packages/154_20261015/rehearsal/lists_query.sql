-- lists_query.sql — the ONE read-only query that yields an environment's predicted list hashes for
-- predict.py: the existing rows plus the literal rows 154, 155 and 156 add (grants, triggers, listings columns).
-- Review fix (2026-10-15): 154 also grants anon/authenticated EXECUTE on is_public(listings); 155 adds
-- trg_listing_ends_at_from_duration (its function is revoked from anon/authenticated, so no grant row).
-- Run on production (MCP execute_sql, 2026-10-15) -> lists_prod.json; on the rehearsal DB -> lists_local.json.
SET TRANSACTION READ ONLY;
SET LOCAL search_path = public, extensions;
with grants as (
  select 'T:' || table_schema || '.' || table_name || ':' || grantee || ':' || privilege_type as g
    from information_schema.role_table_grants
   where grantee in ('anon','authenticated') and table_schema in ('public','ops','kernel','notify','market','venue','catalog')
  union all
  select 'R:' || n.nspname || '.' || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || '):' || r.rolname || ':' || a.privilege_type
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(p.proacl) a
    join pg_roles r on r.oid = a.grantee
   where r.rolname in ('anon','authenticated') and n.nspname in ('public','ops','kernel','notify','market','venue','catalog')
),
add154(g) as (values ('R:public.listing_is_public(uuid):anon:EXECUTE'), ('R:public.listing_is_public(uuid):authenticated:EXECUTE'),
                     ('R:public.listing_private_party(uuid):anon:EXECUTE'), ('R:public.listing_private_party(uuid):authenticated:EXECUTE'),
                     ('R:public.is_public(listings):anon:EXECUTE'), ('R:public.is_public(listings):authenticated:EXECUTE')),
add156(g) as (values ('R:public.current_user_is_admin():authenticated:EXECUTE')),
g154 as (select g from grants union all select g from add154),
g156 as (select g from g154 union all select g from add156),
trg as (
  select c.relname || '.' || t.tgname || ':' || t.tgenabled::text || ':' || t.tgtype::text || ':' || t.tgfoid::regprocedure::text as line
    from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname in ('listings', 'bids', 'listing_visibility')
),
t154 as (select line from trg union all values ('listings.trg_hidden_listing_not_live:O:19:guard_hidden_listing_not_live()'), ('listing_visibility.trg_listing_visibility_not_live:O:7:guard_hidden_listing_not_live()')),
t155 as (select line from t154 union all values ('listings.trg_listing_ends_at_from_duration:O:23:set_listing_ends_at_from_duration()')),
t156 as (select line from t155 union all values ('listings.trg_guard_listing_proof_waiver:O:23:guard_listing_proof_waiver()')),
cols as (select column_name || ':' || data_type || ':' || is_nullable as c from information_schema.columns where table_schema = 'public' and table_name = 'listings'),
c156 as (select c from cols union all values ('proof_waived_at:timestamp with time zone:YES'), ('proof_waived_by:uuid:YES'), ('proof_waiver_reason:text:YES'))
select json_build_object(
  'grants_154', (select count(*) || '|' || md5(string_agg(g, ';' order by g COLLATE "C")) from g154),
  'grants_156', (select count(*) || '|' || md5(string_agg(g, ';' order by g COLLATE "C")) from g156),
  'trg_154', (select md5(string_agg(line, ',' order by line COLLATE "C")) || '|' || count(*) from t154),
  'trg_155', (select md5(string_agg(line, ',' order by line COLLATE "C")) || '|' || count(*) from t155),
  'trg_156', (select md5(string_agg(line, ',' order by line COLLATE "C")) || '|' || count(*) from t156),
  'cols_156', (select count(*) || '|' || md5(string_agg(c, ',' order by c COLLATE "C")) from c156))::text;
