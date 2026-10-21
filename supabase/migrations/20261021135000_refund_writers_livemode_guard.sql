-- ============================================================================
-- 20261021135000_refund_writers_livemode_guard.sql — registry 175 (pgTAP 245).
-- DRAFT, APPLIED NOWHERE; owner-gated (refunds are a stop-and-ask path: CLAUDE.md). Prepared and tested on local
-- production-replay clones only. Applying it is a separate owner approval; the owner also decides whether the
-- 2026-10-28 03:47:04Z hold on listing/bid paths (STATUS.md item 88) covers it — 175 touches no listing or bid code,
-- but a recorded refund can flag a paid transfer for reversal.
--
-- WHY (backlog BE-22, F-MODE-BOUNDARY-DUPLICATED-1, P3). The live/test money boundary (045) is enforced by the
--   payout claim and by settle_verified_payment, but the two SQL refund writers have NO stripe_livemode check:
--   public.record_refund_state and public.record_payment_refund record a refund fact on a payment row of any mode.
--   REPRODUCED on a production-replay clone before this file was written
--   (private-evidence/A-sprint-20261021/a175/01_red.out, production bodies, switch unset): a refund on a
--   stripe_livemode = false row and on a NULL row was recorded by each writer (state row, log row, ledger row,
--   amount_refunded_cents), and settle_verified_payment's full-refund branch recorded one on a NULL row.
--
-- THE RULES AS THEY ARE TODAY (00_rules.txt; production bodies, md5(pg_get_functiondef) = prod_functions.json):
--   settle_verified_payment (bc16180caaa338b871711bdd845f01db), line 68: a BINDING cross-check of the row against
--     the caller's p_livemode (Stripe's PaymentIntent.livemode):
--       mismatch iff row.stripe_livemode IS NOT NULL AND row.stripe_livemode IS DISTINCT FROM p_livemode
--     -> outcome 'binding_mismatch' + a webhook_retries review row, no raise. A NULL row passes; a NULL p_livemode
--     against a non-NULL row is a mismatch. It reads NO server setting (neither app.allow_test_mode_money nor
--     anything else), so "the server's mode setting used by settle_verified_payment" does not exist.
--   claim_payout_attempt (b6aae8680e1891892dd0d42f62b9531b), lines 84-87: the 045 MODE BOUNDARY, the only SQL
--     refusal keyed on a server setting:
--       refuse iff stripe_livemode IS DISTINCT FROM true
--               AND NOT (stripe_livemode IS NOT DISTINCT FROM false
--                        AND coalesce(current_setting('app.allow_test_mode_money', true), 'off') = 'on')
--     -> RAISE 'PAYMENT_NOT_LIVE'. Its edge twin is _shared/payout-logic.ts rowIsLiveActionable (ALLOW_TEST_MODE_MONEY):
--     "only rows explicitly marked live may enter refund/payout/reconciliation paths … null = unclassified and
--     therefore NOT actionable (fail closed)". The sandbox sets the DB switch per API request through
--     pgrst.db_pre_request; production sets neither (docs/security/PAYMENTS_RELIABILITY_2026-09/15_SANDBOX_RESULTS.md §1).
--
-- CALLERS (enumerated; none passes a livemode value, so the SIGNATURES ARE NOT CHANGED — a new parameter would break
--   the deployed edges' named-argument RPC calls):
--   edge (origin/release/production-gate-20260918 @ 6f982f36):
--     stripe-webhook/index.ts:779 (charge.refunded) and :984 (refund.created/updated/failed) -> record_refund_state
--       (pi, refund id, Stripe's status, amount, failure_reason, source from metadata, 'webhook'); :692
--       (charge.dispute.closed, lost) -> record_payment_refund(pi, NULL, dispute id, amount, 'dispute_lost'). Event
--       livemode is never read; every RPC error answers 500 and Stripe redelivers.
--     enforce-transfer-expiry/index.ts:154 recordRefundState -> record_refund_state (create_response | reconcile), from
--       Phase 0 (rows of get_unsettled_payments: NULL rows skipped as legacy_unknown_mode, false rows listed only under
--       the DB switch), Phase 1 (gated by rowIsLiveActionable, :618) and Phase 1b (live rows, false rows only under
--       ALLOW_TEST_MODE_MONEY, :797-799).
--     ops-refund-execute: calls neither writer (ops.executor_claim / ops.record_action_outcome); its own mode check
--       (classify.ts checkModeConsistency) refuses NULL and key-mismatched rows; the refund it creates is recorded by
--       the webhook. confirm-payment calls only settle_verified_payment.
--   SQL (pg_proc prosrc scan on the replay): record_refund_state -> record_payment_refund (counted statuses);
--     settle_verified_payment -> record_payment_refund (full-refund branch, dynamic EXECUTE). No other routine.
--
-- THE RULE APPLIED (derived from the locked payment row, as the task specifies when no livemode argument exists):
--   the 045 predicate of claim_payout_attempt, VERBATIM, in one shared helper public.assert_refund_livemode:
--   admitted iff stripe_livemode = true, or = false while app.allow_test_mode_money = 'on' (sandbox only); NULL is
--   never admitted. Why this one and not a symmetric "row = server mode": with this predicate the set of rows whose
--   refund the writers refuse is EXACTLY the set the payout claim refuses, so an unrecorded refund can never sit on
--   a row that can still be paid out. (A symmetric rule would refuse a live row's refund in a sandbox while
--   claim_payout_attempt still pays it.) This deliberately differs from settle's binding check on NULL rows (settle
--   admits them); see BEHAVIOUR CHANGE.
--
-- WHAT. Every body below is the PRODUCTION pg_get_functiondef text (read from a_sprint_prod_template, fingerprint-
--   identical to production 2026-10-21; prod_functions.json md5s) with only the lines named here added.
--   1. NEW public.assert_refund_livemode(p_payment_id uuid, p_stripe_livemode boolean) RETURNS void — plpgsql,
--      STABLE, SECURITY INVOKER, search_path ''. RAISE EXCEPTION 'LIVEMODE_MISMATCH' (SQLSTATE P0001, the writers'
--      existing style: message = the code) USING DETAIL = 'payment <id> stripe_livemode=<true|false|null>
--      app.allow_test_mode_money=<value|unset>', HINT = 'LIVEMODE_MISMATCH'. REVOKE ALL FROM PUBLIC, anon,
--      authenticated (no client EXECUTE; the writers are SECURITY DEFINER and call it as their owner).
--   2. public.record_refund_state(text,text,text,integer,text,text,text) (production md5 5e9f66129a4bb82b6b3e7a1b41e04365)
--   3. public.record_payment_refund(text,text,text,integer,text)          (production md5 8ce828e3461f97844faa36450241dc8f)
--      Each gains ONE statement, right after its `IF NOT FOUND THEN … 'unknown_payment' … END IF;` on the row it
--      has just locked FOR UPDATE, before any other read or write:
--        PERFORM public.assert_refund_livemode(v_pay.id, v_pay.stripe_livemode);
--      So: every existing input refusal still runs first and is byte-identical (REFUND_REFERENCE_REQUIRED,
--      INVALID_REFUND_STATUS / _OBSERVATION_SOURCE / _SOURCE / _AMOUNT); an unknown payment is still acknowledged
--      (recorded false, reason unknown_payment, never retried); REFUND_PAYMENT_MISMATCH and the stale-observation
--      answer are unchanged on admitted rows; a refused call writes nothing. Signatures, return types, owners,
--      SECURITY DEFINER, search_path, grants and COMMENTs are untouched (CREATE OR REPLACE; the post-check verifies).
--   settle_verified_payment is NOT redefined.
--
-- BEHAVIOUR CHANGE (the whole of it):
--   * production (switch unset): a refund fact for a stripe_livemode false or NULL row now RAISEs LIVEMODE_MISMATCH.
--     Production holds 49 false rows, 8 true, 0 NULL; every recorded refund (2 ledger rows, 2 state rows) is on a
--     live row (replay counts, aggregates only). The live webhook endpoint only receives live events, whose
--     PaymentIntents are live rows, so no reachable production path changes; a cross-mode event would now answer
--     500 (Sentry + fail_stripe_webhook_event, Stripe retries) instead of mutating a test-era audit row.
--   * settle_verified_payment's full-refund branch on a NULL row (or a false row without the switch) now raises
--     from inside record_payment_refund and the whole settle call rolls back. No caller reaches it: the sweep never
--     fetches NULL rows, the webhook passes amount_refunded 0, confirm-payment cannot fetch a non-live
--     PaymentIntent with the live key.
--   * sandbox: unchanged while the per-request switch is on (as provisioned). If the edge ALLOW_TEST_MODE_MONEY and
--     the DB switch ever disagree, an expiry refund issued at Stripe for a test row is not recorded (loud: Sentry,
--     error count; the payout claim refuses the same row, so no payout follows) — keep the two switches together.
--
-- CI (four-file rule; exactly what CI checks):
--   supabase/ci/assert_public_table_grant_decisions.sql — +1 function row 'assert_refund_livemode(uuid, boolean)'
--     'no-client-execute' (every public function needs a decision; the check is anon/authenticated/PUBLIC EXECUTE).
--   .github/workflows/ci.yml Gate-2 census — EXPECT_FUNCS 126 -> 127 (+1 public function); tables, policies and
--     triggers unchanged. Read from an actual chain clone + 175.
--   supabase/tests/162_payout_reversal_and_obligation_recovery.sql P2 pin — 126 -> 127, same reason.
--   supabase/ci/expected_grants.txt — NO change: it is the TABLE-grant matrix only (ci.yml query on
--     information_schema.role_table_grants); 175 changes no table grant.
--   Fixture-only changes where a suite recorded refunds on non-live rows: 123 (seed payments A/B carry
--   stripe_livemode NULL -> set live before its record_payment_refund section) and 193 (its writer fixtures were
--   test-mode -> live; its pure legacy row stays test-mode). Every other suite that reaches the writers or
--   settle_verified_payment (121, 122, 124, 125, 214, 217; 162 apart from the P2 pin) passes unchanged with and
--   without 175 on a chain clone (private-evidence/A-sprint-20261021/a175/04_regress_r2.summary).
-- ROLLBACK: supabase/rollbacks/20261021135000_refund_writers_livemode_guard_rollback.sql restores both production
--   bodies VERBATIM, drops the helper, and verifies md5(pg_get_functiondef) + grants + definer + search_path = production
--   inside its transaction (a partial or stacked rollback raises and changes nothing).
-- VERIFY (read-only; expected after apply, PostgreSQL 17):
--   select p.oid::regprocedure, md5(pg_get_functiondef(p.oid)), array_to_string(p.proacl, ',') from pg_proc p
--    where p.pronamespace = 'public'::regnamespace
--      and p.proname in ('record_refund_state','record_payment_refund','assert_refund_livemode');
--   -- record_refund_state(text,text,text,integer,text,text,text)  24954bb9953ac0249dac6ee7aa93d6cd  (production 5e9f66129a4bb82b6b3e7a1b41e04365)
--   -- record_payment_refund(text,text,text,integer,text)           aadd3cca365aae33b1903daaf9ff67d7  (production 8ce828e3461f97844faa36450241dc8f)
--   -- assert_refund_livemode(uuid,boolean)                         c082eb3832fe435e7d10558bdc4bbc3c  postgres=X/postgres,service_role=X/postgres
-- FAILURE BEHAVIOUR: one transaction. The client_encoding guard, the pre-flight (live bodies must be production's by
--   md5(prosrc); no assert_refund_livemode may exist), a lock timeout, the post-check or any error leaves the database
--   exactly as it was.
-- OWNER APPROVAL POINT: applying this file is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 0. guards (read-only) ───────────────────────────────────────────────────
DO $enc175$
BEGIN
  -- record_payment_refund's production body contains an em dash (U+2014): byte-identity needs a UTF8 client.
  IF current_setting('client_encoding') <> 'UTF8' THEN
    RAISE EXCEPTION '175 refused: client_encoding is %, UTF8 required. Nothing changed.', current_setting('client_encoding')
      USING ERRCODE = 'P0001';
  END IF;
END
$enc175$;

DO $pre175$
DECLARE
  v_bad text;
  v_false int; v_null int; v_on_false int; v_on_null int;
BEGIN
  -- the live bodies must be the production bodies this file was derived from (md5 of the stored source)
  SELECT string_agg(v.sig || ' prosrc md5 ' || coalesce(md5(p.prosrc), '<missing>') || ' <> ' || v.prosrc_md5, '; ')
    INTO v_bad
    FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)', 'aff01ec2414fb8800c40ef05c8db05c8'),
                 ('public.record_payment_refund(text,text,text,integer,text)',          '08924da572763345c38f8fe5263b5431')) v(sig, prosrc_md5)
    LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE md5(p.prosrc) IS DISTINCT FROM v.prosrc_md5;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 pre-flight refused: a writer differs from the production body this file was derived from: %. Rebase 175 on the live body. Nothing changed.', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
              WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'assert_refund_livemode') THEN
    RAISE EXCEPTION '175 pre-flight refused: public.assert_refund_livemode already exists. Nothing changed.'
      USING ERRCODE = 'P0001';
  END IF;
  -- informational only (175 changes no stored row): payments whose refunds 175 would refuse here, and refund facts
  -- already recorded on such rows (counts only)
  SELECT count(*) FILTER (WHERE p.stripe_livemode IS NOT DISTINCT FROM false)::int,
         count(*) FILTER (WHERE p.stripe_livemode IS NULL)::int,
         count(*) FILTER (WHERE p.stripe_livemode IS NOT DISTINCT FROM false
                            AND (EXISTS (SELECT 1 FROM public.payment_refunds r WHERE r.payment_id = p.id)
                                 OR EXISTS (SELECT 1 FROM public.payment_refund_state s WHERE s.payment_id = p.id)))::int,
         count(*) FILTER (WHERE p.stripe_livemode IS NULL
                            AND (EXISTS (SELECT 1 FROM public.payment_refunds r WHERE r.payment_id = p.id)
                                 OR EXISTS (SELECT 1 FROM public.payment_refund_state s WHERE s.payment_id = p.id)))::int
    INTO v_false, v_null, v_on_false, v_on_null
    FROM public.payments p;
  RAISE NOTICE '175 pre-flight: bodies = production. payments stripe_livemode false: % (refund facts on them: %), NULL: % (refund facts on them: %); app.allow_test_mode_money=% (counts only; no row is changed)',
    v_false, v_on_false, v_null, v_on_null, coalesce(nullif(current_setting('app.allow_test_mode_money', true), ''), 'unset');
