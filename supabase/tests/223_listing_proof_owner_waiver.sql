-- ============================================================================
-- 223_listing_proof_owner_waiver.sql — migration 156 (20261015000200).
-- An explicit, recorded owner proof waiver: only an admin listing their own inventory, with no proof
-- path and a reason, at creation. The server stamps the time. A waived listing stays pending_review
-- (never approved / verified). Untrusted callers can never add, change or clear a waiver afterwards.
--   A. wiring: three columns, the all-or-nothing check, the trigger, privileges.
--   B. the admin's own waived listing: accepted; waived_at is the server's now(), not the client's.
--   C. refusals: non-admin; admin with a proof path; admin as someone else; waived_by not the caller;
--      blank reason; partial fields.
--   D. after creation: no untrusted change of any waiver field (owner or not); other edits pass;
--      proof_status cannot be set to approved by a client (existing guard).
--   E. trusted path: service_role may record a waiver (operator backfill).
--   F. current_user_is_admin(): the caller's own boolean only; anon cannot call it.
-- ADDENDUM 3 and the review fixes (2026-10-15):
--   G. client_shows_proof_disclosure(): true only when the x-snatchit-caps request header carries the token
--      proof-disclosure-v1 (space or comma separated); NULL, empty, unparseable or token-less -> false; no
--      client can call it.
--   H. a bid on a waived listing needs that header: without it the old-build refusal (HINT
--      LISTING_UNAVAILABLE); with it the bid is placed; a non-waived listing is unaffected; claims-less
--      postgres and service_role bypass; a postgres session WITH request claims is not trusted.
--   I. a NEW Buy Now hold on a waived listing (reserve_buy_now is SECURITY DEFINER, so the trust test
--      reads the request, not current_user) needs the header: the same message with NO hint, never
--      'sold' or 'already reserved'; releasing a hold, a non-waived listing and the trusted paths are
--      unaffected; handing a held waived listing to another buyer is refused too.
--   J. ADDENDUM 3b: an untrusted create with no waiver needs a proof path ('Upload proof of ownership.').
--   K. no caller, service_role and postgres included, can approve a waived listing (CHECK).
--   L. an untrusted update cannot put a proof path on a waived listing (the waiver stays clean).
-- Helpers are version-agnostic (dynamic SQL, errors caught), so the file runs to completion on a
-- database that lacks any of these objects and reports each gap as its own failure.
-- ============================================================================
BEGIN;
SELECT plan(84);
SELECT tap.seed_core();

