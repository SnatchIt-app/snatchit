-- ============================================================================
-- 20261026110000_scanner_staff_session_and_scan_counters_rollback.sql —
-- mechanical reversal of registry 163 (pgTAP 230). Assigned by Claude A
-- 2026-10-26 (CONTRACTS.md §4; C7 amendment 2026-10-26).
--
-- Drops, in dependency order, the view venue_api.session_admissions, the three
-- venue_cmd SECURITY INVOKER wrappers (get_session_scan_counters, record_scan,
-- validate_ticket_online), venue.record_scan_staff, its zero-grant helper
-- venue.filter_staff_scan_meta and the two counters functions
-- venue.list_session_scan_counters / venue.get_session_scan_counters.
-- NOTHING ELSE: 163 touched no table, no policy, no 086/108 scan body and no
-- grant on a pre-existing object, so nothing is restored. Every DROP is IF
-- EXISTS: the file is idempotent, and it is correct whether or not PART B (the
-- DROPPABLE staff-session commit) ever landed. rc 0 on a database that never
-- saw 163. The grants and comments go with the objects; no default-ACL row was
-- stored. The supabase_migrations ledger row is NOT removed here (separate,
-- owner-authorised step). If venue_api / venue_cmd had been added to
-- PostgREST's exposed schemas, nothing here changes that setting.
-- ORDER: run this BEFORE 161's rollback (which refuses while venue_cmd holds a
-- function it did not create), BEFORE 160's and BEFORE 159's (which refuses
-- while venue_api holds a ninth view).
-- ============================================================================
BEGIN;

DROP VIEW IF EXISTS venue_api.session_admissions;

DROP FUNCTION IF EXISTS venue_cmd.validate_ticket_online(uuid, uuid);
DROP FUNCTION IF EXISTS venue_cmd.record_scan(uuid, uuid, jsonb, text);
DROP FUNCTION IF EXISTS venue.record_scan_staff(uuid, uuid, jsonb, text);
DROP FUNCTION IF EXISTS venue.filter_staff_scan_meta(jsonb);

DROP FUNCTION IF EXISTS venue_cmd.get_session_scan_counters(uuid);
DROP FUNCTION IF EXISTS venue.list_session_scan_counters();
DROP FUNCTION IF EXISTS venue.get_session_scan_counters(uuid);

DO $verify$
DECLARE
  v_left text;
BEGIN
  SELECT string_agg(x, ', ' ORDER BY x) INTO v_left FROM (
    SELECT n.nspname || '.' || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname = 'venue'     AND p.proname IN ('get_session_scan_counters','list_session_scan_counters','record_scan_staff','filter_staff_scan_meta'))
        OR (n.nspname = 'venue_cmd' AND p.proname IN ('get_session_scan_counters','record_scan','validate_ticket_online'))
    UNION ALL
    SELECT 'venue_api.' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'venue_api' AND c.relname = 'session_admissions'
  ) t(x);
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_163_VERIFY_FAILED: still present: %', v_left;
  END IF;
END $verify$;

COMMIT;
