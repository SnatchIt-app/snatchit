BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(9);
SELECT tap.seed_core();
SELECT tap.logout();

UPDATE public.payments SET stripe_livemode = true WHERE id = tap.payment_b();
UPDATE public.profiles SET stripe_connect_id = 'acct_fixture' WHERE id = tap.seller();
SELECT is(public.apply_auto_release(tap.transfer_b()), true, 'fixture transfer is releasable');

CREATE TEMP TABLE first_attempt AS
  SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'cron:enforce-transfer-expiry');
SELECT is(public.mark_payout_requested((SELECT attempt_id FROM first_attempt)), true, 'fixture Stripe request');
SELECT is(public.record_payout_attempt_result(
  (SELECT attempt_id FROM first_attempt), NULL, 'failed_not_created',
  '{"reason_code":"PAYOUT_INSUFFICIENT_FUNDS","error_class":"insufficient_funds"}'::jsonb
)->>'state', 'failed', 'confirmed refusal closes the first attempt');
SELECT throws_ok(
  $$SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'cron:enforce-transfer-expiry')$$,
  'P0001', 'PAYOUT_FUNDING_COOLDOWN', 'the next scheduled sweep cannot allocate a Stripe attempt');
SELECT is((SELECT count(*) FROM public.payout_attempts WHERE transfer_id = tap.transfer_b()),
  1::bigint, 'cooldown leaves the attempt ledger unchanged');

CREATE TEMP TABLE operator_attempt AS
  SELECT * FROM public.claim_payout_attempt(tap.transfer_b(), 'edge:test-operator');
SELECT is((SELECT attempt_no FROM operator_attempt), 2, 'the cooldown is scoped to the failing schedule');
UPDATE public.payout_attempts SET lease_expires_at = now() - interval '1 minute'
 WHERE id = (SELECT attempt_id FROM operator_attempt);
SELECT is((SELECT needs_reconcile FROM public.claim_payout_attempt(tap.transfer_b(), 'cron:enforce-transfer-expiry')),
  true, 'an open attempt is still reconciled after a funding failure');
SELECT is(public.record_payout_attempt_result(
  (SELECT attempt_id FROM operator_attempt), NULL, 'failed_not_created',
  '{"error_class":"balance_insufficient"}'::jsonb
)->>'state', 'failed', 'structured funding failures are retained');
UPDATE public.payout_attempts SET resolved_at = now() - interval '1 hour'
 WHERE id = (SELECT attempt_id FROM operator_attempt);
SELECT is((SELECT attempt_no FROM public.claim_payout_attempt(tap.transfer_b(), 'cron:enforce-transfer-expiry')),
  3, 'an hour later the schedule may try again');

SELECT * FROM finish();
ROLLBACK;
