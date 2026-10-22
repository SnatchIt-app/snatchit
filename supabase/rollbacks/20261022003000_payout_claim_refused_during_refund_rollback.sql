-- ============================================================================
-- ROLLBACK for 20261022003000_payout_claim_refused_during_refund.sql (registry 179, pgTAP 249).
-- Restores public.claim_payout_attempt(uuid, text, interval) to PRODUCTION's body VERBATIM:
--   md5 b6aae8680e1891892dd0d42f62b9531b  (pg_get_functiondef on the replay template, A's read 2026-10-22; neither 157, 158
--   nor 177 touches it), SECURITY DEFINER, search_path public, ACL postgres=X/postgres,service_role=X/postgres, no comment.
-- 179's md5 (the applied state): e2ba30303f77137f589bb4fd37778cb1.
-- STACKING GUARD (first statement): the live body must carry 179's md5 (applied) or production's (already restored;
--   re-running this file is then a no-op that re-verifies). Any third body means someone else's change sits on top
--   (a later migration, a hand edit): RAISE, nothing changed — restoring over it would silently discard it.
-- WHAT: restores the body verbatim, re-states the ACL, drops 179's comment, then VERIFIES inside the same transaction
--   that md5(pg_get_functiondef(...)), the ACL, SECURITY DEFINER, search_path, the comment and the overload count equal
--   production's (the message names what differs, with the live value). Any mismatch RAISEs: a partial or drifted
--   rollback changes nothing.
-- KEEPS: every ops.action row, every payout_attempts row, every transfer and payment. Nothing else is touched: 157's,
--   158's and 177's objects stay (this file is independent of 177's rollback; roll back 179 before 157 only because
--   179's own pre-flight needs 157's helper for a re-apply).
-- AFTER ROLLBACK: a payout can be claimed again while a console refund is unsettled (the defect 179 closes; no security
--   hole is restored: the body is production's, service_role only).
--   Run only under owner approval.
-- ============================================================================
BEGIN;
-- ── stacking guard: refuse (nothing changed) unless the body is 179's or already production's ─
DO $stack179$
DECLARE
  v_md5 text := md5(pg_get_functiondef(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)')));
BEGIN
  IF v_md5 IS DISTINCT FROM 'e2ba30303f77137f589bb4fd37778cb1' AND v_md5 IS DISTINCT FROM 'b6aae8680e1891892dd0d42f62b9531b' THEN
    RAISE EXCEPTION '179 rollback refused (nothing changed): public.claim_payout_attempt(uuid,text,interval) md5 % (expected 179''s e2ba30303f77137f589bb4fd37778cb1 or production''s b6aae8680e1891892dd0d42f62b9531b); another change sits on top of 179: roll that back first',
      coalesce(v_md5, '<missing>');
  END IF;
  IF v_md5 = 'b6aae8680e1891892dd0d42f62b9531b' THEN
    RAISE NOTICE '179 rollback: claim_payout_attempt already carries production''s body; re-verifying only';
  END IF;
END $stack179$;
SET LOCAL lock_timeout = '3s';

-- ── public.claim_payout_attempt: production's body, verbatim ──────────────
CREATE OR REPLACE FUNCTION public.claim_payout_attempt(p_transfer_id uuid, p_actor text, p_lease interval DEFAULT '00:10:00'::interval)
 RETURNS TABLE(attempt_id uuid, attempt_no integer, idempotency_key text, destination text, amount_cents integer, source_charge_id text, payment_intent_id text, needs_reconcile boolean)
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
END; $function$
;

REVOKE ALL ON FUNCTION public.claim_payout_attempt(uuid,text,interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_payout_attempt(uuid,text,interval) TO service_role;
COMMENT ON FUNCTION public.claim_payout_attempt(uuid,text,interval) IS NULL;

-- ── verification (inside the transaction: a mismatch aborts the whole rollback) ─
DO $verify179rb$
DECLARE
  v_md5  text := md5(pg_get_functiondef(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)')));
  v_acl  text := (SELECT coalesce(array_to_string(proacl, ','), '<default>') FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_sec  boolean := (SELECT prosecdef FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_cfg  text := (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_cmt  text := obj_description(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'pg_proc');
  v_n    int  := (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'claim_payout_attempt');
  v_bad  text := '';
BEGIN
  IF v_md5 IS DISTINCT FROM 'b6aae8680e1891892dd0d42f62b9531b' THEN v_bad := v_bad || format('md5 %s <> production''s b6aae8680e1891892dd0d42f62b9531b; ', coalesce(v_md5, '<missing>')); END IF;
  IF v_acl <> 'postgres=X/postgres,service_role=X/postgres' THEN v_bad := v_bad || format('acl %s <> postgres=X/postgres,service_role=X/postgres; ', v_acl); END IF;
  IF has_function_privilege('anon', to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'EXECUTE')
     OR has_function_privilege('authenticated', to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'EXECUTE')
     OR NOT has_function_privilege('service_role', to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'EXECUTE') THEN
    v_bad := v_bad || 'execute privilege: anon / authenticated must not, service_role must; ';
  END IF;
  IF NOT v_sec THEN v_bad := v_bad || 'not SECURITY DEFINER; '; END IF;
  IF v_cfg IS DISTINCT FROM 'search_path=public' THEN v_bad := v_bad || format('proconfig %s <> search_path=public; ', coalesce(v_cfg, '<none>')); END IF;
  IF v_cmt IS NOT NULL THEN v_bad := v_bad || 'comment still present; '; END IF;
  IF v_n <> 1 THEN v_bad := v_bad || format('%s overloads; ', v_n); END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '179 rollback verification failed (nothing changed): %', v_bad USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '179 rollback verified: claim_payout_attempt = production (b6aae8680e1891892dd0d42f62b9531b), acl postgres + service_role, definer, search_path public, no comment';
END $verify179rb$;
COMMIT;

-- Read-only re-check after COMMIT (expect ok = true):
SELECT md5(pg_get_functiondef(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'))) = 'b6aae8680e1891892dd0d42f62b9531b' AS ok;
