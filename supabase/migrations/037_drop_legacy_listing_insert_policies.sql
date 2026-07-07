-- =============================================================================
-- 037_drop_legacy_listing_insert_policies.sql
-- Permissive RLS policies are OR'ed: two legacy INSERT policies found in
-- production ("listings_insert_authenticated", "listings_insert_own" — not in
-- schema.sql) allowed any authenticated seller_id insert, bypassing the 036
-- payout-setup guard entirely. Drop them so "listings: auth insert" (036) is
-- the single INSERT path: seller must have stripe_onboarding_complete = true.
-- service_role continues to bypass RLS (admin/demo flows unaffected).
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "listings_insert_authenticated" ON public.listings;
DROP POLICY IF EXISTS "listings_insert_own"           ON public.listings;

COMMIT;
