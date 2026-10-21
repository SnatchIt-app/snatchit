-- ============================================================================
-- 240_listing_seller_integrity.sql — migration 170 (20261021130000), listing seller integrity.
-- DRAFT package: not for apply before 2026-10-28 03:47:04Z (four live listings) and before build 29's
-- review settles; owner-gated. Source finding: sprint-control/SERVER_REFUSAL_CATALOGUE_C_20261021.md §9
-- ("Surprising" 2 and 4).
--   A. public.cancel_listing. Every state is reached through the shipped RPCs: a Buy Now hold through
--      reserve_buy_now (as the buyer, or the service path on the buyer's behalf), a winner through a real
--      bid + finalize_auction, a sale through reserve_buy_now + a succeeded payment + mark_listing_sold.
--      "Time passes" is the only fixture step: ends_at / reserved_until moved into the past by postgres,
--      which is what the clock does by itself (a hold lasts 10 minutes, an auction at most 72 hours).
--        A1-A11  FIRST, while request.jwt.claims has never been set in this session (the SQL editor / ops
--                script shape; request_is_service_role() reads an unset GUC, which no later reset restores):
--                RELIST_FOUR_LISTINGS_7D_20261021.sql's exact shape (admin inventory with a proof waiver,
--                ended, no bid, no winner, no hold; cancel_listing then admin_relist_listing) still works and
--                preserves every other column; that same path is refused on a live hold and on a winner.
--        A12-A22 live hold (buyer's own reserve_buy_now): seller and service_role refused (LISTING_HELD), the
--                hold intact; an expired hold (reserved_until < now() and = now(), cleanup_expired_
--                reservations' <= boundary) stays cancellable; a hold with one second left is refused.
--        A23-A27 ended auction with a winner: seller and service_role refused (LISTING_HAS_WINNER), intact.
--        A28-A39 the four existing refusals keep their text byte for byte and gain a HINT (LISTING_ALREADY_
--                SOLD, LISTING_NOT_FOUND, NOT_LISTING_OWNER, CALLER_UNKNOWN); anon stays 42501; an OPEN
--                auction with bids (no winner yet) is still voidable (web cancelSellerListing); an already-
--                cancelled listing, including the cancelled-with-winner state pre-170 cancels left behind,
--                returns silently; the function keeps its definer, search_path and ACL.
--   B. guard_listing_edit_lock (BEFORE UPDATE OF the 17 content columns): once a listing has a bid, a
--      Buy Now hold or a sale, an untrusted change of any of them is refused (LISTING_LOCKED_FOR_EDIT),
--      one assertion per column, and the shipped edit request too. Unchanged values (the app re-sends all
--      four fields), the excluded proof path (suite 223 L2 keeps it seller-replaceable), the bid RPC,
--      service_role and claims-less postgres pass; postgres or service_role WITH authenticated claims do
--      not. A listing with no activity stays fully editable. B36: sold_at alone locks (2 legacy production rows).
--   C. firing order: guard_listing_state < trg_guard_listing_content < trg_guard_listing_edit_lock: the existing
--      refusals (state columns, PROHIBITED_CONTENT, ACCOUNT_SUSPENDED) keep answering first, unchanged.
--   D. wiring: SECURITY DEFINER, search_path '', no client EXECUTE, the exact column list, and the
--      derivation from the grants (every client-UPDATE-able column is locked, guarded elsewhere, or the
--      one documented exclusion), so a new client-updatable column fails here until it is classified.
-- Helpers are version-agnostic (dynamic SQL, errors caught), so the file runs to completion on a database
-- without 170 and reports each gap as its own failure (RED).
-- ============================================================================
BEGIN;
SELECT plan(85);
SELECT tap.seed_core();

-- ── helpers ─────────────────────────────────────────────────────────────────
-- Run one statement as the CURRENT role; {"ok": true} or {ok:false, code, message, hint (JSON null if none)}.
CREATE FUNCTION tap._try240(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text; v_hint text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_hint = PG_EXCEPTION_HINT;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg, 'hint', nullif(v_hint, ''));
END $f$;
CREATE FUNCTION tap._no240(p_msg text, p_hint text) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT jsonb_build_object('ok', false, 'code', 'P0001', 'message', p_msg, 'hint', p_hint) $f$;
-- Rows a statement wrote (RETURNING), as the CURRENT role; -1 on error.
CREATE FUNCTION tap._dml240(p_sql text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v bigint;
BEGIN
  EXECUTE format('WITH x AS (%s) SELECT count(*) FROM x', p_sql) INTO v;
  RETURN v;
EXCEPTION WHEN others THEN
  RETURN -1;
END $f$;
CREATE FUNCTION tap._l240(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('eeeeeeee-0240-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._who240(p uuid) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT CASE WHEN p IS NULL THEN 'null' WHEN p = tap.buyer() THEN 'buyer' WHEN p = tap.other_user() THEN 'other'
              WHEN p = tap.admin_user() THEN 'admin' ELSE 'someone' END $f$;
-- Listing state, read past RLS (definer, owner = postgres).
CREATE FUNCTION tap._st240(p_id uuid) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  SELECT l.status || '|' || l.auction_status || '|by=' || tap._who240(l.reserved_by)
         || '|until=' || CASE WHEN l.reserved_until IS NULL THEN 'null' WHEN l.reserved_until > now() THEN 'live' ELSE 'past' END
         || '|winner=' || tap._who240(l.winner_user_id) || '|bids=' || l.bid_count
    FROM public.listings l WHERE l.id = p_id $f$;
CREATE FUNCTION tap._val240(p_id uuid, p_col text) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
DECLARE v text;
BEGIN
  EXECUTE format('SELECT %I::text FROM public.listings WHERE id = %L', p_col, p_id) INTO v;
  RETURN v;
END $f$;
CREATE FUNCTION tap._cancel240(p_id uuid, p_user uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT public.cancel_listing(%L, %L)', p_id, p_user) $f$;
CREATE FUNCTION tap._reserve240(p_id uuid, p_user uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT public.reserve_buy_now(%L, %L, 10)', p_id, p_user) $f$;
CREATE FUNCTION tap._bid240(p_id uuid, p_bidder uuid, p_amount int) RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (%L, %L, %s)', p_id, p_bidder, p_amount) $f$;
-- One column changed, as a seller's direct PostgREST PATCH would (WHERE id + seller_id).
CREATE FUNCTION tap._set240(p_id uuid, p_col text, p_val text) RETURNS text LANGUAGE sql AS $f$
  SELECT format('UPDATE public.listings SET %I = %s WHERE id = %L AND seller_id = %L', p_col, p_val, p_id, tap.seller()) $f$;
-- The shipped edit request (app/listing/edit/[id].tsx:157-167 at e46fc203; web/src/lib/seller-listings.ts:188-197).
CREATE FUNCTION tap._appedit240(p_id uuid, p_name text) RETURNS text LANGUAGE sql AS $f$
  SELECT format($u$UPDATE public.listings SET event_name = %L, venue = 'Club 240', restrictions = NULL, ticket_platform = 'other'
                   WHERE id = %L AND seller_id = %L RETURNING id$u$, p_name, p_id, tap.seller()) $f$;
-- "Time passes" for a hold: the guard bypass only for reserved_until (a state column), then off again.
CREATE FUNCTION tap._hold_until240(p_id uuid, p_until timestamptz) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings SET reserved_until = p_until WHERE id = p_id;
  PERFORM set_config('app.bypass_listing_guard', 'off', true);
END $f$;

-- ── fixtures (as postgres; seller S unless noted; all open for 24 h, start 100, Buy Now 300) ─────────
-- 1 HELD, 2 EXPIRED, 3 BOUNDARY, 4 ONE SECOND LEFT, 5 AUCTION WON, 6 RELIST shape (admin, waived), 7 SOLD,
-- 8 OPEN WITH A BID, 9 PLAIN, 10 LEGACY CANCELLED-WITH-WINNER, 11 HELD (service path), 12 WON (service path),
-- 20 LOCKED BY A BID, 21 NO ACTIVITY, 22 HELD (B), 23 ONCE SOLD (legacy shape).
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
  transfer_method, restrictions, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid,
  cover_image_path, proof_of_ownership_path, auction_status)
SELECT tap._l240(n), tap.seller(), 'Fixture 240 #' || n, 'Club 240', 'wynwood', current_date + 30, '21:00', 'GA', 2,
       'mobile_transfer', NULL, 100, true, 300, 24, now(), now() + interval '24 hours', 100,
       'covers/240.jpg', 'proofs/240.png', 'active'
  FROM unnest(ARRAY[1,2,3,4,5,7,8,9,10,11,12,20,21,22,23]) AS n;
-- 6: the four relisted production rows' shape (sprint-control/RELIST_FOUR_LISTINGS_7D_20261021.sql): owner-admin
-- inventory with an owner proof waiver and no proof path, qty 1, GA, mobile_transfer, Buy Now on.
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
  transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid,
  cover_image_path, auction_status, proof_waived_at, proof_waived_by, proof_waiver_reason)
VALUES (tap._l240(6), tap.admin_user(), 'Fixture 240 #6 relist', 'Club 240', 'wynwood', current_date + 30, '21:00', 'GA', 1,
        'mobile_transfer', 70, true, 150, 24, now(), now() + interval '24 hours', 70,
        'covers/240-6.jpg', 'active', now(), tap.admin_user(), 'Owner inventory (240 fixture)');
UPDATE public.listings SET buy_now_enabled = false, buy_now_price = NULL WHERE id IN (tap._l240(5), tap._l240(12));

-- ═══ A. cancel_listing ══════════════════════════════════════════════════════
-- A1-A11: request.jwt.claims has never been set in this session: the SQL editor / ops-script shape.
SELECT ok(current_setting('request.jwt.claims', true) IS NULL,
  'A1: the session has no request claims at all (as the RELIST script requires; must run before any login)');
UPDATE public.listings SET ends_at = now() - interval '1 minute' WHERE id = tap._l240(6);   -- the clock runs out
SELECT tap._try240(format('SELECT public.finalize_auction(%L)', tap._l240(6)));
SELECT is(tap._st240(tap._l240(6)), 'active|ended|by=null|until=null|winner=null|bids=0',
  'A2: reachable state: the admin''s waived listing ended with no bid (what the four production rows were)');
CREATE TEMP TABLE t240_relist AS
  SELECT md5((to_jsonb(l) - 'auction_status' - 'ends_at' - 'ended_at' - 'updated_at')::text) AS fp
    FROM public.listings l WHERE l.id = tap._l240(6);
SELECT is(tap._try240(tap._cancel240(tap._l240(6), tap.admin_user())), '{"ok": true}'::jsonb,
  'A3: RELIST step 1: public.cancel_listing(id, owner_admin) as claims-less postgres still succeeds (ended, no winner)');
SELECT is(tap._st240(tap._l240(6)), 'active|cancelled|by=null|until=null|winner=null|bids=0',
  'A4: ...ended -> cancelled, the resting state admin_relist_listing requires');
SELECT is(tap._try240(format('SELECT public.admin_relist_listing(%L, now() + interval ''7 days'', %L)', tap._l240(6), tap.admin_user())),
  '{"ok": true}'::jsonb, 'A5: RELIST step 2: public.admin_relist_listing(id, now() + 7 days, owner_admin) succeeds');
SELECT is((SELECT l.status || '|' || l.auction_status || '|' || (l.ends_at = now() + interval '7 days')::text || '|' || coalesce(l.ended_at::text, 'null')
             FROM public.listings l WHERE l.id = tap._l240(6)),
  'active|active|true|null', 'A6: post-state open: active/active, ends_at = the target, ended_at NULL');
SELECT is((SELECT md5((to_jsonb(l) - 'auction_status' - 'ends_at' - 'ended_at' - 'updated_at')::text) FROM public.listings l WHERE l.id = tap._l240(6)),
  (SELECT fp FROM t240_relist),
  'A7: the script''s preserved-column md5 is unchanged (title, image, price, ticket type, transfer, waiver)');
-- The same claims-less path on a live hold (taken by the service path on the buyer's behalf) and on a winner.
SELECT tap._try240(tap._reserve240(tap._l240(11), tap.buyer()));
SELECT is(tap._st240(tap._l240(11)), 'reserved|active|by=buyer|until=live|winner=null|bids=0',
  'A8: reachable state: a live hold for the buyer, taken through reserve_buy_now''s service path');
SELECT is(tap._try240(tap._cancel240(tap._l240(11), tap.seller())),
  tap._no240('This listing has a buyer checking out right now and can''t be cancelled.', 'LISTING_HELD'),
  'A9: the claims-less path (SQL editor, ops scripts) cannot cancel a live hold either: money may be moving');
SELECT tap._try240(tap._bid240(tap._l240(12), tap.other_user(), 140));
UPDATE public.listings SET ends_at = now() - interval '1 minute' WHERE id = tap._l240(12);
SELECT tap._try240(format('SELECT public.finalize_auction(%L)', tap._l240(12)));
SELECT is(tap._st240(tap._l240(12)), 'active|ended|by=null|until=null|winner=other|bids=1',
  'A10: reachable state: an auction won by the other user');
SELECT is(tap._try240(tap._cancel240(tap._l240(12), tap.seller())),
  tap._no240('This auction already has a winner and can''t be cancelled.', 'LISTING_HAS_WINNER'),
  'A11: the claims-less path cannot cancel an auction that has a winner');
-- Still claims-less: content on a locked listing (12 has a bid) stays correctable by the SQL editor.
SELECT is(tap._try240(format('UPDATE public.listings SET restrictions = ''Ops note 240'' WHERE id = %L', tap._l240(12))),
  '{"ok": true}'::jsonb, 'B35: the claims-less SQL-editor path may still correct content on a locked listing');

-- A12-A22: the buyer's own reserve_buy_now.
SELECT tap.login(tap.buyer());
SELECT is(tap._try240(tap._reserve240(tap._l240(1), tap.buyer())), '{"ok": true}'::jsonb,
  'A12: the buyer takes a Buy Now hold through reserve_buy_now');
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(1)), 'reserved|active|by=buyer|until=live|winner=null|bids=0',
  'A13: reachable state: reserved, held by the buyer, reserved_until in the future');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(1), tap.seller())),
  tap._no240('This listing has a buyer checking out right now and can''t be cancelled.', 'LISTING_HELD'),
  'A14: the seller cannot cancel a listing under a live hold (LISTING_HELD)');
SELECT tap.login_service();
SELECT is(tap._try240(tap._cancel240(tap._l240(1), tap.seller())) ->> 'hint', 'LISTING_HELD',
  'A15: nor service_role (an edge function acting for the seller)');
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(1)), 'reserved|active|by=buyer|until=live|winner=null|bids=0',
  'A16: after the refusals the hold is intact (reserved_by and reserved_until kept, auction still active)');
