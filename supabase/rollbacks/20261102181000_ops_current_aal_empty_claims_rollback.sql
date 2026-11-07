-- ============================================================================
-- supabase/rollbacks/20261102181000_ops_current_aal_empty_claims_rollback.sql
-- Rollback for registry 205: restores 115's body of ops.current_aal() (115_ops_console_foundation.sql:75-79)
-- VERBATIM. Guarded like the migration: the pre-flight accepts exactly 205's body (2ea76875ab125648ab5745609f7ed1ef)
-- or 115's (33c0f6adc066ddb1bda8e21996cc38ac — already rolled back: a no-op) and refuses anything else, naming the
-- md5 seen; it captures the posture, and the post-check requires 115's md5 with the ACL, SECURITY DEFINER,
-- search_path, owner, language, volatility and return type unchanged. 205 adds no object: nothing is dropped, no
-- CASCADE.
-- Effect, stated plainly: after a rollback an empty-string request.jwt.claims raises 22P02 again in ops.current_aal()
-- and its callers (ops.assert_reader, ops.whoami, ops.evidence_operator_may_read) instead of reading as absent.
-- Prefer a forward fix.
-- ============================================================================
begin;
set local lock_timeout = '3s';

do $pf$
declare
  v_md5 text;
  v_n   integer;
  q     record;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'ops'::regnamespace and p.proname = 'current_aal';
  if to_regprocedure('ops.current_aal()') is null or v_n <> 1 then
    raise exception 'ROLLBACK_205_REFUSED: expected exactly one ops.current_aal overload, with signature () (overloads %, signature %); nothing changed',
      v_n, case when to_regprocedure('ops.current_aal()') is null then 'absent' else 'present' end;
  end if;
  v_md5 := md5(pg_get_functiondef(to_regprocedure('ops.current_aal()')));
  if v_md5 not in ('2ea76875ab125648ab5745609f7ed1ef', '33c0f6adc066ddb1bda8e21996cc38ac') then
    raise exception 'ROLLBACK_205_REFUSED: ops.current_aal() has md5 %, which is neither 205''s body (2ea76875ab125648ab5745609f7ed1ef) nor 115''s (33c0f6adc066ddb1bda8e21996cc38ac); nothing changed',
      v_md5;
  end if;
  select coalesce(p.proacl::text, '<null>') as acl, p.prosecdef, coalesce(p.proconfig::text, '<null>') as cfg,
         p.proowner::regrole::text as owner, l.lanname as lang, p.provolatile::text as vol,
         p.prorettype::regtype::text as rettype
    into q
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = to_regprocedure('ops.current_aal()');
  perform set_config('rollback_205.preflight',
    jsonb_build_object('md5', v_md5, 'acl', q.acl, 'secdef', q.prosecdef, 'cfg', q.cfg, 'owner', q.owner,
                       'lang', q.lang, 'vol', q.vol, 'rettype', q.rettype)::text, true);
  raise notice '205 rollback pre-flight: ops.current_aal()=% (%)', left(v_md5, 8),
    case v_md5 when '33c0f6adc066ddb1bda8e21996cc38ac' then 'already 115' else '205 body' end;
end $pf$;

do $r1$
declare
  v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.current_aal()')));
begin
  if v_md5 = '33c0f6adc066ddb1bda8e21996cc38ac' then
    raise notice '205 rollback: ops.current_aal() already carries its predecessor (115); unchanged';
  elsif v_md5 = '2ea76875ab125648ab5745609f7ed1ef' then
    execute $def$
create or replace function ops.current_aal()
returns text language sql stable security definer set search_path = ''
as $ops$
  select coalesce(current_setting('request.jwt.claims', true), '{}')::jsonb ->> 'aal';
$ops$
$def$;
    raise notice '205 rollback: ops.current_aal() 205 body -> 115 body';
  else
    raise exception 'ROLLBACK_205_REFUSED: ops.current_aal() has md5 % (unexpected after the pre-flight); nothing changed', v_md5;
  end if;
end $r1$;

do $pc$
declare
  v_cap jsonb := nullif(current_setting('rollback_205.preflight', true), '')::jsonb;
  q     record;
begin
  if v_cap is null then
    raise exception 'ROLLBACK_205_POSTCHECK_FAILED: the pre-flight capture is missing — run this file as one transaction';
  end if;
  select md5(pg_get_functiondef(p.oid)) as md5, coalesce(p.proacl::text, '<null>') as acl, p.prosecdef, p.proconfig,
         coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner, l.lanname as lang,
         p.provolatile::text as vol, p.prorettype::regtype::text as rettype,
         (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n
    into q
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = to_regprocedure('ops.current_aal()');
  if q.md5 is distinct from '33c0f6adc066ddb1bda8e21996cc38ac' then
    raise exception 'ROLLBACK_205_POSTCHECK_FAILED: ops.current_aal() restored body md5 % is not 115''s (33c0f6adc066ddb1bda8e21996cc38ac)',
      coalesce(q.md5, '<absent>');
  end if;
  if q.acl is distinct from v_cap ->> 'acl' or q.prosecdef is distinct from (v_cap ->> 'secdef')::boolean
     or q.cfg is distinct from v_cap ->> 'cfg' or q.proconfig is distinct from array['search_path=""']
     or q.owner is distinct from v_cap ->> 'owner' or q.lang is distinct from v_cap ->> 'lang'
     or q.vol is distinct from v_cap ->> 'vol' or q.rettype is distinct from v_cap ->> 'rettype' or q.n <> 1 then
    raise exception 'ROLLBACK_205_POSTCHECK_FAILED: ops.current_aal() posture changed (acl % -> %, definer % -> %, proconfig % -> %, owner % -> %, language % -> %, volatility % -> %, returns % -> %, overloads %)',
      v_cap ->> 'acl', q.acl, v_cap ->> 'secdef', q.prosecdef, v_cap ->> 'cfg', q.cfg, v_cap ->> 'owner', q.owner,
      v_cap ->> 'lang', q.lang, v_cap ->> 'vol', q.vol, v_cap ->> 'rettype', q.rettype, q.n;
  end if;
  raise notice '205 rollback post-check: ops.current_aal()=33c0f6ad ok (acl %)', q.acl;
end $pc$;

commit;
