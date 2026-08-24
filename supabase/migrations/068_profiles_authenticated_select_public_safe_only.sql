-- Migration 068: restrict the authenticated SELECT grant on profiles to public-safe columns
--
-- Finding addressed: H-1-residual (Medium). After migrations 052/062, anon can read only
--   public-safe profile columns, but `authenticated` retained column SELECT on
--   full_name, phone_number, stripe_connect_id, wallet_balance — meaning any signed-in user
--   could read every other user's wallet balance, Stripe Connect id, phone, and legal name via
--   a direct PostgREST select (BOLA / API3 broken object-property-level authorization).
--
-- Why this is safe (verified 2026-08-24):
--   - Every self-profile read in the app uses the get_my_profile() RPC (SECURITY DEFINER),
--     which returns the owner's full row independent of table grants — so self-service
--     (payout setup, edit profile, home, profile tab) is unaffected.
--   - Every cross-user read selects only public-safe columns: app/profile/[id].tsx and
--     src/screens/ListingDetailScreen.tsx explicitly avoid phone/stripe/wallet.
--   - No client code performs `.from('profiles').select(<sensitive>)` for any user.
--
-- Forward behavior: revoke the blanket authenticated SELECT and re-grant SELECT on exactly the
--   public-safe column set (same columns anon may read). Column-level metadata change; no data
--   touched. Validated in a rolled-back transaction against production before finalizing.
-- Expected locks: catalog-row only. Runtime: milliseconds.
-- Rollback: rollbacks/068_..._rollback.sql re-grants SELECT on the previously-exposed columns.
-- Verification (after apply):
--   select privilege_type, string_agg(column_name,', ' order by column_name)
--     from information_schema.role_column_grants
--    where table_schema='public' and table_name='profiles' and grantee='authenticated'
--    group by privilege_type;
--   -- SELECT list must be: avatar_path, avatar_url, bio, created_at, display_name,
--   --                      id, is_verified_seller, stripe_onboarding_complete

revoke select on public.profiles from authenticated;
grant  select (id, display_name, avatar_url, avatar_path, bio, created_at,
               is_verified_seller, stripe_onboarding_complete)
  on public.profiles to authenticated;