-- An EXPIRED hold stays cancellable (the cleanup path). One live hold per buyer, so 2/4 are the other user's.
SELECT tap.login(tap.other_user());
SELECT is(tap._try240(tap._reserve240(tap._l240(2), tap.other_user())), '{"ok": true}'::jsonb,
  'A17: another buyer takes a hold on listing 2');
SELECT tap.logout();
SELECT tap._hold_until240(tap._l240(2), now() - interval '1 minute');      -- the 10 minutes ran out
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(2), tap.seller())), '{"ok": true}'::jsonb,
  'A18: an expired hold (reserved_until < now()) does not block the seller''s cancel');
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(2)), 'active|cancelled|by=null|until=null|winner=null|bids=0',
  'A19: ...and the cancel clears the lapsed hold as before');
SELECT tap.login(tap.admin_user());
SELECT tap._try240(tap._reserve240(tap._l240(3), tap.admin_user()));
SELECT tap.logout();
SELECT tap._hold_until240(tap._l240(3), now());                            -- exactly the boundary
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(3), tap.seller())), '{"ok": true}'::jsonb,
  'A20: reserved_until = now() is expired (cleanup_expired_reservations'' <= boundary): cancellable');
SELECT tap.login(tap.other_user());
SELECT tap._try240(tap._reserve240(tap._l240(4), tap.other_user()));
SELECT tap.logout();
SELECT tap._hold_until240(tap._l240(4), now() + interval '1 second');      -- 9 m 59 s later
SELECT is(tap._st240(tap._l240(4)), 'reserved|active|by=other|until=live|winner=null|bids=0',
  'A21: reachable state: a hold with one second left');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(4), tap.seller())) ->> 'hint', 'LISTING_HELD',
  'A22: a hold with one second left is still live: refused');
