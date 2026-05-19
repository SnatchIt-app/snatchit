-- =============================================================================
-- Migration 026: Stripe Customer reference on profiles (P1-03 saved cards)
-- =============================================================================
-- Adds public.profiles.stripe_customer_id so PaymentSheet can surface
-- saved cards on repeat checkouts.
--
-- One Customer per Snatch It user. Created lazily by create-payment-intent
-- on the buyer's first checkout. Reused on every subsequent purchase via
-- ephemeral keys + setup_future_usage='on_session'.
--
-- Idempotent: column ADD IF NOT EXISTS + nullable + UNIQUE constraint
-- created via DO block so re-running doesn't error.
-- =============================================================================

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_customer_id text;

-- UNIQUE constraint — a Stripe customer ID should map to exactly one user.
-- Added separately so re-running the migration doesn't fail on duplicate-
-- constraint creation.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_stripe_customer_id_key'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_stripe_customer_id_key UNIQUE (stripe_customer_id);
  END IF;
END
$$;

COMMIT;