CREATE FUNCTION tap._try223(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg);
END $f$;
-- Same, plus the HINT (JSON null when the error carries none): the old builds key their copy on it.
CREATE FUNCTION tap._tryh223(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text; v_hint text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_hint = PG_EXCEPTION_HINT;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg, 'hint', nullif(v_hint, ''));
END $f$;
-- The request header PostgREST exposes as request.headers (lower-cased names, JSON object). NULL = no
-- x-snatchit-caps header at all (an old build); the raw form sets the whole GUC text, garbage included.
CREATE FUNCTION tap._caps223(p_caps text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  PERFORM set_config('request.headers',
                     CASE WHEN p_caps IS NULL THEN '{"accept": "*/*"}' ELSE json_build_object('accept', '*/*', 'x-snatchit-caps', p_caps)::text END,
                     true);
END $f$;
-- client_shows_proof_disclosure() under a given raw request.headers text, as the CURRENT role.
CREATE FUNCTION tap._shows223(p_raw text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text; v_state text;
BEGIN
  PERFORM set_config('request.headers', p_raw, true);
  EXECUTE 'SELECT public.client_shows_proof_disclosure()::text' INTO v;
  RETURN v;
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  RETURN 'ERROR:' || v_state;
END $f$;
CREATE FUNCTION tap._dml223(p_sql text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v bigint;
BEGIN
  EXECUTE format('WITH x AS (%s) SELECT count(*) FROM x', p_sql) INTO v;
  RETURN v;
END $f$;
-- First column of a one-row statement run as the CURRENT role, as text; 'ERROR:<sqlstate>' on failure.
CREATE FUNCTION tap._val223(p_sql text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text; v_state text;
BEGIN
  EXECUTE p_sql INTO v;
  RETURN v;
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  RETURN 'ERROR:' || v_state;
END $f$;
-- The client create shape plus the three waiver fields and the proof path (web /sell sends these).
CREATE FUNCTION tap._create223(p_tag text, p_seller uuid, p_waived_by uuid, p_reason text,
                               p_proof text DEFAULT NULL, p_waived_at timestamptz DEFAULT NULL,
                               p_buy_now boolean DEFAULT false) RETURNS text LANGUAGE sql AS $f$
  SELECT format($i$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
        transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, ends_at, current_bid, cover_image_path,
        proof_of_ownership_path, proof_waived_by, proof_waiver_reason, proof_waived_at)
     VALUES (%L, %L, 'Club 223', 'wynwood', current_date + 7, '21:00', 'GA', 2,
             'mobile_transfer', 60, %L, %L, 24, now() + interval '24 hours', 60, 'covers/223.jpg',
             %L, %L, %L, %L) $i$,
     p_seller, 'Fixture 223 ' || p_tag, p_buy_now, CASE WHEN p_buy_now THEN 200 END,
     p_proof, p_waived_by, p_reason, p_waived_at) $f$;
CREATE FUNCTION tap._id223(p_tag text) RETURNS uuid LANGUAGE sql AS $f$
  SELECT id FROM public.listings WHERE event_name = 'Fixture 223 ' || p_tag $f$;
CREATE FUNCTION tap._bid223(p_tag text, p_bidder uuid, p_amount int) RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (%L, %L, %s)', tap._id223(p_tag), p_bidder, p_amount) $f$;
CREATE FUNCTION tap._reserve223(p_tag text, p_user uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT public.reserve_buy_now(%L, %L, 10)', tap._id223(p_tag), p_user) $f$;
-- The shape of any future definer RPC that hands a held listing to another buyer (opts into the listing
-- guard bypass like the auction RPCs). Defence in depth for I13; no shipped RPC does this today.
CREATE FUNCTION tap._definer_rehold223(p_id uuid, p_to uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $f$
BEGIN
  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings SET reserved_by = p_to, reserved_until = now() + interval '10 minutes' WHERE id = p_id;
END $f$;
GRANT EXECUTE ON FUNCTION tap._definer_rehold223(uuid, uuid) TO authenticated;
CREATE FUNCTION tap._disclosure_msg223() RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT 'This listing needs the latest Snatch It app. Update the app or use app.snatchitapp.com.'::text $f$;
CREATE FUNCTION tap._bid_refusal223() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT jsonb_build_object('ok', false, 'code', 'P0001', 'message', tap._disclosure_msg223(), 'hint', 'LISTING_UNAVAILABLE') $f$;
CREATE FUNCTION tap._hold_refusal223() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT jsonb_build_object('ok', false, 'code', 'P0001', 'message', tap._disclosure_msg223(), 'hint', NULL) $f$;
CREATE FUNCTION tap._proof_msg223() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT '{"ok": false, "code": "P0001", "message": "Upload proof of ownership."}'::jsonb $f$;
CREATE FUNCTION tap._waiver_msg223() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT '{"ok": false, "code": "P0001", "message": "Only an admin listing its own inventory can record an owner proof waiver."}'::jsonb $f$;
CREATE FUNCTION tap._frozen_msg223() RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT '{"ok": false, "code": "P0001", "message": "An owner proof waiver is recorded only when the listing is created."}'::jsonb $f$;

-- The admin is an onboarded, phone-verified seller (the listing INSERT policy's prerequisites).
UPDATE public.profiles SET stripe_onboarding_complete = true WHERE id = tap.admin_user();
UPDATE auth.users SET phone = '+13055550044', phone_confirmed_at = now() WHERE id = tap.admin_user();

-- ── A. wiring ───────────────────────────────────────────────────────────────
SELECT is((SELECT string_agg(column_name || ':' || data_type || ':' || is_nullable, ' ' ORDER BY column_name)
             FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'listings'
              AND column_name IN ('proof_waived_at', 'proof_waived_by', 'proof_waiver_reason')),
  'proof_waived_at:timestamp with time zone:YES proof_waived_by:uuid:YES proof_waiver_reason:text:YES',
  'A1: listings has the three nullable waiver columns');
SELECT ok((SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.listings'::regclass AND contype = 'c'
            AND pg_get_constraintdef(oid) ~ 'proof_waived_at IS NULL' AND pg_get_constraintdef(oid) ~ 'proof_waived_at IS NOT NULL') = 1,
  'A2: one CHECK makes the three fields all-null or all-set');
SELECT is((SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_proof_waiver'),
  'CREATE TRIGGER trg_guard_listing_proof_waiver BEFORE INSERT OR UPDATE ON public.listings FOR EACH ROW EXECUTE FUNCTION guard_listing_proof_waiver()',
  'A3: trg_guard_listing_proof_waiver is BEFORE INSERT OR UPDATE FOR EACH ROW');
SELECT is((SELECT p.prosecdef::text || ':' || coalesce(array_to_string(p.proconfig, ','), '-') || ':' ||
                  has_function_privilege('anon', p.oid, 'EXECUTE')::text || ',' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.guard_listing_proof_waiver()')),
  'true:search_path="":false,false', 'A4: the guard is SECURITY DEFINER, empty search_path, not client-executable');
SELECT is((SELECT string_agg(conname || ':' || convalidated::text, ' ') FROM pg_constraint
            WHERE conrelid = 'public.listings'::regclass AND contype = 'c' AND conname = 'listings_proof_waiver_never_approved'),
  'listings_proof_waiver_never_approved:true', 'A5: the validated CHECK listings_proof_waiver_never_approved exists');
SELECT is((SELECT string_agg(pg_get_triggerdef(t.oid), ' | ' ORDER BY t.tgname) FROM pg_trigger t
            WHERE NOT t.tgisinternal AND t.tgname IN ('trg_bid_requires_disclosure', 'trg_reservation_requires_disclosure')),
  'CREATE TRIGGER trg_bid_requires_disclosure BEFORE INSERT ON public.bids FOR EACH ROW EXECUTE FUNCTION guard_bid_requires_disclosure()'
  || ' | CREATE TRIGGER trg_reservation_requires_disclosure BEFORE UPDATE OF reserved_by ON public.listings FOR EACH ROW EXECUTE FUNCTION guard_reservation_requires_disclosure()',
  'A6: trg_bid_requires_disclosure is BEFORE INSERT on bids; trg_reservation_requires_disclosure is BEFORE UPDATE OF reserved_by on listings');
SELECT is((SELECT string_agg(f || '=' || CASE WHEN to_regprocedure(f) IS NULL THEN 'absent' ELSE
              (SELECT p.prosecdef::text || ':' || p.provolatile::text || ':' || coalesce(array_to_string(p.proconfig, ','), '-') FROM pg_proc p WHERE p.oid = to_regprocedure(f))
              || ':' || has_function_privilege('anon', to_regprocedure(f), 'EXECUTE')::text
              || ',' || has_function_privilege('authenticated', to_regprocedure(f), 'EXECUTE')::text END, ' ' ORDER BY f)
             FROM unnest(ARRAY['public.client_shows_proof_disclosure()', 'public.guard_bid_requires_disclosure()',
                               'public.guard_reservation_requires_disclosure()']) f),
  'public.client_shows_proof_disclosure()=false:s:search_path="":false,false'
  || ' public.guard_bid_requires_disclosure()=true:v:search_path="":false,false'
  || ' public.guard_reservation_requires_disclosure()=true:v:search_path="":false,false',
  'A7: the header reader is STABLE invoker and the two trigger functions SECURITY DEFINER; empty search_path; none client-executable');

-- ── B. the admin's own waived listing ───────────────────────────────────────
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223(tap._create223('ADMIN-OK', tap.admin_user(), tap.admin_user(), 'Owner inventory; tickets held by Snatch It', NULL, '2000-01-01T00:00:00Z')),
  '{"ok": true}'::jsonb, 'B1: an admin seller with no proof path and a reason records a waiver');
SELECT is(tap._val223($$SELECT (proof_waived_at = now())::text || '|' || proof_waived_by::text || '|' || proof_waiver_reason || '|' || proof_status
             FROM public.listings WHERE event_name = 'Fixture 223 ADMIN-OK'$$),
  'true|' || tap.admin_user()::text || '|Owner inventory; tickets held by Snatch It|pending_review',
  'B2: waived_at is the server''s now() (the client sent 2000-01-01), waived_by and reason kept, proof_status stays pending_review');
SELECT is(tap._val223($$SELECT count(*) FROM public.listings WHERE event_name = 'Fixture 223 ADMIN-OK' AND proof_waived_at = '2000-01-01T00:00:00Z'$$), '0',
  'B3: the client-supplied waived_at was overridden, not stored');

-- ── C. refusals at creation ─────────────────────────────────────────────────
SELECT tap.login(tap.seller());
SELECT is(tap._try223(tap._create223('NONADMIN', tap.seller(), tap.seller(), 'I own these')), tap._waiver_msg223(),
  'C1: a non-admin seller cannot record a waiver on their own listing');
SELECT is(tap._try223(tap._create223('PLAIN', tap.seller(), NULL, NULL, 'proofs/223-plain.png')), '{"ok": true}'::jsonb,
  'C2: the same seller''s ordinary listing (no waiver fields, a proof path as every client sends) is unaffected');
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223(tap._create223('PROOF', tap.admin_user(), tap.admin_user(), 'Has proof too', 'proofs/223.png')), tap._waiver_msg223(),
  'C3: an admin who supplies a proof path cannot also record a waiver');
SELECT is(tap._try223(tap._create223('ASOTHER', tap.seller(), tap.admin_user(), 'For the seller')), tap._waiver_msg223(),
  'C4: an admin cannot create a waived listing as someone else');
SELECT is(tap._try223(tap._create223('BYOTHER', tap.admin_user(), tap.seller(), 'Attributed to the seller')), tap._waiver_msg223(),
  'C5: waived_by must be the caller');
SELECT is(tap._try223(tap._create223('BLANK', tap.admin_user(), tap.admin_user(), '   ')), tap._waiver_msg223(),
  'C6: a blank reason is refused');
SELECT is(tap._try223(tap._create223('NOREASON', tap.admin_user(), tap.admin_user(), NULL)), tap._waiver_msg223(),
  'C7: a waiver without a reason is refused');
SELECT is(tap._try223(tap._create223('ATONLY', tap.admin_user(), NULL, NULL, NULL, now())), tap._waiver_msg223(),
  'C8: a client-sent waived_at alone is refused (no partial waiver)');
SELECT tap.login_anon();
SELECT is(tap._try223(tap._create223('ANON', tap.admin_user(), tap.admin_user(), 'anon')) ->> 'code', '42501',
  'C9: anon cannot create a listing at all');

-- ── D. after creation: waiver fields are frozen for clients ─────────────────
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223($$UPDATE public.listings SET proof_waiver_reason = 'Changed later' WHERE event_name = 'Fixture 223 ADMIN-OK'$$), tap._frozen_msg223(),
  'D1: the admin cannot rewrite their waiver reason afterwards');
SELECT is(tap._try223($$UPDATE public.listings SET proof_waived_at = NULL, proof_waived_by = NULL, proof_waiver_reason = NULL WHERE event_name = 'Fixture 223 ADMIN-OK'$$), tap._frozen_msg223(),
  'D2: the admin cannot clear a recorded waiver');
SELECT is(tap._dml223($$UPDATE public.listings SET restrictions = '21+' WHERE event_name = 'Fixture 223 ADMIN-OK' RETURNING id$$), 1::bigint,
  'D3: other edits of a waived listing pass (waiver fields untouched)');
SELECT is(tap._try223($$UPDATE public.listings SET proof_status = 'approved' WHERE event_name = 'Fixture 223 ADMIN-OK'$$) ->> 'message',
  'proof_status can only be changed by Snatch It review',
  'D4: a client cannot mark a waived listing approved (guard_proof_status)');
SELECT tap.login(tap.seller());
SELECT is(tap._try223(format($$UPDATE public.listings SET proof_waived_by = %L, proof_waiver_reason = 'later', proof_waived_at = now() WHERE event_name = 'Fixture 223 PLAIN'$$, tap.seller())),
  tap._frozen_msg223(), 'D5: a seller cannot add a waiver to an existing listing');
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223(format($$UPDATE public.listings SET proof_waived_by = %L, proof_waiver_reason = 'later', proof_waived_at = now() WHERE id = %L$$, tap.admin_user(), tap.listing_a())),
  '{"ok": true}'::jsonb, 'D6: an admin UPDATE on another seller''s listing matches no row (RLS) — nothing to waive');
SELECT is(tap._val223(format('SELECT count(*) FROM public.listings WHERE id = %L AND proof_waived_at IS NOT NULL', tap.listing_a())), '0',
  'D7: and the other seller''s listing carries no waiver');
SELECT tap.logout();
SELECT is((SELECT proof_status FROM public.listings WHERE event_name = 'Fixture 223 ADMIN-OK'), 'pending_review',
  'D8: after every attempt the waived listing is still pending_review, never approved');

-- ── E. trusted path ─────────────────────────────────────────────────────────
SELECT tap.login_service();
SELECT is(tap._try223(format($$UPDATE public.listings SET proof_waived_by = %L, proof_waiver_reason = 'Operator backfill', proof_waived_at = now() WHERE id = %L$$, tap.admin_user(), tap.listing_c())),
  '{"ok": true}'::jsonb, 'E1: service_role can record a waiver (operator backfill)');
SELECT is(tap._try223(format($$UPDATE public.listings SET proof_waived_at = NULL WHERE id = %L$$, tap.listing_c())) ->> 'code', '23514',
  'E2: even the trusted path cannot leave a partial waiver (the all-or-nothing check)');
SELECT tap.logout();

-- ── F. current_user_is_admin() ──────────────────────────────────────────────
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223('SELECT public.current_user_is_admin()'), '{"ok": true}'::jsonb, 'F1: an authenticated caller can call current_user_is_admin()');
SELECT is(tap._val223('SELECT public.current_user_is_admin()'), 'true', 'F2: it is true for an admin_users member');
SELECT tap.login(tap.seller());
SELECT is(tap._val223('SELECT public.current_user_is_admin()'), 'false', 'F3: it is false for a non-admin');
SELECT tap.login_anon();
SELECT is(tap._try223('SELECT public.current_user_is_admin()') ->> 'code', '42501', 'F4: anon is denied EXECUTE');
SELECT tap.logout();
SELECT is((SELECT has_function_privilege('anon', p.oid, 'EXECUTE')::text || ',' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
                  || ',' || p.prosecdef::text || ',' || p.provolatile::text || ',' || coalesce(array_to_string(p.proconfig, ','), '-')
             FROM pg_proc p WHERE p.oid = to_regprocedure('public.current_user_is_admin()')),
  'false,true,true,s,search_path=""', 'F5: authenticated-only, SECURITY DEFINER, STABLE, empty search_path');

-- ── G. client_shows_proof_disclosure() (as postgres: it is not client-executable) ──
-- G1 runs before anything in this transaction sets request.headers: the setting does not exist yet.
SELECT is(tap._val223('SELECT public.client_shows_proof_disclosure()::text'), 'false', 'G1: no request.headers at all -> false');
SELECT is(tap._shows223(''), 'false', 'G2: an empty request.headers -> false');
SELECT is(tap._shows223('proof-disclosure-v1 {not json'), 'false', 'G3: unparseable request.headers -> false (no error)');
SELECT is(tap._shows223('{"accept": "*/*"}'), 'false', 'G4: headers without x-snatchit-caps -> false');
SELECT is(tap._shows223('{"x-snatchit-caps": "proof-disclosure-v1"}'), 'true', 'G5: the token alone -> true');
SELECT is(tap._shows223('{"x-snatchit-caps": "other-cap proof-disclosure-v1"}'), 'true', 'G6: space-separated tokens -> true');
SELECT is(tap._shows223('{"x-snatchit-caps": "other-cap,proof-disclosure-v1"}'), 'true', 'G7: comma-separated tokens -> true');
SELECT is(tap._shows223('{"x-snatchit-caps": " other-cap ,  proof-disclosure-v1 , third "}'), 'true', 'G8: mixed separators and padding -> true');
SELECT is(tap._shows223('{"x-snatchit-caps": "proof-disclosure-v10 xproof-disclosure-v1 proof-disclosure-v1x"}'), 'false',
  'G9: a token is matched whole, never as a substring -> false');
SELECT is(tap._shows223('{"x-snatchit-caps": ["proof-disclosure-v1"]}'), 'false', 'G10: a non-string header value -> false');
SELECT is(tap._shows223('["proof-disclosure-v1"]'), 'false', 'G11: headers that are not a JSON object -> false');
SELECT tap.login(tap.buyer());
SELECT is(tap._try223('SELECT public.client_shows_proof_disclosure()') ->> 'code', '42501', 'G12: an authenticated client cannot call it (EXECUTE revoked)');
SELECT tap.login_anon();
SELECT is(tap._try223('SELECT public.client_shows_proof_disclosure()') ->> 'code', '42501', 'G13: anon cannot call it either');
SELECT tap.logout();

-- ── H. bids on a waived listing need the disclosure header ──────────────────
-- ADMIN-OK (B1) is the admin's live, waived auction; PLAIN (C2) the seller's live, non-waived one.
SELECT tap.login(tap.buyer());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._bid223('ADMIN-OK', tap.buyer(), 70)), tap._bid_refusal223(),
  'H1: an old build (no header) cannot bid on a waived listing: the update message with HINT LISTING_UNAVAILABLE');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.bids WHERE listing_id = tap._id223('ADMIN-OK')), 0, 'H2: the refused bid wrote nothing');
