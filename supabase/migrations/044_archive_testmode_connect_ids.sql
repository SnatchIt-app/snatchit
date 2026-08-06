-- 044 — stripe_connect_archive table (DDL only).
--
-- Trimmed to exactly what production recorded for this migration
-- (supabase_migrations version 20260804024456): the CREATE TABLE and the RLS
-- enable, nothing else.
--
-- The two data steps that used to live here are NOT part of the applied
-- migration and have been moved to
-- supabase/one-off/2026-08-03-archive-testmode-connect-ids.sql.
--
-- They were a one-time incident remediation, and replaying them is actively
-- DESTRUCTIVE: they archive and NULL `stripe_connect_id` for every profile
-- that has one. Production currently has 7 live Connect accounts and 4
-- archived rows, so a replay against the live database would disconnect all
-- seven sellers from Stripe and block their payouts.
--
-- Keeping them in supabase/migrations/ meant `supabase db reset` or any
-- replay would run them. That is why they are out.

CREATE TABLE IF NOT EXISTS stripe_connect_archive (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id        uuid        NOT NULL REFERENCES profiles(id),
  stripe_connect_id text        NOT NULL,
  reason            text        NOT NULL,
  archived_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE stripe_connect_archive ENABLE ROW LEVEL SECURITY;
