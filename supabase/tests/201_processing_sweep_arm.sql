-- 201_processing_sweep_arm.sql — pgTAP for migration 20260916000000 (registry 134, processing_stale arm).
-- Negative control: on the chain without 134, A1 fails (no processing row is ever listed).
BEGIN;
SELECT plan(9);
SELECT tap.seed_core();
CREATE FUNCTION tap._id201(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $m$ SELECT ('20100000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $m$;

INSERT INTO public.listings
  (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
   starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
VALUES (tap._id201(1), tap.seller(), 'Fixture 201', 'Club 201', 'wynwood', current_date + 30, '21:00', 'GA', 2,
        'mobile_transfer', 100, true, 200, 24, now(), now() + interval '24 hours', 100, 'fixtures/201.jpg', 'active');

-- live-mode rows (stripe_livemode true) so the test-mode switch is irrelevant
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, created_at, stripe_livemode)
VALUES (tap._id201(11), tap._id201(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_201_proc_20m', 'processing', 'buy_now', now() - interval '20 minutes', true),
       (tap._id201(12), tap._id201(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_201_proc_5m',  'processing', 'buy_now', now() - interval '5 minutes',  true),
       (tap._id201(13), tap._id201(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_201_proc_8d',  'processing', 'auction', now() - interval '8 days',     true),
       (tap._id201(14), tap._id201(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, NULL,               'processing', 'buy_now', now() - interval '20 minutes', true),
       (tap._id201(15), tap._id201(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_201_pend_20m', 'pending',    'buy_now', now() - interval '20 minutes', true),
       (tap._id201(16), tap._id201(1), tap.buyer(), tap.seller(), 20000, 2000, 2000, 22000, 'pi_201_proc_nul', 'processing', 'buy_now', now() - interval '20 minutes', NULL);

SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(11)), 'processing_stale',
  'A1: a processing row 20 min old is listed as processing_stale');
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(12)), 0,
  'A2: a processing row 5 min old is NOT listed (inside the 15-minute grace)');
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(13)), 0,
  'A3: a processing row 8 days old is NOT listed (outside the 7-day window)');
SELECT is((SELECT count(*)::int FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(14)), 0,
  'A4: a processing row without an intent id is NOT listed');
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(15)), 'pending_stale',
  'A5: the pending_stale arm is unchanged');
SELECT is((SELECT kind FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(16)), 'legacy_unknown_mode',
  'A6: a processing row with unknown livemode is counted as legacy_unknown_mode (never fetched)');
SELECT is((SELECT status FROM public.get_unsettled_payments(50) WHERE payment_id = tap._id201(11)), 'processing',
  'A7: the row''s status rides along so the edge can branch on it');
SELECT ok(has_function_privilege('service_role', 'public.get_unsettled_payments(integer)', 'execute')
      AND NOT has_function_privilege('authenticated', 'public.get_unsettled_payments(integer)', 'execute')
      AND NOT has_function_privilege('anon', 'public.get_unsettled_payments(integer)', 'execute'),
  'A8: grants unchanged — service_role only');
SELECT matches(obj_description('public.get_unsettled_payments(integer)'::regprocedure, 'pg_proc'), 'processing_stale',
  'A9: the function comment names the new kind');

SELECT * FROM finish();
ROLLBACK;
