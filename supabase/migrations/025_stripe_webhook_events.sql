-- =============================================================================
-- Migration 025: Stripe webhook event deduplication (P1-02)
-- =============================================================================
-- Stripe retries deliveries on any non-2xx response, and may legitimately
-- send the same event id more than once. The handler now does an
-- INSERT-with-ON-CONFLICT against this table as its FIRST action; if the
-- event_id already exists, the handler short-circuits with HTTP 200 and
-- skips all side effects.
--
-- We also track processed_at and last_error so ops can replay or audit
-- via the DAY8 admin SQL pack.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
  event_id      text        PRIMARY KEY,
  event_type    text        NOT NULL,
  received_at   timestamptz NOT NULL DEFAULT now(),
  processed     boolean     NOT NULL DEFAULT false,
  processed_at  timestamptz,
  last_error    text,
  retry_count   int         NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS stripe_webhook_events_type_idx
  ON public.stripe_webhook_events (event_type, received_at DESC);

CREATE INDEX IF NOT EXISTS stripe_webhook_events_unprocessed_idx
  ON public.stripe_webhook_events (received_at DESC)
  WHERE processed = false;

ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;
-- No client policies — service-role only.

REVOKE ALL ON public.stripe_webhook_events FROM anon, authenticated;

COMMIT;
