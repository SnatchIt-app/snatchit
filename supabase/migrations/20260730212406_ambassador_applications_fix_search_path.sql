-- 20260730212406_ambassador_applications_fix_search_path.sql
-- Pins search_path on public.set_ambassador_application_updated_at() (Supabase
-- linter rule function_search_path_mutable) so the trigger cannot be hijacked.
-- Recovered from supabase_migrations.schema_migrations version 20260730212406; applied 20260730212406. Not re-applied.

-- Lock down the trigger function's search_path per Supabase's linter guidance
-- (function_search_path_mutable) so it can't be hijacked by a malicious search_path.
create or replace function public.set_ambassador_application_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
