-- Migration 017: Add stripe_onboarding_complete to profiles
-- Used to distinguish "Stripe account created" from "Stripe onboarding finished".
-- stripe_connect_id being set only means an Express account was created;
-- stripe_onboarding_complete = true means details_submitted is true on Stripe.

alter table public.profiles
  add column if not exists stripe_onboarding_complete boolean not null default false;

-- Back-fill: anyone who already has a stripe_connect_id AND whose account has
-- completed onboarding should be true, but we can't query Stripe from SQL.
-- The edge function will set this flag going forward whenever it sees
-- details_submitted = true from the Stripe API.
