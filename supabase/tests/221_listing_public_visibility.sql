-- ============================================================================
-- 221_listing_public_visibility.sql — migration 154 (20261015000000).
-- Hidden listings leave public access on every surface; their private parties keep it.
--   A. wiring: the two replacement SELECT policies (no USING true, no kernel/is_admin), the deny-all
--      side table, the two anon-executable predicates, the invariant trigger pair.
--   B. anon: the PostgREST statements shipped builds send (home, sold, ended, explore, profile,
--      detail by id, bid history) return the public rows and no hidden row.
--   C. a fresh signed-in non-participant: the same, plus market.listing_unified parity.
--   D. private parties: seller, bidder, winner, reservation holder, payment buyer, transfer buyer and
--      transfer seller each see exactly their own hidden listing(s) and its bids; an admin who is not
--      a party sees none of them (no admin clause).
--   E. saved_listings, reports and notifications grant nothing.
--   F. listing_visibility: no client read, insert, update or delete (seller included); service_role can.
--   G. invariant: an OPEN listing (what reserve_buy_now accepts: active/reserved, auction not cancelled,
--      clock not run out) or one under a live Buy Now hold cannot be hidden; a hidden listing cannot be
--      made OPEN, held or extended by any caller (the review's reproductions: the seller's ends_at PATCH on
--      an ended row, a non-party's reserve_buy_now, the wedge on a hidden held row); bids and the
--      create-payment-intent preconditions are refused on every hidden row; non-live edits, the
--      finalizer and the reservation sweep still pass.
--   H. storage: a hidden listing still counts as a reference for its seller's cover.
--   I. get_profile_trust_stats counts nothing derived from hidden listings, and active_listings needs
--      an unexpired clock.
--   K. review fix: listing_visibility.listing_id is ON DELETE RESTRICT, so nobody (the seller included) can
--      delete a hidden listing to erase its hide row and re-create the id publicly; a public listing with no
--      history is still deletable by its seller.
--   J. positive control: with USING (true) put back, the same anon probe sees every hidden row.
--   ADDENDUM 2 also covers: the is_public(listings) computed field (A9/A10/B12/B13/D15/D16) and the
--   no-recursion guarantee (A12/A13: the predicates are owned by the tables' owner, which bypasses RLS,
--   and none of the tables forces RLS).
-- Fixtures are built as postgres before any login. Each persona holds exactly one relation to the
-- hidden rows, so dropping one clause of listing_private_party fails that persona's assertion.
-- The transfer-party personas (TBUY/TSELL) use one deliberately isolated transfer: in production the
-- transfer parties always equal the listing seller and the payment buyer, so this fixture is the only
-- way to prove the transfers clause on its own (defence in depth, not a production state).
-- Helpers are version-agnostic (dynamic SQL, errors caught), so the suite runs to completion on a
-- database without 154 and reports each exposure as its own failure.
-- ============================================================================
BEGIN;
SELECT plan(100);
SELECT tap.seed_core();

-- ── helpers ────────────────────────────────────────────────────────────────
CREATE FUNCTION tap._l221(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('dddddddd-0221-0000-0000-' || v.suffix)::uuid
    FROM (VALUES ('H1','000000000101'), ('H2','000000000102'), ('H3','000000000103'), ('H4','000000000104'),
                 ('H5','000000000105'), ('H6','000000000106'), ('H7','000000000107'),
                 ('VSOLD','000000000201'), ('VENDED','000000000202'), ('VRELIST','000000000203'),
                 ('VRESV','000000000204'), ('VLIVE','000000000205'), ('VEARLY','000000000206'),
                 ('VHOLD','000000000207')) AS v(tag, suffix)
   WHERE v.tag = p $f$;
CREATE FUNCTION tap._u221(p text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('22100000-0000-0000-0000-' || v.suffix)::uuid
    FROM (VALUES ('BID','000000000001'), ('WIN','000000000002'), ('PAY','000000000003'), ('RES','000000000004'),
                 ('TBUY','000000000005'), ('TSELL','000000000006'), ('FRESH','000000000007'),
                 ('SAVER','000000000008'), ('REP','000000000009'), ('NOTE','000000000010')) AS v(tag, suffix)
   WHERE v.tag = p $f$;
CREATE FUNCTION tap._hidden221() RETURNS uuid[] LANGUAGE sql IMMUTABLE AS $f$
  SELECT ARRAY[tap._l221('H1'), tap._l221('H2'), tap._l221('H3'), tap._l221('H4'),
               tap._l221('H5'), tap._l221('H6'), tap._l221('H7')] $f$;
-- Sorted id array from a statement run as the CURRENT role; NULL if the statement fails (for example
-- is_public absent on a database without 154), so the assertion fails and the file runs on.
CREATE FUNCTION tap._ids221(p_sql text) RETURNS uuid[] LANGUAGE plpgsql AS $f$
DECLARE v uuid[];
BEGIN
  EXECUTE format('SELECT coalesce(array_agg(x.id ORDER BY x.id), ''{}'') FROM (%s) x', p_sql) INTO v;
  RETURN v;
EXCEPTION WHEN others THEN
  RETURN NULL;
END $f$;
CREATE FUNCTION tap._sorted221(p uuid[]) RETURNS uuid[] LANGUAGE sql IMMUTABLE AS $f$
  SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM unnest(p) x $f$;
-- Runs a statement as the CURRENT role; returns ok or the SQLSTATE and message.
CREATE FUNCTION tap._try221(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg);
END $f$;
-- First column of a one-row statement run as the CURRENT role, as text; 'ERROR:<sqlstate>' on failure.
CREATE FUNCTION tap._val221(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text; v_state text;
BEGIN
  EXECUTE p_sql INTO v;
  RETURN v;
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  RETURN 'ERROR:' || v_state;
END $f$;
CREATE FUNCTION tap._hide_sql221(p uuid) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT format('INSERT INTO public.listing_visibility (listing_id, hidden_reason, hidden_by) VALUES (%L, %L, %L)',
                p, 'pgTAP 221 hidden fixture', 'tap') $f$;
CREATE FUNCTION tap._count221(p_sql text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v bigint;
BEGIN
  EXECUTE format('SELECT count(*) FROM (%s) x', p_sql) INTO v;
  RETURN v;
END $f$;
-- Rows affected by a data-modifying statement run as the CURRENT role.
CREATE FUNCTION tap._dml221(p_sql text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v bigint;
BEGIN
  EXECUTE format('WITH x AS (%s) SELECT count(*) FROM x', p_sql) INTO v;
  RETURN v;
END $f$;
-- create-payment-intent's preconditions (supabase/functions/create-payment-intent/index.ts, the listing
-- read + sold-to-another check + the buy_now / auction branches), evaluated with the edge function's
-- service-role view (run as postgres). True = the edge function would go on to mint a PaymentIntent.
CREATE FUNCTION tap._cpi221(p_listing uuid, p_buyer uuid, p_mode text) RETURNS boolean LANGUAGE sql AS $f$
  SELECT coalesce((
    SELECT l.seller_id <> p_buyer
       AND NOT EXISTS (SELECT 1 FROM public.payments p
                        WHERE p.listing_id = l.id AND p.status = 'succeeded' AND p.buyer_id <> p_buyer)
       AND l.status <> 'sold'
       AND CASE p_mode
             WHEN 'buy_now' THEN l.status = 'reserved' AND l.reserved_by = p_buyer AND l.reserved_until > now()
                                 AND l.buy_now_enabled AND l.buy_now_price IS NOT NULL
             WHEN 'auction' THEN l.auction_status = 'ended' AND l.winner_user_id = p_buyer
                                 AND NOT (l.status = 'reserved' AND l.reserved_by IS NOT NULL
                                          AND l.reserved_until > now() AND l.reserved_by <> p_buyer)
           END
      FROM public.listings l WHERE l.id = p_listing), false) $f$;

-- ── fixtures (postgres, claims-less: the trusted path) ──────────────────────
INSERT INTO auth.users (id, instance_id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
SELECT tap._u221(t), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       lower(t) || '221@test.local', '{"provider":"email","providers":["email"]}', '{}', now(), now()
  FROM unnest(ARRAY['BID','WIN','PAY','RES','TBUY','TSELL','FRESH','SAVER','REP','NOTE']) t;

-- H1..H6 and the visible V* rows belong to the seed seller S; H7 and VRELIST are admin-owned inventory.
-- H1 starts live so bids can be placed through the real bid path; it is closed below.
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type,
  quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
  current_bid, cover_image_path, status, auction_status, reserved_by, reserved_until)
SELECT tap._l221(v.tag), v.seller, 'Fixture 221 ' || v.tag, 'Club 221', 'wynwood', current_date + 30, '21:00', 'GA',
       2, 'mobile_transfer', 100, true, 300, 24, now() - interval '2 days', v.ends_at, 100,
       v.seller::text || '/' || lower(v.tag) || '-221.jpg', v.status, v.auction_status, v.reserved_by, v.reserved_until
  FROM (VALUES
    ('H1',      tap.seller(),     'active',   'active',    now() + interval '24 hours', NULL::uuid,       NULL::timestamptz),
    ('H2',      tap.seller(),     'reserved', 'active',    now() - interval '1 hour',   tap._u221('RES'), now() - interval '1 minute'),
    ('H3',      tap.seller(),     'active',   'cancelled', now() + interval '3 days',   NULL,             NULL),
    ('H4',      tap.seller(),     'active',   'ended',     now() - interval '1 day',    NULL,             NULL),
    ('H5',      tap.seller(),     'sold',     'sold',      now() - interval '1 day',    NULL,             NULL),
    ('H6',      tap.seller(),     'active',   'active',    now() - interval '1 hour',   NULL,             NULL),
    ('H7',      tap.admin_user(), 'active',   'cancelled', now() - interval '1 day',    NULL,             NULL),
    ('VSOLD',   tap.seller(),     'sold',     'sold',      now() - interval '1 day',    NULL,             NULL),
    ('VENDED',  tap.seller(),     'active',   'ended',     now() - interval '1 day',    NULL,             NULL),
    ('VRELIST', tap.admin_user(), 'active',   'cancelled', now() - interval '1 day',    NULL,             NULL),
    ('VRESV',   tap.seller(),     'reserved', 'active',    now() + interval '24 hours', tap.buyer(),      now() + interval '10 minutes'),
    ('VLIVE',   tap.seller(),     'active',   'active',    now() + interval '24 hours', NULL,             NULL)
  ) AS v(tag, seller, status, auction_status, ends_at, reserved_by, reserved_until);

-- Bids through the bid trigger while H1 and VLIVE are live: BID 110 then WIN 120 on H1; BID 110 on VLIVE.
INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (tap._l221('H1'), tap._u221('BID'), 110);
INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (tap._l221('H1'), tap._u221('WIN'), 120);
INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (tap._l221('VLIVE'), tap._u221('BID'), 110);
-- H1 closes: sold to WIN (the settlement path writes these under the listing guard bypass).
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status = 'sold', auction_status = 'ended', ends_at = now() - interval '1 hour',
       winner_user_id = tap._u221('WIN'), winning_bid_amount = 120, sold_at = now() - interval '30 minutes',
       ended_at = now() - interval '1 hour'
 WHERE id = tap._l221('H1');
SELECT tap.reset_guards();

INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
  stripe_payment_intent_id, status, mode, paid_at) VALUES
  ('bbbbbbbb-0221-0000-0000-000000000001', tap._l221('H1'),    tap._u221('WIN'),  tap.seller(), 12000, 1200, 1200, 13200, 'pi_221_p1', 'succeeded', 'auction', now()),
  ('bbbbbbbb-0221-0000-0000-000000000000', tap._l221('H1'),    tap._u221('PAY'),  tap.seller(), 30000, 3000, 3000, 33000, 'pi_221_p0', 'failed',    'buy_now', NULL),
  ('bbbbbbbb-0221-0000-0000-000000000002', tap._l221('VSOLD'), tap.buyer(),       tap.seller(), 30000, 3000, 3000, 33000, 'pi_221_pv', 'succeeded', 'buy_now', now()),
  ('bbbbbbbb-0221-0000-0000-000000000005', tap._l221('VSOLD'), tap._u221('TBUY'), tap.seller(), 30000, 3000, 3000, 33000, 'pi_221_p5', 'failed',    'buy_now', NULL);
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status,
  buyer_confirmed_at, disputed_at, expires_at) VALUES
  ('cccccccc-0221-0000-0000-000000000001', tap._l221('H1'),    'bbbbbbbb-0221-0000-0000-000000000001', tap.seller(),       tap._u221('WIN'),  'mobile_transfer', 'buyer_confirmed', now(), NULL,  now() + interval '1 day'),
  ('cccccccc-0221-0000-0000-000000000002', tap._l221('VSOLD'), 'bbbbbbbb-0221-0000-0000-000000000002', tap.seller(),       tap.buyer(),       'mobile_transfer', 'buyer_confirmed', now(), NULL,  now() + interval '1 day'),
  -- clause-isolation transfer (see header): parties TSELL/TBUY hold no other relation to H5
  ('cccccccc-0221-0000-0000-000000000005', tap._l221('H5'),    'bbbbbbbb-0221-0000-0000-000000000005', tap._u221('TSELL'), tap._u221('TBUY'), 'mobile_transfer', 'disputed',        NULL,  now(), now() + interval '1 day');

-- Relations that must grant nothing, made the way clients make them (while H1 was public).
SELECT tap.login(tap._u221('SAVER'));
INSERT INTO public.saved_listings (user_id, listing_id) VALUES (tap._u221('SAVER'), tap._l221('H1'));
SELECT tap.login(tap._u221('REP'));
INSERT INTO public.reports (reporter_id, target_type, target_id, reason) VALUES (tap._u221('REP'), 'listing', tap._l221('H1'), 'other');
SELECT tap.logout();
INSERT INTO public.notifications (user_id, type, title, link, metadata)
VALUES (tap._u221('NOTE'), 'listing_update', 'Fixture 221', '/listing/' || tap._l221('H1'),
        jsonb_build_object('listing_id', tap._l221('H1')));

-- Hide H1..H7 (the cleanup's data step, as the trusted path). Errors are recorded, not raised.
CREATE TEMP TABLE _hide221 AS
  SELECT h AS listing_id, tap._try221(tap._hide_sql221(h)) AS outcome FROM unnest(tap._hidden221()) h;

-- ── A. wiring ───────────────────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM _hide221 WHERE outcome = '{"ok": true}'::jsonb), 7,
  'A1: the trusted path hides the seven non-live fixture listings');
SELECT is((SELECT array_agg(policyname || ':' || roles::text ORDER BY policyname) FROM pg_policies
            WHERE schemaname = 'public' AND tablename = 'listings' AND cmd = 'SELECT'),
  ARRAY['listings_select_visible:{anon,authenticated}'],
  'A2: listings has exactly one SELECT policy, listings_select_visible TO anon, authenticated (listings_select_all is gone)');
SELECT is((SELECT array_agg(policyname || ':' || roles::text ORDER BY policyname) FROM pg_policies
            WHERE schemaname = 'public' AND tablename = 'bids' AND cmd = 'SELECT'),
  ARRAY['bids_select_own:{authenticated}', 'bids_select_visible:{anon,authenticated}'],
  'A3: bids SELECT policies are bids_select_own and bids_select_visible (bids_select_all is gone)');
SELECT is((SELECT array_agg(tablename || ':' || qual ORDER BY tablename) FROM pg_policies
            WHERE schemaname = 'public' AND policyname IN ('listings_select_visible', 'bids_select_visible')),
  ARRAY['bids:(listing_is_public(listing_id) OR listing_private_party(listing_id))',
        'listings:(listing_is_public(id) OR listing_private_party(id))'],
  'A4: the two quals are exactly listing_is_public(...) OR listing_private_party(...)');
SELECT is((SELECT count(*)::int FROM pg_policies
            WHERE schemaname = 'public' AND tablename IN ('listings', 'bids') AND cmd = 'SELECT'
              AND (roles && ARRAY['anon','public']::name[])
              AND (qual IS NULL OR qual = 'true' OR qual ~ '(kernel\.|is_admin|ops\.)')), 0,
  'A5: no SELECT policy reachable by anon on listings/bids is USING (true) or calls kernel.*, ops.* or is_admin()');
SELECT is((SELECT relrowsecurity::text || '|' || (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'listing_visibility')::text
             FROM pg_class WHERE oid = to_regclass('public.listing_visibility')),
  'true|0', 'A6: listing_visibility has RLS enabled and zero policies');
SELECT is((SELECT count(*)::int FROM information_schema.role_table_grants
            WHERE table_schema = 'public' AND table_name = 'listing_visibility' AND grantee IN ('anon', 'authenticated', 'PUBLIC')), 0,
  'A7: anon and authenticated hold no privilege on listing_visibility');
SELECT is((SELECT string_agg(privilege_type, ',' ORDER BY privilege_type) FROM information_schema.role_table_grants
            WHERE table_schema = 'public' AND table_name = 'listing_visibility' AND grantee = 'service_role'),
  'DELETE,INSERT,SELECT', 'A8: service_role holds exactly SELECT, INSERT, DELETE on listing_visibility');
SELECT is((SELECT string_agg(f || '=' || CASE WHEN to_regprocedure(f) IS NULL THEN 'absent' ELSE
              has_function_privilege('anon', to_regprocedure(f), 'EXECUTE')::text || ',' ||
              has_function_privilege('authenticated', to_regprocedure(f), 'EXECUTE')::text END, ' ' ORDER BY f)
             FROM unnest(ARRAY['public.listing_is_public(uuid)', 'public.listing_private_party(uuid)',
                               'public.is_public(public.listings)', 'public.guard_hidden_listing_not_live()']) f),
  'public.guard_hidden_listing_not_live()=false,false public.is_public(public.listings)=true,true public.listing_is_public(uuid)=true,true public.listing_private_party(uuid)=true,true',
  'A9: the two predicates and the is_public(listings) computed field are anon/authenticated-executable; the trigger function is not');
SELECT is((SELECT string_agg(p.proname || ':' || p.prosecdef::text || ':' || p.provolatile::text || ':' || coalesce(array_to_string(p.proconfig, ','), '-'), ' ' ORDER BY p.proname)
             FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
              AND p.proname IN ('listing_is_public', 'listing_private_party', 'guard_hidden_listing_not_live', 'is_public')),
  'guard_hidden_listing_not_live:true:v:search_path="" is_public:false:s:search_path="" listing_is_public:true:s:search_path="" listing_private_party:true:s:search_path=""',
  'A10: the predicates and the guard are SECURITY DEFINER, is_public is SECURITY INVOKER; all have an empty search_path; the three readers are STABLE');
SELECT is((SELECT string_agg(c.relname || '.' || t.tgname || ':' || t.tgtype::text || ':' || t.tgfoid::regproc::text, ' ' ORDER BY t.tgname)
             FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
            WHERE NOT t.tgisinternal AND t.tgname IN ('trg_hidden_listing_not_live', 'trg_listing_visibility_not_live')),
  'listings.trg_hidden_listing_not_live:19:guard_hidden_listing_not_live listing_visibility.trg_listing_visibility_not_live:7:guard_hidden_listing_not_live',
  'A11: BEFORE UPDATE row trigger on listings and BEFORE INSERT row trigger on listing_visibility');
SELECT is((SELECT string_agg(p.proname || ':' || (p.proowner = c.relowner)::text || ':' || (r.rolbypassrls OR r.rolsuper)::text, ' ' ORDER BY p.proname)
             FROM pg_proc p JOIN pg_roles r ON r.oid = p.proowner
             CROSS JOIN (SELECT relowner FROM pg_class WHERE oid = 'public.listings'::regclass) c
            WHERE p.pronamespace = 'public'::regnamespace AND p.proname IN ('listing_is_public', 'listing_private_party', 'is_public')),
  'is_public:true:true listing_is_public:true:true listing_private_party:true:true',
  'A12: the three readers are owned by the owner of listings, a role that bypasses RLS (no 42P17 policy recursion)');
SELECT is((SELECT string_agg(c.relname || ':' || (c.relowner = o.relowner)::text || ':' || c.relrowsecurity::text || ':' || c.relforcerowsecurity::text, ' ' ORDER BY c.relname)
             FROM pg_class c CROSS JOIN (SELECT relowner FROM pg_class WHERE oid = 'public.listings'::regclass) o
            WHERE c.oid IN ('public.listings'::regclass, 'public.bids'::regclass, 'public.payments'::regclass,
                            'public.transfers'::regclass, to_regclass('public.listing_visibility'))),
  'bids:true:true:false listing_visibility:true:true:false listings:true:true:false payments:true:true:false transfers:true:true:false',
  'A13: listings, bids, payments, transfers and listing_visibility share that owner, have RLS on and none FORCES it');
SELECT is((SELECT string_agg(conname || ':' || confdeltype::text || ':' || confrelid::regclass::text || ':' || array_length(conkey, 1)::text, ' ')
             FROM pg_constraint WHERE conrelid = to_regclass('public.listing_visibility') AND contype = 'f'),
  'listing_visibility_listing_id_fkey:r:listings:1',
  'A14: listing_visibility has exactly one foreign key, to listings, ON DELETE RESTRICT (r), not CASCADE');

-- ── B. anon (the publishable key; every shipped build) ──────────────────────
SELECT tap.login_anon();
SELECT is(tap._ids221($$SELECT id FROM public.listings WHERE status = 'active' ORDER BY created_at DESC LIMIT 50$$),
  tap._sorted221(ARRAY[tap.listing_a(), tap.listing_b(), tap.listing_c(), tap.listing_d(), tap._l221('VENDED'), tap._l221('VRELIST'), tap._l221('VLIVE')]),
  'B1: anon Home feed (status active, build 25 shape) returns the public actives and no hidden row');
SELECT is(tap._ids221($$SELECT id FROM public.listings WHERE status = 'sold' ORDER BY sold_at DESC NULLS LAST LIMIT 30$$),
  ARRAY[tap._l221('VSOLD')], 'B2: anon Recently Sold returns only the public sold listing (H1, H5 hidden)');
SELECT is(tap._ids221($$SELECT id FROM public.listings WHERE auction_status = 'ended' ORDER BY ends_at DESC LIMIT 30$$),
  ARRAY[tap._l221('VENDED')], 'B3: anon Ended returns only the public ended listing (H1, H4 hidden)');
SELECT is(tap._ids221($$SELECT id FROM public.listings WHERE event_name ILIKE '%Fixture 221%' ORDER BY created_at DESC LIMIT 40$$),
  tap._sorted221(ARRAY[tap._l221('VSOLD'), tap._l221('VENDED'), tap._l221('VRELIST'), tap._l221('VRESV'), tap._l221('VLIVE')]),
  'B4: anon Explore search returns the public matches only');
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE seller_id = %L', tap.seller())),
  tap._sorted221(ARRAY[tap.listing_a(), tap.listing_b(), tap.listing_c(), tap.listing_d(), tap._l221('VSOLD'), tap._l221('VENDED'), tap._l221('VRESV'), tap._l221('VLIVE')]),
  'B5: anon public seller profile lists none of the seller''s six hidden listings');
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = %L', tap._l221('H1'))), 0::bigint,
  'B6: anon detail-by-id (direct link) of a hidden listing returns no row');
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), 0::bigint,
  'B7: anon sees none of the seven hidden listings by any filter');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = %L', tap._l221('H1'))), 0::bigint,
  'B8: anon bid history of a hidden listing is empty');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = %L', tap._l221('VLIVE'))), 1::bigint,
  'B9: anon still reads the bid history of a public listing');
