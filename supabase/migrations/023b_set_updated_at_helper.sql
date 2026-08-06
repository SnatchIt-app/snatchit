-- 023b — the missing set_updated_at() trigger helper.
--
-- This function exists in production but no migration in this directory ever
-- created it; it was applied out of band. Two migrations attach triggers to
-- it — 024_disputes.sql and 20260731224653_venue_partnership_inquiries_website_form.sql
-- — so a from-scratch replay of the repo against an empty database fails on
-- the first of those with "function public.set_updated_at() does not exist".
--
-- The gap is easy to miss because the ambassador_applications migration two
-- days before the venue one defines its OWN
-- set_ambassador_application_updated_at() rather than reusing this, which is
-- what made the omission visible.
--
-- Numbered 023b so it sorts after 023_user_reports_and_blocks and before
-- 024_disputes, the first migration that needs it.
--
-- NOT applied to production: the function is already there, and this body is
-- reproduced verbatim from pg_get_functiondef so the repo matches live exactly.
-- CREATE OR REPLACE makes it a safe no-op if it is ever replayed.
--
-- Reproduced as-is, deliberately including the missing `SET search_path`.
-- Pinning it here would make the repo diverge from production, which defeats
-- the point of this file. Worth pinning later in its own migration, applied to
-- both — it is a trigger function owned by postgres, so an unpinned
-- search_path is a real if narrow hardening gap.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