SELECT tap.login(tap.buyer());
SELECT tap._caps223('proof-disclosure-v1');
SELECT is(tap._tryh223(tap._bid223('ADMIN-OK', tap.buyer(), 70)), '{"ok": true}'::jsonb,
  'H3: the same bid with x-snatchit-caps: proof-disclosure-v1 is placed');
SELECT tap.login(tap.other_user());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._bid223('PLAIN', tap.other_user(), 70)), '{"ok": true}'::jsonb,
  'H4: an old build still bids on a listing without a waiver');
SELECT tap._caps223('other-cap');
SELECT is(tap._tryh223(tap._bid223('ADMIN-OK', tap.other_user(), 80)), tap._bid_refusal223(),
  'H5: a header without the token is refused like no header');
SELECT tap.logout();
SELECT tap.set_claims(tap.other_user());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._bid223('ADMIN-OK', tap.other_user(), 80)), tap._bid_refusal223(),
  'H6: a postgres session that carries request claims is not trusted (claims decide, not current_user)');
SELECT tap.logout();
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._bid223('ADMIN-OK', tap.other_user(), 80)), '{"ok": true}'::jsonb,
  'H7: claims-less postgres (migrations, cron, SQL editor) bypasses the header rule');
SELECT tap.login_service();
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._bid223('ADMIN-OK', tap.seller(), 90)), '{"ok": true}'::jsonb,
  'H8: service_role bypasses the header rule');
