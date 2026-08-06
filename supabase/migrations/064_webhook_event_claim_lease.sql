-- 064 — replace the Stripe webhook dedup gate with a claim/complete/fail lease.
--
-- THE BUG
--
-- stripe-webhook inserts a row into stripe_webhook_events BEFORE doing any
-- work, and the gate only ever asks "does this row exist":
--
--     .insert({ event_id: event.id, event_type: event.type })
--     if (dedupErr.code === '23505') return 200 { duplicate: true }
--
-- The row is never deleted, never rolled back, and `processed` is never read.
-- So:
--
--   1. delivery #1 inserts the row, claims the payment row succeeded, then
--      throws somewhere before finishing (Supabase 5xx, a network blip on an
--      .rpc, .single() on a missing listing)
--   2. the catch returns 500, so Stripe retries — correctly
--   3. delivery #2 hits 23505 at the gate and returns 200, doing nothing
--
-- Net result: payments.status = 'succeeded' — the buyer is charged and marked
-- paid — with no transfer row, no mark_listing_sold, no notifications, and the
-- listing still 'reserved'. Permanently. The only trace is processed = false,
-- and nothing reads it. stripe_webhook_events_unprocessed_idx exists for
-- exactly these rows and has no consumer.
--
-- The gate also fails OPEN on any non-23505 insert error: it logs and
-- continues without a dedup row, so two concurrent deliveries during a
-- database hiccup both run every side effect.
--
-- THE MODEL
--
-- claimed_at    lease holder stamp; NULL means nobody is working on it
-- processed_at  terminal success; set once, never cleared
-- failed_at     last failure; advisory, cleared on the next claim
-- attempt_count incremented on every claim, so retries are visible
-- last_error    text of the last failure
--
-- claim returns one of three answers and the caller maps them to HTTP:
--
--   'claimed'            -> do the work
--   'already_processed'  -> 200, genuinely nothing to do
--   'in_flight'          -> 409, another delivery holds a live lease; Stripe
--                           retries later rather than us double-processing
--
-- A failure releases the lease immediately (claimed_at = NULL) so the very
-- next Stripe retry re-claims and reprocesses. An abandoned lease — the
-- isolate was torn down mid-event, so neither complete nor fail ever ran —
-- is recovered by the lease timeout in the claim predicate. 300s comfortably
-- exceeds the observed worst-case handler time (~5.6s).
--
-- The claim is a single atomic statement, so two concurrent deliveries of a
-- brand-new event cannot both win: one takes the INSERT, the other blocks on
-- the primary key, falls through to DO UPDATE, fails the WHERE because the
-- winner's claimed_at is inside the lease, and gets 'in_flight'.
--
-- Idempotency of the side effects themselves is unchanged and still rests on
-- the existing constraints (idx_payments_one_success_per_listing, the two
-- UNIQUE indexes on transfers, the .neq() status guards, and the RPC-internal
-- FOR UPDATE re-checks). This migration stops a failed event being silently
-- dropped; it does not loosen anything.

ALTER TABLE public.stripe_webhook_events
  ADD COLUMN IF NOT EXISTS claimed_at    timestamptz,
  ADD COLUMN IF NOT EXISTS failed_at     timestamptz,
  ADD COLUMN IF NOT EXISTS attempt_count integer NOT NULL DEFAULT 0;

-- The 31 existing rows predate processed_at being mandatory. Backfill so the
-- claim function's "processed_at IS NOT NULL" test classifies them correctly
-- as already_processed rather than re-running months-old events.
UPDATE public.stripe_webhook_events
   SET processed_at = coalesce(processed_at, received_at)
 WHERE processed AND processed_at IS NULL;

-- Reconciliation surface: events that were accepted from Stripe but never
-- reached a terminal success. Replaces the unused partial index as the way to
-- find them.
CREATE INDEX IF NOT EXISTS stripe_webhook_events_incomplete_idx
  ON public.stripe_webhook_events (received_at DESC)
  WHERE processed_at IS NULL;


