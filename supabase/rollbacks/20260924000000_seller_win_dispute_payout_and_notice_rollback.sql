-- ============================================================================
-- ROLLBACK of 20260924000000_seller_win_dispute_payout_and_notice.sql (registry 148)
-- Restores the APPLIED bodies verbatim — claim_payout_attempt from
-- 20260906120000 and notify_transfer_state_inbox from 058 (extracted, not
-- retyped) — inside one transaction. It refuses unless the current bodies are
-- exactly the 148 bodies, and it raises unless the restored bodies hash to the
-- pre-148 values. Consequence of rolling back: the payout claim again admits a
-- seller-win under a pending hold (via confirm-and-release), and the seller is
-- again told "Buyer confirmed receipt" after a seller-win. The edge change
-- (enforce-transfer-expiry Phase 2b d) rolls back by redeploying the previous
-- function version; with the edge rolled back and this SQL kept, nothing breaks
-- (the claim rule only refuses more).
--   148 prosrc md5:     claim_payout_attempt ce30b56ca038ae0c4de2c88770870561
--                       notify_transfer_state_inbox ff103b3e98faa04f9bd64996a90b27ab
--   pre-148 prosrc md5: claim_payout_attempt 083bf9a396e1d42f66abf7c7eb07f9b7
--                       notify_transfer_state_inbox 203f7c7d88c6545a9c083e037a6aa5db
-- ============================================================================
BEGIN;

DO $guard$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.claim_payout_attempt(uuid,text,interval)'::regprocedure)
       IS DISTINCT FROM 'ce30b56ca038ae0c4de2c88770870561'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.notify_transfer_state_inbox()'::regprocedure)
       IS DISTINCT FROM 'ff103b3e98faa04f9bd64996a90b27ab' THEN
    RAISE EXCEPTION '148 rollback refused: the current bodies are not the 20260924000000 bodies — inspect before restoring anything';
  END IF;
END $guard$;

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

CREATE OR REPLACE FUNCTION public.notify_transfer_state_inbox()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_title text;
BEGIN
  BEGIN
    SELECT event_name INTO v_title FROM public.listings WHERE id = NEW.listing_id;

    IF NEW.status = 'seller_sent' AND OLD.status IS DISTINCT FROM 'seller_sent' THEN
      PERFORM public.enqueue_notification(
        NEW.buyer_id, 'buyer_confirmation_needed', 'Your tickets were sent',
        'The seller sent your tickets for ' || coalesce(v_title,'your purchase') || '. Confirm once you have them.',
        '/transfer/receive/' || NEW.id::text,
        'buyer_confirmation_needed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    IF NEW.buyer_viewed_at IS NOT NULL AND OLD.buyer_viewed_at IS NULL THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_viewed', 'Buyer viewed your transfer',
        'The buyer opened the transfer for ' || coalesce(v_title,'your sale') || '.',
        '/transfer/send/' || NEW.id::text,
        'transfer_viewed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    IF NEW.status = 'buyer_confirmed' AND OLD.status IS DISTINCT FROM 'buyer_confirmed' THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_confirmed', 'Buyer confirmed receipt',
        'The buyer confirmed they received the tickets for ' || coalesce(v_title,'your sale') || '.',
        '/transfer/send/' || NEW.id::text,
        'transfer_confirmed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    IF NEW.status = 'disputed' AND OLD.status IS DISTINCT FROM 'disputed' THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_disputed', 'A dispute was opened',
        'The buyer opened a dispute on ' || coalesce(v_title,'your sale') || '. Your payout is on hold.',
        '/transfer/send/' || NEW.id::text,
        'transfer_disputed:' || NEW.id::text || ':seller',
        jsonb_build_object('transfer_id', NEW.id));
      PERFORM public.enqueue_notification(
        NEW.buyer_id, 'transfer_disputed', 'Your dispute was opened',
        'We received your dispute for ' || coalesce(v_title,'your purchase') || '. Support will follow up.',
        '/transfer/receive/' || NEW.id::text,
        'transfer_disputed:' || NEW.id::text || ':buyer',
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    -- Single authoritative payout predicate. The auto-release path does NOT
    -- change status, so status is unusable here; payout_released_at is the only
    -- transition that happens exactly once, on both release paths.
    IF NEW.payout_released_at IS NOT NULL AND OLD.payout_released_at IS NULL THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'payout_released', 'Your payout was released',
        'Your payout for ' || coalesce(v_title,'your sale') || ' is on its way to your bank.',
        '/account/sales',
        'payout_released:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
      PERFORM public.enqueue_notification(
        NEW.buyer_id, 'order_complete', 'Order complete',
        'Your order for ' || coalesce(v_title,'your purchase') || ' is complete. Enjoy the event!',
        '/account/purchases',
        'order_complete:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_transfer_state_inbox failed: %', SQLERRM;
  END;
  RETURN NEW;
END; $function$;

DO $check$
BEGIN
  IF (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.claim_payout_attempt(uuid,text,interval)'::regprocedure)
       IS DISTINCT FROM '083bf9a396e1d42f66abf7c7eb07f9b7'
  OR (SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.notify_transfer_state_inbox()'::regprocedure)
       IS DISTINCT FROM '203f7c7d88c6545a9c083e037a6aa5db' THEN
    RAISE EXCEPTION '148 rollback: restored bodies do not match the pre-148 hashes — transaction aborted';
  END IF;
END $check$;

COMMIT;
