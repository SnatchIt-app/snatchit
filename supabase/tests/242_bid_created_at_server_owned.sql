-- ============================================================================
-- 242_bid_created_at_server_owned.sql — registry 172 (20261021132000), BE-37 S2.
-- DRAFT suite for a DRAFT migration (bid-path change): 172 is not for apply before 2026-10-28 03:47:04Z (four live
-- listings) and before build 29's review settles; owner-gated.
--
-- The defect (reproduced on the production replay and on the chain, private-evidence/A-sprint-20261021/a2/p3):
-- validate_and_apply_bid's 3-second rate limit reads the bidder's LAST STORED bids.created_at
-- (ORDER BY created_at DESC LIMIT 1), and that column was whatever the client sent:
--   * created_at NULL (production only: the column is nullable there) — DESC sorts NULLs first, the last-bid
--     time reads NULL, and the limit is off for that bidder on that listing for as long as the row exists;
--   * a backdated created_at (both sides) — the last bid always looks old enough;
--   * a future created_at (both sides) — not a bypass but a lock-out, and a bid row dated in the future.
-- After 172 a BEFORE INSERT trigger that fires first stamps NEW.created_at := now() on every insert.
--
-- Version-agnostic probe: every insert goes through tap._try242 and every catalog read through
-- to_regprocedure / pg_trigger lookups, so on a database WITHOUT 172 the suite runs to the end and each
-- missing protection is its own `not ok` (RED), never an abort that hides the assertions after it.
-- Time: now() is frozen for the whole test transaction, so "inside the 3-second window" is every bid in this
-- file; "the window has passed" is simulated by ageing this file's own server-stamped rows by one minute
-- with a plain UPDATE (the 219 pattern; the stamp is INSERT-only, so the UPDATE is kept — D1 pins that).
-- Review of 9f1a21b0 (a2/p3/review_adv): a "clock-skew tolerance" stamp (keep a client value within 2 s of now())
-- passed the first 25 assertions yet let real bids through ~1.2 s apart with a 1.9 s backdate. B17-B20 pin the
-- stamp as unconditional down to the smallest timestamptz step; B21 pins the one-request two-row NULL insert;
-- A3 pins the stamp's body (md5 of pg_get_functiondef), the premise of 219 A2's exemption for this trigger.
-- ============================================================================
BEGIN;
SELECT plan(30);
SELECT tap.seed_core();

CREATE FUNCTION tap._try242(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg);
END $f$;
-- Ten synthetic active auctions, one per scenario, so each (listing, bidder) rate-limit history is independent.
CREATE FUNCTION tap._l242(p_n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('dddddddd-0242-0000-0000-' || lpad(p_n::text, 12, '0'))::uuid $f$;
-- The client bid shape (PlaceBidScreen / web lib/bids.ts insert {listing_id, bidder_id, amount}); an attacker
-- adds created_at. p_created_at: 'absent' omits the column (the default applies), anything else is an SQL
-- expression for the value sent (e.g. 'NULL', 'now() - interval ''1 hour''').
CREATE FUNCTION tap._bid242(p_n int, p_bidder uuid, p_amount int, p_created_at text DEFAULT 'absent') RETURNS text LANGUAGE sql AS $f$
  SELECT CASE WHEN p_created_at = 'absent'
    THEN format('INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (%L, %L, %s)', tap._l242(p_n), p_bidder, p_amount)
    ELSE format('INSERT INTO public.bids (listing_id, bidder_id, amount, created_at) VALUES (%L, %L, %s, %s)',
                tap._l242(p_n), p_bidder, p_amount, p_created_at) END $f$;
-- What was stored for one bid, read past RLS: 'NULL', 'server_now' (= this transaction's now()), or the offset.
CREATE FUNCTION tap._stored242(p_n int, p_amount int) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  SELECT CASE WHEN b.created_at IS NULL THEN 'NULL' WHEN b.created_at = now() THEN 'server_now'
              ELSE (b.created_at - now())::text END
    FROM public.bids b WHERE b.listing_id = tap._l242(p_n) AND b.amount = p_amount $f$;
-- Time passes for one listing's bids: shift this file's own rows back one minute (fixture write, past RLS).
CREATE FUNCTION tap._age242(p_n int) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  UPDATE public.bids SET created_at = created_at - interval '1 minute' WHERE listing_id = tap._l242(p_n) $f$;
CREATE FUNCTION tap._counters242(p_n int) RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $f$
  SELECT current_bid || '|' || bid_count FROM public.listings WHERE id = tap._l242(p_n) $f$;
GRANT EXECUTE ON FUNCTION tap._stored242(int, int), tap._age242(int), tap._counters242(int) TO authenticated, service_role;

INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
  transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid,
  cover_image_path, auction_status)
SELECT tap._l242(n), tap.seller(), 'Fixture 242 #' || n, 'Club 242', 'wynwood', current_date + 30, '21:00', 'GA', 2,
       'mobile_transfer', 100, false, NULL, 24, now(), now() + interval '24 hours', 100, 'fixtures/242.jpg', 'active'
  FROM generate_series(1, 10) n;

-- ── A. wiring ───────────────────────────────────────────────────────────────
SELECT is((SELECT t.tgname || ':' || t.tgtype::text || ':' || t.tgenabled::text || ':' || t.tgfoid::regprocedure::text
             FROM pg_trigger t WHERE t.tgrelid = 'public.bids'::regclass AND t.tgname = 'before_bid_created_at_server_owned'),
  'before_bid_created_at_server_owned:7:O:set_bid_created_at_server_clock()',
  'A1: before_bid_created_at_server_owned is an enabled BEFORE INSERT row trigger on bids running set_bid_created_at_server_clock()');
SELECT is((SELECT string_agg(t.tgname, ',' ORDER BY t.tgname COLLATE "C") FROM pg_trigger t
            WHERE t.tgrelid = 'public.bids'::regclass AND NOT t.tgisinternal AND t.tgtype & 6 = 6),
  'before_bid_created_at_server_owned,before_bid_guard_parties,before_bid_insert,trg_bid_requires_disclosure',
  'A2: it is the FIRST BEFORE INSERT trigger on bids in firing (name) order; the other three are unchanged');
SELECT is((SELECT p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ','), '-') || '|' || l.lanname || '|'
                  || p.prorettype::regtype::text || '|' || (p.proacl IS NULL)::text || '|'
                  || has_function_privilege('anon', p.oid, 'EXECUTE')::text || '|'
                  || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text || '|'
                  || EXISTS (SELECT 1 FROM aclexplode(p.proacl) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')::text || '|'
                  || md5(pg_get_functiondef(p.oid))
             FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
            WHERE p.oid = to_regprocedure('public.set_bid_created_at_server_clock()')),
  'false|search_path=""|plpgsql|trigger|false|false|false|false|cbd7c591f6d213b07bfb480773479c87',
  'A3: the function is plain (not SECURITY DEFINER), search_path empty, plpgsql, returns trigger; explicit ACL, no anon/authenticated/PUBLIC EXECUTE; '
  'body pinned (md5 of pg_get_functiondef: only NEW.created_at := now(); RETURN NEW, so it cannot refuse or lock, which 219 A2''s exemption relies on)');
