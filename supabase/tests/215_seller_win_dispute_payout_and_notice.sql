-- ============================================================================
-- 215_seller_win_dispute_payout_and_notice.sql — F-DISPUTE-SELLERWIN-1
-- (migration 20260924000000, registry 148).
--
-- A seller-win dispute resolution (065 resolve_transfer_dispute) sets status
-- 'buyer_confirmed' but — correctly — leaves buyer_confirmed_at NULL: the buyer
-- never confirmed. Two readers conflated the status with a buyer action:
--   PAYOUT  claim_payout_attempt admitted a seller-win regardless of risk holds
--           (reachable through confirm-and-release's "already confirmed" path).
--           An operator's decision is not the buyer's statement: it must NOT
--           inherit the buyer confirmation's override of holds.
--   NOTICE  notify_transfer_state_inbox told the seller "Buyer confirmed
--           receipt". The seller must instead be told "Dispute resolved in your
--           favour", without implying the payout has completed.
-- Payout and notification are asserted in SEPARATE tests. Every state is
-- reached through the real functions (apply_payout_hold / apply_manual_review,
-- buyer_dispute_transfer, resolve_transfer_dispute, confirm_transfer_received).
-- The hold states are the shared matrix (tests/fixtures/seller_win_hold_matrix.json;
-- tests/seller-win-dispute.test.ts fails if the block below differs from it).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(43);
SELECT tap.seed_core();
SELECT tap.logout();
UPDATE public.profiles SET stripe_connect_id = 'acct_A' WHERE id = tap.seller();

-- ── fixture helpers (transaction-local) ─────────────────────────────────────
-- One seller_sent transfer per case, each on its own listing and live payment.
CREATE FUNCTION pg_temp.mk(p_n int, p_live boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_l uuid := ('dddddddd-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_p uuid := ('eeeeeeee-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
  v_t uuid := ('ffffffff-0000-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
     transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
     current_bid, cover_image_path, auction_status)
  VALUES (v_l, tap.seller(), 'SW Event ' || p_n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
          'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/sw.jpg', 'active');
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id,
     status, mode, paid_at, stripe_livemode)
  VALUES (v_p, v_l, tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_sw_' || p_n,
          'succeeded', 'buy_now', now(), p_live);
  INSERT INTO public.transfers
    (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at,
     auto_release_at, transfer_evidence_path, expires_at)
  VALUES (v_t, v_l, v_p, tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now() - interval '4 days',
          now() - interval '1 day', 'fixtures/evidence-sw.jpg', now() + interval '24 hours');
  RETURN v_t;
END $$;

-- the buyer opens a dispute through the real RPC, as the buyer
CREATE FUNCTION pg_temp.dispute(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.login(tap.buyer());
  PERFORM public.buyer_dispute_transfer(p_t);
  PERFORM tap.logout();
END $$;

-- the buyer confirms receipt through the real RPC, as the buyer
CREATE FUNCTION pg_temp.confirm(p_t uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM tap.login(tap.buyer());
  PERFORM public.confirm_transfer_received(p_t, tap.buyer());
  PERFORM tap.logout();
END $$;

-- a seller-win in the given hold state: hold/review applied while seller_sent
-- (as Phase 2 would), then dispute, then the operator's seller-win decision
CREATE FUNCTION pg_temp.seller_win(p_n int, p_review text, p_hold_offset_min int, p_live boolean DEFAULT true)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_t uuid := pg_temp.mk(p_n, p_live);
BEGIN
  IF p_review = 'held' THEN
    PERFORM public.apply_payout_hold(v_t,
      CASE WHEN p_hold_offset_min IS NULL THEN NULL ELSE now() + make_interval(mins => p_hold_offset_min) END,
      'medium', ARRAY['SELLER_UNPROVEN']);
  ELSIF p_review = 'manual_review' THEN
    PERFORM public.apply_manual_review(v_t, 'high', ARRAY['EVENT_DATE_UNKNOWN']);
    IF p_hold_offset_min IS NOT NULL THEN
      PERFORM set_config('app.bypass_transfer_guard', 'on', true);
      UPDATE public.transfers SET payout_hold_until = now() + make_interval(mins => p_hold_offset_min) WHERE id = v_t;
    END IF;
  ELSIF p_hold_offset_min IS NOT NULL THEN
    PERFORM set_config('app.bypass_transfer_guard', 'on', true);
    UPDATE public.transfers SET payout_hold_until = now() + make_interval(mins => p_hold_offset_min) WHERE id = v_t;
  END IF;
  PERFORM pg_temp.dispute(v_t);
  PERFORM public.resolve_transfer_dispute(v_t, 'seller_win', tap.admin_user(), 'seller proved delivery');
  RETURN v_t;
END $$;

-- claim outcome as text: the refusal code, or 'admitted'
CREATE FUNCTION pg_temp.claim(p_t uuid) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM * FROM public.claim_payout_attempt(p_t, 'test');
  RETURN 'admitted';
EXCEPTION WHEN raise_exception THEN
  RETURN SQLERRM;
END $$;

-- notifications for one transfer, by title
CREATE FUNCTION pg_temp.notes(p_t uuid, p_title text) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.notifications n
   WHERE n.metadata ->> 'transfer_id' = p_t::text AND n.title = p_title;
$$;

-- ── the shared hold matrix (pinned to tests/fixtures/seller_win_hold_matrix.json) ──
CREATE TEMP TABLE _matrix (n int, case_name text, review text, hold_offset_min int, expect text);
INSERT INTO _matrix (case_name, review, hold_offset_min, expect)
-- MATRIX-BEGIN
VALUES
  ('no_hold', NULL, NULL, NULL),
  ('held_future', 'held', 4320, 'PAYOUT_HELD'),
  ('held_past', 'held', -60, NULL),
  ('held_no_end', 'held', NULL, 'PAYOUT_HELD'),
  ('hold_until_future_no_review', NULL, 60, 'PAYOUT_HELD'),
  ('manual_review', 'manual_review', NULL, 'PAYOUT_UNDER_REVIEW'),
  ('manual_review_past_hold', 'manual_review', -60, 'PAYOUT_UNDER_REVIEW')
-- MATRIX-END
;
UPDATE _matrix m SET n = s.rn + 100
  FROM (SELECT case_name, row_number() OVER (ORDER BY case_name) AS rn FROM _matrix) s
 WHERE s.case_name = m.case_name;

-- ============================================================================
-- PAYOUT CORRECTNESS
-- ============================================================================
CREATE TEMP TABLE _sw AS SELECT pg_temp.seller_win(1, NULL, NULL) AS t;

-- P2: the operator's decision never manufactures a buyer confirmation
SELECT is((SELECT status FROM public.transfers WHERE id = (SELECT t FROM _sw)), 'buyer_confirmed',
  'fixture: a seller-win leaves status buyer_confirmed');
SELECT ok((SELECT buyer_confirmed_at IS NULL FROM public.transfers WHERE id = (SELECT t FROM _sw)),
  'P2: buyer_confirmed_at stays NULL after a seller-win (no manufactured timestamp)');
SELECT ok((SELECT dispute_resolution = 'resolved_seller_paid' AND disputed_at IS NULL AND dispute_resolved_at IS NOT NULL
             FROM public.transfers WHERE id = (SELECT t FROM _sw)),
  'fixture: the resolution is recorded as the operator''s decision');

-- P1: a legitimate seller-win is admitted by the authority
SELECT is(pg_temp.claim((SELECT t FROM _sw)), 'admitted', 'P1: an unheld seller-win is admitted by claim_payout_attempt');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id = (SELECT t FROM _sw)), 1::bigint,
  'P1: exactly one attempt opened');

-- P5: no duplicate processing
SELECT is(pg_temp.claim((SELECT t FROM _sw)), 'PAYOUT_ATTEMPT_IN_PROGRESS', 'P5: a concurrent claim is refused while the lease is live');
SELECT is(public.mark_payout_requested((SELECT id FROM public.payout_attempts WHERE transfer_id = (SELECT t FROM _sw))), true,
  'P5: the attempt is marked requested');
SELECT lives_ok(
  $$ SELECT public.record_payout_attempt_result((SELECT id FROM public.payout_attempts WHERE transfer_id = (SELECT t FROM _sw)), 'tr_sw_1', 'succeeded') $$,
  'P5: the Stripe transfer is recorded');
SELECT is(pg_temp.claim((SELECT t FROM _sw)), 'ALREADY_RELEASED', 'P5: a paid seller-win cannot be claimed again');
SELECT is((SELECT stripe_transfer_id FROM public.transfers WHERE id = (SELECT t FROM _sw)), 'tr_sw_1',
  'P5: the transfer row carries the one Stripe transfer id');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id = (SELECT t FROM _sw)), 1::bigint,
  'P5: still exactly one attempt');
