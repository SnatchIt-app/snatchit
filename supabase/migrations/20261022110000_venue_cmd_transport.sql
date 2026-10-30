-- ============================================================================
-- 20261022110000_venue_cmd_transport.sql — the venue dashboard's COMMAND
-- transport: schema `venue_cmd` holding SECURITY INVOKER wrappers that delegate
-- to the venue.* definer RPCs. Authority stays in the definer bodies.
--
-- Registry 161 / pgTAP 228 — assigned by Claude A 2026-10-22 (registry 573850a4).
-- A reviews before this leaves draft. DARK: applied nowhere (local rehearsal
-- clones only); exposes nothing. Adding `venue_cmd` to PostgREST's exposed
-- schemas (db-schemas) is a separate, OWNER-approved configuration step and is
-- NOT in this migration. `venue_api` stays views-only (226 A3 pins zero
-- functions there) and `venue` is never exposed.
-- ORDER (registry 573850a4): applies only AFTER 160 (20261022100000) — the
-- wrappers call venue.set_ticket_type_visibility, set_ticket_type_rank and
-- get_inventory_counters, created there.
--
-- TRANSPORT RULING (A, 2026-10-22): a separate venue_cmd schema of SECURITY
-- INVOKER wrappers — confirmed. Why a separate schema and not functions in
-- venue_api: 226 A3 asserts venue_api has no function (no definer surface in the
-- read schema) and the owner's exposure setting is per schema, so reads and
-- commands can be exposed independently. Why SECURITY INVOKER: the wrapper runs
-- as the caller (`authenticated`, who already holds USAGE on venue — 076:78 — and
-- EXECUTE on the venue.* RPCs — 081 PART 16, 160 PART 7), so it adds no
-- privilege: every refusal (42501, P0002, precondition_failed) propagates
-- unchanged from the definer body, and the audit row is written by that body
-- with the same actor. The wrappers hold no logic (LANGUAGE sql, one SELECT).
--
-- WRAPPERS (identical argument lists and result types to their targets):
--   venue_cmd.create_ticket_type(uuid, text, text, integer, text, text)  -> venue.create_ticket_type
--   venue_cmd.set_ticket_type_price(uuid, integer, text, text)           -> venue.set_ticket_type_price
--   venue_cmd.set_ticket_type_visibility(uuid, text, text, text)         -> venue.set_ticket_type_visibility (160)
--   venue_cmd.set_ticket_type_rank(uuid, smallint, text)                 -> venue.set_ticket_type_rank (160)
--   venue_cmd.set_batch_capacity(uuid, integer, text, text)              -> venue.set_batch_capacity
--   venue_cmd.get_inventory_counters(uuid) returns table(...)            -> venue.get_inventory_counters (160)
-- WITHHELD: venue_cmd.create_inventory_batch — waits for S2's E-33 receipt
-- (S1_slice.json "EXCLUDED"); 228 A4 pins its absence.
--
-- GRANT DECISIONS (every one, because the CI grant gates read `public` only and
-- 228 is the gate for this schema — the 246/226 pattern):
--   schema venue_cmd  USAGE   : authenticated ONLY. anon: NONE (the dashboard has
--                               no anonymous surface, spec §5). PUBLIC: NONE
--                               (REVOKE ALL ... FROM PUBLIC). service_role: NONE
--                               (no server-side caller; the edges never call
--                               these verbs — E-76 enumeration, D's evidence dir).
--   each wrapper      EXECUTE : authenticated ONLY. REVOKE ALL FROM PUBLIC, anon,
--                               authenticated first (a bare REVOKE FROM PUBLIC is
--                               not enough once role grants exist — 067), then
--                               GRANT EXECUTE TO authenticated. anon/PUBLIC/
--                               service_role: NONE. No proacl is left DEFAULTED
--                               (228 A17).
--   default privileges        : none stored. A per-schema ALTER DEFAULT PRIVILEGES
--                               is role-scoped to whoever runs the migration and
--                               stores a row that 226 F3-style pins would have to
--                               reason about; the explicit per-function REVOKE +
--                               228's schema-wide sweep (A2/A5/A14/A16/A17: every
--                               function in the schema, not a fixed list) cover
--                               anything added later.
--   anon reach                : none at any layer — no USAGE on venue_cmd, no
--                               EXECUTE on any wrapper, and no USAGE on venue
--                               (076/E-30) behind it.
--
-- FOUR-FILE RULE (CLAUDE.md): the grant-decision manifest and expected_grants.txt
-- read `public` only (159 added no row; the manifest's B2 fails closed on a row
-- for a function outside public), so no row is added; 228 pins the exact ACL of
-- the schema and of every function in it. Gate-2 census (ci.yml) reads `public`
-- only: unchanged (dated comment line). Rollback:
-- supabase/rollbacks/20261022110000_venue_cmd_transport_rollback.sql — drops the
-- six wrappers and the schema (not CASCADE: refuses if anything else was ever
-- created there). Roll back 161 BEFORE 160 (160's rollback refuses while
-- venue_cmd exists).
--
-- VERIFICATION (after apply):
--   select count(*), bool_and(not prosecdef), bool_and(l.lanname='sql')
--     from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
--    where n.nspname='venue_cmd';                                      -- 6 | t | t
--   select has_schema_privilege('anon','venue_cmd','USAGE');          -- f
--   select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='venue_cmd';  -- 0
-- LOCKS / RUNTIME: CREATE SCHEMA / CREATE FUNCTION only; no table is touched.
-- ============================================================================
BEGIN;

