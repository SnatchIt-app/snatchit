-- ============================================================================
-- 20260924120000_payout_decisions_buyer_confirmed_truth.sql  (registry 149, pgTAP 216)
--
-- F-CR-148-SHARED follow-up, SQL writers a3/a4 (FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md).
--
-- payout_decisions.buyer_confirmed states that the BUYER confirmed receipt. The
-- only record of that act is transfers.buyer_confirmed_at, written by
-- confirm_transfer_received (0550). Two writers derived the flag from
-- transfers.status = 'buyer_confirmed' instead — a status that a seller-win
-- dispute resolution (065) also sets while leaving buyer_confirmed_at NULL — so
-- a manual_review decision on a seller-win row asserted a confirmation that
-- never happened, and one on a confirmed row later frozen by a chargeback
-- (status 'disputed') denied one that did:
--   a3  record_payout_attempt_result  (reversal_required: DUPLICATE_TRANSFER,
--       PAID_DURING_DISPUTE)
--   a4  flag_payout_reversal_required (a chargeback lost after payout)
-- Each now reads buyer_confirmed_at IS NOT NULL. Nothing else changes: both
-- bodies are 20260906120000's byte for byte apart from that one expression, so
-- signature, SECURITY DEFINER, search_path, lock order and grants (preserved by
-- CREATE OR REPLACE) are unchanged. No new object; census unchanged.
--
-- Versioned by TIMESTAMP: both functions are owned by timestamped
-- 20260906120000, and a numbered file would sort before it (registry rule, 134).
-- The edge writers a1/a2 (confirm-and-release) are fixed in the same change.
-- Body md5 (prosrc) before -> after:
--   record_payout_attempt_result   6a8372b4ee470d7a6ab9c1e0754765da -> 62f747287fa1c47d7bea06b686426ae3
--   flag_payout_reversal_required  d86c2b36f40c83835624bbacee716d38 -> 03ea4589c46624b72fa4d48e466ac977
-- Rollback: supabase/rollbacks/20260924120000_payout_decisions_buyer_confirmed_truth_rollback.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_payout_attempt_result(
  p_attempt_id         uuid,
  p_stripe_transfer_id text,
  p_outcome            text,
  p_error              jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_a        public.payout_attempts%ROWTYPE;
  v_t        public.transfers%ROWTYPE;
  v_tid      uuid;
  v_state    text;
  v_reasons  text[];
  v_recorded boolean := false;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('succeeded','failed_not_created','unknown') THEN
    RAISE EXCEPTION 'INVALID_OUTCOME' USING DETAIL = coalesce(p_outcome, '<null>');
  END IF;

  -- Lock order (review round 1 MINOR-2): transfers FIRST, then the attempt —
  -- the same order as claim_payout_attempt / flag_payout_reversal_required,
  -- so a transfer.created webhook racing the 2b sweep serialises on the
  -- transfer row instead of deadlocking (40P01). The attempt's transfer_id is
  -- immutable (guard_payout_attempt_columns), so the unlocked read is safe.
  SELECT a.transfer_id INTO v_tid FROM public.payout_attempts a WHERE a.id = p_attempt_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = v_tid FOR UPDATE;
  SELECT * INTO v_a FROM public.payout_attempts WHERE id = p_attempt_id FOR UPDATE;

  IF p_outcome = 'unknown' THEN
    IF v_a.state IN ('claimed','requested','unknown') THEN
      UPDATE public.payout_attempts
         SET state = 'unknown', error = coalesce(p_error, error),
             lease_expires_at = now() + interval '10 minutes'
       WHERE id = p_attempt_id
       RETURNING * INTO v_a;
    END IF;
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  IF p_outcome = 'failed_not_created' THEN
    IF v_a.state IN ('claimed','requested','unknown') THEN
      UPDATE public.payout_attempts
         SET state = 'failed', error = coalesce(p_error, error), resolved_at = now()
       WHERE id = p_attempt_id
       RETURNING * INTO v_a;
    END IF;
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  -- succeeded
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RAISE EXCEPTION 'STRIPE_TRANSFER_ID_REQUIRED';
  END IF;
  IF v_a.stripe_transfer_id IS NOT NULL AND v_a.stripe_transfer_id <> p_stripe_transfer_id THEN
    RAISE EXCEPTION 'ATTEMPT_TRANSFER_MISMATCH' USING DETAIL = v_a.stripe_transfer_id || ' <> ' || p_stripe_transfer_id;
  END IF;

  IF v_a.state IN ('succeeded','reversal_required') THEN
    -- Idempotent replay (transfer.created webhook after the edge recorded).
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  -- Always record the money movement on the transfer row (056d refused here — F07).
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET payout_released_at = coalesce(payout_released_at, now()),
         stripe_transfer_id = p_stripe_transfer_id
   WHERE id = v_a.transfer_id
     AND (stripe_transfer_id IS NULL OR stripe_transfer_id = p_stripe_transfer_id);
  v_recorded := FOUND;

  v_state   := 'succeeded';
  v_reasons := ARRAY[]::text[];
  IF v_t.disputed_at IS NOT NULL AND v_t.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
    v_state   := 'reversal_required';
    v_reasons := array_append(v_reasons, 'PAID_DURING_DISPUTE');
  END IF;
  IF NOT v_recorded THEN
    -- The transfer row already carries a DIFFERENT Stripe transfer: two real
    -- transfers exist for one obligation. Never silent.
    v_state   := 'reversal_required';
    v_reasons := array_append(v_reasons, 'DUPLICATE_TRANSFER');
  END IF;

  UPDATE public.payout_attempts
     SET state = v_state, stripe_transfer_id = p_stripe_transfer_id,
         resolved_at = now(),
         -- evidence is never overwritten: a later recorder (the transfer.created
         -- webhook after the edge) is appended under "subsequent"
         error = CASE WHEN p_error IS NULL THEN error
                      WHEN error   IS NULL THEN p_error
                      ELSE error || jsonb_build_object('subsequent',
                             coalesce(error->'subsequent', '[]'::jsonb) || jsonb_build_array(p_error - 'subsequent'))
                 END
   WHERE id = p_attempt_id
   RETURNING * INTO v_a;

  IF v_state = 'reversal_required' THEN
    INSERT INTO public.payout_decisions
      (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence,
       buyer_confirmed, dispute_open, actor)
    SELECT v_t.id, v_t.payment_id, v_t.seller_id, v_t.buyer_id, 'high', 'manual_review', v_reasons,
           jsonb_build_object('attempt_id', v_a.id, 'attempt_no', v_a.attempt_no,
                              'stripe_transfer_id', p_stripe_transfer_id,
                              'existing_stripe_transfer_id', v_t.stripe_transfer_id,
                              'amount_cents', v_a.amount_cents, 'destination', v_a.destination),
           v_t.buyer_confirmed_at IS NOT NULL, v_t.disputed_at IS NOT NULL, v_a.actor
    WHERE NOT EXISTS (
      SELECT 1 FROM public.payout_decisions d
       WHERE d.transfer_id = v_t.id AND d.decision = 'manual_review'
         AND d.evidence->>'attempt_id' = v_a.id::text
         AND d.reason_codes && v_reasons);
  END IF;

  RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                            'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', v_recorded,
                            'transfer_id', v_a.transfer_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.flag_payout_reversal_required(
  p_transfer_id uuid,
  p_reason_code text,
  p_evidence    jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_t   public.transfers%ROWTYPE;
  v_att uuid;
  v_ins int := 0;
BEGIN
  IF p_reason_code IS NULL OR p_reason_code = '' THEN
    RAISE EXCEPTION 'REASON_CODE_REQUIRED';
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSFER_NOT_FOUND';
  END IF;
  IF v_t.payout_released_at IS NULL AND v_t.stripe_transfer_id IS NULL THEN
    RETURN jsonb_build_object('transfer_id', p_transfer_id, 'paid_out', false, 'flagged', false);
  END IF;

  UPDATE public.payout_attempts
     SET state = 'reversal_required',
         error = coalesce(error, '{}'::jsonb) || jsonb_build_object('reversal_reason', p_reason_code)
   WHERE transfer_id = p_transfer_id AND state = 'succeeded'
   RETURNING id INTO v_att;

  INSERT INTO public.payout_decisions
    (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence,
     buyer_confirmed, dispute_open, actor)
  SELECT v_t.id, v_t.payment_id, v_t.seller_id, v_t.buyer_id, 'high', 'manual_review', ARRAY[p_reason_code],
         coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('stripe_transfer_id', v_t.stripe_transfer_id, 'attempt_id', v_att),
         v_t.buyer_confirmed_at IS NOT NULL, true, 'edge:stripe-webhook'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.payout_decisions d
     WHERE d.transfer_id = v_t.id AND d.decision = 'manual_review' AND p_reason_code = ANY(d.reason_codes));
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'paid_out', true, 'flagged', true,
                            'attempt_id', v_att, 'decision_inserted', v_ins = 1,
                            'stripe_transfer_id', v_t.stripe_transfer_id);
