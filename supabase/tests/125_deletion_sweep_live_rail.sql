-- ============================================================================
-- 125_deletion_sweep_live_rail.sql — BOTH deletion protections hold on the
-- converged chain (Phase-2 tombstone machine 077/078/093 + payments Package 3
-- 20260906120000 + the BP-13 hook extension 20260906130000).
--
--   (1) every Phase-2 hook is UNTOUCHED (kernel.deletion_blockers_money keeps
--       its 093 body: native arms present, no BP-13 text, one routine, ACL) and
--       the 078 sweep body carries exactly one addition — the BP-13 arm AFTER
--       BP-12 — so BP-1..BP-12 precedence is unchanged (141 O24/O25/Q3 hold);
--   (2) public.account_deletion_block_reason returns BP-13 when
--       public.account_deletion_blockers names an unsettled live-rail
--       obligation, and NULL for a clean identity; service_role EXECUTE only;
--   (3) END TO END through kernel.request_account_deletion (always accepts) and
--       kernel.sweep_deletion_pending: the sweep records BP-13 and tombstones
--       NOTHING while the obligation stands; once it settles (full refund),
--       the same identity is tombstoned (deletion_state = ERASED);
--   (4) the pre-existing inline arms still fire after the hook returns NULL:
--       an identity with no money rows but a live buy-now reservation is held
--       by BP-8; releasing it lets the terminal run.
-- Fixtures: tap.seed_core() (public marketplace world, 000_helpers); the kernel
-- identity rows are created on demand by request_account_deletion.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(28);
SELECT tap.seed_core();
SELECT tap.logout();

-- ── (1) hooks untouched; sweep body = 078 + one BP-13 arm after BP-12 ──────
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'),
  1, 'SEAM: exactly one kernel.sweep_deletion_pending (body-only replace)');
