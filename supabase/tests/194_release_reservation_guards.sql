-- ============================================================================
-- 194_release_reservation_guards.sql — migration 127 (L1 + L2).
--
-- L2: `release_reservation` must no-op on a listing that holds a succeeded
--     payment, matching the N1 guard the sweeps already apply.
-- L1: `release_reservation_for_payment` must release ONLY the hold that belongs
--     to the given payment — never one taken after it (the stale-cancellation
--     case), never on a paid or sold listing, never for a payment that is not
--     this listing's and this buyer's.
--
-- The suite also pins the TTL COUPLING between 127 and `reserve_buy_now`: 127's
-- staleness test is `reserved_until > payment.created_at + 10 minutes`, which is
-- only correct while reserve_buy_now's window is 10 minutes. If either moves,
-- assertion 7 fails rather than the guard silently going wrong.
--
-- now() is frozen for the suite transaction, so "taken after the payment" is
-- constructed by backdating the payment row rather than by waiting.
-- ============================================================================
BEGIN;
SELECT plan(30);
-- Runs as the suite runner does (role `postgres`, no request.jwt.claims), which
-- is ALLOW 2 of 119's guard_listing_insert_columns(); tap.seed_core() sets
-- server-controlled listing columns and is refused under any other role.
SELECT tap.seed_core();

CREATE TABLE tap.memo_194 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._s194(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_194 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._f194(k text) RETURNS text
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v FROM tap.memo_194 WHERE k=$1 $m$;

-- Fixture: one buy-now listing, held by the buyer, plus the buyer's payment row.
CREATE FUNCTION tap._mklisting194(p_name text) RETURNS uuid LANGUAGE plpgsql AS $f$
declare v_id uuid;
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  insert into public.listings
    (seller_id, event_name, venue, neighborhood, event_date, event_time,
     ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
     buy_now_price, duration_hours, ends_at, current_bid, cover_image_path)
  values (tap.seller(), p_name, 'Club X', 'wynwood', current_date + 7, '21:00',
          'GA', 1, 'mobile_transfer', 100, true, 100, 24, now() + interval '24 hours', 100, 'covers/194.jpg')
  returning id into v_id;
  return v_id;
end $f$;

CREATE FUNCTION tap._hold194(p_listing uuid, p_until timestamptz) RETURNS void LANGUAGE plpgsql AS $f$
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status = 'reserved', reserved_by = tap.buyer(), reserved_until = p_until
   where id = p_listing;
end $f$;

CREATE FUNCTION tap._pay194(p_listing uuid, p_status text, p_created timestamptz) RETURNS uuid LANGUAGE plpgsql AS $f$
declare v_id uuid;
begin
  -- seller_id is required for buy_now/auction by payments_rail_pairing_ck.
  insert into public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, mode, status, created_at)
  values (p_listing, tap.buyer(), tap.seller(), 100, 10, 110, 'buy_now', p_status, p_created)
  returning id into v_id;
  return v_id;
end $f$;

CREATE FUNCTION tap._paymode194(p_listing uuid, p_status text, p_mode text) RETURNS uuid LANGUAGE plpgsql AS $f$
declare v_id uuid;
begin
  insert into public.payments (listing_id, buyer_id, seller_id, amount, buyer_fee, total, mode, status)
  values (p_listing, tap.buyer(), tap.seller(), 100, 10, 110, p_mode, p_status)
  returning id into v_id;
  return v_id;
end $f$;

CREATE FUNCTION tap._state194(p_listing uuid) RETURNS text LANGUAGE sql AS
$f$ SELECT status || '/' || coalesce(reserved_by::text,'-') FROM public.listings WHERE id = p_listing $f$;

-- ── A. shape, grants, and the TTL coupling ──────────────────────────────────
SELECT has_function('public'::name, 'release_reservation_for_payment'::name,
  ARRAY['uuid','uuid','uuid']::name[], 'A1: public.release_reservation_for_payment(uuid,uuid,uuid) exists');
SELECT ok(has_function_privilege('service_role', 'public.release_reservation_for_payment(uuid,uuid,uuid)', 'EXECUTE'),
  'A2: service_role may EXECUTE it (the webhook path)');
SELECT ok(NOT has_function_privilege('authenticated', 'public.release_reservation_for_payment(uuid,uuid,uuid)', 'EXECUTE'),
  'A3: authenticated may NOT — a client never drives a payment-scoped release');
SELECT ok(NOT has_function_privilege('anon', 'public.release_reservation_for_payment(uuid,uuid,uuid)', 'EXECUTE'),
  'A4: anon may NOT');
