BEGIN;
CREATE OR REPLACE FUNCTION public.claim_payout_attempt(
  p_transfer_id uuid,
  p_actor       text,
  p_lease       interval DEFAULT '10 minutes'
) RETURNS TABLE(
  attempt_id        uuid,
  attempt_no        int,
  idempotency_key   text,
  destination       text,
  amount_cents      int,
  source_charge_id  text,
  payment_intent_id text,
  needs_reconcile   boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_t     public.transfers%ROWTYPE;
  v_p     public.payments%ROWTYPE;
  v_open  public.payout_attempts%ROWTYPE;
  v_dest  text;
  v_pi    text;
  v_no    int;
  v_amt   int;
  v_lease interval := coalesce(p_lease, interval '10 minutes');
BEGIN
  IF v_lease <= interval '0' OR v_lease > interval '1 hour' THEN
    v_lease := interval '10 minutes';
  END IF;

  SELECT * INTO v_t FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSFER_NOT_FOUND';
  END IF;

  -- An open attempt always wins: it is reconciled, never duplicated. This
  -- check precedes eligibility so an attempt stuck 'unknown' on a transfer
  -- that has since been disputed is still reconciled (F07 compounding).
  SELECT * INTO v_open FROM public.payout_attempts a
   WHERE a.transfer_id = p_transfer_id AND a.state IN ('claimed','requested','unknown')
   FOR UPDATE;
  IF FOUND THEN
    IF v_open.lease_expires_at > now() THEN
      -- Another worker owns it. Handing it out could let this caller mark a
      -- POST that is in flight elsewhere as failed.
      RAISE EXCEPTION 'PAYOUT_ATTEMPT_IN_PROGRESS' USING DETAIL = v_open.id::text;
    END IF;
    UPDATE public.payout_attempts SET lease_expires_at = now() + v_lease WHERE id = v_open.id;
    SELECT p.stripe_payment_intent_id INTO STRICT v_pi FROM public.payments p WHERE p.id = v_open.payment_id;
    RETURN QUERY SELECT v_open.id, v_open.attempt_no, v_open.idempotency_key, v_open.destination,
                        v_open.amount_cents, v_open.source_charge_id, v_pi, true;
    RETURN;
  END IF;

  -- Eligibility (the 056d predicate plus the payment-side truths).
  IF v_t.payout_released_at IS NOT NULL OR v_t.stripe_transfer_id IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.payout_attempts a WHERE a.transfer_id = p_transfer_id AND a.state IN ('succeeded','reversal_required')) THEN
    RAISE EXCEPTION 'ALREADY_RELEASED';
  END IF;
  IF v_t.disputed_at IS NOT NULL AND v_t.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
    RAISE EXCEPTION 'DISPUTED';
  END IF;
  IF v_t.status NOT IN ('buyer_confirmed','auto_released') THEN
    RAISE EXCEPTION 'TRANSFER_NOT_RELEASABLE' USING DETAIL = 'status=' || v_t.status;
  END IF;
  -- 20260924000000 (registry 148, F-DISPUTE-SELLERWIN-1). A seller-win dispute
  -- resolution (065) leaves status 'buyer_confirmed' with buyer_confirmed_at NULL
  -- and dispute_resolution 'resolved_seller_paid'. That is an OPERATOR'S decision,
  -- not the buyer's statement, so it does NOT inherit the genuine buyer
  -- confirmation's override of risk holds: manual_review, or a payout_hold_until
  -- still in the future (or 'held' with no end), keeps it unpayable. The asymmetry
  -- is deliberate — do not harmonise it with the genuine-confirmation path, which
  -- stays exactly as before (buyer_confirmed_at IS NOT NULL is never tested here).
  IF v_t.status = 'buyer_confirmed' AND v_t.buyer_confirmed_at IS NULL
     AND v_t.dispute_resolution = 'resolved_seller_paid' THEN
    IF v_t.payout_review_status = 'manual_review' THEN
      RAISE EXCEPTION 'PAYOUT_UNDER_REVIEW';
    END IF;
    IF (v_t.payout_hold_until IS NOT NULL AND v_t.payout_hold_until > now())
       OR (v_t.payout_review_status = 'held' AND v_t.payout_hold_until IS NULL) THEN
      RAISE EXCEPTION 'PAYOUT_HELD' USING DETAIL = coalesce(v_t.payout_hold_until::text, 'no end');
    END IF;
  END IF;

  SELECT * INTO v_p FROM public.payments WHERE id = v_t.payment_id;
  IF NOT FOUND OR v_p.status <> 'succeeded' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_SUCCEEDED' USING DETAIL = coalesce(v_p.status, '<missing>');
  END IF;
  -- Mode boundary (045): never pay out against a non-live capture. The
  -- sandbox-only switch app.allow_test_mode_money = 'on' (ALTER DATABASE on an
  -- isolated test project; never production) admits stripe_livemode = false
  -- rows so a Stripe test key can exercise real Connect test transfers. NULL
  -- (unclassified) is never admitted.
  IF v_p.stripe_livemode IS DISTINCT FROM true
     AND NOT (v_p.stripe_livemode IS NOT DISTINCT FROM false
              AND coalesce(current_setting('app.allow_test_mode_money', true), 'off') = 'on') THEN
    RAISE EXCEPTION 'PAYMENT_NOT_LIVE';
  END IF;
  IF v_p.stripe_payment_intent_id IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_SUCCEEDED' USING DETAIL = 'no payment intent id';
  END IF;
  -- A partially refunded charge (review round 2, MINOR-3): the platform no
  -- longer retains amount - seller_fee, and who bears a partial refund is an
  -- operator decision. Never pay automatically; the transfer stays an
  -- unpaid_seller_obligation until an operator settles it (DAY5 playbook).
  IF coalesce(v_p.amount_refunded_cents, 0) > 0 THEN
    RAISE EXCEPTION 'PAYMENT_PARTIALLY_REFUNDED'
      USING DETAIL = v_p.amount_refunded_cents::text || '/' || v_p.total::text;
  END IF;

  SELECT pr.stripe_connect_id INTO v_dest FROM public.profiles pr WHERE pr.id = v_t.seller_id;
  IF v_dest IS NULL OR v_dest = '' THEN
    RAISE EXCEPTION 'SELLER_NOT_ONBOARDED';
  END IF;

  -- 10/10 fee model: seller net = amount − seller_fee (integer cents).
  v_amt := v_p.amount - coalesce(v_p.seller_fee, 0);
  IF v_amt <= 0 THEN
    RAISE EXCEPTION 'PAYOUT_AMOUNT_INVALID' USING DETAIL = v_amt::text;
  END IF;

  -- The open-attempt branch above always reconciles. Only throttle fresh
  -- scheduled attempts, while holding the same transfer lock as the insert.
  IF p_actor = 'cron:enforce-transfer-expiry' AND EXISTS (
    SELECT 1
      FROM (
        SELECT a.state, a.error, a.resolved_at
          FROM public.payout_attempts a
         WHERE a.transfer_id = p_transfer_id
         ORDER BY a.attempt_no DESC
         LIMIT 1
      ) latest
     WHERE latest.state = 'failed'
       AND latest.resolved_at > now() - interval '1 hour'
       AND (
         latest.error->>'reason_code' = 'PAYOUT_INSUFFICIENT_FUNDS'
         OR latest.error->>'error_class' IN ('insufficient_funds', 'balance_insufficient')
       )
  ) THEN
    RAISE EXCEPTION 'PAYOUT_FUNDING_COOLDOWN';
  END IF;

  SELECT coalesce(max(a.attempt_no), 0) + 1 INTO v_no FROM public.payout_attempts a WHERE a.transfer_id = p_transfer_id;

  INSERT INTO public.payout_attempts
    (transfer_id, payment_id, attempt_no, state, destination, amount_cents, currency, source_charge_id,
     idempotency_key, actor, lease_expires_at)
  VALUES
    (p_transfer_id, v_p.id, v_no, 'claimed', v_dest, v_amt, 'usd', NULL,
     'payout_' || p_transfer_id::text || '_a' || v_no::text, coalesce(p_actor, 'unknown'), now() + v_lease)
  RETURNING * INTO v_open;

  RETURN QUERY SELECT v_open.id, v_open.attempt_no, v_open.idempotency_key, v_open.destination,
                      v_open.amount_cents, v_open.source_charge_id, v_p.stripe_payment_intent_id, false;
END; $function$;
COMMIT;
