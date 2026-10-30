-- ============================================================================
-- 123_payment_monotonic.sql — refund/dispute facts on payments are monotonic
-- (migration 20260906120000): every legitimate writer transition still lives
-- (webhook succeeded/failed claims, confirm-payment, create-payment-intent
-- retire, enforce-transfer-expiry refund, delete_account_cleanup
-- anonymization), refunded is TERMINAL, money/identity columns are immutable
-- once succeeded (060 F-3), refund references never change once set,
-- amount_refunded_cents never decreases, payment_refunds is append-only, and
-- record_payment_refund() is idempotent, partial-aware, and never writes a
-- dispute id into stripe_refund_id (a chargeback is not a refund).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(53);
SELECT tap.seed_core();
SELECT tap.logout();

-- ── Schema ──────────────────────────────────────────────────────────────────
SELECT has_column('public'::name, 'payments'::name, 'amount_refunded_cents'::name, 'payments.amount_refunded_cents exists');
SELECT has_table('public'::name, 'payment_refunds'::name, 'payment_refunds exists');
SELECT has_trigger('public'::name, 'payments'::name, 'trg_guard_payment_transitions'::name, 'payments has the transition guard');

-- ── Every existing writer transition still lives ────────────────────────────
-- payment D is the pending fixture; walk it through the lifecycle.
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'processing' WHERE id = tap.payment_d() $$,
  'pending -> processing');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'failed' WHERE stripe_payment_intent_id = 'pi_fixture_d'
       AND status <> 'succeeded' AND status <> 'refunded' $$,
  'processing -> failed (stripe-webhook payment_intent.payment_failed claim shape)');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'succeeded', paid_at = now()
      WHERE stripe_payment_intent_id = 'pi_fixture_d' AND status <> 'succeeded' $$,
  'failed -> succeeded (stripe-webhook payment_intent.succeeded claim shape; PaymentSheet retry)');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'succeeded', paid_at = now(), payment_method = 'card'
      WHERE stripe_payment_intent_id = 'pi_fixture_d' AND buyer_id = tap.buyer() $$,
  'succeeded -> succeeded with payment_method (confirm-payment shape, no status predicate)');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'refunded', refunded_at = now(), stripe_refund_id = 're_d1'
      WHERE id = tap.payment_d() $$,
  'succeeded -> refunded with refund facts (enforce-transfer-expiry Phase 1 shape)');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'refunded', refunded_at = now(), stripe_refund_id = 're_d1'
      WHERE id = tap.payment_d() AND status = 'succeeded' $$,
  'Phase 1b shape on an already-refunded row matches zero rows and lives');
SELECT lives_ok(
  $$ UPDATE public.payments SET stripe_livemode = false WHERE id = tap.payment_d() $$,
  'quarantine (stripe_livemode) is not a guarded column');

-- refunded is TERMINAL: the redelivered payment_intent.succeeded claim must throw.
SELECT throws_like(
  $$ UPDATE public.payments SET status = 'succeeded', paid_at = now()
      WHERE stripe_payment_intent_id = 'pi_fixture_d' AND status <> 'succeeded' $$,
  '%refunded is terminal%',
  'refunded -> succeeded THROWS (F05: a replayed webhook cannot un-refund)');
SELECT throws_like(
  $$ UPDATE public.payments SET status = 'failed' WHERE id = tap.payment_d() $$,
  '%refunded is terminal%', 'refunded -> failed THROWS');
SELECT throws_like(
  $$ UPDATE public.payments SET status = 'pending' WHERE id = tap.payment_a() $$,
  '%not allowed%', 'succeeded -> pending THROWS');
SELECT throws_like(
  $$ UPDATE public.payments SET status = 'failed' WHERE id = tap.payment_a() $$,
  '%not allowed%', 'succeeded -> failed THROWS (late payment_failed cannot freeze a paid order)');

-- pending -> failed (create-payment-intent retire) and pending -> succeeded on
-- a fresh pending row.
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode)
VALUES ('bbbbbbbb-0000-0000-0000-000000000009', tap.listing_d(), tap.other_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_x', 'pending', 'buy_now');
SELECT lives_ok(
  $$ UPDATE public.payments SET amount = 9000, total = 9900, buyer_fee = 900
      WHERE id = 'bbbbbbbb-0000-0000-0000-000000000009' $$,
  'amounts are still writable while pending (server-side repricing before capture)');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'failed'
      WHERE id = 'bbbbbbbb-0000-0000-0000-000000000009' AND status = 'pending' $$,
  'pending -> failed (create-payment-intent retire shape)');