SELECT ok((SELECT buyer_confirmed_at IS NULL FROM public.transfers WHERE id = (SELECT t FROM _sw)),
  'P2: buyer_confirmed_at is still NULL after the payout is recorded');

-- P7: the hold matrix, through the real hold writers
CREATE TEMP TABLE _hm AS
  SELECT m.case_name, m.expect, pg_temp.seller_win(m.n, m.review, m.hold_offset_min) AS t FROM _matrix m;
SELECT is(pg_temp.claim(h.t), coalesce(h.expect, 'admitted'),
          'P7 matrix [' || h.case_name || ']: claim → ' || coalesce(h.expect, 'admitted'))
  FROM _hm h ORDER BY h.case_name;
SELECT is((SELECT count(*) FROM public.payout_attempts a JOIN _hm h ON h.t = a.transfer_id WHERE h.expect IS NOT NULL), 0::bigint,
  'P7: a refused seller-win opens no attempt row');

-- P8: test-mode payment
SELECT is(pg_temp.claim(pg_temp.seller_win(2, NULL, NULL, false)), 'PAYMENT_NOT_LIVE',
  'P8: a seller-win on a test-mode payment stays unpayable');

-- P3 / P4: unresolved, buyer-win and partial outcomes stay blocked by the authority
CREATE TEMP TABLE _ud AS SELECT pg_temp.mk(3) AS t;
DO $$ BEGIN PERFORM pg_temp.dispute((SELECT t FROM _ud)); END $$;
SELECT is(pg_temp.claim((SELECT t FROM _ud)), 'DISPUTED', 'P3: an unresolved dispute is refused');
CREATE TEMP TABLE _bw AS SELECT pg_temp.mk(4) AS t;
DO $$ BEGIN PERFORM pg_temp.dispute((SELECT t FROM _bw)); END $$;
SELECT lives_ok($$ SELECT public.resolve_transfer_dispute((SELECT t FROM _bw), 'buyer_win', tap.admin_user(), 'not delivered') $$,
  'fixture: buyer-win resolution');