SELECT tap.logout();
SELECT is((SELECT string_agg(amount::text, ',' ORDER BY amount) FROM public.bids WHERE listing_id = tap._id223('ADMIN-OK')), '70,80,90',
  'H9: exactly the three allowed bids were written (H3, H7, H8)');

-- ── I. a new Buy Now hold on a waived listing needs the header ──────────────
SELECT tap.login(tap.admin_user());
SELECT tap._caps223(NULL);
SELECT is(tap._try223(tap._create223('BN1', tap.admin_user(), tap.admin_user(), 'Owner inventory, Buy Now', NULL, NULL, true))
       || tap._try223(tap._create223('BN2', tap.admin_user(), tap.admin_user(), 'Owner inventory, Buy Now', NULL, NULL, true))
       || tap._try223(tap._create223('BN3', tap.admin_user(), tap.admin_user(), 'Owner inventory, Buy Now', NULL, NULL, true)),
  '{"ok": true}'::jsonb, 'I0: the admin lists three waived Buy Now listings (creating needs no header)');
SELECT tap.login(tap.seller());
SELECT is(tap._try223(tap._create223('PLAIN-BN', tap.seller(), NULL, NULL, 'proofs/223-plainbn.png', NULL, true)), '{"ok": true}'::jsonb,
  'I0b: the seller lists a non-waived Buy Now listing');