SELECT is(
  (SELECT pg_get_function_identity_arguments(p.oid) || ' -> ' || pg_get_function_result(p.oid)
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'),
  'p_limit integer -> jsonb', 'sweep signature frozen');
SELECT ok(
  (SELECT p.prosecdef AND p.proconfig::text LIKE '%search_path=%'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'),
  'sweep attributes frozen: SECURITY DEFINER, pinned search_path');
SELECT ok(
  (SELECT position('public.account_deletion_block_reason(v_row.identity_id)' IN p.prosrc) >
          position('kernel.deletion_blockers_orders(v_row.identity_id)' IN p.prosrc)
      AND position('kernel.deletion_blockers_orders(v_row.identity_id)' IN p.prosrc) > 0
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'),
  'the BP-13 arm is the LAST coalesce operand — after BP-12 (BP-1..BP-12 precedence unchanged)');
SELECT is(
  (SELECT (length(p.prosrc) - length(replace(p.prosrc, 'account_deletion_block_reason(v_row.identity_id)', ''))) / length('account_deletion_block_reason(v_row.identity_id)')
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'sweep_deletion_pending'),
  1, 'exactly one BP-13 CALL SITE in the sweep (the comment mention does not count)');
SELECT ok(
  (SELECT p.prosrc NOT LIKE '%BP-13%'
      AND p.prosrc LIKE '%BP-5: identity payout in flight%'
      AND p.prosrc LIKE '%BP-12: inside the post-event deletion hold%'
     FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname = 'deletion_blockers_money'),
  'kernel.deletion_blockers_money is UNTOUCHED: 093 native arms present, no BP-13 text (141 Q3 holds)');
SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'kernel' AND p.proname IN ('deletion_blockers_custody','deletion_blockers_orders','deletion_blockers_wallet','deletion_blockers_money','deletion_blockers_market')
      AND p.prosrc LIKE '%BP-13%'),
  0, 'no Phase-2 hook carries BP-13 (the arm lives in the sweep only)');
SELECT has_function('public'::name, 'account_deletion_block_reason'::name, ARRAY['uuid'], 'public.account_deletion_block_reason(uuid) exists');
SELECT ok(
  NOT has_function_privilege('anon', 'public.account_deletion_block_reason(uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated', 'public.account_deletion_block_reason(uuid)', 'EXECUTE')
  AND has_function_privilege('service_role', 'public.account_deletion_block_reason(uuid)', 'EXECUTE'),
  'account_deletion_block_reason: service_role only (SEC-2)');

-- ── (2) predicate semantics ─────────────────────────────────────────────────
SELECT is(public.account_deletion_block_reason(tap.admin_user()), NULL,
  'clean identity (no live-rail rows) ⇒ NULL');
-- other_user: a succeeded payment with no transfer row (paid_no_transfer)
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at, stripe_livemode)
VALUES ('bbbbbbbb-0000-0000-0000-000000000125', tap.listing_c(), tap.other_user(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_125', 'succeeded', 'buy_now', now(), true);
SELECT ok(EXISTS (SELECT 1 FROM public.account_deletion_blockers(tap.other_user()) WHERE kind = 'paid_no_transfer'),
  'fixture: the public predicate names paid_no_transfer for other_user');
SELECT ok(public.account_deletion_block_reason(tap.other_user()) LIKE 'BP-13: unsettled live-rail money obligation (%paid_no_transfer%)%',
  'predicate ⇒ BP-13 naming the kind');
SELECT ok(public.account_deletion_block_reason(tap.buyer()) LIKE 'BP-13:%active_transfer%',
  'predicate ⇒ BP-13 for the buyer of a seller_sent transfer (active_transfer)');
SELECT is(kernel.deletion_blockers_money(tap.other_user()), NULL,
  'the money HOOK stays NULL for the same identity (BP-13 is not a hook arm)');

-- ── (3) end to end: request (always accepts) → sweep blocked → settle → erased
SELECT tap.login(tap.other_user());
SELECT is((kernel.request_account_deletion('ck125-1'))->>'status', 'ok',
  'OR-17 preserved: the request is ACCEPTED although a live-rail obligation stands');
SELECT tap.logout();
SELECT is(
  (SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = tap.other_user()),
  'DELETION_PENDING', 'identity enters DELETION_PENDING');
SELECT is(((kernel.sweep_deletion_pending())->>'tombstoned'), '0',
  'sweep tombstones NOTHING while BP-13 holds');
SELECT ok(
  (SELECT deletion_block_reason LIKE 'BP-13:%paid_no_transfer%' FROM kernel.identity_ext WHERE identity_id = tap.other_user()),
  'sweep records BP-13 with the obligation kind as the operator-legible reason');
SELECT is(
  (SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = tap.other_user()),
  'DELETION_PENDING', 'identity is still pending (not erased) after the blocked pass');
-- The platform settles the obligation: the captured money goes back to the buyer.
SELECT is((public.record_payment_refund('pi_fixture_125', 're_fixture_125', NULL, 11000, 'unfulfillable'))->>'status', 'refunded',
  'fixture: the paid-with-no-transfer capture is fully refunded');
SELECT is_empty($$ SELECT * FROM public.account_deletion_blockers(tap.other_user()) $$,
  'the public predicate is now clear for other_user');
SELECT is(public.account_deletion_block_reason(tap.other_user()), NULL, 'predicate ⇒ NULL once settled');
SELECT is(((kernel.sweep_deletion_pending())->>'tombstoned'), '1',
  'with every predicate false the sweep executes terminal entry for other_user');
SELECT is(
  (SELECT deletion_state FROM kernel.identity_ext WHERE identity_id = tap.other_user()),
  'ERASED', 'terminal marker: deletion_state = ERASED');

-- ── (4) the pre-existing inline arms still hold after the hook returns NULL ──
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET reserved_by = tap.admin_user(), reserved_until = now() + interval '9 minutes'
 WHERE id = tap.listing_c();
SELECT is(public.account_deletion_block_reason(tap.admin_user()), NULL,
  'a live reservation is NOT a live-rail money obligation (predicate NULL) — BP-8 owns it');
SELECT tap.login(tap.admin_user());
SELECT is((kernel.request_account_deletion('ck125-2'))->>'status', 'ok', 'admin_user requests deletion');
SELECT tap.logout();
SELECT is(((kernel.sweep_deletion_pending())->>'tombstoned'), '0', 'sweep tombstones nothing while BP-8 holds');
SELECT ok(
  (SELECT deletion_block_reason LIKE 'BP-8%' FROM kernel.identity_ext WHERE identity_id = tap.admin_user()),
  'the Phase-2 inline BP-8 arm (live buy-now reservation) is still evaluated and recorded');

SELECT * FROM finish();
ROLLBACK;