END
$pre175$;

-- Capture each writer's (and settle_verified_payment's) grants, owner, definer flag, search_path and comment BEFORE
-- the replacement, so the post-check proves this file changed none of them in WHATEVER environment it runs in
-- (production, a replay, CI's chain).
CREATE TEMP TABLE m175_pre ON COMMIT DROP AS
SELECT v.sig, array_to_string(p.proacl, ',') AS acl, p.prosecdef AS secdef, array_to_string(p.proconfig, ',') AS config,
       p.proowner AS owner, obj_description(p.oid, 'pg_proc') AS cmt, md5(pg_get_functiondef(p.oid)) AS def_md5
  FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)'),
               ('public.record_payment_refund(text,text,text,integer,text)'),
               ('public.settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)')) v(sig)
  JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig);

-- ── 1. the shared helper ─────────────────────────────────────────────────────
CREATE FUNCTION public.assert_refund_livemode(p_payment_id uuid, p_stripe_livemode boolean)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
BEGIN
  -- 175 (BE-22): the live/test money boundary for the SQL refund writers. The 045 predicate of
  -- public.claim_payout_attempt, verbatim: a row is admitted iff stripe_livemode = true, or = false while the
  -- sandbox-only switch app.allow_test_mode_money is exactly 'on' (never set in production). NULL (unclassified)
  -- is never admitted. Same predicate => the refund-record refusal set equals the payout refusal set.
  IF p_stripe_livemode IS DISTINCT FROM true
     AND NOT (p_stripe_livemode IS NOT DISTINCT FROM false
              AND coalesce(pg_catalog.current_setting('app.allow_test_mode_money', true), 'off') = 'on') THEN
    RAISE EXCEPTION 'LIVEMODE_MISMATCH'
      USING DETAIL = 'payment ' || coalesce(p_payment_id::text, '<null>')
                     || ' stripe_livemode=' || coalesce(p_stripe_livemode::text, 'null')
                     || ' app.allow_test_mode_money='
                     || coalesce(nullif(pg_catalog.current_setting('app.allow_test_mode_money', true), ''), 'unset'),
            HINT = 'LIVEMODE_MISMATCH';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.assert_refund_livemode(uuid, boolean) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.assert_refund_livemode(uuid, boolean) IS
  '175 (BE-22): raises LIVEMODE_MISMATCH (P0001, HINT LIVEMODE_MISMATCH) unless stripe_livemode = true, or = false under app.allow_test_mode_money = on (the 045 predicate of claim_payout_attempt). Called by record_refund_state and record_payment_refund on the locked payment row. No client EXECUTE.';