SELECT tap.login(tap.buyer());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._reserve223('BN1', tap.buyer())), tap._hold_refusal223(),
  'I1: an old build (no header) cannot reserve a waived listing: the same message, NO hint');
SELECT ok((tap._tryh223(tap._reserve223('BN1', tap.buyer())) ->> 'message') !~* '(sold|already reserved)',
  'I2: the refusal never says "sold" or "already reserved" (old builds show "Reservation failed — <message>")');
SELECT tap.logout();
SELECT is((SELECT status || '|' || coalesce(reserved_by::text, 'null') FROM public.listings WHERE id = tap._id223('BN1')), 'active|null',
  'I3: the refused reservation left the listing active and unheld');
SELECT tap.set_claims(tap.buyer());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._reserve223('BN1', tap.buyer())), tap._hold_refusal223(),
  'I4: inside reserve_buy_now (SECURITY DEFINER) a session with request claims is not trusted, even though current_user is the owner');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT tap._caps223('proof-disclosure-v2');
SELECT is(tap._tryh223(tap._reserve223('BN1', tap.buyer())), tap._hold_refusal223(), 'I5: a header without the token is refused');
SELECT tap._caps223('other-cap,proof-disclosure-v1');
SELECT is(tap._tryh223(tap._reserve223('BN1', tap.buyer())), '{"ok": true}'::jsonb, 'I6: with the token the reservation is taken');
SELECT tap.logout();
SELECT is((SELECT status || '|' || reserved_by::text FROM public.listings WHERE id = tap._id223('BN1')), 'reserved|' || tap.buyer()::text,
  'I7: the buyer holds BN1');
