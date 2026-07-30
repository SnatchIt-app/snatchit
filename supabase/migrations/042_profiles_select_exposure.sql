-- =============================================================================
-- 042_profiles_get_my_profile_rpc.sql
-- DRAFT — NOT APPLIED.
--
-- Stage 1 of 2 in the profiles SELECT-exposure remediation. See
-- 043_profiles_select_column_restriction.sql for stage 2 (the actual
-- enforcement), which must NOT be applied until mobile adoption is
-- confirmed — see the release-sequence notes in the accompanying report.
--
-- Purely additive: creates get_my_profile(), a SECURITY DEFINER RPC
-- returning the caller's own private profile fields. Touches no existing
-- grant, RLS policy, trigger, or column on public.profiles. The
-- currently-live (App-Store-submitted) mobile build, which reads these
-- fields directly from public.profiles, is completely unaffected by
-- applying this migration on its own — it doesn't know this function
-- exists and never calls it. Safe to apply independently of 043, any time.
--
-- Return set — re-audited this session against every "own profile" call
-- site in web/src, app/, and src/screens/ (web/src/lib/profile.ts;
-- app/settings/payout-setup.tsx, preferences.tsx, edit-profile.tsx;
-- app/(tabs)/profile.tsx, home.tsx; src/screens/CreateListingScreen.tsx):
-- full_name, display_name, phone_number, is_verified_buyer,
-- is_verified_seller, created_at, avatar_path, avatar_url, bio,
-- wallet_balance, stripe_connect_id, stripe_onboarding_complete,
-- preferred_neighborhoods. Deliberately excludes every column no current
-- call site reads even for the owner's own profile: is_admin,
-- trust_status_override, stripe_connect_status, stripe_payouts_enabled,
-- stripe_charges_enabled, stripe_customer_id, and the legacy `phone` column.
--
-- Safeguards:
--   - SECURITY DEFINER + explicit SET search_path = public (prevents
--     search-path hijacking of the unqualified auth.uid() / table ref).
--   - No parameters — auth.uid() is the only identity source, nothing to
--     spoof by passing a different id.
--   - Explicit auth.uid() IS NULL guard: raises rather than silently
--     returning zero rows, so an unauthenticated caller gets a clear error
--     instead of an ambiguous empty result (defense in depth — EXECUTE is
--     not granted to anon anyway, so this should be unreachable in
--     practice).
--   - RETURNS TABLE with an explicit, named column list, not
--     RETURNS public.profiles / SELECT * — the function signature itself
--     caps what can come back; widening it later requires a visible
--     CREATE OR REPLACE, not a quietly edited query.
--   - No dynamic SQL — a single static SELECT.
--   - REVOKE ALL FROM PUBLIC, anon, authenticated, then GRANT EXECUTE to
--     authenticated only — anon is explicitly denied, not just omitted.
--   - service_role is never named — its own grants and RLS bypass are
--     untouched.
--
-- Rollback: supabase/rollbacks/042_profiles_get_my_profile_rpc_rollback.sql
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS TABLE (
  id                          uuid,
  full_name                   text,
  display_name                text,
  phone_number                text,
  is_verified_buyer           boolean,
  is_verified_seller          boolean,
  created_at                  timestamptz,
  avatar_path                 text,
  avatar_url                  text,
  bio                         text,
  wallet_balance               numeric,
  stripe_connect_id            text,
  stripe_onboarding_complete  boolean,
  preferred_neighborhoods     text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  caller uuid := auth.uid();
BEGIN
  IF caller IS NULL THEN
    RAISE EXCEPTION 'get_my_profile() requires an authenticated caller';
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.full_name, p.display_name, p.phone_number, p.is_verified_buyer,
    p.is_verified_seller, p.created_at, p.avatar_path, p.avatar_url, p.bio,
    p.wallet_balance, p.stripe_connect_id, p.stripe_onboarding_complete,
    p.preferred_neighborhoods
  FROM public.profiles p
  WHERE p.id = caller;
END;
$$;

COMMENT ON FUNCTION public.get_my_profile() IS
  'Returns the calling user''s own private profile fields only. No parameters — always auth.uid(). Introduced alongside 043, which restricts direct SELECT on public.profiles to the public-safe column set.';

REVOKE ALL ON FUNCTION public.get_my_profile() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated;

COMMIT;