SELECT is(pg_temp.claim((SELECT t FROM _bw)), 'DISPUTED', 'P4: a buyer-win is refused');
CREATE TEMP TABLE _pr AS SELECT pg_temp.mk(5) AS t;
DO $$ BEGIN PERFORM pg_temp.dispute((SELECT t FROM _pr)); END $$;
SELECT lives_ok($$ SELECT public.resolve_transfer_dispute((SELECT t FROM _pr), 'partial_refund', tap.admin_user(), 'partial') $$,
  'fixture: partial-refund resolution');
SELECT is(pg_temp.claim((SELECT t FROM _pr)), 'DISPUTED', 'P4: a partial-refund outcome is refused');

-- P6: a genuine buyer confirmation is unchanged — it still overrides holds and manual review
CREATE TEMP TABLE _gh AS SELECT pg_temp.mk(6) AS t;
DO $$ BEGIN PERFORM public.apply_payout_hold((SELECT t FROM _gh), now() + interval '3 days', 'medium', ARRAY['SELLER_UNPROVEN']); END $$;
DO $$ BEGIN PERFORM pg_temp.confirm((SELECT t FROM _gh)); END $$;
SELECT ok((SELECT buyer_confirmed_at IS NOT NULL FROM public.transfers WHERE id = (SELECT t FROM _gh)),
  'fixture: a genuine confirmation sets buyer_confirmed_at');