SELECT lives_ok(
  $$ UPDATE public.payments SET status = 'pending'
      WHERE id = 'bbbbbbbb-0000-0000-0000-000000000009' $$,
  'failed -> pending (fresh PI minted for the same row)');

-- ── Money / identity columns are immutable once succeeded (060 F-3) ─────────
SELECT throws_like(
  $$ UPDATE public.payments SET amount = 1, total = 1 WHERE id = tap.payment_a() $$,
  '%immutable once succeeded%', 'amount/total cannot be rewritten on a succeeded payment');
SELECT throws_like(
  $$ UPDATE public.payments SET seller_fee = 0 WHERE id = tap.payment_a() $$,
  '%immutable once succeeded%', 'seller_fee cannot be rewritten');
SELECT throws_like(
  $$ UPDATE public.payments SET stripe_payment_intent_id = 'pi_other' WHERE id = tap.payment_a() $$,
  '%immutable once succeeded%', 'stripe_payment_intent_id cannot be rewritten');
SELECT throws_like(
  $$ UPDATE public.payments SET mode = 'auction' WHERE id = tap.payment_a() $$,
  '%immutable once succeeded%', 'mode cannot be rewritten');
SELECT throws_like(
  $$ UPDATE public.payments SET listing_id = tap.listing_c() WHERE id = tap.payment_a() $$,
  '%immutable once succeeded%', 'listing_id cannot be rewritten');
SELECT throws_like(
  $$ UPDATE public.payments SET buyer_id = tap.other_user() WHERE id = tap.payment_a() $$,
  '%immutable once succeeded%', 'buyer_id cannot be moved to another real user');
SELECT is((SELECT amount FROM public.payments WHERE id = tap.payment_a()), 10000, 'amount untouched');

-- ── Refund references never change once set ─────────────────────────────────
SELECT lives_ok(
  $$ UPDATE public.payments SET stripe_refund_id = 're_a1' WHERE id = tap.payment_a() $$,
  'first refund id can be recorded');
SELECT lives_ok(
  $$ UPDATE public.payments SET stripe_refund_id = 're_a1' WHERE id = tap.payment_a() $$,
  'same refund id is a no-op');
SELECT throws_like(
  $$ UPDATE public.payments SET stripe_refund_id = 're_a2' WHERE id = tap.payment_a() $$,
  '%refund facts are monotonic%', 'a different refund id is refused');
SELECT throws_like(
  $$ UPDATE public.payments SET stripe_refund_id = NULL WHERE id = tap.payment_a() $$,
  '%refund facts are monotonic%', 'a refund id cannot be cleared');
SELECT lives_ok(
  $$ UPDATE public.payments SET amount_refunded_cents = 5000 WHERE id = tap.payment_a() $$,
  'amount_refunded_cents can rise');
SELECT throws_like(
  $$ UPDATE public.payments SET amount_refunded_cents = 4000 WHERE id = tap.payment_a() $$,
  '%non-decreasing%', 'amount_refunded_cents cannot fall');
SELECT throws_like(
  $$ UPDATE public.payments SET amount_refunded_cents = NULL WHERE id = tap.payment_a() $$,
  '%non-decreasing%', 'amount_refunded_cents cannot be cleared');
SELECT throws_like(
  $$ UPDATE public.payments SET amount_refunded_cents = 12000 WHERE id = tap.payment_a() $$,
  '%non-decreasing%', 'amount_refunded_cents cannot exceed total');

-- ── Anonymization (delete_account_cleanup) still works; bypass is one statement ──
SELECT lives_ok($$ SELECT public.delete_account_cleanup(tap.buyer()) $$,
  'delete_account_cleanup anonymizes the buyer past the guard (its own arming is honoured)');
SELECT is((SELECT buyer_id FROM public.payments WHERE id = tap.payment_a()),
  '00000000-0000-0000-0000-000000000000'::uuid, 'buyer anonymized to the sentinel');
SELECT tap.reset_guards();
SELECT throws_like(
  $$ UPDATE public.payments SET seller_id = '00000000-0000-0000-0000-000000000000' WHERE id = tap.payment_b() $$,
  '%immutable once succeeded%', 'sentinel rewrite WITHOUT the bypass GUC is refused');
SELECT lives_ok(
  $$ SELECT set_config('app.bypass_payment_guard', 'on', true);
     UPDATE public.payments SET seller_id = '00000000-0000-0000-0000-000000000000' WHERE id = tap.payment_b() $$,
  'sentinel rewrite WITH app.bypass_payment_guard lives');
SELECT is(current_setting('app.bypass_payment_guard', true), 'off',
  'the bypass GUC is closed by the statement trigger (one statement, like 056c)');