SELECT is(tap._val221(format('SELECT public.listing_private_party(%L)', tap._l221('H1'))), 'false',
  'B10: listing_private_party is false for anon (no auth.uid())');
SELECT is(tap._val221(format('SELECT public.listing_is_public(%L)::text || '','' || public.listing_is_public(%L)::text', tap._l221('H1'), tap._l221('VLIVE'))), 'false,true',
  'B11: listing_is_public answers only a boolean: false for hidden, true for public');
SELECT is(tap._ids221($$SELECT id FROM public.listings l WHERE l.status = 'active' AND public.is_public(l) = true ORDER BY created_at DESC LIMIT 50$$),
  tap._sorted221(ARRAY[tap.listing_a(), tap.listing_b(), tap.listing_c(), tap.listing_d(), tap._l221('VENDED'), tap._l221('VRELIST'), tap._l221('VLIVE')]),
  'B12: anon Home feed with the next build''s computed-field filter (.eq(''is_public'', true)) works and returns the B1 rows');
SELECT is(tap._val221(format('SELECT public.is_public(l)::text FROM public.listings l WHERE l.id = %L', tap._l221('VLIVE'))), 'true',
  'B13: anon can select the is_public computed field (EXECUTE held; a public row reads true)');

-- ── C. a fresh signed-in user with no relation to any hidden row ────────────
SELECT tap.login(tap._u221('FRESH'));
SELECT is(tap._ids221($$SELECT id FROM public.listings WHERE status = 'active' AND auction_status = 'active' AND ends_at > now() ORDER BY ends_at, id LIMIT 50$$),
  tap._sorted221(ARRAY[tap.listing_a(), tap.listing_b(), tap.listing_d(), tap._l221('VLIVE')]),
  'C1: non-participant Home feed (RC8 shape) returns the public live listings only');
