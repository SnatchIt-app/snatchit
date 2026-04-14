ALTER TABLE public.transfers
  ADD COLUMN IF NOT EXISTS auto_release_at timestamptz;


ALTER TABLE public.transfers
  DROP CONSTRAINT IF EXISTS transfers_status_check;

ALTER TABLE public.transfers
  ADD CONSTRAINT transfers_status_check
  CHECK (status IN (
    'pending',
    'seller_sent',
    'buyer_confirmed',
    'disputed',
    'expired',
    'auto_released'
  ));


CREATE INDEX IF NOT EXISTS idx_transfers_seller_sent_auto_release
  ON public.transfers (auto_release_at)
  WHERE status = 'seller_sent';


CREATE OR REPLACE FUNCTION public.mark_transfer_sent(
  p_transfer_id uuid,
  p_user_id     uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_seller_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT status, seller_id
    INTO v_status, v_seller_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_seller_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the seller can mark a transfer as sent.';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status          = 'seller_sent',
         seller_sent_at  = now(),
         auto_release_at = now() + interval '72 hours'
   WHERE id = p_transfer_id;
END;
$$;


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
     SET status             = 'auto_released'
    FROM releasable r
   WHERE t.id = r.id
  RETURNING t.id        AS transfer_id,
            t.payment_id,
            t.listing_id,
            t.buyer_id,
            t.seller_id;
END;
$$;
