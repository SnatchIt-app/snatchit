-- =============================================================================
-- 041_profiles_column_grants.sql
-- Profiles security hardening — close column-level mass-assignment gap.
--
-- PROBLEM (confirmed live via information_schema this session): anon and
-- authenticated currently hold Supabase's default, unrestricted INSERT and
-- UPDATE grants on every column of public.profiles — including is_admin,
-- wallet_balance, stripe_connect_id, stripe_connect_status,
-- stripe_payouts_enabled, stripe_charges_enabled, stripe_onboarding_complete,
-- stripe_customer_id, is_verified_buyer, is_verified_seller, and
-- trust_status_override.
--
-- RLS's existing profiles_update_own policy (id = auth.uid()) correctly
-- restricts which ROW an authenticated user can touch, but RLS does not
-- restrict which COLUMNS a permitted UPDATE can set on that row. Right now
-- any authenticated user can PATCH their own profile row to set
-- is_admin = true, fabricate a wallet_balance, or fake Stripe/verification
-- state — the app's UI never does this, but nothing at the database layer
-- stops a direct PostgREST call from doing it.
--
-- This migration does not touch RLS policies, triggers, or SELECT — only
-- the INSERT/UPDATE/DELETE column-level grant surface for anon and
-- authenticated. Same REVOKE-then-GRANT pattern already established in
-- 040_web_accounts_foundation.sql for public.notifications.
--
-- Verified safe (this session, by reading every current call site):
--   - Every client UPDATE call site writes only to: full_name, display_name,
--     phone_number, bio, avatar_path, preferred_neighborhoods.
--       web/src/lib/profile-actions.ts:44   (full_name, display_name, phone_number)
--       app/settings/edit-profile.tsx:150   (avatar_path)
--       app/settings/edit-profile.tsx:209   (display_name, phone_number, bio)
--       app/settings/preferences.tsx:69     (preferred_neighborhoods)
--       app/(tabs)/profile.tsx:263          (avatar_path)
--   - No client code anywhere calls .insert() on profiles — row creation is
--     exclusively handle_new_user(), a SECURITY DEFINER trigger on
--     auth.users, which runs with the function owner's privileges and is
--     unaffected by revoking INSERT from anon/authenticated.
--   - No client code anywhere calls .delete() on profiles — account
--     deletion goes through delete_account_cleanup_rpc (020), a
--     SECURITY DEFINER function documented as service-role-only; there is
--     also no RLS DELETE policy on profiles today, so DELETE is already
--     fully blocked at the row level regardless of this grant.
--   - Every edge function that writes profiles' sensitive columns
--     (create-connect-account, stripe-webhook, confirm-and-release,
--     create-payment-intent, delete-account, enforce-transfer-expiry) uses
--     SUPABASE_SERVICE_ROLE_KEY exclusively. service_role's own separate
--     grants are untouched by this migration (REVOKE targets PUBLIC, anon,
--     authenticated only).
--
-- Explicitly NOT changed here (flagged, not fixed, by design):
--   - `phone` and `avatar_url` are legacy columns no current client code
--     writes to (avatar_url is set once, server-side, by handle_new_user()
--     at signup; phone_number/avatar_path are the live equivalents in
--     active use). Left out of the UPDATE grant — nothing currently needs
--     to write them from the client.
--   - SELECT is unchanged. profiles has public-read RLS policies today
--     (profiles_select_all / "profiles: public read", both qual = true),
--     which is how public listing pages show seller display names. That
--     means any anon/authenticated caller can currently SELECT every
--     column — including wallet_balance and Stripe IDs — for every user.
--     That is a separate, wider exposure question from the mass-assignment
--     one this migration closes; intentionally out of scope here.
--
-- Rollback: supabase/rollbacks/041_profiles_column_grants_rollback.sql
-- (kept outside supabase/migrations/ so it never auto-applies).
-- =============================================================================

BEGIN;

REVOKE ALL ON public.profiles FROM PUBLIC, anon, authenticated;

GRANT SELECT ON public.profiles TO anon, authenticated;

GRANT UPDATE (
  full_name,
  display_name,
  phone_number,
  bio,
  avatar_path,
  preferred_neighborhoods
) ON public.profiles TO authenticated;

COMMIT;
