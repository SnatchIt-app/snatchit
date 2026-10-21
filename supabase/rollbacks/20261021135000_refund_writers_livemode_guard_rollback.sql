-- ============================================================================
-- ROLLBACK for 20261021135000_refund_writers_livemode_guard.sql (registry 175, pgTAP 245).
-- DRAFT like the migration; owner-gated. Run only under owner approval, and only if 175 was applied.
-- Pre-175 state = production 2026-10-21 (prod_functions.json, A's read-only snapshot; md5(pg_get_functiondef)):
--   public.record_refund_state(text,text,text,integer,text,text,text)  5e9f66129a4bb82b6b3e7a1b41e04365
--   public.record_payment_refund(text,text,text,integer,text)           8ce828e3461f97844faa36450241dc8f
--   public.assert_refund_livemode(uuid,boolean)                         absent
--   both writers: owner postgres, SECURITY DEFINER, ACL postgres=X/postgres,service_role=X/postgres;
--   search_path "" (record_refund_state) / public (record_payment_refund).
-- WHAT: restores the two writer bodies VERBATIM (the production pg_get_functiondef text read from
--   a_sprint_prod_template, byte for byte — not an older repo migration), then drops the helper. CREATE OR REPLACE
--   keeps the grants, owners and COMMENTs, which 175 never changed. Then VERIFIES inside the same transaction that
--   md5(pg_get_functiondef) of both writers equals production, that their grants, owner, SECURITY DEFINER and
--   search_path are unchanged from the pre-rollback state, and that the helper is gone. Any mismatch RAISEs, so a
--   partial or drifted rollback changes nothing.
-- STACKING GUARD (refuses, changes nothing): each writer must be either 175's body (md5s below) or production's;
--   the helper must be 175's body or absent; and no routine other than the two writers may reference
--   assert_refund_livemode. Anything else means a LATER migration built on 175; rolling 175 back would silently revert
--   or break it — roll the later one back first.
-- KEEPS: every row. 175 writes no data; refunds recorded while 175 was live stay recorded.
-- AFTER ROLLBACK: the writers again record refund facts on payment rows of ANY mode (the pre-175 defect,
--   private-evidence/A-sprint-20261021/a175/01_red.out). That is the production pre-state, not a new hole: no grant,
--   RLS or definer property is widened by this file.
-- ORDER: independent of the 154–158 and 170–174 rollbacks (175 touches only these two public routines and its own
--   helper).
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $guard175rb$
DECLARE
  v_bad text;
BEGIN
  -- record_payment_refund's production body contains an em dash (U+2014): byte-identity needs a UTF8 client
  IF current_setting('client_encoding') <> 'UTF8' THEN
    RAISE EXCEPTION '175 rollback refused: client_encoding is %, UTF8 required. Nothing changed.', current_setting('client_encoding')
      USING ERRCODE = 'P0001';
  END IF;
  SELECT string_agg(v.sig || ' md5 ' || coalesce(md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))), '<missing>'), '; ')
    INTO v_bad
    FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)', '24954bb9953ac0249dac6ee7aa93d6cd', '5e9f66129a4bb82b6b3e7a1b41e04365'),
                 ('public.record_payment_refund(text,text,text,integer,text)',          'aadd3cca365aae33b1903daaf9ff67d7', '8ce828e3461f97844faa36450241dc8f')) v(sig, md5_175, md5_prod)
   WHERE md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))) IS DISTINCT FROM v.md5_175
     AND md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))) IS DISTINCT FROM v.md5_prod;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 rollback refused (nothing changed): a writer is neither 175''s body nor production''s — a later migration redefined it; roll that back first: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text || ' md5 ' || md5(pg_get_functiondef(p.oid)), '; ')
    INTO v_bad
    FROM pg_catalog.pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'assert_refund_livemode'
     AND (p.oid IS DISTINCT FROM pg_catalog.to_regprocedure('public.assert_refund_livemode(uuid,boolean)')
          OR md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM 'c082eb3832fe435e7d10558bdc4bbc3c');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 rollback refused (nothing changed): assert_refund_livemode is not 175''s helper — a later migration changed it; roll that back first: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, '; ')
    INTO v_bad
    FROM pg_catalog.pg_proc p
   WHERE p.prosrc LIKE '%assert_refund_livemode%'
     AND p.oid NOT IN (pg_catalog.to_regprocedure('public.record_refund_state(text,text,text,integer,text,text,text)'),
                       pg_catalog.to_regprocedure('public.record_payment_refund(text,text,text,integer,text)'))
     AND p.oid IS DISTINCT FROM pg_catalog.to_regprocedure('public.assert_refund_livemode(uuid,boolean)');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 rollback refused (nothing changed): another routine calls assert_refund_livemode; dropping it would break that routine — roll it back first: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
