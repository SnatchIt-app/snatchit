-- Rollback 064 — drop the webhook claim/complete/fail lease.
--
-- ORDER MATTERS. stripe-webhook v39+ calls claim_stripe_webhook_event and will
-- fail CLOSED (500 on every event) if these functions disappear. Roll the Edge
-- Function back to v38 FIRST, then run this. Doing it the other way round
-- stops all Stripe webhook processing.
--
-- The added columns are deliberately NOT dropped: claimed_at / failed_at /
-- attempt_count are additive, cost nothing when unused, and v38 ignores them.
-- Dropping them would destroy the retry history that makes an incident
-- reconstructable. Only the functions and the index go.

DROP FUNCTION IF EXISTS public.claim_stripe_webhook_event(text, text, integer);
DROP FUNCTION IF EXISTS public.complete_stripe_webhook_event(text);
DROP FUNCTION IF EXISTS public.fail_stripe_webhook_event(text, text);
DROP FUNCTION IF EXISTS public.get_incomplete_webhook_events(integer, integer);

DROP INDEX IF EXISTS public.stripe_webhook_events_incomplete_idx;

-- To also shed the columns (NOT recommended — loses retry history):
-- ALTER TABLE public.stripe_webhook_events
--   DROP COLUMN IF EXISTS claimed_at,
--   DROP COLUMN IF EXISTS failed_at,
--   DROP COLUMN IF EXISTS attempt_count;
