-- ============================================================================
-- 20261029170000_venue_cmd_create_inventory_batch_rollback.sql — mechanical
-- reversal of registry 192 (pgTAP 261). Registry allocated by Claude A 2026-10-29.
--
-- Drops the ONE SECURITY INVOKER wrapper 192 created,
-- venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text).
-- NOTHING ELSE: 192 created no table, type or schema, changed no body and
-- touched no grant on any pre-existing object (its post-flight refused a change
-- to the target's ACL), so nothing is restored. The wrapper's grant and comment
-- go with it; no default-ACL row was stored. Batches already created through the
-- wrapper are ordinary venue.inventory_batch rows and STAY (they belong to the
-- body, not to the wrapper). The schema venue_cmd stays (161's). The
-- supabase_migrations ledger row is NOT removed here (separate, owner-authorised
-- step). If venue_cmd is exposed to PostgREST, nothing here changes that setting;
-- after this file the dashboard's "first inventory release" step gets PGRST202
-- until redeployed to the pre-192 contract.
-- ORDER: roll back 192 BEFORE 165/167/166/164 and before 161 (161's rollback
-- refuses while venue_cmd holds a function it did not create).
--
-- Guards (167's G1/G2/G2b block is the model; each refuses with NOTHING changed,
-- psql -v ON_ERROR_STOP=1 exits 3; an absent wrapper is tolerated — idempotent):
--   G1  the live body must hash (md5 of prosrc) to 192's — otherwise a later
--       migration replaced it and this file would silently remove that package's
--       object: roll that package back first.
--   G2  no catalog object (a view, a default, …) may depend on it (pg_depend).
--   G2b no OTHER function body may call it by name ('venue_cmd.create_inventory_batch(',
--       word-bounded prosrc scan — plpgsql / sql bodies record no pg_depend row).
--   192 body (md5 prosrc, PG17): d6d48059afcfc50c9746c298a48a4a24
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $g$
DECLARE
  v_sig text := 'venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text)';
  v_md5 text;
  v_dep text;
  v_ref text;
BEGIN
  IF to_regprocedure(v_sig) IS NULL THEN
    RAISE NOTICE 'ROLLBACK_192: % is already absent (tolerated).', v_sig;
    RETURN;
  END IF;
  SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(v_sig);
  IF v_md5 IS DISTINCT FROM 'd6d48059afcfc50c9746c298a48a4a24' THEN
    RAISE EXCEPTION 'ROLLBACK_192_REFUSED (G1): the live body of % is not 192''s (md5 %); a later migration replaced it — roll that package back first. Nothing changed.', v_sig, v_md5;
  END IF;
  SELECT string_agg(d.classid::regclass::text || ':' || d.objid::text, ', ') INTO v_dep
    FROM pg_depend d
   WHERE d.refobjid = to_regprocedure(v_sig)
     AND d.refclassid = 'pg_proc'::regclass
     AND d.deptype <> 'i'
     AND NOT (d.classid = 'pg_proc'::regclass AND d.objid = to_regprocedure(v_sig));
  IF v_dep IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_192_REFUSED (G2): another catalog object depends on % (%) — roll that package back first. Nothing changed.', v_sig, v_dep;
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_ref
    FROM pg_proc p
   WHERE p.oid <> to_regprocedure(v_sig)
     AND p.prosrc ~ '\mvenue_cmd\.create_inventory_batch\s*\(';
  IF v_ref IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_192_REFUSED (G2b): another function body calls % (%) — roll that package back first. Nothing changed.', v_sig, v_ref;
  END IF;
END $g$;

DROP FUNCTION IF EXISTS venue_cmd.create_inventory_batch(uuid, uuid, text, integer, integer, text);

DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
              WHERE n.nspname = 'venue_cmd' AND p.proname = 'create_inventory_batch') THEN
    RAISE EXCEPTION 'ROLLBACK_192_VERIFY_FAILED: venue_cmd.create_inventory_batch still present';
  END IF;
END $verify$;

COMMIT;
