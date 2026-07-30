-- =============================================================================
-- ROLLBACK for supabase/migrations/042_profiles_select_exposure.sql
-- (a.k.a. 042_profiles_get_my_profile_rpc.sql — see the migration's own
-- header; the file was narrowed to an RPC-only, additive-only migration
-- after 041's follow-up review, but keeps its original 042 filename.)
-- DRAFT — companion to a migration that has not been applied.
--
-- ⚠ Intentionally OUTSIDE supabase/migrations/ so it is never picked up by
-- an automated `supabase db push` / `supabase migration up`.
--
-- Drops get_my_profile(). Safe at any point before 043 is applied and
-- client code is shipped calling it: nothing else depends on this
-- function, and the currently-live app never calls it. 042 makes no other
-- change — no grant, RLS policy, trigger, or column was touched — so
-- dropping the function is the entire rollback.
--
-- If 043 has ALREADY been applied and new client code is already calling
-- get_my_profile() in production, do not run this in isolation — roll back
-- 043 first (restores direct-SELECT access), or the app will start seeing
-- "function does not exist" errors on every own-profile read.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.get_my_profile();

COMMIT;
