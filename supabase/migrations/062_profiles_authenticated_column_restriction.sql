-- 062 — take the unreferenced sensitive profile columns away from `authenticated`.
--
-- This is the safely-shippable part of migration 043. The rest of 043 is
-- BLOCKED, and deliberately not applied here — see the note at the bottom.
--
-- profiles has two RLS SELECT policies that are both USING (true)
-- ('profiles: public read' and 'profiles_select_all'), so any signed-in user
-- can read every row of every other user. 052 already fixed this for `anon` by
-- revoking table-wide SELECT and re-granting a public-safe column list. The
-- same treatment for `authenticated` is what 043 describes.
--
-- Column privileges in Postgres are per-role, not per-row, so a column granted
-- to `authenticated` is readable on ANY row, not just the caller's own. That
-- makes the column list the only lever available without breaking the embedded
-- joins that both clients rely on (`profiles!seller_id(display_name)` etc.).
--
-- Revoked here — verified to have ZERO references in either client tree
-- (web/src, and the mobile src/ + app/ trees at build 13):
--
--   phone                    legacy duplicate of phone_number
--   stripe_customer_id       Stripe internal id
--   stripe_connect_id        NOT revoked -- see below
--   stripe_connect_status    Connect internals, written by the webhook
--   stripe_payouts_enabled     "
--   stripe_charges_enabled     "
--   is_admin                 admin flag -- disclosing this hands an attacker a target list
--   trust_status_override    moderation state
--
-- Kept, because the SHIPPED mobile client reads them directly from the table
-- rather than through get_my_profile(), so revoking would break build 13:
--
--   phone_number             app/(tabs)/profile.tsx:137, app/settings/edit-profile.tsx:103
--   wallet_balance           app/(tabs)/profile.tsx:137
--   stripe_connect_id        app/(tabs)/profile.tsx:137,
--                            src/screens/CreateListingScreen.tsx:393,
--                            app/settings/payout-setup.tsx:64
--   full_name                read CROSS-USER by the bid-history join,
--                            src/hooks/useListingRealtime.ts:63:
--                              '*, profiles(full_name, display_name, avatar_url)'
--   preferred_neighborhoods  app/settings/preferences.tsx:40, app/(tabs)/home.tsx:48
--   is_verified_buyer        app/(tabs)/profile.tsx:137
--
-- So the remainder of 043 cannot be applied from the database alone. Closing it
-- needs a mobile release first: move the self-reads onto get_my_profile()
-- (which is SECURITY DEFINER and therefore unaffected by column grants), and
-- drop full_name from BIDS_SELECT so bid history stops showing other bidders'
-- legal names. Only then can phone_number, wallet_balance, stripe_connect_id
-- and full_name be revoked from `authenticated`.
--
-- Applying the full 043 list today would break a build that is in App Review.

-- `authenticated` currently holds BOTH a table-wide SELECT and an explicit
-- grant on all 21 columns. REVOKE SELECT ON TABLE clears both, so the grant
-- below is the complete allow-list — same shape as 052 did for anon.

REVOKE SELECT ON public.profiles FROM authenticated;

GRANT SELECT (
  id,
  created_at,
  full_name,
  display_name,
  phone_number,
  avatar_url,
  avatar_path,
  is_verified_buyer,
  is_verified_seller,
  wallet_balance,
  bio,
  stripe_connect_id,
  preferred_neighborhoods,
  stripe_onboarding_complete
) ON public.profiles TO authenticated;
