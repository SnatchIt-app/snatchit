-- 045 — payments.stripe_livemode column (DDL only).
--
-- Trimmed to exactly what production recorded for this migration
-- (supabase_migrations version 20260804185549): the ALTER TABLE and the
-- COMMENT.
--
-- The backfill that used to follow is NOT part of the applied migration and
-- has been moved to
-- supabase/one-off/2026-08-04-backfill-payments-stripe-livemode.sql.
--
-- It classifies every pre-existing payment by a hardcoded cutoff date, which
-- is a one-time judgement about historical rows, not a schema change. Re-running
-- it later would reclassify any row that happened to be NULL at that moment.

ALTER TABLE payments ADD COLUMN IF NOT EXISTS stripe_livemode boolean;
COMMENT ON COLUMN payments.stripe_livemode IS
  'Stripe environment of stripe_payment_intent_id. true=live, false=test-era (inert for financial automation), null=unclassified. Set from Stripe''s livemode at creation since 2026-08-04.';
