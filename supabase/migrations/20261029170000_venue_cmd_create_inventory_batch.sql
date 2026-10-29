-- ============================================================================
-- 20261029170000_venue_cmd_create_inventory_batch.sql — the dashboard's route
-- to venue.create_inventory_batch: ONE SECURITY INVOKER wrapper in venue_cmd.
--
-- Registry 192 / pgTAP 261 — registry and stem allocated by Claude A 2026-10-29
-- (closeout board P2.2, option (a): finish the dashboard path; the owner ruled
-- the proof not waivable); pgTAP 261 is the next free number (260 is taken on
-- another branch) — A to confirm. E reviews the exact head. DARK: applied
-- nowhere. Applying it to the sandbox waits on the owner's yes (bundled with
-- F's P2 deploy yes); production is A's ordered release, never D.
-- ORDER: after 161 (20261022110000, schema venue_cmd) and 162 (20261026100000,
-- the current venue.create_inventory_batch body: the session pool guard and the
-- E-76 operator conjunct). Lands on top of the gate (release/production-gate-
-- 20260918) after 165 and A's 188/189.
--
-- WHY NOW. 161 WITHHELD this wrapper "until S2's E-33 receipt" (228 A4 pinned
-- its absence). On the gate tip, F's dashboard can create events, sessions and
-- tiers but its "first inventory release" step is preview-only, so a new event
-- can never reach on_sale (empty_inventory) and P2.2's buyer-discovery proof
-- cannot complete. This file closes that one server gap; 228 A4 flips with it.
--
-- E-33, DISCLOSED, NOT RESOLVED HERE (POST_FREEZE_AMENDMENTS E-33): the body's
-- frozen p_command_key is NOT an idempotency anchor — venue.inventory_batch has
-- no command-key column and "no unique beyond PK" (schema §3.2), so a RETRIED
-- create adds a second batch. That is benign (capacity over-provision, never
-- oversell: each batch is oversell-safe by its own CHECK, and the session pool
-- guard of 162 still caps the sum when a pool is set), admin-frequency and
-- operator-visible. Resolving it needs a ratified §3.2 schema addition, which
-- this wrapper does not invent. The CLIENT contract therefore is:
--   * never auto-retry venue_cmd.create_inventory_batch;
--   * after an uncertain outcome (timeout, lost response), re-read the
--     session's batches (venue_cmd.get_inventory_counters /
--     venue_cmd.get_session_capacity) before offering a second submit.
--
-- WHAT THIS MIGRATION IS:
--   venue_cmd.create_inventory_batch(p_ticket_type_id uuid, p_session_id uuid,
--     p_release_kind text, p_capacity integer, p_shard_count integer,
--     p_command_key text) returns jsonb
--   LANGUAGE sql, SECURITY INVOKER, VOLATILE, search_path = '', body exactly
--   `select venue.create_inventory_batch(<the same six arguments>)` — the 161 /
--   164 sibling pattern (identical argument list and result type to the target).
--   The caller already holds USAGE on venue (076:78) and EXECUTE on the target
--   (081 PART 16: authenticated), so the wrapper adds NO privilege: every
--   refusal (42501 'insufficient_privilege: venue_manager or org_owner/org_admin
--   required', bad release_kind, bad_capacity, sharding_deferred,
--   type_session_event_mismatch, session_capacity_exceeded, P0002) propagates
--   verbatim from the definer body, and the body writes the audit row with the
--   caller as actor. release_kind ∈ public_sale | promoter_hold | comp | door |
--   presale (the body checks it).
--
-- GRANT DECISIONS (the CI grant gates read `public` only; pgTAP 261 + 228's
-- schema-wide sweep are the gate for this object):
--   venue_cmd.create_inventory_batch  EXECUTE : authenticated ONLY. REVOKE ALL
--     FROM PUBLIC, anon, authenticated, service_role first (067: a bare REVOKE
--     FROM PUBLIC is not enough; service_role named explicitly so the outcome is
--     identical on the local replay shim and CI's fresh stack), then GRANT
--     EXECUTE TO authenticated. anon / PUBLIC / service_role: NONE. No proacl is
--     left DEFAULTED. Schema venue_cmd USAGE: unchanged (161: authenticated only).
--   venue.create_inventory_batch (the target): UNCHANGED — no grant, no revoke,
--     no body change; the post-flight refuses if its ACL moved.
--   default privileges: none stored (161's reasoning).
--
-- FOUR-FILE RULE (CLAUDE.md): nothing lands in `public`, so no grant-decision
-- manifest row (its B2 fails closed on a row for a function outside public) and
-- no expected_grants.txt line (tables only) — a dated scope note in the manifest
-- and a dated comment line in the Gate-2 census block record the decision (the
-- 161/163/164 pattern). Gate-2 census: unchanged (it reads `public` only). pgTAP
-- census pins that move: venue_cmd 22 -> 23 (228, 229 A26 — measured on the gate
-- replay; EVIDENCE-192). Rollback:
-- supabase/rollbacks/20261029170000_venue_cmd_create_inventory_batch_rollback.sql.
--
-- PRE-FLIGHT (A's N1 pattern, accept-own): venue_cmd.create_inventory_batch must
-- be ABSENT (first apply) or exactly 192's own wrapper (re-apply): one function
-- by that name, md5(prosrc) = 192's, LANGUAGE sql, SECURITY INVOKER,
-- search_path="". Anything else is refused:
--   MIGRATION_192_REFUSED (pre-flight): venue_cmd.create_inventory_batch exists and is not 192's own wrapper (...); nothing changed
-- (one transaction; psql -v ON_ERROR_STOP=1 exits 3). md5 (PG17):
--   venue_cmd.create_inventory_batch  d6d48059afcfc50c9746c298a48a4a24  (PG17; a body change re-hashes it here, in the pre-/post-flight and in the rollback)
--
-- VERIFICATION (read-only, after apply):
--   select md5(prosrc), prosecdef, proconfig, proacl from pg_proc
--    where oid = 'venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure;
--   -- <192 md5> | f | {search_path=""} | {postgres=X/postgres,authenticated=X/postgres}
--   select proacl from pg_proc where oid = 'venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)'::regprocedure;
--   -- unchanged
-- LOCKS / RUNTIME: CREATE FUNCTION / GRANT on one new function; no table, no
-- existing function and no row is touched.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ---------------------------------------------------------------------------
-- 0. Order guard: 161's schema and 162's target, with the target's shape; a
--    snapshot of the target's ACL (transaction-local GUC) for the post-flight.
-- ---------------------------------------------------------------------------
DO $order192$
BEGIN
  IF to_regnamespace('venue_cmd') IS NULL THEN
    RAISE EXCEPTION 'ORDER_192_REFUSED: schema venue_cmd (161, 20261022110000) is absent; apply 160 then 161 first';
  END IF;
  IF to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)') IS NULL
     OR pg_get_function_result(to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)')) <> 'jsonb'
     OR NOT (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)')) THEN
    RAISE EXCEPTION 'ORDER_192_REFUSED: venue.create_inventory_batch(uuid, uuid, text, integer, integer, text) is absent or not a jsonb SECURITY DEFINER body';
  END IF;
  PERFORM set_config('d192.target_acl_before',
    coalesce((SELECT p.proacl::text FROM pg_proc p
               WHERE p.oid = to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)')), 'DEFAULTED'),
    true);
END $order192$;

-- ---------------------------------------------------------------------------
-- 0b. PRE-FLIGHT (accept-own; see the header).
-- ---------------------------------------------------------------------------
DO $pre192$
DECLARE
  v_n   integer;
  v_got text;
BEGIN
  SELECT count(*), string_agg(md5(p.prosrc) || '/' || l.lanname || '/' || p.prosecdef::text || '/' || coalesce(array_to_string(p.proconfig, ','), '-'), ' ')
    INTO v_n, v_got
    FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
   WHERE p.pronamespace = 'venue_cmd'::regnamespace AND p.proname = 'create_inventory_batch';
  IF v_n > 0 AND (v_n > 1 OR v_got IS DISTINCT FROM ('d6d48059afcfc50c9746c298a48a4a24' || '/sql/false/search_path=""')) THEN
    RAISE EXCEPTION 'MIGRATION_192_REFUSED (pre-flight): venue_cmd.create_inventory_batch exists and is not 192''s own wrapper (% by name: %); nothing changed', v_n, v_got;
  END IF;
END $pre192$;

-- ---------------------------------------------------------------------------
-- 1. The wrapper. One SELECT; the target's argument names/types and result type.
-- ---------------------------------------------------------------------------
create or replace function venue_cmd.create_inventory_batch(
  p_ticket_type_id uuid, p_session_id uuid, p_release_kind text,
  p_capacity integer, p_shard_count integer, p_command_key text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select venue.create_inventory_batch(p_ticket_type_id, p_session_id, p_release_kind, p_capacity, p_shard_count, p_command_key)
$$;
comment on function venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text) is
  '192: invoker wrapper -> venue.create_inventory_batch (081, body 162). release_kind public_sale|promoter_hold|comp|door|presale; p_shard_count NULL or 0. NOT idempotent on p_command_key (E-33): never auto-retry; re-read the session''s batches after an uncertain outcome.';

-- ---------------------------------------------------------------------------
-- 2. ACL: strip PUBLIC/anon/authenticated/service_role, grant exactly authenticated.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text)
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Post-flight: the wrapper's posture and ACL; the target's ACL unchanged.
-- ---------------------------------------------------------------------------
DO $post192$
DECLARE
  v_w    oid := to_regprocedure('venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text)');
  v_t    oid := to_regprocedure('venue.create_inventory_batch(uuid, uuid, text, integer, integer, text)');
  v_acl  text;
BEGIN
  IF v_w IS NULL
     OR (SELECT p.prosecdef FROM pg_proc p WHERE p.oid = v_w)
     OR (SELECT l.lanname FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang WHERE p.oid = v_w) <> 'sql'
     OR (SELECT p.provolatile FROM pg_proc p WHERE p.oid = v_w) <> 'v'
     OR NOT ('search_path=""' = ANY (coalesce((SELECT p.proconfig FROM pg_proc p WHERE p.oid = v_w), '{}')))
     OR pg_get_function_result(v_w) <> pg_get_function_result(v_t)
     OR pg_get_function_identity_arguments(v_w) <> pg_get_function_identity_arguments(v_t)
     OR md5((SELECT p.prosrc FROM pg_proc p WHERE p.oid = v_w)) <> 'd6d48059afcfc50c9746c298a48a4a24' THEN
    RAISE EXCEPTION 'POSTFLIGHT_192_FAILED: venue_cmd.create_inventory_batch posture is wrong (definer / language / volatility / search_path / signature / body)';
  END IF;
  SELECT string_agg(e.entry, ',' ORDER BY e.entry)
    INTO v_acl
    FROM (SELECT CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE a.grantee::regrole::text END || ':' || a.privilege_type AS entry
            FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) a
           WHERE p.oid = v_w) e;
  IF (SELECT p.proacl FROM pg_proc p WHERE p.oid = v_w) IS NULL
     OR v_acl IS DISTINCT FROM 'authenticated:EXECUTE,postgres:EXECUTE' THEN
    RAISE EXCEPTION 'POSTFLIGHT_192_FAILED: venue_cmd.create_inventory_batch ACL is % (expected exactly owner postgres + authenticated EXECUTE)', coalesce(v_acl, 'DEFAULTED');
  END IF;
  IF coalesce((SELECT p.proacl::text FROM pg_proc p WHERE p.oid = v_t), 'DEFAULTED') <> current_setting('d192.target_acl_before', true) THEN
    RAISE EXCEPTION 'POSTFLIGHT_192_FAILED: the target venue.create_inventory_batch ACL changed (before % / after %)',
      current_setting('d192.target_acl_before', true), coalesce((SELECT p.proacl::text FROM pg_proc p WHERE p.oid = v_t), 'DEFAULTED');
  END IF;
END $post192$;

COMMIT;
