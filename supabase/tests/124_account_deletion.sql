-- ============================================================================
-- 124_account_deletion.sql — account deletion fails closed (migration
-- 20260906120000): account_deletion_blockers(uuid) names every open money
-- obligation a user is party to — active transfers, unpaid seller
-- obligations (buyer_confirmed/auto_released without a payout), open
-- disputes, expired/reversed transfers whose payment is not fully refunded,
-- succeeded payments with no transfer row, fresh pending payments, open
-- payout attempts and open manual reviews — and returns zero rows for a user
-- with nothing outstanding. The account_deletions ledger is service-only.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);
SELECT tap.seed_core();
SELECT tap.logout();
UPDATE public.payments SET stripe_livemode = true WHERE id IN (tap.payment_a(), tap.payment_b());
UPDATE public.profiles SET stripe_connect_id = 'acct_A' WHERE id = tap.seller();

SELECT has_table('public'::name, 'account_deletions'::name, 'account_deletions ledger exists');

-- ── Clean user → zero rows ──────────────────────────────────────────────────
SELECT is_empty(
  $$ SELECT * FROM public.account_deletion_blockers(tap.admin_user()) $$,
  'a user with no money rows has zero blockers');

-- ── Fixture state: A pending, B seller_sent, D pending payment (fresh) ──────
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'active_transfer' AND ref_id = tap.transfer_a()),
  'seller: pending transfer A is an active_transfer blocker');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'active_transfer' AND ref_id = tap.transfer_b()),
  'buyer: seller_sent transfer B is an active_transfer blocker');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'pending_payment' AND ref_id = tap.payment_d()),
  'buyer: a pending payment younger than 24h blocks');
UPDATE public.payments SET created_at = now() - interval '25 hours' WHERE id = tap.payment_d();
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'pending_payment'),
  'buyer: a stale pending payment (>24h) no longer blocks');

-- ── (a) unpaid seller obligation: buyer_confirmed / auto_released, no payout ─
SELECT is(public.apply_auto_release(tap.transfer_b()), true, 'fixture: B auto_released (unpaid)');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'unpaid_seller_obligation' AND ref_id = tap.transfer_b()),
  'seller: auto_released-but-unpaid B blocks (F10: previously deletable, then unpayable)');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'unpaid_seller_obligation' AND ref_id = tap.transfer_b()),
  'buyer: the same obligation blocks the buyer side too');

-- ── open payout attempt ─────────────────────────────────────────────────────
CREATE TEMP TABLE _c AS SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'test');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'open_payout_attempt' AND ref_id = (SELECT attempt_id FROM _c)),
  'seller: an open payout attempt blocks');

-- ── open manual review ──────────────────────────────────────────────────────
INSERT INTO public.payout_decisions (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, actor)
VALUES (tap.transfer_b(), tap.payment_b(), tap.seller(), tap.buyer(), 'high', 'manual_review', ARRAY['TEST'], 'test');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'open_manual_review' AND ref_id = tap.transfer_b()),
  'seller: an open manual_review decision blocks');

-- ── (b) open dispute ────────────────────────────────────────────────────────
SELECT is(public.freeze_transfer_for_dispute(tap.transfer_b()), true, 'fixture: B disputed');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'open_dispute' AND ref_id = tap.transfer_b()),
  'seller: a disputed transfer blocks');
INSERT INTO public.disputes (stripe_dispute_id, stripe_charge_id, stripe_pi_id, payment_id, transfer_id, amount, reason, status)
VALUES ('dp_test', 'ch_test', 'pi_fixture_b', tap.payment_b(), tap.transfer_b(), 11000, 'fraudulent', 'needs_response');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'open_dispute' AND ref_id = (SELECT id FROM public.disputes WHERE stripe_dispute_id = 'dp_test')),
  'buyer: an open Stripe dispute row blocks');
UPDATE public.disputes SET status = 'won' WHERE stripe_dispute_id = 'dp_test';
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'open_dispute' AND ref_id = (SELECT id FROM public.disputes WHERE stripe_dispute_id = 'dp_test')),
  'buyer: a closed Stripe dispute row no longer blocks');

-- ── (c) expired, payment not refunded → pending_refund; refund clears it ────
SELECT set_config('app.bypass_transfer_guard', 'on', true);
UPDATE public.transfers SET status = 'expired', expired_at = now() WHERE id = tap.transfer_a();
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()), 'expired', 'fixture: A expired');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'pending_refund' AND ref_id = tap.transfer_a()),
  'buyer: expired transfer with an unrefunded payment blocks');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'active_transfer' AND ref_id = tap.transfer_a()),
  '…and it is no longer reported as active');
SELECT is((public.record_payment_refund('pi_fixture_a', 're_a', NULL, 11000, 'expiry'))->>'status', 'refunded',
  'fixture: A fully refunded');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE ref_id = tap.transfer_a()),
  'buyer: a fully refunded expired transfer is settled — no blocker');

-- ── (d) paid with no transfer row ───────────────────────────────────────────
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
VALUES ('bbbbbbbb-0000-0000-0000-000000000007', tap.listing_c(), tap.other_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_c', 'succeeded', 'buy_now', now());
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.other_user()) WHERE kind = 'paid_no_transfer' AND ref_id = 'bbbbbbbb-0000-0000-0000-000000000007'),
  'other user: a succeeded payment with no transfer row blocks');

-- ── Grants ──────────────────────────────────────────────────────────────────
SELECT ok(
  NOT has_function_privilege('anon', 'public.account_deletion_blockers(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.account_deletion_blockers(uuid)', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.account_deletion_blockers(uuid)', 'EXECUTE'),
  'account_deletion_blockers: service_role only');
SELECT ok(
  NOT has_table_privilege('anon', 'public.account_deletions', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.account_deletions', 'SELECT')
  AND has_table_privilege('service_role', 'public.account_deletions', 'INSERT')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.account_deletions'::regclass)
  AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'account_deletions') = 0,
  'account_deletions: RLS on, zero policies, service_role only');
SELECT ok(
  NOT has_table_privilege('anon', 'public.payment_refunds', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.payment_refunds', 'INSERT')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.payment_refunds'::regclass)
  AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payment_refunds') = 0,
  'payment_refunds: RLS on, zero policies, no client privileges');

SELECT * FROM finish();
ROLLBACK;