-- ── record_payment_refund: partial vs full, idempotent, dispute-aware ────────
CREATE TEMP TABLE _p1 AS SELECT public.record_payment_refund('pi_fixture_b', 're_b1', NULL, 5000, 'dashboard') AS r;
SELECT is((SELECT r->>'status' FROM _p1), 'succeeded', 'partial refund keeps status succeeded');
SELECT is((SELECT (r->>'amount_refunded_cents')::int FROM _p1), 5000, 'partial amount recorded');
SELECT is((SELECT (public.record_payment_refund('pi_fixture_b', 're_b1', NULL, 5000, 'dashboard'))->>'amount_refunded_cents')::int, 5000,
  'replaying the same refund id is idempotent');
SELECT is((SELECT count(*) FROM public.payment_refunds WHERE payment_id = tap.payment_b()), 1::bigint,
  'one payment_refunds row for one refund');
CREATE TEMP TABLE _p2 AS SELECT public.record_payment_refund('pi_fixture_b', 're_b2', NULL, 6000, 'dashboard') AS r;
SELECT is((SELECT r->>'status' FROM _p2), 'refunded', 'refunds reaching total flip status to refunded');
SELECT is((SELECT stripe_refund_id FROM public.payments WHERE id = tap.payment_b()), 're_b1',
  'payments.stripe_refund_id keeps the first refund reference');
SELECT ok((SELECT refunded_at IS NOT NULL FROM public.payments WHERE id = tap.payment_b()), 'refunded_at stamped');

-- Dispute lost: chargeback recorded with the dispute id, never as a refund id.
CREATE TEMP TABLE _p3 AS SELECT public.record_payment_refund('pi_fixture_a', NULL, 'dp_1', 11000, 'dispute_lost') AS r;
SELECT is((SELECT r->>'status' FROM _p3), 'refunded', 'lost dispute for the full amount marks the payment refunded');
SELECT is((SELECT stripe_refund_id FROM public.payments WHERE id = tap.payment_a()), 're_a1',
  'stripe_refund_id NOT touched by a dispute');
SELECT is((SELECT stripe_dispute_id FROM public.payment_refunds WHERE payment_id = tap.payment_a() AND source = 'dispute_lost'), 'dp_1',
  'payment_refunds row carries the dispute id');
SELECT is((SELECT r->>'payment_id' FROM (SELECT public.record_payment_refund('pi_unknown', 're_z', NULL, 1, 'dashboard') AS r) x), NULL,
  'unknown payment intent returns payment_id NULL (acknowledged, not retried forever)');
SELECT throws_ok(
  $$ SELECT public.record_payment_refund('pi_fixture_a', 're_q', NULL, 1, 'bogus') $$,
  'P0001', 'INVALID_REFUND_SOURCE', 'source is validated');
SELECT throws_ok(
  $$ UPDATE public.payment_refunds SET amount_cents = 1 WHERE payment_id = tap.payment_a() $$,
  'P0001', 'payment_refunds is append-only (20260906120000).', 'payment_refunds cannot be rewritten');

-- ── Grants ──────────────────────────────────────────────────────────────────
SELECT ok(
  NOT has_function_privilege('anon', 'public.record_payment_refund(text, text, text, integer, text)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.record_payment_refund(text, text, text, integer, text)', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.record_payment_refund(text, text, text, integer, text)', 'EXECUTE'),
  'record_payment_refund: service_role only');

-- ── Review round 2 (converged RC, MAJOR-1): the guard is NULL-safe on the 093
-- payments shape (mode native_primary, listing_id/seller_id NULL). ────────────
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
VALUES ('bbbbbbbb-0000-0000-0000-00000000c123', NULL, tap.other_user(), NULL, 5000, 0, 0, 5000, 'pi_123_native', 'succeeded', 'native_primary', now(), true);
SELECT set_config('app.bypass_transfer_guard', 'on', true);
SELECT lives_ok(
  $$ UPDATE public.payments SET buyer_id = '00000000-0000-0000-0000-000000000000' WHERE id = 'bbbbbbbb-0000-0000-0000-00000000c123' $$,
  'R2 MAJOR-1: anonymising a native-rail row (delete_account_cleanup shape) is NULL-safe — no raise');
SELECT set_config('app.bypass_transfer_guard', 'off', true);
SELECT throws_like(
  $$ UPDATE public.payments SET amount = 1 WHERE id = 'bbbbbbbb-0000-0000-0000-00000000c123' $$,
  '%immutable%', 'R2: money columns stay immutable on a succeeded native-rail row');

SELECT * FROM finish();
ROLLBACK;
