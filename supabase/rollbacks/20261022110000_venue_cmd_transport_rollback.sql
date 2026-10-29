-- ============================================================================
-- 20261022110000_venue_cmd_transport_rollback.sql — mechanical reversal of
-- registry 161 (pgTAP 228). Assigned by Claude A 2026-10-22 (registry 573850a4).
--
-- Drops the six SECURITY INVOKER wrappers and schema venue_cmd. The wrappers
-- own no data and no authority (every rule lives in the venue.* definer bodies),
-- so nothing but the transport goes away. Their grants and comments go with
-- them. The schema's REVOKE/GRANT stored no default-ACL row, so nothing is left
-- behind. DROP SCHEMA is deliberately NOT CASCADE and the guard refuses if the
-- schema holds anything other than the six functions this migration created:
-- a later object is somebody else's and is not dropped silently.
-- Run this BEFORE 160's rollback (which refuses while venue_cmd exists).
-- If venue_cmd had been added to PostgREST's exposed schemas, remove it there
-- first. The supabase_migrations ledger row is NOT removed here (separate,
-- owner-authorised step).
-- ============================================================================
BEGIN;

DO $guard$
DECLARE
  v_extra text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'venue_cmd') THEN
    RAISE NOTICE 'venue_cmd does not exist; nothing to roll back.';
    RETURN;
  END IF;
  -- any relation, type (other than none), or function outside the six -> refuse
  SELECT string_agg(x, ', ' ORDER BY x) INTO v_extra FROM (
    SELECT 'relation ' || c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'venue_cmd'
    UNION ALL
    SELECT 'function ' || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')'
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'venue_cmd'
       AND p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' NOT IN (
         'create_ticket_type(uuid, text, text, integer, text, text)',
         'set_ticket_type_price(uuid, integer, text, text)',
         'set_ticket_type_visibility(uuid, text, text, text)',
         'set_ticket_type_rank(uuid, smallint, text)',
         'set_batch_capacity(uuid, integer, text, text)',
         'get_inventory_counters(uuid)')
  ) t(x);
  IF v_extra IS NOT NULL THEN
    RAISE EXCEPTION 'ROLLBACK_161_REFUSED: venue_cmd holds objects 161 did not create (%); nothing changed.', v_extra;
  END IF;
END $guard$;

DROP FUNCTION IF EXISTS venue_cmd.get_inventory_counters(uuid);
DROP FUNCTION IF EXISTS venue_cmd.set_batch_capacity(uuid, integer, text, text);
DROP FUNCTION IF EXISTS venue_cmd.set_ticket_type_rank(uuid, smallint, text);
DROP FUNCTION IF EXISTS venue_cmd.set_ticket_type_visibility(uuid, text, text, text);
DROP FUNCTION IF EXISTS venue_cmd.set_ticket_type_price(uuid, integer, text, text);
DROP FUNCTION IF EXISTS venue_cmd.create_ticket_type(uuid, text, text, integer, text, text);
DROP SCHEMA IF EXISTS venue_cmd;

DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'venue_cmd') THEN
    RAISE EXCEPTION 'ROLLBACK_161_VERIFY_FAILED: venue_cmd still exists.';
  END IF;
END $verify$;

COMMIT;