SELECT tap.logout();

-- A23-A27: an ended auction WITH a winner (the buyer's real bid, the clock runs out, finalize_auction).
SELECT tap.login(tap.buyer());
SELECT is(tap._try240(tap._bid240(tap._l240(5), tap.buyer(), 150)), '{"ok": true}'::jsonb,
  'A23: the buyer bids 150 on the auction');
SELECT tap.logout();
UPDATE public.listings SET ends_at = now() - interval '1 minute' WHERE id = tap._l240(5);
SELECT tap.login(tap.buyer());
SELECT tap._try240(format('SELECT public.finalize_auction(%L)', tap._l240(5)));
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(5)), 'active|ended|by=null|until=null|winner=buyer|bids=1',
  'A24: reachable state: ended, winner = the buyer (finalize_auction)');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(5), tap.seller())),
  tap._no240('This auction already has a winner and can''t be cancelled.', 'LISTING_HAS_WINNER'),
  'A25: the seller cannot cancel an auction that has a winner (LISTING_HAS_WINNER)');
SELECT tap.login_service();
SELECT is(tap._try240(tap._cancel240(tap._l240(5), tap.seller())) ->> 'hint', 'LISTING_HAS_WINNER',
  'A26: nor service_role');
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(5)), 'active|ended|by=null|until=null|winner=buyer|bids=1',
  'A27: the winner and the ended state are intact (settle_listing_for_payment can still settle the winner)');

