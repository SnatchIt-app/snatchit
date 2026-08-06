-- ONE-OFF backfill — classify pre-2026-08-04 payments as test-era.
-- ALREADY EXECUTED against production. DO NOT RUN AGAIN.
--
-- Deliberately NOT in supabase/migrations/: the cutoff is a one-time judgement
-- about historical rows, not a schema change. Re-running it would reclassify
-- any payment whose stripe_livemode happened to be NULL at that moment.
--
-- Since 2026-08-04 the column is written from Stripe's own `livemode` at
-- PaymentIntent creation, so no new row needs this.

UPDATE payments
SET stripe_livemode = (created_at >= '2026-08-04 00:00:00+00')
WHERE stripe_livemode IS NULL;