SELECT is(tap._ids221($$SELECT id FROM public.listings WHERE status = 'sold' LIMIT 30$$), ARRAY[tap._l221('VSOLD')],
  'C2: non-participant Recently Sold returns the public sold listing only');
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), 0::bigint,
  'C3: a fresh signed-in user sees none of the hidden listings');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = ANY(%L::uuid[])', tap._hidden221())), 0::bigint,
  'C4: a fresh signed-in user sees no bid on a hidden listing');
SELECT is((SELECT count(*) FROM market.listing_unified),
          (SELECT count(*) FROM public.listings),
  'C5: market.listing_unified (security_invoker) shows the non-participant exactly the public listing count');
SELECT is((SELECT count(*) FROM market.listing_unified WHERE id = ANY(tap._hidden221())), 0::bigint,
  'C6: market.listing_unified shows no hidden listing');

-- ── D. private parties keep their own hidden listing and its bids ───────────
SELECT tap.login(tap.seller());
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())),
  tap._sorted221(ARRAY[tap._l221('H1'), tap._l221('H2'), tap._l221('H3'), tap._l221('H4'), tap._l221('H5'), tap._l221('H6')]),
  'D1: the seller sees all six of their hidden listings (seller clause), and not the admin''s H7');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = %L', tap._l221('H1'))), 2::bigint,
  'D2: the seller sees both bids on their hidden listing');
