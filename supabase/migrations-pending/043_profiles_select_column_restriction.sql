-- =============================================================================
-- 043_profiles_select_column_restriction.sql
-- DRAFT — NOT APPLIED. Stage 2 of 2.
--
-- DO NOT APPLY until the adoption gate in the release-sequence report is
-- satisfied. This migration WILL break any mobile client still on the
-- currently-submitted App Store build, which reads is_verified_buyer,
-- wallet_balance, stripe_connect_id, preferred_neighborhoods, and
-- phone_number directly from public.profiles with no fallback path.
--
-- Prerequisites before applying:
--   1. 042 (get_my_profile RPC) already applied.
--   2. New web + mobile client code shipped, calling get_my_profile()
--      instead of reading these fields directly from profiles (see the
--      accompanying report's Phase 3 diffs).
--   3. New mobile build approved by Apple, and the adoption/enforcement
--      gate recommended in the release-sequence report has been met.
--
-- Restricts base-table SELECT to the public-safe column set for anon and
-- authenticated, uniformly for every row — this is what actually closes
-- the exposure. wallet_balance, stripe_connect_id, stripe_customer_id,
-- is_admin, trust_status_override, etc. become unreadable via direct
-- SELECT for everyone, including the row's own owner; the owner's copies
-- of the non-public fields come only from get_my_profile() (042) after
-- this point.
--
-- Public-safe column set — matches every "other user" read site audited
-- this session (public listing pages, seller/community profile screens,
-- blocked-user names, transfer/bid counterparty names):
-- id, display_name, avatar_path, avatar_url, bio, created_at,
-- is_verified_seller, stripe_onboarding_complete (the last one only ever
-- consumed as a boolean "verified" signal, matching 029's original intent
-- — no Stripe identifier is exposed).
--
-- Does not touch RLS policies (both existing SELECT policies remain
-- qual = true — the column grant is what performs the actual restriction
-- now, not row visibility), the 041 UPDATE grant, triggers, or
-- service_role.
--
-- The profiles_select_all vs. "profiles: public read" policy-drift cleanup
-- (see report Phase 2) is intentionally NOT included here, per explicit
-- instruction not to drop either policy yet. It changes nothing about
-- enforcement either way, since this migration's restriction works
-- entirely through the column grant, independent of which/how many
-- always-true SELECT policies exist.
--
-- Rollback: supabase/rollbacks/043_profiles_select_column_restriction_rollback.sql
-- =============================================================================

BEGIN;

REVOKE SELECT ON public.profiles FROM PUBLIC, anon, authenticated;

GRANT SELECT (
  id,
  display_name,
  avatar_path,
  avatar_url,
  bio,
  created_at,
  is_verified_seller,
  stripe_onboarding_complete
) ON public.profiles TO anon, authenticated;

COMMIT;
