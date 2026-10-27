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
--
-- Guards (A's N2, review of 164-167/165, 2026-10-27; 167's G1/G2/G2b block is the
-- model). Each refuses with NOTHING changed (psql -v ON_ERROR_STOP=1 exits 3); a
-- wrapper that is already absent is tolerated (idempotent re-run):
--   G1  the live body of each present wrapper must hash (md5 of prosrc) to 164's —
--       otherwise a later migration replaced it and this file would silently
--       remove that package's object: roll it back first.
--   G2  no catalog object (a view, a default, …) may depend on one of them (pg_depend).
--   G2b no OTHER function body may call one of them by name ('venue_cmd.<name>(',
--       word-bounded over every pg_proc prosrc — plpgsql / sql bodies record no
--       pg_depend row for the functions they call; A's case: an outside plpgsql
--       caller of venue_cmd.publish_event survived the old rollback rc 0 and then
--       failed 42883).
--   164 bodies (md5 prosrc, PG17):
--     venue_cmd.create_event(uuid, text, jsonb, text)      449f43e0aacc02c970ae44e179d547e4
--     venue_cmd.update_event(uuid, jsonb, text)            8e556d5ca13ec261134a04cdfb5c6b26
--     venue_cmd.create_event_session(uuid, jsonb, text)    41f8b55a70e1ea6698d5b1e654ea25d7
--     venue_cmd.update_event_session(uuid, jsonb, text)    8f8eeaca4d1d74c805e123ef90b8e340
--     venue_cmd.publish_event(uuid, text, text)            09fd6c26f49316411bacea7797b206bd
--     venue_cmd.cancel_event(uuid, text, text)             09b321729670af3113ea22babf02b329
--     venue_cmd.update_venue(uuid, jsonb, text)            164862649cd50f3bbfa1bfbe38dcc584
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $g$
DECLARE
  r record;
  v_md5 text;
  v_dep text;
  v_ref text;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('venue_cmd.create_event(uuid, text, jsonb, text)', '449f43e0aacc02c970ae44e179d547e4'),
      ('venue_cmd.update_event(uuid, jsonb, text)', '8e556d5ca13ec261134a04cdfb5c6b26'),
      ('venue_cmd.create_event_session(uuid, jsonb, text)', '41f8b55a70e1ea6698d5b1e654ea25d7'),
      ('venue_cmd.update_event_session(uuid, jsonb, text)', '8f8eeaca4d1d74c805e123ef90b8e340'),
      ('venue_cmd.publish_event(uuid, text, text)', '09fd6c26f49316411bacea7797b206bd'),
      ('venue_cmd.cancel_event(uuid, text, text)', '09b321729670af3113ea22babf02b329'),
      ('venue_cmd.update_venue(uuid, jsonb, text)', '164862649cd50f3bbfa1bfbe38dcc584')) AS x(sig, want)
  LOOP
    IF to_regprocedure(r.sig) IS NULL THEN
      RAISE NOTICE 'ROLLBACK_164: % is already absent (tolerated).', r.sig;
      CONTINUE;
    END IF;
    SELECT md5(p.prosrc) INTO v_md5 FROM pg_proc p WHERE p.oid = to_regprocedure(r.sig);
    IF v_md5 IS DISTINCT FROM r.want THEN
      RAISE EXCEPTION 'ROLLBACK_164_REFUSED (G1): the live body of % is not 164''s (md5 % <> %); a later migration replaced it — roll that package back first. Nothing changed.', r.sig, v_md5, r.want;
    END IF;
    SELECT string_agg(d.classid::regclass::text || ':' || d.objid::text, ', ') INTO v_dep
      FROM pg_depend d
     WHERE d.refobjid = to_regprocedure(r.sig)
       AND d.refclassid = 'pg_proc'::regclass
       AND d.deptype <> 'i'
       AND NOT (d.classid = 'pg_proc'::regclass AND d.objid = to_regprocedure(r.sig));
    IF v_dep IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_164_REFUSED (G2): another catalog object depends on % (%) — roll that package back first. Nothing changed.', r.sig, v_dep;
    END IF;
    SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_ref
      FROM pg_proc p
     WHERE p.oid <> to_regprocedure(r.sig)
       AND p.prosrc ~ ('\mvenue_cmd\.' || split_part(split_part(r.sig, '.', 2), '(', 1) || '\s*\(');
    IF v_ref IS NOT NULL THEN
      RAISE EXCEPTION 'ROLLBACK_164_REFUSED (G2b): another function body calls % (%) — roll that package back first. Nothing changed.', r.sig, v_ref;
    END IF;
  END LOOP;
END $g$;

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