-- A28-A39: the existing refusals (text byte-identical, HINT added), the paths that must keep working, wiring.
SELECT tap.login(tap.buyer());
SELECT tap._try240(tap._reserve240(tap._l240(7), tap.buyer()));
SELECT tap.logout();
INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, paid_at)
VALUES (tap._l240(7), tap.buyer(), tap.seller(), 30000, 3000, 3000, 33000, 'pi_fixture_240_sold', 'succeeded', 'buy_now', now());
SELECT tap.login(tap.buyer());
SELECT tap._try240(format('SELECT public.mark_listing_sold(%L, %L)', tap._l240(7), tap.buyer()));
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(7)), 'sold|sold|by=null|until=null|winner=null|bids=0',
  'A28: reachable state: sold through reserve_buy_now + a succeeded payment + mark_listing_sold');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(7), tap.seller())),
  tap._no240('This listing has already been sold and cannot be cancelled.', 'LISTING_ALREADY_SOLD'),
  'A29: sold: the existing message, byte for byte, now with HINT LISTING_ALREADY_SOLD');
SELECT is(tap._try240(tap._cancel240(tap._l240(9999), tap.seller())),
  tap._no240('Listing not found.', 'LISTING_NOT_FOUND'),
  'A30: not found: the existing message with HINT LISTING_NOT_FOUND');