SELECT tap.login(tap._u221('BID'));
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H1')],
  'D3: a losing bidder sees the hidden listing they bid on, and only that one (bids clause)');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = %L', tap._l221('H1'))), 2::bigint,
  'D4: the losing bidder sees the full bid history (2), not only their own bid (bids_select_own gives 1)');
SELECT tap.login(tap._u221('WIN'));
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H1')],
  'D5: the winner sees the hidden listing they won');
SELECT tap.login(tap._u221('PAY'));
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H1')],
  'D6: a payment buyer with no other relation sees the hidden listing (payments clause)');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = %L', tap._l221('H1'))), 2::bigint,
  'D7: the payment buyer sees that listing''s bids');
SELECT is((SELECT count(*) FROM public.payments p JOIN public.listings l ON l.id = p.listing_id WHERE p.buyer_id = tap._u221('PAY')), 1::bigint,
  'D8: the payment buyer''s own payment still embeds its listing (order history survives)');
SELECT tap.login(tap._u221('RES'));
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H2')],
  'D9: the reservation holder sees the hidden listing they hold (reserved_by clause)');
SELECT tap.login(tap._u221('TBUY'));
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H5')],
  'D10: a transfer buyer with no other relation sees the hidden listing (transfers clause, buyer side)');
SELECT is((SELECT count(*) FROM public.transfers t JOIN public.listings l ON l.id = t.listing_id WHERE t.buyer_id = tap._u221('TBUY')), 1::bigint,
  'D11: the transfer buyer''s order still embeds its listing (disputed order keeps context)');
