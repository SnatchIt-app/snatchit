-- 016_fix_auto_release_payout.sql
-- FIX: enforce_auto_release() must NOT set payout_released_at.
-- Only the edge function should set it AFTER Stripe Transfer succeeds.
-- This prevents false-positive "paid" state when Stripe Transfer fails.

CREATE OR REPLACE FUNCTION public.enforce_auto_release()
RETURNS TABLE (
  transfer_id  uuid,
  payment_id   uuid,
  listing_id   uuid,
  buyer_id     uuid,
  seller_id    uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH releasable AS (
    SELECT t.id,
           t.payment_id,
           t.listing_id,
           t.buyer_id,
           t.seller_id
      FROM public.transfers t
     WHERE t.status = 'seller_sent'
       AND t.auto_release_at IS NOT NULL
       AND t.auto_release_at < now()
       AND t.payout_released_at IS NULL
       FOR UPDATE SKIP LOCKED
  )
  UPDATE public.transfers t
     SET status = 'auto_released'
    FROM releasable r
   WHERE t.id = r.id
  RETURNING t.id        AS transfer_id,
            t.payment_id,
            t.listing_id,
            t.buyer_id,
            t.seller_id;
END;
$$;
