-- ============================================================================
-- 20261021120000_venue_api_read_views_rollback.sql — mechanical reversal.
--
-- PROVISIONAL version and pgTAP number — A assigns the final ones in docs/release/MIGRATION_NUMBER_REGISTRY.md on origin/release/candidate-20260918
--
-- Re-timestamped copy of origin/venue/dashboard-v2
-- supabase/rollbacks/20260910120000_venue_api_read_views_rollback.sql (blob
-- 114b94ed); the statements from BEGIN to COMMIT are byte-identical.
--
-- Drops the eight security_invoker views and the venue_api schema. No base table,
-- policy, grant or row is touched (the views never owned data). Idempotent.
-- The views' grants and comments go with them. The migration's
-- ALTER DEFAULT PRIVILEGES … REVOKE stores no pg_default_acl row (the built-in
-- table default already grants nothing), so nothing is left behind; the
-- rehearsal proves the full catalog returns to its pre-apply fingerprint.
-- DROP SCHEMA is deliberately NOT CASCADE: if anything else was ever created
-- in venue_api, the rollback stops instead of silently dropping it.
-- If `venue_api` had been added to PostgREST's exposed schemas, remove it there
-- first or PostgREST will log a missing-schema warning until reload.
-- The supabase_migrations ledger row is NOT removed here; that is a separate,
-- owner-authorised step (docs/venue-dashboard/VENUE_API_PROVISIONAL_MIGRATION.md).
-- ============================================================================
BEGIN;
DROP VIEW IF EXISTS venue_api.my_org_roles;
DROP VIEW IF EXISTS venue_api.my_staff_roles;
DROP VIEW IF EXISTS venue_api.inventory_batches;
DROP VIEW IF EXISTS venue_api.ticket_types;
DROP VIEW IF EXISTS venue_api.resale_policies;
DROP VIEW IF EXISTS venue_api.event_sessions;
DROP VIEW IF EXISTS venue_api.events;
DROP VIEW IF EXISTS venue_api.venues;
DROP SCHEMA IF EXISTS venue_api;
COMMIT;
