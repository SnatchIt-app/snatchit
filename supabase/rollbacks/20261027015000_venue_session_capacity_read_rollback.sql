-- ============================================================================
-- 20261027015000_venue_session_capacity_read_rollback.sql — mechanical reversal
-- of registry 166 (pgTAP 233). Assigned by Claude A 2026-10-26 (registry
-- 166/233).
--
-- Drops, in dependency order, the view venue_api.session_capacity, the
-- venue_cmd SECURITY INVOKER wrapper venue_cmd.get_session_capacity and the two
-- definer reads venue.list_session_capacity / venue.get_session_capacity.
-- NOTHING ELSE: 166 touched no table, no column, no policy, no 162 body and no
-- grant on a pre-existing object, so nothing is restored. Every DROP is IF
-- EXISTS: the file is idempotent, rc 0 on a database that never saw 166. The
-- grants and comments go with the objects; no default-ACL row was stored. The
-- supabase_migrations ledger row is NOT removed here (separate, owner-authorised
-- step). If venue_api / venue_cmd had been added to PostgREST's exposed schemas,
-- nothing here changes that setting.
-- ORDER: run this BEFORE 162's, 161's (which refuses while venue_cmd holds a
-- function it did not create) and 159's (which refuses while venue_api holds a
-- view it did not create) rollbacks. Independent of 163's/182's/164's/165's.
--
-- Guards (A's N2, review of 164-167/165, 2026-10-27; 167's G1/G2/G2b block is the
-- model). Each refuses with NOTHING changed (psql -v ON_ERROR_STOP=1 exits 3); an
-- object that is already absent is tolerated (idempotent re-run):
--   G1  each present function's md5(prosrc), and the view's md5(pg_get_viewdef),
--       must be 166's — otherwise a later migration replaced it: roll that back first.
--   G2  no catalog object outside 166 may depend on the three functions or on the
--       view (pg_depend; the view's own dependency on venue.list_session_capacity is
--       166's and is excluded).
--   G2b no function body outside 166 may name venue.get_session_capacity(,
--       venue.list_session_capacity(, venue_cmd.get_session_capacity( or
--       venue_api.session_capacity (word-bounded prosrc scan — function bodies
--       record no pg_depend row; A's case: an outside plpgsql caller of
--       venue.get_session_capacity survived the old rollback rc 0, then failed 42883).
--   166 objects (PG17): venue.get_session_capacity 553f805c84f6d0b901bf0d8827e3f3dd,
--   venue.list_session_capacity 14b9d99b8f0dd2c801cacce4929cd6fb,
--   venue_cmd.get_session_capacity 908f9663a72d563ac08be91c94726af2,
--   venue_api.session_capacity viewdef 02a452dfff5305946eda2b23be3d65bb.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $g$
DECLARE
  r record;
  v_md5 text;
  v_dep text;
  v_ref text;
  v_own oid[] := ARRAY[to_regprocedure('venue.get_session_capacity(uuid)'),
                       to_regprocedure('venue.list_session_capacity()'),
                       to_regprocedure('venue_cmd.get_session_capacity(uuid)')]::oid[];
  v_view oid := to_regclass('venue_api.session_capacity');
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('venue.get_session_capacity(uuid)',     '553f805c84f6d0b901bf0d8827e3f3dd', 'venue\.get_session_capacity'),
      ('venue.list_session_capacity()',        '14b9d99b8f0dd2c801cacce4929cd6fb', 'venue\.list_session_capacity'),
      ('venue_cmd.get_session_capacity(uuid)', '908f9663a72d563ac08be91c94726af2', 'venue_cmd\.get_session_capacity')) AS x(sig, want, re)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE NOTICE 'ROLLBACK_166: % is already absent (tolerated).', r.sig;
      CONTINUE;
    END IF;
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(r.sig);
    IF v_md5 IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION 'ROLLBACK_166_REFUSED (G1): the live body of % is not 166''s (md5 % <> %); a later migration replaced it — roll that package back first. Nothing changed.', r.sig, v_md5, r.want;
    END IF;
    SELECT string_agg(d.classid::regclass::text || ':' || d.objid::text, ', ') INTO v_dep
      FROM pg_depend d
      LEFT JOIN pg_rewrite w ON d.classid = 'pg_rewrite'::regclass AND w.oid = d.objid
     WHERE d.refobjid = to_regprocedure(r.sig)
       AND d.refclassid = 'pg_proc'::regclass
       AND d.deptype <> 'i'
       AND NOT (d.classid = 'pg_proc'::regclass AND d.objid = ANY (v_own))
       AND w.ev_class IS DISTINCT FROM v_view;
    IF v_dep IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_166_REFUSED (G2): another catalog object depends on % (%) — roll that package back first. Nothing changed.', r.sig, v_dep;
    END IF;
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_ref
      FROM pg_proc p
     WHERE NOT (p.oid = ANY (v_own))
       AND p.prosrc ~ ('\m' || r.re || '\s*\(');
    IF v_ref IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_166_REFUSED (G2b): another function body calls % (%) — roll that package back first. Nothing changed.', r.sig, v_ref;
    END IF;
  END LOOP;
  IF v_view IS NOT NULL THEN
    IF (SELECT c.relkind FROM pg_class c WHERE c.oid = v_view) <> 'v'
       OR md5(pg_get_viewdef(v_view)) IS DISTINCT FROM '02a452dfff5305946eda2b23be3d65bb' THEN
      RAISE EXCEPTION 'ROLLBACK_166_REFUSED (G1): venue_api.session_capacity is not 166''s view; a later migration replaced it — roll that package back first. Nothing changed.';
    END IF;
    SELECT string_agg(w.ev_class::regclass::text, ', ') INTO v_dep
      FROM pg_depend d JOIN pg_rewrite w ON d.classid = 'pg_rewrite'::regclass AND w.oid = d.objid
     WHERE d.refclassid = 'pg_class'::regclass AND d.refobjid = v_view AND w.ev_class <> v_view;
    IF v_dep IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_166_REFUSED (G2): another view depends on venue_api.session_capacity (%) — roll that package back first. Nothing changed.', v_dep;
    END IF;
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_ref
      FROM pg_proc p
     WHERE NOT (p.oid = ANY (v_own)) AND p.prosrc ~ '\mvenue_api\.session_capacity\M';
    IF v_ref IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_166_REFUSED (G2b): another function body reads venue_api.session_capacity (%) — roll that package back first. Nothing changed.', v_ref;
    END IF;
  END IF;
END $g$;

DROP VIEW IF EXISTS venue_api.session_capacity;

DROP FUNCTION IF EXISTS venue_cmd.get_session_capacity(uuid);
DROP FUNCTION IF EXISTS venue.list_session_capacity();
DROP FUNCTION IF EXISTS venue.get_session_capacity(uuid);

DO $verify$
DECLARE
  v_left text;
BEGIN
  SELECT string_agg(x, ', ' ORDER BY x) INTO v_left FROM (
    SELECT n.nspname || '.' || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname = 'venue'     AND p.proname IN ('get_session_capacity','list_session_capacity'))
        OR (n.nspname = 'venue_cmd' AND p.proname = 'get_session_capacity')
    UNION ALL
    SELECT 'venue_api.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'venue_api' AND c.relname = 'session_capacity'
  ) t(x);
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_166_VERIFY_FAILED: still present: %', v_left;
  END IF;
END $verify$;

COMMIT;
