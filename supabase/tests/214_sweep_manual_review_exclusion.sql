-- 214_sweep_manual_review_exclusion.sql — pgTAP for migration 20260923000000 (registry 147).
-- Reproduces the 2026-09-23 production incident shape: a succeeded live-mode external-rail payment whose
-- listing is NOT 'sold' (sold_at set, status left 'active') and which already carries a transfer with a
-- completed payout. Before the fix, get_unsettled_payments re-selected it on every run once the sweep had
-- parked it under 'unfulfillable:manual_review' (the paid_unsettled branch never consulted the marker).
-- Negative controls (all predicted before they were run):
--   gate tree (no 147)                    -> exactly A2, A3, A5, A6, A7, A11, A12 fail
--   M1: parentheses removed from the test-mode disjunction (A OR B AND C) -> exactly A12 fails
--   M2: exclusion widened to LIKE 'unfulfillable%'                        -> exactly A13 fails
BEGIN;
SELECT plan(13);
SELECT tap.seed_core();
CREATE FUNCTION tap._id214(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $m$ SELECT ('21400000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $m$;

-- Listings: L1 = the incident listing (active WITH sold_at); L2 = a genuinely unsettled one; L3, L4, L5 hosts;
-- L6, L7 = two more incident-shaped listings (A12, A13).
INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
SELECT tap._id214(n), tap.seller(), 'Fixture 214-' || n, 'Club 214', 'wynwood', current_date + 30, '21:00', 'GA', 2,
       'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/214.jpg', 'active'
  FROM generate_series(1, 7) n;
-- sold_at is a guarded state column: set it the way the RPCs do (transaction-local bypass), status stays 'active'.
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET sold_at = now() - interval '50 days', auction_status = 'cancelled'
 WHERE id IN (tap._id214(1), tap._id214(6), tap._id214(7));
SELECT set_config('app.bypass_listing_guard', 'off', true);

-- Payments (all live-mode so the test-mode switch is irrelevant):
--   P1 incident: succeeded, paid 50 days ago, on L1, with a transfer (below)
--   P2 valid eligible: succeeded, paid 1 hour ago, on L2, no transfer, no marker — must still be listed
--   P3 pending_stale shape on L3 (20 min old), P4 processing_stale shape on L4 (20 min old)
--   P5 succeeded on L5 with a RESOLVED manual_review marker only — must still be listed
--   P6, P7 incident-shaped (succeeded, paid 50 days ago, transfer with payout) on L6, L7 — A12 and A13
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, paid_at, stripe_livemode)
VALUES (tap._id214(11), tap._id214(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_incident', 'succeeded',  'buy_now', now() - interval '50 days',   now() - interval '50 days', true),
       (tap._id214(12), tap._id214(2), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_eligible', 'succeeded',  'buy_now', now() - interval '1 hour',    now() - interval '1 hour',   true),
       (tap._id214(13), tap._id214(3), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_pending',  'pending',    'buy_now', now() - interval '20 minutes', NULL,                        true),
       (tap._id214(14), tap._id214(4), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_process',  'processing', 'buy_now', now() - interval '20 minutes', NULL,                        true),
       (tap._id214(15), tap._id214(5), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_resolved', 'succeeded',  'buy_now', now() - interval '2 hours',   now() - interval '2 hours',  true),
       (tap._id214(16), tap._id214(6), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_testmode', 'succeeded',  'buy_now', now() - interval '50 days',   now() - interval '50 days', true),
       (tap._id214(17), tap._id214(7), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_214_relabel',  'succeeded',  'buy_now', now() - interval '50 days',   now() - interval '50 days', true);

-- P1's, P6's and P7's transfers: buyer confirmed, payout already recorded (the incident's exact shape).
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status,
                              seller_sent_at, buyer_confirmed_at, expires_at, stripe_transfer_id, payout_released_at)
VALUES (tap._id214(21), tap._id214(1), tap._id214(11), tap.seller(), tap.buyer(), 'mobile_transfer', 'buyer_confirmed',
        now() - interval '50 days', now() - interval '50 days', now() - interval '47 days', 'tr_214_incident', now() - interval '50 days'),
       (tap._id214(22), tap._id214(6), tap._id214(16), tap.seller(), tap.buyer(), 'mobile_transfer', 'buyer_confirmed',
        now() - interval '50 days', now() - interval '50 days', now() - interval '47 days', 'tr_214_testmode', now() - interval '50 days'),
       (tap._id214(23), tap._id214(7), tap._id214(17), tap.seller(), tap.buyer(), 'mobile_transfer', 'buyer_confirmed',
        now() - interval '50 days', now() - interval '50 days', now() - interval '47 days', 'tr_214_relabel',  now() - interval '50 days');

-- A1: the incident shape IS the sweep's business before any marker exists (this is how the loop started).
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(11)), 'paid_unsettled',
  'A1: a succeeded payment whose listing is not sold is listed as paid_unsettled before any marker exists');

-- The sweep parks it: settle_verified_payment wrote a review row and the edge marked it manual_review.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap._id214(11), tap._id214(1), 'settle_verified_payment', 'unfulfillable:manual_review', false);

-- A2/A3: under an unresolved manual_review marker the payment is NOT selected — on this run and on the next.
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(11)), 0,
  'A2: a payment under unresolved manual review is not selected by paid_unsettled');
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(11)), 0,
  'A3: repeated run — still not selected (no re-selection loop)');

