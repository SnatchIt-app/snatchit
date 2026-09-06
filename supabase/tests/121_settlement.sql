-- ============================================================================
-- 121_settlement.sql — Package 2 (PAYMENTS_RELIABILITY_2026-09).
--
-- Pins the ONE verified-settlement contract introduced by migration
-- 20260906110000_settle_verified_payment.sql (ratified decision 5):
--
--   * settle_verified_payment(...): service_role only. Every step is guarded
--     by CURRENT state, never by "did I run before": binding (amount /
--     currency / livemode / metadata) before any write; refund monotonicity
--     (a refunded row is never promoted; a refunded PaymentIntent ends
--     refunded); promotion only on Stripe `succeeded`; delegation to the
--     Package 1 core; non-settling outcomes recorded ONCE in webhook_retries
--     (the compensation / review queue).
--   * get_unsettled_payments(): the reconciliation sweep's work list —
--     paid-but-unsettled, stale pending, and unresolved unfulfillable rows.
--   * cleanup_expired_reservations(): never re-lists a listing that holds a
--     succeeded payment (investigation B §2 row 2 — the "second buyer 500-loops
--     forever" path).
--
-- Every fixture lives and dies inside this file's transaction. now() is frozen
-- for the transaction, so "old" timestamps are set explicitly.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(95);

SELECT tap.seed_core();

-- ── File-local fixtures (as postgres) ───────────────────────────────────────
-- 201: Buy-Now, reserved LIVE by buyer; pending payment 201 (the happy path).
-- 202: Buy-Now, reserved by buyer; payment 202 already REFUNDED (refund
--      arrived before the success event).
-- 203: Buy-Now, reserved by buyer; pending payment 203 — Stripe says succeeded
--      AND fully refunded in the same look-up.
-- 204: Buy-Now, reserved by buyer; pending payment 204 — binding / not
--      succeeded / canceled probes.
-- 205: SOLD to other_user's payment 291 (now refunded, its transfer exists);
--      buyer's late capture 205 is pending.
-- 206: Buy-Now, reserved by buyer; other_user already holds the listing's
--      one SUCCEEDED payment (292); buyer's capture 206 is pending.
-- 207: Buy-Now, reservation by buyer LAPSED; succeeded payment 207 paid 10 min
--      ago, no transfer (paid-but-unsettled; cleanup must not re-list it).
-- 208: Buy-Now, active; pending payment 208 created 20 min ago (stale pending).
-- 209: Buy-Now, reservation by other_user LAPSED, no payment (cleanup control).
-- 210: ended auction, winner buyer; pending auction payment 210.
-- 211: Buy-Now, active; pending payment 211 created just now (NOT stale).
-- Round-2 fixtures (review P2 round 1, MAJOR-1 / MINOR-3 / MINOR-4 / MINOR-5):
-- 212: Buy-Now, reserved by buyer; pending payment 212 — Stripe says succeeded
--      with a PARTIAL refund (500 of 22000): must still settle, no refund facts.
-- 213: Buy-Now, reserved by buyer; pending payment 213 — metadata uuids arrive
--      upper-case (client-echoed listing_id): must bind.
-- 214: Buy-Now, reserved by buyer; pending payment 214 — malformed metadata uuid.
-- 215: Buy-Now, reserved by buyer; PROCESSING payment 215 — canceled PI.
-- 216: SOLD to buyer's succeeded payment 216 with its transfer; an unresolved
--      'unfulfillable:manual_review' marker row (MINOR-4) must NOT be work.
-- 217: SOLD, succeeded payment 217 paid 10 min ago, NO transfer, stripe_livemode
--      NULL (pre-045 legacy row): listed as legacy_unknown_mode, never fetched.
-- 218: Buy-Now, active; pending payment 218 created 3 h ago (outside the
--      15 min .. 2 h pending_stale window).
-- 219: Buy-Now, active; pending payment 219 created 20 min ago, livemode NULL.
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time,
   ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
   buy_now_price, duration_hours, starts_at, ends_at, current_bid,
   cover_image_path, auction_status)
SELECT ('aaaaaaaa-0000-0000-0000-0000000002' || n)::uuid, tap.seller(),
       'Fixture 121-' || n, 'Club ' || n, 'wynwood', current_date + 30, '21:00',
       'GA', 2, 'mobile_transfer', 100, true, 200, 24, now(),
       now() + interval '24 hours', 100, 'fixtures/121-' || n || '.jpg', 'active'
  FROM unnest(ARRAY['01','02','03','04','05','06','07','08','09','10','11',
                    '12','13','14','15','16','17','18','19']) AS n;

SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status='reserved', reserved_by=tap.buyer(), reserved_until=now() + interval '5 minutes'
 WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000201','aaaaaaaa-0000-0000-0000-000000000202',
              'aaaaaaaa-0000-0000-0000-000000000203','aaaaaaaa-0000-0000-0000-000000000204',
              'aaaaaaaa-0000-0000-0000-000000000206',
              'aaaaaaaa-0000-0000-0000-000000000212','aaaaaaaa-0000-0000-0000-000000000213',
              'aaaaaaaa-0000-0000-0000-000000000214','aaaaaaaa-0000-0000-0000-000000000215');
UPDATE public.listings SET status='reserved', reserved_by=tap.buyer(), reserved_until=now() - interval '1 minute'
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000207';
UPDATE public.listings SET status='sold', auction_status='sold', sold_at=now()
 WHERE id IN ('aaaaaaaa-0000-0000-0000-000000000216','aaaaaaaa-0000-0000-0000-000000000217');
UPDATE public.listings SET status='reserved', reserved_by=tap.other_user(), reserved_until=now() - interval '1 minute'
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000209';
UPDATE public.listings SET status='sold', auction_status='sold', sold_at=now()
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000205';
UPDATE public.listings SET auction_status='ended', winner_user_id=tap.buyer(), winning_bid_amount=150, ends_at=now() - interval '1 minute'
 WHERE id = 'aaaaaaaa-0000-0000-0000-000000000210';
SELECT tap.reset_guards();

INSERT INTO public.payments
  (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
   stripe_payment_intent_id, status, mode, paid_at, refunded_at, stripe_refund_id, stripe_livemode, created_at)
