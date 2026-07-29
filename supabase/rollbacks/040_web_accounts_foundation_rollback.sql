-- =============================================================================
-- ROLLBACK for supabase/migrations/040_web_accounts_foundation.sql
--
-- ⚠ This file is intentionally OUTSIDE supabase/migrations/ so it is never
-- picked up by an automated `supabase db push` / `supabase migration up` —
-- it is a forward-DROP script to run manually (via the same apply_migration
-- workflow, or the SQL editor) only if migration 040 needs to be reversed.
--
-- Scope: drops ONLY the two tables 040 created. Dropping a table
-- automatically drops everything owned by it (its policies, indexes,
-- constraints, comments) — no separate DROP POLICY / DROP INDEX needed.
--
-- Explicitly does NOT touch, and CANNOT touch, because it names nothing
-- else:
--   - public.profiles (any column, any policy)
--   - the on_auth_user_created trigger or handle_new_user() function
--   - auth.users (schema, rows, or config)
--   - public.listings (schema or rows)
--   - any other existing trigger, function, or policy
--   - any mobile-app data or behavior
--
-- Both tables were empty in production at the time 040 was applied except
-- for rows created during this session's own QA (which are removed before
-- this rollback would ever run) — dropping them is zero-data-loss to any
-- other object. Safe to re-run (IF EXISTS).
-- =============================================================================

BEGIN;

DROP TABLE IF EXISTS public.saved_listings;
DROP TABLE IF EXISTS public.notifications;

COMMIT;
