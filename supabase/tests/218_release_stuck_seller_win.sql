-- ============================================================================
-- 218_release_stuck_seller_win.sql — the stuck seller-win payout detector
-- (migration 20260925010000, registry 151; finding b2, D's, verified by A).
--
-- A seller-win decision (065 resolve_transfer_dispute) leaves the transfer
-- 'buyer_confirmed' with buyer_confirmed_at NULL. 117's ops.detect_release_stuck
-- dated such a row by coalesce(buyer_confirmed_at, auto_release_at):
--   * a Stripe dispute frozen before the seller sent (freeze_transfer_for_dispute)
--     has auto_release_at NULL too, so the row was NEVER flagged;
--   * a buyer report (only from seller_sent) carries the send-time auto_release_at,
--     so the row was flagged the moment it was resolved, inside the payout sweep's
--     own 15-minute quiet period, or not until up to 72 hours later.
-- 151 dates a seller-win row from when it became payable:
-- greatest(dispute_resolved_at, payout_hold_until) — the sweep's (d) selection
-- and claim_payout_attempt's hold rule (20260924000000) — and says in the case
-- when automation will never pay it (manual_review, or held with no end).
--
-- Every row is built through the real RPCs (buyer_dispute_transfer,
-- freeze_transfer_for_dispute, apply_payout_hold, apply_manual_review,
-- resolve_transfer_dispute, confirm_transfer_received, record_transfer_payout);
-- only timestamps are moved back, because now() is frozen in a transaction.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(17);

SELECT tap.seed_core();
SELECT tap.logout();

-- ── fixtures (transaction-local) ────────────────────────────────────────────
-- One transfer per case on its own listing and live payment. p_status is
-- 'seller_sent' (auto_release_at given) or 'pending' (never sent).
CREATE FUNCTION pg_temp.mk(p_n int, p_status text DEFAULT 'seller_sent', p_auto_release interval DEFAULT interval '-1 day')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_l uuid := ('dddddddd-0000-0000-0218-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p uuid := ('eeeeeeee-0000-0000-0218-' || lpad(p_n::text, 12, '0'))::uuid;
  v_t uuid := ('ffffffff-0000-0000-0218-' || lpad(p_n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
     transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
     current_bid, cover_image_path, auction_status)
  VALUES (v_l, tap.seller(), 'RS Event ' || p_n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
          'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/rs.jpg', 'active');
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id,
     status, mode, paid_at, stripe_livemode)
  VALUES (v_p, v_l, tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_rs_' || p_n,
          'succeeded', 'buy_now', now(), true);
  IF p_status = 'seller_sent' THEN
    INSERT INTO public.transfers
      (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at,
       auto_release_at, transfer_evidence_path, expires_at)
    VALUES (v_t, v_l, v_p, tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now() - interval '4 days',
            now() + p_auto_release, 'fixtures/evidence-rs.jpg', now() + interval '24 hours');
  ELSE
    INSERT INTO public.transfers
      (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
    VALUES (v_t, v_l, v_p, tap.seller(), tap.buyer(), 'mobile_transfer', 'pending', now() + interval '24 hours');
  END IF;
  RETURN v_t;
END $$;
CREATE FUNCTION pg_temp.tid(p_n int) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('ffffffff-0000-0000-0218-' || lpad(p_n::text, 12, '0'))::uuid $$;

-- a buyer report through the real RPC, as the buyer
CREATE FUNCTION pg_temp.report(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.login(tap.buyer());
  PERFORM public.buyer_dispute_transfer(p_t);
  PERFORM tap.logout();
END $$;

-- a Stripe dispute (charge.dispute.created) freezes the transfer, as the webhook does
CREATE FUNCTION pg_temp.stripe_dispute(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.login_service();
  PERFORM public.freeze_transfer_for_dispute(p_t);
  PERFORM tap.logout();
END $$;

-- the operator's decision, then the resolution time moved back
CREATE FUNCTION pg_temp.decide(p_t uuid, p_outcome text, p_ago interval) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.resolve_transfer_dispute(p_t, p_outcome, tap.admin_user(), 'test decision');
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET dispute_resolved_at = now() - p_ago WHERE id = p_t;
  PERFORM set_config('app.bypass_transfer_guard', 'off', true);
END $$;

-- move one timestamp column back (or forward) by name
CREATE FUNCTION pg_temp.shift(p_t uuid, p_col text, p_at timestamptz) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  EXECUTE format('UPDATE public.transfers SET %I = $1 WHERE id = $2', p_col) USING p_at, p_t;
  PERFORM set_config('app.bypass_transfer_guard', 'off', true);
END $$;

CREATE FUNCTION pg_temp.run() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM tap.login_service();
  v := ops.run_job('release_stuck', 'test');
  PERFORM tap.logout();
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.open_case(p_t uuid) RETURNS ops."case" LANGUAGE sql AS $$
  SELECT c.* FROM ops."case" c
   WHERE c.dedupe_key = 'release_stuck:' || p_t::text AND c.status NOT IN ('resolved','dismissed') $$;

-- ── rows ────────────────────────────────────────────────────────────────────
-- 1: a Stripe dispute frozen before the seller sent; seller-win 45 min ago
SELECT pg_temp.mk(1, 'pending');
SELECT pg_temp.stripe_dispute(pg_temp.tid(1));
SELECT pg_temp.decide(pg_temp.tid(1), 'seller_win', interval '45 minutes');
-- 2: a buyer report; auto_release_at 3 days past; seller-win 5 min ago
SELECT pg_temp.mk(2, 'seller_sent', interval '-3 days');
SELECT pg_temp.report(pg_temp.tid(2));
SELECT pg_temp.decide(pg_temp.tid(2), 'seller_win', interval '5 minutes');
-- 3: a buyer report; auto_release_at 2 days ahead; seller-win 2 hours ago
SELECT pg_temp.mk(3, 'seller_sent', interval '2 days');
SELECT pg_temp.report(pg_temp.tid(3));
SELECT pg_temp.decide(pg_temp.tid(3), 'seller_win', interval '2 hours');
-- 4: a live hold (ends in a day), applied while seller_sent; seller-win 2 hours ago
SELECT pg_temp.mk(4, 'seller_sent', interval '-3 days');
SELECT public.apply_payout_hold(pg_temp.tid(4), now() + interval '1 day', 'medium', ARRAY['SELLER_UNPROVEN']);
SELECT pg_temp.report(pg_temp.tid(4));
SELECT pg_temp.decide(pg_temp.tid(4), 'seller_win', interval '2 hours');
-- 5: a hold that ended 10 min ago; seller-win 2 days ago
SELECT pg_temp.mk(5, 'seller_sent', interval '-4 days');
SELECT public.apply_payout_hold(pg_temp.tid(5), now() + interval '1 day', 'medium', ARRAY['SELLER_UNPROVEN']);
SELECT pg_temp.report(pg_temp.tid(5));
SELECT pg_temp.decide(pg_temp.tid(5), 'seller_win', interval '2 days');
SELECT pg_temp.shift(pg_temp.tid(5), 'payout_hold_until', now() - interval '10 minutes');
-- 6: a hold that ended 45 min ago; seller-win 2 days ago
SELECT pg_temp.mk(6, 'seller_sent', interval '-4 days');
SELECT public.apply_payout_hold(pg_temp.tid(6), now() + interval '1 day', 'medium', ARRAY['SELLER_UNPROVEN']);
SELECT pg_temp.report(pg_temp.tid(6));
SELECT pg_temp.decide(pg_temp.tid(6), 'seller_win', interval '2 days');
SELECT pg_temp.shift(pg_temp.tid(6), 'payout_hold_until', now() - interval '45 minutes');
-- 7: manual_review; seller-win 45 min ago
SELECT pg_temp.mk(7);
SELECT public.apply_manual_review(pg_temp.tid(7), 'high', ARRAY['EVENT_DATE_UNKNOWN']);
SELECT pg_temp.report(pg_temp.tid(7));
SELECT pg_temp.decide(pg_temp.tid(7), 'seller_win', interval '45 minutes');
-- 8: held with no end; seller-win 45 min ago
SELECT pg_temp.mk(8);
SELECT public.apply_payout_hold(pg_temp.tid(8), NULL, 'medium', ARRAY['SELLER_UNPROVEN']);
SELECT pg_temp.report(pg_temp.tid(8));
SELECT pg_temp.decide(pg_temp.tid(8), 'seller_win', interval '45 minutes');
-- 9: a seller-win already paid (the real writer)
SELECT pg_temp.mk(9);
SELECT pg_temp.report(pg_temp.tid(9));
SELECT pg_temp.decide(pg_temp.tid(9), 'seller_win', interval '2 hours');
SELECT public.record_transfer_payout(pg_temp.tid(9), 'tr_rs_9');
-- 10 / 11: genuine confirmations 45 and 10 minutes ago (117's rule, unchanged)
SELECT pg_temp.mk(10);
SELECT tap.login(tap.buyer());
SELECT public.confirm_transfer_received(pg_temp.tid(10), tap.buyer());
SELECT tap.logout();
SELECT pg_temp.shift(pg_temp.tid(10), 'buyer_confirmed_at', now() - interval '45 minutes');
SELECT pg_temp.mk(11);
SELECT tap.login(tap.buyer());
SELECT public.confirm_transfer_received(pg_temp.tid(11), tap.buyer());
SELECT tap.logout();
SELECT pg_temp.shift(pg_temp.tid(11), 'buyer_confirmed_at', now() - interval '10 minutes');
-- 12: auto_released 45 min ago (117's rule, unchanged)
SELECT pg_temp.mk(12, 'seller_sent', interval '-45 minutes');
SELECT public.apply_auto_release(pg_temp.tid(12));
-- 13: a buyer-win decision (the seller is not paid)
SELECT pg_temp.mk(13);
SELECT pg_temp.report(pg_temp.tid(13));
SELECT pg_temp.decide(pg_temp.tid(13), 'buyer_win', interval '2 hours');

SELECT pg_temp.run();

-- ── S — structure ───────────────────────────────────────────────────────────
SELECT ok(NOT has_function_privilege('anon', 'ops.detect_release_stuck()', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'ops.detect_release_stuck()', 'EXECUTE')
      AND NOT has_function_privilege('service_role', 'ops.detect_release_stuck()', 'EXECUTE'),
  'S1: ops.detect_release_stuck stays unexecutable by every client role (only run_job calls it)');

-- ── T — the detector ────────────────────────────────────────────────────────
SELECT ok((pg_temp.open_case(pg_temp.tid(1))).id IS NOT NULL,
  'T1: a seller-win on a transfer frozen before sending (no auto_release_at) is flagged 45 min after the decision');
SELECT ok((pg_temp.open_case(pg_temp.tid(2))).id IS NULL,
  'T2: a seller-win decided 5 min ago is not flagged, whatever its old auto_release_at says');
SELECT ok((pg_temp.open_case(pg_temp.tid(3))).id IS NOT NULL,
  'T3: a seller-win decided 2 hours ago is flagged even though auto_release_at is still ahead');
SELECT ok((pg_temp.open_case(pg_temp.tid(4))).id IS NULL,
  'T4: a seller-win under a live hold is not flagged (claim_payout_attempt refuses it until the hold ends)');
SELECT ok((pg_temp.open_case(pg_temp.tid(5))).id IS NULL,
  'T5: a seller-win whose hold ended 10 min ago is not flagged yet (dated from the hold''s end)');
SELECT ok((pg_temp.open_case(pg_temp.tid(6))).id IS NOT NULL,
  'T6: a seller-win whose hold ended 45 min ago is flagged');
SELECT ok((pg_temp.open_case(pg_temp.tid(7))).id IS NOT NULL
      AND position('manual_review' IN (pg_temp.open_case(pg_temp.tid(7))).summary) > 0,
  'T7: a seller-win in manual_review is flagged, and the case says automation will not pay it');
SELECT ok((pg_temp.open_case(pg_temp.tid(8))).id IS NOT NULL
      AND position('no end' IN (pg_temp.open_case(pg_temp.tid(8))).summary) > 0,
  'T8: a seller-win held with no end is flagged, and the case says so');
SELECT ok((pg_temp.open_case(pg_temp.tid(9))).id IS NULL,
  'T9: a paid seller-win is never flagged');
SELECT ok((pg_temp.open_case(pg_temp.tid(10))).id IS NOT NULL AND (pg_temp.open_case(pg_temp.tid(11))).id IS NULL,
  'T10: a genuine confirmation is flagged after 30 min and not before (117''s rule unchanged)');
SELECT ok((pg_temp.open_case(pg_temp.tid(12))).id IS NOT NULL,
  'T11: an auto_released row is flagged as before');
SELECT ok((pg_temp.open_case(pg_temp.tid(13))).id IS NULL,
  'T12: a buyer-win decision is never flagged (the seller is not paid)');
SELECT ok(position('decided for the seller' IN (pg_temp.open_case(pg_temp.tid(1))).summary) > 0,
  'T13: a seller-win case says the dispute was decided for the seller');
SELECT is((SELECT (pg_temp.open_case(pg_temp.tid(3))).priority), 'p2',
  'T14: seller-win cases keep release_stuck''s priority (p2)');

-- paying row 1 through the real writer clears its case on the next run
SELECT tap.login_service();
SELECT public.record_transfer_payout(pg_temp.tid(1), 'tr_rs_1');
SELECT tap.logout();
SELECT pg_temp.run();
SELECT ok((pg_temp.open_case(pg_temp.tid(1))).id IS NULL
      AND (SELECT count(*) FROM ops."case" WHERE dedupe_key = 'release_stuck:' || pg_temp.tid(1)::text
                                            AND status = 'resolved' AND resolved_by IS NULL) = 1,
  'T15: once paid, the seller-win case auto-resolves');
SELECT ok((pg_temp.open_case(pg_temp.tid(3))).id IS NOT NULL,
  'T16: the other seller-win cases stay open');

SELECT * FROM finish();
ROLLBACK;
