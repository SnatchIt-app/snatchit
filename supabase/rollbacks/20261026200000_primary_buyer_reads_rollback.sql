-- ============================================================================
-- 20261026200000_primary_buyer_reads_rollback.sql — reversal of registry 182
-- (pgTAP 252). Confirmed by Claude A 2026-10-26 (CONTRACTS.md §4).
--
-- 182 is purely additive in `public` (four SECURITY DEFINER read functions +
-- their EXECUTE grants; no table, column, policy, trigger, grant on any
-- existing object, flag or data). This file drops exactly those four and
-- nothing else, so the catalog fingerprint returns to its pre-182 state
-- (EVIDENCE-182 §5: pre-182 vs post-rollback diff = 0 lines) and the Gate-2
-- public function census returns 130 -> 126.
--
-- Guards (each refuses with NOTHING changed; psql -v ON_ERROR_STOP=1 exits 3):
--   G1 the live body of each of the four functions must hash (md5 of prosrc)
--      to 182's — otherwise a later migration replaced it body-only and this
--      file would silently undo that package: roll it back first. A function
--      that is already absent is tolerated (idempotent re-run).
--   G2 nothing else in the catalog may depend on the four (a later view or
--      function built over them) — pg_depend is read; roll that package back
--      first.
--   G2b no OTHER function body may call one of the four by name. A plpgsql or
--      LANGUAGE sql body records NO pg_depend row for the functions it calls,
--      so G2 alone cannot see e.g. a later public.list_my_primary_orders built
--      over public.get_my_primary_orders (registry 167): every other pg_proc
--      prosrc is matched against 'public.<name>(' (word-bounded) instead. Roll
--      that package back first.
-- Verify (inside the same transaction): none of the four remains; the public
-- census moved by exactly the number dropped.
--
-- What this re-introduces, on the record: the buyer discovery surface (C1) and
-- the owner-scoped ticket/order reads (C5) disappear — C's Tickets/QR screen and
-- the discovery list get PGRST202 (undefined function) until redeployed to the
-- pre-182 contract; 252 goes RED throughout (18 emitted); ci.yml EXPECT_FUNCS
-- and tests/162 P2 must return to 126 in the same change set, and the four
-- manifest rows must be removed (B2 fails closed on a row for a function that
-- is gone). The supabase_migrations ledger row is NOT removed here (separate,
-- owner-authorised step).
--
--   182 bodies (md5 prosrc) — the FOLD-IN bodies (2026-10-26: list gained
--   timezone / starts_at_local / doors_at_local, detail gained buyer_fee_minor /
--   all_in_price_minor, orders gained charge_total_minor; atoms unchanged):
--                            list_primary_sessions_on_sale 7a3fcb91976cdd31b32be4e192d09437
--                            get_primary_session           5c2f3321170798edd277ef0d639c45e3
--                            get_my_ticket_atoms           8f142e0d4f47d197d633d13c33e70312
--                            get_my_primary_orders         3a098366bfa9b58a22214718d2f21c30
--   (pre-fold-in bodies, never applied anywhere but rehearsal clones, are NOT
--   accepted: list 93debdf3ad599a263a7e6a208ec7e7c9, detail
--   9bfb318898954b958c07982cc7723835, orders f0ec61fcf60b8125bcb1a43dc4332de6
--   — a clone carrying them is rebuilt, not rolled back with this file.)
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TEMP TABLE _pre182_rb ON COMMIT DROP AS
  SELECT count(*)::integer AS n_public_fns,
         (to_regprocedure('public.list_primary_sessions_on_sale()') IS NOT NULL)::integer
       + (to_regprocedure('public.get_primary_session(uuid)')       IS NOT NULL)::integer
       + (to_regprocedure('public.get_my_ticket_atoms(uuid)')       IS NOT NULL)::integer
       + (to_regprocedure('public.get_my_primary_orders(uuid)')     IS NOT NULL)::integer AS n_present
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
      ('public.list_primary_sessions_on_sale()', '7a3fcb91976cdd31b32be4e192d09437'),
      ('public.get_primary_session(uuid)',       '5c2f3321170798edd277ef0d639c45e3'),
      ('public.get_my_ticket_atoms(uuid)',       '8f142e0d4f47d197d633d13c33e70312'),
      ('public.get_my_primary_orders(uuid)',     '3a098366bfa9b58a22214718d2f21c30')) AS x(sig, want)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE NOTICE 'ROLLBACK_182: % is already absent (tolerated).', r.sig;
      CONTINUE;
    END IF;
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(r.sig);
    IF v_md5 IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION 'ROLLBACK_182_REFUSED (G1): the live body of % is not 182''s (md5 % <> %); a later migration replaced it — roll that package back first. Nothing changed.', r.sig, v_md5, r.want;
    END IF;
    SELECT string_agg(d.classid::regclass::text || ':' || d.objid::text, ', ') INTO v_dep
      FROM pg_depend d
     WHERE d.refobjid = to_regprocedure(r.sig)
       AND d.refclassid = 'pg_proc'::regclass
       AND d.deptype <> 'i'
       AND NOT (d.classid = 'pg_proc'::regclass AND d.objid = to_regprocedure(r.sig));
    IF v_dep IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_182_REFUSED (G2): another catalog object depends on % (%) — roll that package back first. Nothing changed.', r.sig, v_dep;
    END IF;
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_ref
      FROM pg_proc p
     WHERE p.oid <> to_regprocedure(r.sig)
       AND p.prosrc ~ ('\mpublic\.' || split_part(split_part(r.sig, '.', 2), '(', 1) || '\s*\(');
    IF v_ref IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_182_REFUSED (G2b): another function body calls % (%) — roll that package back first. Nothing changed.', r.sig, v_ref;
    END IF;
  END LOOP;
END $g$;

DROP FUNCTION IF EXISTS public.get_my_primary_orders(uuid);
DROP FUNCTION IF EXISTS public.get_my_ticket_atoms(uuid);
DROP FUNCTION IF EXISTS public.get_primary_session(uuid);
DROP FUNCTION IF EXISTS public.list_primary_sessions_on_sale();

DO $v$
DECLARE
  v_pre  integer := (SELECT n_public_fns FROM _pre182_rb);
  v_n    integer := (SELECT n_present    FROM _pre182_rb);
  v_post integer;
BEGIN
  IF to_regprocedure('public.list_primary_sessions_on_sale()') IS NOT NULL
  OR to_regprocedure('public.get_primary_session(uuid)')       IS NOT NULL
  OR to_regprocedure('public.get_my_ticket_atoms(uuid)')       IS NOT NULL
  OR to_regprocedure('public.get_my_primary_orders(uuid)')     IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_182_VERIFY_FAILED: a 182 function still exists.';
  END IF;
  SELECT count(*)::integer INTO v_post
    FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e');
  IF v_post <> v_pre - v_n THEN
    RAISE EXCEPTION 'ROLLBACK_182_VERIFY_FAILED: public function census moved % -> % (expected -%).', v_pre, v_post, v_n;
  END IF;
  RAISE NOTICE 'ROLLBACK_182: % function(s) dropped; public functions % -> % (Gate-2 EXPECT_FUNCS back to 126 on the certified chain).', v_n, v_pre, v_post;
END $v$;

COMMIT;