SELECT tap.login(tap.other_user());
SELECT is(tap._try240(tap._cancel240(tap._l240(9), tap.other_user())),
  tap._no240('You can only cancel your own listings.', 'NOT_LISTING_OWNER'),
  'A31: not the seller: the existing message with HINT NOT_LISTING_OWNER');
SELECT is(tap._try240(tap._cancel240(tap._l240(9), tap.seller())) ->> 'hint', 'NOT_LISTING_OWNER',
  'A32: p_user_id cannot be spoofed by an authenticated caller (the seller''s id passed by another user)');
-- An authenticated request whose claims carry no sub: auth.uid() is NULL and it is not the service path.
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT set_config('role', 'authenticated', true);
SELECT is(tap._try240(tap._cancel240(tap._l240(9), tap.seller())),
  tap._no240('Unable to identify caller. Ensure the request is authenticated.', 'CALLER_UNKNOWN'),
  'A33: no caller: the existing message with HINT CALLER_UNKNOWN');
SELECT tap.login_anon();
SELECT is(tap._try240(tap._cancel240(tap._l240(9), tap.seller())) ->> 'code', '42501',
  'A34: anon still has no EXECUTE (42501)');
SELECT tap.login(tap.other_user());
SELECT is(tap._try240(tap._bid240(tap._l240(8), tap.other_user(), 120)), '{"ok": true}'::jsonb,
  'A35: a bid on an open auction (listing 8)');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(8), tap.seller())), '{"ok": true}'::jsonb,
  'A36: an OPEN auction with bids and no winner yet is still voidable by its seller (web cancelSellerListing)');
SELECT is(tap._try240(tap._cancel240(tap._l240(9), tap.seller())) || tap._try240(tap._cancel240(tap._l240(9), tap.seller())),
  '{"ok": true}'::jsonb, 'A37: a plain listing cancels, and cancelling it again returns silently (idempotent)');
SELECT tap.logout();
-- The state a pre-170 cancel of a won auction left behind (cancel_listing's own SET list, through the same RPC
-- bypass): re-cancelling it stays a silent no-op, not a winner refusal.
SELECT tap.login(tap.buyer());
SELECT tap._try240(tap._bid240(tap._l240(10), tap.buyer(), 130));
SELECT tap.logout();
UPDATE public.listings SET ends_at = now() - interval '1 minute' WHERE id = tap._l240(10);
SELECT tap._try240(format('SELECT public.finalize_auction(%L)', tap._l240(10)));
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET auction_status = 'cancelled', status = 'active', reserved_by = NULL, reserved_until = NULL, ended_at = now()
 WHERE id = tap._l240(10);
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._cancel240(tap._l240(10), tap.seller())) || jsonb_build_object('state', tap._st240(tap._l240(10))),
  '{"ok": true, "state": "active|cancelled|by=null|until=null|winner=buyer|bids=1"}'::jsonb,
  'A38: an already-cancelled listing that kept its winner (pre-170 history) re-cancels silently');
SELECT tap.logout();
SELECT is((SELECT p.prosecdef::text || '|' || array_to_string(p.proconfig, ',') || '|' || array_to_string(p.proacl, ',')
             FROM pg_proc p WHERE p.oid = 'public.cancel_listing(uuid,uuid)'::regprocedure),
  'true|search_path=public|postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres',
  'A39: cancel_listing keeps SECURITY DEFINER, search_path=public and its ACL (authenticated + service_role)');

