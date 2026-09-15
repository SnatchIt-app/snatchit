-- D review harness: a catalog identity snapshot for rollback-battery diffs. One line per object, sorted.
-- Covers the user schemas a migration can change; excludes pgTAP, temp and extension-owned objects.
with sch as (
  select n.oid, n.nspname from pg_namespace n
   where n.nspname not in ('pg_catalog','information_schema','pg_toast','tap')
     and n.nspname not like 'pg_temp%' and n.nspname not like 'pg_toast_temp%'
), ext as (select objid from pg_depend where deptype = 'e')
select line from (
  select 'schema|'||s.nspname||'|'||coalesce(array_to_string(n.nspacl, ','), '') as line
    from sch s join pg_namespace n on n.oid = s.oid
  union all
  select 'rel|'||s.nspname||'.'||c.relname||'|'||c.relkind::text||'|rls='||c.relrowsecurity||'|force='||c.relforcerowsecurity||'|acl='||coalesce(array_to_string(c.relacl, ','), '')
    from pg_class c join sch s on s.oid = c.relnamespace
   where c.relkind in ('r','v','m','p','f','S') and c.oid not in (select objid from ext)
  union all
  select 'col|'||s.nspname||'.'||c.relname||'.'||a.attname||'|'||format_type(a.atttypid, a.atttypmod)||'|nn='||a.attnotnull||'|def='||coalesce(pg_get_expr(d.adbin, d.adrelid), '')||'|acl='||coalesce(array_to_string(a.attacl, ','), '')
    from pg_attribute a join pg_class c on c.oid = a.attrelid join sch s on s.oid = c.relnamespace
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where a.attnum > 0 and not a.attisdropped and c.relkind in ('r','v','m','p','f') and c.oid not in (select objid from ext)
  union all
  select 'con|'||s.nspname||'.'||c.relname||'|'||k.conname||'|'||pg_get_constraintdef(k.oid)
    from pg_constraint k join pg_class c on c.oid = k.conrelid join sch s on s.oid = c.relnamespace
  union all
  select 'idx|'||s.nspname||'|'||pg_get_indexdef(i.indexrelid)
    from pg_index i join pg_class c on c.oid = i.indexrelid join sch s on s.oid = c.relnamespace
  union all
  select 'pol|'||p.schemaname||'.'||p.tablename||'|'||p.policyname||'|'||p.cmd||'|'||array_to_string(p.roles, ',')||'|'||coalesce(p.qual, '')||'|'||coalesce(p.with_check, '')
    from pg_policies p where p.schemaname in (select nspname from sch)
  union all
  select 'trg|'||s.nspname||'.'||c.relname||'|'||pg_get_triggerdef(t.oid)
    from pg_trigger t join pg_class c on c.oid = t.tgrelid join sch s on s.oid = c.relnamespace where not t.tgisinternal
  union all
  select 'fn|'||p.oid::regprocedure::text||'|'||md5(pg_get_functiondef(p.oid))||'|acl='||coalesce(array_to_string(p.proacl, ','), '')
    from pg_proc p join sch s on s.oid = p.pronamespace
   where p.prokind in ('f','p') and p.oid not in (select objid from ext)
  union all
  select 'view|'||s.nspname||'.'||c.relname||'|'||md5(pg_get_viewdef(c.oid))
    from pg_class c join sch s on s.oid = c.relnamespace where c.relkind in ('v','m')
) x order by line;
