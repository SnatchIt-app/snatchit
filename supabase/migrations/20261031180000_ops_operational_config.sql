-- ============================================================================
-- 20261031180000_ops_operational_config.sql — registry 197 / pgTAP 266.
-- D writes and owns; A allocated 2026-10-31 (stem validated by A: a real timestamp, not Luhn-valid); E reviews.
-- DARK: applied nowhere. Spec: planning/2026-10-26-launch/A/RECONCILE-HOLDS-EXPIRY-20261031.md §1.
--
-- THE GAP. Four platform keys are single-admin BY DESIGN — catalog.set_platform_config writes them directly for one
-- platform_admin; they are not in its dual-control `v_dual`:
--   inventory.per_user_active_hold_max  (the per-buyer hold cap; unset => every reserve refused)
--   inventory.hold_ttl_interval         (the hold lifetime; unset => hold_ttl_unset)
--   feature.native_issuance_enabled     (the Stage 8 flip AND the runbook's sales kill switch)
--   feature.native_scanning_enabled     (the Stage 8 flip)
-- In production none of them has a lawful client path: `catalog` is not exposed (owner: never), and
-- ops.request_platform_config (196) refuses every key that is not a money key. So today neither the hold settings
-- nor the kill switch can be set from the console.
--
-- WHAT THIS MIGRATION IS. Additive only: two NEW functions in schema `ops`, nothing replaced, nothing in `public`,
-- no table, no grant beyond EXECUTE on the two to `authenticated`. It sets NO value: reachability only. Setting a
-- flag or a hold value stays a separate owner GO, done through the console after this ships.
--   ops.set_operational_config(p_key, p_value, p_reason_code, p_command_key)  SECURITY INVOKER passthrough to
--       catalog.set_platform_config. It runs with the caller's own privileges (`authenticated` already holds USAGE
--       on catalog and EXECUTE on set_platform_config — the pre-flight asserts both), so it can only NARROW that
--       path. Its gates, in order:
--         1. a session (auth.uid);
--         2. platform_admin (via ops.actor_role; the message names this function);
--         3. an aal2 session (the nullif read — after a logout the claims GUC is '', not NULL). This is aal2 ON
--            THIS PATH only: catalog.set_platform_config itself has no aal check, so nothing here makes a key
--            (the kill switch included) "require aal2" anywhere else;
--         4. a refusal of any dual-control money key (ops.money_config_key, 196). Defence in depth only: the
--            allow-list already excludes them, and set_platform_config's own v_dual parking still applies
--            underneath — this check is not a substitute for it. Money keys go through
--            ops.request_platform_config and a second founder;
--         5. the explicit allow-list of the four keys above.
--       It then returns catalog.set_platform_config(...) unchanged, which keeps its own platform_admin check,
--       per-key validation (hold max a JSON integer >= 1; TTL a parseable interval string, a bare number refused),
--       the type witness (flags stay booleans), the admin_audit row (actor = the caller) and noop_replay on an
--       equal value.
--   ops.list_operational_config()  SECURITY DEFINER read, gated by ops.assert_role(platform_admin) (aal2): the
--       same four keys with their live version, value, effective_from and created_at, so the console can show each
--       key's live value. `authenticated` cannot read catalog.platform_config itself.
--   The allow-list is written out in both bodies. pgTAP 266 X1 proves they are the same set: over EVERY seeded
--   key, the setter accepts the key (as a no-op write of its live value) exactly when the list returns it.
--
-- GRANTS / FOUR-FILE RULE. The CI grant gates (grant-decision manifest, expected_grants, Gate-2 census) read
-- `public` only, so two `ops` functions add no manifest row, no expected_grants line, and Gate-2 +0 (a dated note in
-- ci.yml; the same as 115-118, 188 and 196). Rollback:
-- supabase/rollbacks/20261031180000_ops_operational_config_rollback.sql drops the two functions under an inverse md5
-- guard; before 197 neither existed.
--
-- MD5 — md5(pg_get_functiondef(...)), measured on a local PG17 replay (a154c_green + main 7496fee3 + 197):
--   ops.set_operational_config(text,jsonb,text,text)  994691ae418af4cc3b79bac3912ebe8b
--   ops.list_operational_config()                     a0415b34eb17f66b9698d63aa83d7b5c
-- The pre-flight accepts each function absent (first apply) or at its own md5 (idempotent re-apply). It also
-- requires catalog.set_platform_config at 188's body (2ece44b98c73af1e8c2b5d930b0a5895) and ops.money_config_key at
-- 196's (6a6c96d328b248bbf031964d61da7ed3) — the two bodies this path relies on.
-- ============================================================================
begin;

-- ── PRE-FLIGHT
do $pf$
declare
  v_md5 text;
  r     record;