SELECT tap.login(tap._u221('TSELL'));
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H5')],
  'D12: a transfer seller with no other relation sees the hidden listing (transfers clause, seller side)');
SELECT tap.login(tap.admin_user());
SELECT is(tap._ids221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), ARRAY[tap._l221('H7')],
  'D13: an admin sees only the hidden listing they own: no admin clause puts others'' hidden rows in a consumer feed');
SELECT is(tap._val221(format('SELECT public.listing_private_party(%L)', tap._l221('H1'))), 'false',
  'D14: listing_private_party is false for an admin who is not a party');
SELECT tap.login(tap.seller());
SELECT is(tap._ids221($$SELECT id FROM public.listings l WHERE l.status = 'sold' AND public.is_public(l) = true ORDER BY sold_at DESC NULLS LAST LIMIT 30$$),
  ARRAY[tap._l221('VSOLD')],
  'D15: the seller''s Recently Sold with the is_public filter leaves out their own hidden sales H1 and H5 (the next build''s fix for the ≤27 exception)');
SELECT is(tap._val221(format('SELECT count(*)::text || '':'' || string_agg(DISTINCT public.is_public(l)::text, '','') FROM public.listings l WHERE l.id = ANY(%L::uuid[])',
                             tap._hidden221())),
  '6:false', 'D16: is_public is false on each of the six hidden rows the seller can read');

