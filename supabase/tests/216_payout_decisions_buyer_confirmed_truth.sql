-- ============================================================================
-- 216_payout_decisions_buyer_confirmed_truth.sql — F-CR-148-SHARED follow-up,
-- writers a3/a4 (migration 20260924120000, registry 149).
--
-- payout_decisions.buyer_confirmed states that the BUYER confirmed receipt.
-- The only record of that act is transfers.buyer_confirmed_at, written by
-- confirm_transfer_received (0550:204). Two SQL writers instead derived the
-- flag from transfers.status = 'buyer_confirmed', which a seller-win dispute
-- resolution (065) also sets while leaving buyer_confirmed_at NULL:
--   a3  record_payout_attempt_result — reversal_required decisions
--       (DUPLICATE_TRANSFER; PAID_DURING_DISPUTE)
--   a4  flag_payout_reversal_required — a chargeback lost after payout
-- After the fix both read buyer_confirmed_at. Every state below is reached
-- through the real functions: confirm_transfer_received (as the buyer),
-- buyer_dispute_transfer + resolve_transfer_dispute (seller-win),
-- apply_auto_release, freeze_transfer_for_dispute, claim_payout_attempt,
-- record_payout_attempt_result and flag_payout_reversal_required.
-- DUPLICATE_TRANSFER is a CONTRACT TEST OF A DEFENSIVE BRANCH, not a reproduction
-- of a production-reachable state: it uses record_transfer_payout, which has no
-- live caller in deployed edge code (service_role only). In deployed code the
-- state needs the in-flight race that the attempt protocol (ALREADY_RELEASED,
-- reconcile) exists to prevent; DUPLICATE_TRANSFER is its last-resort detector.
-- Every writer of status 'buyer_confirmed' (002, 0550: with buyer_confirmed_at;
-- 065: seller-win, without) means a status-only row is a seller-win or a direct
-- write, so recording false there is exact, not conservative.
-- The edge writers a1/a2 (confirm-and-release) are covered by vitest
-- tests/payout-decisions-buyer-confirmed.test.ts.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(26);
SELECT tap.seed_core();
SELECT tap.logout();
UPDATE public.profiles SET stripe_connect_id = 'acct_A' WHERE id = tap.seller();

