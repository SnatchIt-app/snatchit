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
--
-- Guard (refuses with nothing changed; psql -v ON_ERROR_STOP=1 exits 3):
--   G2b (A's N5, review of #169, 2026-10-26; 162's rollback G2b form) NO
--      function in any schema outside the seven functions this file drops may
--      reference one of them, and no view other than venue_api.session_admissions
--      may depend on one — dropping a function under an outside caller breaks
--      every call of it (A's case: an outside plpgsql caller of
--      venue.record_scan_staff was left dangling, rc 0). Roll that package back
--      first. Functions call by name, so pg_depend holds no edge for them: the
--      scan reads pg_proc.prosrc for the four venue names (unique to 163) and
--      for the venue_cmd-QUALIFIED call of venue_cmd.record_scan /
--      venue_cmd.validate_ticket_online (their bare names are 086's
--      venue.record_scan* / venue.validate_ticket_online, which stay); views are
--      read through pg_depend/pg_rewrite. 182 (the next package up) calls none
--      of 163's functions, so the guard does not fire for it. PART B's four
--      entries are NULL-safe (to_regprocedure) and inert when PART B never
--      landed or was dropped.
-- ============================================================================
BEGIN;

-- G2b (A's N5): no OUTSIDE caller of a function dropped here — any schema, functions and views.
DO $guard$
BEGIN
  IF EXISTS (
       SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname NOT IN ('pg_catalog','information_schema')
          AND p.oid NOT IN (SELECT o FROM unnest(ARRAY[
                to_regprocedure('venue.get_session_scan_counters(uuid)'),
                to_regprocedure('venue.list_session_scan_counters()'),
                to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'),
                -- PART B (NULL when PART B never landed)
                to_regprocedure('venue.filter_staff_scan_meta(jsonb)'),
                to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)'),
                to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'),
                to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)')
              ]::oid[]) AS o WHERE o IS NOT NULL)
          AND (p.prosrc LIKE '%get_session_scan_counters%' OR p.prosrc LIKE '%list_session_scan_counters%'
               OR p.prosrc LIKE '%filter_staff_scan_meta%' OR p.prosrc LIKE '%record_scan_staff%'
               OR p.prosrc ~* 'venue_cmd"?[[:space:]]*[.][[:space:]]*"?record_scan"?[[:space:]]*[(]'
               OR p.prosrc ~* 'venue_cmd"?[[:space:]]*[.][[:space:]]*"?validate_ticket_online"?[[:space:]]*[(]'))
  OR EXISTS (
       SELECT 1 FROM pg_depend d
         JOIN pg_rewrite r ON d.classid = 'pg_rewrite'::regclass AND d.objid = r.oid
        WHERE d.refclassid = 'pg_proc'::regclass
          AND d.refobjid IN (SELECT o FROM unnest(ARRAY[
                to_regprocedure('venue.get_session_scan_counters(uuid)'),
                to_regprocedure('venue.list_session_scan_counters()'),
                to_regprocedure('venue_cmd.get_session_scan_counters(uuid)'),
                to_regprocedure('venue.filter_staff_scan_meta(jsonb)'),
                to_regprocedure('venue.record_scan_staff(uuid, uuid, jsonb, text)'),
                to_regprocedure('venue_cmd.record_scan(uuid, uuid, jsonb, text)'),
                to_regprocedure('venue_cmd.validate_ticket_online(uuid, uuid)')
              ]::oid[]) AS o WHERE o IS NOT NULL)
          AND r.ev_class IS DISTINCT FROM to_regclass('venue_api.session_admissions')) THEN
    RAISE EXCEPTION 'ROLLBACK_163_REFUSED (G2b): a function or view outside 163 calls a function dropped here (venue.get_session_scan_counters / list_session_scan_counters / filter_staff_scan_meta / record_scan_staff, venue_cmd.get_session_scan_counters / record_scan / validate_ticket_online); roll that package back first. Nothing changed.';
  END IF;
END $guard$;

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
