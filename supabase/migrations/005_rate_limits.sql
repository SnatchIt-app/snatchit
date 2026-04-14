-- =============================================================================
-- Migration 005: DB-backed rate limiting
-- =============================================================================
-- Creates a lightweight rate_limits table and a check_rate_limit() RPC.
--
-- Design:
--   • One row per (user_id, action).
--   • counter resets when now() > window_start + window_seconds.
--   • Single UPSERT is atomic — no separate SELECT + UPDATE race condition.
--   • Probabilistic cleanup (1-in-20) removes stale rows inline so no cron
--     job is needed during private beta.
--   • SECURITY DEFINER + search_path = '' prevents privilege escalation.
--   • No RLS needed — only service-role callers (edge functions) use this.
-- =============================================================================

-- ── Table ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.rate_limits (
  user_id        uuid        NOT NULL,
  action         text        NOT NULL,
  window_start   timestamptz NOT NULL DEFAULT now(),
  counter        int         NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, action)
);

-- Index is already covered by the PK; no additional index needed.

-- Deny direct client access — only service-role (edge functions) may touch this.
REVOKE ALL ON public.rate_limits FROM anon, authenticated;

-- ── RPC ──────────────────────────────────────────────────────────────────────

-- check_rate_limit
--   p_user_id        uuid    — authenticated caller
--   p_action         text    — e.g. 'create-payment-intent'
--   p_max            int     — maximum requests allowed in the window
--   p_window_seconds int     — rolling window length in seconds
--
-- Returns TRUE  → request is within limits, counter has been incremented.
-- Returns FALSE → request exceeds the limit, caller should return HTTP 429.
--
-- Fail-open: the EXCEPTION block catches all DB errors and returns TRUE so
-- that a transient DB hiccup never blocks a real payment.

CREATE OR REPLACE FUNCTION public.check_rate_limit(
  p_user_id        uuid,
  p_action         text,
  p_max            int,
  p_window_seconds int
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now         timestamptz := now();
  v_counter     int;
  v_window_start timestamptz;
BEGIN
  -- Probabilistic cleanup: ~5% of calls purge rows whose window has been
  -- expired for at least twice the window length. Keeps the table small
  -- without a scheduled job.
  IF random() < 0.05 THEN
    DELETE FROM public.rate_limits
    WHERE  window_start < v_now - (p_window_seconds * 2 * interval '1 second');
  END IF;

  -- Upsert:
  --   • New row:      counter = 1, window_start = now()
  --   • Existing row within window: increment counter
  --   • Existing row with expired window: reset counter to 1, reset window_start
  INSERT INTO public.rate_limits (user_id, action, window_start, counter)
  VALUES (p_user_id, p_action, v_now, 1)
  ON CONFLICT (user_id, action) DO UPDATE
    SET window_start = CASE
          WHEN public.rate_limits.window_start < v_now - (p_window_seconds * interval '1 second')
          THEN v_now          -- window expired → start a new window
          ELSE public.rate_limits.window_start  -- still in same window
        END,
        counter = CASE
          WHEN public.rate_limits.window_start < v_now - (p_window_seconds * interval '1 second')
          THEN 1              -- new window → reset to 1
          ELSE public.rate_limits.counter + 1  -- same window → increment
        END
  RETURNING counter, window_start INTO v_counter, v_window_start;

  -- Allow if we're within the limit
  RETURN v_counter <= p_max;

EXCEPTION WHEN OTHERS THEN
  -- Fail-open: never block a legitimate request due to a rate-limit DB error.
  RAISE WARNING 'check_rate_limit error (failing open): %', SQLERRM;
  RETURN true;
END;
$$;

-- Grant execute only to service_role (used by edge functions via service key)
REVOKE EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, int, int) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, int, int) TO service_role;
