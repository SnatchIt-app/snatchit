-- ============================================================================
-- 20261027015500_primary_buyer_holds_and_orders_rollback.sql — reversal of
-- registry 167 (pgTAP 234). Assigned by Claude A 2026-10-26 (registry 167/234,
-- registry @ 5f29cbcc).
--
-- 167 is purely additive in `public` (three SECURITY DEFINER wrappers + their
-- EXECUTE grants; no table, column, policy, trigger, grant on any existing
-- object, flag or data). This file drops exactly those three and nothing else,
-- so the catalog fingerprint returns to its pre-167 state (EVIDENCE-167 §5:
-- pre-167 vs post-rollback diff = 0 lines) and the Gate-2 public function
-- census returns 133 -> 130. Holds already taken through reserve_primary_tier
-- are ordinary venue.inventory_hold rows and stay (the sweep expires them);
-- nothing about them depended on the wrapper.
--
-- Guards (each refuses with NOTHING changed; psql -v ON_ERROR_STOP=1 exits 3):
--   G1 the live body of each of the three must hash (md5 of prosrc) to 167's —
--      otherwise a later migration replaced it body-only and this file would
--      silently undo that package: roll it back first. A function that is
--      already absent is tolerated (idempotent re-run).
--   G2 no catalog object may depend on the three (pg_depend).
--   G2b no OTHER function body may call one of them by name ('public.<name>(',
--      word-bounded over every pg_proc prosrc — plpgsql / sql bodies record no
--      pg_depend row for the functions they call).
-- Verify (inside the same transaction): none of the three remains; the public
-- census moved by exactly the number dropped.
--
-- What this re-introduces, on the record: the buyer app loses its public
-- reserve / release / all-orders verbs — C's checkout and Tickets tab get
-- PGRST202 until redeployed to the pre-167 contract; 234 goes RED; ci.yml
-- EXPECT_FUNCS, tests/162 P2 and 252 A17 must return to 130 in the same change
-- set and the three manifest rows must be removed (B2 fails closed on a row for
-- a function that is gone). Rolling back 182 afterwards is then possible (its
-- G2b refuses while list_my_primary_orders still names get_my_primary_orders).
-- The supabase_migrations ledger row is NOT removed here (separate, owner-
-- authorised step).
--
--   167 bodies (md5 prosrc): reserve_primary_tier    f397c9a49b04f37793165e996490e2f0
--                            release_primary_hold    d043cada2d528d5ec5ab4a5164224261
--                            list_my_primary_orders  febebba44a44fb925dd56de58a47effa
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE _pre167_rb ON COMMIT DROP AS
  SELECT count(*)::integer AS n_public_fns,
         (to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)') IS NOT NULL)::integer
       + (to_regprocedure('public.release_primary_hold(uuid, text)')                IS NOT NULL)::integer
       + (to_regprocedure('public.list_my_primary_orders()')                        IS NOT NULL)::integer AS n_present
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');

DO $g$
DECLARE
  r record;
  v_md5 text;
  v_dep text;
  v_ref text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('public.reserve_primary_tier(uuid, uuid, integer, text)', 'f397c9a49b04f37793165e996490e2f0'),
      ('public.release_primary_hold(uuid, text)',                'd043cada2d528d5ec5ab4a5164224261'),
      ('public.list_my_primary_orders()',                        'febebba44a44fb925dd56de58a47effa')) AS x(sig, want)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE NOTICE 'ROLLBACK_167: % is already absent (tolerated).', r.sig;
      CONTINUE;
    END IF;
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(r.sig);
    IF v_md5 IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION 'ROLLBACK_167_REFUSED (G1): the live body of % is not 167''s (md5 % <> %); a later migration replaced it — roll that package back first. Nothing changed.', r.sig, v_md5, r.want;
    END IF;
    SELECT string_agg(d.classid::regclass::text || ':' || d.objid::text, ', ') INTO v_dep
      FROM pg_depend d
     WHERE d.refobjid = to_regprocedure(r.sig)
       AND d.refclassid = 'pg_proc'::regclass
       AND d.deptype <> 'i'
       AND NOT (d.classid = 'pg_proc'::regclass AND d.objid = to_regprocedure(r.sig));
    IF v_dep IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_167_REFUSED (G2): another catalog object depends on % (%) — roll that package back first. Nothing changed.', r.sig, v_dep;
    END IF;
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_ref
      FROM pg_proc p
     WHERE p.oid <> to_regprocedure(r.sig)
       AND p.prosrc ~ ('\mpublic\.' || split_part(split_part(r.sig, '.', 2), '(', 1) || '\s*\(');
    IF v_ref IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_167_REFUSED (G2b): another function body calls % (%) — roll that package back first. Nothing changed.', r.sig, v_ref;
    END IF;
  END LOOP;
END $g$;

DROP FUNCTION IF EXISTS public.list_my_primary_orders();
DROP FUNCTION IF EXISTS public.release_primary_hold(uuid, text);
DROP FUNCTION IF EXISTS public.reserve_primary_tier(uuid, uuid, integer, text);

DO $v$
DECLARE
  v_pre  integer := (SELECT n_public_fns FROM _pre167_rb);
  v_n    integer := (SELECT n_present    FROM _pre167_rb);
  v_post integer;
BEGIN
  IF to_regprocedure('public.reserve_primary_tier(uuid, uuid, integer, text)') IS NOT NULL
  OR to_regprocedure('public.release_primary_hold(uuid, text)')                IS NOT NULL
  OR to_regprocedure('public.list_my_primary_orders()')                        IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_167_VERIFY_FAILED: a 167 function still exists.';
  END IF;
  SELECT count(*)::integer INTO v_post
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');
  IF v_post <> v_pre - v_n THEN
    RAISE EXCEPTION 'ROLLBACK_167_VERIFY_FAILED: public function census moved % -> % (expected -%).', v_pre, v_post, v_n;
  END IF;
  RAISE NOTICE 'ROLLBACK_167: % function(s) dropped; public functions % -> % (Gate-2 EXPECT_FUNCS back to 130 on the 182 chain).', v_n, v_pre, v_post;
END $v$;

COMMIT;
