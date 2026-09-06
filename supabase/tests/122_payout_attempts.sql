-- ============================================================================
-- 122_payout_attempts.sql — payouts are ledgered per attempt (migration
-- 20260906120000): claim_payout_attempt() freezes the request parameters and
-- hands out a lease; one open attempt per transfer; frozen params are
-- immutable; state only advances; a transfer Stripe reports is ALWAYS
-- recorded — even when a dispute landed between claim and record
-- (reversal_required + PAID_DURING_DISPUTE decision, F07); reconcile closes
-- or promotes an attempt; transfers.stripe_transfer_id is unique (F-2).
-- All calls run on the trusted service path (claims cleared).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(60);
SELECT tap.seed_core();
SELECT tap.logout();

-- Live-mode payments + an onboarded seller (fixture defaults are NULL/none).
UPDATE public.payments SET stripe_livemode = true WHERE id IN (tap.payment_a(), tap.payment_b());
UPDATE public.profiles SET stripe_connect_id = 'acct_A' WHERE id = tap.seller();

-- ── Schema ──────────────────────────────────────────────────────────────────
SELECT has_table('public'::name, 'payout_attempts'::name, 'payout_attempts exists');
SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes
           WHERE schemaname = 'public' AND tablename = 'transfers'
             AND indexname = 'transfers_stripe_transfer_id_uniq'
             AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%WHERE%'),
  'transfers_stripe_transfer_id_uniq partial unique index exists (F-2 closed)');

-- ── Eligibility gate ────────────────────────────────────────────────────────
SELECT throws_ok(
  $$ SELECT * FROM public.claim_payout_attempt(tap.transfer_a(), 'test') $$,
  'P0001', 'TRANSFER_NOT_RELEASABLE',
  'a pending transfer cannot be claimed for payout');
SELECT throws_ok(
  $$ SELECT * FROM public.claim_payout_attempt('cccccccc-0000-0000-0000-00000000dead', 'test') $$,
  'P0001', 'TRANSFER_NOT_FOUND',
  'unknown transfer id is refused');

SELECT is(public.apply_auto_release(tap.transfer_b()), true, 'fixture: transfer B auto_released');

-- Payment must be live-mode: flip it off and the claim refuses.
UPDATE public.payments SET stripe_livemode = NULL WHERE id = tap.payment_b();
SELECT throws_ok(
  $$ SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'test') $$,
  'P0001', 'PAYMENT_NOT_LIVE',
  'an unclassified (NULL livemode) payment is not payable — fail closed');
UPDATE public.payments SET stripe_livemode = true WHERE id = tap.payment_b();

-- ── Claim freezes the request ───────────────────────────────────────────────
CREATE TEMP TABLE _c1 AS SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'edge:test');
SELECT is((SELECT attempt_no FROM _c1), 1, 'first claim is attempt 1');
SELECT is((SELECT idempotency_key FROM _c1), 'payout_' || tap.transfer_b()::text || '_a1',
  'idempotency key is payout_<transfer_id>_a<attempt_no>');
SELECT is((SELECT destination FROM _c1), 'acct_A', 'destination snapshotted from the seller profile');
SELECT is((SELECT amount_cents FROM _c1), 9000, 'amount = payment.amount - seller_fee (10000 - 1000)');
SELECT is((SELECT payment_intent_id FROM _c1), 'pi_fixture_b', 'payment intent id returned for the pre-flight');
SELECT is((SELECT needs_reconcile FROM _c1), false, 'a fresh attempt does not need reconciliation');
SELECT is((SELECT state FROM public.payout_attempts WHERE id = (SELECT attempt_id FROM _c1)), 'claimed',
  'attempt row is claimed');

-- A second claim while the lease is live must not open a second attempt and
-- must not hand the row to a second worker (it could mark a live POST failed).
SELECT throws_ok(
  $$ SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'edge:other') $$,
  'P0001', 'PAYOUT_ATTEMPT_IN_PROGRESS',
  'a live lease blocks a concurrent claim');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id = tap.transfer_b()), 1::bigint,
  'still exactly one attempt');

-- ── mark_payout_requested ───────────────────────────────────────────────────
SELECT is(public.mark_payout_requested((SELECT attempt_id FROM _c1)), true, 'claimed -> requested');
SELECT is(public.mark_payout_requested((SELECT attempt_id FROM _c1)), false, 'requested is not re-marked');