END
$guard175rb$;

CREATE TEMP TABLE r175_pre ON COMMIT DROP AS
SELECT v.sig, array_to_string(p.proacl, ',') AS acl, p.prosecdef AS secdef, array_to_string(p.proconfig, ',') AS config,
       p.proowner AS owner
  FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)'),
               ('public.record_payment_refund(text,text,text,integer,text)')) v(sig)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig);

-- ── production bodies, verbatim ─────────────────────────────────────────────
-- 1. record_refund_state (production md5 5e9f66129a4bb82b6b3e7a1b41e04365)
CREATE OR REPLACE FUNCTION public.record_refund_state(p_payment_intent_id text, p_stripe_refund_id text, p_status text, p_amount_cents integer, p_failure_reason text, p_source text, p_observed_via text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_pay      public.payments%ROWTYPE;
  v_prev     public.payment_refund_state%ROWTYPE;
  v_had      boolean;
  v_changed  boolean;
  v_counted  boolean := false;
  v_req      integer;
  v_ok       integer;
  v_fail     integer;
BEGIN
  IF nullif(p_stripe_refund_id, '') IS NULL THEN
    RAISE EXCEPTION 'REFUND_REFERENCE_REQUIRED';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('pending','requires_action','succeeded','failed','canceled') THEN
    RAISE EXCEPTION 'INVALID_REFUND_STATUS' USING DETAIL = coalesce(p_status, '<null>');
  END IF;
  IF p_observed_via IS NULL OR p_observed_via NOT IN ('create_response','webhook','reconcile') THEN
    RAISE EXCEPTION 'INVALID_OBSERVATION_SOURCE' USING DETAIL = coalesce(p_observed_via, '<null>');
  END IF;
  IF p_source IS NULL OR p_source NOT IN ('expiry','dashboard','admin','unfulfillable') THEN
    RAISE EXCEPTION 'INVALID_REFUND_SOURCE' USING DETAIL = coalesce(p_source, '<null>');
  END IF;
  IF p_amount_cents IS NULL OR p_amount_cents < 0 THEN
    RAISE EXCEPTION 'INVALID_REFUND_AMOUNT' USING DETAIL = coalesce(p_amount_cents::text, '<null>');
  END IF;

  SELECT * INTO v_pay FROM public.payments
   WHERE stripe_payment_intent_id = p_payment_intent_id
   FOR UPDATE;
  IF NOT FOUND THEN
    -- Unknown to us (test-mode / foreign charge): acknowledged, never retried.
    RETURN jsonb_build_object('recorded', false, 'reason', 'unknown_payment', 'payment_id', NULL);
  END IF;

  SELECT * INTO v_prev FROM public.payment_refund_state
   WHERE stripe_refund_id = p_stripe_refund_id
   FOR UPDATE;
  v_had := FOUND;
  IF v_had AND v_prev.payment_id <> v_pay.id THEN
    RAISE EXCEPTION 'REFUND_PAYMENT_MISMATCH' USING DETAIL = p_stripe_refund_id;
  END IF;

  -- Failed and canceled are final at Stripe (docs.stripe.com/refunds documents no
  -- exit from either). An observation that disagrees is older than the one
  -- recorded: two deliveries each re-fetch the refund, and the earlier fetch can
  -- commit last. Refuse it whole: no state change, no log row, and never the
  -- one-way record, or a refund first seen failed would be counted as returned.
  -- Other statuses are not ordered: a bank refund goes succeeded -> requires_action.
  IF v_had AND v_prev.status IN ('failed','canceled') AND p_status <> v_prev.status THEN
    RETURN jsonb_build_object(
      'recorded',        false,
      'reason',          'stale_observation',
      'stale_ignored',   true,
      'payment_id',      v_pay.id,
      'refund_status',   v_prev.status,
      'requested_cents', v_pay.refund_requested_cents,
      'succeeded_cents', v_pay.refund_succeeded_cents,
      'failed_cents',    v_pay.refund_failed_cents
    );
  END IF;

  v_changed := NOT v_had
            OR v_prev.status         IS DISTINCT FROM p_status
            OR v_prev.failure_reason IS DISTINCT FROM p_failure_reason
            OR v_prev.amount_cents   IS DISTINCT FROM p_amount_cents;

  INSERT INTO public.payment_refund_state
    (stripe_refund_id, payment_id, amount_cents, status, failure_reason, source, last_observed_via)
  VALUES (p_stripe_refund_id, v_pay.id, p_amount_cents, p_status, p_failure_reason, p_source, p_observed_via)
  ON CONFLICT (stripe_refund_id) DO UPDATE
     SET amount_cents      = EXCLUDED.amount_cents,
         status            = EXCLUDED.status,
         failure_reason    = EXCLUDED.failure_reason,
         last_observed_at  = now(),
         last_observed_via = EXCLUDED.last_observed_via;

  IF v_changed THEN
    INSERT INTO public.payment_refund_state_log
      (stripe_refund_id, payment_id, status, amount_cents, failure_reason, observed_via)
    VALUES (p_stripe_refund_id, v_pay.id, p_status, p_amount_cents, p_failure_reason, p_observed_via);
  END IF;

  -- Only a refund that is (or was, when first seen) on its way back to the buyer
  -- enters the one-way record. It stays there if it later fails: the record means
  -- "a refund was requested" and keeps the payout blocked; the truth is below.
  IF p_status IN ('pending','requires_action','succeeded') THEN
    PERFORM public.record_payment_refund(p_payment_intent_id, p_stripe_refund_id, NULL, p_amount_cents, p_source);
    v_counted := true;
  END IF;

  SELECT coalesce(sum(amount_cents) FILTER (WHERE status IN ('pending','requires_action')), 0),
         coalesce(sum(amount_cents) FILTER (WHERE status = 'succeeded'), 0),
         coalesce(sum(amount_cents) FILTER (WHERE status IN ('failed','canceled')), 0)
    INTO v_req, v_ok, v_fail
    FROM public.payment_refund_state
   WHERE payment_id = v_pay.id;

  PERFORM set_config('app.refund_state_writer', 'on', true);
  UPDATE public.payments
     SET refund_requested_cents = v_req,
         refund_succeeded_cents = v_ok,
         refund_failed_cents    = v_fail
   WHERE id = v_pay.id;
  PERFORM set_config('app.refund_state_writer', 'off', true);

  RETURN jsonb_build_object(
    'recorded',        true,
    'payment_id',      v_pay.id,
    'refund_status',   p_status,
    'counted',         v_counted,
    'stale_ignored',   false,
    'requested_cents', v_req,
    'succeeded_cents', v_ok,
    'failed_cents',    v_fail
  );
END; $function$

;

-- 2. record_payment_refund (production md5 8ce828e3461f97844faa36450241dc8f)
CREATE OR REPLACE FUNCTION public.record_payment_refund(p_payment_intent_id text, p_stripe_refund_id text, p_stripe_dispute_id text, p_amount_cents integer, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_pay        public.payments%ROWTYPE;
  v_amount     int;
  v_sum        int;
  v_new_total  int;
  v_inserted   int := 0;
  v_paid       record;
BEGIN
  IF p_source IS NULL OR p_source NOT IN ('expiry','dispute_lost','dashboard','admin','unfulfillable') THEN
    RAISE EXCEPTION 'INVALID_REFUND_SOURCE' USING DETAIL = coalesce(p_source, '<null>');
  END IF;
  IF nullif(p_stripe_refund_id, '') IS NULL AND nullif(p_stripe_dispute_id, '') IS NULL THEN
    RAISE EXCEPTION 'REFUND_REFERENCE_REQUIRED';
  END IF;
  IF p_source = 'dispute_lost' AND nullif(p_stripe_dispute_id, '') IS NULL THEN
    RAISE EXCEPTION 'REFUND_REFERENCE_REQUIRED' USING DETAIL = 'dispute_lost needs a dispute id';
  END IF;

  SELECT * INTO v_pay FROM public.payments
   WHERE stripe_payment_intent_id = p_payment_intent_id
   FOR UPDATE;
  IF NOT FOUND THEN
    -- Unknown to us (test-mode / foreign charge): acknowledged, never retried.
    RETURN jsonb_build_object('payment_id', NULL, 'status', NULL, 'amount_refunded_cents', NULL,
                              'recorded', false, 'reason', 'unknown_payment');
  END IF;

  -- NULL amount = full refund of what the charge captured (Stripe's
  -- amount-less POST /refunds). Capped at total so a chargeback on an already
  -- refunded charge cannot push the fact past the money that existed.
  v_amount := least(coalesce(p_amount_cents, v_pay.total), v_pay.total);
  IF v_amount < 0 THEN
    RAISE EXCEPTION 'INVALID_REFUND_AMOUNT';
  END IF;

  IF nullif(p_stripe_refund_id, '') IS NOT NULL THEN
    INSERT INTO public.payment_refunds (payment_id, stripe_refund_id, stripe_dispute_id, amount_cents, source)
    VALUES (v_pay.id, p_stripe_refund_id, nullif(p_stripe_dispute_id, ''), v_amount, p_source)
    ON CONFLICT (stripe_refund_id) DO NOTHING;
  ELSE
    INSERT INTO public.payment_refunds (payment_id, stripe_refund_id, stripe_dispute_id, amount_cents, source)
    VALUES (v_pay.id, NULL, p_stripe_dispute_id, v_amount, p_source)
    ON CONFLICT (payment_id, stripe_dispute_id) WHERE stripe_dispute_id IS NOT NULL DO NOTHING;
  END IF;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  SELECT coalesce(sum(amount_cents), 0) INTO v_sum FROM public.payment_refunds WHERE payment_id = v_pay.id;
  v_new_total := least(greatest(coalesce(v_pay.amount_refunded_cents, 0), v_sum), v_pay.total);

  UPDATE public.payments
     SET amount_refunded_cents = v_new_total,
         -- a dispute is a chargeback, never a refund reference
         stripe_refund_id      = coalesce(stripe_refund_id, nullif(p_stripe_refund_id, '')),
         status                = CASE WHEN v_new_total >= total THEN 'refunded' ELSE status END,
         refunded_at           = CASE WHEN v_new_total >= total THEN coalesce(refunded_at, now()) ELSE refunded_at END
   WHERE id = v_pay.id
   RETURNING * INTO v_pay;

  -- Refund AFTER payout (review round 2, MAJOR-2): the seller already holds
  -- money that has just gone back to the buyer. Flag every paid transfer of
  -- this payment for reversal (manual_review decision; deletion blocker
  -- open_manual_review) — once per reason, idempotent. dispute_lost is
  -- excluded: the webhook's charge.dispute.closed branch flags that case as
  -- DISPUTE_LOST_AFTER_PAYOUT itself.
  IF v_inserted = 1 AND p_source <> 'dispute_lost' THEN
    FOR v_paid IN
      SELECT t.id FROM public.transfers t
       WHERE t.payment_id = v_pay.id
         AND (t.payout_released_at IS NOT NULL OR t.stripe_transfer_id IS NOT NULL)
    LOOP
      PERFORM public.flag_payout_reversal_required(
        v_paid.id,
        CASE WHEN v_new_total >= v_pay.total THEN 'REFUNDED_AFTER_PAYOUT' ELSE 'PARTIAL_REFUND_AFTER_PAYOUT' END,
        jsonb_build_object('source', p_source, 'stripe_refund_id', nullif(p_stripe_refund_id, ''),
                           'stripe_dispute_id', nullif(p_stripe_dispute_id, ''),
                           'refund_amount_cents', v_amount, 'amount_refunded_cents', v_new_total));
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'payment_id',            v_pay.id,
    'status',                v_pay.status,
    'amount_refunded_cents', v_pay.amount_refunded_cents,
    'total',                 v_pay.total,
    'recorded',              v_inserted = 1
  );
END; $function$

;

-- 3. the helper (175's own object; nothing else references it — checked above)
DROP FUNCTION IF EXISTS public.assert_refund_livemode(uuid, boolean);

-- ── verification (inside the transaction: a mismatch aborts the whole rollback) ─
DO $verify175$
DECLARE
  v_bad text;
BEGIN
  IF (SELECT count(*) FROM r175_pre) <> 2 THEN
    RAISE EXCEPTION '175 rollback verification failed (nothing changed): expected 2 captured writers' USING ERRCODE = 'P0001';
  END IF;
  SELECT string_agg(v.sig || ' md5 ' || coalesce(md5(pg_get_functiondef(p.oid)), '<missing>') || ' (production ' || v.prod_md5 || ')'
                    || ' acl ' || coalesce(r.acl, '<null>') || ' -> ' || coalesce(array_to_string(p.proacl, ','), '<null>')
                    || ' secdef=' || coalesce(p.prosecdef::text, '<missing>')
                    || ' config=' || coalesce(array_to_string(p.proconfig, ','), '<null>'), '; ')
    INTO v_bad
    FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)', '5e9f66129a4bb82b6b3e7a1b41e04365', true, 'search_path=""'),
                 ('public.record_payment_refund(text,text,text,integer,text)',          '8ce828e3461f97844faa36450241dc8f', true, 'search_path=public')) v(sig, prod_md5, secdef, config)
    JOIN r175_pre r ON r.sig = v.sig
    LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE md5(pg_get_functiondef(p.oid)) IS DISTINCT FROM v.prod_md5
      OR array_to_string(p.proacl, ',') IS DISTINCT FROM r.acl
      OR p.proowner IS DISTINCT FROM r.owner
      OR p.prosecdef IS DISTINCT FROM v.secdef
      OR array_to_string(p.proconfig, ',') IS DISTINCT FROM v.config;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 rollback verification failed (nothing changed): %', v_bad USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'assert_refund_livemode') THEN
    RAISE EXCEPTION '175 rollback verification failed (nothing changed): assert_refund_livemode still exists' USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '175 rollback verified: both writers = production md5s; grants, owner, definer and search_path unchanged; helper dropped';
END
$verify175$;

COMMIT;

-- Read-only re-check after COMMIT (expect three rows, ok = true):
SELECT v.sig, coalesce(md5(pg_get_functiondef(pg_catalog.to_regprocedure(v.sig))), 'absent') = v.want AS ok
  FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)', '5e9f66129a4bb82b6b3e7a1b41e04365'),
               ('public.record_payment_refund(text,text,text,integer,text)',          '8ce828e3461f97844faa36450241dc8f'),
               ('public.assert_refund_livemode(uuid,boolean)',                         'absent')) v(sig, want);
