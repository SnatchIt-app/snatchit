-- ============================================================================
-- 20261030210000_ops_money_config_requests.sql — registry 196 / pgTAP 265.
-- D writes and owns; A allocated 2026-10-30 (owner-directed sprint work); E reviews. DARK: applied nowhere.
-- The stem is the first whole minute after 21:00 that sorts after 194's 20261030094200 and whose 14 digits
-- are not Luhn-valid, so the scanner's card rule never fires on it.
--
-- WHAT THIS MIGRATION IS. Additive only: three NEW functions in schema `ops`, nothing replaced, nothing in
-- `public`, no table, no grant beyond EXECUTE on the new functions to `authenticated`. It gives the production
-- admin console an API path for the money-key dual-control flow that already exists in the kernel:
--   * REQUEST — catalog.set_platform_config (188) parks a loosening of a money key as kernel.approval_request
--     'config.set_money_key', but `catalog` is not exposed to PostgREST in production (owner decision: never
--     expose it), so the console has no way to call it.
--   * LIST    — kernel.list_approval_requests (085) requires p_org_id NOT NULL, and money-key requests are
--     platform-scoped (org_id IS NULL by CHECK), so they cannot be listed.
--   * APPROVE — kernel.approve_refund_request (085) already decides 'config.set_money_key' (a second, distinct
--     platform_admin; aal2 to approve) and is exposed to `authenticated`. Nothing is added for it here; the
--     console calls it directly.
--
-- THE THREE FUNCTIONS
--   ops.money_config_key(p_key)  IMMUTABLE predicate: is p_key in the dual-control namespaces that
--       catalog.set_platform_config parks? Its expression is set_platform_config's `v_dual` assignment, verbatim
--       (pgTAP 265 D1 compares the two texts, so a change to either fails CI instead of drifting).
--   ops.request_platform_config(p_key, p_value, p_reason_code, p_command_key)  SECURITY INVOKER. It runs with
--       the caller's own privileges, so it can never do more than the caller could already do: `authenticated`
--       already holds USAGE on catalog and EXECUTE on catalog.set_platform_config (076/078; the pre-flight
--       asserts both). It only NARROWS that path, adding:
--         platform_admin (via ops.actor_role) + an aal2 session (the console's step-up idiom, as
--         ops.assert_reader) + money keys only (ops.money_config_key).
--       It then returns catalog.set_platform_config(...) unchanged. That function records requested_by =
--       auth.uid() (the caller), parks a loosening for a second admin, and applies a tightening at once (the
--       frozen RPC §20.2.1 rule: one human may tighten, loosening takes two). Inline checks rather than
--       ops.assert_role: that helper is not granted to `authenticated`, and an INVOKER function runs with the
--       caller's privileges.
--   ops.list_config_approvals(p_state)  SECURITY DEFINER read, gated by ops.assert_role(platform_admin) (aal2).
--       It returns {items, next_cursor: null, count_hint, state, money_keys}:
--         * items: kernel.approval_request rows with action = 'config.set_money_key', newest first, at most
--           200. Each carries the key, the proposed value, the value and version pinned at request time, the
--           live version and value, key_changed_since_request, state, is_expired, reason_code, expires_at and
--           timestamps. People appear as ids only (requested_by, decided_by) plus requested_by_me / can_decide
--           for the caller: no emails, no labels.
--         * money_keys: the latest version and value of every key for which ops.money_config_key is true, so
--           the request form offers real keys with their current values.
--
-- NOT CHANGED, RECORDED:
--   * The console-wide pause (ops.setting actions_enabled) governs ops.action mutations. This path is the
--     kernel's dual-control flow and is not paused by it (ops.assert_actions_enabled is not granted to
--     `authenticated`). Open question for A/owner.
--   * kernel.approve_refund_request's config arm writes the parked proposed_value without re-validating it or
--     checking that the key is still at the pinned version (also recorded in 188's header). The list exposes
--     key_changed_since_request so the deciding admin sees it.
--
-- GRANTS / FOUR-FILE RULE. The CI grant gates (grant-decision manifest, expected_grants, Gate-2 census) read
-- `public` only. Three `ops` functions add no manifest row, no expected_grants line, and Gate-2 +0 (a dated
-- note in ci.yml). Rollback: supabase/rollbacks/20261030210000_ops_money_config_requests_rollback.sql drops
-- the three functions under an inverse md5 guard; before 196 none of them existed.
--
-- MD5 — md5(pg_get_functiondef(...)), measured on a local PG17 replay (a154c_green + main 517ad393 + 196):
--   ops.money_config_key(text)                         6a6c96d328b248bbf031964d61da7ed3
--   ops.request_platform_config(text,jsonb,text,text)  bc80b674d67d0a14e6b5416d9a234c99
--   ops.list_config_approvals(text)                    59ed8b127bfddb9136f0fdd07408a98d
-- The pre-flight accepts each function absent (first apply) or at its own md5 (idempotent re-apply). It also
-- requires catalog.set_platform_config at 188's body (2ece44b98c73af1e8c2b5d930b0a5895), the body whose
-- `v_dual` and parking this migration relies on.
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
    raise exception 'MIGRATION_196_REFUSED: catalog.set_platform_config body md5 % is not 188''s — its v_dual/parking may have changed; re-examine 196', v_md5;
  end if;
  if not has_schema_privilege('authenticated', 'catalog', 'USAGE')
     or not has_function_privilege('authenticated', 'catalog.set_platform_config(text,jsonb,text,text)', 'EXECUTE') then
    raise exception 'MIGRATION_196_REFUSED: authenticated lacks USAGE on catalog or EXECUTE on catalog.set_platform_config — the INVOKER request path cannot work';
  end if;
  if not has_function_privilege('authenticated', 'ops.actor_role()', 'EXECUTE') then
    raise exception 'MIGRATION_196_REFUSED: authenticated lacks EXECUTE on ops.actor_role()';
  end if;
  -- to_regprocedure, never a '...'::regprocedure literal: the literal cast is resolved even when the
  -- function is absent, which would refuse every first apply.
  for r in
    select * from (values
      ('ops.money_config_key(text)',                        '6a6c96d328b248bbf031964d61da7ed3'),
      ('ops.request_platform_config(text,jsonb,text,text)', 'bc80b674d67d0a14e6b5416d9a234c99'),
      ('ops.list_config_approvals(text)',                   '59ed8b127bfddb9136f0fdd07408a98d')
    ) as t(sig, want_md5)
  loop
    v_md5 := md5(pg_get_functiondef(to_regprocedure(r.sig)));
    if v_md5 is not null and v_md5 <> r.want_md5 then
      raise exception 'MIGRATION_196_REFUSED: a foreign % exists (md5 %)', r.sig, v_md5;
    end if;
  end loop;
end $pf$;

-- ── ops.money_config_key — set_platform_config's v_dual, verbatim (p_key is the same parameter name there).
create or replace function ops.money_config_key(p_key text)
returns boolean
language sql
immutable
set search_path = ''
as $ops$
  select p_key like 'refund.%' or p_key like 'payout.%' or p_key like 'authn.%'
         or p_key like 'comp.%'   or p_key like 'wallet.%' or p_key like 'credential.%'
         or p_key like 'door.session\_%' or p_key like 'fee.%'
         or p_key like 'deletion.%' or p_key like 'ticket.%'
         or p_key = 'signing.expected_key_fingerprint' or p_key = 'signing.expected_max_not_after';
$ops$;
revoke all on function ops.money_config_key(text) from public, anon, authenticated;
grant execute on function ops.money_config_key(text) to authenticated;

-- ── ops.request_platform_config — INVOKER passthrough; narrows, never widens.
create or replace function ops.request_platform_config(
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
    raise exception 'insufficient_privilege: platform_admin required (ops.request_platform_config)' using errcode = '42501';
  end if;
  -- nullif: after a logout the claims GUC reads '' (not NULL), which is not valid jsonb.
  v_aal := coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb ->> 'aal';
  if v_aal is null then
    raise exception 'step_up_unavailable: the session carries no aal claim';
  end if;
  if v_aal <> 'aal2' then
    raise exception 'step_up_required: an aal2 (MFA) session is required to request a money setting change';
  end if;
  if p_key is null or not ops.money_config_key(p_key) then
    raise exception 'invalid_input: % is not a dual-control money key — this path requests money keys only',
      coalesce(p_key, '<null>');
  end if;
  return catalog.set_platform_config(p_key, p_value, p_reason_code, p_command_key);
end;
$ops$;
revoke all on function ops.request_platform_config(text, jsonb, text, text) from public, anon, authenticated;
grant execute on function ops.request_platform_config(text, jsonb, text, text) to authenticated;

-- ── ops.list_config_approvals — platform-scoped read of the money-key requests (+ the money keys).
create or replace function ops.list_config_approvals(p_state text default 'pending')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $ops$
declare
  v_state text := coalesce(nullif(p_state, ''), 'pending');
  v_uid   uuid := auth.uid();
  v_items jsonb;
  v_keys  jsonb;
begin
  perform ops.assert_role(array['platform_admin']);
  if v_state not in ('pending','approved','denied','expired','stale','cancelled','all') then
    raise exception 'invalid_input: state must be pending|approved|denied|expired|stale|cancelled|all';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
           'request_id',                ar.request_id,
           'key',                       ar.payload ->> 'key',
           'proposed_value',            ar.payload -> 'proposed_value',
           'value_at_request',          ar.payload -> 'current_value',
           'version_at_request',        (ar.config_versions ->> (ar.payload ->> 'key'))::integer,
           'live_version',              lv.version,
           'live_value',                lv.value,
           'key_changed_since_request', lv.version is distinct from (ar.config_versions ->> (ar.payload ->> 'key'))::integer,
           'state',                     ar.state,
           'is_expired',                ar.expires_at <= now(),
           'reason_code',               ar.reason_code,
           'requested_by',              ar.requested_by,
           'decided_by',                ar.approved_by,
           'requested_by_me',           ar.requested_by = v_uid,
           'can_decide',                ar.state = 'pending' and ar.expires_at > now() and ar.requested_by <> v_uid,
           'expires_at',                ar.expires_at,
           'created_at',                ar.created_at,
           'updated_at',                ar.updated_at)
         order by ar.created_at desc, ar.request_id desc), '[]'::jsonb)
    into v_items
    from (select a.* from kernel.approval_request a
           where a.action = 'config.set_money_key'
             and (v_state = 'all' or a.state = v_state)
           order by a.created_at desc, a.request_id desc
           limit 200) ar
    left join lateral (select c.version, c.value from catalog.platform_config c
                        where c.key = ar.payload ->> 'key'
                        order by c.version desc limit 1) lv on true;
  select coalesce(jsonb_agg(jsonb_build_object('key', k.key, 'version', k.version, 'value', k.value)
                            order by k.key), '[]'::jsonb)
    into v_keys
    from (select distinct on (c.key) c.key, c.version, c.value
            from catalog.platform_config c
           where ops.money_config_key(c.key)
           order by c.key, c.version desc) k;
  return jsonb_build_object('items', v_items, 'next_cursor', null,
                            'count_hint', jsonb_array_length(v_items), 'state', v_state,
                            'money_keys', v_keys);