-- ── E. relations that grant nothing ─────────────────────────────────────────
SELECT tap.login(tap._u221('SAVER'));
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), 0::bigint,
  'E1: saving a listing grants no access to it once hidden');
SELECT is((SELECT count(*)::text || ':' || count(l.id)::text FROM public.saved_listings s LEFT JOIN public.listings l ON l.id = s.listing_id
            WHERE s.user_id = tap._u221('SAVER')), '1:0',
  'E2: the saved row survives and its listing embed is null (clients show "no longer available")');
SELECT tap.login(tap._u221('REP'));
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), 0::bigint,
  'E3: reporting a listing grants no access to it');
SELECT tap.login(tap._u221('NOTE'));
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), 0::bigint,
  'E4: a notification that names a listing grants no access to it');

-- ── F. listing_visibility is closed to clients ──────────────────────────────
SELECT tap.login_anon();
SELECT is(tap._try221('SELECT * FROM public.listing_visibility') ->> 'code', '42501', 'F1: anon cannot read listing_visibility');
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VENDED'))) ->> 'code', '42501', 'F2: anon cannot insert into listing_visibility');
SELECT tap.login(tap._u221('FRESH'));
SELECT is(tap._try221('SELECT * FROM public.listing_visibility') ->> 'code', '42501', 'F3: an authenticated user cannot read listing_visibility');
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VENDED'))) ->> 'code', '42501', 'F4: an authenticated user cannot hide a listing');
SELECT tap.login(tap.seller());
SELECT is(tap._try221(format('DELETE FROM public.listing_visibility WHERE listing_id = %L', tap._l221('H3'))) ->> 'code', '42501',
  'F5: the seller cannot unhide their own listing (DELETE denied)');
SELECT is(tap._try221(format('UPDATE public.listing_visibility SET hidden_reason = %L WHERE listing_id = %L', 'x', tap._l221('H3'))) ->> 'code', '42501',
  'F6: the seller cannot rewrite a visibility row (UPDATE denied)');
SELECT tap.login_service();
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VENDED'))), '{"ok": true}'::jsonb, 'F7: service_role can hide a non-live listing');
SELECT is(tap._try221(format('DELETE FROM public.listing_visibility WHERE listing_id = %L', tap._l221('VENDED'))), '{"ok": true}'::jsonb,
  'F8: service_role can unhide it again');
SELECT is(tap._try221(format('UPDATE public.listing_visibility SET hidden_reason = %L WHERE listing_id = %L', 'x', tap._l221('H3'))) ->> 'code', '42501',
  'F9: service_role holds no UPDATE: a visibility row is inserted or deleted, never rewritten');
SELECT tap.logout();

-- ── I. trust stats (before G mutates fixtures) ──────────────────────────────
SELECT tap.login(tap._u221('FRESH'));
SELECT is((SELECT completed_sales || '|' || seller_terminal_total || '|' || seller_terminal_successful || '|' || active_listings
             FROM public.get_profile_trust_stats(tap.seller())), '1|1|1|4',
  'I1: the seller''s public stats count only the public sale (VSOLD) and the four public live listings (H1''s sale and H6 excluded)');
SELECT is((SELECT completed_purchases FROM public.get_profile_trust_stats(tap._u221('WIN'))), 0,
  'I2: a purchase on a hidden listing is not a public completed purchase');
SELECT is((SELECT completed_purchases FROM public.get_profile_trust_stats(tap.buyer())), 1,
  'I3: a purchase on a public listing still counts (the filter is not blanket)');
SELECT is((SELECT disputes_opened FROM public.get_profile_trust_stats(tap._u221('TBUY'))), 0,
  'I4: a dispute on a hidden listing is not shown on the public profile');
SELECT tap.logout();
-- listing_b's clock runs out before the finalizer has closed it (cron every 2 min): still active/active.
UPDATE public.listings SET ends_at = now() - interval '1 minute' WHERE id = tap.listing_b();
SELECT tap.login(tap._u221('FRESH'));
SELECT is((SELECT active_listings FROM public.get_profile_trust_stats(tap.seller())), 3,
  'I5: an expired auction the finalizer has not closed yet is not an active listing (ends_at > now(); was 4 in I1)');

-- ── G. a hidden listing is never live, held or extended ─────────────────────
-- Two more public listings, written by the trusted path, for the hide-time predicate:
--   VEARLY: status active, auction_status 'ended' while its clock still runs, Buy Now on (an auction a
--           trusted write closed early). reserve_buy_now still accepts it (G5): it never requires
--           auction_status = 'active'.
--   VHOLD : a Buy Now hold taken just before the clock ran out, live for 8 more minutes (a hold outlives
--           ends_at by up to 10 minutes); create-payment-intent would mint for its holder.
SELECT tap.logout();
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type,
  quantity, transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at,
  current_bid, cover_image_path, status, auction_status, reserved_by, reserved_until)
