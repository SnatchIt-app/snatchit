-- =============================================================================
-- ROLLBACK for supabase/migrations/041_profiles_column_grants.sql
--
-- ⚠ This file is intentionally OUTSIDE supabase/migrations/ so it is never
-- picked up by an automated `supabase db push` / `supabase migration up` —
-- it is a script to run manually (via the same apply_migration workflow, or
-- the SQL editor) only if migration 041 needs to be reversed.
--
-- Restores the exact pre-migration grant state on public.profiles: full,
-- unrestricted INSERT/UPDATE/DELETE/REFERENCES/TRIGGER/TRUNCATE for PUBLIC,
-- anon, and authenticated — i.e. undoes the column-level restriction and
-- re-opens every column (including is_admin, wallet_balance, and the
-- Stripe/verification fields) to client UPDATE again.
--
-- Explicitly does NOT touch, and cannot touch, because it names nothing
-- else:
--   - RLS policies on public.profiles (profiles_update_own, profiles_select_*,
--     profiles_insert_own are untouched by both 041 and this rollback)
--   - any trigger or function
--   - service_role's grants (041 never modified them, so there is nothing
--     to restore)
--   - any other table
--
-- Run this only if 041 is confirmed to have broken a legitimate write path
-- that testing didn't catch. Safe to re-run.
-- =============================================================================

BEGIN;

GRANT ALL ON public.profiles TO PUBLIC, anon, authenticated;

COMMIT;
