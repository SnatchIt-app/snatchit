-- =============================================================================
-- 038_listing_requires_verified_phone.sql
-- Selling now requires a VERIFIED phone (Supabase Phone Auth, phone_change
-- OTP flow) in addition to completed Stripe payout onboarding (036/037).
--
-- Truth source: auth.users.phone_confirmed_at — set only by Supabase Auth
-- when an OTP is verified. Clients cannot write it, so no mirrored profile
-- flag is needed. Exposed to RLS via a SECURITY DEFINER helper because the
-- authenticated role cannot read auth.users directly.
--
-- service_role bypasses RLS → admin tooling / demo seeding unaffected.
-- Browsing, bidding, and buying are NOT gated — selling only.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.phone_verified()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users
     WHERE id = auth.uid()
       AND phone_confirmed_at IS NOT NULL
  );
$$;

REVOKE ALL ON FUNCTION public.phone_verified() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.phone_verified() TO authenticated, service_role;

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
    AND public.phone_verified()
  );

COMMIT;