END; $function$;

insert into supabase_migrations.schema_migrations(version, name, statements, created_by) values ('20260924120000', 'payout_decisions_buyer_confirmed_truth', array[$snatchit_ledger_149$-- ============================================================================
-- 20260924120000_payout_decisions_buyer_confirmed_truth.sql  (registry 149, pgTAP 216)
--
-- F-CR-148-SHARED follow-up, SQL writers a3/a4 (FINDINGS_20260924_DISPUTE_GRANT_AND_OPS_CASE.md).
--
-- payout_decisions.buyer_confirmed states that the BUYER confirmed receipt. The
-- only record of that act is transfers.buyer_confirmed_at, written by
-- confirm_transfer_received (0550). Two writers derived the flag from
-- transfers.status = 'buyer_confirmed' instead — a status that a seller-win
-- dispute resolution (065) also sets while leaving buyer_confirmed_at NULL — so
-- a manual_review decision on a seller-win row asserted a confirmation that
-- never happened, and one on a confirmed row later frozen by a chargeback
-- (status 'disputed') denied one that did:
--   a3  record_payout_attempt_result  (reversal_required: DUPLICATE_TRANSFER,
--       PAID_DURING_DISPUTE)
--   a4  flag_payout_reversal_required (a chargeback lost after payout)
-- Each now reads buyer_confirmed_at IS NOT NULL. Nothing else changes: both
-- bodies are 20260906120000's byte for byte apart from that one expression, so
-- signature, SECURITY DEFINER, search_path, lock order and grants (preserved by
-- CREATE OR REPLACE) are unchanged. No new object; census unchanged.
--
-- Versioned by TIMESTAMP: both functions are owned by timestamped
-- 20260906120000, and a numbered file would sort before it (registry rule, 134).
-- The edge writers a1/a2 (confirm-and-release) are fixed in the same change.
-- Body md5 (prosrc) before -> after:
--   record_payout_attempt_result   6a8372b4ee470d7a6ab9c1e0754765da -> 62f747287fa1c47d7bea06b686426ae3
--   flag_payout_reversal_required  d86c2b36f40c83835624bbacee716d38 -> 03ea4589c46624b72fa4d48e466ac977
-- Rollback: supabase/rollbacks/20260924120000_payout_decisions_buyer_confirmed_truth_rollback.sql
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_payout_attempt_result(
  p_attempt_id         uuid,
  p_stripe_transfer_id text,
  p_outcome            text,
  p_error              jsonb DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_a        public.payout_attempts%ROWTYPE;
  v_t        public.transfers%ROWTYPE;
  v_tid      uuid;
  v_state    text;
  v_reasons  text[];
  v_recorded boolean := false;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('succeeded','failed_not_created','unknown') THEN
    RAISE EXCEPTION 'INVALID_OUTCOME' USING DETAIL = coalesce(p_outcome, '<null>');
  END IF;

  -- Lock order (review round 1 MINOR-2): transfers FIRST, then the attempt —
  -- the same order as claim_payout_attempt / flag_payout_reversal_required,
  -- so a transfer.created webhook racing the 2b sweep serialises on the
  -- transfer row instead of deadlocking (40P01). The attempt's transfer_id is
  -- immutable (guard_payout_attempt_columns), so the unlocked read is safe.
  SELECT a.transfer_id INTO v_tid FROM public.payout_attempts a WHERE a.id = p_attempt_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = v_tid FOR UPDATE;
  SELECT * INTO v_a FROM public.payout_attempts WHERE id = p_attempt_id FOR UPDATE;

  IF p_outcome = 'unknown' THEN
    IF v_a.state IN ('claimed','requested','unknown') THEN
      UPDATE public.payout_attempts
         SET state = 'unknown', error = coalesce(p_error, error),
             lease_expires_at = now() + interval '10 minutes'
       WHERE id = p_attempt_id
       RETURNING * INTO v_a;
    END IF;
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  IF p_outcome = 'failed_not_created' THEN
    IF v_a.state IN ('claimed','requested','unknown') THEN
      UPDATE public.payout_attempts
         SET state = 'failed', error = coalesce(p_error, error), resolved_at = now()
       WHERE id = p_attempt_id
       RETURNING * INTO v_a;
    END IF;
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  -- succeeded
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RAISE EXCEPTION 'STRIPE_TRANSFER_ID_REQUIRED';
  END IF;
  IF v_a.stripe_transfer_id IS NOT NULL AND v_a.stripe_transfer_id <> p_stripe_transfer_id THEN
    RAISE EXCEPTION 'ATTEMPT_TRANSFER_MISMATCH' USING DETAIL = v_a.stripe_transfer_id || ' <> ' || p_stripe_transfer_id;
  END IF;

  IF v_a.state IN ('succeeded','reversal_required') THEN
    -- Idempotent replay (transfer.created webhook after the edge recorded).
    RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                              'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', false);
  END IF;

  -- Always record the money movement on the transfer row (056d refused here — F07).
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET payout_released_at = coalesce(payout_released_at, now()),
         stripe_transfer_id = p_stripe_transfer_id
   WHERE id = v_a.transfer_id
     AND (stripe_transfer_id IS NULL OR stripe_transfer_id = p_stripe_transfer_id);
  v_recorded := FOUND;

  v_state   := 'succeeded';
  v_reasons := ARRAY[]::text[];
  IF v_t.disputed_at IS NOT NULL AND v_t.dispute_resolution IS DISTINCT FROM 'resolved_seller_paid' THEN
    v_state   := 'reversal_required';
    v_reasons := array_append(v_reasons, 'PAID_DURING_DISPUTE');
  END IF;
  IF NOT v_recorded THEN
    -- The transfer row already carries a DIFFERENT Stripe transfer: two real
    -- transfers exist for one obligation. Never silent.
    v_state   := 'reversal_required';
    v_reasons := array_append(v_reasons, 'DUPLICATE_TRANSFER');
  END IF;

  UPDATE public.payout_attempts
     SET state = v_state, stripe_transfer_id = p_stripe_transfer_id,
         resolved_at = now(),
         -- evidence is never overwritten: a later recorder (the transfer.created
         -- webhook after the edge) is appended under "subsequent"
         error = CASE WHEN p_error IS NULL THEN error
                      WHEN error   IS NULL THEN p_error
                      ELSE error || jsonb_build_object('subsequent',
                             coalesce(error->'subsequent', '[]'::jsonb) || jsonb_build_array(p_error - 'subsequent'))
                 END
   WHERE id = p_attempt_id
   RETURNING * INTO v_a;

  IF v_state = 'reversal_required' THEN
    INSERT INTO public.payout_decisions
      (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence,
       buyer_confirmed, dispute_open, actor)
    SELECT v_t.id, v_t.payment_id, v_t.seller_id, v_t.buyer_id, 'high', 'manual_review', v_reasons,
           jsonb_build_object('attempt_id', v_a.id, 'attempt_no', v_a.attempt_no,
                              'stripe_transfer_id', p_stripe_transfer_id,
                              'existing_stripe_transfer_id', v_t.stripe_transfer_id,
                              'amount_cents', v_a.amount_cents, 'destination', v_a.destination),
           v_t.buyer_confirmed_at IS NOT NULL, v_t.disputed_at IS NOT NULL, v_a.actor
    WHERE NOT EXISTS (
      SELECT 1 FROM public.payout_decisions d
       WHERE d.transfer_id = v_t.id AND d.decision = 'manual_review'
         AND d.evidence->>'attempt_id' = v_a.id::text
         AND d.reason_codes && v_reasons);
  END IF;

  RETURN jsonb_build_object('attempt_id', v_a.id, 'state', v_a.state,
                            'stripe_transfer_id', v_a.stripe_transfer_id, 'recorded', v_recorded,
                            'transfer_id', v_a.transfer_id);
END; $function$;

CREATE OR REPLACE FUNCTION public.flag_payout_reversal_required(
  p_transfer_id uuid,
  p_reason_code text,
  p_evidence    jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_t   public.transfers%ROWTYPE;
  v_att uuid;
  v_ins int := 0;
BEGIN
  IF p_reason_code IS NULL OR p_reason_code = '' THEN
    RAISE EXCEPTION 'REASON_CODE_REQUIRED';
  END IF;
  SELECT * INTO v_t FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSFER_NOT_FOUND';
  END IF;
  IF v_t.payout_released_at IS NULL AND v_t.stripe_transfer_id IS NULL THEN
    RETURN jsonb_build_object('transfer_id', p_transfer_id, 'paid_out', false, 'flagged', false);
  END IF;

  UPDATE public.payout_attempts
     SET state = 'reversal_required',
         error = coalesce(error, '{}'::jsonb) || jsonb_build_object('reversal_reason', p_reason_code)
   WHERE transfer_id = p_transfer_id AND state = 'succeeded'
   RETURNING id INTO v_att;

  INSERT INTO public.payout_decisions
    (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, evidence,
     buyer_confirmed, dispute_open, actor)
  SELECT v_t.id, v_t.payment_id, v_t.seller_id, v_t.buyer_id, 'high', 'manual_review', ARRAY[p_reason_code],
         coalesce(p_evidence, '{}'::jsonb) || jsonb_build_object('stripe_transfer_id', v_t.stripe_transfer_id, 'attempt_id', v_att),
         v_t.buyer_confirmed_at IS NOT NULL, true, 'edge:stripe-webhook'
  WHERE NOT EXISTS (
    SELECT 1 FROM public.payout_decisions d
     WHERE d.transfer_id = v_t.id AND d.decision = 'manual_review' AND p_reason_code = ANY(d.reason_codes));
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  RETURN jsonb_build_object('transfer_id', p_transfer_id, 'paid_out', true, 'flagged', true,
                            'attempt_id', v_att, 'decision_inserted', v_ins = 1,
                            'stripe_transfer_id', v_t.stripe_transfer_id);
END; $function$;
$snatchit_ledger_149$], 'claude-a/owner-authorised-149');