SELECT ok((SELECT md5(pg_get_functiondef('public.validate_and_apply_bid()'::regprocedure)))
            IN ('d237200eb6a4cc6a2400b217e25e0618', 'e22bd09f1ba1341b7baae647ad584c18'),
  'A4: validate_and_apply_bid is untouched (production md5 d237200e… or the chain''s e22bd09f… at bfc5cf97; F10 parked)');
SELECT is((SELECT tgfoid::regprocedure::text FROM pg_trigger WHERE tgrelid = 'public.bids'::regclass AND tgname = 'before_bid_insert'),
  'validate_and_apply_bid()', 'A5: before_bid_insert still runs validate_and_apply_bid()');

-- ── B. the client path, as an authenticated non-seller buyer ────────────────
SELECT tap.login(tap.buyer());
-- normal bids (listing 1): unaffected
SELECT is(tap._try242(tap._bid242(1, tap.buyer(), 110)), '{"ok": true}'::jsonb, 'B1: a normal bid (no created_at sent) is accepted');
SELECT is(tap._stored242(1, 110), 'server_now', 'B2: it is stored at the server''s now()');
SELECT is(tap._try242(tap._bid242(1, tap.buyer(), 120)),
  '{"ok": false, "code": "P0001", "message": "Please wait before bidding again."}'::jsonb,
  'B3: a second normal bid inside 3 seconds is refused with the unchanged rate-limit message');
SELECT tap._age242(1);
SELECT is(tap._try242(tap._bid242(1, tap.buyer(), 130)), '{"ok": true}'::jsonb, 'B4: once the window has passed, the next normal bid is accepted');
SELECT is(tap._counters242(1), '130|2', 'B5: listing counters move exactly as before (two accepted bids, current bid 130)');
-- created_at NULL (listing 2)
SELECT is(tap._try242(tap._bid242(2, tap.buyer(), 110, 'NULL')), '{"ok": true}'::jsonb, 'B6: a bid that sends created_at NULL is accepted (the server stamps it)');
SELECT is(tap._stored242(2, 110), 'server_now', 'B7: it is stored at the server''s now(), not NULL');
SELECT is(tap._try242(tap._bid242(2, tap.buyer(), 120)),
  '{"ok": false, "code": "P0001", "message": "Please wait before bidding again."}'::jsonb,
  'B8: the next normal bid inside 3 seconds is refused (a NULL no longer switches the limit off)');
SELECT is(tap._try242(tap._bid242(2, tap.buyer(), 130, 'NULL')),
  '{"ok": false, "code": "P0001", "message": "Please wait before bidding again."}'::jsonb,
  'B9: sending NULL again inside 3 seconds is refused too');