SELECT tap.login(tap.other_user());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(format('SELECT tap._definer_rehold223(%L, %L)', tap._id223('BN1'), tap.other_user())), tap._hold_refusal223(),
  'I13: handing a held waived listing to another buyer without the header is refused too (a new holder, not only a first one)');
SELECT tap.login(tap.buyer());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(format('SELECT public.release_reservation(%L, %L)', tap._id223('BN1'), tap.buyer())), '{"ok": true}'::jsonb,
  'I8: releasing a hold needs no header (only a new holder is checked)');
SELECT tap.logout();
SELECT is((SELECT status || '|' || coalesce(reserved_by::text, 'null') FROM public.listings WHERE id = tap._id223('BN1')), 'active|null',
  'I8b: and the hold is gone');
SELECT tap.login(tap.other_user());
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._reserve223('PLAIN-BN', tap.other_user())), '{"ok": true}'::jsonb,
  'I9: an old build still reserves a listing without a waiver');
SELECT tap.logout();
SELECT tap._caps223(NULL);
-- (reserve_buy_now cannot name a caller here: request_is_service_role() needs claims that were never set, and
-- tap.logout() leaves them ''. The trusted shape is the operator / settlement write: postgres, guard bypass on.)
SELECT set_config('app.bypass_listing_guard', 'on', true);
SELECT is(tap._tryh223(format($u$UPDATE public.listings SET status = 'reserved', reserved_by = %L, reserved_until = now() + interval '10 minutes'
                                 WHERE id = %L$u$, tap.other_user(), tap._id223('BN2'))), '{"ok": true}'::jsonb,
  'I10: claims-less postgres (an operator or settlement write) bypasses the header rule');