-- ── Expired lease → same attempt comes back flagged for reconciliation ──────
UPDATE public.payout_attempts SET lease_expires_at = now() - interval '1 minute'
 WHERE id = (SELECT attempt_id FROM _c1);
-- Destination changes during recovery are NOT picked up: the attempt replays
-- its frozen parameters (F08(e)).
UPDATE public.profiles SET stripe_connect_id = 'acct_B' WHERE id = tap.seller();
CREATE TEMP TABLE _c2 AS SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'cron:test');
SELECT is((SELECT attempt_id FROM _c2), (SELECT attempt_id FROM _c1), 'expired lease returns the SAME attempt');
SELECT is((SELECT needs_reconcile FROM _c2), true, '…flagged needs_reconcile');
SELECT is((SELECT destination FROM _c2), 'acct_A', '…with the FROZEN destination, not the new profile value');
SELECT ok((SELECT lease_expires_at > now() FROM public.payout_attempts WHERE id = (SELECT attempt_id FROM _c1)),
  'reconcile claim re-arms the lease');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id = tap.transfer_b()), 1::bigint,
  'no second attempt was opened');

-- ── Frozen parameters are immutable; state only advances ────────────────────
SELECT throws_ok(
  $$ UPDATE public.payout_attempts SET destination = 'acct_B' WHERE transfer_id = tap.transfer_b() $$,
  'P0001', 'payout_attempts request parameters are immutable (20260906120000).',
  'destination cannot be rewritten');
SELECT throws_ok(
  $$ UPDATE public.payout_attempts SET amount_cents = 1 WHERE transfer_id = tap.transfer_b() $$,
  'P0001', 'payout_attempts request parameters are immutable (20260906120000).',
  'amount cannot be rewritten');
SELECT throws_ok(
  $$ UPDATE public.payout_attempts SET idempotency_key = 'x' WHERE transfer_id = tap.transfer_b() $$,
  'P0001', 'payout_attempts request parameters are immutable (20260906120000).',
  'idempotency key cannot be rewritten');
SELECT throws_ok(
  $$ UPDATE public.payout_attempts SET state = 'claimed' WHERE transfer_id = tap.transfer_b() $$,
  'P0001', 'payout_attempts.state may only advance: requested -> claimed (20260906120000).',
  'state cannot move backwards');

-- ── 'unknown' extends the lease, records the error ──────────────────────────
UPDATE public.payout_attempts SET lease_expires_at = now() - interval '1 minute'
 WHERE id = (SELECT attempt_id FROM _c1);
SELECT is(
  (public.record_payout_attempt_result((SELECT attempt_id FROM _c1), NULL, 'unknown', '{"reason":"network timeout"}'::jsonb))->>'state',
  'unknown', 'a lost response marks the attempt unknown');
SELECT ok((SELECT lease_expires_at > now() FROM public.payout_attempts WHERE id = (SELECT attempt_id FROM _c1)),
  'unknown extends the lease');
SELECT throws_ok(
  $$ SELECT public.record_payout_attempt_result((SELECT attempt_id FROM _c1), NULL, 'succeeded', NULL) $$,
  'P0001', 'STRIPE_TRANSFER_ID_REQUIRED',
  'succeeded without a Stripe transfer id is refused');

-- ── F07: dispute lands between claim and record → STILL recorded ────────────
SELECT is(public.freeze_transfer_for_dispute(tap.transfer_b()), true, 'chargeback freezes the unpaid transfer');
CREATE TEMP TABLE _r1 AS
  SELECT public.record_payout_attempt_result((SELECT attempt_id FROM _c1), 'tr_x', 'succeeded', NULL) AS r;
SELECT is((SELECT r->>'state' FROM _r1), 'reversal_required',
  'money moved during a dispute → attempt is reversal_required');
SELECT is((SELECT stripe_transfer_id FROM public.transfers WHERE id = tap.transfer_b()), 'tr_x',
  'transfers.stripe_transfer_id IS written (the tr_ is never lost)');
SELECT ok((SELECT payout_released_at IS NOT NULL FROM public.transfers WHERE id = tap.transfer_b()),
  'payout_released_at stamped');
