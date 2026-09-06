-- ============================================================================
-- 060_payments_money.sql — payments are server-managed evidence: clients can
-- only read their own; a listing can only ever be paid once (003); one
-- payment maps to one transfer (003). F-2/F-3 closed by 20260906120000
-- (unique stripe_transfer_id; payments transition/money guard).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);
SELECT tap.seed_core();

-- ── Client write ban / read scoping ─────────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, mode, status)
     VALUES (tap.listing_d(), tap.buyer(), tap.seller(), 1, 0, 1, 'buy_now', 'succeeded') $$,
  '42501', NULL, 'client cannot INSERT payments (no policy)');
SELECT is_empty(
  $$ WITH u AS (UPDATE public.payments SET status = 'succeeded'
                 WHERE id = tap.payment_d() RETURNING id)
     SELECT * FROM u $$,
  'client cannot promote a payment to succeeded (no UPDATE policy — zero rows)');
SELECT is_empty(
  $$ WITH d AS (DELETE FROM public.payments RETURNING id) SELECT * FROM d $$,
  'client cannot DELETE payments (no policy — zero rows)');
SELECT is((SELECT count(*) FROM public.payments), 3::bigint,
  'buyer sees exactly their own payments');
SELECT tap.logout();
SELECT is((SELECT status FROM public.payments WHERE id = tap.payment_d()), 'pending',
  'the pending payment is still pending after the client attempts');

SELECT tap.login(tap.other_user());
SELECT is_empty($$ SELECT id FROM public.payments $$,
  'unrelated user sees zero payments');
SELECT tap.logout();

-- ── 003: at most one succeeded payment per listing ──────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, mode, status)
     VALUES (tap.listing_a(), tap.other_user(), tap.seller(), 10000, 1000, 11000, 'buy_now', 'succeeded') $$,
  '23505', NULL, 'second succeeded payment for the same listing rejected (idx_payments_one_success_per_listing)');
SELECT lives_ok(
  $$ INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, mode, status)
     VALUES (tap.listing_a(), tap.other_user(), tap.seller(), 10000, 1000, 11000, 'buy_now', 'pending') $$,
  'a further PENDING payment on the same listing is allowed (retries stay possible)');

-- ── 003: one payment -> one transfer; one listing -> one transfer ───────────
SELECT throws_ok(
  $$ INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, expires_at)
     VALUES (tap.listing_d(), tap.payment_a(), tap.seller(), tap.buyer(), 'email', now() + interval '1 day') $$,
  '23505', NULL, 'duplicate transfer for the same payment rejected (transfers_payment_id_key)');
SELECT throws_ok(
  $$ INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, expires_at)
     VALUES (tap.listing_a(), tap.payment_d(), tap.seller(), tap.buyer(), 'email', now() + interval '1 day') $$,
  '23505', NULL, 'duplicate transfer for the same listing rejected (transfers_listing_id_key)');

-- ── F-2 / F-3 — formerly todo() markers, real assertions since 20260906120000 ─
-- F-2: transfers.stripe_transfer_id was not unique (056a: mark_transfer_reversed
-- had to use "> 0"). transfers_stripe_transfer_id_uniq (partial, non-NULL)
-- closes it; 122_payout_attempts.sql proves the 23505.
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public' AND tablename = 'transfers'
             AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%stripe_transfer_id%'),
  'transfers.stripe_transfer_id should be unique');

-- F-3: payments had NO column guard trigger — any service-path writer could
-- silently rewrite amounts. guard_payment_transitions closes it; the full
-- transition matrix lives in 123_payment_monotonic.sql.
SELECT throws_ok(
  $$ UPDATE public.payments SET amount = 1, total = 1 WHERE id = tap.payment_a() $$,
  'P0001', NULL, 'direct service-path rewrite of payment amounts should be blocked');

SELECT * FROM finish();
ROLLBACK;
