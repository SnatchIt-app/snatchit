-- ============================================================================
-- 090_webhooks.sql — the 064 claim/complete/fail lease: first claim wins, a
-- live lease returns in_flight, completion is terminal, failure releases the
-- lease immediately, an abandoned lease is recovered after timeout. Plus 061:
-- ensure_transfer_exists() only ever mints a transfer from a VERIFIED
-- (succeeded) payment — the free-ticket exploit stays dead.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(21);
SELECT tap.seed_core();

-- ── Client bans ─────────────────────────────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok($$ SELECT * FROM public.stripe_webhook_events $$,
  '42501', NULL, 'authenticated cannot read webhook events');
SELECT throws_ok($$ SELECT * FROM public.webhook_retries $$,
  '42501', NULL, 'authenticated cannot read webhook retries (069)');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.stripe_webhook_events $$,
  '42501', NULL, 'anon cannot read webhook events');
SELECT tap.logout();
SELECT ok(NOT has_function_privilege('anon',          'public.claim_stripe_webhook_event(text,text,integer)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.claim_stripe_webhook_event(text,text,integer)', 'EXECUTE'),
  'clients cannot execute claim_stripe_webhook_event (064)');
SELECT ok(NOT has_function_privilege('authenticated', 'public.complete_stripe_webhook_event(text)', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.fail_stripe_webhook_event(text,text)', 'EXECUTE'),
  'clients cannot execute complete/fail webhook RPCs (064)');

-- ── Lease semantics (service path) ──────────────────────────────────────────
SELECT is(public.claim_stripe_webhook_event('evt_t1', 'payment_intent.succeeded', 300),
  'claimed', 'first claim wins');
SELECT is(public.claim_stripe_webhook_event('evt_t1', 'payment_intent.succeeded', 300),
  'in_flight', 'second claim inside the lease returns in_flight (no double-processing)');
SELECT is((SELECT attempt_count FROM public.stripe_webhook_events WHERE event_id = 'evt_t1'),
  1, 'losing claim did not bump attempt_count');
SELECT is(public.complete_stripe_webhook_event('evt_t1'), true, 'completion succeeds');
SELECT is(public.claim_stripe_webhook_event('evt_t1', 'payment_intent.succeeded', 300),
  'already_processed', 'a completed event can never be re-claimed');
SELECT is(public.fail_stripe_webhook_event('evt_t1', 'late failure'), false,
  'a completed event cannot be dragged back to failed');

-- Abandoned lease: claimed, isolate dies, no complete/fail — timeout recovers.
SELECT is(public.claim_stripe_webhook_event('evt_t2', 'charge.dispute.created', 300),
  'claimed', 'evt_t2 claimed');
SELECT lives_ok(
  $$ UPDATE public.stripe_webhook_events
        SET claimed_at = claimed_at - interval '10 minutes'
      WHERE event_id = 'evt_t2' $$,
  'backdate the lease past its timeout (service path)');
SELECT is(public.claim_stripe_webhook_event('evt_t2', 'charge.dispute.created', 300),
  'claimed', 'an abandoned lease is re-claimable after the timeout');
SELECT is((SELECT attempt_count FROM public.stripe_webhook_events WHERE event_id = 'evt_t2'),
  2, 'retry visible in attempt_count');

-- Failure releases the lease immediately (no timeout wait).
SELECT is(public.fail_stripe_webhook_event('evt_t2', 'boom'), true, 'failure recorded');
SELECT ok((SELECT claimed_at IS NULL AND failed_at IS NOT NULL AND last_error = 'boom'
             FROM public.stripe_webhook_events WHERE event_id = 'evt_t2'),
  'failure released the lease and kept the error');
SELECT is(public.claim_stripe_webhook_event('evt_t2', 'charge.dispute.created', 300),
  'claimed', 'the next delivery re-claims immediately after a failure');

-- ── 061: transfers only from verified payments ──────────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ SELECT public.ensure_transfer_exists(tap.listing_d(), NULL) $$,
  'P0001',
  'No verified payment found for this listing. Payment must be confirmed before a transfer can be created.',
  'a PENDING payment cannot mint a transfer (free-purchase exploit stays dead, 061)');
SELECT results_eq(
  $$ SELECT public.ensure_transfer_exists(tap.listing_a(), NULL) $$,
  ARRAY['cccccccc-0000-0000-0000-000000000001'::uuid],
  'a succeeded payment resolves to its existing transfer (idempotent)');
SELECT results_eq(
  $$ SELECT public.ensure_transfer_exists(tap.listing_a(), NULL) $$,
  ARRAY['cccccccc-0000-0000-0000-000000000001'::uuid],
  'repeat call returns the same transfer — no duplicates');

SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