-- A4: a genuinely unsettled payment with no marker must still be listed (selection only; settlement is the edge's).
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(12)), 'paid_unsettled',
  'A4: a valid eligible payment (no marker) is still listed as paid_unsettled');

-- A5: no bypass through review_unfulfillable — a second, ordinary unresolved review row for the SAME payment
-- (the shape settle_verified_payment writes on every run) does not bring it back while the marker is unresolved.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap._id214(11), tap._id214(1), 'settle_verified_payment', 'unfulfillable:card_declined', false);
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(11)), 0,
  'A5: an ordinary unresolved review row cannot bypass the manual_review exclusion (review_unfulfillable branch)');

-- A6/A7: no bypass through pending_stale / processing_stale either.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap._id214(13), tap._id214(3), 'settle_verified_payment', 'unfulfillable:manual_review', false),
       (tap._id214(14), tap._id214(4), 'settle_verified_payment', 'unfulfillable:manual_review', false);
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(13)), 0,
  'A6: a pending_stale-shaped payment under manual review is not selected');
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(14)), 0,
  'A7: a processing_stale-shaped payment under manual review is not selected');

-- A8: eligible again — the operator resolves the review rows; the payment returns to the work list.
UPDATE public.webhook_retries SET resolved = true WHERE payment_id = tap._id214(11);
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(11)), 'paid_unsettled',
  'A8: once every review row is resolved the payment is eligible again (never permanently stranded)');

-- A9: a RESOLVED manual_review marker alone excludes nothing.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap._id214(15), tap._id214(5), 'settle_verified_payment', 'unfulfillable:manual_review', true);
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(15)), 'paid_unsettled',
  'A9: a resolved manual_review marker does not exclude the payment');

-- A12: the exclusion holds under the sandbox-only test-mode switch. The switch is the FIRST disjunct of the
-- deduped WHERE; without the parentheses Postgres binds `A OR (B AND C)` and, with the switch on, the exclusion
-- is bypassed entirely. Production never sets the switch, so only this assertion can see that mistake.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap._id214(16), tap._id214(6), 'settle_verified_payment', 'unfulfillable:manual_review', false);
SELECT set_config('app.allow_test_mode_money', 'on', true);
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(16)), 0,
  'A12: the manual_review exclusion still applies with app.allow_test_mode_money = on (parenthesisation)');
SELECT set_config('app.allow_test_mode_money', 'off', true);

-- A13: the exclusion is EXACT on purpose. The producer chain writes 'unfulfillable:listing' (settle_verified_payment)
-- and the edge relabels it to 'unfulfillable:manual_review' best-effort. A row the relabel has not (yet) reached is
-- still sweep work: it is selected under review_unfulfillable (priority 1, never paid_unsettled), whose handler
-- retries the relabel, and settle_verified_payment's own guard suppresses a second insert while it is unresolved.
-- Widening the exclusion to LIKE 'unfulfillable%' would silence review_unfulfillable for EVERY candidate (each one
-- carries exactly such a row) and stop the refund path — this assertion is the guard against that widening.
INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
VALUES (tap._id214(17), tap._id214(7), 'settle_verified_payment', 'unfulfillable:listing', false);
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id214(17)), 'review_unfulfillable',
  'A13: an unresolved producer literal (unfulfillable:listing, not yet relabeled) stays selectable as review_unfulfillable');

-- A10/A11: grants unchanged; the comment names the new rule.
SELECT ok(has_function_privilege('service_role', 'public.get_unsettled_payments(integer)', 'execute')
      AND NOT has_function_privilege('authenticated', 'public.get_unsettled_payments(integer)', 'execute')
      AND NOT has_function_privilege('anon', 'public.get_unsettled_payments(integer)', 'execute'),
  'A10: grants unchanged — service_role only');
SELECT matches(obj_description('public.get_unsettled_payments(integer)'::regprocedure, 'pg_proc'), 'manual_review',
  'A11: the function comment names the manual_review exclusion');

SELECT * FROM finish();
ROLLBACK;