-- ── fixture helpers (transaction-local) ─────────────────────────────────────
-- One seller_sent transfer per case, on its own listing and live payment.
CREATE FUNCTION pg_temp.mk(p_n int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_l uuid := ('dddddddd-0000-0000-0216-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p uuid := ('eeeeeeee-0000-0000-0216-' || lpad(p_n::text, 12, '0'))::uuid;
  v_t uuid := ('ffffffff-0000-0000-0216-' || lpad(p_n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
     transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
     current_bid, cover_image_path, auction_status)
  VALUES (v_l, tap.seller(), 'BC Event ' || p_n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
          'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/bc.jpg', 'active');
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id,
     status, mode, paid_at, stripe_livemode)
  VALUES (v_p, v_l, tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_bc_' || p_n,
          'succeeded', 'buy_now', now(), true);
  INSERT INTO public.transfers
    (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at,
     auto_release_at, transfer_evidence_path, expires_at)
  VALUES (v_t, v_l, v_p, tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now() - interval '4 days',
          now() - interval '1 day', 'fixtures/evidence-bc.jpg', now() + interval '24 hours');
  RETURN v_t;
END $$;

-- genuine: the buyer confirms receipt through the real RPC, as the buyer
CREATE FUNCTION pg_temp.genuine(p_n int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_t uuid := pg_temp.mk(p_n);
BEGIN
  PERFORM tap.login(tap.buyer());
  PERFORM public.confirm_transfer_received(v_t, tap.buyer());
  PERFORM tap.logout();
  RETURN v_t;
END $$;

-- seller-win: the buyer disputes, the operator resolves in the seller's favour
CREATE FUNCTION pg_temp.seller_win(p_n int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_t uuid := pg_temp.mk(p_n);
BEGIN
  PERFORM tap.login(tap.buyer());
  PERFORM public.buyer_dispute_transfer(v_t);
  PERFORM tap.logout();
  PERFORM public.resolve_transfer_dispute(v_t, 'seller_win', tap.admin_user(), 'seller proved delivery');
  RETURN v_t;
END $$;

-- auto-release: the 039 cron path (seller_sent → auto_released), no buyer act
CREATE FUNCTION pg_temp.auto_released(p_n int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_t uuid := pg_temp.mk(p_n);
BEGIN
  PERFORM public.apply_auto_release(v_t);
  RETURN v_t;
END $$;

CREATE FUNCTION pg_temp.claim(p_t uuid) RETURNS uuid LANGUAGE sql AS $$
  SELECT attempt_id FROM public.claim_payout_attempt(p_t, 'test');
$$;

-- a3 via DUPLICATE_TRANSFER (defensive-branch contract, see header): an attempt is
-- open when the legacy recorder writes a different Stripe transfer onto the row; the
-- attempt's own result then cannot be recorded on it → reversal_required + a
-- manual_review decision
CREATE FUNCTION pg_temp.duplicate(p_t uuid, p_tag text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_a uuid := pg_temp.claim(p_t);
BEGIN
  IF NOT public.record_transfer_payout(p_t, 'tr_legacy_' || p_tag) THEN
    RAISE EXCEPTION 'fixture: record_transfer_payout refused %', p_tag;
  END IF;
  RETURN public.record_payout_attempt_result(v_a, 'tr_new_' || p_tag, 'succeeded', NULL);
END $$;

-- a4: paid through the attempt protocol, then a chargeback lost after payout
CREATE FUNCTION pg_temp.paid_then_lost(p_t uuid, p_tag text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_a uuid := pg_temp.claim(p_t);
BEGIN
  PERFORM public.record_payout_attempt_result(v_a, 'tr_paid_' || p_tag, 'succeeded', NULL);
  RETURN public.flag_payout_reversal_required(p_t, 'DISPUTE_LOST_AFTER_PAYOUT', '{"dispute_id":"dp_test"}'::jsonb);
END $$;

-- the flag on the ONE decision a case produced (NULL if none; error if several)
CREATE FUNCTION pg_temp.flag(p_t uuid, p_reason text) RETURNS boolean LANGUAGE sql AS $$
  SELECT buyer_confirmed FROM public.payout_decisions
   WHERE transfer_id = p_t AND decision = 'manual_review' AND p_reason = ANY(reason_codes);
$$;

-- ── fixtures ────────────────────────────────────────────────────────────────
CREATE TEMP TABLE _c (k text PRIMARY KEY, t uuid);
INSERT INTO _c VALUES
  ('gen_dup',  pg_temp.genuine(1)),
  ('sw_dup',   pg_temp.seller_win(2)),
  ('auto_dup', pg_temp.auto_released(3)),
  ('gen_pdd',  pg_temp.genuine(4)),
  ('gen_cb',   pg_temp.genuine(5)),
  ('sw_cb',    pg_temp.seller_win(6)),
  ('auto_cb',  pg_temp.auto_released(7));
CREATE FUNCTION pg_temp.t(p_k text) RETURNS uuid LANGUAGE sql AS $$ SELECT t FROM _c WHERE k = p_k $$;

-- ── F: the fixtures are the states they claim to be ─────────────────────────
SELECT ok((SELECT status = 'buyer_confirmed' AND buyer_confirmed_at IS NOT NULL AND dispute_resolution IS NULL
             FROM public.transfers WHERE id = pg_temp.t('gen_dup')),
  'F1 genuine: confirm_transfer_received sets status AND buyer_confirmed_at');
SELECT ok((SELECT status = 'buyer_confirmed' AND buyer_confirmed_at IS NULL
                  AND dispute_resolution = 'resolved_seller_paid' AND disputed_at IS NULL
             FROM public.transfers WHERE id = pg_temp.t('sw_dup')),
  'F2 seller-win: the same status with buyer_confirmed_at NULL (065 never manufactures a confirmation)');
SELECT ok((SELECT status = 'auto_released' AND buyer_confirmed_at IS NULL
             FROM public.transfers WHERE id = pg_temp.t('auto_dup')),
  'F3 auto-release: no buyer act recorded');

-- ── a3 record_payout_attempt_result: DUPLICATE_TRANSFER ─────────────────────
CREATE TEMP TABLE _r AS
  SELECT k, pg_temp.duplicate(t, k) AS r FROM _c WHERE k IN ('gen_dup','sw_dup','auto_dup');
SELECT is((SELECT count(*) FROM _r WHERE r->>'state' = 'reversal_required' AND (r->>'recorded')::boolean = false),
  3::bigint, 'A3-0 all three duplicate cases reach reversal_required (the row keeps the legacy transfer)');
SELECT is(pg_temp.flag(pg_temp.t('gen_dup'), 'DUPLICATE_TRANSFER'), true,
  'A3-1 genuine buyer confirmation: the DUPLICATE_TRANSFER decision records buyer_confirmed = true');
SELECT is(pg_temp.flag(pg_temp.t('sw_dup'), 'DUPLICATE_TRANSFER'), false,
  'A3-2 seller-win: the DUPLICATE_TRANSFER decision records buyer_confirmed = false (status is not a buyer act)');
SELECT is(pg_temp.flag(pg_temp.t('auto_dup'), 'DUPLICATE_TRANSFER'), false,
  'A3-3 auto-release: the DUPLICATE_TRANSFER decision records buyer_confirmed = false');

-- ── a3 record_payout_attempt_result: PAID_DURING_DISPUTE ────────────────────
-- the buyer confirmed; a chargeback froze the row between claim and record
CREATE TEMP TABLE _pdd AS SELECT pg_temp.claim(pg_temp.t('gen_pdd')) AS a;
SELECT is(public.freeze_transfer_for_dispute(pg_temp.t('gen_pdd')), true,
  'A3-4a a chargeback freezes the confirmed, unpaid row (status becomes disputed)');
SELECT is((public.record_payout_attempt_result((SELECT a FROM _pdd), 'tr_pdd', 'succeeded', NULL))->>'state',
  'reversal_required', 'A3-4b money moved during the dispute → reversal_required');
SELECT is(pg_temp.flag(pg_temp.t('gen_pdd'), 'PAID_DURING_DISPUTE'), true,
  'A3-4 PAID_DURING_DISPUTE after a genuine confirmation records buyer_confirmed = true (the act happened; status now reads disputed)');

-- ── a4 flag_payout_reversal_required: chargeback lost after payout ─────────
CREATE TEMP TABLE _f AS
  SELECT k, pg_temp.paid_then_lost(t, k) AS r FROM _c WHERE k IN ('gen_cb','sw_cb','auto_cb');
SELECT is((SELECT count(*) FROM _f WHERE (r->>'flagged')::boolean AND (r->>'decision_inserted')::boolean),
  3::bigint, 'A4-0 all three paid cases are flagged with one new decision each');
SELECT is(pg_temp.flag(pg_temp.t('gen_cb'), 'DISPUTE_LOST_AFTER_PAYOUT'), true,
  'A4-1 genuine buyer confirmation: the chargeback decision records buyer_confirmed = true');
SELECT is(pg_temp.flag(pg_temp.t('sw_cb'), 'DISPUTE_LOST_AFTER_PAYOUT'), false,
  'A4-2 seller-win: the chargeback decision records buyer_confirmed = false');
SELECT is(pg_temp.flag(pg_temp.t('auto_cb'), 'DISPUTE_LOST_AFTER_PAYOUT'), false,
  'A4-3 auto-release: the chargeback decision records buyer_confirmed = false');
SELECT is((SELECT dispute_open FROM public.payout_decisions
            WHERE transfer_id = pg_temp.t('sw_cb') AND 'DISPUTE_LOST_AFTER_PAYOUT' = ANY(reason_codes)), true,
  'A4-4 dispute_open is unchanged (still true on a lost chargeback)');

-- ── I: invariants over every decision this test produced ────────────────────
SELECT is((SELECT count(*) FROM public.payout_decisions d JOIN _c c ON c.t = d.transfer_id), 7::bigint,
  'I1 exactly seven decisions: one per case');
SELECT is((SELECT count(*) FROM public.payout_decisions d
             JOIN _c c ON c.t = d.transfer_id
             JOIN public.transfers tr ON tr.id = d.transfer_id
            WHERE d.buyer_confirmed IS DISTINCT FROM (tr.buyer_confirmed_at IS NOT NULL)), 0::bigint,
  'I2 every decision''s buyer_confirmed equals whether the buyer confirmed (buyer_confirmed_at)');
SELECT is((SELECT count(*) FROM public.payout_decisions d
             JOIN _c c ON c.t = d.transfer_id
             JOIN public.transfers tr ON tr.id = d.transfer_id
            WHERE tr.dispute_resolution = 'resolved_seller_paid' AND d.buyer_confirmed), 0::bigint,
  'I3 no seller-win decision asserts a buyer confirmation');
SELECT is((SELECT count(*) FROM public.payout_decisions d JOIN _c c ON c.t = d.transfer_id
            WHERE 'BUYER_CONFIRMED' = ANY(d.reason_codes)), 0::bigint,
  'I4 the SQL writers never add a BUYER_CONFIRMED reason code');
SELECT is((SELECT count(*) FROM public.transfers tr JOIN _c c ON c.t = tr.id
            WHERE c.k IN ('sw_dup','sw_cb','auto_dup','auto_cb') AND tr.buyer_confirmed_at IS NOT NULL), 0::bigint,
  'I5 no writer manufactured buyer_confirmed_at on a seller-win or auto-release row');

-- ── S: the definitions keep their contract (CREATE OR REPLACE) ──────────────
SELECT is((SELECT prosecdef FROM pg_proc WHERE oid = 'public.record_payout_attempt_result(uuid,text,text,jsonb)'::regprocedure),
  true, 'S1 record_payout_attempt_result is SECURITY DEFINER');
SELECT is((SELECT prosecdef FROM pg_proc WHERE oid = 'public.flag_payout_reversal_required(uuid,text,jsonb)'::regprocedure),
  true, 'S2 flag_payout_reversal_required is SECURITY DEFINER');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'public.record_payout_attempt_result(uuid,text,text,jsonb)'::regprocedure),
  ARRAY['search_path=public'], 'S3 record_payout_attempt_result search_path = public');
SELECT is((SELECT proconfig FROM pg_proc WHERE oid = 'public.flag_payout_reversal_required(uuid,text,jsonb)'::regprocedure),
  ARRAY['search_path=public'], 'S4 flag_payout_reversal_required search_path = public');
SELECT is((SELECT array_agg(r ORDER BY r) FROM unnest(ARRAY['anon','authenticated','service_role']) r
            WHERE has_function_privilege(r, 'public.record_payout_attempt_result(uuid,text,text,jsonb)', 'EXECUTE')),
  ARRAY['service_role'], 'S5 record_payout_attempt_result: EXECUTE for service_role only');
SELECT is((SELECT array_agg(r ORDER BY r) FROM unnest(ARRAY['anon','authenticated','service_role']) r
            WHERE has_function_privilege(r, 'public.flag_payout_reversal_required(uuid,text,jsonb)', 'EXECUTE')),
  ARRAY['service_role'], 'S6 flag_payout_reversal_required: EXECUTE for service_role only');

SELECT * FROM finish();
ROLLBACK;