SELECT is((SELECT stripe_transfer_id FROM public.payout_attempts WHERE id = (SELECT attempt_id FROM _c1)), 'tr_x',
  'attempt carries the Stripe transfer id');
SELECT is((SELECT count(*) FROM public.payout_decisions
            WHERE transfer_id = tap.transfer_b() AND decision = 'manual_review'
              AND 'PAID_DURING_DISPUTE' = ANY(reason_codes)), 1::bigint,
  'one PAID_DURING_DISPUTE manual_review decision');
SELECT lives_ok(
  $$ SELECT public.record_payout_attempt_result((SELECT attempt_id FROM _c1), 'tr_x', 'succeeded', NULL) $$,
  'recording the same result again is idempotent');
SELECT is((SELECT count(*) FROM public.payout_decisions
            WHERE transfer_id = tap.transfer_b() AND 'PAID_DURING_DISPUTE' = ANY(reason_codes)), 1::bigint,
  '…and does not duplicate the decision');
SELECT throws_ok(
  $$ SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'test') $$,
  'P0001', 'ALREADY_RELEASED',
  'a paid transfer cannot be claimed again');

-- ── F-2: the same Stripe transfer id cannot land on two rows ────────────────
SELECT throws_ok(
  $$ SELECT public.record_transfer_payout(tap.transfer_a(), 'tr_x') $$,
  '23505', NULL,
  'transfers.stripe_transfer_id is unique');

-- ── Reconcile: not found closes the attempt; a later attempt opens fresh ────
SELECT tap.login(tap.seller());
SELECT lives_ok($$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.seller()) $$, 'fixture: A seller_sent');
SELECT tap.logout();
SELECT is(public.apply_auto_release(tap.transfer_a()), true, 'fixture: A auto_released');
CREATE TEMP TABLE _a1 AS SELECT * FROM public.claim_payout_attempt(tap.transfer_a(), 'edge:test');
SELECT is(public.mark_payout_requested((SELECT attempt_id FROM _a1)), true, 'A attempt 1 requested');
SELECT is(
  (public.reconcile_payout_attempt((SELECT attempt_id FROM _a1), NULL))->>'state', 'failed',
  'reconcile with no Stripe transfer found closes the attempt as failed');
CREATE TEMP TABLE _a2 AS SELECT * FROM public.claim_payout_attempt(tap.transfer_a(), 'edge:test');
SELECT is((SELECT attempt_no FROM _a2), 2, 'a NEW attempt opens only after the previous is terminal');
SELECT is((SELECT idempotency_key FROM _a2), 'payout_' || tap.transfer_a()::text || '_a2',
  'new attempt, new key');
SELECT is(
  (public.reconcile_payout_attempt((SELECT attempt_id FROM _a2), 'tr_y'))->>'state', 'succeeded',
  'reconcile with a found transfer records it');
SELECT is((SELECT stripe_transfer_id FROM public.transfers WHERE id = tap.transfer_a()), 'tr_y',
  'found transfer written to transfers');

-- ── Partial unique indexes ──────────────────────────────────────────────────
SELECT throws_ok(
  $$ INSERT INTO public.payout_attempts
       (transfer_id, payment_id, attempt_no, state, destination, amount_cents, idempotency_key, actor, lease_expires_at)
     VALUES (tap.transfer_a(), tap.payment_a(), 3, 'succeeded', 'acct_A', 9000, 'k3', 'test', now()) $$,
  '23505', NULL, 'one succeeded attempt per transfer');
INSERT INTO public.payout_attempts
  (transfer_id, payment_id, attempt_no, state, destination, amount_cents, idempotency_key, actor, lease_expires_at)
VALUES (tap.transfer_a(), tap.payment_a(), 4, 'claimed', 'acct_A', 9000, 'k4', 'test', now());
SELECT throws_ok(
  $$ INSERT INTO public.payout_attempts
       (transfer_id, payment_id, attempt_no, state, destination, amount_cents, idempotency_key, actor, lease_expires_at)
     VALUES (tap.transfer_a(), tap.payment_a(), 5, 'requested', 'acct_A', 9000, 'k5', 'test', now()) $$,
  '23505', NULL, 'one OPEN attempt per transfer');