SELECT tap.reset_guards();
SELECT tap.login_service();
SELECT tap._caps223(NULL);
SELECT is(tap._tryh223(tap._reserve223('BN3', tap.buyer())), '{"ok": true}'::jsonb, 'I11: service_role bypasses the header rule');
SELECT tap.logout();
SELECT is((SELECT string_agg(event_name || ':' || coalesce(reserved_by::text, 'null'), ' ' ORDER BY event_name) FROM public.listings
            WHERE event_name IN ('Fixture 223 BN2', 'Fixture 223 BN3')),
  'Fixture 223 BN2:' || tap.other_user()::text || ' Fixture 223 BN3:' || tap.buyer()::text, 'I12: the two trusted reservations were taken');

-- ── J. ADDENDUM 3b: proof stays required for an ordinary listing ────────────
SELECT tap.login(tap.seller());
SELECT is(tap._try223(tap._create223('NOPROOF', tap.seller(), NULL, NULL)), tap._proof_msg223(),
  'J1: an untrusted create with no waiver and no proof path is refused');
SELECT is(tap._try223(tap._create223('BLANKPROOF', tap.seller(), NULL, NULL, '   ')), tap._proof_msg223(),
  'J2: a blank proof path is no proof');
SELECT is(tap._try223(tap._create223('WITHPROOF', tap.seller(), NULL, NULL, 'proofs/223-j3.png')), '{"ok": true}'::jsonb,
  'J3: with a proof path the same create passes');
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223(tap._create223('ADMINNOPROOF', tap.admin_user(), NULL, NULL)), tap._proof_msg223(),
  'J4: an admin without a recorded waiver needs a proof path too (B1 is the waived exception)');
