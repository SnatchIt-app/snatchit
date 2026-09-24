-- ============================================================================
-- 20260924000000_seller_win_dispute_payout_and_notice.sql — registry 148
-- F-DISPUTE-SELLERWIN-1 (A, 2026-09-24). Source change for review; NOT applied.
--
-- WHAT. A seller-win dispute resolution (065 resolve_transfer_dispute) sets
-- transfers.status = 'buyer_confirmed', clears disputed_at, records
-- dispute_resolution = 'resolved_seller_paid' + dispute_resolved_at, and leaves
-- buyer_confirmed_at NULL — correctly: the buyer never confirmed. Two readers
-- treated the status as proof that the BUYER acted:
--   1. claim_payout_attempt admitted a seller-win regardless of risk holds. The
--      path that reaches it today is confirm-and-release, whose "already
--      confirmed" inference pays a seller-win immediately when the losing buyer
--      calls it. After this migration that path respects the hold: a behaviour
--      change to a live path, made on purpose.
--   2. notify_transfer_state_inbox (058) told the seller "Buyer confirmed receipt".
-- This migration redefines exactly those two functions (bodies copied verbatim
-- from 20260906120000 and 058, plus the marked additions). No table, grant,
-- trigger or policy changes; CREATE OR REPLACE keeps the existing ACLs.
-- The payout SELECTION for seller-wins is an edge change in the same PR
-- (enforce-transfer-expiry Phase 2b d); the a)+b) query is byte-identical.
--
-- THE ASYMMETRY (deliberate — do not harmonise). A genuine buyer confirmation
-- overrides risk holds (the buyer's own statement is the strongest delivery
-- evidence). An operator's seller-win decision does not: manual_review and a
-- pending payout_hold_until keep it unpayable. The discriminator is existing
-- state (buyer_confirmed_at IS NULL AND dispute_resolution = 'resolved_seller_paid');
-- nothing manufactures a confirmation timestamp.
--
-- VERIFY. pgTAP 215 (payout and notification asserted separately; hold matrix
-- shared with tests/seller-win-dispute.test.ts). Rollback:
-- supabase/rollbacks/20260924000000_seller_win_dispute_payout_and_notice_rollback.sql
-- restores both applied bodies verbatim and checks their hashes.
-- ============================================================================

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

    -- 20260924000000 (registry 148): only a GENUINE buyer confirmation sets
    -- buyer_confirmed_at (confirm_transfer_received, 0550). An operator's
    -- seller-win decision (065) and the old manual runbook set the status alone,
    -- so without the timestamp the seller must not be told the buyer confirmed.
    IF NEW.status = 'buyer_confirmed' AND OLD.status IS DISTINCT FROM 'buyer_confirmed'
       AND NEW.buyer_confirmed_at IS NOT NULL THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'transfer_confirmed', 'Buyer confirmed receipt',
        'The buyer confirmed they received the tickets for ' || coalesce(v_title,'your sale') || '.',
        '/transfer/send/' || NEW.id::text,
        'transfer_confirmed:' || NEW.id::text,
        jsonb_build_object('transfer_id', NEW.id));
    END IF;

    -- 20260924000000 (registry 148): the operator's decision itself, keyed on the
    -- recorded resolution (state, not a parameter). Fires whether or not the
    -- transfer was already paid, and says nothing about the payout: the payout
    -- notice comes only when payout_released_at is actually set (below).
    IF NEW.dispute_resolution = 'resolved_seller_paid'
       AND OLD.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
      PERFORM public.enqueue_notification(
        NEW.seller_id, 'dispute_resolved_seller', 'Dispute resolved in your favour',
        'The dispute on ' || coalesce(v_title,'your sale') || ' was resolved in your favour.',
        '/transfer/send/' || NEW.id::text,
        'dispute_resolved:' || NEW.id::text || ':seller',
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