CREATE OR REPLACE FUNCTION public.claim_stripe_webhook_event(
  p_event_id      text,
  p_event_type    text,
  p_lease_seconds integer DEFAULT 300
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_claimed int; v_processed timestamptz;
BEGIN
  IF p_event_id IS NULL OR p_event_id = '' THEN
    RAISE EXCEPTION 'event_id is required';
  END IF;

  INSERT INTO public.stripe_webhook_events (event_id, event_type, claimed_at, attempt_count)
  VALUES (p_event_id, coalesce(p_event_type, 'unknown'), now(), 1)
  ON CONFLICT (event_id) DO UPDATE
     SET claimed_at    = now(),
         attempt_count = public.stripe_webhook_events.attempt_count + 1
   WHERE public.stripe_webhook_events.processed_at IS NULL
     AND (public.stripe_webhook_events.claimed_at IS NULL
          OR public.stripe_webhook_events.claimed_at
             < now() - make_interval(secs => greatest(p_lease_seconds, 1)));

  GET DIAGNOSTICS v_claimed = ROW_COUNT;
  IF v_claimed = 1 THEN
    RETURN 'claimed';
  END IF;

  -- Lost the race, or it is already done. Distinguish, because the caller
  -- returns 200 for one and 409 for the other.
  SELECT processed_at INTO v_processed
    FROM public.stripe_webhook_events WHERE event_id = p_event_id;
  IF v_processed IS NOT NULL THEN
    RETURN 'already_processed';
  END IF;
  RETURN 'in_flight';
END; $function$;

CREATE OR REPLACE FUNCTION public.complete_stripe_webhook_event(p_event_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v int;
BEGIN
  UPDATE public.stripe_webhook_events
     SET processed_at = coalesce(processed_at, now()),
         processed    = true,          -- kept in sync for the legacy column
         claimed_at   = NULL,
         failed_at    = NULL,
         last_error   = NULL
   WHERE event_id = p_event_id;
  GET DIAGNOSTICS v = ROW_COUNT;
  RETURN v = 1;
END; $function$;

CREATE OR REPLACE FUNCTION public.fail_stripe_webhook_event(p_event_id text, p_error text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v int;
BEGIN
  -- claimed_at is cleared so the next Stripe delivery re-claims immediately
  -- instead of waiting out the lease. processed_at is deliberately untouched:
  -- an event that already succeeded can never be dragged back to failed.
  UPDATE public.stripe_webhook_events
     SET failed_at  = now(),
         claimed_at = NULL,
         last_error = left(coalesce(p_error, 'unknown'), 2000)
   WHERE event_id = p_event_id
     AND processed_at IS NULL;
  GET DIAGNOSTICS v = ROW_COUNT;
  RETURN v = 1;
END; $function$;

-- Reconciliation: Stripe accepted the event, we never finished it. Feeds an
-- ops sweep for the "succeeded at Stripe, incomplete internally" case.
CREATE OR REPLACE FUNCTION public.get_incomplete_webhook_events(
  p_lease_seconds integer DEFAULT 300,
  p_limit         integer DEFAULT 100
) RETURNS TABLE (
  event_id      text,
  event_type    text,
  received_at   timestamptz,
  attempt_count integer,
  failed_at     timestamptz,
  last_error    text,
  lease_state   text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT e.event_id, e.event_type, e.received_at, e.attempt_count,
         e.failed_at, e.last_error,
         CASE
           WHEN e.claimed_at IS NULL THEN 'released'
           WHEN e.claimed_at < now() - make_interval(secs => greatest(p_lease_seconds, 1))
             THEN 'abandoned'
           ELSE 'in_flight'
         END AS lease_state
    FROM public.stripe_webhook_events e
   WHERE e.processed_at IS NULL
   ORDER BY e.received_at DESC
   LIMIT greatest(p_limit, 1);
$function$;

REVOKE ALL ON FUNCTION public.claim_stripe_webhook_event(text, text, integer)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_stripe_webhook_event(text)                FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fail_stripe_webhook_event(text, text)              FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_incomplete_webhook_events(integer, integer)    FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.claim_stripe_webhook_event(text, text, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_stripe_webhook_event(text)             TO service_role;
GRANT EXECUTE ON FUNCTION public.fail_stripe_webhook_event(text, text)           TO service_role;
GRANT EXECUTE ON FUNCTION public.get_incomplete_webhook_events(integer, integer) TO service_role;