end;
$ops$;
revoke all on function ops.list_config_approvals(text) from public, anon, authenticated;
grant execute on function ops.list_config_approvals(text) to authenticated;

-- ── POST-APPLY SELF-CHECK: bodies, posture, ACL, owner.
do $pc$
declare
  r record;
  v_acl text;
begin
  for r in
    select * from (values
      ('ops.money_config_key(text)',                        '6a6c96d328b248bbf031964d61da7ed3',  false),
      ('ops.request_platform_config(text,jsonb,text,text)', 'bc80b674d67d0a14e6b5416d9a234c99',  false),
      ('ops.list_config_approvals(text)',                   '59ed8b127bfddb9136f0fdd07408a98d', true)
    ) as t(sig, want_md5, want_definer)
  loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.want_md5 then
      raise exception 'POSTFLIGHT_196_FAILED: % body md5 % is not 196''s — this file was modified',
        r.sig, md5(pg_get_functiondef(r.sig::regprocedure));
    end if;
    select string_agg(e.entry, ',' order by e.entry) into v_acl
      from pg_proc p,
           lateral (select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end
                           || ':' || a.privilege_type as entry
                      from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a) e
     where p.oid = r.sig::regprocedure;
    if v_acl <> 'authenticated:EXECUTE,postgres:EXECUTE' then
      raise exception 'POSTFLIGHT_196_FAILED: % ACL is %, not authenticated + postgres EXECUTE', r.sig, v_acl;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = r.sig::regprocedure
                      and p.prosecdef = r.want_definer
                      and p.proconfig = array['search_path=""']
                      and p.proowner = 'postgres'::regrole) then
      raise exception 'POSTFLIGHT_196_FAILED: % posture (definer %, search_path '''', owner postgres) not as decided',
        r.sig, r.want_definer;
    end if;
  end loop;
end $pc$;

commit;
