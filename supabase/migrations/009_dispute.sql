ALTER TABLE public.transfers
  ADD COLUMN IF NOT EXISTS disputed_at timestamptz;


CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(
  p_transfer_id uuid,
  p_user_id     uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  SELECT status, buyer_id
    INTO v_status, v_buyer_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer can dispute a transfer.';
  END IF;

  IF v_status = 'disputed' THEN
    RETURN;
  END IF;

  IF v_status <> 'seller_sent' THEN
    RAISE EXCEPTION 'Cannot dispute transfer in current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status      = 'disputed',
         disputed_at = now()
   WHERE id = p_transfer_id;
END;
$$;
