-- 061_ensure_transfer_exists_requires_verified_payment.sql  APPLIED 2026-08-05, verified.
--
-- CRITICAL free-purchase exploit. ensure_transfer_exists could mint a transfer
-- from an UNPAID payment, yielding free tickets funded by the platform.
--
-- It selected the caller's payment with status IN ('pending','succeeded') then ran
--   UPDATE public.payments SET status='succeeded', paid_at=coalesce(paid_at,now())
--    WHERE id = v_payment_id AND status='pending';
-- with NO Stripe verification, and EXECUTE held by `authenticated`. Any signed-in
-- buyer could reserve_buy_now -> create-payment-intent (inserts a `pending`
-- payments row) -> never confirm the card -> POST /rest/v1/rpc/ensure_transfer_exists.
-- Payment flipped to succeeded, a transfer was created, the seller shipped a real
-- ticket, and the payout pipeline released funds never collected. Reachable
-- straight from the REST API with the publishable key, no web app needed.
--
-- SAFE TO REMOVE, verified before changing anything: `succeeded` is already
-- written by two Stripe-verified writers and only after a real check --
--   confirm-payment/index.ts:178 fetches /payment_intents/{id}; :183 requires
--     stripeData.status === 'succeeded'; :219 then writes succeeded
--   stripe-webhook/index.ts:202 writes succeeded on the signature-verified
--     payment_intent.succeeded event
-- Every legitimate checkout therefore already holds a verified succeeded row
-- before this function runs. The promotion was a redundant unverified fallback,
-- not a compatibility requirement -- so it was removed outright rather than
-- preserved.
--
-- Transfer creation now REQUIRES status='succeeded', still scoped to the
-- authenticated caller and the given listing (both pre-existing, retained).
-- Idempotency unchanged: an existing transfer is returned, and the INSERT keeps
-- ON CONFLICT (payment_id) DO NOTHING, so retries and replays stay safe.
--
-- ADVERSARIALLY VERIFIED after applying:
--   promotion removed from function body ......... CONFIRMED GONE
--   ATTACK pending payment -> transfer ........... REJECTED (run against a REAL
--       pending payment with no transfer -- the exact exploit precondition)
--   ATTACK caller with no payment for listing .... REJECTED
--   LEGIT succeeded payment -> existing transfer .. OK (idempotent)
--
-- Rollback: supabase/rollbacks/061_..._rollback.sql -- reintroduces the exploit;
-- do not run.

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260806002500. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 061: CRITICAL. ensure_transfer_exists could mint a transfer from an UNPAID
-- payment, yielding free tickets funded by the platform.
--
-- The function selected the caller's payment with status IN ('pending','succeeded')
-- and then did:
--     UPDATE public.payments SET status='succeeded', paid_at=coalesce(paid_at,now())
--      WHERE id = v_payment_id AND status='pending';
-- with NO Stripe verification. EXECUTE is held by `authenticated`, so any signed-in
-- buyer could: reserve_buy_now -> create-payment-intent (inserts a `pending`
-- payments row) -> never confirm the card -> POST /rest/v1/rpc/ensure_transfer_exists.
-- The payment flipped to succeeded, a transfer was created, the seller shipped a
-- real ticket, and the payout pipeline released funds never collected. Reachable
-- straight from the REST API with the publishable key.
--
-- SAFE TO REMOVE: `succeeded` is already written by two Stripe-verified writers,
-- and only after a real check against Stripe --
--   confirm-payment/index.ts:178 fetches /payment_intents/{id}, :183 requires
--     stripeData.status === 'succeeded', :219 then writes succeeded
--   stripe-webhook/index.ts:202 writes succeeded on the signature-verified
--     payment_intent.succeeded event
-- so every legitimate checkout already has a verified `succeeded` row before this
-- function runs. The promotion was a redundant unverified fallback, not a
-- compatibility requirement.
--
-- Now: transfer creation REQUIRES an already-verified succeeded payment, scoped to
-- the authenticated caller and the specified listing (both were already enforced by
-- the WHERE clause and are retained). Idempotency is unchanged -- an existing
-- transfer for the payment is returned as before, and the INSERT keeps
-- ON CONFLICT (payment_id) DO NOTHING, so retries and replays remain safe.

CREATE OR REPLACE FUNCTION public.ensure_transfer_exists(p_listing_id uuid, p_user_id uuid DEFAULT NULL::uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller_id uuid; v_payment_id uuid; v_seller_id uuid; v_buyer_id uuid;
  v_transfer_method text; v_existing_transfer uuid; v_new_transfer uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  -- Only a payment that a Stripe-verified writer has already marked succeeded,
  -- belonging to THIS caller and THIS listing, can produce a transfer.
  SELECT id, seller_id, buyer_id INTO v_payment_id, v_seller_id, v_buyer_id
    FROM public.payments
   WHERE listing_id = p_listing_id
     AND buyer_id   = v_caller_id
     AND status     = 'succeeded'
   ORDER BY created_at DESC LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No verified payment found for this listing. Payment must be confirmed before a transfer can be created.';
  END IF;

  SELECT id INTO v_existing_transfer FROM public.transfers WHERE payment_id = v_payment_id;
  IF FOUND THEN RETURN v_existing_transfer; END IF;

  SELECT transfer_method INTO v_transfer_method FROM public.listings WHERE id = p_listing_id;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);

  INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
  VALUES (p_listing_id, v_payment_id, v_seller_id, v_buyer_id,
          coalesce(v_transfer_method,'mobile_transfer'), 'pending', now() + interval '24 hours')
  ON CONFLICT (payment_id) DO NOTHING
  RETURNING id INTO v_new_transfer;

  IF v_new_transfer IS NULL THEN
    SELECT id INTO v_new_transfer FROM public.transfers WHERE payment_id = v_payment_id;
  END IF;

  RETURN v_new_transfer;
END; $function$;

REVOKE EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid,uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid,uuid) TO authenticated, service_role;