-- `LIKE '%search_path=%'` passes for ANY value, including one that re-exposes a
-- mutable schema. Assert the value.
SELECT ok((SELECT p.prosecdef AND p.proconfig @> ARRAY['search_path=public'] AND (p.prorettype::regtype)::text = 'jsonb'
             FROM pg_proc p WHERE p.oid = 'public.release_reservation_for_payment(uuid,uuid,uuid)'::regprocedure),
  'A5: SECURITY DEFINER, search_path pinned to public, returns jsonb');
SELECT has_function('public'::name, 'release_reservation'::name, ARRAY['uuid','uuid']::name[],
  'A6: release_reservation keeps its signature');
-- 0590 removed the last coalesce(auth.uid(), p_user_id) fallbacks so a future
-- re-GRANT could not reopen that hole. An earlier revision of 127 rebuilt this
-- body from 000_baseline and silently reverted it; this pins it in both files.
SELECT ok(pg_get_functiondef('public.release_reservation(uuid,uuid)'::regprocedure) ~ 'request_is_service_role'
          AND pg_get_functiondef('public.release_reservation(uuid,uuid)'::regprocedure) !~* 'coalesce\s*\(\s*auth\.uid\(\)\s*,\s*p_user_id\s*\)',
  'A8: ...and keeps 0590''s strict identity resolution — no coalesce fallback');
SELECT ok(has_function_privilege('authenticated', 'public.release_reservation(uuid,uuid)', 'EXECUTE')
          AND NOT has_function_privilege('anon', 'public.release_reservation(uuid,uuid)', 'EXECUTE'),
  'A9: ...and its grants survive the replace (authenticated yes, anon no)');
SELECT ok(
  pg_get_functiondef('public.release_reservation_for_payment(uuid,uuid,uuid)'::regprocedure) ~ 'interval ''10 minutes'''
  -- Anchored: unanchored, `v_minutes := 100` matched and a 100-minute drift would
  -- have passed while the guard released holds up to 90 minutes newer than the payment.
  AND pg_get_functiondef('public.reserve_buy_now(uuid,uuid,integer)'::regprocedure) ~ 'v_minutes\s*:=\s*10\s*;',
  'A7: TTL COUPLING — 127''s staleness window matches reserve_buy_now''s 10-minute hold');

-- ── B. L2 on the client-facing release ──────────────────────────────────────
-- Control: an ordinary held listing with no succeeded payment is released.
SELECT tap._s194('l1', tap._mklisting194('194 control')::text);
SELECT tap._hold194(tap._f194('l1')::uuid, now() + interval '9 minutes');
SELECT public.release_reservation(tap._f194('l1')::uuid, tap.buyer());
SELECT is(tap._state194(tap._f194('l1')::uuid), 'active/-', 'B1: control — a plain hold is still released (no behaviour change)');

-- L2: the same call must no-op once the listing holds a succeeded payment.
SELECT tap._s194('l2', tap._mklisting194('194 paid')::text);
SELECT tap._hold194(tap._f194('l2')::uuid, now() + interval '9 minutes');
SELECT tap._pay194(tap._f194('l2')::uuid, 'succeeded', now());
SELECT public.release_reservation(tap._f194('l2')::uuid, tap.buyer());
SELECT is(tap._state194(tap._f194('l2')::uuid), 'reserved/' || tap.buyer()::text,
  'B2: L2 — a paid listing''s hold is NOT released (the sweeps'' N1 guard, now on the live path)');

-- Sold stays a no-op, unchanged from the baseline.
SELECT tap._s194('l3', tap._mklisting194('194 sold')::text);
SELECT tap._hold194(tap._f194('l3')::uuid, now() + interval '9 minutes');
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status = 'sold' WHERE id = tap._f194('l3')::uuid;
SELECT public.release_reservation(tap._f194('l3')::uuid, tap.buyer());
SELECT is((SELECT status FROM public.listings WHERE id = tap._f194('l3')::uuid), 'sold',
  'B3: a sold listing is untouched (unchanged)');

-- ── C. L1 on the payment-scoped release ─────────────────────────────────────
-- C1: the payment's OWN hold — taken before the payment — is released.
SELECT tap._s194('l4', tap._mklisting194('194 own hold')::text);
SELECT tap._hold194(tap._f194('l4')::uuid, now() + interval '9 minutes');
SELECT tap._s194('p4', tap._pay194(tap._f194('l4')::uuid, 'failed', now())::text);
SELECT is((public.release_reservation_for_payment(tap._f194('l4')::uuid, tap.buyer(), tap._f194('p4')::uuid) ->> 'released'), 'true',
  'C1: the payment''s own hold IS released');