-- ── A6 (review round 1, MINOR-2): every writer locks transfers BEFORE
-- payout_attempts, so a transfer.created webhook racing the 2b sweep cannot
-- deadlock (40P01). A two-session probe needs dblink/pg_background, which the
-- rehearsal stack does not ship; the order is asserted on the function
-- sources instead (the FOR UPDATE statements are unique strings). ───────────
SELECT ok((SELECT position('FROM public.transfers WHERE id = p_transfer_id FOR UPDATE' IN prosrc) > 0
             AND position('FROM public.transfers WHERE id = p_transfer_id FOR UPDATE' IN prosrc)
               < position('FROM public.payout_attempts a' IN prosrc)
             FROM pg_proc WHERE proname = 'claim_payout_attempt' AND pronamespace = 'public'::regnamespace),
  'A6 claim_payout_attempt: transfers FOR UPDATE precedes payout_attempts FOR UPDATE');
SELECT ok((SELECT position('FROM public.transfers WHERE id = v_tid FOR UPDATE' IN prosrc) > 0
             AND position('FROM public.transfers WHERE id = v_tid FOR UPDATE' IN prosrc)
               < position('FROM public.payout_attempts WHERE id = p_attempt_id FOR UPDATE' IN prosrc)
             FROM pg_proc WHERE proname = 'record_payout_attempt_result' AND pronamespace = 'public'::regnamespace),
  'A6 record_payout_attempt_result: transfers FOR UPDATE precedes payout_attempts FOR UPDATE (same order as claim)');
SELECT ok((SELECT position('FROM public.transfers WHERE id = p_transfer_id FOR UPDATE' IN prosrc) > 0
             AND position('FROM public.transfers WHERE id = p_transfer_id FOR UPDATE' IN prosrc)
               < position('UPDATE public.payout_attempts' IN prosrc)
             FROM pg_proc WHERE proname = 'flag_payout_reversal_required' AND pronamespace = 'public'::regnamespace),
  'A6 flag_payout_reversal_required: transfers FOR UPDATE precedes the payout_attempts write');

-- ── A3 (review round 1, MINOR-3): the attempt ledger is append-only — DELETE
-- and TRUNCATE raise even for service_role (which holds both privileges and
-- BYPASSRLS). ──────────────────────────────────────────────────────────────
SELECT has_trigger('public'::name, 'payout_attempts'::name, 'trg_payout_attempts_no_delete'::name,
  'BEFORE DELETE trigger exists on payout_attempts');
CREATE TEMP TABLE _cnt AS SELECT count(*) AS n FROM public.payout_attempts;
SELECT tap.login_service();
SELECT throws_ok(
  $$ DELETE FROM public.payout_attempts WHERE transfer_id = tap.transfer_a() $$,
  'P0001', 'payout_attempts is append-only: rows are never deleted (20260906120000).',
  'A3 service_role cannot DELETE payout_attempts rows');
SELECT throws_ok(
  $$ TRUNCATE public.payout_attempts $$,
  'P0001', 'payout_attempts is append-only: rows are never deleted (20260906120000).',
  'A3 service_role cannot TRUNCATE payout_attempts');
SELECT tap.logout();
SELECT is((SELECT count(*) FROM public.payout_attempts), (SELECT n FROM _cnt), 'A3 ledger row count unchanged');

-- ── Grants ──────────────────────────────────────────────────────────────────
SELECT ok(NOT has_function_privilege('anon', 'public.claim_payout_attempt(uuid, text, interval)', 'EXECUTE'),
  'anon cannot EXECUTE claim_payout_attempt');
SELECT ok(NOT has_function_privilege('authenticated', 'public.record_payout_attempt_result(uuid, text, text, jsonb)', 'EXECUTE'),
  'authenticated cannot EXECUTE record_payout_attempt_result');
SELECT ok(has_function_privilege('service_role', 'public.claim_payout_attempt(uuid, text, interval)', 'EXECUTE'),
  'service_role can EXECUTE claim_payout_attempt');
SELECT ok(
  NOT has_table_privilege('anon', 'public.payout_attempts', 'SELECT')
  AND NOT has_table_privilege('authenticated', 'public.payout_attempts', 'SELECT')
  AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.payout_attempts'::regclass)
  AND (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payout_attempts') = 0,
  'payout_attempts: RLS on, zero policies, no client privileges');

SELECT * FROM finish();
ROLLBACK;