-- ── 2. record_refund_state: production body + the mode check ────────────────
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

  -- 175 (BE-22): the live/test money boundary on the row just locked, before any other read or write. The 045
  -- predicate of claim_payout_attempt (shared helper): live rows always; test-mode rows only under the sandbox
  -- switch app.allow_test_mode_money = 'on'; NULL never. Refuses with LIVEMODE_MISMATCH (HINT LIVEMODE_MISMATCH).
  PERFORM public.assert_refund_livemode(v_pay.id, v_pay.stripe_livemode);

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

-- ── 3. record_payment_refund: production body + the mode check ──────────────
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

  -- 175 (BE-22): the live/test money boundary on the row just locked, before any other read or write. The 045
  -- predicate of claim_payout_attempt (shared helper): live rows always; test-mode rows only under the sandbox
  -- switch app.allow_test_mode_money = 'on'; NULL never. Refuses with LIVEMODE_MISMATCH (HINT LIVEMODE_MISMATCH).
  PERFORM public.assert_refund_livemode(v_pay.id, v_pay.stripe_livemode);

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

-- ── 4. post-check (inside the transaction: a mismatch aborts everything) ────
DO $post175$
DECLARE
  v_bad text;
  v_h oid := pg_catalog.to_regprocedure('public.assert_refund_livemode(uuid,boolean)');