SELECT is(pg_temp.claim((SELECT t FROM _gh)), 'admitted', 'P6: a genuine confirmation still overrides a pending hold');
CREATE TEMP TABLE _gm AS SELECT pg_temp.mk(7) AS t;
DO $$ BEGIN PERFORM public.apply_manual_review((SELECT t FROM _gm), 'high', ARRAY['EVENT_DATE_UNKNOWN']); END $$;
DO $$ BEGIN PERFORM pg_temp.confirm((SELECT t FROM _gm)); END $$;
SELECT is(pg_temp.claim((SELECT t FROM _gm)), 'admitted', 'P6: a genuine confirmation still overrides manual review');

-- ============================================================================
-- NOTIFICATION TRUTHFULNESS (separate tests; no payout assertion below)
-- ============================================================================
CREATE TEMP TABLE _ns AS SELECT pg_temp.seller_win(8, NULL, NULL) AS t;
SELECT is(pg_temp.notes((SELECT t FROM _ns), 'Buyer confirmed receipt'), 0::bigint,
  'N1: a seller-win produces NO "Buyer confirmed receipt"');
SELECT is(pg_temp.notes((SELECT t FROM _ns), 'Dispute resolved in your favour'), 1::bigint,
  'N2: a seller-win produces exactly one "Dispute resolved in your favour"');
SELECT is((SELECT n.user_id FROM public.notifications n
            WHERE n.metadata ->> 'transfer_id' = (SELECT t FROM _ns)::text AND n.title = 'Dispute resolved in your favour'),
          tap.seller(), 'N2: addressed to the seller');
SELECT ok((SELECT n.body IS NOT NULL
                  AND n.title || ' ' || n.body !~* '(payout|paid|release|on its way|transferred|funds)'
             FROM public.notifications n
            WHERE n.metadata ->> 'transfer_id' = (SELECT t FROM _ns)::text AND n.title = 'Dispute resolved in your favour'),
  'N3: the notice does not imply the payout has completed');
SELECT is((SELECT count(*) FROM public.notifications n
            WHERE n.metadata ->> 'transfer_id' = (SELECT t FROM _ns)::text AND n.type = 'payout_released'), 0::bigint,
  'N3: no payout notice exists before a payout is recorded');
SELECT is((SELECT n.link FROM public.notifications n
            WHERE n.metadata ->> 'transfer_id' = (SELECT t FROM _ns)::text AND n.title = 'Dispute resolved in your favour'),
          '/transfer/send/' || (SELECT t FROM _ns)::text, 'N2: links the seller to the transfer');

-- N4: a genuine buyer confirmation still tells the seller the truth
CREATE TEMP TABLE _ng AS SELECT pg_temp.mk(9) AS t;
DO $$ BEGIN PERFORM pg_temp.confirm((SELECT t FROM _ng)); END $$;
SELECT is(pg_temp.notes((SELECT t FROM _ng), 'Buyer confirmed receipt'), 1::bigint,
  'N4: a genuine confirmation still produces "Buyer confirmed receipt"');
SELECT is(pg_temp.notes((SELECT t FROM _ng), 'Dispute resolved in your favour'), 0::bigint,
  'N4: a genuine confirmation produces no dispute notice');

-- N6: buyer-win and partial produce no seller-favourable notice
SELECT is(pg_temp.notes((SELECT t FROM _bw), 'Dispute resolved in your favour'), 0::bigint, 'N6: buyer-win — no "resolved in your favour"');
SELECT is(pg_temp.notes((SELECT t FROM _bw), 'Buyer confirmed receipt'), 0::bigint, 'N6: buyer-win — no "Buyer confirmed receipt"');
SELECT is(pg_temp.notes((SELECT t FROM _pr), 'Dispute resolved in your favour'), 0::bigint, 'N6: partial — no "resolved in your favour"');
SELECT is(pg_temp.notes((SELECT t FROM _pr), 'Buyer confirmed receipt'), 0::bigint, 'N6: partial — no "Buyer confirmed receipt"');

-- N2 also holds for a seller-win on a transfer whose hold is still pending
SELECT is(pg_temp.notes((SELECT t FROM _hm WHERE case_name = 'held_future'), 'Dispute resolved in your favour'), 1::bigint,
  'N2: a held seller-win is told the outcome too');
SELECT is(pg_temp.notes((SELECT t FROM _hm WHERE case_name = 'held_future'), 'Buyer confirmed receipt'), 0::bigint,
  'N1: …and is not told the buyer confirmed');

SELECT * FROM finish();
ROLLBACK;
