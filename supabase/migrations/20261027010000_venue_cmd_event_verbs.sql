-- ============================================================================
-- 20261027010000_venue_cmd_event_verbs.sql — the venue dashboard's ROUTE to the
-- catalog event / session / venue verbs: seven LANGUAGE sql SECURITY INVOKER
-- wrappers in schema venue_cmd, each a one-line delegation to its catalog.*
-- SECURITY DEFINER body. Authority, validation and audit stay in those bodies.
--
-- Registry 164 / pgTAP 231 — assigned by Claude A 2026-10-26 (registry 164/231).
-- Wrapper set ruled by A + F 2026-10-26 (supersedes the first brief): create_event,
-- update_event, create_event_session, update_event_session, publish_event,
-- cancel_event, update_venue. A reviews before this leaves draft. DARK: applied
-- nowhere (local rehearsal clones only); exposes no schema, flips no flag, seeds
-- no config key. venue_cmd stays unexposed (adding it to PostgREST's db-schemas is
-- a separate OWNER step, and per CONTRACTS-D §6 it waits for 165's E-76 conjunct
-- on these catalog bodies before any production exposure). `catalog` is never
-- exposed to a client by this package.
-- ORDER: applies only AFTER 161 (20261022110000, venue_cmd). On the stacked tree it
-- sits after 159 → 176 → 160 → 161 → 162 → 163 → 182; it depends on nothing of
-- 162/163/182 (the guard below checks only venue_cmd and the seven targets).
-- Roll back 164 BEFORE 163/162/161: 161's rollback refuses while venue_cmd holds a
-- function it did not create.
--
-- WHY A ROUTE AND NOT A GRANT. The seven catalog bodies are ALREADY granted
-- EXECUTE to authenticated, by the dynamic loops that created them:
--   catalog.create_event(uuid,text,jsonb,text)        078 PART 7 v_auth (078:1470)
--   catalog.update_event(uuid,jsonb,text)             078 PART 7 v_auth
--   catalog.create_event_session(uuid,jsonb,text)     078 PART 7 v_auth
--   catalog.update_venue(uuid,jsonb,text)             078 PART 7 v_auth (093:5974 body, ACL kept)
--   catalog.update_event_session(uuid,jsonb,text)     079 v_auth (079:762-770; 093:6950 body, ACL kept)
--   catalog.publish_event(uuid,text,text)             081 PART 16 v_auth (081:1086-1097; 102:329 body, ACL kept)
--   catalog.cancel_event(uuid,text,text)              088 PART 8 explicit grant (088:1849)
-- (CREATE OR REPLACE keeps a function's ACL, so the 093/102 body replaces did not
-- move it.) Production ACL, read by A read-only: {postgres=X/postgres,
-- authenticated=X/postgres} — anon, service_role and PUBLIC hold nothing. What
-- the dashboard lacks is only a ROUTE: `catalog` is not a PostgREST-exposed
-- schema. A SECURITY INVOKER wrapper runs as the caller (`authenticated`, who
-- holds USAGE on catalog — 076 — and EXECUTE on each body), so it ADDS NO
-- PRIVILEGE: a caller who could not call catalog.X directly cannot call
-- venue_cmd.X either (231 Section C proves it by revoking the body's EXECUTE and
-- watching the wrapper fail with the body's permission error), every refusal
-- (42501, P0002, the exact precondition_failed / invalid_input text) propagates
-- unchanged, and each audit row is written by the definer body with the same
-- actor (auth.uid()).
--
-- WRAPPERS (identical argument names, types, defaults and result type to the target):
--   venue_cmd.create_event(p_venue_id uuid, p_title text, p_first_session jsonb, p_command_key text) returns jsonb
--   venue_cmd.update_event(p_event_id uuid, p_patch jsonb, p_command_key text) returns jsonb
--   venue_cmd.create_event_session(p_event_id uuid, p_session jsonb, p_command_key text) returns jsonb
--   venue_cmd.update_event_session(p_session_id uuid, p_patch jsonb, p_command_key text) returns jsonb
--   venue_cmd.publish_event(p_event_id uuid, p_target_status text, p_command_key text) returns jsonb
--   venue_cmd.cancel_event(p_event_id uuid, p_reason_code text, p_command_key text) returns jsonb
--   venue_cmd.update_venue(p_venue_id uuid, p_patch jsonb, p_command_key text) returns jsonb
-- NOT ROUTED: catalog.create_venue / approve_venue (platform_admin verbs — no
-- dashboard caller), set_platform_config / set_resale_policy (platform config),
-- catalog.set_session_door_schedule (086:474) — dropped by A + F 2026-10-26: B
-- first fixes its body to RPC §20.6.5 under B's own number (it requires no reason
-- and writes no audit row today — B's known gap, flagged here for B/A); F edits
-- doors through update_event_session's doors_at, which is guarded
-- (boundary_engaged once the door opened, reason_required once atoms exist) and
-- audited. 231 A18 pins the absence of all five.
--
-- WHAT THE ROUTE INHERITS (recorded so 165 and F read the same baseline; 231
-- pins each one through the wrapper as an authenticated operator):
--   * NO E-76 conjunct on the venue_manager arm of create_event, update_event,
--     create_event_session, update_event_session and publish_event (078/079/081/
--     093/102 bodies): the venue_manager of a re-operated room still acts on the
--     FORMER operator's event there. 231 pins it as "STATUS QUO (165 flips)" —
--     package 165 (20261027020000/232) adds the conjunct; these pins are its
--     baseline. cancel_event ALREADY carries it (088:1627-1631) — 231 pins the
--     refusal. update_venue has no event to bind: a venue_manager grant on a
--     re-operated room still edits the room's profile (231: "STATUS QUO (165
--     baseline)"); create_event at such a room stamps the CURRENT operator's org
--     (078:856-868) — same label.
--   * the marketing-only arm of update_event / update_event_session admits
--     venue_marketing (and org_marketing) for description/hero/category/genre /
--     session_label patches — never for title or a time column (078:957-972,
--     093:7010-7023). 231 pins both sides.
--   * update_venue: authority BEFORE the key loop (a fan learns 42501, never the
--     key rules); org_id refused 'precondition_failed: operatorship_transfer_frozen'
--     (Decision C, 093 item 3); audit reason is always 'profile_edit' (093 no
--     longer assigns v_reason, so a patch-carried reason_code is accepted but not
--     recorded). update_event / update_event_session check the unwritable-key set
--     BEFORE authority (T-RPC-CAT-01/02): a fan naming 'status' learns
--     invalid_input. All pinned in 231.
--
-- GRANT DECISIONS (every one — the CI grant gates and the Gate-2 census read
-- `public` only, so pgTAP 231 (this package) and 228 (the schema-wide venue_cmd
-- sweep) are the gate, the 161/163 pattern):
--   each of the seven wrappers  EXECUTE : authenticated ONLY. REVOKE ALL FROM
--                               PUBLIC, anon, authenticated, service_role first (067:
--                               a bare REVOKE FROM PUBLIC is not enough once role
--                               grants exist; service_role named explicitly so a
--                               runner whose default ACL includes it — the local
--                               replay shim's, scripts/local/replay_shim.sql:487-489,
--                               is scoped to public, but the REVOKE does not rely on
--                               that — leaves nothing), then GRANT EXECUTE TO
--                               authenticated. anon: NONE (and no USAGE on venue_cmd,
--                               161). PUBLIC: NONE. service_role: NONE — no
--                               server-side caller; the edges never call these verbs.
--                               No proacl is left DEFAULTED (231 A14, 228 A17).
--   schema venue_cmd            USAGE   : UNCHANGED (161: authenticated only).
--   the seven catalog TARGETS   EXECUTE : UNCHANGED — NO grant, NO revoke, NO body
--                               change here. The post-flight below compares their
--                               ACLs before and after this migration and refuses on
--                               any difference; 231 A15-A17 pin them as exactly
--                               owner (postgres) + authenticated.
--   default privileges                  : none stored (161's reasoning).
--
-- FOUR-FILE RULE (CLAUDE.md): nothing lands in `public`, so no grant-decision
-- manifest row and no expected_grants.txt line (the manifest's B2 fails closed on
-- a row for a function outside public); a dated scope note in the manifest and a
-- dated comment line in the Gate-2 census block record the decision (161/163
-- pattern). Gate-2 census: unchanged. pgTAP census pins that move: venue_cmd
-- functions 14 -> 21 (228 A2/A3/A5-A7/A14-A20/A23, 229 A26, 230 D13 — D's own,
-- edited in this package). Nothing else moves (measured: full suite on the clone,
-- EVIDENCE-164.md). Rollback:
-- supabase/rollbacks/20261027010000_venue_cmd_event_verbs_rollback.sql — drops the
-- seven wrappers (IF EXISTS, idempotent, rc 0); nothing else to restore. Since A's
-- N2 it refuses (G1) a wrapper whose body is not 164's and (G2/G2b) while any other
-- object or function body calls one of them.
-- PRE-FLIGHT (A's N1): section 0b refuses a foreign object under any of the seven
-- names; 164's own wrappers re-apply (rc 0).
--
-- VERIFICATION (after apply):
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='venue_cmd';   -- 21 (was 14)
--   select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
--    where n.nspname='venue_cmd' and not p.prosecdef and l.lanname='sql';                                       -- 21
--   select p.proname, p.proacl from pg_proc p join pg_namespace n on n.oid=p.pronamespace
--    where n.nspname='catalog' and p.proname in ('create_event','update_event','create_event_session',
--          'update_event_session','publish_event','cancel_event','update_venue') order by 1;                    -- each {postgres=X/postgres,authenticated=X/postgres}
-- LOCKS / RUNTIME: CREATE FUNCTION / GRANT on seven new functions only; no table,
-- no existing function, no row is touched.
-- ============================================================================
BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Order guard + the targets' shape, and a snapshot of the targets' ACLs
--    (transaction-local GUC) for the post-flight comparison.
-- ---------------------------------------------------------------------------
do $$
declare
  v_missing text;
  v_acl     text;
begin
  if not exists (select 1 from pg_namespace where nspname = 'venue_cmd') then
    raise exception 'ORDER_164_REFUSED: schema venue_cmd (161, 20261022110000) is absent; apply 160 then 161 first';
  end if;
  select string_agg(t.sig, ', ' order by t.sig) into v_missing
    from (values ('catalog.create_event(uuid,text,jsonb,text)'),
                 ('catalog.update_event(uuid,jsonb,text)'),
                 ('catalog.create_event_session(uuid,jsonb,text)'),
                 ('catalog.update_event_session(uuid,jsonb,text)'),
                 ('catalog.publish_event(uuid,text,text)'),
                 ('catalog.cancel_event(uuid,text,text)'),
                 ('catalog.update_venue(uuid,jsonb,text)')) t(sig)
   where to_regprocedure(t.sig) is null
      or pg_get_function_result(to_regprocedure(t.sig)) <> 'jsonb'
      or not (select p.prosecdef from pg_proc p where p.oid = to_regprocedure(t.sig));
  if v_missing is not null then
    raise exception 'ORDER_164_REFUSED: catalog target(s) absent or not a jsonb SECURITY DEFINER body: %', v_missing;
  end if;
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, 'DEFAULTED'), ';' order by p.proname) into v_acl
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'catalog'
     and p.proname in ('create_event','update_event','create_event_session','update_event_session',
                       'publish_event','cancel_event','update_venue');
  perform set_config('d164.target_acl_before', v_acl, true);