-- ═══ B. edits after activity ═══════════════════════════════════════════════
-- Listing 20: one real bid by another user (bid_count 1), still open. Each content column, one at a time.
SELECT tap.login(tap.other_user());
SELECT tap._try240(tap._bid240(tap._l240(20), tap.other_user(), 150));
SELECT tap.logout();
SELECT is(tap._st240(tap._l240(20)), 'active|active|by=null|until=null|winner=null|bids=1',
  'B0: reachable state: an open auction with one bid');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._set240(tap._l240(20), c.col, c.val)),
          tap._no240('This listing can''t be edited after it has bids, a buyer checking out, or a sale.', 'LISTING_LOCKED_FOR_EDIT'),
          'B' || c.n || ': with a bid, the seller cannot change ' || c.col)
  FROM (VALUES ( 1, 'event_name',                    quote_literal('Renamed 240')),
               ( 2, 'venue',                         quote_literal('Other venue 240')),
               ( 3, 'neighborhood',                  quote_literal('brickell')),
               ( 4, 'event_date',                    'current_date + 31'),
               ( 5, 'event_time',                    quote_literal('22:30')),
               ( 6, 'ticket_type',                   quote_literal('VIP')),
               ( 7, 'quantity',                      '3'),
               ( 8, 'transfer_method',               quote_literal('email')),
               ( 9, 'restrictions',                  quote_literal('18+')),
               (10, 'starting_bid',                  '120'),
               (11, 'buy_now_enabled',               'false'),
               (12, 'buy_now_price',                 '350'),
               (13, 'starts_at',                     'now() + interval ''1 hour'''),
               (14, 'cover_image_path',              quote_literal('covers/240-swapped.jpg')),
               (15, 'ticket_platform',               quote_literal('dice')),
               (16, 'seller_commitment_accepted_at', 'now() - interval ''1 day'''),
               (17, 'category',                      quote_literal('concerts'))) AS c(n, col, val)
 ORDER BY c.n;
SELECT is(tap._dml240(tap._appedit240(tap._l240(20), 'Stale form 240')), -1::bigint,
  'B18: the shipped edit request (a stale form saved after the first bid) is refused');
SELECT is(tap._dml240(format($u$UPDATE public.listings SET event_name = event_name, venue = venue, restrictions = restrictions,
                                  ticket_platform = ticket_platform WHERE id = %L AND seller_id = %L RETURNING id$u$, tap._l240(20), tap.seller())),
  1::bigint, 'B19: re-sending the same values (no change) still passes');
SELECT is(tap._dml240(format($u$UPDATE public.listings SET proof_of_ownership_path = 'proofs/240-replaced.png'
                                  WHERE id = %L AND seller_id = %L RETURNING id$u$, tap._l240(20), tap.seller())),
  1::bigint, 'B20: the proof path is not locked (documented exclusion; suite 223 L2)');
SELECT tap.login(tap.buyer());
SELECT is(tap._try240(tap._bid240(tap._l240(20), tap.buyer(), 175)), '{"ok": true}'::jsonb,
  'B21: bidding on a locked listing still works (the bid trigger writes state columns only)');
SELECT tap.login_service();
SELECT is(tap._try240(format('UPDATE public.listings SET event_name = ''Ops rename 240'' WHERE id = %L', tap._l240(20))),
  '{"ok": true}'::jsonb, 'B22: service_role (claims absent or service_role) may still correct content');
SELECT tap.logout();
SELECT is(tap._try240(format('UPDATE public.listings SET venue = ''Ops venue 240'' WHERE id = %L', tap._l240(20))),
  '{"ok": true}'::jsonb, 'B23: postgres with empty claims (tap.logout, read as none by the guards'' nullif) may too');
SELECT tap.set_claims(tap.seller(), 'authenticated');
SELECT is(tap._try240(format('UPDATE public.listings SET venue = ''Claimed venue 240'' WHERE id = %L', tap._l240(20))) ->> 'hint',
  'LISTING_LOCKED_FOR_EDIT', 'B24: a postgres session that carries request claims is not trusted');
SELECT set_config('role', 'service_role', true);
SELECT is(tap._try240(format('UPDATE public.listings SET venue = ''Claimed venue 240'' WHERE id = %L', tap._l240(20))) ->> 'hint',
  'LISTING_LOCKED_FOR_EDIT', 'B25: service_role carrying authenticated claims is not trusted either');
SELECT tap.logout();
SELECT is(tap._val240(tap._l240(20), 'event_name') || '|' || tap._val240(tap._l240(20), 'venue') || '|' || tap._val240(tap._l240(20), 'starting_bid'),
  'Ops rename 240|Ops venue 240|100', 'B26: only the trusted edits landed');

-- Listing 22: a live Buy Now hold, then the same hold lapsed but not yet swept (status still reserved).
SELECT tap.login(tap.buyer());
SELECT tap._try240(tap._reserve240(tap._l240(22), tap.buyer()));
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._set240(tap._l240(22), 'event_name', quote_literal('Renamed during checkout'))) ->> 'hint',
  'LISTING_LOCKED_FOR_EDIT', 'B27: under a live hold the seller cannot change the listing the buyer is paying for');