VALUES
  (tap._l221('VEARLY'), tap.seller(), 'Fixture 221 VEARLY', 'Club 221', 'wynwood', current_date + 30, '21:00', 'GA', 2,
   'mobile_transfer', 100, true, 300, 24, now() - interval '2 hours', now() + interval '1 day', 100,
   tap.seller()::text || '/vearly-221.jpg', 'active', 'ended', NULL, NULL),
  (tap._l221('VHOLD'), tap.seller(), 'Fixture 221 VHOLD', 'Club 221', 'wynwood', current_date + 30, '21:00', 'GA', 2,
   'mobile_transfer', 100, true, 300, 24, now() - interval '1 day', now() - interval '1 minute', 100,
   tap.seller()::text || '/vhold-221.jpg', 'reserved', 'active', tap.buyer(), now() + interval '8 minutes');

-- hide time (the cleanup's data step runs as the trusted path)
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VLIVE'))),
  '{"ok": false, "code": "P0001", "message": "Cannot hide a live listing; end or cancel it first."}'::jsonb,
  'G1: a live listing cannot be hidden, even by the trusted path');
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VRESV'))),
  '{"ok": false, "code": "P0001", "message": "Cannot hide a live listing; end or cancel it first."}'::jsonb,
  'G2: a listing under a Buy Now hold that would return to live cannot be hidden either');
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VEARLY'))),
  '{"ok": false, "code": "P0001", "message": "Cannot hide a live listing; end or cancel it first."}'::jsonb,
  'G3: an auction marked ended while its clock still runs cannot be hidden (Buy Now still accepts it)');
SELECT is(tap._try221(tap._hide_sql221(tap._l221('VHOLD'))),
  '{"ok": false, "code": "P0001", "message": "Cannot hide a listing under a live Buy Now hold; let the hold lapse or complete first."}'::jsonb,
  'G4: a listing whose clock ran out under a still-live Buy Now hold cannot be hidden (its holder could still pay)');
SELECT tap.login(tap._u221('FRESH'));
SELECT is(tap._try221(format('SELECT public.reserve_buy_now(%L, %L, 10)', tap._l221('VEARLY'), tap._u221('FRESH'))), '{"ok": true}'::jsonb,
  'G5: control: a stranger CAN reserve VEARLY, so G3 refuses a row that really is open to Buy Now');
SELECT tap.reset_guards();
SELECT tap.logout();

