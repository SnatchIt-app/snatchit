-- Rollback for migration 066. Restores the prior (unset) search_path on the five
-- functions. This re-introduces linter warning 0011 but is behaviorally inert.
alter function public.disputes_set_updated_at()        reset search_path;
alter function public.guard_listing_identity_columns() reset search_path;
alter function public.guard_listing_state_columns()    reset search_path;
alter function public.handle_new_user()                reset search_path;
alter function public.set_updated_at()                 reset search_path;