VALUES
  ('bbbbbbbb-0000-0000-0000-000000000201', 'aaaaaaaa-0000-0000-0000-000000000201', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_201', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000202', 'aaaaaaaa-0000-0000-0000-000000000202', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_202', 'refunded',  'buy_now', now(), now(), 're_202', true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000203', 'aaaaaaaa-0000-0000-0000-000000000203', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_203', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000204', 'aaaaaaaa-0000-0000-0000-000000000204', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_204', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000291', 'aaaaaaaa-0000-0000-0000-000000000205', tap.other_user(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_291', 'refunded',  'buy_now', now(), now(), 're_291', true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000205', 'aaaaaaaa-0000-0000-0000-000000000205', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_205', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000292', 'aaaaaaaa-0000-0000-0000-000000000206', tap.other_user(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_292', 'succeeded', 'buy_now', now(), NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000206', 'aaaaaaaa-0000-0000-0000-000000000206', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_206', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000207', 'aaaaaaaa-0000-0000-0000-000000000207', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_207', 'succeeded', 'buy_now', now() - interval '10 minutes', NULL, NULL, true, now() - interval '12 minutes'),
  ('bbbbbbbb-0000-0000-0000-000000000208', 'aaaaaaaa-0000-0000-0000-000000000208', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_208', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now() - interval '20 minutes'),
  ('bbbbbbbb-0000-0000-0000-000000000210', 'aaaaaaaa-0000-0000-0000-000000000210', tap.buyer(),      tap.seller(), 15000, 1500, 1500, 16500, 'pi_121_210', 'pending',   'auction', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000211', 'aaaaaaaa-0000-0000-0000-000000000211', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_211', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000212', 'aaaaaaaa-0000-0000-0000-000000000212', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_212', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000213', 'aaaaaaaa-0000-0000-0000-000000000213', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_213', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000214', 'aaaaaaaa-0000-0000-0000-000000000214', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_214', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000215', 'aaaaaaaa-0000-0000-0000-000000000215', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_215', 'processing','buy_now', NULL,  NULL,  NULL,     true, now()),
  ('bbbbbbbb-0000-0000-0000-000000000216', 'aaaaaaaa-0000-0000-0000-000000000216', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_216', 'succeeded', 'buy_now', now() - interval '10 minutes', NULL, NULL, true, now() - interval '12 minutes'),
  ('bbbbbbbb-0000-0000-0000-000000000217', 'aaaaaaaa-0000-0000-0000-000000000217', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_217', 'succeeded', 'buy_now', now() - interval '10 minutes', NULL, NULL, NULL, now() - interval '12 minutes'),
  ('bbbbbbbb-0000-0000-0000-000000000218', 'aaaaaaaa-0000-0000-0000-000000000218', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_218', 'pending',   'buy_now', NULL,  NULL,  NULL,     true, now() - interval '3 hours'),
  ('bbbbbbbb-0000-0000-0000-000000000219', 'aaaaaaaa-0000-0000-0000-000000000219', tap.buyer(),      tap.seller(), 20000, 2000, 2000, 22000, 'pi_121_219', 'pending',   'buy_now', NULL,  NULL,  NULL,     NULL, now() - interval '20 minutes');

INSERT INTO public.transfers
  (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
VALUES
  ('cccccccc-0000-0000-0000-000000000291', 'aaaaaaaa-0000-0000-0000-000000000205', 'bbbbbbbb-0000-0000-0000-000000000291', tap.seller(), tap.other_user(), 'mobile_transfer', 'expired', now() - interval '1 hour'),
  ('cccccccc-0000-0000-0000-000000000216', 'aaaaaaaa-0000-0000-0000-000000000216', 'bbbbbbbb-0000-0000-0000-000000000216', tap.seller(), tap.buyer(),      'mobile_transfer', 'pending', now() + interval '20 hours');

-- MINOR-4: the sweep parks an unfulfillable capture that already carries a
-- transfer under this marker; it is an operator item, not sweep work.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES ('bbbbbbbb-0000-0000-0000-000000000216', 'aaaaaaaa-0000-0000-0000-000000000216', 'settle_verified_payment', 'unfulfillable:manual_review', false);

-- Metadata helper: what create-payment-intent stamps on every PaymentIntent.
CREATE FUNCTION pg_temp.meta(p_listing uuid, p_buyer uuid, p_mode text DEFAULT 'buy_now')
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('mode', p_mode, 'listing_id', p_listing::text,
                            'buyer_id', p_buyer::text, 'seller_id', tap.seller()::text)
$$;

-- ── A. happy path, twice — as the service role the edge functions use ───────
SELECT tap.login_service();
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome, transfer_id IS NOT NULL
       FROM public.settle_verified_payment('pi_121_201', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000201', tap.buyer()), 'webhook:evt_a1') $$,
  $$ VALUES ('succeeded'::text, 'sold'::text, 'settled'::text, true) $$,
  'A1 a verified succeeded PaymentIntent promotes the row, sells the listing and creates the transfer');
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome
       FROM public.settle_verified_payment('pi_121_201', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000201', tap.buyer()), 'webhook:evt_a2') $$,
  $$ VALUES ('succeeded'::text, 'sold'::text, 'already_settled'::text) $$,
  'A2 a second delivery (different event id) is already_settled');
SELECT tap.logout();
SELECT is((SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000201'),
  1::bigint, 'A3 ...exactly one transfer');
SELECT is(
  (SELECT t.id FROM public.transfers t WHERE t.payment_id = 'bbbbbbbb-0000-0000-0000-000000000201'),
  (SELECT s.transfer_id FROM public.settle_verified_payment('pi_121_201', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000201', tap.buyer()), 'sweep') s),
  'A4 ...the returned transfer_id is that transfer');
SELECT ok(
  (SELECT status = 'succeeded' AND paid_at IS NOT NULL AND payment_method = 'card'
     FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000201'),
  'A5 ...payment succeeded, paid_at and payment_method recorded');
SELECT ok(
  (SELECT status = 'sold' AND auction_status = 'sold' AND reserved_by IS NULL
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000201'),
  'A6 ...listing sold, reservation cleared');
SELECT is((SELECT count(*) FROM public.webhook_retries WHERE payment_id = 'bbbbbbbb-0000-0000-0000-000000000201'),
  0::bigint, 'A7 ...no review row for a clean settlement');

-- Auction mode settles through the same contract.
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome
       FROM public.settle_verified_payment('pi_121_210', 'succeeded', 16500, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000210', tap.buyer(), 'auction'), 'webhook:evt_a3') $$,
  $$ VALUES ('succeeded'::text, 'sold'::text, 'settled'::text) $$,
  'A8 the winner''s verified auction payment settles the auction');

-- ── B. refund-before-success: a refunded row is never promoted ──────────────
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome
       FROM public.settle_verified_payment('pi_121_202', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000202', tap.buyer()), 'webhook:evt_b1') $$,
  $$ VALUES ('refunded'::text, 'reserved'::text, 'refunded'::text) $$,
  'B1 a succeeded event for an already-REFUNDED row is outcome refunded (F05 closed)');
SELECT ok(
  (SELECT status = 'refunded' AND stripe_refund_id = 're_202' AND refunded_at IS NOT NULL
     FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000202'),
  'B2 ...refund facts untouched');
SELECT ok(
  (SELECT status = 'reserved' FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000202'),
  'B3 ...listing NOT sold');
SELECT is((SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000202'),
  0::bigint, 'B4 ...no transfer');

-- ── C. succeeded at Stripe but fully refunded: ends refunded, nothing sold ───
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome
       FROM public.settle_verified_payment('pi_121_203', 'succeeded', 22000, 'usd', true, 22000, 're_203', 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000203', tap.buyer()), 'confirm-payment') $$,
  $$ VALUES ('refunded'::text, 'reserved'::text, 'refunded'::text) $$,
  'C1 a pending row whose PaymentIntent is succeeded AND fully refunded ends refunded');
SELECT ok(
  (SELECT status = 'refunded' AND paid_at IS NOT NULL AND refunded_at IS NOT NULL AND stripe_refund_id = 're_203'
     FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000203'),
  'C2 ...transition went pending -> succeeded -> refunded (paid_at set, refund facts set)');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.buyer() FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000203'),
  'C3 ...listing untouched');
SELECT is((SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000203'),
  0::bigint, 'C4 ...no transfer');
SELECT results_eq(
  $$ SELECT payment_status, outcome
       FROM public.settle_verified_payment('pi_121_203', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000203', tap.buyer()), 'webhook:evt_c2') $$,
  $$ VALUES ('refunded'::text, 'refunded'::text) $$,
  'C5 a later plain succeeded event cannot un-refund it');
SELECT is(
  (SELECT count(*) FROM public.payment_refunds r
     WHERE r.payment_id = 'bbbbbbbb-0000-0000-0000-000000000203' AND r.stripe_refund_id = 're_203'
       AND r.amount_cents = 22000 AND r.source = 'dashboard'),
  1::bigint, 'C6 the full refund is ledgered through record_payment_refund (one payment_refunds row, source dashboard)');
SELECT is(
  (SELECT amount_refunded_cents FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000203'),
  22000, 'C7 ...amount_refunded_cents = total');

-- ── N. PARTIAL refund: a partially refunded succeeded charge is still a paid order
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome, transfer_id IS NOT NULL
       FROM public.settle_verified_payment('pi_121_212', 'succeeded', 22000, 'usd', true, 500, 're_212', 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000212', tap.buyer()), 'sweep') $$,
  $$ VALUES ('succeeded'::text, 'sold'::text, 'settled'::text, true) $$,
  'N1 a partial refund (500 of 22000) on a pending row still promotes AND settles (MAJOR-1)');
SELECT ok(
  (SELECT status = 'succeeded' AND refunded_at IS NULL AND stripe_refund_id IS NULL AND amount_refunded_cents IS NULL
     FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000212'),
  'N2 ...no refund fact is written by the contract on a partial refund');
SELECT is((SELECT count(*) FROM public.payment_refunds WHERE payment_id = 'bbbbbbbb-0000-0000-0000-000000000212'),
  0::bigint, 'N3 ...and nothing is ledgered');

-- ── D. binding mismatch: no writes, ONE review row ──────────────────────────
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_204', 'succeeded', 21000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'webhook:evt_d1')),
  'binding_mismatch', 'D1 wrong amount_received => binding_mismatch');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_204', 'succeeded', 21000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'webhook:evt_d1')),
  'binding_mismatch', 'D2 ...same delivery again => binding_mismatch');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_204', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.other_user()), 'webhook:evt_d3')),
  'binding_mismatch', 'D3 metadata.buyer_id that is not the row''s buyer => binding_mismatch');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_204', 'succeeded', 22000, 'usd', false, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'webhook:evt_d4')),
  'binding_mismatch', 'D4 livemode false against a live row => binding_mismatch');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_204', 'succeeded', 22000, 'eur', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'webhook:evt_d5')),
  'binding_mismatch', 'D5 non-usd currency => binding_mismatch');
SELECT ok(
  (SELECT status = 'pending' AND paid_at IS NULL FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000204'),
  'D6 ...payment untouched');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.buyer() FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000204'),
  'D7 ...listing untouched');
SELECT is((SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000204'),
  0::bigint, 'D8 ...no transfer');
SELECT is(
  (SELECT count(*) FROM public.webhook_retries
     WHERE payment_id = 'bbbbbbbb-0000-0000-0000-000000000204' AND rpc_name = 'settle_verified_payment'
       AND error_message LIKE 'binding_mismatch%' AND resolved IS NOT TRUE),
  1::bigint, 'D9 ...exactly ONE unresolved binding_mismatch review row across five mismatching calls');

-- ── O. metadata uuids are compared as uuids, not text (MINOR-3) ─────────────
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome
       FROM public.settle_verified_payment('pi_121_213', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              jsonb_build_object('mode', 'buy_now',
                                 'listing_id', upper('aaaaaaaa-0000-0000-0000-000000000213'),
                                 'buyer_id',   ' ' || upper(tap.buyer()::text) || ' ',
                                 'seller_id',  upper(tap.seller()::text)), 'webhook:evt_o1') $$,
  $$ VALUES ('succeeded'::text, 'sold'::text, 'settled'::text) $$,
  'O1 upper-case / padded metadata uuids bind to the row (uuid-normalized compare)');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_214', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              jsonb_build_object('mode', 'buy_now', 'listing_id', 'not-a-uuid', 'buyer_id', tap.buyer()::text), 'webhook:evt_o2')),
  'binding_mismatch', 'O2 a malformed metadata uuid is binding_mismatch');
SELECT ok(
  (SELECT status = 'pending' FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000214'),
  'O3 ...row untouched');

-- ── E. not succeeded: no writes ─────────────────────────────────────────────
SELECT results_eq(
  $$ SELECT payment_status, outcome
       FROM public.settle_verified_payment('pi_121_204', 'processing', 0, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'sweep') $$,
  $$ VALUES ('pending'::text, 'not_succeeded'::text) $$,
  'E1 a processing PaymentIntent is not_succeeded (amount binding only applies to a succeeded PI)');
SELECT results_eq(
  $$ SELECT payment_status, outcome
       FROM public.settle_verified_payment('pi_121_204', 'requires_payment_method', 0, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'sweep') $$,
  $$ VALUES ('pending'::text, 'not_succeeded'::text) $$,
  'E2 requires_payment_method is not_succeeded');
SELECT ok(
  (SELECT status = 'pending' AND paid_at IS NULL AND failed_at IS NULL
     FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000204'),
  'E3 ...payment untouched');

-- ── F. canceled: pending -> failed, idempotent ──────────────────────────────
SELECT results_eq(
  $$ SELECT payment_status, outcome
       FROM public.settle_verified_payment('pi_121_204', 'canceled', 0, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'webhook:evt_f1') $$,
  $$ VALUES ('failed'::text, 'canceled'::text) $$,
  'F1 a canceled PaymentIntent marks the pending row failed');
SELECT ok(
  (SELECT status = 'failed' AND failed_at IS NOT NULL FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000204'),
  'F2 ...failed_at recorded');
SELECT results_eq(
  $$ SELECT payment_status, outcome
       FROM public.settle_verified_payment('pi_121_204', 'canceled', 0, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000204', tap.buyer()), 'webhook:evt_f2') $$,
  $$ VALUES ('failed'::text, 'canceled'::text) $$,
  'F3 ...redelivery is still canceled, row stays failed');
SELECT ok(
  (SELECT status = 'reserved' FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000204'),
  'F4 ...the contract never releases a reservation (the webhook does that explicitly)');
SELECT results_eq(
  $$ SELECT payment_status, outcome
       FROM public.settle_verified_payment('pi_121_215', 'canceled', 0, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000215', tap.buyer()), 'webhook:evt_f5') $$,
  $$ VALUES ('failed'::text, 'canceled'::text) $$,
  'F5 a canceled PaymentIntent marks a PROCESSING row failed too (MINOR-4 C1)');

-- ── G. unfulfillable: listing already sold to a DIFFERENT payment ───────────
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome, transfer_id
       FROM public.settle_verified_payment('pi_121_205', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000205', tap.buyer()), 'webhook:evt_g1') $$,
  $$ VALUES ('succeeded'::text, 'sold'::text, 'unfulfillable'::text, NULL::uuid) $$,
  'G1 a verified capture for a listing sold to another payment is unfulfillable (payment promoted, nothing else)');
SELECT ok(
  (SELECT status = 'succeeded' AND paid_at IS NOT NULL FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000205'),
  'G2 ...the money fact (succeeded) is recorded so the sweep can refund it');
SELECT is((SELECT count(*) FROM public.transfers WHERE listing_id = 'aaaaaaaa-0000-0000-0000-000000000205'),
  1::bigint, 'G3 ...no second transfer');
SELECT is(
  (SELECT count(*) FROM public.webhook_retries
     WHERE payment_id = 'bbbbbbbb-0000-0000-0000-000000000205' AND error_message = 'unfulfillable:listing' AND resolved IS NOT TRUE),
  1::bigint, 'G4 ...one review row unfulfillable:listing');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_205', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000205', tap.buyer()), 'sweep')),
  'unfulfillable', 'G5 ...the sweep sees the same outcome');
SELECT is(
  (SELECT count(*) FROM public.webhook_retries
     WHERE payment_id = 'bbbbbbbb-0000-0000-0000-000000000205' AND error_message = 'unfulfillable:listing'),
  1::bigint, 'G6 ...and does not add a second review row');

-- ── H. unfulfillable: another payment already holds the listing''s one success
SELECT results_eq(
  $$ SELECT payment_status, listing_status, outcome
       FROM public.settle_verified_payment('pi_121_206', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000206', tap.buyer()), 'webhook:evt_h1') $$,
  $$ VALUES ('pending'::text, 'reserved'::text, 'unfulfillable'::text) $$,
  'H1 idx_payments_one_success_per_listing collision => unfulfillable, payment left pending');
SELECT is(
  (SELECT count(*) FROM public.webhook_retries
     WHERE payment_id = 'bbbbbbbb-0000-0000-0000-000000000206' AND error_message = 'unfulfillable:one_success_per_listing' AND resolved IS NOT TRUE),
  1::bigint, 'H2 ...one review row unfulfillable:one_success_per_listing');
SELECT ok(
  (SELECT status = 'succeeded' FROM public.payments WHERE id = 'bbbbbbbb-0000-0000-0000-000000000292'),
  'H3 ...the other buyer''s success is untouched');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.buyer() FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000206'),
  'H4 ...listing untouched');

-- ── I. unknown PaymentIntent ────────────────────────────────────────────────
SELECT results_eq(
  $$ SELECT payment_id, payment_status, outcome
       FROM public.settle_verified_payment('pi_121_nope', 'succeeded', 22000, 'usd', true, 0, NULL, 'card', '{}'::jsonb, 'webhook:evt_i1') $$,
  $$ VALUES (NULL::uuid, NULL::text, 'unknown_payment'::text) $$,
  'I1 a PaymentIntent with no payments row is unknown_payment');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_nope', 'succeeded', 22000, 'usd', true, 0, NULL, 'card', '{}'::jsonb, 'webhook:evt_i2')),
  'unknown_payment', 'I2 ...again');
SELECT is(
  (SELECT count(*) FROM public.webhook_retries
     WHERE payment_id IS NULL AND rpc_name = 'settle_verified_payment'
       AND error_message LIKE 'unknown_payment:pi_121_nope%' AND resolved IS NOT TRUE),
  1::bigint, 'I3 ...exactly one review row keyed on the PaymentIntent id');

-- ── J. get_unsettled_payments — the sweep''s work list ───────────────────────
SELECT tap.login_service();
SELECT ok(
  EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u
           WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000207' AND u.kind = 'paid_unsettled'
             AND u.stripe_payment_intent_id = 'pi_121_207' AND u.mode = 'buy_now' AND u.status = 'succeeded'),
  'J1 a succeeded payment paid > 5 min ago with no transfer is paid_unsettled');
SELECT ok(
  EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u
           WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000205' AND u.kind = 'review_unfulfillable'),
  'J2 an unresolved unfulfillable review row surfaces its payment as review_unfulfillable');
SELECT ok(
  EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u
           WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000206' AND u.kind = 'review_unfulfillable'),
  'J3 ...including the one-success collision (payment still pending)');
SELECT ok(
  EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u
           WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000208' AND u.kind = 'pending_stale'),
  'J4 a pending row created > 15 min ago with a PaymentIntent is pending_stale');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000201'),
  'J5 a settled payment (listing sold, transfer exists) is NOT listed');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000211'),
  'J6 a pending row created just now is NOT listed');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u WHERE u.payment_id IN ('bbbbbbbb-0000-0000-0000-000000000202','bbbbbbbb-0000-0000-0000-000000000203')),
  'J7 refunded rows are NOT listed');
SELECT is(
  (SELECT count(*) FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000205'),
  1::bigint, 'J8 a payment is listed once even when it matches two kinds');
SELECT is((SELECT count(*) FROM public.get_unsettled_payments(1)), 1::bigint, 'J9 p_limit is honoured');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000216'),
  'J10 an unfulfillable:manual_review marker row is an operator item, not sweep work (MINOR-4)');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000218'),
  'J11 a pending row created 3 h ago is outside the pending_stale window (MINOR-5)');
SELECT is(
  (SELECT u.kind FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000217'),
  'legacy_unknown_mode', 'J12 a paid-unsettled row with stripe_livemode NULL is legacy_unknown_mode, never paid_unsettled');
SELECT is(
  (SELECT u.kind FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000219'),
  'legacy_unknown_mode', 'J13 a stale pending row with stripe_livemode NULL is legacy_unknown_mode, never pending_stale');
SELECT ok(
  (SELECT bool_and(u.kind IN ('review_unfulfillable','paid_unsettled','pending_stale')) FROM public.get_unsettled_payments(50) u
     JOIN public.payments p ON p.id = u.payment_id WHERE p.stripe_livemode IS NOT NULL),
  'J14 every live row keeps its real kind (legacy_unknown_mode is only for NULL livemode)');
SELECT tap.logout();

-- ── K. cleanup_expired_reservations never re-lists a paid listing ───────────
SELECT lives_ok($$ SELECT public.cleanup_expired_reservations() $$, 'K1 cleanup runs');
SELECT ok(
  (SELECT status = 'reserved' AND reserved_by = tap.buyer() FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000207'),
  'K2 a lapsed reservation whose holder has a SUCCEEDED payment is left untouched (N1)');
SELECT ok(
  (SELECT status = 'active' AND reserved_by IS NULL AND reserved_until IS NULL
     FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000209'),
  'K3 a lapsed reservation with no payment is released as before');
SELECT ok(
  (SELECT status = 'reserved' FROM public.listings WHERE id = 'aaaaaaaa-0000-0000-0000-000000000204'),
  'K4 a live reservation is untouched');
-- ...and the paid-unsettled row still settles afterwards (money wins).
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_207', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000207', tap.buyer()), 'sweep')),
  'settled', 'K5 the sweep settles the paid-but-unsettled row');
SELECT ok(
  NOT EXISTS (SELECT 1 FROM public.get_unsettled_payments(50) u WHERE u.payment_id = 'bbbbbbbb-0000-0000-0000-000000000207'),
  'K6 ...and it leaves the work list');

-- ── L. grant posture and shape ──────────────────────────────────────────────
SELECT ok(has_function_privilege('service_role', 'public.settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)', 'EXECUTE'),
  'L1 settle_verified_payment: EXECUTE for service_role');
SELECT ok(NOT has_function_privilege('anon', 'public.settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)', 'EXECUTE'),
  'L2 settle_verified_payment: no EXECUTE for anon');
SELECT ok(NOT has_function_privilege('authenticated', 'public.settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)', 'EXECUTE'),
  'L3 settle_verified_payment: no EXECUTE for authenticated');
SELECT ok(
  (SELECT p.proacl IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      AND p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres' AND 'search_path=public' = ANY (p.proconfig)
     FROM pg_proc p WHERE p.oid = 'public.settle_verified_payment(text,text,integer,text,boolean,integer,text,text,jsonb,text)'::regprocedure),
  'L4 settle_verified_payment: explicit ACL, no PUBLIC, SECURITY DEFINER, owner postgres, search_path pinned');
SELECT ok(has_function_privilege('service_role', 'public.get_unsettled_payments(integer)', 'EXECUTE'),
  'L5 get_unsettled_payments: EXECUTE for service_role');
SELECT ok(NOT has_function_privilege('anon', 'public.get_unsettled_payments(integer)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.get_unsettled_payments(integer)', 'EXECUTE'),
  'L6 get_unsettled_payments: no EXECUTE for anon / authenticated');
SELECT ok(
  (SELECT p.proacl IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
      AND p.prosecdef AND pg_get_userbyid(p.proowner) = 'postgres' AND 'search_path=public' = ANY (p.proconfig)
     FROM pg_proc p WHERE p.oid = 'public.get_unsettled_payments(integer)'::regprocedure),
  'L7 get_unsettled_payments: explicit ACL, no PUBLIC, SECURITY DEFINER, owner postgres, search_path pinned');
SELECT ok(has_function_privilege('service_role', 'public.cleanup_expired_reservations()', 'EXECUTE')
      AND NOT has_function_privilege('anon', 'public.cleanup_expired_reservations()', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.cleanup_expired_reservations()', 'EXECUTE'),
  'L8 cleanup_expired_reservations: posture unchanged (service_role only)');
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT * FROM public.settle_verified_payment('pi_121_201', 'succeeded', 22000, 'usd', true, 0, NULL, 'card', '{}'::jsonb, 'x') $$,
  '42501', NULL, 'L9 authenticated cannot call settle_verified_payment');
SELECT throws_ok(
  $$ SELECT * FROM public.get_unsettled_payments(50) $$,
  '42501', NULL, 'L10 authenticated cannot call get_unsettled_payments');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok(
  $$ SELECT * FROM public.settle_verified_payment('pi_121_201', 'succeeded', 22000, 'usd', true, 0, NULL, 'card', '{}'::jsonb, 'x') $$,
  '42501', NULL, 'L11 anon cannot call settle_verified_payment');
SELECT throws_ok(
  $$ SELECT * FROM public.get_unsettled_payments(50) $$,
  '42501', NULL, 'L12 anon cannot call get_unsettled_payments');
SELECT tap.logout();

-- ── M. invariant: after settlement no succeeded payment sits on an unsold
--       listing without a review row (the sweep's contract).
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_292', 'succeeded', 22000, 'usd', true, 0, NULL, 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000206', tap.other_user()), 'sweep')),
  'settled', 'M1 the other buyer''s earlier success settles listing 206 even though buyer holds the live hold (money wins)');
SELECT is(
  (SELECT count(*) FROM public.payments p JOIN public.listings l ON l.id = p.listing_id
     WHERE p.stripe_payment_intent_id LIKE 'pi_121_%' AND p.status = 'succeeded' AND l.status <> 'sold'
       AND NOT EXISTS (SELECT 1 FROM public.webhook_retries w WHERE w.payment_id = p.id AND w.resolved IS NOT TRUE)),
  0::bigint, 'M2 every 121 succeeded payment is either settled or queued for review');

-- ── Review round 2 (converged RC) ───────────────────────────────────────────
-- R2-A (MAJOR-1): a kernel-rail row (093 shape: mode native_primary, listing_id
-- and seller_id NULL) is never settled here — no writes, no review row.
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, stripe_livemode)
VALUES ('aaaaaaaa-0000-0000-0000-00000000f121', NULL, tap.other_user(), NULL, 5000, 0, 0, 5000,
        'pi_121_native', 'pending', 'native_primary', true);
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_native', 'succeeded', 5000, 'usd', true, 0, NULL, 'card', '{}'::jsonb, 'webhook')),
  'not_external_rail', 'R2-A a native_primary row yields not_external_rail');
SELECT is(
  (SELECT status FROM public.payments WHERE stripe_payment_intent_id = 'pi_121_native'), 'pending',
  'R2-A …and is not promoted');
SELECT is(
  (SELECT count(*) FROM public.webhook_retries w WHERE w.payment_id = 'aaaaaaaa-0000-0000-0000-00000000f121'), 0::bigint,
  'R2-A …and no review row is written');
-- R2-B (MINOR-4): the contract ledgers the INCREMENT under the newest refund id,
-- never Stripe's cumulative figure — 212 (settled, partial 500 already ledgered
-- by charge.refunded) then fully refunded at Stripe: 500 + 21500 = 22000.
SELECT is((public.record_payment_refund('pi_121_212', 're_212a', NULL, 500, 'dashboard'))->>'amount_refunded_cents', '500',
  'R2-B fixture: charge.refunded ledgered the first partial refund (500)');
SELECT is(
  (SELECT outcome FROM public.settle_verified_payment('pi_121_212', 'succeeded', 22000, 'usd', true, 22000, 're_212b', 'card',
              pg_temp.meta('aaaaaaaa-0000-0000-0000-000000000212', tap.buyer()), 'webhook')),
  'refunded', 'R2-B full refund observed (cumulative 22000 under the newest id re_212b) ⇒ refunded');
SELECT is(
  (SELECT sum(amount_cents) FROM public.payment_refunds pr JOIN public.payments p ON p.id = pr.payment_id
    WHERE p.stripe_payment_intent_id = 'pi_121_212'), 22000::bigint,
  'R2-B the ledger sums to the total — 500 (re_212a) + 21500 (re_212b increment), not 500 + 22000');

SELECT * FROM finish();
ROLLBACK;