SELECT tap.login_service();
SELECT is(tap._try223(tap._create223('SVCNOPROOF', tap.seller(), NULL, NULL)), '{"ok": true}'::jsonb,
  'J5: the trusted path (service_role) may create without a proof path (operator)');
SELECT tap.logout();

-- ── K. a waived listing can never be approved, by any caller ────────────────
SELECT tap.login_service();
SELECT is(tap._try223($$UPDATE public.listings SET proof_status = 'approved' WHERE event_name = 'Fixture 223 ADMIN-OK'$$) ->> 'code', '23514',
  'K1: service_role cannot approve a waived listing (check violation)');
SELECT is(tap._try223($$UPDATE public.listings SET proof_status = 'approved' WHERE event_name = 'Fixture 223 PLAIN'$$), '{"ok": true}'::jsonb,
  'K2: control: service_role can approve a listing without a waiver');
SELECT tap.logout();
SELECT is(tap._try223($$UPDATE public.listings SET proof_status = 'approved' WHERE event_name = 'Fixture 223 BN2'$$) ->> 'code', '23514',
  'K3: claims-less postgres cannot approve a waived listing either');
SELECT is(tap._try223(format($i$INSERT INTO public.listings (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type,
       quantity, transfer_method, starting_bid, buy_now_enabled, duration_hours, ends_at, current_bid, cover_image_path, proof_status,
       proof_waived_at, proof_waived_by, proof_waiver_reason)
     VALUES (%L, 'Fixture 223 K4', 'Club 223', 'wynwood', current_date + 7, '21:00', 'GA', 1, 'mobile_transfer', 60, false, 24,
             now() + interval '24 hours', 60, 'covers/223k.jpg', 'approved', now(), %L, 'Trusted insert')$i$, tap.admin_user(), tap.admin_user())) ->> 'code',
  '23514', 'K4: a trusted insert of a waived listing that is already approved is refused');

-- ── L. the waiver stays clean: no proof path added later by a client ────────
SELECT tap.login(tap.admin_user());
SELECT is(tap._try223($$UPDATE public.listings SET proof_of_ownership_path = 'proofs/223-later.png' WHERE event_name = 'Fixture 223 ADMIN-OK'$$),
  '{"ok": false, "code": "P0001", "message": "A listing with an owner proof waiver cannot take a proof of ownership."}'::jsonb,
  'L1: the admin cannot add a proof path to their waived listing');
SELECT tap.login(tap.seller());
SELECT is(tap._dml223($$UPDATE public.listings SET proof_of_ownership_path = 'proofs/223-replaced.png' WHERE event_name = 'Fixture 223 PLAIN' RETURNING id$$),
  1::bigint, 'L2: control: a seller can still replace the proof path of a listing without a waiver');
SELECT tap.logout();
SELECT is((SELECT coalesce(proof_of_ownership_path, 'null') || '|' || (proof_waived_at IS NOT NULL)::text || '|' || proof_status
             FROM public.listings WHERE event_name = 'Fixture 223 ADMIN-OK'), 'null|true|pending_review',
  'L3: after every attempt the waived listing has no proof path, keeps its waiver and is still pending_review');

SELECT * FROM finish();
ROLLBACK;
