-- ============================================================================
-- 217_refund_lifecycle_state.sql — refund lifecycle accuracy (migration
-- 20260925000000, registry 150). Design: docs/release/REFUND_LIFECYCLE_TRACE_AND_FIX_20260924.md.
--
-- A Stripe refund has its own state (pending, requires_action, succeeded,
-- failed, canceled) that can move in any direction for ~30 days; a card refund
-- can report succeeded and later fail (docs.stripe.com/testing). Before 150 the
-- only writer, record_payment_refund, took no status: a pending, failed or
-- canceled refund was recorded as money returned, and the one-way guard on
-- payments (20260906120000) made a later failure unrecordable.
--
-- Under test:
--   S  objects, grants, RLS, the seeded switch (off);
--   W  record_refund_state: counting only pending/requires_action/succeeded,
--      the three sums, a failure after success, first-seen failures never
--      counted, idempotency, unknown payments, input validation;
--   G  the payments refund-state columns move only through the writer; the
--      state log is append-only;
--   D  ops.detect_refunds: the new branches are off by default; on, a failed
--      Stripe refund opens refund_failed (per refund), a covering succeeded
--      refund clears it, a human close suppresses re-detection, a stale pending
--      refund opens refund_pending, and 118's owed-refund branch is unchanged.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(41);
SELECT tap.seed_core();
SELECT tap.logout();

