-- ============================================================================
-- 20261027010000_venue_cmd_event_verbs_rollback.sql — mechanical reversal of
-- registry 164 (pgTAP 231). Assigned by Claude A 2026-10-26 (registry 164/231).
--
-- Drops the seven SECURITY INVOKER wrappers 164 created in venue_cmd
-- (create_event, update_event, create_event_session, update_event_session,
-- publish_event, cancel_event, update_venue). NOTHING ELSE: 164 created no
-- table, no type, no schema, changed no body and touched no grant on any
-- pre-existing object — the seven catalog.* targets keep their 078/079/081/088
-- ACLs, which 164 never altered (its post-flight refused any difference) — so
-- nothing is restored. The wrappers' grants and comments go with them; no
-- default-ACL row was stored. Every DROP is IF EXISTS: the file is idempotent
-- and rc 0 on a database that never saw 164. The schema venue_cmd stays (161's).
-- The supabase_migrations ledger row is NOT removed here (separate, owner-
-- authorised step). If venue_cmd had been added to PostgREST's exposed schemas,
-- nothing here changes that setting.
-- ORDER: run this BEFORE 163's / 162's / 161's rollback (161's refuses while
-- venue_cmd holds a function it did not create).
-- ============================================================================
BEGIN;

DROP FUNCTION IF EXISTS venue_cmd.update_venue(uuid, jsonb, text);
DROP FUNCTION IF EXISTS venue_cmd.cancel_event(uuid, text, text);
DROP FUNCTION IF EXISTS venue_cmd.publish_event(uuid, text, text);
DROP FUNCTION IF EXISTS venue_cmd.update_event_session(uuid, jsonb, text);
DROP FUNCTION IF EXISTS venue_cmd.create_event_session(uuid, jsonb, text);
DROP FUNCTION IF EXISTS venue_cmd.update_event(uuid, jsonb, text);
DROP FUNCTION IF EXISTS venue_cmd.create_event(uuid, text, jsonb, text);

DO $verify$
DECLARE
  v_left text;
BEGIN
  SELECT string_agg(p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')', ', ' ORDER BY p.proname)
    INTO v_left
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'venue_cmd'
     AND p.proname IN ('create_event','update_event','create_event_session','update_event_session',
                       'publish_event','cancel_event','update_venue');
  IF v_left IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_164_VERIFY_FAILED: still present in venue_cmd: %', v_left;
  END IF;
END $verify$;

COMMIT;
