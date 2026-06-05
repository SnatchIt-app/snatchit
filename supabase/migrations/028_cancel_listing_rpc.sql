-- =============================================================================
-- Migration 028: re-assert public.cancel_listing(uuid, uuid) RPC
-- =============================================================================
-- The function is defined in supabase/schema.sql (block 10b), which is the
-- canonical bootstrap script. Some environments (CI, fresh branches, local
-- shadow DBs) only run files in supabase/migrations/, so this migration
-- re-asserts the function to guarantee it is present everywhere.
--
-- Behaviour (unchanged):
--   • SECURITY DEFINER
--   • caller := coalesce(auth.uid(), p_user_id)
--   • raise if caller != seller
--   • raise if listing already sold
--   • no-op (idempotent return) if already cancelled
--   • sets auction_status='cancelled', status='active', clears reservation,
--     bumps ended_at
--   • bypasses guard_listing_state_columns via app.bypass_listing_guard
--
-- Idempotent — re-runs cleanly.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.cancel_listing(
  p_listing_id uuid,
  p_user_id    uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id      uuid;
  v_seller_id      uuid;
  v_status         text;
  v_auction_status text;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT seller_id, status, auction_status
    INTO v_seller_id, v_status, v_auction_status
    FROM public.listings
   WHERE id = p_listing_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found.';
  END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'You can only cancel your own listings.';
  END IF;
  IF v_status = 'sold' THEN
    RAISE EXCEPTION 'This listing has already been sold and cannot be cancelled.';
  END IF;
  IF v_auction_status = 'cancelled' THEN
    RETURN; -- idempotent
  END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);

  UPDATE public.listings
     SET auction_status = 'cancelled',
         status         = 'active',
         reserved_by    = NULL,
         reserved_until = NULL,
         ended_at       = now()
   WHERE id = p_listing_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_listing(uuid, uuid) TO authenticated;

COMMIT;