-- ── fixtures (transaction-local) ────────────────────────────────────────────
-- One live, succeeded payment per case (total 11000 unless given).
CREATE FUNCTION tap._p217(n int, p_total int DEFAULT 11000) RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE
  v_l uuid := ('dddddddd-0000-0000-0217-' || lpad(n::text, 12, '0'))::uuid;
  v_p uuid := ('eeeeeeee-0000-0000-0217-' || lpad(n::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
     transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
     current_bid, cover_image_path, auction_status)
  VALUES (v_l, tap.seller(), 'RL Event ' || n, 'Club', 'wynwood', current_date + 30, '21:00', 'GA', 1,
          'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/rl.jpg', 'active');
  INSERT INTO public.payments
    (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id,
     status, mode, paid_at, stripe_livemode)
  VALUES (v_p, v_l, tap.buyer(), tap.seller(), p_total - p_total / 11, p_total / 11, p_total / 11, p_total,
          'pi_rl_' || n, 'succeeded', 'buy_now', now(), true);
  RETURN v_p;
END $f$;
CREATE FUNCTION tap._pid217(n int) RETURNS uuid LANGUAGE sql AS $f$
  SELECT ('eeeeeeee-0000-0000-0217-' || lpad(n::text, 12, '0'))::uuid $f$;
-- the writer, called as the service role exactly as the edge functions call it
CREATE FUNCTION tap._rs(n int, p_re text, p_status text, p_amount int, p_fail text DEFAULT NULL,
                        p_source text DEFAULT 'expiry', p_via text DEFAULT 'webhook') RETURNS jsonb
LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM tap.login_service();
  v := public.record_refund_state('pi_rl_' || n, p_re, p_status, p_amount, p_fail, p_source, p_via);
  PERFORM tap.logout();
  RETURN v;
END $f$;
CREATE FUNCTION tap._pay217(n int) RETURNS public.payments LANGUAGE sql AS $f$
  SELECT * FROM public.payments WHERE id = tap._pid217(n) $f$;
CREATE FUNCTION tap._run217() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v jsonb;
BEGIN
  PERFORM tap.login_service();
  v := ops.run_job('refunds', 'test');
  PERFORM tap.logout();
  RETURN v;
END $f$;
CREATE FUNCTION tap._case217(p_key text) RETURNS ops."case" LANGUAGE sql AS $f$
  SELECT c.* FROM ops."case" c WHERE c.dedupe_key = p_key AND c.status NOT IN ('resolved','dismissed') $f$;

-- ── S — structure, grants, the switch ───────────────────────────────────────
SELECT has_table('public', 'payment_refund_state', 'S1: public.payment_refund_state exists');
SELECT has_table('public', 'payment_refund_state_log', 'S2: public.payment_refund_state_log exists');
SELECT ok((SELECT count(*) = 3 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'payments'
              AND column_name IN ('refund_requested_cents','refund_succeeded_cents','refund_failed_cents')
              AND is_nullable = 'NO' AND column_default = '0'),
  'S3: payments carries refund_requested/succeeded/failed_cents, NOT NULL DEFAULT 0');
SELECT ok((SELECT p.prosecdef AND p.proconfig = ARRAY['search_path=""']
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'record_refund_state'),
  'S4: record_refund_state is SECURITY DEFINER with search_path=''''');
SELECT ok(NOT has_function_privilege('anon', 'public.record_refund_state(text,text,text,integer,text,text,text)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.record_refund_state(text,text,text,integer,text,text,text)', 'EXECUTE')
      AND has_function_privilege('service_role', 'public.record_refund_state(text,text,text,integer,text,text,text)', 'EXECUTE'),
  'S5: only service_role may execute record_refund_state');
SELECT ok(NOT has_table_privilege('anon', 'public.payment_refund_state', 'SELECT')
      AND NOT has_table_privilege('authenticated', 'public.payment_refund_state', 'SELECT')
      AND NOT has_table_privilege('authenticated', 'public.payment_refund_state_log', 'SELECT')
      AND NOT has_table_privilege('anon', 'public.payment_refund_state_log', 'INSERT'),
  'S6: clients hold no privilege on the state tables');
SELECT ok((SELECT bool_and(c.relrowsecurity) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname IN ('payment_refund_state','payment_refund_state_log')),
  'S7: RLS is enabled on both state tables');
SELECT is((SELECT value FROM ops.setting WHERE key = 'refund_state_detection_enabled'), 'false'::jsonb,
  'S8: refund_state_detection_enabled is seeded false (the owner flips it)');
SELECT is((SELECT value FROM ops.setting WHERE key = 'refund_state_pending_hours'), '120'::jsonb,
  'S9: refund_state_pending_hours is seeded 120');

-- ── W — the writer ──────────────────────────────────────────────────────────
SELECT tap._p217(1);
SELECT is(tap._rs(1, 're_rl_1', 'pending', 11000, NULL, 'expiry', 'create_response') ->> 'recorded', 'true',
  'W1: a pending refund is recorded');
SELECT ok((SELECT amount_refunded_cents = 11000 AND status = 'refunded'
                  AND refund_requested_cents = 11000 AND refund_succeeded_cents = 0 AND refund_failed_cents = 0
             FROM tap._pay217(1)),
  'W2: pending is COUNTED (one-way record, payout blocked) and sits in the requested sum, not succeeded');
SELECT is((SELECT count(*)::int FROM public.payment_refunds WHERE stripe_refund_id = 're_rl_1'), 1,
  'W3: exactly one payment_refunds row for the counted refund');
SELECT tap._rs(1, 're_rl_1', 'pending', 11000);
SELECT is((SELECT count(*)::int FROM public.payment_refund_state_log WHERE stripe_refund_id = 're_rl_1'), 1,
  'W4: re-observing the same state is idempotent (no new log row)');
SELECT tap._rs(1, 're_rl_1', 'succeeded', 11000);
SELECT ok((SELECT refund_requested_cents = 0 AND refund_succeeded_cents = 11000 AND refund_failed_cents = 0
             FROM tap._pay217(1)),
  'W5: succeeded moves the amount from requested to succeeded');
SELECT tap._rs(1, 're_rl_1', 'failed', 11000, 'expired_or_canceled_card');
SELECT ok((SELECT refund_succeeded_cents = 0 AND refund_failed_cents = 11000 FROM tap._pay217(1)),
  'W6: a failure AFTER success is recorded: failed = 11000, succeeded = 0');
SELECT ok((SELECT amount_refunded_cents = 11000 AND status = 'refunded' AND refunded_at IS NOT NULL FROM tap._pay217(1)),
  'W7: the one-way record is untouched by the later failure (guard holds; payout stays blocked)');
SELECT is((SELECT status || '/' || coalesce(failure_reason, '-') FROM public.payment_refund_state WHERE stripe_refund_id = 're_rl_1'),
  'failed/expired_or_canceled_card', 'W8: the state row carries Stripe''s status and failure_reason');
SELECT is((SELECT string_agg(status, ',' ORDER BY id) FROM public.payment_refund_state_log WHERE stripe_refund_id = 're_rl_1'),
  'pending,succeeded,failed', 'W9: the log holds every observed change, in order');

SELECT tap._p217(2, 5000);
SELECT tap._rs(2, 're_rl_2', 'failed', 5000, 'declined', 'expiry', 'create_response');
SELECT ok((SELECT status = 'succeeded' AND amount_refunded_cents IS NULL AND refunded_at IS NULL
                  AND refund_failed_cents = 5000 AND refund_requested_cents = 0 FROM tap._pay217(2)),
  'W10: a refund FIRST seen failed is never counted (payment stays succeeded; failed = 5000)');
SELECT is((SELECT count(*)::int FROM public.payment_refunds WHERE stripe_refund_id = 're_rl_2'), 0,
  'W11: …and writes no payment_refunds row');

SELECT tap._p217(3);
SELECT tap._rs(3, 're_rl_3', 'canceled', 11000, 'merchant_request');
SELECT ok((SELECT status = 'succeeded' AND amount_refunded_cents IS NULL AND refund_failed_cents = 11000 FROM tap._pay217(3)),
  'W12: a canceled refund is not counted and sits in the failed sum');

SELECT tap._p217(4);
SELECT tap._rs(4, 're_rl_4', 'requires_action', 4000, NULL, 'dashboard');
SELECT ok((SELECT status = 'succeeded' AND amount_refunded_cents = 4000 AND refund_requested_cents = 4000 FROM tap._pay217(4)),
  'W13: a partial requires_action refund counts toward the one-way record and sits in requested');

SELECT is(tap._rs(99, 're_rl_99', 'succeeded', 100) ->> 'recorded', 'false',
  'W14: an unknown PaymentIntent is acknowledged, not recorded');
SELECT is((SELECT count(*)::int FROM public.payment_refund_state WHERE stripe_refund_id = 're_rl_99'), 0,
  'W15: …and leaves no state row');
SELECT throws_ok($$ SELECT tap._rs(1, 're_rl_bad', 'refunded', 100) $$, 'P0001', 'INVALID_REFUND_STATUS',
  'W16: a status outside Stripe''s five raises INVALID_REFUND_STATUS');
SELECT throws_ok($$ SELECT tap._rs(1, 're_rl_bad', 'pending', 100, NULL, 'expiry', 'guess') $$, 'P0001', 'INVALID_OBSERVATION_SOURCE',
  'W17: an unknown observed_via raises INVALID_OBSERVATION_SOURCE');
SELECT throws_ok($$ SELECT tap._rs(1, NULL, 'pending', 100) $$, 'P0001', 'REFUND_REFERENCE_REQUIRED',
  'W18: a missing refund id raises REFUND_REFERENCE_REQUIRED');

-- ── G — guards ──────────────────────────────────────────────────────────────
SELECT throws_ok($$ UPDATE public.payments SET refund_succeeded_cents = 11000 WHERE id = tap._pid217(2) $$,
  'P0001', 'payments refund-state columns are written only by record_refund_state (150).', 'G1: a direct write to a refund-state column is refused (only the writer may set them)');
SELECT throws_ok($$ UPDATE public.payment_refund_state_log SET status = 'succeeded' WHERE stripe_refund_id = 're_rl_1' $$,
  'P0001', 'payment_refund_state_log is append-only (150).', 'G2: the state log refuses UPDATE');
SELECT throws_ok($$ DELETE FROM public.payment_refund_state_log WHERE stripe_refund_id = 're_rl_1' $$,
  'P0001', 'payment_refund_state_log is append-only (150).', 'G3: the state log refuses DELETE');
SELECT ok((SELECT refund_succeeded_cents = 0 FROM tap._pay217(2)), 'G4: the refused write changed nothing');

-- ── D — the detector ────────────────────────────────────────────────────────
SELECT tap._run217();
SELECT ok((tap._case217('refund_failed:re_rl_1')).id IS NULL AND (tap._case217('refund_failed:re_rl_2')).id IS NULL,
  'D1: with the switch off, no Stripe-state case opens');
UPDATE ops.setting SET value = 'true'::jsonb WHERE key = 'refund_state_detection_enabled';
SELECT tap._run217();
SELECT ok((tap._case217('refund_failed:re_rl_1')).priority = 'p1'
      AND (tap._case217('refund_failed:re_rl_1')).subject_kind = 'payment',
  'D2: a refund that failed after success opens a p1 refund_failed case keyed by the refund');
SELECT ok((tap._case217('refund_failed:re_rl_2')).id IS NOT NULL AND (tap._case217('refund_failed:re_rl_3')).id IS NOT NULL,
  'D3: first-seen failed and canceled refunds open cases too');
SELECT ok(position('re_rl_1' IN (tap._case217('refund_failed:re_rl_1')).summary) > 0
      AND position('pi_rl_1' IN (tap._case217('refund_failed:re_rl_1')).summary) > 0,
  'D4: the case names the refund and the PaymentIntent');
-- a later refund that succeeds for the full total clears payment 2's failure
SELECT tap._rs(2, 're_rl_2b', 'succeeded', 5000, NULL, 'dashboard');
SELECT tap._run217();
SELECT ok((tap._case217('refund_failed:re_rl_2')).id IS NULL
      AND (SELECT count(*) FROM ops."case" WHERE dedupe_key = 'refund_failed:re_rl_2' AND status = 'resolved' AND resolved_by IS NULL) = 1,
  'D5: a covering succeeded refund auto-resolves the case (condition cleared)');
-- an operator closes payment 3's case by hand: the detector must not reopen it
UPDATE ops."case" SET status = 'resolved', resolved_at = now(), resolved_by = tap.admin_user()
 WHERE dedupe_key = 'refund_failed:re_rl_3' AND status NOT IN ('resolved','dismissed');
SELECT tap._run217();
SELECT ok((tap._case217('refund_failed:re_rl_3')).id IS NULL,
  'D6: a case a human closed is not re-opened while the same refund stays failed');
-- a refund pending at Stripe longer than refund_state_pending_hours
SELECT tap._p217(5);
SELECT tap._rs(5, 're_rl_5', 'pending', 11000, NULL, 'dashboard');
UPDATE public.payment_refund_state SET first_observed_at = now() - interval '121 hours' WHERE stripe_refund_id = 're_rl_5';
SELECT tap._run217();
SELECT ok((tap._case217('refund_pending:re_rl_5')).priority = 'p1',
  'D7: a refund still pending past refund_state_pending_hours opens refund_pending keyed by the refund');
SELECT tap._rs(5, 're_rl_5', 'succeeded', 11000, NULL, 'dashboard');
SELECT tap._run217();
SELECT ok((tap._case217('refund_pending:re_rl_5')).id IS NULL,
  'D8: …and clears once it succeeds');
-- 118's owed-refund branch is unchanged: an expired order with a succeeded payment and no refund
SELECT tap._p217(6);
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at, expired_at)
VALUES ('ffffffff-0000-0000-0217-000000000006', 'dddddddd-0000-0000-0217-000000000006', tap._pid217(6),
        tap.seller(), tap.buyer(), 'mobile_transfer', 'expired', now() - interval '3 hours', now() - interval '2 hours');
SELECT tap._run217();
SELECT ok((tap._case217('refund_pending:' || tap._pid217(6)::text)).id IS NOT NULL,
  'D9: 118''s owed-refund branch still opens refund_pending keyed by the payment');
SELECT ok((tap._case217('refund_failed:re_rl_1')).id IS NOT NULL,
  'D10: the Stripe-state and owed-refund branches do not resolve each other''s cases');

SELECT * FROM finish();
ROLLBACK;
