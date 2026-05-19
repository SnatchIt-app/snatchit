-- =============================================================================
-- Migration 021: Rate-limit fail-closed + RLS on rate_limits
-- =============================================================================
-- Production deployments already ran migration 005 with the original
-- fail-OPEN behavior. This migration replaces the function with a
-- fail-CLOSED implementation and enables RLS on the rate_limits table.
--
-- Why fail-closed:
--   The original behavior returned TRUE on any DB error so a transient
--   hiccup wouldn't block a real payment. This is exploitable: an attacker
--   able to induce errors (lock contention, slow query) silently bypasses
--   abuse protection on create-payment-intent, create-connect-account,
--   confirm-and-release, confirm-payment, and delete-account.
--
-- Idempotent: CREATE OR REPLACE FUNCTION + ALTER TABLE ... ENABLE RLS are
-- both safe to re-run.
-- =============================================================================

-- Defense-in-depth: deny all non-service-role access to the table.
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

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
  v_now          timestamptz := now();
  v_counter      int;
  v_window_start timestamptz;
BEGIN
  IF random() < 0.05 THEN
    DELETE FROM public.rate_limits
    WHERE  window_start < v_now - (p_window_seconds * 2 * interval '1 second');
  END IF;

  INSERT INTO public.rate_limits (user_id, action, window_start, counter)
  VALUES (p_user_id, p_action, v_now, 1)
  ON CONFLICT (user_id, action) DO UPDATE
    SET window_start = CASE
          WHEN public.rate_limits.window_start < v_now - (p_window_seconds * interval '1 second')
          THEN v_now
          ELSE public.rate_limits.window_start
        END,
        counter = CASE
          WHEN public.rate_limits.window_start < v_now - (p_window_seconds * interval '1 second')
          THEN 1
          ELSE public.rate_limits.counter + 1
        END
  RETURNING counter, window_start INTO v_counter, v_window_start;

  RETURN v_counter <= p_max;

EXCEPTION WHEN OTHERS THEN
  -- Fail-CLOSED: callers must treat FALSE as "deny" and return 429 / 503.
  RAISE WARNING 'check_rate_limit error (failing closed): %', SQLERRM;
  RETURN false;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, int, int) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.check_rate_limit(uuid, text, int, int) TO service_role;
