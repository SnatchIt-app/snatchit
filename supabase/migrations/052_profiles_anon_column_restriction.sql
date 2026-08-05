-- =============================================================================
-- 052_profiles_anon_column_restriction.sql
--
-- STATUS: PREPARED, NOT YET APPLIED (2026-08-05).
-- Reviewed and ready; the automated apply was refused by the tooling guardrail
-- that gates REVOKE statements against production. Awaiting an operator to
-- apply it. Everything below has been verified against live state; no part of
-- this migration has taken effect yet.
--
-- Stage 1.5 of the profiles SELECT hardening: the half of 043 that is safe to
-- ship TODAY, without waiting on the App Store adoption gate.
--
-- LIVE EXPOSURE. public.profiles has two RLS SELECT policies, both qual = true,
-- and a table-level SELECT grant to `anon`. So anyone holding the publishable
-- anon key — which ships inside both clients and is therefore public — can read
-- EVERY column of EVERY user row today, including:
--   wallet_balance, stripe_connect_id, stripe_customer_id, stripe_charges_enabled,
--   stripe_payouts_enabled, stripe_connect_status, phone, phone_number,
--   full_name, is_admin, trust_status_override, is_verified_buyer,
--   preferred_neighborhoods.
--
-- 043 is the full fix and remains correctly UNAPPLIED: it revokes from
-- `authenticated` too, which breaks the currently-submitted mobile build (it
-- reads wallet_balance / phone_number / stripe_connect_id / is_verified_buyer /
-- preferred_neighborhoods straight off profiles with no fallback).
--
-- KEY OBSERVATION that makes this migration safe now: every read of a sensitive
-- column, in both clients, is a read of the caller's OWN row over an
-- AUTHENTICATED session. Audited exhaustively:
--   mobile app/(tabs)/profile.tsx:138        own row  (wallet_balance, phone_number, ...)
--   mobile app/settings/edit-profile.tsx:104 own row  (phone_number)
--   mobile app/settings/payout-setup.tsx:65  own row  (stripe_connect_id)
--   mobile src/screens/CreateListingScreen.tsx:394 own row (stripe_connect_id)
--   mobile app/(tabs)/home.tsx:49, settings/preferences.tsx:41 own row (preferred_neighborhoods)
-- Every OTHER-user read is already confined to the public-safe set:
--   mobile src/screens/ListingDetailScreen.tsx:365, app/profile/[id].tsx:268,
--   app/settings/blocked-users.tsx:86, web listings.ts:131, and the
--   profiles(display_name) embeds in web sales.ts / transfers.ts / useListingBids.ts.
--
-- Nothing anywhere reads a sensitive profile column as `anon`. So revoking them
-- from `anon` ONLY closes the unauthenticated internet-wide exposure while
-- leaving `authenticated` bit-for-bit untouched — the shipped mobile build
-- (build 13, in App Review) cannot be affected by this migration.
--
-- The public-safe column set is copied verbatim from 043 so the two migrations
-- stay consistent; 043 later applies the same set to `authenticated`.
--
-- Grants are direct and table-level (relacl: anon=r/postgres,
-- authenticated=r/postgres) — there is no grant to PUBLIC, so revoking from
-- `anon` cannot leak through role inheritance.
--
-- Does NOT touch: RLS policies (both stay qual = true — the column grant is
-- what enforces this, exactly as in 043), the 041 UPDATE column grants,
-- triggers, service_role, or the profiles_select_all vs "profiles: public read"
-- policy drift (still deliberately left alone).
--
-- No data is read, moved, or deleted. Grants only. Fully reversible.
--
-- Rollback: supabase/rollbacks/052_profiles_anon_column_restriction_rollback.sql
-- =============================================================================

BEGIN;

REVOKE SELECT ON public.profiles FROM anon;

GRANT SELECT (
  id,
  display_name,
  avatar_path,
  avatar_url,
  bio,
  created_at,
  is_verified_seller,
  stripe_onboarding_complete
) ON public.profiles TO anon;

COMMIT;
