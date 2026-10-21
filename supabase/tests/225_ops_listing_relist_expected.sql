-- ============================================================================
-- 225_ops_listing_relist_expected.sql — migration 20261021110000 (registry 158): a console relist
-- (ops.execute_action 'listing_relist') must state the listing version the operator saw.
--
--   R1  happy path: expected = the five keys of ops.listing_detail(id)->'listing' (updated_at is the raw
--       to_jsonb string, microseconds included) => succeeded; the listing is active with the new ends_at and
--       ended_at NULL; the ops.action row is succeeded; result.before = the locked row (the compared fields).
--       R1.8: with expected = {updated_at} alone, result.before is still the locked row's five fields: the
--       server's verified record, never an echo of the client's expected (ops.action.expected keeps that).
--   R2  expected.updated_at is required: expected NULL, {} and today's console payload {status, auction_status}
--       raise invalid_input (P0001) before any row or audit is written.
--   R3  ...and must be a concrete ISO-8601 instant with its UTC offset that casts to timestamptz: JSON null, a
--       number, '', 'yesterday', no offset, 2026-02-30 => invalid_input. No ops.action row, no audit row, the
--       listing unchanged (row md5).
--   R4  ABA: expected captured, then the listing is relisted directly (admin_relist_listing, the owner's path) and
--       cancelled again (cancel_listing, the seller path): the stale submit is rejected / stale_state with the
--       contract message, result.current = the live row, the listing unchanged and still cancelled. Also with
--       expected = {updated_at} alone (updated_at is the key that catches it).
--   R5  content drift: the seller edits restrictions (the client UPDATE path) after the capture => stale_state.
--       Keys PRESENT in expected are compared (status, auction_status, ends_at, ended_at; JSON null = expected
--       NULL); keys ABSENT are not ({updated_at} alone, fresh, succeeds).
--   R6  precision contract: updated_at truncated to milliseconds (the JS Date shape) => stale_state; the same
--       instant written with another offset ('Z') succeeds (compared as an instant, exact to the microsecond); a
--       value read under another session TimeZone (+05:45, not a whole hour) is accepted under the default one.
--       R6.6/R6.7: a live updated_at EARLIER than the expected one => stale_state, listing unchanged. updated_at =
--       now() is the writing transaction's start, so a writer that began before the version the operator loaded
--       and committed after it stamps an earlier value: the compare is equality, not "the client's copy is older".
--   R7  domain guards with a FRESH expected keep surfacing as today (rejected / precondition, the domain message,
--       listing unchanged): bid, payment, transfer history; non-admin seller; hidden listing (154); new_ends_at
--       in the past or missing. Listing not found: the pre-158 answer byte for byte (rejected / precondition
--       'Listing not found.', admin_relist_listing's own text, R7.11), now answered from the dispatch's locked read.
--   R8  idempotent replay is unchanged (the key lookup precedes the new check).
--   R9  a platform_support caller gets 42501 (unchanged), also with today's console payload (no updated_at): the
--       existing refusals keep their place and text ahead of the new check (role, then reason, then expected);
--       R10 console paused => precondition_failed (unchanged), also with today's console payload.
--   R11 the owner's direct service-role path is untouched: the RELIST_FOUR_LISTINGS_7D DO-block shape
--       (postgres, no request claims; cancel_listing + admin_relist_listing under FOR UPDATE, preserved-column md5)
--       succeeds on fixture rows; public.admin_relist_listing(id, ts, admin) with no expected works and keeps md5
--       ef4c9ba0a832230db6752c069e467ca4.
--   R12 ACLs of execute_action / action_dispatch / admin_relist_listing = 157 / production; execute_action minus
--       the marked 158 block = 157's body (md5 0da9bc63acb58f1d76a86f8039c0c877); action_dispatch with the
--       production listing_relist branch put back = production (md5 bfb8b9dcfaace5ff04009f96b6de7bef); the
--       neighbouring functions keep their md5s; static: the listing_relist branch locks the listing FOR UPDATE
--       before it calls admin_relist_listing (a single session cannot observe a missing lock; the two-session
--       proof is scripts/local/rehearsal_158_concurrency.sh).
--   R13 157's money guard still works with 158 applied (a duplicate refund_execute is refused).
--
-- now() is frozen inside this transaction, so every UPDATE here stamps the same updated_at. A listing loaded in
-- an earlier transaction carries an earlier one: tap._age225 sets a cancelled fixture's updated_at to
-- 2026-10-20 15:04:05.123456+00 (trigger trg_listings_updated_at disabled for that one statement), the state a
-- listing cancelled the day before has. Without it R4 (updated_at only), R5 and R6 could not tell versions apart.
-- Fixtures: admin-owned listings inserted as postgres (the seed_core way), then cancelled through
-- public.cancel_listing by their seller; R11's rows start 'ended' like the four production listings did.
-- Founder A = tap.admin_user() (platform_admin via admin_users), founder B = tap.other_user().
-- ============================================================================
BEGIN;
SELECT plan(81);
SELECT tap.seed_core();

INSERT INTO public.admin_users (user_id, label) VALUES (tap.other_user(), 'FOUNDER B') ON CONFLICT (user_id) DO NOTHING;

CREATE TABLE tap.memo_225 (k text PRIMARY KEY, v jsonb);
CREATE FUNCTION tap._s225(k text, v jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_225 VALUES (k, v) ON CONFLICT (k) DO UPDATE SET v = excluded.v $m$;
CREATE FUNCTION tap._g225(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_225 WHERE k = $1 $m$;

-- fixture ids
CREATE FUNCTION tap._l225(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('aaaaaaaa-0225-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._p225(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('bbbbbbbb-0225-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
CREATE FUNCTION tap._t225(n int) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$ SELECT ('cccccccc-0225-0000-0000-' || lpad(n::text, 12, '0'))::uuid $f$;
-- the contract texts (for F)
CREATE FUNCTION tap._inval225() RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT 'invalid_input: listing_relist requires expected.updated_at (the listing''s updated_at exactly as ops.listing_detail returned it); reload the listing' $f$;
CREATE FUNCTION tap._stale225() RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT 'listing changed since you loaded it — reload and try again' $f$;
CREATE FUNCTION tap._aged225() RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $f$ SELECT '2026-10-20 15:04:05.123456+00'::timestamptz $f$;

-- an active listing (as postgres, the seed_core way)
CREATE FUNCTION tap._new225(n int, p_seller uuid, p_auction text DEFAULT 'active', p_ends timestamptz DEFAULT NULL) RETURNS void
LANGUAGE plpgsql AS $f$
begin
  insert into public.listings
    (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity, transfer_method,
     starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
  values (tap._l225(n), p_seller, 'Fixture 225 #' || n, 'Club 225', 'wynwood', current_date + 30, '21:00', 'GA', 1, 'mobile_transfer',
          100, true, 200, 24, now() - interval '1 day', coalesce(p_ends, now() + interval '24 hours'), 100, 'fixtures/225.jpg', p_auction);
end $f$;
-- the seller cancels it (public.cancel_listing, the app path)
CREATE FUNCTION tap._cancel225(p_id uuid, p_seller uuid) RETURNS void LANGUAGE plpgsql AS $f$
begin
  perform tap.login(p_seller);
  perform public.cancel_listing(p_id, p_seller);
  perform tap.logout();
end $f$;
-- the updated_at a listing last written in an earlier transaction carries (see the header)
CREATE FUNCTION tap._age225(p_id uuid) RETURNS void LANGUAGE plpgsql AS $f$
begin
  alter table public.listings disable trigger trg_listings_updated_at;
  update public.listings set updated_at = tap._aged225() where id = p_id;
  alter table public.listings enable trigger trg_listings_updated_at;
end $f$;
-- a cancelled admin-owned (or p_seller-owned) listing, loaded "yesterday"
CREATE FUNCTION tap._mk225(n int, p_seller uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $f$
begin
  perform tap._new225(n, coalesce(p_seller, tap.admin_user()));
  perform tap._cancel225(tap._l225(n), coalesce(p_seller, tap.admin_user()));
  perform tap._age225(tap._l225(n));
end $f$;

CREATE FUNCTION tap._aal225() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- persona wrappers: each call logs in (aal2), runs one RPC, logs out
CREATE FUNCTION tap._rl225(p_who uuid, p_key text, p_subject uuid, p_params jsonb, p_expected jsonb,
                           p_reason text DEFAULT 'pgTAP 225 relist') RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal225();
  v := ops.execute_action(p_key, 'listing_relist', 'listing', p_subject, p_params, p_reason, p_expected, NULL);
  perform tap.logout();
  return v;
end $f$;
CREATE FUNCTION tap._ex225(p_who uuid, p_key text, p_type text, p_kind text, p_subject uuid,
                           p_params jsonb DEFAULT '{}'::jsonb, p_ref text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql AS $f$
declare v jsonb;
begin
  perform tap.login(p_who); perform tap._aal225();
  v := ops.execute_action(p_key, p_type, p_kind, p_subject, p_params, 'pgTAP 225 ' || p_type, NULL, p_ref);
  perform tap.logout();
  return v;
end $f$;
-- what the console reads: the five relist keys of ops.listing_detail(id)->'listing', verbatim
CREATE FUNCTION tap._exp225(p_id uuid) RETURNS jsonb LANGUAGE plpgsql AS $f$
declare l jsonb;
begin
  perform tap.login(tap.admin_user()); perform tap._aal225();
  l := ops.listing_detail(p_id) -> 'listing';
  perform tap.logout();
  return jsonb_build_object('updated_at', l -> 'updated_at', 'status', l -> 'status', 'auction_status', l -> 'auction_status',
                            'ends_at', l -> 'ends_at', 'ended_at', l -> 'ended_at');
end $f$;
-- the live row's compared fields, and the whole row's md5
CREATE FUNCTION tap._row225(p_id uuid) RETURNS jsonb LANGUAGE sql STABLE AS $f$
  SELECT jsonb_build_object('status', l.status, 'auction_status', l.auction_status, 'ends_at', l.ends_at,
                            'ended_at', l.ended_at, 'updated_at', l.updated_at)
    FROM public.listings l WHERE l.id = p_id $f$;
CREATE FUNCTION tap._md225(p_id uuid) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT md5(to_jsonb(l)::text) FROM public.listings l WHERE l.id = p_id $f$;
CREATE FUNCTION tap._in3d() RETURNS jsonb LANGUAGE sql STABLE AS $f$ SELECT jsonb_build_object('new_ends_at', now() + interval '3 days') $f$;

-- ── R11a — the owner's DO-block shape FIRST (postgres, no request claims yet in this session) ─────────────
-- Two admin-owned rows in the 'ended' resting state, like the four production listings before 2026-10-21.
SELECT tap._new225(21, tap.admin_user(), 'ended', now() - interval '1 hour');
SELECT tap._new225(22, tap.admin_user(), 'ended', now() - interval '1 hour');
SELECT lives_ok($do$DO $relist$
DECLARE
  ids uuid[] := ARRAY[tap._l225(21), tap._l225(22)];
  owner_admin uuid := tap.admin_user();
  target timestamptz := now() + interval '7 days';
  corr uuid := gen_random_uuid();
  r public.listings%ROWTYPE;
  fp_before text;
  n_after record;
  n_ok int := 0;
BEGIN
  PERFORM set_config('lock_timeout', '3s', true);
  IF nullif(current_setting('request.jwt.claims', true), '') IS NOT NULL THEN
    RAISE EXCEPTION 'STOP: request claims are set; run as postgres with no request context';
  END IF;
  FOR r IN SELECT * FROM public.listings WHERE id = ANY(ids) ORDER BY id FOR UPDATE LOOP
    IF r.status <> 'active' OR r.auction_status <> 'ended' OR r.seller_id <> owner_admin THEN
      RAISE EXCEPTION 'STOP %: not the ended owner-admin fixture', r.id;
    END IF;
    fp_before := md5((to_jsonb(r) - 'auction_status' - 'ends_at' - 'ended_at' - 'updated_at')::text);
    PERFORM public.cancel_listing(r.id, owner_admin);
    PERFORM public.admin_relist_listing(r.id, target, owner_admin);
    SELECT md5((to_jsonb(l) - 'auction_status' - 'ends_at' - 'ended_at' - 'updated_at')::text) AS fp,
           l.status, l.auction_status, l.ends_at, l.ended_at, public.listing_is_public(l.id) AS pub
      INTO n_after FROM public.listings l WHERE l.id = r.id;
    IF n_after.fp IS DISTINCT FROM fp_before THEN
      RAISE EXCEPTION 'STOP %: a preserved column changed', r.id;
    END IF;
    IF n_after.status <> 'active' OR n_after.auction_status <> 'active' OR n_after.ends_at <> target
       OR n_after.ended_at IS NOT NULL OR NOT n_after.pub THEN
      RAISE EXCEPTION 'STOP %: post-state is not open and public', r.id;
    END IF;
    INSERT INTO ops.audit (actor, actor_role, action, subject_kind, subject_id, subject_ref, reason, before, after, outcome, correlation_id)
    VALUES (owner_admin, 'platform_admin', 'listing.relist', 'listing', r.id, r.event_name, 'pgTAP 225 R11 DO-block shape',
            jsonb_build_object('status', r.status, 'auction_status', r.auction_status, 'ends_at', r.ends_at, 'ended_at', r.ended_at),
            jsonb_build_object('status', n_after.status, 'auction_status', n_after.auction_status, 'ends_at', n_after.ends_at,
                               'ended_at', n_after.ended_at), 'succeeded', corr);
    n_ok := n_ok + 1;
  END LOOP;
  IF n_ok <> 2 THEN
    RAISE EXCEPTION 'STOP: relisted % of 2', n_ok;
  END IF;
END
$relist$$do$,
  'R11.1: the RELIST_FOUR_LISTINGS_7D DO-block shape (postgres, no claims; cancel_listing + admin_relist_listing under FOR UPDATE, preserved-column md5) succeeds on two fixture rows');
SELECT is((SELECT array_agg(status || '/' || auction_status || '/' || (ended_at IS NULL)::text ORDER BY id) FROM public.listings
            WHERE id IN (tap._l225(21), tap._l225(22))),
          ARRAY['active/active/true', 'active/active/true'], 'R11.2: ...both rows are open again (active / active, ended_at NULL)');
SELECT is((SELECT count(*)::int FROM ops.action WHERE subject_id IN (tap._l225(21), tap._l225(22))), 0,
  'R11.3: ...the owner path wrote no ops.action row (it never goes through the console layer)');

-- fixtures for the console cases (cancelled through cancel_listing by their seller, then "loaded yesterday")
SELECT tap._mk225(1);    -- R1 / R8
SELECT tap._mk225(2);    -- R2 / R3
SELECT tap._mk225(3);    -- R4 full keys
SELECT tap._mk225(4);    -- R4 updated_at only
SELECT tap._mk225(5);    -- R5 drift
SELECT tap._mk225(6);    -- R5 present keys
SELECT tap._mk225(7);    -- R6 precision
SELECT tap._mk225(8);    -- R6 another session TimeZone
SELECT tap._mk225(9);    -- R9 / R10
SELECT tap._mk225(23);   -- R11 direct call
SELECT tap._mk225(41);   -- R6.6 earlier-started writer
SELECT tap._mk225(42);   -- R1.8 result.before with expected {updated_at} alone
-- R7: history (bid while active, then cancelled), payment, payment + transfer, a real seller, hidden, end time
SELECT tap._new225(11, tap.admin_user());
SELECT tap.login(tap.buyer());
INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (tap._l225(11), tap.buyer(), 120);
SELECT tap.logout();
SELECT tap._cancel225(tap._l225(11), tap.admin_user());
SELECT tap._mk225(12);
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
VALUES (tap._p225(12), tap._l225(12), tap.buyer(), tap.admin_user(), 10000, 1000, 1000, 11000, 'pi_fixture_225_12', 'failed', 'buy_now', NULL);
SELECT tap._mk225(13);
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
VALUES (tap._p225(13), tap._l225(13), tap.buyer(), tap.admin_user(), 10000, 1000, 1000, 11000, 'pi_fixture_225_13', 'succeeded', 'buy_now', now());
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
VALUES (tap._t225(13), tap._l225(13), tap._p225(13), tap.admin_user(), tap.buyer(), 'mobile_transfer', 'pending', now() + interval '24 hours');
SELECT tap._mk225(14, tap.seller());
SELECT tap._mk225(15);
INSERT INTO public.listing_visibility (listing_id, hidden_reason, hidden_by) VALUES (tap._l225(15), 'pgTAP 225 hidden', tap.admin_user());
SELECT tap._mk225(16);
SELECT is((SELECT count(*)::int FROM public.listings WHERE id IN (tap._l225(1), tap._l225(2), tap._l225(3), tap._l225(4), tap._l225(5),
             tap._l225(6), tap._l225(7), tap._l225(8), tap._l225(9), tap._l225(11), tap._l225(12), tap._l225(13), tap._l225(14),
             tap._l225(15), tap._l225(16), tap._l225(23)) AND status = 'active' AND auction_status = 'cancelled' AND ended_at IS NOT NULL), 16,
  'F0: fixtures: sixteen listings in the cancelled resting state, reached through cancel_listing');

-- ── R1 — happy path (listing 1) ─────────────────────────────────────────────
SELECT tap._s225('e1', tap._exp225(tap._l225(1)));
SELECT is(((tap._g225('e1') ->> 'updated_at')::timestamptz, (tap._g225('e1') ->> 'updated_at') ~ '\.123456', tap._g225('e1') ->> 'updated_at'),
          (tap._aged225(), true, to_jsonb((SELECT updated_at FROM public.listings WHERE id = tap._l225(1))) #>> '{}'),
  'R1.1: ops.listing_detail returns listing.updated_at as the raw to_jsonb string, microseconds included');
SELECT tap._s225('row1', tap._row225(tap._l225(1)));
SELECT tap._s225('in1', tap._in3d());
SELECT tap._s225('r1', tap._rl225(tap.admin_user(), 'k225-r1-relist-a01', tap._l225(1), tap._g225('in1'), tap._g225('e1')));
SELECT is(tap._g225('r1') ->> 'status', 'succeeded', 'R1.2: relist with the expected read from ops.listing_detail => succeeded');
SELECT is((SELECT (status, auction_status, ends_at, ended_at IS NULL) FROM public.listings WHERE id = tap._l225(1)),
          ('active'::text, 'active'::text, (tap._g225('in1') ->> 'new_ends_at')::timestamptz, true),
  'R1.3: the listing is active / active with the new ends_at and ended_at NULL');
SELECT is((SELECT (state, reject_reason IS NULL, completed_at IS NOT NULL, approval_id IS NULL, expected = tap._g225('e1'))
             FROM ops.action WHERE idempotency_key = 'k225-r1-relist-a01'),
          ('succeeded'::text, true, true, true, true), 'R1.4: the ops.action row is succeeded (no approval), expected stored as sent');
SELECT is(tap._g225('r1') #> '{result,before}', tap._g225('row1'), 'R1.5: result.before = the locked row (status, auction_status, ends_at, ended_at, updated_at)');
SELECT is((tap._g225('r1') #>> '{result,result,listing_id}', (tap._g225('r1') #>> '{result,result,previous_ends_at}')::timestamptz),
          (tap._l225(1)::text, (tap._g225('row1') ->> 'ends_at')::timestamptz),
  'R1.6: result.result is admin_relist_listing''s own answer (listing_id, previous_ends_at)');
SELECT is((SELECT count(*)::int FROM ops.audit WHERE subject_id = tap._l225(1) AND action = 'action.listing_relist' AND outcome = 'succeeded'), 1,
  'R1.7: audited action.listing_relist / succeeded');
-- R1.8 (listing 42): in R1 the expected IS the locked row (same jsonb), so R1.5 cannot tell them apart. Here the
-- client sends {updated_at} alone (R5.8's shape): result.before must still be the five fields of the locked row.
SELECT tap._s225('row42', tap._row225(tap._l225(42)));
SELECT tap._s225('r42', tap._rl225(tap.admin_user(), 'k225-r1-before-a02', tap._l225(42), tap._in3d(),
                                   jsonb_build_object('updated_at', tap._exp225(tap._l225(42)) -> 'updated_at')));
SELECT is((tap._g225('r42') ->> 'status', tap._g225('r42') #> '{result,before}'), ('succeeded'::text, tap._g225('row42')),
  'R1.8: expected {updated_at} alone => succeeded and result.before = the locked row''s five fields (the server''s record, not the client''s expected)');

-- ── R2 / R3 — expected.updated_at is required (listing 2) ───────────────────
SELECT tap._s225('md2', to_jsonb(tap._md225(tap._l225(2))));
SELECT tap._s225('au2', to_jsonb((SELECT count(*) FROM ops.audit WHERE subject_id = tap._l225(2))));
SELECT tap._s225('e2', tap._exp225(tap._l225(2)));
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, NULL)', tap.admin_user(), 'k225-r2-null-01', tap._l225(2), tap._in3d()),
  'P0001', tap._inval225(), 'R2.1: expected NULL => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r2-empty-01', tap._l225(2), tap._in3d(), '{}'),
  'P0001', tap._inval225(), 'R2.2: expected {} => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r2-console-01', tap._l225(2), tap._in3d(),
                        jsonb_build_object('status', tap._g225('e2') -> 'status', 'auction_status', tap._g225('e2') -> 'auction_status')),
  'P0001', tap._inval225(), 'R2.3: today''s console payload {status, auction_status} => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r3-jsonnull-01', tap._l225(2), tap._in3d(),
                        tap._g225('e2') || '{"updated_at": null}'),
  'P0001', tap._inval225(), 'R3.1: updated_at JSON null => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r3-number-01', tap._l225(2), tap._in3d(),
                        tap._g225('e2') || '{"updated_at": 1729436645}'),
  'P0001', tap._inval225(), 'R3.2: updated_at a number => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r3-yesterday-01', tap._l225(2), tap._in3d(),
                        tap._g225('e2') || '{"updated_at": "yesterday"}'),
  'P0001', tap._inval225(), 'R3.3: updated_at ''yesterday'' (casts, but is not a version) => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r3-blank-01', tap._l225(2), tap._in3d(),
                        tap._g225('e2') || '{"updated_at": ""}'),
  'P0001', tap._inval225(), 'R3.4: updated_at '''' => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r3-nooffset-01', tap._l225(2), tap._in3d(),
                        tap._g225('e2') || '{"updated_at": "2026-10-20T15:04:05.123456"}'),
  'P0001', tap._inval225(), 'R3.5: updated_at without a UTC offset (session-TimeZone dependent) => invalid_input');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r3-badday-01', tap._l225(2), tap._in3d(),
                        tap._g225('e2') || '{"updated_at": "2026-02-30T15:04:05.123456+00:00"}'),
  'P0001', tap._inval225(), 'R3.6: updated_at shaped right but not a date (2026-02-30) => invalid_input');
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key LIKE 'k225-r2-%' OR idempotency_key LIKE 'k225-r3-%'), 0,
  'R3.7: no ops.action row for any refused request');
SELECT is((SELECT count(*) FROM ops.audit WHERE subject_id = tap._l225(2)), (tap._g225('au2') #>> '{}')::bigint,
  'R3.8: no audit row for any refused request');
SELECT is(tap._md225(tap._l225(2)), tap._g225('md2') #>> '{}', 'R3.9: listing 2 unchanged (row md5)');

-- ── R4 — ABA (listings 3 and 4) ─────────────────────────────────────────────
SELECT tap._s225('e3', tap._exp225(tap._l225(3)));
SELECT tap._s225('e4', jsonb_build_object('updated_at', tap._exp225(tap._l225(4)) -> 'updated_at'));
-- after the capture: relisted directly (the owner's service-role path), then cancelled again by the seller
SELECT tap.login_service();
SELECT tap._s225('aba3', public.admin_relist_listing(tap._l225(3), now() + interval '7 days', tap.admin_user()));
SELECT tap._s225('aba4', public.admin_relist_listing(tap._l225(4), now() + interval '7 days', tap.admin_user()));
SELECT tap.logout();
SELECT tap._cancel225(tap._l225(3), tap.admin_user());
SELECT tap._cancel225(tap._l225(4), tap.admin_user());
SELECT is((SELECT (status, auction_status, ends_at <> (tap._g225('e3') ->> 'ends_at')::timestamptz) FROM public.listings WHERE id = tap._l225(3)),
          ('active'::text, 'cancelled'::text, true), 'R4.1: fixture: listing 3 is back in the cancelled resting state (the A of ABA)');
SELECT tap._s225('md3', to_jsonb(tap._md225(tap._l225(3))));
SELECT tap._s225('md4', to_jsonb(tap._md225(tap._l225(4))));
SELECT tap._s225('r4', tap._rl225(tap.admin_user(), 'k225-r4-aba-a01', tap._l225(3), tap._in3d(), tap._g225('e3')));
SELECT is((tap._g225('r4') ->> 'status', tap._g225('r4') ->> 'reject_reason'), ('rejected'::text, 'stale_state'::text),
  'R4.2: the stale submit after relist + re-cancel => rejected / stale_state');
SELECT is((tap._g225('r4') ->> 'message', tap._g225('r4') #>> '{result,message}'), (tap._stale225(), tap._stale225()), 'R4.3: message (contract wording)');
SELECT is(tap._g225('r4') #> '{result,current}', tap._row225(tap._l225(3)), 'R4.4: result.current = the live row');
SELECT is((tap._md225(tap._l225(3)), (SELECT auction_status FROM public.listings WHERE id = tap._l225(3))),
          (tap._g225('md3') #>> '{}', 'cancelled'::text), 'R4.5: the listing is unchanged and still cancelled');
SELECT is((SELECT (state, reject_reason, completed_at IS NOT NULL, result -> 'current' = tap._row225(tap._l225(3)))
             FROM ops.action WHERE idempotency_key = 'k225-r4-aba-a01'),
          ('rejected'::text, 'stale_state'::text, true, true), 'R4.6: the ops.action row is rejected / stale_state with result.current');
SELECT tap._s225('r4b', tap._rl225(tap.admin_user(), 'k225-r4-aba-a02', tap._l225(4), tap._in3d(), tap._g225('e4')));
SELECT is((tap._g225('r4b') ->> 'status', tap._g225('r4b') ->> 'reject_reason', tap._md225(tap._l225(4))),
          ('rejected'::text, 'stale_state'::text, tap._g225('md4') #>> '{}'),
  'R4.7: expected = {updated_at} alone catches the same ABA (stale_state, listing 4 unchanged)');

-- ── R5 — content drift (listing 5); present / absent keys (listing 6) ───────
SELECT tap._s225('e5', tap._exp225(tap._l225(5)));
SELECT tap.login(tap.admin_user());
UPDATE public.listings SET restrictions = 'No re-entry (225 drift)' WHERE id = tap._l225(5);
SELECT tap.logout();
SELECT tap._s225('md5', to_jsonb(tap._md225(tap._l225(5))));
SELECT tap._s225('r5', tap._rl225(tap.admin_user(), 'k225-r5-drift-a01', tap._l225(5), tap._in3d(), tap._g225('e5')));
SELECT is((tap._g225('r5') ->> 'status', tap._g225('r5') ->> 'reject_reason', tap._g225('r5') #>> '{result,current,auction_status}'),
          ('rejected'::text, 'stale_state'::text, 'cancelled'::text),
  'R5.1: the seller edited restrictions after the capture (client UPDATE path) => stale_state');
SELECT is(((tap._g225('r5') #>> '{result,current,updated_at}')::timestamptz, tap._md225(tap._l225(5)),
           (SELECT restrictions FROM public.listings WHERE id = tap._l225(5))),
          ((SELECT updated_at FROM public.listings WHERE id = tap._l225(5)), tap._g225('md5') #>> '{}', 'No re-entry (225 drift)'::text),
  'R5.2: ...result.current.updated_at is the live one, and the listing (with the unreviewed text) stays unpublished and unchanged');
SELECT tap._s225('e6', tap._exp225(tap._l225(6)));
SELECT tap._s225('md6', to_jsonb(tap._md225(tap._l225(6))));
SELECT is(tap._rl225(tap.admin_user(), 'k225-r5-keys-a01', tap._l225(6), tap._in3d(), tap._g225('e6') || '{"auction_status": "active"}') ->> 'reject_reason',
          'stale_state', 'R5.3: present auction_status that differs => stale_state (updated_at fresh)');
SELECT is(tap._rl225(tap.admin_user(), 'k225-r5-keys-a02', tap._l225(6), tap._in3d(), tap._g225('e6') || '{"status": "sold"}') ->> 'reject_reason',
          'stale_state', 'R5.4: present status that differs => stale_state');
SELECT is(tap._rl225(tap.admin_user(), 'k225-r5-keys-a03', tap._l225(6), tap._in3d(),
                     tap._g225('e6') || jsonb_build_object('ends_at', (tap._g225('e6') ->> 'ends_at')::timestamptz + interval '1 microsecond')) ->> 'reject_reason',
          'stale_state', 'R5.5: present ends_at one microsecond off => stale_state');
SELECT is(tap._rl225(tap.admin_user(), 'k225-r5-keys-a04', tap._l225(6), tap._in3d(), tap._g225('e6') || '{"ended_at": null}') ->> 'reject_reason',
          'stale_state', 'R5.6: present ended_at JSON null (= expected NULL) while the live ended_at is set => stale_state');
SELECT is(tap._md225(tap._l225(6)), tap._g225('md6') #>> '{}', 'R5.7: listing 6 unchanged by the four refusals');
SELECT is(tap._rl225(tap.admin_user(), 'k225-r5-keys-a05', tap._l225(6), tap._in3d(), jsonb_build_object('updated_at', tap._g225('e6') -> 'updated_at')) ->> 'status',
          'succeeded', 'R5.8: absent keys are not compared: {updated_at} alone (fresh) => succeeded');

-- ── R6 — precision (listing 7) ──────────────────────────────────────────────
SELECT tap._s225('e7', tap._exp225(tap._l225(7)));
SELECT tap._s225('e7ms', tap._g225('e7') || jsonb_build_object('updated_at', date_trunc('milliseconds', (tap._g225('e7') ->> 'updated_at')::timestamptz)));
SELECT is(((tap._g225('e7ms') ->> 'updated_at') <> (tap._g225('e7') ->> 'updated_at'),
           (tap._g225('e7ms') ->> 'updated_at')::timestamptz = (tap._g225('e7') ->> 'updated_at')::timestamptz),
          (true, false), 'R6.1: fixture: the millisecond string differs from the live value as text and as an instant');
SELECT tap._s225('md7', to_jsonb(tap._md225(tap._l225(7))));
SELECT is(tap._rl225(tap.admin_user(), 'k225-r6-ms-a01', tap._l225(7), tap._in3d(), tap._g225('e7ms')) ->> 'reject_reason',
          'stale_state', 'R6.2: updated_at truncated to milliseconds (a JS Date round trip) => stale_state');
SELECT is(tap._md225(tap._l225(7)), tap._g225('md7') #>> '{}', 'R6.3: listing 7 unchanged');
SELECT is(tap._rl225(tap.admin_user(), 'k225-r6-utc-a02', tap._l225(7), tap._in3d(),
                     tap._g225('e7') || jsonb_build_object('updated_at', to_char((tap._g225('e7') ->> 'updated_at')::timestamptz AT TIME ZONE 'UTC',
                                                                                 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))) ->> 'status',
          'succeeded', 'R6.4: the same instant written in UTC (''...Z'') => succeeded (compared as an instant, to the microsecond)');
-- listing 8 read under Asia/Kathmandu (+05:45), relisted under the session default: the string names an instant.
-- The whole file runs in one transaction, so SET LOCAL / RESET change nothing outside it.
SET LOCAL TimeZone = 'Asia/Kathmandu';
SELECT tap._s225('e8', tap._exp225(tap._l225(8)));
RESET TimeZone;
SELECT is(((tap._g225('e8') ->> 'updated_at') ~ '\+05:45$', current_setting('TimeZone') <> 'Asia/Kathmandu',
           tap._rl225(tap.admin_user(), 'k225-r6-tz-a03', tap._l225(8), tap._in3d(), tap._g225('e8')) ->> 'status'),
          (true, true, 'succeeded'::text),
  'R6.5: expected read under another session TimeZone (+05:45) and submitted under the default one => succeeded');
-- listing 41: the live updated_at moves BACK. A writer whose transaction began before the version the operator
-- loaded, and committed after it, stamps an earlier updated_at (now() = its transaction start). Simulated here:
-- after the capture the content changes and updated_at becomes 1 microsecond earlier (trigger off for that statement).
SELECT tap._s225('e41', tap._exp225(tap._l225(41)));
ALTER TABLE public.listings DISABLE TRIGGER trg_listings_updated_at;
UPDATE public.listings SET restrictions = 'R6.6 earlier-started writer', updated_at = tap._aged225() - interval '1 microsecond'
 WHERE id = tap._l225(41);
ALTER TABLE public.listings ENABLE TRIGGER trg_listings_updated_at;
SELECT tap._s225('md41', to_jsonb(tap._md225(tap._l225(41))));
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason')
             FROM tap._rl225(tap.admin_user(), 'k225-r6-back-a06', tap._l225(41), tap._in3d(), tap._g225('e41')) r),
          ('rejected'::text, 'stale_state'::text),
  'R6.6: the live updated_at is EARLIER than the expected one (an earlier-started writer rewrote the content) => stale_state');
SELECT is(tap._md225(tap._l225(41)), tap._g225('md41') #>> '{}', 'R6.7: listing 41 unchanged (the unreviewed content stays unpublished)');

-- ── R7 — domain guards with a FRESH expected ────────────────────────────────
SELECT tap._s225('md7x', (SELECT jsonb_object_agg(n::text, tap._md225(tap._l225(n))) FROM unnest(ARRAY[11,12,13,14,15,16]) n));
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-bid-a01', tap._l225(11), tap._in3d(), tap._exp225(tap._l225(11))) r),
          ('rejected'::text, 'precondition'::text, 'Listing has payment/transfer/bid history and cannot be relisted.'::text),
  'R7.1: bid history => rejected / precondition (domain message)');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-pay-a01', tap._l225(12), tap._in3d(), tap._exp225(tap._l225(12))) r),
          ('rejected'::text, 'precondition'::text, 'Listing has payment/transfer/bid history and cannot be relisted.'::text),
  'R7.2: payment history => rejected / precondition');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-xfer-a01', tap._l225(13), tap._in3d(), tap._exp225(tap._l225(13))) r),
          ('rejected'::text, 'precondition'::text, 'Listing has payment/transfer/bid history and cannot be relisted.'::text),
  'R7.3: payment + transfer history => rejected / precondition');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-seller-a01', tap._l225(14), tap._in3d(), tap._exp225(tap._l225(14))) r),
          ('rejected'::text, 'precondition'::text, 'Only admin-owned inventory can be relisted; a real seller''s cancellation stands.'::text),
  'R7.4: a real seller''s listing => rejected / precondition');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-hidden-a01', tap._l225(15), tap._in3d(), tap._exp225(tap._l225(15))) r),
          ('rejected'::text, 'precondition'::text, 'Hidden listing cannot be made live.'::text),
  'R7.5: a hidden listing (154) => rejected / precondition');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-past-a01', tap._l225(16), jsonb_build_object('new_ends_at', now() - interval '1 hour'),
                             tap._exp225(tap._l225(16))) r),
          ('rejected'::text, 'precondition'::text, 'New end time must be in the future.'::text),
  'R7.6: new_ends_at in the past => rejected / precondition');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-noend-a01', tap._l225(16), '{}'::jsonb, tap._exp225(tap._l225(16))) r),
          ('rejected'::text, 'precondition'::text, 'New end time must be in the future.'::text),
  'R7.7: new_ends_at missing => rejected / precondition');
SELECT is((SELECT (r ->> 'status', r ->> 'reject_reason', r ->> 'message', r -> 'result')
             FROM tap._rl225(tap.admin_user(), 'k225-r7-none-a01', 'aaaaaaaa-0225-0000-0000-0000000000ff', tap._in3d(),
                             jsonb_build_object('updated_at', '2026-10-20T15:04:05.123456+00:00')) r),
          ('rejected'::text, 'precondition'::text, 'Listing not found.'::text,
           '{"status": "rejected", "reject_reason": "precondition", "message": "Listing not found."}'::jsonb),
  'R7.8: listing not found => the pre-158 answer byte for byte (rejected / precondition ''Listing not found.'')');
SELECT is((SELECT jsonb_object_agg(n::text, tap._md225(tap._l225(n))) FROM unnest(ARRAY[11,12,13,14,15,16]) n), tap._g225('md7x'),
  'R7.9: listings 11-16 unchanged (row md5 each)');
SELECT is((SELECT count(*)::int FROM ops.action WHERE idempotency_key LIKE 'k225-r7-%' AND state = 'rejected' AND reject_reason = 'precondition'), 8,
  'R7.10: eight ops.action rows, each rejected / precondition');
SELECT throws_ok(format('SELECT public.admin_relist_listing(%L, now() + interval ''3 days'', %L)', 'aaaaaaaa-0225-0000-0000-0000000000ff', tap.admin_user()),
  'P0001', 'Listing not found.', 'R7.11: ...that text is admin_relist_listing''s own refusal for a missing listing (the existing message, unchanged)');

-- ── R8 — idempotent replay (listing 1, after R1) ────────────────────────────
SELECT tap._s225('md1', to_jsonb(tap._md225(tap._l225(1))));
SELECT is((SELECT (r ->> 'status', r ->> 'action_id', r ->> 'state')
             FROM tap._rl225(tap.admin_user(), 'k225-r1-relist-a01', tap._l225(1), tap._g225('in1'), tap._g225('e1')) r),
          ('idempotent_replay'::text, tap._g225('r1') ->> 'action_id', 'succeeded'::text),
  'R8.1: replaying R1''s key => idempotent_replay of the same action (state succeeded)');
SELECT is((SELECT (r ->> 'status', r ->> 'action_id')
             FROM tap._rl225(tap.admin_user(), 'k225-r1-relist-a01', tap._l225(1), tap._g225('in1'), '{}'::jsonb) r),
          ('idempotent_replay'::text, tap._g225('r1') ->> 'action_id'),
  'R8.2: ...even without expected: the key lookup comes first, as before 158');
SELECT is(((SELECT count(*)::int FROM ops.action WHERE idempotency_key = 'k225-r1-relist-a01'), tap._md225(tap._l225(1))),
          (1, tap._g225('md1') #>> '{}'), 'R8.3: one row for the key; listing 1 not relisted again');

-- ── R9 / R10 — role and pause (listing 9) ───────────────────────────────────
SELECT tap._s225('md9', to_jsonb(tap._md225(tap._l225(9))));
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.seller(), 'platform_support', tap.admin_user());
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.seller(), 'k225-r9-support-01', tap._l225(9), tap._in3d(),
                        tap._exp225(tap._l225(9))),
  '42501', 'insufficient_privilege: platform_support may not perform listing_relist', 'R9.1: platform_support => 42501 (unchanged)');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.seller(), 'k225-r9-support-02', tap._l225(9), tap._in3d(),
                        '{"status": "active", "auction_status": "cancelled"}'),
  '42501', 'insufficient_privilege: platform_support may not perform listing_relist',
  'R9.2: platform_support with today''s console payload (no updated_at) => still 42501, not invalid_input (the role check comes first)');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb, NULL)', tap.admin_user(), 'k225-r9-noreason-01', tap._l225(9), tap._in3d(),
                        '{"status": "active", "auction_status": "cancelled"}'),
  'P0001', 'invalid_input: a reason is required for listing_relist',
  'R9.3: no reason and no updated_at => the existing ''a reason is required'' refusal, unchanged (the reason check comes first)');
SELECT is(tap._ex225(tap.admin_user(), 'k225-r10-pause-01', 'setting_set', 'setting', NULL, '{"value": false}'::jsonb, 'actions_enabled') ->> 'status',
          'succeeded', 'R10.1: a founder pauses console actions');
SELECT throws_ok(format('SELECT tap._rl225(%L, %L, %L, %L::jsonb, %L::jsonb)', tap.admin_user(), 'k225-r10-paused-01', tap._l225(9), tap._in3d(),
                        '{"status": "active", "auction_status": "cancelled"}'),
  'P0001', 'precondition_failed: console_actions_paused — a founder paused console actions (ops.setting actions_enabled = false); reads remain available',
  'R10.2: paused => precondition_failed (unchanged), also with today''s console payload (no updated_at)');
SELECT is(tap._ex225(tap.admin_user(), 'k225-r10-resume-01', 'setting_set', 'setting', NULL, '{"value": true}'::jsonb, 'actions_enabled') ->> 'status',
          'succeeded', 'R10.3: ...and resumes them');
SELECT is(((SELECT count(*)::int FROM ops.action WHERE idempotency_key IN ('k225-r9-support-01', 'k225-r9-support-02', 'k225-r9-noreason-01',
                                                                         'k225-r10-paused-01')), tap._md225(tap._l225(9))),
          (0, tap._g225('md9') #>> '{}'), 'R10.4: no row for any of the four refused requests; listing 9 unchanged');

-- ── R11b — the direct 3-arg call still works with no expected (listing 23) ──
SELECT tap.login_service();
SELECT tap._s225('r11', public.admin_relist_listing(tap._l225(23), now() + interval '7 days', tap.admin_user()));
SELECT tap.logout();
SELECT is((tap._g225('r11') ->> 'listing_id', (SELECT auction_status FROM public.listings WHERE id = tap._l225(23))),
          (tap._l225(23)::text, 'active'::text), 'R11.4: public.admin_relist_listing(id, ts, admin) as service_role, no expected => relisted');
SELECT is(md5(pg_get_functiondef('public.admin_relist_listing(uuid,timestamptz,uuid)'::regprocedure)), 'ef4c9ba0a832230db6752c069e467ca4',
  'R11.5: public.admin_relist_listing keeps its production md5');

-- ── R12 — ACLs and catalog ──────────────────────────────────────────────────
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure),
          'postgres=X/postgres,authenticated=X/postgres', 'R12.1: execute_action ACL = production / 157');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'ops.action_dispatch(ops.action)'::regprocedure),
          'postgres=X/postgres', 'R12.2: action_dispatch ACL = production (postgres only)');
SELECT is((SELECT array_to_string(proacl, ',') FROM pg_proc WHERE oid = 'public.admin_relist_listing(uuid,timestamptz,uuid)'::regprocedure),
          'postgres=X/postgres,service_role=X/postgres', 'R12.3: admin_relist_listing ACL unchanged (postgres + service_role)');
SELECT is((SELECT array_agg(p.proname::text || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ','), '') ORDER BY p.proname)
             FROM pg_proc p WHERE p.oid IN ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure,
                                            'ops.action_dispatch(ops.action)'::regprocedure)),
          ARRAY['action_dispatch:true:search_path=""', 'execute_action:true:search_path=""'],
  'R12.4: both stay SECURITY DEFINER with search_path ''''');
SELECT is((SELECT md5(substr(d, 1, s - 1) || substr(d, e + length('  -- 158 end') + 1))
             FROM (SELECT d, position('  -- 158 begin' IN d) AS s, position('  -- 158 end' IN d) AS e
                     FROM (SELECT pg_get_functiondef('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)'::regprocedure) AS d) x) y
            WHERE s > 0 AND e > s),
          '0da9bc63acb58f1d76a86f8039c0c877',
  'R12.5: execute_action without the marked 158 block is 157''s body byte for byte (md5 0da9bc63)');
SELECT is((SELECT md5(substr(d, 1, s - 1)
                      || E'  when ''listing_relist'' then\n'
                      || E'    v_res := public.admin_relist_listing(a.subject_id, (a.params ->> ''new_ends_at'')::timestamptz, v_uid);\n'
                      || E'    return jsonb_build_object(''status'',''succeeded'',''result'', v_res);\n\n'
                      || substr(d, e))
             FROM (SELECT d, position(E'  when ''listing_relist'' then\n' IN d) AS s, position(E'  when ''report_resolve'' then\n' IN d) AS e
                     FROM (SELECT pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure) AS d) x) y
            WHERE s > 0 AND e > s),
          'bfb8b9dcfaace5ff04009f96b6de7bef',
  'R12.6: action_dispatch with the production listing_relist branch put back is production''s body (md5 bfb8b9dc): no other branch changed');
SELECT is((SELECT count(*)::int FROM (VALUES
             ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', '0da9bc63acb58f1d76a86f8039c0c877'),
             ('ops.execute_action(text,text,text,uuid,jsonb,text,jsonb,text)', 'e59c158453adabc662431cac9dca1040'),
             ('ops.action_dispatch(ops.action)', 'bfb8b9dcfaace5ff04009f96b6de7bef')) v(sig, old_md5)
            WHERE md5(pg_get_functiondef(v.sig::regprocedure)) <> v.old_md5), 3,
  'R12.7: both redefined bodies are live (neither 157''s nor production''s md5)');
SELECT is((SELECT coalesce(array_agg(v.sig ORDER BY v.sig), '{}'::text[]) FROM (VALUES
             ('ops.action_run(uuid)', '546693f1489c364de19e9416a92c07ed'),
             ('ops.action_requires_approval(text)', '44ab739b9db2c77ef8709fed6c1d5082'),
             ('ops.action_allowed_roles(text)', '972443bf571dc94ef1e1400602b28315'),
             ('ops.action_precheck(ops.action)', 'fbc3d08eae4de831ab3f085e170e8f10'),
             ('ops.action_hash(text,text,uuid,text,jsonb)', 'ad280c19761b428d644281f6e336a7c5'),
             ('ops.listing_detail(uuid)', '5208dbb14d749db54c2fdd62e50ab800'),
             ('ops.approve_action(uuid,text,text)', '60fb8ce43d5ff1b051e379ac6affb53f'),
             ('ops.order_detail(uuid)', '4358f577291f84b25986b8904b38ab36'),
             ('public.cancel_listing(uuid,uuid)', 'ba31642267e65fefbf9485a144efc753')) v(sig, md5)
            WHERE md5(pg_get_functiondef(to_regprocedure(v.sig))) IS DISTINCT FROM v.md5),
          '{}'::text[],
  'R12.8: neighbours unchanged: action_run, requires_approval, allowed_roles, precheck, action_hash, listing_detail (production); approve_action, order_detail (157); cancel_listing');
-- static lock check (M1): a single session cannot observe a missing FOR UPDATE. In the listing_relist branch of the
-- live dispatch (comments stripped, whitespace collapsed) the listing is read FOR UPDATE before admin_relist_listing.
SELECT is((SELECT CASE WHEN lk = 0 THEN 'no locked listing read' WHEN rl = 0 THEN 'no admin_relist_listing call'
                       WHEN lk < rl THEN 'listing locked first' ELSE 'admin_relist_listing first' END
             FROM (SELECT position('from public.listings where id = a.subject_id for update' IN b) AS lk,
                          position('public.admin_relist_listing(' IN b) AS rl
                     FROM (SELECT substring(d FROM 'when ''listing_relist'' then(.*?)when ''report_resolve'' then') AS b
                             FROM (SELECT regexp_replace(regexp_replace(lower(pg_get_functiondef('ops.action_dispatch(ops.action)'::regprocedure)),
                                                                        '--[^\n]*', '', 'g'), '\s+', ' ', 'g') AS d) x) y) z),
          'listing locked first',
  'R12.9: the listing_relist branch reads the listing FOR UPDATE before it calls admin_relist_listing (static; comments stripped)');

-- ── R13 — 157's money guard still works with 158 applied (order 31) ─────────
SELECT tap._new225(31, tap.seller());
INSERT INTO public.payments (id, listing_id, buyer_id, seller_id, amount, buyer_fee, seller_fee, total, stripe_payment_intent_id, status, mode, paid_at)
VALUES (tap._p225(31), tap._l225(31), tap.buyer(), tap.seller(), 10000, 1000, 1000, 11000, 'pi_fixture_225_31', 'succeeded', 'buy_now', now());
INSERT INTO public.transfers (id, listing_id, payment_id, seller_id, buyer_id, transfer_method, status, seller_sent_at, auto_release_at, transfer_evidence_path, expires_at)
VALUES (tap._t225(31), tap._l225(31), tap._p225(31), tap.seller(), tap.buyer(), 'mobile_transfer', 'seller_sent', now(), now() + interval '72 hours',
        'fixtures/evidence-225.jpg', now() + interval '24 hours');
SELECT is(tap._ex225(tap.admin_user(), 'k225-r13-set-on', 'setting_set', 'setting', NULL, '{"value": true}'::jsonb, 'refund_execute_enabled') ->> 'status',
          'succeeded', 'R13.1: setting_set refund_execute_enabled=true (inside this transaction)');
SELECT tap._s225('r13a', tap._ex225(tap.admin_user(), 'k225-r13-refund-a01', 'refund_execute', 'payment', tap._p225(31)));
SELECT tap._s225('r13b', tap._ex225(tap.other_user(), 'k225-r13-refund-b01', 'refund_execute', 'payment', tap._p225(31)));
SELECT is((tap._g225('r13a') ->> 'status', tap._g225('r13b') ->> 'status', tap._g225('r13b') ->> 'reject_reason', tap._g225('r13b') #>> '{blocking,action_id}'),
          ('awaiting_approval'::text, 'rejected'::text, 'duplicate_unsettled'::text, tap._g225('r13a') ->> 'action_id'),
  'R13.2: the first refund parks; a second (founder B, new key) is refused duplicate_unsettled, blocking = the first');
SELECT is((SELECT count(*)::int FROM ops.action WHERE action_type = 'refund_execute' AND subject_id = tap._p225(31)
            AND state IN ('requested','awaiting_approval','processing','unknown','succeeded_at_provider')), 1,
  'R13.3: exactly one unsettled refund_execute on the payment');

SELECT * FROM finish();
ROLLBACK;