-- relisting / extending / reactivating
SELECT is(tap._try221(format('SELECT public.admin_relist_listing(%L, now() + interval ''2 days'', %L)', tap._l221('H7'), tap.admin_user())),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G6: admin_relist_listing on a hidden admin-owned listing is refused');
SELECT is((SELECT auction_status FROM public.listings WHERE id = tap._l221('H7')), 'cancelled', 'G7: the refused relist changed nothing');
SELECT is(tap._try221(format('SELECT public.admin_relist_listing(%L, now() + interval ''2 days'', %L)', tap._l221('VRELIST'), tap.admin_user())),
  '{"ok": true}'::jsonb, 'G8: control: the same relist of a public admin listing succeeds, so G6 is refused by the hide');
SELECT tap.reset_guards();

-- the review's reproduction (blocker): H4 is hidden in production's shape (active / auction ended / clock
-- run out); its seller moves ends_at forward with a plain PATCH, then a stranger who holds the id reserves.
SELECT tap.login(tap.seller());
SELECT is(tap._try221(format('UPDATE public.listings SET ends_at = now() + interval ''3 days'' WHERE id = %L', tap._l221('H4'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G9: the seller cannot move a hidden ended listing''s end time forward (the first step of the Buy Now hole)');
SELECT tap.login(tap._u221('FRESH'));
SELECT is(tap._try221(format('SELECT public.reserve_buy_now(%L, %L, 10)', tap._l221('H4'), tap._u221('FRESH'))),
  '{"ok": false, "code": "P0001", "message": "This auction has ended."}'::jsonb,
  'G10: a stranger''s reserve_buy_now on the hidden listing is refused');
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = %L', tap._l221('H4'))), 0::bigint,
  'G11: the stranger did not become a reservation holder: the hidden listing is still invisible to them');
SELECT tap.reset_guards();
SELECT tap.logout();

-- trusted writes (postgres under the listing-guard bypass: the auction-RPC / SQL-editor path); each case
-- is caught by exactly one rule of the UPDATE branch
SELECT set_config('app.bypass_listing_guard', 'on', true);
SELECT is(tap._try221(format('UPDATE public.listings SET ends_at = now() + interval ''1 hour'' WHERE id = %L', tap._l221('H6'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G12: extending a hidden, expired auction is refused, even under the listing-guard bypass');
SELECT is(tap._try221(format('UPDATE public.listings SET auction_status = ''active'' WHERE id = %L', tap._l221('H3'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G13: reactivating a hidden cancelled listing is refused');
SELECT is(tap._try221(format('UPDATE public.listings SET auction_status = ''ended'' WHERE id = %L', tap._l221('H3'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G14: flipping a hidden cancelled listing with time left to ''ended'' is refused (it would re-open Buy Now)');
SELECT is(tap._try221(format('UPDATE public.listings SET ends_at = now() + interval ''1 day'' WHERE id = %L', tap._l221('H5'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G15: moving a hidden sold listing''s end time forward is refused (no end-time move on a hidden row, whatever its status)');
SELECT is(tap._try221(format('UPDATE public.listings SET status = ''reserved'', reserved_by = %L, reserved_until = now() + interval ''10 minutes'' WHERE id = %L',
                             tap._u221('FRESH'), tap._l221('H4'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be reserved."}'::jsonb,
  'G16: a direct Buy Now hold on a hidden listing is refused');
SELECT tap.reset_guards();

-- the money paths on every hidden row
SELECT tap.login(tap._u221('FRESH'));
SELECT is((SELECT count(*)::int FROM unnest(tap._hidden221()) h
            WHERE tap._try221(format('INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (%L, %L, 10000)', h, tap._u221('FRESH')))
                  = '{"ok": true}'::jsonb), 0,
  'G17: a bid INSERT is refused on each of the seven hidden listings');
SELECT tap.logout();
SELECT is((SELECT count(*)::int
             FROM unnest(tap._hidden221()) h
            CROSS JOIN unnest(ARRAY[tap._u221('FRESH'), tap._u221('BID'), tap._u221('WIN'), tap._u221('PAY'), tap._u221('RES'),
                                    tap._u221('TBUY'), tap._u221('TSELL'), tap._u221('SAVER'), tap.buyer(), tap.other_user()]) u
            CROSS JOIN unnest(ARRAY['buy_now', 'auction']) m
            WHERE tap._cpi221(h, u, m)), 0,
  'G18: create-payment-intent''s preconditions (buy_now and auction) hold for no persona on any hidden listing');
SELECT ok(tap._cpi221(tap._l221('VEARLY'), tap._u221('FRESH'), 'buy_now'),
  'G19: control: the same precondition holds for the stranger''s live hold on the public VEARLY (G18 is not vacuous)');

-- the reservation sweep cannot be wedged (review: hidden held row + ends_at PATCH)
SELECT tap.login(tap.seller());
SELECT is(tap._try221(format('UPDATE public.listings SET ends_at = now() + interval ''2 days'' WHERE id = %L', tap._l221('H2'))),
  '{"ok": false, "code": "P0001", "message": "Hidden listing cannot be made live."}'::jsonb,
  'G20: the seller cannot move the end time of a hidden listing under a (lapsed) hold');
SELECT tap.logout();
SELECT lives_ok('SELECT public.auto_finalize_expired_auctions()',
  'G21: the finalizer cron (which runs the reservation sweep) completes with hidden rows in both batches');
SELECT is((SELECT status || '|' || coalesce(reserved_by::text, 'null') FROM public.listings WHERE id = tap._l221('H2')), 'active|null',
  'G22: the sweep released the hidden lapsed hold (the listing is closed: its auction time is over)');
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT is(tap._dml221(format('UPDATE public.listings SET restrictions = %L WHERE id = %L RETURNING id', 'Edited 221', tap._l221('H4'))), 1::bigint,
  'G23: the seller can still edit a hidden listing when the edit does not re-open it');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.listings l
            WHERE l.id = ANY(tap._hidden221())
              AND ((l.status IN ('active', 'reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now())
                   OR (l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false)))), 0,
  'G24: after every attempt above, no hidden listing is open to bids or Buy Now, or under a live hold');

-- ── H. storage: a hidden listing still protects its seller's cover ──────────
SELECT tap.login(tap.seller());
SELECT is((SELECT EXISTS (SELECT 1 FROM public.listings l WHERE l.cover_image_path = tap.seller()::text || '/h3-221.jpg')), true,
  'H1: the owner-delete policy''s reference check (run as the seller) still finds the hidden listing''s cover');
SELECT tap.logout();
SELECT ok((SELECT qual ~ 'cover_image_path' AND qual ~ 'listings' FROM pg_policies
            WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'auction-media owner delete unreferenced'),
  'H2: the auction-media owner delete policy is the invoker-run listings reference check that H1 evaluates');

-- ── K. a hidden listing cannot be deleted (its hide row is never erased by a delete) ─
SELECT tap.login(tap.seller());
SELECT is(tap._try221(format('DELETE FROM public.listings WHERE id = %L', tap._l221('H3'))) ->> 'code', '23503',
  'K1: the seller cannot delete their hidden listing (foreign_key_violation: the hide row restricts it)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.listings l JOIN public.listing_visibility v ON v.listing_id = l.id WHERE l.id = tap._l221('H3')), 1,
  'K2: the hidden listing and its hide row are both still there');
SELECT tap.login(tap.seller());
SELECT is(tap._dml221(format('DELETE FROM public.listings WHERE id = %L RETURNING id', tap._l221('VENDED'))), 1::bigint,
  'K3: control: the seller can still delete a public listing with no history (VENDED)');
SELECT tap.logout();
SELECT is(tap._try221(format('DELETE FROM public.listings WHERE id = %L', tap._l221('H7'))) ->> 'code', '23503',
  'K4: the trusted path cannot delete a hidden listing either (an operator unhides it first, deliberately)');
SELECT is((SELECT count(*)::int FROM public.listing_visibility WHERE listing_id = ANY(tap._hidden221())), 7,
  'K5: all seven hide rows survive every delete attempt');

-- ── J. positive control: put USING (true) back and the probe sees everything ─
DROP POLICY IF EXISTS listings_select_visible ON public.listings;
DROP POLICY IF EXISTS listings_select_all ON public.listings;
CREATE POLICY listings_select_all ON public.listings FOR SELECT USING (true);
DROP POLICY IF EXISTS bids_select_visible ON public.bids;
DROP POLICY IF EXISTS bids_select_all ON public.bids;
CREATE POLICY bids_select_all ON public.bids FOR SELECT USING (true);
SELECT tap.login_anon();
SELECT is(tap._count221(format('SELECT id FROM public.listings WHERE id = ANY(%L::uuid[])', tap._hidden221())), 7::bigint,
  'J1: with listings_select_all USING (true) restored, the B7 probe sees all seven hidden rows (the probe is not vacuous)');
SELECT is(tap._count221(format('SELECT id FROM public.bids WHERE listing_id = %L', tap._l221('H1'))), 2::bigint,
  'J2: with bids_select_all restored, the B8 probe sees the hidden listing''s bids');

SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
