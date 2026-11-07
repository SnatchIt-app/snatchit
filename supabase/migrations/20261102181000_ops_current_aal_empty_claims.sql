-- ============================================================================
-- 20261102181000_ops_current_aal_empty_claims.sql — registry 205 / pgTAP 274.
-- D writes and owns; A allocated the number and decided the scope (D/HARDENING-PROPOSALS-20261102.md, H5 and its
-- "H5 census"); E reviews. REPO-ONLY: applied nowhere, no production change.
--
-- WHAT CHANGES — body-only CREATE OR REPLACE of ONE function, ops.current_aal() (115_ops_console_foundation.sql:75-79;
-- no later migration redefines it). Same signature, language sql, STABLE, SECURITY DEFINER, search_path '', owner and
-- ACL (the post-flight proves each unchanged against the pre-flight's own capture). The only edit is in the one
-- expression: the claims GUC text passes through nullif(..., '') before the coalesce with '{}' and the jsonb cast —
-- the idiom 196's ops.request_platform_config already uses — so an EMPTY-STRING request.jwt.claims reads exactly like
-- an ABSENT one. Every other byte equals 115's text (diff: D/s17-205/pred-vs-new.diff).
--
-- CLAIMS GUC CLASSES (before -> after):
--   absent (NULL)                         returns NULL                        -> unchanged
--   '' (empty string)                     raises 22P02                        -> returns NULL, the same as absent
--   '{}' / a JSON value with no aal       returns NULL                        -> unchanged
--   non-empty text that is not JSON       raises 22P02                        -> unchanged: still 22P02, not caught.
--                                                                                Only the exact empty string is
--                                                                                normalised; whitespace is not.
--   a JSON object carrying aal            returns that aal                    -> unchanged
-- No input yields 'aal2' without an aal2 claim, before or after. Malformed claims keep failing closed with their own
-- SQLSTATE; this file only aligns the empty string with the absent case.
--
-- CALLERS — the live bodies that reference ops.current_aal() (pg_proc.prosrc over the 7496fee3 chain; pg_depend has
-- no edge because none of them is BEGIN ATOMIC), each unchanged here and picking up the new body by name:
--   ops.assert_reader()               (115) '' : 22P02 -> step_up_unavailable (P0001), as for absent claims.
--                                           ops.assert_role(text[]) and every ops reader inherit through it.
--   ops.whoami()                      (115) '' : 22P02 -> returns aal null, as for absent claims.
--   ops.evidence_operator_may_read()  (118) '' : 22P02 -> not true (NULL for an operator, false otherwise), as for
--                                           absent claims; read by the storage policy "proof-docs operator read".
-- No test, CI file or migration pins ops.current_aal's md5 before this file; no caller's md5 moves.
-- Out of scope (other lanes' functions, unchanged): the kernel and signing-key claims readers and
-- public.request_is_service_role.
--
-- MD5 — md5(pg_get_functiondef(...)), measured on a local PG17 replay (d197_base = main 7496fee3's chain):
--   ops.current_aal()   115 predecessor  33c0f6adc066ddb1bda8e21996cc38ac
--                       205 (this file)  2ea76875ab125648ab5745609f7ed1ef
-- PRE-FLIGHT accepts exactly those two (115: first apply; 205: idempotent re-apply, a no-op) and refuses anything
-- else, naming the md5 seen; it also refuses a second ops.current_aal overload and any posture other than 115's
-- (SECURITY DEFINER, search_path '', owner postgres, sql, STABLE, returns text, no EXECUTE for PUBLIC, anon or
-- authenticated). It captures the ACL, prosecdef, proconfig, owner, language, volatility and return type in a
-- transaction-local setting; the POST-FLIGHT requires 205's md5 and every captured attribute unchanged (no ACL string
-- is hard-coded). Run the file as one transaction (it carries begin/commit); without the capture the post-flight
-- fails closed.
--
-- GRANTS / FOUR-FILE RULE: ops only. CREATE OR REPLACE keeps every grant; none is re-stated. The CI gates read
-- `public` only (grant-decision manifest, expected_grants, Gate-2 census): no manifest row, no expected_grants line,
-- Gate-2 +0 (a dated note in ci.yml).
-- LOCKS / RUNTIME: CREATE OR REPLACE FUNCTION only; no table or row is read or written; lock_timeout 3s.
-- ROLLBACK: supabase/rollbacks/20261102181000_ops_current_aal_empty_claims_rollback.sql restores 115's body under an
-- inverse md5 guard (no CASCADE, no drop).
-- TESTS: supabase/tests/274_ops_current_aal_empty_claims.sql.
-- ============================================================================
begin;
set local lock_timeout = '3s';

-- ── PRE-FLIGHT: one overload, a known body, 115's posture; capture what the post-flight compares.
-- to_regprocedure, never a '...'::regprocedure literal (the literal is resolved at plan time, even when absent).
do $pf$
declare
  v_md5 text;
  v_n   integer;
  q     record;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'ops'::regnamespace and p.proname = 'current_aal';
  if to_regprocedure('ops.current_aal()') is null or v_n <> 1 then
    raise exception 'MIGRATION_205_REFUSED: expected exactly one ops.current_aal overload, with signature () (overloads %, signature %); nothing changed',
      v_n, case when to_regprocedure('ops.current_aal()') is null then 'absent' else 'present' end;
  end if;
  v_md5 := md5(pg_get_functiondef(to_regprocedure('ops.current_aal()')));
  if v_md5 not in ('33c0f6adc066ddb1bda8e21996cc38ac', '2ea76875ab125648ab5745609f7ed1ef') then
    raise exception 'MIGRATION_205_REFUSED: ops.current_aal() has md5 %, which is neither 115''s body (33c0f6adc066ddb1bda8e21996cc38ac) nor 205''s (2ea76875ab125648ab5745609f7ed1ef); nothing changed',
      v_md5;
  end if;
  select coalesce(p.proacl::text, '<null>') as acl, p.prosecdef, p.proconfig, coalesce(p.proconfig::text, '<null>') as cfg,
         p.proowner::regrole::text as owner, l.lanname as lang, p.provolatile::text as vol,
         p.prorettype::regtype::text as rettype,
         exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public_exec,
         has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
    into q
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = to_regprocedure('ops.current_aal()');
  if not q.prosecdef or q.proconfig is distinct from array['search_path=""'] or q.owner <> 'postgres'
     or q.lang <> 'sql' or q.vol <> 's' or q.rettype <> 'text' then
    raise exception 'MIGRATION_205_REFUSED: ops.current_aal() posture is not 115''s (definer %, proconfig %, owner %, language %, volatility %, returns %); nothing changed',
      q.prosecdef, q.cfg, q.owner, q.lang, q.vol, q.rettype;
  end if;
  if q.public_exec or q.anon_exec or q.auth_exec then
    raise exception 'MIGRATION_205_REFUSED: ops.current_aal() is executable beyond its owner (PUBLIC %, anon %, authenticated %; acl %); nothing changed',
      q.public_exec, q.anon_exec, q.auth_exec, q.acl;
  end if;
  perform set_config('migration_205.preflight',
    jsonb_build_object('md5', v_md5, 'acl', q.acl, 'secdef', q.prosecdef, 'cfg', q.cfg, 'owner', q.owner,
                       'lang', q.lang, 'vol', q.vol, 'rettype', q.rettype)::text, true);
  raise notice '205 pre-flight: ops.current_aal()=% (%)', left(v_md5, 8),
    case v_md5 when '2ea76875ab125648ab5745609f7ed1ef' then 'already 205' else '115 predecessor' end;
end $pf$;

-- ── ops.current_aal(): an empty-string claims GUC reads as absent; malformed non-empty text still raises 22P02.
do $c1$
declare
  v_md5 text := md5(pg_get_functiondef(to_regprocedure('ops.current_aal()')));
begin
  if v_md5 = '2ea76875ab125648ab5745609f7ed1ef' then
    raise notice '205: ops.current_aal() already carries 205''s body; unchanged (re-apply)';
  elsif v_md5 = '33c0f6adc066ddb1bda8e21996cc38ac' then
    execute $def$
create or replace function ops.current_aal()
returns text language sql stable security definer set search_path = ''
as $ops$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'aal';
$ops$
$def$;
    raise notice '205: ops.current_aal() 115 body -> 205 body';
  else
    raise exception 'MIGRATION_205_REFUSED: ops.current_aal() has md5 % (unexpected after the pre-flight); nothing changed', v_md5;
  end if;
end $c1$;

-- ── POST-FLIGHT: 205's md5, and every captured attribute unchanged.
do $pc$
declare
  v_cap jsonb := nullif(current_setting('migration_205.preflight', true), '')::jsonb;
  q     record;
begin
  if v_cap is null then
    raise exception 'POSTFLIGHT_205_FAILED: the pre-flight capture is missing — run this file as one transaction';
  end if;
  select md5(pg_get_functiondef(p.oid)) as md5, coalesce(p.proacl::text, '<null>') as acl, p.prosecdef, p.proconfig,
         coalesce(p.proconfig::text, '<null>') as cfg, p.proowner::regrole::text as owner, l.lanname as lang,
         p.provolatile::text as vol, p.prorettype::regtype::text as rettype,
         (select count(*) from pg_proc x where x.pronamespace = p.pronamespace and x.proname = p.proname) as n,
         has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
         has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_exec
    into q
    from pg_proc p join pg_language l on l.oid = p.prolang
   where p.oid = to_regprocedure('ops.current_aal()');
  if q.md5 is distinct from '2ea76875ab125648ab5745609f7ed1ef' then
    raise exception 'POSTFLIGHT_205_FAILED: ops.current_aal() body md5 % is not 205''s (2ea76875ab125648ab5745609f7ed1ef) — this file was modified',
      coalesce(q.md5, '<absent>');
  end if;
  if q.acl is distinct from v_cap ->> 'acl' then
    raise exception 'POSTFLIGHT_205_FAILED: ops.current_aal() ACL changed from % to %', v_cap ->> 'acl', q.acl;
  end if;
  if q.prosecdef is distinct from (v_cap ->> 'secdef')::boolean or not q.prosecdef then
    raise exception 'POSTFLIGHT_205_FAILED: ops.current_aal() SECURITY DEFINER changed (was %, now %)', v_cap ->> 'secdef', q.prosecdef;
  end if;
  if q.cfg is distinct from v_cap ->> 'cfg' or q.proconfig is distinct from array['search_path=""'] then
    raise exception 'POSTFLIGHT_205_FAILED: ops.current_aal() proconfig changed (was %, now %)', v_cap ->> 'cfg', q.cfg;
  end if;
  if q.owner is distinct from v_cap ->> 'owner' or q.lang is distinct from v_cap ->> 'lang'
     or q.vol is distinct from v_cap ->> 'vol' or q.rettype is distinct from v_cap ->> 'rettype' or q.n <> 1 then
    raise exception 'POSTFLIGHT_205_FAILED: ops.current_aal() owner/language/volatility/return type/overloads changed (owner % -> %, language % -> %, volatility % -> %, returns % -> %, overloads %)',
      v_cap ->> 'owner', q.owner, v_cap ->> 'lang', q.lang, v_cap ->> 'vol', q.vol, v_cap ->> 'rettype', q.rettype, q.n;
  end if;
  if q.anon_exec or q.auth_exec then
    raise exception 'POSTFLIGHT_205_FAILED: ops.current_aal() became executable by anon (%) or authenticated (%)', q.anon_exec, q.auth_exec;
  end if;
  raise notice '205 post-flight: ops.current_aal()=2ea76875 ok (acl %, definer, search_path '''', owner %)', q.acl, q.owner;
end $pc$;

commit;
