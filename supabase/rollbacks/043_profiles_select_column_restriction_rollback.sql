-- =============================================================================
-- ROLLBACK for supabase/migrations/043_profiles_select_column_restriction.sql
-- DRAFT — companion to a migration that has not been applied.
--
-- ⚠ Intentionally OUTSIDE supabase/migrations/ so it is never picked up by
-- an automated `supabase db push` / `supabase migration up`.
--
-- Restores full, unrestricted SELECT on every column of public.profiles
-- for PUBLIC/anon/authenticated — i.e. re-opens the exposure 043 closed.
-- Use this only as an emergency unblock if 043 turns out to have been
-- applied before every client actually needed the restriction (e.g. an
-- overlooked call site, or adoption was lower than assumed) — the correct
-- long-term state is 043 applied, not this rollback.
--
-- Does not touch get_my_profile() (042) or any RLS policy — both are left
-- exactly as 043 left them.
-- =============================================================================

BEGIN;

GRANT SELECT ON public.profiles TO PUBLIC, anon, authenticated;

COMMIT;
