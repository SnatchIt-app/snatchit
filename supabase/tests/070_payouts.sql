-- ============================================================================
-- 070_payouts.sql — record_transfer_payout() is the ONLY way money-out gets
-- recorded: idempotent (a replay cannot double-record), refuses NULL/empty
-- ids, refuses any transfer with an open dispute (056d), and only a
-- seller-win resolution (065) reopens it. Reversal handling included.
-- All calls run on the trusted service path (claims cleared).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(19);
SELECT tap.seed_core();
SELECT tap.logout();

-- ── Happy path + idempotency ────────────────────────────────────────────────
SELECT is(public.record_transfer_payout(tap.transfer_b(), 'tr_test_1'), true,
  'payout recorded for the seller_sent transfer');
SELECT is((SELECT stripe_transfer_id FROM public.transfers WHERE id = tap.transfer_b()),
  'tr_test_1', 'stripe_transfer_id recorded');
SELECT ok((SELECT payout_released_at IS NOT NULL FROM public.transfers WHERE id = tap.transfer_b()),
  'payout_released_at stamped');
SELECT is(public.record_transfer_payout(tap.transfer_b(), 'tr_test_2'), false,
  'replay with a different transfer id refuses — no double payout');
SELECT is((SELECT stripe_transfer_id FROM public.transfers WHERE id = tap.transfer_b()),
  'tr_test_1', 'original stripe_transfer_id untouched by the replay');

-- ── Input guards ────────────────────────────────────────────────────────────
SELECT is(public.record_transfer_payout(tap.transfer_a(), NULL), false,
  'NULL stripe id refused (would poison its own idempotency predicate)');
SELECT is(public.record_transfer_payout(tap.transfer_a(), ''), false,
  'empty stripe id refused');

-- ── 056d: an open dispute freezes payout inside the writer itself ───────────
SELECT is(public.freeze_transfer_for_dispute(tap.transfer_a()), true,
  'dispute freeze claims the undisputed transfer');
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()),
  'disputed', 'transfer A is disputed');
SELECT is(public.record_transfer_payout(tap.transfer_a(), 'tr_test_3'), false,
  'record_transfer_payout REFUSES a disputed transfer (056d)');
SELECT is(public.freeze_transfer_for_dispute(tap.transfer_b()), false,
  'an already-paid transfer cannot be dispute-frozen (TOCTOU moved into the statement)');

-- ── 065: resolution gate ────────────────────────────────────────────────────
SELECT throws_ok(
  $$ SELECT public.resolve_transfer_dispute(tap.transfer_a(), 'seller_win', tap.buyer(), 'not an admin', NULL) $$,
  'P0001', 'Resolution requires a known admin actor.',
  'resolution demands an actor on the admin allowlist');
SELECT lives_ok(
  $$ SELECT public.resolve_transfer_dispute(tap.transfer_a(), 'seller_win', tap.admin_user(), 'test resolution', NULL) $$,
  'a known admin CAN resolve seller_win');
SELECT is((SELECT count(*) FROM public.dispute_resolutions WHERE transfer_id = tap.transfer_a()),
  1::bigint, 'resolution wrote its immutable audit row');
SELECT throws_ok(
  $$ UPDATE public.dispute_resolutions SET outcome = 'buyer_win'
      WHERE transfer_id = tap.transfer_a() $$,
  'P0001', 'dispute_resolutions is append-only (065).',
  'the audit history cannot be rewritten — even by the service path');
SELECT is(public.record_transfer_payout(tap.transfer_a(), 'tr_test_4'), true,
  'seller_win resolution reopens the payout path (056d predicate satisfied)');

-- ── Reversal ────────────────────────────────────────────────────────────────
SELECT is(public.mark_transfer_reversed('tr_test_1'), true,
  'a recorded payout can be marked reversed by its Stripe id');
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_b()),
  'reversed', 'transfer B is reversed');
SELECT is(public.mark_transfer_reversed('tr_test_1'), false,
  'reversal replay is a no-op');

SELECT * FROM finish();
ROLLBACK;