CREATE SCHEMA IF NOT EXISTS venue_cmd;
COMMENT ON SCHEMA venue_cmd IS
  'Venue dashboard command transport. SECURITY INVOKER sql wrappers over venue.* definer RPCs; authority and audit live in the definer bodies. No tables, no definer functions. Exposure over PostgREST is an owner setting.';

REVOKE ALL ON SCHEMA venue_cmd FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA venue_cmd TO authenticated;

-- ---------------------------------------------------------------------------
-- The six wrappers. One SELECT each; argument names and types, and the result
-- type, are the target's (228 A18/A19 pin both against pg_catalog).
-- ---------------------------------------------------------------------------
create or replace function venue_cmd.create_ticket_type(
  p_event_id uuid, p_kind text, p_name text, p_price_minor integer,
  p_visibility text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.create_ticket_type(p_event_id, p_kind, p_name, p_price_minor, p_visibility, p_command_key)
$$;
comment on function venue_cmd.create_ticket_type(uuid, text, text, integer, text, text) is
  '161: invoker wrapper -> venue.create_ticket_type (081, E-76 by 160).';

create or replace function venue_cmd.set_ticket_type_price(
  p_ticket_type_id uuid, p_price_minor integer, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.set_ticket_type_price(p_ticket_type_id, p_price_minor, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_ticket_type_price(uuid, integer, text, text) is
  '161: invoker wrapper -> venue.set_ticket_type_price (081, E-76 by 160).';

create or replace function venue_cmd.set_ticket_type_visibility(
  p_ticket_type_id uuid, p_visibility text, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.set_ticket_type_visibility(p_ticket_type_id, p_visibility, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_ticket_type_visibility(uuid, text, text, text) is
  '161: invoker wrapper -> venue.set_ticket_type_visibility (160).';

create or replace function venue_cmd.set_ticket_type_rank(
  p_ticket_type_id uuid, p_display_rank smallint, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.set_ticket_type_rank(p_ticket_type_id, p_display_rank, p_command_key)
$$;
comment on function venue_cmd.set_ticket_type_rank(uuid, smallint, text) is
  '161: invoker wrapper -> venue.set_ticket_type_rank (160).';

create or replace function venue_cmd.set_batch_capacity(
  p_batch_id uuid, p_new_capacity integer, p_reason_code text, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.set_batch_capacity(p_batch_id, p_new_capacity, p_reason_code, p_command_key)
$$;
comment on function venue_cmd.set_batch_capacity(uuid, integer, text, text) is
  '161: invoker wrapper -> venue.set_batch_capacity (081, E-76 by 160).';

create or replace function venue_cmd.get_inventory_counters(p_event_id uuid)
returns table (
  batch_id         uuid,
  ticket_type_id   uuid,
  event_session_id uuid,
  release_kind     text,
  capacity         integer,
  held             integer,
  sold             integer,
  remaining        integer)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.batch_id, c.ticket_type_id, c.event_session_id, c.release_kind,
         c.capacity, c.held, c.sold, c.remaining
    from venue.get_inventory_counters(p_event_id) c
$$;
comment on function venue_cmd.get_inventory_counters(uuid) is
  '161: invoker wrapper -> venue.get_inventory_counters (160). Same P0002 for unknown and unauthorized events.';

-- ---------------------------------------------------------------------------
-- ACLs: strip PUBLIC/anon/authenticated, grant exactly authenticated (081 PART 16)
-- ---------------------------------------------------------------------------
do $$
declare
  v_fn text;
  v_all constant text[] := array[
    'venue_cmd.create_ticket_type(uuid, text, text, integer, text, text)',
    'venue_cmd.set_ticket_type_price(uuid, integer, text, text)',
    'venue_cmd.set_ticket_type_visibility(uuid, text, text, text)',
    'venue_cmd.set_ticket_type_rank(uuid, smallint, text)',
    'venue_cmd.set_batch_capacity(uuid, integer, text, text)',
    'venue_cmd.get_inventory_counters(uuid)'
  ];
begin
  foreach v_fn in array v_all loop
    execute format('revoke all on function %s from public, anon, authenticated', v_fn);
    execute format('grant execute on function %s to authenticated', v_fn);
  end loop;
end $$;

COMMIT;