-- backdated created_at (listing 3)
SELECT is(tap._try242(tap._bid242(3, tap.buyer(), 110, 'now() - interval ''1 hour''')), '{"ok": true}'::jsonb,
  'B10: a bid that sends a created_at one hour in the past is accepted');
SELECT is(tap._stored242(3, 110), 'server_now', 'B11: it is stored at the server''s now(), not the backdated value');
SELECT is(tap._try242(tap._bid242(3, tap.buyer(), 120, 'now() - interval ''1 hour''')),
  '{"ok": false, "code": "P0001", "message": "Please wait before bidding again."}'::jsonb,
  'B12: a second backdated bid inside 3 seconds is refused (backdating no longer bypasses the limit)');
-- future created_at (listing 4)
SELECT is(tap._try242(tap._bid242(4, tap.buyer(), 110, 'now() + interval ''1 day''')), '{"ok": true}'::jsonb,
  'B13: a bid that sends a created_at one day in the future is accepted');
SELECT is(tap._stored242(4, 110), 'server_now', 'B14: it is stored at the server''s now(), not the future value');
SELECT is(tap._try242(tap._bid242(4, tap.buyer(), 120)),
  '{"ok": false, "code": "P0001", "message": "Please wait before bidding again."}'::jsonb,
  'B15: the next normal bid inside 3 seconds is refused (the limit holds)');
SELECT tap._age242(4);
SELECT is(tap._try242(tap._bid242(4, tap.buyer(), 130)), '{"ok": true}'::jsonb,
  'B16: once the window has passed the bidder can bid again (a future created_at no longer locks them out)');
-- small offsets (listings 7-9): the stamp is unconditional, not a clock-skew tolerance. A 2 s backdate is where the
-- reviewer's surviving mutant kept the client value; 1 microsecond either side is the smallest timestamptz step, so
-- no tolerance of any width survives B19/B20.
SELECT is(tap._try242(tap._bid242(7, tap.buyer(), 110, 'now() - interval ''2 seconds''')), '{"ok": true}'::jsonb,
  'B17: a bid that sends a created_at 2 seconds in the past is accepted');
SELECT is(tap._stored242(7, 110), 'server_now',
  'B18: it is stored at the server''s now(), not the 2-second backdate (no clock-skew tolerance)');
SELECT is(tap._try242(tap._bid242(8, tap.buyer(), 110, 'now() - interval ''1 microsecond''')) || jsonb_build_object('stored', tap._stored242(8, 110)),
  '{"ok": true, "stored": "server_now"}'::jsonb,
  'B19: a created_at 1 microsecond in the past (the smallest timestamptz step) is accepted and stored at now()');
SELECT is(tap._try242(tap._bid242(9, tap.buyer(), 110, 'now() + interval ''1 microsecond''')) || jsonb_build_object('stored', tap._stored242(9, 110)),
  '{"ok": true, "stored": "server_now"}'::jsonb,
  'B20: a created_at 1 microsecond in the future is accepted and stored at now()');
-- one request, two rows (listing 10): on the production replay without 172, one PostgREST request with a two-row
-- array, both created_at null, placed two bids at once. Each row is stamped, so the second row sees the first.
SELECT is(tap._try242(format('INSERT INTO public.bids (listing_id, bidder_id, amount, created_at) VALUES (%L, %L, 110, NULL), (%L, %L, 120, NULL)',
                             tap._l242(10), tap.buyer(), tap._l242(10), tap.buyer()))
            || jsonb_build_object('counters', tap._counters242(10)),
  '{"ok": false, "code": "P0001", "message": "Please wait before bidding again.", "counters": "100|0"}'::jsonb,
  'B21: one INSERT carrying two bids with created_at NULL is refused by the rate limit and places neither bid');
SELECT tap.logout();

-- ── C. trusted writers are stamped too (unconditional) ──────────────────────
SELECT tap.reset_guards();
SELECT is(tap._try242(tap._bid242(5, tap.other_user(), 110, 'now() - interval ''1 day''')), '{"ok": true}'::jsonb,
  'C1: a claims-less postgres insert (migrations, SQL editor) with a backdated created_at is accepted');
SELECT is(tap._stored242(5, 110), 'server_now', 'C2: ... and stored at now(): the stamp has no trusted-caller exemption');
SELECT tap.login_service();
SELECT is(tap._try242(tap._bid242(6, tap.other_user(), 110, 'NULL')) || jsonb_build_object('stored', tap._stored242(6, 110)),
  '{"ok": true, "stored": "server_now"}'::jsonb,
  'C3: a service_role insert with created_at NULL is accepted and stored at now()');
SELECT tap.logout();

-- ── D. existing rows: the stamp is INSERT-only ──────────────────────────────
-- Listing 1's first bid was stored at now() (B2) and aged by one minute (before B4) with a plain UPDATE.
SELECT is(tap._stored242(1, 110), '-00:01:00', 'D1: an UPDATE of created_at is kept as written: the trigger never rewrites an existing row');

SELECT * FROM finish();
ROLLBACK;
