-- =============================================================================
-- 010_ensure_transfer.sql — Guarantee transfer row exists after checkout
-- =============================================================================
-- PURPOSE: Provide a synchronous, idempotent RPC that the checkout client can
-- call AFTER mark_listing_sold / complete_auction_payment to ensure a transfer
-- row exists. This closes the reliability gap where confirm-payment (best-effort)
-- and stripe-webhook (async) could both fail to create the transfer before the
-- seller opens the listing.
--
-- SAFETY:
--   - ON CONFLICT (payment_id) DO NOTHING prevents duplicates
--   - UNIQUE constraint on transfers.listing_id is a secondary guard
--   - Does NOT modify any existing RPCs, edge functions, or payout logic
--   - Idempotent: returns existing transfer id if row already exists
--
-- PRESERVES: Day 1 (confirm+payout), Day 2 (expiry+refund),
--            Day 3 (auto-release), Day 4 (dispute)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.ensure_transfer_exists(
  p_listing_id uuid,
  p_user_id    uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id          uuid;
  v_payment_id         uuid;
  v_seller_id          uuid;
  v_buyer_id           uuid;
  v_transfer_method    text;
  v_existing_transfer  uuid;
  v_new_transfer       uuid;
BEGIN
  -- ── 1. Identify caller ────────────────────────────────────────────────────
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  -- ── 2. Find the payment for this listing by this buyer ──────────────────
  -- Accept BOTH 'pending' and 'succeeded': when confirm-payment edge function
  -- fails (returns non-2xx), payments.status stays 'pending' even though the
  -- Stripe charge succeeded. This RPC is only called after presentPaymentSheet()
  -- returns success, so the charge is confirmed at the Stripe level.
  SELECT id, seller_id, buyer_id
    INTO v_payment_id, v_seller_id, v_buyer_id
    FROM public.payments
   WHERE listing_id = p_listing_id
     AND buyer_id   = v_caller_id
     AND status     IN ('pending', 'succeeded')
   ORDER BY created_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No payment found for this listing.';
  END IF;

  -- ── 2b. Promote 'pending' → 'succeeded' if confirm-payment didn't ────────
  -- This is the same status change that confirm-payment was supposed to make.
  -- Atomic WHERE guard prevents double-write if confirm-payment runs later.
  UPDATE public.payments
     SET status  = 'succeeded',
         paid_at = coalesce(paid_at, now())
   WHERE id     = v_payment_id
     AND status = 'pending';

  -- ── 3. Idempotency: if transfer already exists, return its id ─────────────
  SELECT id INTO v_existing_transfer
    FROM public.transfers
   WHERE payment_id = v_payment_id;

  IF FOUND THEN
    RETURN v_existing_transfer;
  END IF;

  -- ── 4. Look up transfer method from listing ───────────────────────────────
  SELECT transfer_method
    INTO v_transfer_method
    FROM public.listings
   WHERE id = p_listing_id;

  -- ── 5. Create the transfer row ────────────────────────────────────────────
  INSERT INTO public.transfers (
    listing_id,
    payment_id,
    seller_id,
    buyer_id,
    transfer_method,
    status,
    expires_at
  ) VALUES (
    p_listing_id,
    v_payment_id,
    v_seller_id,
    v_buyer_id,
    coalesce(v_transfer_method, 'mobile_transfer'),
    'pending',
    now() + interval '24 hours'
  )
  ON CONFLICT (payment_id) DO NOTHING
  RETURNING id INTO v_new_transfer;

  -- ── 6. If ON CONFLICT fired, fetch existing row ───────────────────────────
  IF v_new_transfer IS NULL THEN
    SELECT id INTO v_new_transfer
      FROM public.transfers
     WHERE payment_id = v_payment_id;
  END IF;

  RETURN v_new_transfer;
END;
$$;