end $$;

-- ---------------------------------------------------------------------------
-- 0b. PRE-FLIGHT (A's N1, review of 164-167/165, 2026-10-27; 163's pattern). Each of
--     the seven names must be ABSENT from venue_cmd (first apply) or be exactly
--     164's own wrapper (re-apply): ONE function by that name, md5(prosrc) = 164's,
--     LANGUAGE sql, SECURITY INVOKER, proconfig = search_path="". Anything else — a
--     foreign body, a SECURITY DEFINER plant carrying its own grants (A's case: a
--     definer venue_cmd.update_event with EXECUTE to anon, which CREATE OR REPLACE
--     used to overwrite silently), an overload — is refused with
--       MIGRATION_164_REFUSED (pre-flight): venue_cmd.<name> exists and is not 164's own wrapper (...); nothing changed
--     (one transaction; psql -v ON_ERROR_STOP=1 exits 3). md5s are PG17 values
--     (local clone = CI = production major); a change to a wrapper body re-hashes it
--     here and in the rollback.
-- ---------------------------------------------------------------------------
DO $pre164$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT e.fname, e.h164,
           (SELECT count(*) FROM pg_proc p WHERE p.pronamespace = 'venue_cmd'::regnamespace AND p.proname = e.fname) AS n_by_name,
           (SELECT string_agg(md5(p.prosrc) || '/' || l.lanname || '/' || p.prosecdef::text || '/' || coalesce(array_to_string(p.proconfig, ','), '-'), ' ')
              FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
             WHERE p.pronamespace = 'venue_cmd'::regnamespace AND p.proname = e.fname) AS got
      FROM (VALUES
              ('create_event', '449f43e0aacc02c970ae44e179d547e4'),
              ('update_event', '8e556d5ca13ec261134a04cdfb5c6b26'),
              ('create_event_session', '41f8b55a70e1ea6698d5b1e654ea25d7'),
              ('update_event_session', '8f8eeaca4d1d74c805e123ef90b8e340'),
              ('publish_event', '09fd6c26f49316411bacea7797b206bd'),
              ('cancel_event', '09b321729670af3113ea22babf02b329'),
              ('update_venue', '164862649cd50f3bbfa1bfbe38dcc584')
           ) AS e(fname, h164)
  LOOP
    CONTINUE WHEN r.n_by_name = 0;
    IF r.n_by_name > 1 OR r.got IS DISTINCT FROM (r.h164 || '/sql/false/search_path=""') THEN
      RAISE EXCEPTION 'MIGRATION_164_REFUSED (pre-flight): venue_cmd.% exists and is not 164''s own wrapper (% by name: %); nothing changed', r.fname, r.n_by_name, r.got;
    END IF;
  END LOOP;
