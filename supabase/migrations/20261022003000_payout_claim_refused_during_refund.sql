-- ============================================================================
-- 20261022003000_payout_claim_refused_during_refund.sql — registry 179 (pgTAP 249). Stacked on 157
-- (20261021100000_ops_money_action_unsettled_guard.sql: the per-order advisory lock and the unsettled vocabulary this
-- file reuses); applied after 158 (20261021110000) and 177 (20261022001000) in the branch order, independent of both.
-- Owner decision (Jose, 2026-10-21): "Keep manual refunds, no automatic refund after released payout"; E's finding D2
-- (2026-10-21): the INVERSE direction. A sprint 2026-10-21. Server side only. Prepared and tested on the local
-- production replay only.
--
-- WHY. 177 refuses a console refund (refund_execute) once the order's seller payout is released or in flight. The other
--   direction stayed open (177 header, NOT COVERED, first item): a refund_execute already accepted and UNSETTLED
--   (parked awaiting approval; 'processing' at the ops-refund-execute edge; 'unknown' / 'succeeded_at_provider' until
--   the Stripe webhook lands) does not stop the payout side. The payout writers read payments.status and
--   amount_refunded_cents, which change only when the refund is RECORDED (record_payment_refund), so between the
--   refund's dispatch and its record the cron can auto-release the transfer, the buyer can confirm it, or
--   dispute_resolve seller_win can flip it, and the next sweep (enforce-transfer-expiry phase 2b), confirm-and-release
--   or the seller-win path through the sweep claims and pays the seller: the buyer is refunded AND the seller is paid
--   (REFUNDED_AFTER_PAYOUT, detected only afterwards by record_payment_refund; the reversal is manual).
--
-- WHAT. public.claim_payout_attempt(uuid, text, interval) is the single choke point before any Stripe transfer
--   (_shared/payouts.ts executePayoutAttempt step 1, used by the payout sweep, confirm-and-release and the seller-win
--   path). Its PRODUCTION body (md5 b6aae8680e1891892dd0d42f62b9531b, read on the replay template 2026-10-22; SECURITY DEFINER,
--   search_path public, ACL postgres + service_role) plus THREE marked blocks ('  -- 179 begin' / '  -- 179 end';
--   stripping them gives production byte for byte: verified below and pinned by pgTAP 249):
--   1. DECLARE: v_order (the transfer's payment id = 157's ORDER key), v_refund (the blocking action id).
--   2. BEFORE the transfer FOR UPDATE: read transfers.payment_id (no lock; no writer updates it) and take 157's order
--      advisory lock, pg_advisory_xact_lock(hashtextextended('ops_money_order:' || <payment id>, 0)) — the key
--      ops.execute_action and ops.approve_action take FIRST for every refund_execute / payout_release (157 lines
--      364 / 509; ops.money_order_id maps a payment subject to its own id, a transfer subject to transfers.payment_id;
--      the expression is replicated here because that helper is internal to ops and the claim's search_path is
--      public). A missing transfer takes no lock and gets TRANSFER_NOT_FOUND, as before.
--   3. AFTER every existing answer (TRANSFER_NOT_FOUND, the open-attempt reconcile, ALREADY_RELEASED, DISPUTED,
--      TRANSFER_NOT_RELEASABLE, PAYOUT_UNDER_REVIEW, PAYOUT_HELD, PAYMENT_NOT_SUCCEEDED, PAYMENT_NOT_LIVE,
--      PAYMENT_PARTIALLY_REFUNDED, SELLER_NOT_ONBOARDED, PAYOUT_AMOUNT_INVALID — each still answers first, byte for
--      byte) and BEFORE the INSERT that opens the attempt: re-take the order lock on the LOCKED row's payment id
--      (re-entrant; a no-op when it equals v_order), then read ops.action for an UNSETTLED refund_execute on that
--      payment — action_type 'refund_execute', subject_kind 'payment', subject_id = the payment id, state IN 157's
--      unsettled set ('requested','awaiting_approval','processing','unknown','succeeded_at_provider'; 157's partial
--      unique index action_money_unsettled_uidx covers exactly this predicate: at most one row). Found ->
--      RAISE EXCEPTION 'REFUND_IN_FLIGHT' USING DETAIL = <ops.action.id> (errcode P0001, the siblings' style:
--      PAYOUT_ATTEMPT_IN_PROGRESS carries the attempt id the same way). Nothing is written: no payout_attempts row,
--      the transfer and the action row are untouched.
--   NOT refused: no refund_execute on the payment; one in a TERMINAL state (succeeded, failed, rejected); a refund on
--   another payment; an unsettled payout_release (the same direction as the claim; 157 serializes those); and the
--   open-attempt RECONCILE path (needs_reconcile = true hands back an attempt that already exists and never opens a
--   new Stripe transfer; refusing it would strand the attempt — pinned by 249 R5 as a design decision).
--
-- LOCK ORDER (why block 2 sits BEFORE the transfer FOR UPDATE). 157: execute_action = order advisory lock ->
--   ops.action; approve_action = order advisory lock -> ops.action FOR UPDATE -> ops.approval FOR UPDATE -> action_run
--   -> action_dispatch: public.payments FOR UPDATE -> (177) public.transfers FOR UPDATE. Production's claim =
--   transfers FOR UPDATE -> payout_attempts INSERT (FOR KEY SHARE on the payment through the FK), i.e. transfers ->
--   payments: 177 found and reproduced the resulting cycle with the refund dispatch (177 header LOCK ORDER; its
--   rehearsal D8: 40P01 after deadlock_timeout, one victim). 179's claim = order advisory lock -> transfers FOR
--   UPDATE -> payments KEY SHARE. The two console paths and the claim now BEGIN with the SAME lock on the SAME key, so
--   a claim and a console money action on one order are serialized and cannot form a cycle: the D8 deadlock
--   disappears (rehearsal E3 re-runs 177's paused dispatch copy: the claim waits on the advisory lock, no 40P01).
--   Had the lock been taken AFTER the transfer FOR UPDATE (claim: transfers -> advisory; approval: advisory -> ... ->
--   transfers) every concurrent approval on the order would have deadlocked; pgTAP 249 pins the order statically
--   (R7). Taking the lock BEFORE the ops.action read means the read (a new statement, a new snapshot under READ
--   COMMITTED) sees every refund request committed before the lock was granted; a request that starts later waits on
--   the same lock until the claim commits, and 177 then refuses it (payout_attempt_claimed in its basis): rehearsal
--   E1 / E2. Unchanged and pre-existing: record_payment_refund -> flag_payout_reversal_required takes payments ->
--   transfers without the advisory lock, against the claim's transfers -> payments KEY SHARE (a cycle Postgres already
--   resolves; neither widened nor narrowed here). apply_auto_release (FOR UPDATE SKIP LOCKED) skips a transfer the
--   claim holds. Two-session proof: scripts/local/rehearsal_179_concurrency.sh (private-evidence a179).
--
-- CONTRACT FOR THE CALLERS (edge). The claim raises P0001 'REFUND_IN_FLIGHT', DETAIL = the blocking ops.action id.
--   _shared/payouts.ts executePayoutAttempt maps claim errors by substring (rpcReason over ALREADY_RELEASED,
--   PAYOUT_ATTEMPT_IN_PROGRESS and PAYOUT_NOT_ELIGIBLE_REASONS; identical on origin/release/production-gate-20260918
--   and this branch). REFUND_IN_FLIGHT is not in that list, so until the edge adds it the outcome is
--   {kind:'db_error', stage:'claim'}: enforce-transfer-expiry logs 'payout attempt DB error' (console.error; Sentry
--   only for stage 'record') and counts the row 'failed' for this run; confirm-and-release answers its db_error arm.
--   NO Stripe call is made either way; the next sweep retries, and once the refund settles the claim either proceeds
--   (failed / rejected) or production's PAYMENT_NOT_SUCCEEDED / PAYMENT_PARTIALLY_REFUNDED answers (succeeded, the
--   payment recorded refunded). RECOMMENDED edge follow-up (not in this file, no deploy needed for safety): add
--   'REFUND_IN_FLIGHT' to PAYOUT_NOT_ELIGIBLE_REASONS so it logs as 'payout not eligible' like DISPUTED.
--
-- NOT COVERED (by design or scope).
--   - A refund_execute requested AFTER the claim committed (the attempt is then open): 177 refuses it at request and
--     at approval (payout_attempt_claimed / requested / unknown in its basis) — the other half of the closure.
--   - A refund recorded outside the console (Stripe Dashboard -> record_payment_refund): production's answers.
--   - mark_payout_requested / record_payout_attempt_result / reconcile_payout_attempt: untouched.
--   - A refund_execute stuck in processing / unknown blocks the order's payout until an operator settles it (157
--     already documents the same for new money requests).
--
-- IMPACT (aggregate counts only, local replay of the 2026-10-15 snapshot): ops.action holds no refund_execute row and
--   payout_attempts holds 0 rows: no existing order changes outcome at apply time.
--
-- ROLLOUT (each step an owner decision).
--   1. Read-only pre-checks in production: md5(pg_get_functiondef('public.claim_payout_attempt(uuid,text,interval)'::regprocedure))
--      = b6aae8680e1891892dd0d42f62b9531b; ops.money_order_id(text,uuid) present (157 applied).
--   2. Apply this file (one transaction; lock_timeout 3s; CREATE OR REPLACE rewrites one pg_proc row, no user table is
--      locked). A claim already running finishes with the body it started with.
--   3. Edge: nothing to deploy for safety (the refusal makes no Stripe call); the follow-up above only changes a log line.
-- ROLLBACK: supabase/rollbacks/20261022003000_payout_claim_refused_during_refund_rollback.sql restores production's
--   body VERBATIM (md5 b6aae8680e1891892dd0d42f62b9531b), re-states the ACL, drops the comment and verifies md5 + ACL +
--   SECURITY DEFINER + search_path inside the transaction (a mismatch changes nothing). Stacking guard: refuses when
--   the live body is neither 179's nor production's. Independent of 177's rollback (different objects); roll back 179
--   before 157 only because this file's pre-flight needs 157's helper (the rollback itself does not).
-- CI (four-file rule): no change. CREATE OR REPLACE of an existing public function: the Gate-2 census counts public
--   functions by number (.github/workflows/ci.yml:605-608) — unchanged; the grant diff compares TABLE grants in public
--   (:726-733 against supabase/ci/expected_grants.txt) — untouched; supabase/ci/assert_public_table_grant_decisions.sql
--   :386 already carries claim_payout_attempt's row ('no-client-execute', unchanged: the ACL is re-stated identically
--   and verified unchanged below); pgTAP 249 is picked up by glob (ci.yml:795-802).
-- 179's md5 (the applied state, pg_get_functiondef of the body below): e2ba30303f77137f589bb4fd37778cb1.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. pre-flight (read-only): claim_payout_attempt = production, one overload, 157 present ─
DO $pre179$
DECLARE
  v_md5 text := md5(pg_get_functiondef(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)')));
  v_n   int  := (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'claim_payout_attempt');
  v_acl text := (SELECT coalesce(array_to_string(proacl, ','), '<default>') FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
BEGIN
  IF v_md5 = 'e2ba30303f77137f589bb4fd37778cb1' THEN
    RAISE EXCEPTION '179 pre-flight refused: public.claim_payout_attempt(uuid,text,interval) already carries 179''s body (md5 %). Nothing changed.', v_md5;
  END IF;
  IF v_md5 IS DISTINCT FROM 'b6aae8680e1891892dd0d42f62b9531b' OR v_n <> 1 THEN
    RAISE EXCEPTION '179 pre-flight refused: public.claim_payout_attempt(uuid,text,interval) md5 % (expected production''s b6aae8680e1891892dd0d42f62b9531b), % overload(s) (expected 1): another body sits there, review it first. Nothing changed.',
      coalesce(v_md5, '<missing>'), v_n;
  END IF;
  IF to_regprocedure('ops.money_order_id(text,uuid)') IS NULL THEN
    RAISE EXCEPTION '179 pre-flight refused: ops.money_order_id(text,uuid) is absent, so 157 (20261021100000) is not applied; this file reuses 157''s order lock. Nothing changed.';
  END IF;
  PERFORM set_config('a179.pre_acl', v_acl, true);   -- compared after the CREATE OR REPLACE: the ACL must not change
  RAISE NOTICE '179 pre-flight: claim_payout_attempt = production (b6aae8680e1891892dd0d42f62b9531b), one overload, 157 present, acl %', v_acl;
END $pre179$;

-- ── 2. public.claim_payout_attempt: production's body + the three marked 179 blocks ─
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
  -- 179 begin
  v_order  uuid;   -- 157's ORDER key: the transfer's payment id, read before the transfer lock (header: LOCK ORDER)
  v_refund uuid;   -- the UNSETTLED console refund_execute on that payment, if any (REFUND_IN_FLIGHT's DETAIL)
  -- 179 end
BEGIN
  IF v_lease <= interval '0' OR v_lease > interval '1 hour' THEN
    v_lease := interval '10 minutes';
  END IF;

  -- 179 begin
  -- 179: 157's per-order advisory lock FIRST (the key ops.execute_action / ops.approve_action take before any
  -- refund_execute / payout_release on this order), BEFORE the transfer FOR UPDATE so a claim and a console money
  -- action on one order serialize instead of forming a lock cycle (header: LOCK ORDER). transfers.payment_id has no
  -- writer; a missing transfer takes no lock and gets TRANSFER_NOT_FOUND below, as before.
  SELECT t.payment_id INTO v_order FROM public.transfers t WHERE t.id = p_transfer_id;
  IF v_order IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('ops_money_order:' || v_order::text, 0));
  END IF;
  -- 179 end
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

  -- 179 begin
  -- 179 (E's D2; owner decision 2026-10-21, the inverse of 177): never open a payout attempt while the console is
  -- refunding this payment. An UNSETTLED refund_execute (157's set) on the transfer's payment refuses the claim; a
  -- settled one (succeeded / failed / rejected) or a refund on another payment does not. Read after every existing
  -- answer, under the transfer FOR UPDATE and the order lock, re-taken here on the LOCKED row's payment id
  -- (re-entrant: a no-op when it equals v_order).
  PERFORM pg_advisory_xact_lock(hashtextextended('ops_money_order:' || v_t.payment_id::text, 0));
  SELECT a.id INTO v_refund FROM ops.action a
   WHERE a.action_type = 'refund_execute' AND a.subject_kind = 'payment' AND a.subject_id = v_t.payment_id
     AND a.state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')
   ORDER BY a.requested_at, a.id LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'REFUND_IN_FLIGHT' USING DETAIL = v_refund::text;
  END IF;
  -- 179 end
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

-- the production ACL, re-stated (a no-op where it already holds; verified unchanged below)
REVOKE ALL ON FUNCTION public.claim_payout_attempt(uuid,text,interval) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_payout_attempt(uuid,text,interval) TO service_role;
COMMENT ON FUNCTION public.claim_payout_attempt(uuid,text,interval) IS
  '179 (20261022003000): production''s claim (the single choke point before any Stripe transfer) + REFUND_IN_FLIGHT: refuses while an '
  'UNSETTLED console refund_execute (157''s set) exists for the transfer''s payment, read under 157''s per-order advisory lock (taken '
  'before the transfer FOR UPDATE) and the transfer lock. P0001, DETAIL = the blocking ops.action id. service_role only.';

-- ── 3. verification (inside the transaction: a mismatch aborts the apply) ──
DO $verify179$
DECLARE
  d      text := pg_get_functiondef(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_md5  text := md5(d);
  v_strp text := md5(regexp_replace(d, '  -- 179 begin\n.*?  -- 179 end\n', '', 'g'));
  v_acl  text := (SELECT coalesce(array_to_string(proacl, ','), '<default>') FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_pre  text := current_setting('a179.pre_acl', true);
  v_sec  boolean := (SELECT prosecdef FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_cfg  text := (SELECT array_to_string(proconfig, ',') FROM pg_proc WHERE oid = to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'));
  v_n    int  := (SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'claim_payout_attempt');
  v_bad  text := '';
BEGIN
  IF v_md5 <> 'e2ba30303f77137f589bb4fd37778cb1' THEN v_bad := v_bad || format('md5 %s <> 179''s e2ba30303f77137f589bb4fd37778cb1; ', v_md5); END IF;
  IF v_strp <> 'b6aae8680e1891892dd0d42f62b9531b' THEN v_bad := v_bad || format('body minus the 179 blocks md5 %s <> production''s b6aae8680e1891892dd0d42f62b9531b; ', v_strp); END IF;
  IF v_acl IS DISTINCT FROM v_pre THEN v_bad := v_bad || format('acl %s <> before %s; ', v_acl, v_pre); END IF;
  IF v_acl <> 'postgres=X/postgres,service_role=X/postgres' THEN v_bad := v_bad || format('acl %s <> postgres + service_role; ', v_acl); END IF;
  IF has_function_privilege('anon', to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'EXECUTE')
     OR has_function_privilege('authenticated', to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'EXECUTE')
     OR NOT has_function_privilege('service_role', to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'), 'EXECUTE') THEN
    v_bad := v_bad || 'execute privilege: anon / authenticated must not, service_role must; ';
  END IF;
  IF NOT v_sec THEN v_bad := v_bad || 'not SECURITY DEFINER; '; END IF;
  IF v_cfg IS DISTINCT FROM 'search_path=public' THEN v_bad := v_bad || format('proconfig %s <> search_path=public; ', coalesce(v_cfg, '<none>')); END IF;
  IF v_n <> 1 THEN v_bad := v_bad || format('%s overloads; ', v_n); END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION '179 verification failed (nothing changed): %', v_bad USING ERRCODE = 'P0001';
  END IF;
  RAISE NOTICE '179 verified: claim_payout_attempt md5 e2ba30303f77137f589bb4fd37778cb1, minus the 179 blocks = production (b6aae8680e1891892dd0d42f62b9531b), acl unchanged (%), definer, search_path public', v_acl;
END $verify179$;
COMMIT;

-- Read-only re-check after COMMIT (expect ok = true):
SELECT md5(pg_get_functiondef(to_regprocedure('public.claim_payout_attempt(uuid,text,interval)'))) = 'e2ba30303f77137f589bb4fd37778cb1' AS ok;
