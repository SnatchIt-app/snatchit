-- =============================================================================
-- Migration 029: Public seller profiles — safe fields + RLS (Community feature)
-- =============================================================================
-- Minimal trust-profile feature. This migration only guarantees the two
-- profile-safe, user-editable text columns exist and that RLS allows:
--   • anyone to READ profiles  (the public seller profile screen), and
--   • a user to UPDATE only their own profile row.
--
-- It deliberately does NOT touch payment / Stripe / wallet columns or any
-- payout logic. App-Review-safe: the public profile screen selects only safe
-- columns (display_name, avatar, bio, created_at, stripe_onboarding_complete
-- as a boolean verified flag, is_verified_seller). No email/phone/Stripe IDs
-- are surfaced by the client.
--
-- Fully idempotent: re-running is a no-op. bio + avatar_url already exist on
-- existing projects; the IF NOT EXISTS guards make this safe everywhere.
-- =============================================================================

BEGIN;

-- 1. Profile-safe, user-editable columns ------------------------------------
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bio        text;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url text;

-- 2. RLS --------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Public read: anyone (incl. anon) may SELECT profile rows. The client only
-- ever selects profile-safe columns on the public screen.
DROP POLICY IF EXISTS "profiles: public read" ON public.profiles;
CREATE POLICY "profiles: public read" ON public.profiles
  FOR SELECT
  USING (true);

-- Update own: a user may UPDATE only their own row.
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

COMMIT;