SELECT is(tap._state194(tap._f194('l4')::uuid), 'active/-', 'C2: ...and the listing is back to active');

-- C3: THE L1 CASE — a hold taken AFTER the payment is refused. The payment is
-- backdated by more than the hold TTL, so its window cannot cover this hold.
SELECT tap._s194('l5', tap._mklisting194('194 newer hold')::text);
SELECT tap._hold194(tap._f194('l5')::uuid, now() + interval '9 minutes');
SELECT tap._s194('p5', tap._pay194(tap._f194('l5')::uuid, 'failed', now() - interval '45 minutes')::text);
SELECT is((public.release_reservation_for_payment(tap._f194('l5')::uuid, tap.buyer(), tap._f194('p5')::uuid) ->> 'reason'),
  'hold_newer_than_payment', 'C3: L1 — a hold taken after the payment is REFUSED (stale cancellation)');
SELECT is(tap._state194(tap._f194('l5')::uuid), 'reserved/' || tap.buyer()::text,
  'C4: ...and the live hold survives');

-- C5: a paid listing is refused here too.
SELECT tap._s194('l6', tap._mklisting194('194 paid scoped')::text);
SELECT tap._hold194(tap._f194('l6')::uuid, now() + interval '9 minutes');
SELECT tap._s194('p6', tap._pay194(tap._f194('l6')::uuid, 'failed', now())::text);
SELECT tap._pay194(tap._f194('l6')::uuid, 'succeeded', now());
SELECT is((public.release_reservation_for_payment(tap._f194('l6')::uuid, tap.buyer(), tap._f194('p6')::uuid) ->> 'reason'),
  'listing_has_succeeded_payment', 'C5: L2 applies on the payment-scoped path as well');

-- C6: a payment that is not this listing's cannot drive a release.
SELECT is((public.release_reservation_for_payment(tap._f194('l5')::uuid, tap.buyer(), tap._f194('p4')::uuid) ->> 'reason'),
  'payment_not_for_listing_buyer', 'C6: a payment bound to another listing is refused');

-- C7: an unknown payment id is refused, not treated as permission.
SELECT is((public.release_reservation_for_payment(tap._f194('l5')::uuid, tap.buyer(), gen_random_uuid()) ->> 'reason'),
  'unknown_payment', 'C7: an unknown payment is refused');

-- C8: a hold owned by someone else is refused.
SELECT tap._s194('l7', tap._mklisting194('194 other holder')::text);
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status='reserved', reserved_by = tap.other_user(), reserved_until = now() + interval '9 minutes'
 WHERE id = tap._f194('l7')::uuid;
SELECT tap._s194('p7', tap._pay194(tap._f194('l7')::uuid, 'failed', now())::text);
SELECT is((public.release_reservation_for_payment(tap._f194('l7')::uuid, tap.buyer(), tap._f194('p7')::uuid) ->> 'reason'),
  'not_held_by_buyer', 'C8: another buyer''s hold is refused');

-- C9: IDEMPOTENCE — replaying the same event finds nothing left to release.
SELECT is((public.release_reservation_for_payment(tap._f194('l4')::uuid, tap.buyer(), tap._f194('p4')::uuid) ->> 'reason'),
  'not_held_by_buyer', 'C9: replaying the same webhook event is a no-op, for the stated reason');
SELECT is(tap._state194(tap._f194('l4')::uuid), 'active/-', 'C10: ...and the listing is unchanged by the replay');

