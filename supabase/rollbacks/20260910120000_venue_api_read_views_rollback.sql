-- ============================================================================
-- 20260910120000_venue_api_read_views_rollback.sql — mechanical reversal.
-- Drops the six security_invoker views and the venue_api schema. No base table,
-- policy, grant or row is touched (the views never owned data). Idempotent.
-- If `venue_api` had been added to PostgREST's exposed schemas, remove it there
-- first or PostgREST will log a missing-schema warning until reload.
-- ============================================================================
BEGIN;
DROP VIEW IF EXISTS venue_api.inventory_batches;
DROP VIEW IF EXISTS venue_api.ticket_types;
DROP VIEW IF EXISTS venue_api.resale_policies;
DROP VIEW IF EXISTS venue_api.event_sessions;
DROP VIEW IF EXISTS venue_api.events;
DROP VIEW IF EXISTS venue_api.venues;
DROP SCHEMA IF EXISTS venue_api;
COMMIT;
