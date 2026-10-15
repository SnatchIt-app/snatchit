-- ============================================================================
-- 222_listing_duration_72h.sql — migration 155 (20261015000100).
-- The listing duration allow-list gains 72 h and nothing else. The client create path (an onboarded,
-- phone-verified seller through the INSERT policy) accepts 72; 96 and 0 stay refused; the old values
-- still work. Expiry is unchanged: the finalizer acts on ends_at, not duration_hours.
-- ============================================================================
BEGIN;
SELECT plan(7);
SELECT tap.seed_core();

CREATE FUNCTION tap._try222(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg);
END $f$;
-- The client create shape (CreateListingScreen / web create-listing) with a chosen duration.
CREATE FUNCTION tap._create222(p_hours int) RETURNS text LANGUAGE sql AS $f$
  SELECT format($i$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
        transfer_method, starting_bid, buy_now_enabled, duration_hours, ends_at, current_bid, cover_image_path)
     VALUES (%L, %L, 'Club 222', 'wynwood', current_date + 7, '21:00', 'GA', 2,
             'mobile_transfer', 60, false, %s, now() + make_interval(hours => %s), 60, 'covers/222.jpg') $i$,
     tap.seller(), 'Fixture 222 ' || p_hours || 'h', p_hours, greatest(p_hours, 1)) $f$;

SELECT is((SELECT pg_get_constraintdef(oid) FROM pg_constraint
            WHERE conrelid = 'public.listings'::regclass AND conname = 'listings_duration_hours_check'),
  'CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72])))',
  '1: listings_duration_hours_check is exactly {1,3,6,12,24,48,72}');

SELECT tap.login(tap.seller());
SELECT is(tap._try222(tap._create222(72)), '{"ok": true}'::jsonb, '2: a seller creates a 72 h listing through the client insert path');
SELECT is((SELECT duration_hours || '|' || (ends_at - now())::text FROM public.listings WHERE event_name = 'Fixture 222 72h'), '72|3 days',
  '3: the 72 h listing is stored with duration 72 and ends 72 h out');
SELECT is(tap._try222(tap._create222(96)) ->> 'code', '23514', '4: 96 h is refused (check violation)');
SELECT is(tap._try222(tap._create222(0)) ->> 'code', '23514', '5: 0 h is refused (check violation)');
SELECT is(tap._try222(tap._create222(48)), '{"ok": true}'::jsonb, '6: the previous maximum, 48 h, is still accepted');
SELECT tap.logout();
SELECT is(tap._try222(tap._create222(73)) ->> 'code', '23514', '7: the trusted path cannot store an off-list value either (73 h)');

SELECT * FROM finish();
ROLLBACK;
