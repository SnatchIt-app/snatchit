-- =============================================================================
-- 044_realtime_publication_bids_listings.sql
--
-- Root cause found while building web bidding (parity work, 2026-07-30):
-- neither `bids` nor `listings` was ever added to the `supabase_realtime`
-- publication (confirmed live — `select * from pg_publication_tables where
-- pubname = 'supabase_realtime'` returned zero rows, on every table, not
-- just these two). Both mobile's useListingRealtime hook and the new web
-- equivalent subscribe via `.channel(...).on('postgres_changes', ...)`,
-- which requires the source table to be in this publication — without it,
-- Postgres never replicates change events to Realtime, so every bid still
-- inserts correctly (RLS + validate_and_apply_bid() trigger are unaffected,
-- verified by a live test bid before this migration), but no client, mobile
-- or web, receives the live update; each has always required a manual
-- refetch. This migration does not change any table, column, policy, or
-- trigger — it only adds two existing tables to an existing publication.
--
-- Rollback: supabase/rollbacks/044_realtime_publication_bids_listings_rollback.sql
-- =============================================================================

BEGIN;

ALTER PUBLICATION supabase_realtime ADD TABLE public.bids;
ALTER PUBLICATION supabase_realtime ADD TABLE public.listings;

COMMIT;