SELECT tap.logout();
SELECT tap._hold_until240(tap._l240(22), now() - interval '1 minute');
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._set240(tap._l240(22), 'buy_now_price', '50')) ->> 'hint', 'LISTING_LOCKED_FOR_EDIT',
  'B28: a lapsed hold not yet swept is still status reserved: locked');
SELECT is(tap._try240(tap._set240(tap._l240(7), 'venue', quote_literal('Sold venue 240'))) ->> 'hint', 'LISTING_LOCKED_FOR_EDIT',
  'B29: a sold listing (no bids, sold through Buy Now) is locked');
SELECT is(tap._try240(tap._set240(tap._l240(5), 'restrictions', quote_literal('changed after the win'))) ->> 'hint', 'LISTING_LOCKED_FOR_EDIT',
  'B30: an ended auction with a winner (bids) is locked');
SELECT is(tap._try240(tap._set240(tap._l240(8), 'event_name', quote_literal('Renamed after cancel'))) ->> 'hint', 'LISTING_LOCKED_FOR_EDIT',
  'B31: a cancelled listing that had bids keeps its bid history: locked');
-- Listing 21: no activity — the edit screen's normal path, and a price change, still pass.
SELECT is(tap._dml240(tap._appedit240(tap._l240(21), 'Renamed before any bid')), 1::bigint,
  'B32: with no bid, hold or sale the shipped edit request passes');
SELECT is(tap._try240(tap._set240(tap._l240(21), 'starting_bid', '130')), '{"ok": true}'::jsonb,
  'B33: with no activity the seller may still change the starting bid (bid rules unchanged; F10)');
SELECT is(tap._try240(tap._set240(tap._l240(21), 'cover_image_path', quote_literal('covers/240-21b.jpg'))), '{"ok": true}'::jsonb,
  'B34: ...and the cover');
SELECT tap.logout();
-- Listing 23: sold (real path), then the legacy shape production still holds in 2 rows (active/cancelled, no bid,
-- sold_at kept, a transfer; aggregate count on the replay, 2026-10-21; no current RPC writes it), set through the
-- RPC bypass: sold_at alone keeps it locked.
SELECT tap.login(tap.admin_user());
SELECT tap._try240(tap._reserve240(tap._l240(23), tap.admin_user()));
SELECT tap.logout();
INSERT INTO public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total,
                             stripe_payment_intent_id, status, mode, paid_at)
VALUES (tap._l240(23), tap.admin_user(), tap.seller(), 30000, 3000, 3000, 33000, 'pi_fixture_240_legacy', 'succeeded', 'buy_now', now());
SELECT tap.login(tap.admin_user());
SELECT tap._try240(format('SELECT public.mark_listing_sold(%L, %L)', tap._l240(23), tap.admin_user()));
SELECT tap.logout();
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status = 'active', auction_status = 'cancelled' WHERE id = tap._l240(23);
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT is(tap._st240(tap._l240(23)) || '|sold_at=' || (tap._val240(tap._l240(23), 'sold_at') IS NOT NULL)::text || '|'
          || (tap._try240(tap._set240(tap._l240(23), 'event_name', quote_literal('Reused listing 240'))) ->> 'hint'),
  'active|cancelled|by=null|until=null|winner=null|bids=0|sold_at=true|LISTING_LOCKED_FOR_EDIT',
  'B36: a once-sold listing (sold_at kept, status no longer sold, no bid) stays locked by sold_at alone');
SELECT tap.logout();

-- ═══ C. firing order (BEFORE UPDATE row triggers fire in name order) ════════
-- The lock sorts AFTER trg_guard_listing_content: every refusal clients already map (PROHIBITED_CONTENT,
-- ACCOUNT_SUSPENDED via readServerRefusal) keeps answering first on a locked listing, exactly as today (suite
-- 219 G4); the lock answers only an edit those guards accept.
SELECT tap.reset_guards();   -- RPCs above leave app.bypass_listing_guard on for this transaction; C3 needs the state guard live
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._set240(tap._l240(20), 'event_name', quote_literal('Now with an open bar'))) ->> 'hint',
  'PROHIBITED_CONTENT', 'C1: on a locked listing prohibited text still gets the moderation refusal first (unchanged copy)');
SELECT is(tap._try240(tap._set240(tap._l240(21), 'event_name', quote_literal('Now with an open bar'))) ->> 'hint',
  'PROHIBITED_CONTENT', 'C2: on an unlocked listing the content guard still refuses prohibited text');
