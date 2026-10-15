-- ============================================================================
-- 222_listing_duration_72h.sql — migration 155 (20261015000100).
-- The listing duration allow-list gains 72 h and nothing else, and the end time is server-owned:
--   * the client create path (an onboarded, phone-verified seller through the INSERT policy) accepts 72;
--     96 and 0 stay refused; the old values still work;
--   * an untrusted insert's ends_at is overwritten with now() + duration_hours, whatever the device sent
--     (each client row below sends ends_at = now() + 1 hour, so a pass cannot be the client's own value);
--   * an untrusted update cannot move ends_at or duration_hours, even inside a definer function, unless
--     an auction RPC set the listing-guard bypass (admin_relist_listing through the ops chain);
--   * trusted callers (claims-less postgres, service_role) keep the value they write.
-- Expiry is unchanged: the finalizer acts on ends_at.
-- ============================================================================
BEGIN;
SELECT plan(25);
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
-- The client create shape (CreateListingScreen / web create-listing) with a chosen duration and the
-- ends_at the device computed (deliberately NOT now() + duration, so the server's value is observable).
CREATE FUNCTION tap._create222(p_hours int, p_tag text, p_client_ends interval DEFAULT interval '1 hour') RETURNS text LANGUAGE sql AS $f$
  SELECT format($i$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
        transfer_method, starting_bid, buy_now_enabled, duration_hours, ends_at, current_bid, cover_image_path)
     VALUES (%L, %L, 'Club 222', 'wynwood', current_date + 7, '21:00', 'GA', 2,
             'mobile_transfer', 60, false, %s, now() + %L::interval, 60, 'covers/222.jpg') $i$,
     tap.seller(), 'Fixture 222 ' || p_tag, p_hours, p_client_ends) $f$;
CREATE FUNCTION tap._stored222(p_tag text) RETURNS text LANGUAGE sql AS $f$
  SELECT duration_hours || '|' || (ends_at - now())::text FROM public.listings WHERE event_name = 'Fixture 222 ' || p_tag $f$;
CREATE FUNCTION tap._id222(p_tag text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM public.listings WHERE event_name = 'Fixture 222 ' || p_tag $f$;
-- A definer function the client can call that writes ends_at WITHOUT the listing-guard bypass (the shape
-- of any future RPC that forgets to opt in), and one that relists through admin_relist_listing (the shape
-- of ops.action_dispatch 'listing_relist': definer, admin claims, the RPC sets the bypass).
CREATE FUNCTION tap._definer_patch222(p_id uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  UPDATE public.listings SET ends_at = now() + interval '9 days' WHERE id = p_id $f$;
CREATE FUNCTION tap._definer_relist222(p_id uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  SELECT public.admin_relist_listing(p_id, now() + interval '72 hours', tap.admin_user()) $f$;
GRANT EXECUTE ON FUNCTION tap._definer_patch222(uuid), tap._definer_relist222(uuid) TO authenticated;
-- Admin-owned inventory in the cancelled resting state with no history (what admin_relist_listing accepts).
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
  transfer_method, starting_bid, buy_now_enabled, duration_hours, starts_at, ends_at, current_bid, cover_image_path,
  status, auction_status)
VALUES ('dddddddd-0222-0000-0000-000000000001', tap.admin_user(), 'Fixture 222 relist', 'Club 222', 'wynwood', current_date + 7,
  '21:00', 'GA', 1, 'mobile_transfer', 60, false, 24, now() - interval '2 days', now() - interval '1 day', 60, 'covers/222r.jpg',
  'active', 'cancelled');

-- ── wiring ──────────────────────────────────────────────────────────────────
SELECT is((SELECT pg_get_constraintdef(oid) FROM pg_constraint
            WHERE conrelid = 'public.listings'::regclass AND conname = 'listings_duration_hours_check'),
  'CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48, 72])))',
  '1: listings_duration_hours_check is exactly {1,3,6,12,24,48,72}');
SELECT is((SELECT string_agg(c.relname || '.' || t.tgname || ':' || t.tgtype::text || ':' || t.tgfoid::regproc::text, ' ')
             FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
            WHERE NOT t.tgisinternal AND t.tgname = 'trg_listing_ends_at_from_duration'),
  'listings.trg_listing_ends_at_from_duration:23:set_listing_ends_at_from_duration',
  '2: BEFORE INSERT OR UPDATE row trigger on listings runs set_listing_ends_at_from_duration');
SELECT is((SELECT p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ','), '-') || '|'
                  || has_function_privilege('anon', p.oid, 'EXECUTE')::text || '|' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.set_listing_ends_at_from_duration()')),
  'false|search_path=""|false|false',
  '3: set_listing_ends_at_from_duration is SECURITY INVOKER, search_path empty, not client-executable');

-- ── the client create path: the server owns the end time ────────────────────
SELECT tap.login(tap.seller());
SELECT is(tap._try222(tap._create222(72, '72h')), '{"ok": true}'::jsonb, '4: a seller creates a 72 h listing through the client insert path');
SELECT is(tap._stored222('72h'), '72|3 days',
  '5: the 72 h listing ends exactly 72 h after the insert (server clock), not at the 1 h the client sent');
SELECT is(tap._try222(tap._create222(96, '96h')) ->> 'code', '23514', '6: 96 h is refused (check violation)');
SELECT is(tap._try222(tap._create222(0, '0h')) ->> 'code', '23514', '7: 0 h is refused (check violation)');
SELECT is(tap._try222(tap._create222(48, '48h')), '{"ok": true}'::jsonb, '8: the previous maximum, 48 h, is still accepted');
SELECT is(tap._stored222('48h'), '48|2 days', '9: the 48 h listing ends 48 h after the insert, not at the client''s 1 h');
SELECT is(tap._try222(tap._create222(24, 'skew', interval '-1 day')), '{"ok": true}'::jsonb,
  '10: a create whose device clock is a day behind is accepted');
SELECT is(tap._stored222('skew'), '24|1 day',
  '11: ... and cannot make an already-ended listing: ends_at is now() + 24 h, not the device''s past time');

-- ── untrusted updates cannot move the end time or the duration ──────────────
SELECT is(tap._try222(format('UPDATE public.listings SET ends_at = now() + interval ''9 days'' WHERE id = %L', tap._id222('72h'))),
  '{"ok": false, "code": "P0001", "message": "Cannot change a listing''s end time or duration after it is created."}'::jsonb,
  '12: the seller cannot PATCH ends_at on their own listing (the listings UPDATE policies allow the row)');
SELECT is(tap._try222(format('UPDATE public.listings SET duration_hours = 1 WHERE id = %L', tap._id222('72h'))),
  '{"ok": false, "code": "P0001", "message": "Cannot change a listing''s end time or duration after it is created."}'::jsonb,
  '13: the seller cannot PATCH duration_hours either');
SELECT is(tap._try222(format('UPDATE public.listings SET event_name = %L, venue = %L, restrictions = %L, ticket_platform = %L WHERE id = %L',
                             'Fixture 222 72h', 'Club 222 Edited', '21+', 'dice', tap._id222('72h'))),
  '{"ok": true}'::jsonb, '14: the shipped edit payload (event_name, venue, restrictions, ticket_platform) still saves');
SELECT is(tap._try222(format('SELECT tap._definer_patch222(%L)', tap._id222('72h'))),
  '{"ok": false, "code": "P0001", "message": "Cannot change a listing''s end time or duration after it is created."}'::jsonb,
  '15: inside a definer function the client is still untrusted: no ends_at move without the RPC bypass');
SELECT is(tap._stored222('72h'), '72|3 days', '16: after 12, 13 and 15 the 72 h listing still ends 72 h after its insert');
SELECT tap.login(tap.admin_user());
SELECT is(tap._try222(format('SELECT tap._definer_relist222(%L)', 'dddddddd-0222-0000-0000-000000000001')), '{"ok": true}'::jsonb,
  '17: an admin relist through the definer chain (ops.action_dispatch shape; admin_relist_listing sets the listing-guard bypass) succeeds');
SELECT tap.reset_guards();
SELECT tap.logout();
SELECT is((SELECT auction_status || '|' || (ends_at - now())::text FROM public.listings WHERE id = 'dddddddd-0222-0000-0000-000000000001'),
  'active|3 days', '18: ... and moved ends_at: the guard honours the auction RPCs'' bypass');

-- ── trusted callers keep their own value ────────────────────────────────────
SELECT is(tap._try222(tap._create222(73, '73h')) ->> 'code', '23514', '19: the trusted path cannot store an off-list value either (73 h)');
SELECT is(tap._try222(tap._create222(72, 'trusted', interval '5 hours')), '{"ok": true}'::jsonb,
  '20: a claims-less postgres insert (migrations, seeds, the SQL editor) is accepted');
SELECT is(tap._stored222('trusted'), '72|05:00:00', '21: ... and keeps the ends_at it wrote');
SELECT tap.login_service();
SELECT is(tap._try222(tap._create222(72, 'service', interval '7 hours')), '{"ok": true}'::jsonb, '22: a service_role insert is accepted');
SELECT tap.logout();
SELECT is(tap._stored222('service'), '72|07:00:00', '23: ... and keeps the ends_at it wrote');
SELECT is(tap._try222(format('UPDATE public.listings SET ends_at = now() + interval ''6 hours'' WHERE id = %L', tap._id222('trusted'))),
  '{"ok": true}'::jsonb, '24: a claims-less postgres update may move ends_at (the operator path is untouched)');
SELECT is(tap._stored222('trusted'), '72|06:00:00', '25: ... and the new end time is stored');

SELECT * FROM finish();
ROLLBACK;
