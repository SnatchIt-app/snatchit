-- Rollback for 044_realtime_publication_bids_listings.sql
-- Removes bids/listings from the supabase_realtime publication, restoring
-- the (latent, pre-existing) no-realtime-on-any-table state.

BEGIN;

ALTER PUBLICATION supabase_realtime DROP TABLE public.bids;
ALTER PUBLICATION supabase_realtime DROP TABLE public.listings;

COMMIT;