SELECT is(tap._try240(format('UPDATE public.listings SET event_name = ''x240'', current_bid = 1 WHERE id = %L', tap._l240(20))),
  '{"ok": false, "code": "P0001", "hint": null, "message": "Cannot directly modify auction state columns. Use the appropriate RPC."}'::jsonb,
  'C3: a state-column change is still answered first by guard_listing_state');
SELECT tap.logout();
INSERT INTO ops.user_restriction (user_id, kind, reason, actor) VALUES (tap.seller(), 'suspended', '240 precedence probe', tap.admin_user());
SELECT tap.login(tap.seller());
SELECT is(tap._try240(tap._set240(tap._l240(20), 'event_name', quote_literal('Suspended seller rename'))) ->> 'hint',
  'ACCOUNT_SUSPENDED', 'C4: a suspended seller editing a locked listing still gets ACCOUNT_SUSPENDED first (219 G4 shape)');
SELECT tap.logout();
SELECT is((SELECT array_agg(t.tgname::text ORDER BY t.tgname) FROM pg_trigger t
            WHERE t.tgrelid = 'public.listings'::regclass AND NOT t.tgisinternal
              AND (t.tgtype & 2) = 2 AND (t.tgtype & 16) = 16 AND (t.tgtype & 1) = 1),
  ARRAY['guard_listing_state','trg_guard_listing_content','trg_guard_listing_edit_lock','trg_guard_listing_identity',
        'trg_guard_listing_proof_waiver','trg_guard_listing_reservation_parties','trg_guard_proof_status',
        'trg_hidden_listing_not_live','trg_listing_ends_at_from_duration','trg_listings_updated_at',
        'trg_reservation_requires_disclosure'],
  'C5: the BEFORE UPDATE row triggers on listings, in firing order: the lock is third, after the content guard');

-- ═══ D. wiring ═════════════════════════════════════════════════════════════
SELECT is((SELECT p.prosecdef::text || '|' || array_to_string(p.proconfig, ',') || '|' || p.prorettype::regtype::text
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.guard_listing_edit_lock()')),
  'true|search_path=""|trigger', 'D1: guard_listing_edit_lock() is SECURITY DEFINER with search_path ''''');
SELECT is((SELECT has_function_privilege('anon', p.oid, 'EXECUTE')::text || '|' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
                  || '|' || (coalesce(array_to_string(p.proacl, ','), '<default>') ~ '(^|,)=X/')::text
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.guard_listing_edit_lock()')),
  'false|false|false', 'D2: no client EXECUTE (anon, authenticated, PUBLIC)');
SELECT is((SELECT (t.tgtype::int)::text || '|' || t.tgenabled::text || '|' || (t.tgfoid = to_regprocedure('public.guard_listing_edit_lock()'))::text
                  || '|' || (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
                               FROM unnest(t.tgattr::int2[]) k JOIN pg_attribute a ON a.attrelid = t.tgrelid AND a.attnum = k)
             FROM pg_trigger t WHERE t.tgrelid = 'public.listings'::regclass AND t.tgname = 'trg_guard_listing_edit_lock'),
  '19|O|true|buy_now_enabled,buy_now_price,category,cover_image_path,event_date,event_name,event_time,neighborhood,quantity,'
  || 'restrictions,seller_commitment_accepted_at,starting_bid,starts_at,ticket_platform,ticket_type,transfer_method,venue',
  'D3: BEFORE UPDATE OF exactly the 17 content columns, FOR EACH ROW, enabled, executing the new function');
SELECT is((SELECT string_agg(a.attname::text, ',' ORDER BY a.attname) FROM pg_attribute a
            WHERE a.attrelid = 'public.listings'::regclass AND a.attnum > 0 AND NOT a.attisdropped
              AND has_column_privilege('authenticated', 'public.listings', a.attname, 'UPDATE')
              AND a.attnum <> ALL (coalesce((SELECT t.tgattr::int2[] FROM pg_trigger t
                                              WHERE t.tgrelid = 'public.listings'::regclass AND t.tgname = 'trg_guard_listing_edit_lock'),
                                            '{}'::int2[]))),
  'auction_status,bid_count,created_at,current_bid,duration_hours,ended_at,ends_at,highest_bidder_id,id,proof_of_ownership_path,'
  || 'proof_status,proof_waived_at,proof_waived_by,proof_waiver_reason,reserved_by,reserved_until,seller_id,sold_at,status,'
  || 'updated_at,winner_user_id,winning_bid_amount',
  'D4: derived from the grants: every other client-UPDATE-able column is guarded elsewhere (state, identity, end time, '
  || 'proof status, waiver), server-set (updated_at) or the documented proof-path exclusion');

SELECT * FROM finish();
ROLLBACK;
