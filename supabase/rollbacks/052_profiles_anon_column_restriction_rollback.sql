-- Rollback for 052_profiles_anon_column_restriction.sql
--
-- WARNING: this restores unauthenticated read access to every column of every
-- row in public.profiles — wallet_balance, phone_number, full_name,
-- stripe_connect_id, stripe_customer_id, is_admin, trust_status_override — to
-- anyone holding the publishable anon key.
--
-- Only run this if the column restriction broke an anonymous read path that
-- cannot be fixed forward. Prefer granting the single missing column to `anon`
-- instead of restoring the blanket table-level grant.
--
-- Restores the exact pre-052 state captured from pg_class.relacl on 2026-08-05:
--   {postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,
--    anon=r/postgres,authenticated=r/postgres}

BEGIN;

-- Drop the per-column grants added by 052, then restore the table-level grant.
REVOKE SELECT ON public.profiles FROM anon;

GRANT SELECT ON public.profiles TO anon;

COMMIT;
