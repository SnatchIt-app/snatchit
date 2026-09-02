-- admin_relist_listing — restore a cancelled ADMIN-owned listing to active.
--
-- Applied to production 2026-09-02 as version 20260902003623 (this file is the
-- required in-git source for that ledger row).
--
-- Exists because no supported path did: the admin dashboard is read-only for
-- listings, and direct state-column UPDATEs are (correctly) refused by
-- guard_listing_state_columns. Historically the house listings were extended
-- with ad-hoc bypass-guard SQL; this makes that a named, guarded operation
-- instead. First use: relisting the III Points Saturday GA house listing
-- (c8d04339) that a bulk cleanup cancelled on 2026-07-28.
--
-- Deliberately NARROW. It can only resurrect inventory that:
--   * belongs to a seller who is in admin_users — a real user's cancelled
--     listing is their decision, and this function must never undo it
--   * is plainly cancelled-and-unwound: status='active' (cancel_listing's
--     resting state), no winner, no reservation, and ZERO payments, transfers
--     or bids attached — so relisting cannot duplicate sold inventory,
--     resurrect a voided auction, or touch any money path
-- and the new end time must be in the future.
--
-- Same trust pattern as every other admin writer: SECURITY DEFINER, pinned
-- search_path, transaction-local bypass GUC, EXECUTE for service_role only,
-- acting admin recorded in the return value.

CREATE OR REPLACE FUNCTION public.admin_relist_listing(
  p_listing_id uuid,
  p_new_ends_at timestamptz,
  p_admin_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v listings%ROWTYPE;
BEGIN
  IF p_admin_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = p_admin_id) THEN
    RAISE EXCEPTION 'Relisting requires a known admin actor.';
  END IF;
  IF p_new_ends_at IS NULL OR p_new_ends_at <= now() THEN
    RAISE EXCEPTION 'New end time must be in the future.';
  END IF;

  SELECT * INTO v FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Listing not found.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = v.seller_id) THEN
    RAISE EXCEPTION 'Only admin-owned inventory can be relisted; a real seller''s cancellation stands.';
  END IF;
  IF v.auction_status <> 'cancelled' OR v.status <> 'active' THEN
    RAISE EXCEPTION 'Listing is not in the cancelled resting state (status=%, auction_status=%).', v.status, v.auction_status;
  END IF;
  IF v.winner_user_id IS NOT NULL OR v.reserved_by IS NOT NULL THEN
    RAISE EXCEPTION 'Listing carries a winner or reservation and cannot be relisted.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.payments  p WHERE p.listing_id = p_listing_id)
  OR EXISTS (SELECT 1 FROM public.transfers t WHERE t.listing_id = p_listing_id)
  OR EXISTS (SELECT 1 FROM public.bids      b WHERE b.listing_id = p_listing_id) THEN
    RAISE EXCEPTION 'Listing has payment/transfer/bid history and cannot be relisted.';
  END IF;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET auction_status = 'active',
         ends_at  = p_new_ends_at,
         ended_at = NULL
   WHERE id = p_listing_id;

  RETURN jsonb_build_object(
    'listing_id', p_listing_id,
    'event_name', v.event_name,
    'relisted_by', p_admin_id,
    'new_ends_at', p_new_ends_at,
    'previous_ends_at', v.ends_at
  );
END; $function$;

REVOKE ALL ON FUNCTION public.admin_relist_listing(uuid, timestamptz, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_relist_listing(uuid, timestamptz, uuid) TO service_role;