BEGIN
  IF (SELECT count(*) FROM m175_pre) <> 3 THEN
    RAISE EXCEPTION '175 post-check failed (nothing changed): expected 3 captured routines' USING ERRCODE = 'P0001';
  END IF;
  SELECT string_agg(v.sig || ' acl ' || coalesce(v.acl, '<null>') || ' -> ' || coalesce(array_to_string(p.proacl, ','), '<null>')
                    || ' secdef ' || coalesce(v.secdef::text, '<null>') || ' -> ' || coalesce(p.prosecdef::text, '<missing>')
                    || ' config ' || coalesce(v.config, '<null>') || ' -> ' || coalesce(array_to_string(p.proconfig, ','), '<null>'), '; ')
    INTO v_bad
    FROM m175_pre v
    LEFT JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE array_to_string(p.proacl, ',') IS DISTINCT FROM v.acl
      OR p.prosecdef IS DISTINCT FROM v.secdef
      OR array_to_string(p.proconfig, ',') IS DISTINCT FROM v.config
      OR p.proowner IS DISTINCT FROM v.owner
      OR obj_description(p.oid, 'pg_proc') IS DISTINCT FROM v.cmt;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 post-check failed (nothing changed): grant, owner, definer, search_path or comment of a writer changed: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
  -- each writer calls the helper exactly once, on the locked row
  SELECT string_agg(v.sig, '; ') INTO v_bad
    FROM (VALUES ('public.record_refund_state(text,text,text,integer,text,text,text)'),
                 ('public.record_payment_refund(text,text,text,integer,text)')) v(sig)
    JOIN pg_catalog.pg_proc p ON p.oid = pg_catalog.to_regprocedure(v.sig)
   WHERE (length(p.prosrc) - length(replace(p.prosrc, 'PERFORM public.assert_refund_livemode(v_pay.id, v_pay.stripe_livemode);', '')))
         <> length('PERFORM public.assert_refund_livemode(v_pay.id, v_pay.stripe_livemode);');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '175 post-check failed (nothing changed): writer does not call the helper exactly once: %', v_bad USING ERRCODE = 'P0001';
  END IF;
  -- the helper: no client EXECUTE (anon, authenticated, PUBLIC), ACL not defaulted, invoker, search_path ''
  IF v_h IS NULL
     OR (SELECT p.proacl IS NULL OR p.prosecdef OR p.proconfig IS DISTINCT FROM ARRAY['search_path=""']
           FROM pg_catalog.pg_proc p WHERE p.oid = v_h)
     OR has_function_privilege('anon', v_h, 'EXECUTE')
     OR has_function_privilege('authenticated', v_h, 'EXECUTE')
     OR EXISTS (SELECT 1 FROM pg_catalog.pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_h AND a.grantee = 0) THEN
    RAISE EXCEPTION '175 post-check failed (nothing changed): assert_refund_livemode is missing, client-executable, definer or has the wrong search_path'
      USING ERRCODE = 'P0001';
  END IF;
  -- settle_verified_payment (which reaches record_payment_refund) is not touched
  IF (SELECT md5(pg_get_functiondef(p.oid)) FROM pg_catalog.pg_proc p
       WHERE p.oid = 'public.settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)'::regprocedure)
       IS DISTINCT FROM (SELECT v.def_md5 FROM m175_pre v WHERE v.sig LIKE 'public.settle_verified_payment(%') THEN
    RAISE EXCEPTION '175 post-check failed (nothing changed): settle_verified_payment changed' USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '175 applied: helper created (no client EXECUTE); 2 writer bodies replaced; their grants, owner, definer, search_path and comments unchanged; settle_verified_payment untouched';
END
$post175$;

COMMIT;
