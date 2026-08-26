-- ============================================================================
-- 050_transfers_custody.sql — the crown jewels. Transfer state is RPC-only
-- custody: no client, no service_role, not even the table-owner connection
-- may write state columns directly (055/056b); the bypass GUC authorises
-- exactly one statement (056c); evidence is append-only; the state machine
-- enforces actor + transition.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);
SELECT tap.seed_core();

-- ── Read scoping ────────────────────────────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT results_eq(
  $$ SELECT id FROM public.transfers ORDER BY id $$,
  ARRAY['cccccccc-0000-0000-0000-000000000001'::uuid,
        'cccccccc-0000-0000-0000-000000000002'::uuid],
  'buyer sees exactly their own transfers');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT is_empty($$ SELECT id FROM public.transfers $$,
  'unrelated user sees zero transfers');

-- ── Direct writes: authenticated (42501 — SELECT-only grant, 055) ───────────
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT throws_ok(
  $$ UPDATE public.transfers SET status = 'seller_sent' WHERE id = tap.transfer_a() $$,
  '42501', NULL, 'seller cannot UPDATE transfers directly (privilege revoked)');
SELECT throws_ok(
  $$ DELETE FROM public.transfers WHERE id = tap.transfer_a() $$,
  '42501', NULL, 'seller cannot DELETE transfers');

-- ── Direct writes: service_role (056b — the removed exemption) ──────────────
SELECT tap.logout();
SELECT tap.login_service();
SELECT throws_ok(
  $$ UPDATE public.transfers SET status = 'seller_sent' WHERE id = tap.transfer_a() $$,
  'P0001', 'Cannot directly modify transfer state columns. Use the appropriate RPC.',
  'service_role direct state writes blocked — RPC-only custody (056b)');
SELECT throws_ok(
  $$ UPDATE public.transfers SET seller_id = tap.other_user() WHERE id = tap.transfer_b() $$,
  'P0001', 'Cannot directly modify transfer state columns. Use the appropriate RPC.',
  'service_role cannot redirect a payout by rewriting seller_id (056b)');

-- ── Direct writes: table-owner / cron connection (no role exemption at all) ─
SELECT tap.logout();
SELECT tap.reset_guards();
SELECT throws_ok(
  $$ UPDATE public.transfers SET payout_released_at = now() WHERE id = tap.transfer_a() $$,
  'P0001', 'Cannot directly modify transfer state columns. Use the appropriate RPC.',
  'even the direct service connection cannot forge payout state');

-- ── Evidence append-only ────────────────────────────────────────────────────
SELECT throws_ok(
  $$ UPDATE public.transfers SET transfer_evidence_path = NULL WHERE id = tap.transfer_b() $$,
  'P0001', 'transfer_evidence_path is append-only.',
  'evidence path cannot be cleared once set (055)');

-- ── State machine: wrong state / wrong actor first ──────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT public.confirm_transfer_received(tap.transfer_a(), tap.buyer()) $$,
  'P0001', 'Transfer cannot be confirmed from current status: pending.',
  'buyer cannot confirm before the seller has sent');
SELECT throws_ok(
  $$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.buyer()) $$,
  'P0001', 'Only the seller can mark a transfer as sent.',
  'buyer cannot mark-sent (wrong actor)');

-- ── Happy path: seller marks sent via RPC ───────────────────────────────────
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT lives_ok(
  $$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.seller()) $$,
  'seller CAN advance pending -> seller_sent through the RPC');

-- ── 056c: the bypass GUC died with that statement ───────────────────────────
-- The RPC above armed app.bypass_transfer_guard inside this very transaction;
-- the AFTER-statement trigger must have closed the window immediately.
SELECT is(current_setting('app.bypass_transfer_guard', true), 'off',
  'bypass GUC reset by the statement-level trigger (056c)');
SELECT tap.logout();
SELECT throws_ok(
  $$ UPDATE public.transfers SET status = 'buyer_confirmed' WHERE id = tap.transfer_a() $$,
  'P0001', 'Cannot directly modify transfer state columns. Use the appropriate RPC.',
  'a later direct write in the same transaction is still blocked (056c)');

-- ── State machine continues ─────────────────────────────────────────────────
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()),
  'seller_sent', 'transfer A advanced to seller_sent');
SELECT ok((SELECT auto_release_at IS NOT NULL FROM public.transfers WHERE id = tap.transfer_a()),
  'mark_transfer_sent armed the 72h auto-release clock');

SELECT tap.login(tap.seller());
SELECT throws_ok(
  $$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.seller()) $$,
  'P0001', 'Transfer cannot be marked as sent from current status: seller_sent.',
  'mark-sent is not replayable (state guard)');

SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ SELECT public.confirm_transfer_received(tap.transfer_a(), tap.buyer()) $$,
  'buyer CAN confirm seller_sent -> buyer_confirmed through the RPC');
SELECT tap.logout();
SELECT is((SELECT status FROM public.transfers WHERE id = tap.transfer_a()),
  'buyer_confirmed', 'transfer A reached buyer_confirmed');

SELECT * FROM finish();
ROLLBACK;