-- ── F. THE REAL L1 TIMELINE (the case the first draft of 127 did not close) ──
-- Built with the actual producer of holds, reserve_buy_now, not a hand-written
-- reserved_until: the holder re-reserving a live hold KEEPS the existing window,
-- so a retired attempt and the live one sit under ONE hold and no timestamp can
-- tell them apart. An earlier draft released the live hold here.
-- The listing is created with no request context (119's ALLOW 2), then the hold
-- is taken as the buyer, because reserve_buy_now requires an identified caller.
SELECT tap.logout();
SELECT tap._s194('l8', tap._mklisting194('194 real timeline')::text);
SELECT tap.login(tap.buyer());
SELECT public.reserve_buy_now(tap._f194('l8')::uuid, tap.buyer(), 10);
SELECT tap.logout();
SELECT tap._s194('ru8', (SELECT reserved_until::text FROM public.listings WHERE id = tap._f194('l8')::uuid));
-- P1 is the attempt create-payment-intent retired to 'failed'; P2 is the live one
-- it minted in the same invocation. Both created under the same unchanged hold.
SELECT tap._s194('p8a', tap._pay194(tap._f194('l8')::uuid, 'failed',  now())::text);
SELECT tap._s194('p8b', tap._pay194(tap._f194('l8')::uuid, 'pending', now())::text);
SELECT is((public.release_reservation_for_payment(tap._f194('l8')::uuid, tap.buyer(), tap._f194('p8a')::uuid) ->> 'released'), 'false',
  'F1: the late canceled event for the RETIRED attempt does NOT free the hold the live attempt is using');
SELECT is((public.release_reservation_for_payment(tap._f194('l8')::uuid, tap.buyer(), tap._f194('p8a')::uuid) ->> 'reason'),
  'live_sibling_attempt', 'F2: ...refused because a sibling attempt is still in flight, not on timestamps');
SELECT is(tap._state194(tap._f194('l8')::uuid), 'reserved/' || tap.buyer()::text, 'F3: ...the live hold survives');

-- Pins the premise the timestamp half depends on: re-reserving a live hold does
-- NOT move the window. If reserve_buy_now ever starts extending, this fails here
-- rather than the guard going quietly wrong.
-- F4 was VACUOUS and is replaced. It re-reserved and compared reserved_until,
-- but now() is frozen for the transaction and reserve_buy_now recomputes
-- now() + 10 minutes, so the value is bit-identical whether or not the early
-- RETURN exists -- removing that branch still passed. The invariant is not
-- observable from the value, so assert the branch itself.
SELECT ok(pg_get_functiondef('public.reserve_buy_now(uuid,uuid,integer)'::regprocedure)
            ~* 'v_reserved_by\s*=\s*v_caller_id\s+AND\s+v_reserved_until\s*>\s*now\(\)\s*THEN\s*RETURN',
  'F4: INVARIANT — reserve_buy_now still RETURNS EARLY on the holder''s own live hold, so a re-reserve cannot move the window');

-- An auction payment must never drive a Buy Now hold release: auctions take no
-- reservation, so the hold window means nothing for them.
SELECT tap._s194('p8c', tap._paymode194(tap._f194('l8')::uuid, 'failed', 'auction')::text);
SELECT is((public.release_reservation_for_payment(tap._f194('l8')::uuid, tap.buyer(), tap._f194('p8c')::uuid) ->> 'reason'),
  'payment_not_buy_now', 'F5: an auction-mode payment is refused outright');

-- A reserved row with no window: refuse, and say why accurately.
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET reserved_until = NULL WHERE id = tap._f194('l8')::uuid;
DELETE FROM public.payments WHERE id = tap._f194('p8b')::uuid;  -- clear the live sibling first
SELECT is((public.release_reservation_for_payment(tap._f194('l8')::uuid, tap.buyer(), tap._f194('p8a')::uuid) ->> 'reason'),
  'hold_window_unknown', 'F6: a reserved row with no window is refused with its own reason, not blamed on timestamps');

-- Earns F2: with the sibling removed the SAME call releases, so F2's refusal is
-- attributable to the sibling check and not to the timestamp test shadowing it.
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status='reserved', reserved_by = tap.buyer(), reserved_until = tap._f194('ru8')::timestamptz
 WHERE id = tap._f194('l8')::uuid;
SELECT is((public.release_reservation_for_payment(tap._f194('l8')::uuid, tap.buyer(), tap._f194('p8a')::uuid) ->> 'released'), 'true',
  'F7: with no live sibling the same call DOES release — F2''s refusal was the sibling check, not timestamps');

-- D5: a listing can be both auction and buy-now enabled. An auction attempt
-- holds no reservation, so it must not count as a sibling.
SELECT set_config('app.bypass_listing_guard', 'on', true);
UPDATE public.listings SET status='reserved', reserved_by = tap.buyer(), reserved_until = tap._f194('ru8')::timestamptz
 WHERE id = tap._f194('l8')::uuid;
SELECT tap._s194('p8e', tap._paymode194(tap._f194('l8')::uuid, 'pending', 'auction')::text);
SELECT is((public.release_reservation_for_payment(tap._f194('l8')::uuid, tap.buyer(), tap._f194('p8a')::uuid) ->> 'released'), 'true',
  'F8: a pending AUCTION payment is not a sibling — it never needed the hold');

SELECT * FROM finish();
ROLLBACK;
