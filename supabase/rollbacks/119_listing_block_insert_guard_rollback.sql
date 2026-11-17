-- ============================================================================
-- 119_listing_block_insert_guard_rollback.sql — mechanical reversal of 119.
-- Drops the BEFORE INSERT trigger and its function. After this, the listing
-- block is again advisory only (can_create_listing()). Gate-2 census returns
-- to functions=70 / triggers=26. Idempotent. Safe in production if ever
-- needed (no data touched); record the reason in the PR / runbook.
-- ============================================================================
BEGIN;
DROP TRIGGER IF EXISTS trg_guard_listing_seller_not_blocked ON public.listings;
DROP FUNCTION IF EXISTS public.guard_listing_seller_not_blocked();
COMMIT;
