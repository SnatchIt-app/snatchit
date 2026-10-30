-- ============================================================================
-- 124_account_deletion.sql — account deletion fails closed (migration
-- 20260906120000): account_deletion_blockers(uuid) names every open money
-- obligation a user is party to — active transfers, unpaid seller
-- obligations (buyer_confirmed/auto_released without a payout), open
-- disputes, expired/reversed transfers whose payment is not fully refunded,
-- succeeded payments with no transfer row, fresh pending payments, open
-- payout attempts, open manual reviews (before OR after a payout, until a
-- later release decision or a reversal — review round 1 A2), unresolved
-- webhook_retries review rows (A1) — and returns zero rows for a user with
-- nothing outstanding. The account_deletions ledger is service-only.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(42);
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

-- ── A1 (review round 1, MAJOR-1): an unresolved webhook_retries row is an
-- open obligation — Package 2 parks a captured-but-mismatched charge there
-- with the payment still pending; the 24h bound must not let it through. ──
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap.payment_d(), tap.listing_d(), 'settle_verified_payment', 'binding_mismatch:pi_fixture_d stripe=succeeded/11000', false);
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'unresolved_review' AND ref_id = tap.payment_d()),
  'A1 buyer: an unresolved webhook_retries row on a 3-day-old pending payment blocks (unresolved_review)');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'pending_payment' AND ref_id = tap.payment_d()),
  'A1 buyer: the 24h bound on pending_payment is dropped while a review row is open');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'unresolved_review' AND ref_id = tap.payment_d()),
  'A1 seller: the same review row blocks the seller side too');
UPDATE public.webhook_retries SET resolved = true WHERE payment_id = tap.payment_d();
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE ref_id = tap.payment_d()),
  'A1 buyer: once the review row is resolved the stale pending payment no longer blocks');

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

-- ── A2 (review round 1, MAJOR-2): a LEGACY paid-out transfer (no attempt
-- row) whose dispute is LOST after the payout. flag_payout_reversal_required
-- writes a DISPUTE_LOST_AFTER_PAYOUT manual_review with attempt_id NULL; the
-- payment is refunded and the transfer paid, so it is "settled" — the review
-- row ALONE must block, regardless of payout_released_at, until a later
-- release decision supersedes it or the transfer is reversed. ───────────────
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES ('aaaaaaaa-0000-0000-0000-000000000005', tap.seller(), 'Fixture Event E', 'Club E', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
        100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/e.jpg', 'active');
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
VALUES ('bbbbbbbb-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000005', tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_e', 'succeeded', 'buy_now', now(), true);
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
VALUES ('cccccccc-0000-0000-0000-000000000005', 'aaaaaaaa-0000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-000000000005', tap.seller(), tap.buyer(),
        'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours', 'fixtures/evidence-e.jpg', now() + interval '24 hours');

SELECT is(public.apply_auto_release('cccccccc-0000-0000-0000-000000000005'), true, 'fixture: E auto_released');
SELECT lives_ok($$ SELECT public.record_transfer_payout('cccccccc-0000-0000-0000-000000000005', 'tr_legacy_e') $$,
  'fixture: E paid out the legacy way (record_transfer_payout, no attempt row)');
SELECT ok((SELECT payout_released_at IS NOT NULL AND stripe_transfer_id = 'tr_legacy_e'
             FROM public.transfers WHERE id = 'cccccccc-0000-0000-0000-000000000005'),
  'fixture: E carries the legacy payout');
SELECT is((public.record_payment_refund('pi_fixture_e', NULL, 'dp_lost_e', 11000, 'dispute_lost'))->>'status', 'refunded',
  'fixture: E chargeback recorded — payment refunded');
SELECT is((public.flag_payout_reversal_required('cccccccc-0000-0000-0000-000000000005', 'DISPUTE_LOST_AFTER_PAYOUT', '{}'::jsonb))->>'decision_inserted', 'true',
  'fixture: DISPUTE_LOST_AFTER_PAYOUT manual_review inserted');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id = 'cccccccc-0000-0000-0000-000000000005'), 0::bigint,
  'fixture: E has no attempt row (legacy) — the decision carries attempt_id NULL');
SELECT is((SELECT array_agg(DISTINCT kind ORDER BY kind) FROM public.account_deletion_blockers(tap.seller())
            WHERE ref_id = 'cccccccc-0000-0000-0000-000000000005'),
  ARRAY['open_manual_review'],
  'A2 seller: the post-payout DISPUTE_LOST_AFTER_PAYOUT review blocks — and it is the ONLY blocker on E');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.buyer()) WHERE kind = 'open_manual_review' AND ref_id = 'cccccccc-0000-0000-0000-000000000005'),
  'A2 buyer: the same review blocks the buyer side');
INSERT INTO public.payout_decisions (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, actor, decided_at)
VALUES ('cccccccc-0000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-000000000005', tap.seller(), tap.buyer(), 'high', 'release', ARRAY['OPS_REVERSAL_SETTLED'], 'admin:test', now() + interval '1 second');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE ref_id = 'cccccccc-0000-0000-0000-000000000005'),
  'A2 seller: a LATER release decision supersedes the review — no blocker');
INSERT INTO public.payout_decisions (transfer_id, payment_id, seller_id, buyer_id, risk_tier, decision, reason_codes, actor, decided_at)
VALUES ('cccccccc-0000-0000-0000-000000000005', 'bbbbbbbb-0000-0000-0000-000000000005', tap.seller(), tap.buyer(), 'high', 'manual_review', ARRAY['SECOND_LOOK'], 'admin:test', now() + interval '2 seconds');
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE kind = 'open_manual_review' AND ref_id = 'cccccccc-0000-0000-0000-000000000005'),
  'A2 seller: a fresh manual_review AFTER the release blocks again');
SELECT is(public.mark_transfer_reversed('tr_legacy_e'), true, 'fixture: E reversed on Stripe');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.seller()) WHERE ref_id = 'cccccccc-0000-0000-0000-000000000005'),
  'A2 seller: once the transfer is reversed the review no longer blocks');

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

-- ── Review round 2 (converged RC, MAJOR-1): kernel-rail rows (093 shape) are
-- not live-rail obligations — the kernel arms own them. ───────────────────────
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
VALUES ('bbbbbbbb-0000-0000-0000-00000000a124', NULL, tap.admin_user(), NULL, 5000, 0, 0, 5000, 'pi_124_native_paid', 'succeeded', 'native_primary', now(), true),
       ('bbbbbbbb-0000-0000-0000-00000000b124', NULL, tap.admin_user(), NULL, 5000, 0, 0, 5000, 'pi_124_native_pend', 'pending',   'native_primary', NULL,  true);
SELECT is_empty(
  $$ SELECT * FROM public.account_deletion_blockers(tap.admin_user()) WHERE kind = 'paid_no_transfer' $$,
  'R2 MAJOR-1: a succeeded native_primary payment with no transfer is NOT paid_no_transfer');
SELECT is_empty(
  $$ SELECT * FROM public.account_deletion_blockers(tap.admin_user()) $$,
  'R2 MAJOR-1: …nor is a fresh pending native_primary row a pending_payment blocker (admin_user stays clean)');

SELECT * FROM finish();
ROLLBACK;