begin
  v_md5 := md5(pg_get_functiondef('catalog.set_platform_config(text,jsonb,text,text)'::regprocedure));
  if v_md5 <> '2ece44b98c73af1e8c2b5d930b0a5895' then
    raise exception 'MIGRATION_197_REFUSED: catalog.set_platform_config body md5 % is not 188''s — its validation/v_dual may have changed; re-examine 197', v_md5;
  end if;
  v_md5 := md5(pg_get_functiondef(to_regprocedure('ops.money_config_key(text)')));
  if v_md5 is distinct from '6a6c96d328b248bbf031964d61da7ed3' then
    raise exception 'MIGRATION_197_REFUSED: ops.money_config_key(text) is absent or not 196''s body (md5 %) — apply 196 first', coalesce(v_md5, '<absent>');
  end if;
  if not has_schema_privilege('authenticated', 'catalog', 'USAGE')
     or not has_function_privilege('authenticated', 'catalog.set_platform_config(text,jsonb,text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'ops.actor_role()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'ops.money_config_key(text)', 'EXECUTE') then
    raise exception 'MIGRATION_197_REFUSED: authenticated lacks a grant the INVOKER path needs (catalog USAGE, set_platform_config, ops.actor_role or ops.money_config_key EXECUTE)';
  end if;
  -- to_regprocedure, never a '...'::regprocedure literal: the literal is resolved even when the function is absent
  for r in
    select * from (values
      ('ops.set_operational_config(text,jsonb,text,text)', '994691ae418af4cc3b79bac3912ebe8b'),
      ('ops.list_operational_config()',                    'a0415b34eb17f66b9698d63aa83d7b5c')
    ) as t(sig, want_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is not null and v_md5 <> r.want_md5 then
      raise exception 'MIGRATION_197_REFUSED: a foreign % exists (md5 %)', r.sig, v_md5;
    end if;
  end loop;
end $pf$;

-- ── ops.set_operational_config — INVOKER passthrough for the four single-admin keys; narrows, never widens.
create or replace function ops.set_operational_config(
  p_key text, p_value jsonb, p_reason_code text, p_command_key text)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $ops$
declare
  v_aal text;
begin
  if auth.uid() is null then
    raise exception 'insufficient_privilege: authentication required' using errcode = '42501';
  end if;
  -- named in the message so a refusal here is distinguishable from set_platform_config's own gate
  if ops.actor_role() is distinct from 'platform_admin' then
    raise exception 'insufficient_privilege: platform_admin required (ops.set_operational_config)' using errcode = '42501';
  end if;
  -- nullif: after a logout the claims GUC reads '' (not NULL), which is not valid jsonb.
  v_aal := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: an aal2 (MFA) session is required to change an operational setting';
  end if;
  -- defensive: a dual-control money key never takes the single-admin path, whatever the allow-list below says
  if p_key is not null and ops.money_config_key(p_key) then
    raise exception 'invalid_input: % is a dual-control money key — request it through ops.request_platform_config (a second founder decides)', p_key;
  end if;
  if p_key is null or p_key not in ('inventory.per_user_active_hold_max', 'inventory.hold_ttl_interval',
                                    'feature.native_issuance_enabled', 'feature.native_scanning_enabled') then
    raise exception 'invalid_input: % is not an operational setting this path may change', coalesce(p_key, '<null>');
  end if;
  return catalog.set_platform_config(p_key, p_value, p_reason_code, p_command_key);
end;
$ops$;
revoke all on function ops.set_operational_config(text, jsonb, text, text) from public, anon, authenticated;
grant execute on function ops.set_operational_config(text, jsonb, text, text) to authenticated;

-- ── ops.list_operational_config — the same four keys' live values, for the console form.
create or replace function ops.list_operational_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $ops$
declare
  v_items jsonb;
begin
  perform ops.assert_role(array['platform_admin']);
  select coalesce(jsonb_agg(jsonb_build_object(
           'key',            k.key,
           'version',        lv.version,
           'value',          lv.value,
           'effective_from', lv.effective_from,
           'created_at',     lv.created_at)
         order by k.ord), '[]'::jsonb)
    into v_items
    from (values (1, 'inventory.per_user_active_hold_max'), (2, 'inventory.hold_ttl_interval'),
                 (3, 'feature.native_issuance_enabled'),    (4, 'feature.native_scanning_enabled')) as k(ord, key)
    left join lateral (select c.version, c.value, c.effective_from, c.created_at
                         from catalog.platform_config c
                        where c.key = k.key
                        order by c.version desc limit 1) lv on true;
  return jsonb_build_object('items', v_items, 'next_cursor', null, 'count_hint', jsonb_array_length(v_items));
end;
$ops$;
revoke all on function ops.list_operational_config() from public, anon, authenticated;
grant execute on function ops.list_operational_config() to authenticated;

-- ── POST-APPLY SELF-CHECK: bodies, posture, ACL, owner.
do $pc$
declare
  r     record;
  v_acl text;
begin
  for r in
    select * from (values
      ('ops.set_operational_config(text,jsonb,text,text)', '994691ae418af4cc3b79bac3912ebe8b',  false),
      ('ops.list_operational_config()',                    'a0415b34eb17f66b9698d63aa83d7b5c', true)
    ) as t(sig, want_md5, want_definer)
  loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.want_md5 then
      raise exception 'POSTFLIGHT_197_FAILED: % body md5 % is not 197''s — this file was modified',
        r.sig, md5(pg_get_functiondef(r.sig::regprocedure));
    end if;
    select string_agg(e.entry, ',' order by e.entry) into v_acl
      from pg_proc p,
           lateral (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                           || ':' || a.privilege_type as entry
                      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) e
     where p.oid = r.sig::regprocedure;
    if v_acl <> 'authenticated:EXECUTE,postgres:EXECUTE' then
      raise exception 'POSTFLIGHT_197_FAILED: % ACL is %, not authenticated + postgres EXECUTE', r.sig, v_acl;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = r.sig::regprocedure
                      and p.prosecdef = r.want_definer
                      and p.proconfig = array['search_path=""']
                      and p.proowner = 'postgres'::regrole) then
      raise exception 'POSTFLIGHT_197_FAILED: % posture (definer %, search_path '''', owner postgres) not as decided',
        r.sig, r.want_definer;
    end if;
  end loop;
end $pc$;

commit;
