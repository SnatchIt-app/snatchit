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
-- ============================================================================
BEGIN;

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
