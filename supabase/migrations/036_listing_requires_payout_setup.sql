-- =============================================================================
-- 036_listing_requires_payout_setup.sql
-- Server-side listing guard: the client-side stripe_onboarding_complete gate
-- (CreateListingScreen) was the ONLY enforcement. Strengthen the listings
-- INSERT RLS policy so a listing row can only be created by a seller whose
-- payout onboarding is complete.
--
-- Safety:
--   • service_role bypasses RLS → admin tooling, demo seeding, and edge
--     functions are unaffected.
--   • The flag is written by create-connect-account (status check) and the
--     Stripe account.updated webhook BEFORE the client gate ever passes, so
--     legitimate sellers cannot be rejected by flag lag.
--   • UPDATE/SELECT/DELETE policies untouched — existing listings unaffected.
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "listings: auth insert" ON public.listings;
CREATE POLICY "listings: auth insert"
  ON public.listings FOR INSERT
  WITH CHECK (
    seller_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.profiles p
       WHERE p.id = auth.uid()
         AND p.stripe_onboarding_complete = true
    )
  );

COMMIT;
