with ns as (select oid, nspname from pg_namespace where nspname not in ('pg_catalog','information_schema','pg_toast') and nspname not like 'pg_temp%' and nspname not like 'pg_toast_temp%'),
ext as (select objid from pg_depend where deptype='e')
select 'fn|'||n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')|'||md5(coalesce(p.prosrc,''))||'|secdef='||p.prosecdef||'|cfg='||coalesce(array_to_string(p.proconfig,','),'')||'|acl='||coalesce(p.proacl::text,'')
  from pg_proc p join ns n on n.oid=p.pronamespace where p.oid not in (select objid from ext)
union all
select 'col|'||n.nspname||'.'||c.relname||'.'||a.attname||'|'||format_type(a.atttypid,a.atttypmod)||'|nn='||a.attnotnull||'|def='||coalesce(pg_get_expr(d.adbin,d.adrelid),'')
  from pg_attribute a join pg_class c on c.oid=a.attrelid join ns n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
 where a.attnum>0 and not a.attisdropped and c.relkind in ('r','v','m','p','f') and c.oid not in (select objid from ext)
union all
select 'rel|'||n.nspname||'.'||c.relname||'|'||c.relkind::text||'|rls='||c.relrowsecurity||'|acl='||coalesce(c.relacl::text,'')
  from pg_class c join ns n on n.oid=c.relnamespace where c.relkind in ('r','v','m','p','f','S') and c.oid not in (select objid from ext)
union all
select 'pol|'||schemaname||'.'||tablename||'.'||policyname||'|'||cmd||'|'||array_to_string(roles,',')||'|'||coalesce(qual,'')||'|'||coalesce(with_check,'') from pg_policies
union all
select 'trg|'||n.nspname||'.'||c.relname||'.'||t.tgname||'|'||pg_get_triggerdef(t.oid) from pg_trigger t join pg_class c on c.oid=t.tgrelid join ns n on n.oid=c.relnamespace where not t.tgisinternal
union all
select 'idx|'||schemaname||'.'||indexname||'|'||indexdef from pg_indexes where schemaname not in ('pg_catalog','information_schema')
union all
select 'view|'||n.nspname||'.'||c.relname||'|'||md5(pg_get_viewdef(c.oid)) from pg_class c join ns n on n.oid=c.relnamespace where c.relkind in ('v','m')
order by 1;
