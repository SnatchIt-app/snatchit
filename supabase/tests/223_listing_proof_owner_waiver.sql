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
-- ============================================================================
BEGIN;
SELECT plan(31);
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
                               p_proof text DEFAULT NULL, p_waived_at timestamptz DEFAULT NULL) RETURNS text LANGUAGE sql AS $f$
  SELECT format($i$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
        transfer_method, starting_bid, buy_now_enabled, duration_hours, ends_at, current_bid, cover_image_path,
        proof_of_ownership_path, proof_waived_by, proof_waiver_reason, proof_waived_at)
     VALUES (%L, %L, 'Club 223', 'wynwood', current_date + 7, '21:00', 'GA', 2,
             'mobile_transfer', 60, false, 24, now() + interval '24 hours', 60, 'covers/223.jpg',
             %L, %L, %L, %L) $i$,
     p_seller, 'Fixture 223 ' || p_tag, p_proof, p_waived_by, p_reason, p_waived_at) $f$;
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
SELECT is(tap._try223(tap._create223('PLAIN', tap.seller(), NULL, NULL)), '{"ok": true}'::jsonb,
  'C2: the same seller''s ordinary listing (no waiver fields) is unaffected');
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

SELECT * FROM finish();
ROLLBACK;