END $pre164$;

-- ---------------------------------------------------------------------------
-- 1. The seven wrappers. One SELECT each; argument names/types and the result
--    type are the target's (231 A6-A9 pin both against pg_catalog, and the body
--    text against 'select catalog.<same name>(<same arguments>)').
-- ---------------------------------------------------------------------------
create or replace function venue_cmd.create_event(
  p_venue_id uuid, p_title text, p_first_session jsonb, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.create_event(p_venue_id, p_title, p_first_session, p_command_key)
$$;
comment on function venue_cmd.create_event(uuid, text, jsonb, text) is
  '164: invoker wrapper -> catalog.create_event (078:829). Born draft; venue must be approved; first session needs starts_at.';

create or replace function venue_cmd.update_event(
  p_event_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.update_event(p_event_id, p_patch, p_command_key)
$$;
comment on function venue_cmd.update_event(uuid, jsonb, text) is
  '164: invoker wrapper -> catalog.update_event (078:901). Keys: title, description, hero_image_ref, category, genre_tags, reason_code.';

create or replace function venue_cmd.create_event_session(
  p_event_id uuid, p_session jsonb, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.create_event_session(p_event_id, p_session, p_command_key)
$$;
comment on function venue_cmd.create_event_session(uuid, jsonb, text) is
  '164: invoker wrapper -> catalog.create_event_session (078:749). session_label, starts_at (required), ends_at, doors_at.';

create or replace function venue_cmd.update_event_session(
  p_session_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.update_event_session(p_session_id, p_patch, p_command_key)
$$;
comment on function venue_cmd.update_event_session(uuid, jsonb, text) is
  '164: invoker wrapper -> catalog.update_event_session (093:6950). Keys: session_label, starts_at, ends_at, doors_at, reason_code.';

create or replace function venue_cmd.publish_event(
  p_event_id uuid, p_target_status text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.publish_event(p_event_id, p_target_status, p_command_key)
$$;
comment on function venue_cmd.publish_event(uuid, text, text) is
  '164: invoker wrapper -> catalog.publish_event (102:329). Forward transitions only; on_sale gates intact.';

create or replace function venue_cmd.cancel_event(
  p_event_id uuid, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.cancel_event(p_event_id, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.cancel_event(uuid, text, text) is
  '164: invoker wrapper -> catalog.cancel_event (088:1612). Void+refund cascade; venue arm already E-76-bound.';

create or replace function venue_cmd.update_venue(
  p_venue_id uuid, p_patch jsonb, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select catalog.update_venue(p_venue_id, p_patch, p_command_key)
$$;
comment on function venue_cmd.update_venue(uuid, jsonb, text) is
  '164: invoker wrapper -> catalog.update_venue (093:5974). Keys: name, neighborhood, address, capacity_hint, org_id (refused: operatorship_transfer_frozen), reason_code.';

-- ---------------------------------------------------------------------------
-- 2. ACLs: strip PUBLIC/anon/authenticated/service_role, grant exactly authenticated
-- ---------------------------------------------------------------------------
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue_cmd.create_event(uuid, text, jsonb, text)',
    'venue_cmd.update_event(uuid, jsonb, text)',
    'venue_cmd.create_event_session(uuid, jsonb, text)',
    'venue_cmd.update_event_session(uuid, jsonb, text)',
    'venue_cmd.publish_event(uuid, text, text)',
    'venue_cmd.cancel_event(uuid, text, text)',
    'venue_cmd.update_venue(uuid, jsonb, text)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- 3. Post-flight: the seven wrappers' posture, and the targets' ACLs unchanged.
-- ---------------------------------------------------------------------------
do $$
declare
  v_bad   text;
  v_after text;
begin
  select string_agg(w.proname, ', ' order by w.proname) into v_bad
    from pg_proc w
    join pg_namespace n on n.oid = w.pronamespace
    join pg_language l on l.oid = w.prolang
   where n.nspname = 'venue_cmd'
     and w.proname in ('create_event','update_event','create_event_session','update_event_session',
                       'publish_event','cancel_event','update_venue')
     and not (    not w.prosecdef
              and l.lanname = 'sql'
              and w.proconfig = array['search_path=""']
              and w.proacl is not null
              and has_function_privilege('authenticated', w.oid, 'EXECUTE')
              and not has_function_privilege('anon', w.oid, 'EXECUTE')
              and not has_function_privilege('service_role', w.oid, 'EXECUTE')
              and not exists (select 1 from aclexplode(w.proacl) a where a.grantee = 0));
  if v_bad is not null then
    raise exception 'POSTFLIGHT_164_FAILED: wrapper posture wrong for: %', v_bad;
  end if;
  if (select count(*) from pg_proc w join pg_namespace n on n.oid = w.pronamespace
       where n.nspname = 'venue_cmd'
         and w.proname in ('create_event','update_event','create_event_session','update_event_session',
                           'publish_event','cancel_event','update_venue')) <> 7 then
    raise exception 'POSTFLIGHT_164_FAILED: expected exactly seven 164 wrappers in venue_cmd';
  end if;
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, 'DEFAULTED'), ';' order by p.proname) into v_after
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'catalog'
     and p.proname in ('create_event','update_event','create_event_session','update_event_session',
                       'publish_event','cancel_event','update_venue');
  if v_after is distinct from current_setting('d164.target_acl_before', true) then
    raise exception 'POSTFLIGHT_164_FAILED: a catalog target ACL changed (before % / after %)',
      current_setting('d164.target_acl_before', true), v_after;
  end if;
end $$;

COMMIT;
