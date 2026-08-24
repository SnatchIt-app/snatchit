-- Migration 066: pin search_path on the 5 remaining mutable-search_path functions
--
-- Finding addressed: Supabase linter 0011 (function_search_path_mutable) — the last
--   five functions still lacking an explicit search_path. A mutable search_path on a
--   table-owner trigger / SECURITY DEFINER function is a privilege-escalation vector:
--   an attacker able to create an object in a schema earlier on the resolved path could
--   shadow an unqualified reference and have it run with the definer's privileges.
--
-- Forward behavior: metadata-only ALTER FUNCTION ... SET search_path. Bodies are
--   untouched and object resolution is unchanged (all five already resolve against
--   public, which stays first). pg_temp is pinned last so temp resolution is
--   deterministic and cannot be hijacked.
-- Compatibility: none of the five is a client RPC. Three are BEFORE-UPDATE guards on
--   listings; two are updated_at triggers (set_updated_at, disputes_set_updated_at);
--   handle_new_user is the auth.users AFTER INSERT trigger. Trigger execution does not
--   consult EXECUTE grants, so this is behaviorally inert beyond closing the lint.
-- Expected locks: brief lock on each function's catalog row only; no table locks.
-- Expected runtime: milliseconds.
-- Rollback: rollbacks/066_pin_search_path_definer_functions_rollback.sql (RESET).
-- Verification (after apply):
--   select proname, proconfig from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname='public' and proname in
--      ('disputes_set_updated_at','guard_listing_identity_columns',
--       'guard_listing_state_columns','handle_new_user','set_updated_at');
--   -- every proconfig must contain: search_path=public, pg_temp

alter function public.disputes_set_updated_at()        set search_path = public, pg_temp;
alter function public.guard_listing_identity_columns() set search_path = public, pg_temp;
alter function public.guard_listing_state_columns()    set search_path = public, pg_temp;
alter function public.handle_new_user()                set search_path = public, pg_temp;
alter function public.set_updated_at()                 set search_path = public, pg_temp;
