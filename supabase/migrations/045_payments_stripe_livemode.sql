-- 045_payments_stripe_livemode.sql  (applied 2026-08-04)
-- Explicit Stripe mode boundary on payments.
--
-- The production DB predates the 2026-08-04 00:57Z live-key cutover and
-- holds test-mode Stripe object ids. Automation must never address a
-- test-mode object with the live key (Sentry REACT-NATIVE-8: the Phase 1b
-- refund self-heal swept test-era rows and threw "No such payment_intent …
-- exists in test mode" every cron run).
--
-- This column is the explicit boundary:
--   • new rows: set from Stripe's own `livemode` field at PaymentIntent
--     creation (create-payment-intent);
--   • historical rows: backfilled from proven key-usage history — the live
--     secret key was first set 2026-08-04T00:57Z and its Stripe "last used"
--     was empty before that, so no live object can predate the cutover;
--     the payments row gap 2026-07-29 19:51 → 2026-08-04 01:00 is empty,
--     making the classification unambiguous (49 test / 4 live at backfill).
--
-- Financial automation (refund self-heal, payout sweeps) selects
-- stripe_livemode = true only. Test-era rows stay preserved for audit but
-- are inert.

ALTER TABLE payments ADD COLUMN IF NOT EXISTS stripe_livemode boolean;
COMMENT ON COLUMN payments.stripe_livemode IS
  'Stripe environment of stripe_payment_intent_id. true=live, false=test-era (inert for financial automation), null=unclassified. Set from Stripe''s livemode at creation since 2026-08-04.';

UPDATE payments
SET stripe_livemode = (created_at >= '2026-08-04 00:00:00+00')
WHERE stripe_livemode IS NULL;
