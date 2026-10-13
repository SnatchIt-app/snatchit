-- ============================================================================
-- 219_marketplace_safety_enforcement.sql — migration 152 (20261013000000).
--   A. wiring: three triggers on the right events; five functions not client-executable.
--   B. baseline: with no block or suspension, the same statements succeed (the guards are the blockers).
--   C. block, seller blocks buyer: the buyer's new bid and new reservation, and the seller's bid on the
--      buyer's listing, are refused BLOCKED_PARTY; a third party is unaffected; the pre-block bid stands;
--      a report still goes through; the trusted service path is refused too.
--   D. block, buyer blocks seller: the same refusals from the other side.
--   E. existing reservation: a hold taken before the block completes; once lapsed, a new one is refused.
--   F. suspension authority: non-operator, direct table write, support role and self-suspension refused;
--      admin suspends with reason, actor and time recorded and audited; double suspension is stale.
--   G. suspension enforcement: the suspended user's bid, reservation, listing create and text edit refused
--      (ACCOUNT_SUSPENDED); can_create_listing says listing_blocked; others' bids and reservations on the
--      suspended seller's listings refused (LISTING_UNAVAILABLE); pre-suspension bid, orders and reports kept.
--   H. restoration: support cannot lift; admin lifts with reason; the user can bid again; history kept.
--   I. prohibited content: all ten terms refused on create (with variants), near-misses allowed, an edit
--      into a term refused, and a system write on a legacy row with unchanged text still passes.
--   J. scope: no 152 function is referenced by any trigger on orders, payments, refunds or payouts.
-- Every client action runs through tap.login (claims set): the same statement a stale app build, the live
-- web app or a direct PostgREST call sends.
-- ============================================================================
BEGIN;
SELECT plan(73);
SELECT tap.seed_core();

CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- Runs a statement as the CURRENT role and returns its outcome; a failure is rolled back to a savepoint.
CREATE FUNCTION tap._try219(p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_state text; v_msg text; v_hint text; v_detail text;
BEGIN
  EXECUTE p_sql;
  RETURN jsonb_build_object('ok', true);
EXCEPTION WHEN others THEN
  GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_hint = PG_EXCEPTION_HINT, v_detail = PG_EXCEPTION_DETAIL;
  RETURN jsonb_build_object('ok', false, 'code', v_state, 'message', v_msg, 'hint', v_hint, 'detail', v_detail);
END $f$;
CREATE FUNCTION tap._bid219(p_listing uuid, p_bidder uuid, p_amount int) RETURNS text LANGUAGE sql AS $f$
  SELECT format('INSERT INTO public.bids (listing_id, bidder_id, amount) VALUES (%L, %L, %s)', p_listing, p_bidder, p_amount) $f$;
CREATE FUNCTION tap._reserve219(p_listing uuid, p_user uuid) RETURNS text LANGUAGE sql AS $f$
  SELECT format('SELECT public.reserve_buy_now(%L, %L, 10)', p_listing, p_user) $f$;
-- The exact client create shape (CreateListingScreen / web create-listing).
CREATE FUNCTION tap._create219(p_seller uuid, p_name text, p_venue text DEFAULT 'Club X', p_restrictions text DEFAULT NULL) RETURNS text LANGUAGE sql AS $f$
  SELECT format($i$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, restrictions, starting_bid, buy_now_enabled,
        duration_hours, ends_at, current_bid, cover_image_path)
     VALUES (%L, %L, %L, 'wynwood', current_date + 7, '21:00',
             'GA', 2, 'mobile_transfer', %L, 60, false, 24, now() + interval '24 hours', 60, 'covers/219.jpg') $i$,
     p_seller, p_name, p_venue, p_restrictions) $f$;
-- The exact client edit shape (app/listing/edit/[id].tsx).
CREATE FUNCTION tap._edit219(p_listing uuid, p_seller uuid, p_name text) RETURNS text LANGUAGE sql AS $f$
  SELECT format($u$ UPDATE public.listings SET event_name = %L, venue = venue, restrictions = restrictions, ticket_platform = ticket_platform
                     WHERE id = %L AND seller_id = %L $u$, p_name, p_listing, p_seller) $f$;
CREATE FUNCTION tap._backdate219() RETURNS void LANGUAGE sql SECURITY DEFINER AS $f$
  UPDATE public.bids SET created_at = created_at - interval '1 minute' $f$;   -- clears the 3-second rebid rule

-- Fixture listings (as postgres). S = seller, B = buyer, O = other, A = admin.
-- LS1/LS2: S's auction + Buy Now. LB1/LB2: B's. LO1: O's. All active, ending in 24 h.
INSERT INTO public.listings (id, seller_id, event_name, venue, neighborhood, event_date, event_time, ticket_type, quantity,
  transfer_method, starting_bid, buy_now_enabled, buy_now_price, duration_hours, starts_at, ends_at, current_bid, cover_image_path, auction_status)
SELECT v.id, v.seller, 'Fixture 219 ' || v.tag, 'Club 219', 'wynwood', current_date + 30, '21:00', 'GA', 2, 'mobile_transfer',
       100, true, 300, 24, now(), now() + interval '24 hours', 100, 'fixtures/219.jpg', 'active'
  FROM (VALUES ('dddddddd-0219-0000-0000-000000000001'::uuid, tap.seller(), 'LS1'),
               ('dddddddd-0219-0000-0000-000000000002'::uuid, tap.seller(), 'LS2'),
               ('dddddddd-0219-0000-0000-000000000003'::uuid, tap.buyer(),  'LB1'),
               ('dddddddd-0219-0000-0000-000000000004'::uuid, tap.buyer(),  'LB2'),
               ('dddddddd-0219-0000-0000-000000000005'::uuid, tap.other_user(), 'LO1'),
               ('dddddddd-0219-0000-0000-000000000006'::uuid, tap.seller(), 'LS3')) AS v(id, seller, tag);
CREATE FUNCTION tap.ls1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'dddddddd-0219-0000-0000-000000000001'::uuid $$;
CREATE FUNCTION tap.ls2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'dddddddd-0219-0000-0000-000000000002'::uuid $$;
CREATE FUNCTION tap.lb1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'dddddddd-0219-0000-0000-000000000003'::uuid $$;
CREATE FUNCTION tap.lb2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'dddddddd-0219-0000-0000-000000000004'::uuid $$;
CREATE FUNCTION tap.lo1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'dddddddd-0219-0000-0000-000000000005'::uuid $$;
CREATE FUNCTION tap.ls3() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'dddddddd-0219-0000-0000-000000000006'::uuid $$;
-- Listing-create prerequisites (036/038) for B and O as sellers.
UPDATE public.profiles SET stripe_onboarding_complete = true WHERE id IN (tap.buyer(), tap.other_user());
UPDATE auth.users SET phone = '+1305555' || right(id::text, 4), phone_confirmed_at = now()
 WHERE id IN (tap.buyer(), tap.other_user());

-- ── A. wiring ───────────────────────────────────────────────────────────────
SELECT alike((SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'public.bids'::regclass AND tgname = 'before_bid_guard_parties'),
  'CREATE TRIGGER before_bid_guard_parties BEFORE INSERT ON public.bids FOR EACH ROW EXECUTE FUNCTION %guard_bid_parties()',
  'A1: before_bid_guard_parties is BEFORE INSERT on bids');
SELECT ok('before_bid_guard_parties' < (SELECT min(tgname) FROM pg_trigger WHERE tgrelid = 'public.bids'::regclass
            AND NOT tgisinternal AND tgname <> 'before_bid_guard_parties' AND tgtype & 2 = 2),
  'A2: it sorts before every other BEFORE trigger on bids, so it fires first');
SELECT alike((SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_reservation_parties'),
  'CREATE TRIGGER trg_guard_listing_reservation_parties BEFORE UPDATE OF status, reserved_by ON public.listings FOR EACH ROW EXECUTE FUNCTION %guard_listing_reservation_parties()',
  'A3: the reservation guard is BEFORE UPDATE OF status, reserved_by on listings');
SELECT alike((SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass AND tgname = 'trg_guard_listing_content'),
  'CREATE TRIGGER trg_guard_listing_content BEFORE INSERT OR UPDATE OF event_name, venue, restrictions ON public.listings FOR EACH ROW EXECUTE FUNCTION %guard_listing_content()',
  'A4: the content guard is BEFORE INSERT OR UPDATE OF the three text columns');
SELECT is((SELECT count(*)::int FROM unnest(ARRAY['public.assert_marketplace_parties(uuid,uuid)','public.guard_bid_parties()',
            'public.guard_listing_reservation_parties()','public.listing_prohibited_term(text[])','public.guard_listing_content()']) f
           WHERE has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')), 0,
  'A5: none of the five functions is executable by anon or authenticated');
SELECT is((SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'user_restriction_kind_check'),
  'CHECK ((kind = ANY (ARRAY[''listing_blocked''::text, ''suspended''::text])))', 'A6: ops.user_restriction.kind admits suspended');

-- ── B. baseline ─────────────────────────────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._bid219(tap.ls1(), tap.buyer(), 110)), '{"ok": true}'::jsonb, 'B1: with no block, B bids on S''s LS1');
SELECT tap.logout();
SELECT tap._backdate219();
SELECT tap.login(tap.seller());
SELECT is(tap._try219(tap._bid219(tap.lb1(), tap.seller(), 110)), '{"ok": true}'::jsonb, 'B2: with no block, S bids on B''s LB1');
SELECT tap.logout();
SELECT tap._backdate219();

-- ── C. S blocks B (the real client write: an owner row in user_blocks) ──────
SELECT tap.login(tap.seller());
SELECT lives_ok($$INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES (tap.seller(), tap.buyer())$$, 'C1: S blocks B');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._bid219(tap.ls1(), tap.buyer(), 120)) - 'detail',
  '{"ok": false, "code": "P0001", "message": "This listing isn''t available to you.", "hint": "BLOCKED_PARTY"}'::jsonb,
  'C2: the blocked B''s new bid on S''s listing is refused: P0001, the exact sentence, BLOCKED_PARTY');
SELECT is(tap._try219(tap._reserve219(tap.ls2(), tap.buyer())) ->> 'hint', 'BLOCKED_PARTY', 'C3: B''s new Buy Now reservation on S''s LS2 is refused');
SELECT is((tap._try219($$INSERT INTO public.reports (reporter_id, target_type, target_id, reason) VALUES (tap.buyer(), 'user', tap.seller(), 'harassment')$$)) ->> 'ok',
  'true', 'C4: B can still report S');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is(tap._try219(tap._bid219(tap.lb1(), tap.seller(), 120)) ->> 'hint', 'BLOCKED_PARTY', 'C5: the blocker S cannot bid on B''s listing either');
SELECT is(tap._try219(tap._reserve219(tap.lb2(), tap.seller())) ->> 'hint', 'BLOCKED_PARTY', 'C6: nor reserve B''s listing');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT is(tap._try219(tap._bid219(tap.ls1(), tap.other_user(), 130)), '{"ok": true}'::jsonb, 'C7: a third party O still bids on LS1');
SELECT tap.logout();
SELECT tap._backdate219();
SELECT is((SELECT count(*)::int FROM public.bids WHERE listing_id = tap.ls1() AND bidder_id = tap.buyer() AND amount = 110), 1,
  'C8: B''s bid placed before the block stands');
SELECT tap.login_service();
SELECT is(tap._try219(tap._reserve219(tap.ls2(), tap.buyer())) ->> 'hint', 'BLOCKED_PARTY',
  'C9: the trusted service path reserving for B on S''s listing is refused too');
SELECT tap.logout();
SELECT is((SELECT (status, reserved_by) FROM public.listings WHERE id = tap.ls2()), ('active'::text, NULL::uuid), 'C10: LS2 is not reserved');

-- ── D. the other direction: B blocks S ──────────────────────────────────────
DELETE FROM public.user_blocks WHERE blocker_id = tap.seller() AND blocked_id = tap.buyer();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._bid219(tap.ls1(), tap.buyer(), 140)), '{"ok": true}'::jsonb, 'D1: unblocked again, B bids on LS1');
SELECT lives_ok($$INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES (tap.buyer(), tap.seller())$$, 'D2: B blocks S');
SELECT tap.logout();
SELECT tap._backdate219();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._bid219(tap.ls1(), tap.buyer(), 150)) ->> 'hint', 'BLOCKED_PARTY', 'D3: the blocker B cannot bid on S''s listing');
SELECT is(tap._try219(tap._reserve219(tap.ls2(), tap.buyer())) ->> 'hint', 'BLOCKED_PARTY', 'D4: nor reserve it');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT is(tap._try219(tap._bid219(tap.lb1(), tap.seller(), 150)) ->> 'message', 'This listing isn''t available to you.',
  'D5: the blocked S gets the same sentence (no direction disclosed)');
SELECT is(tap._try219(tap._reserve219(tap.lb2(), tap.seller())) ->> 'hint', 'BLOCKED_PARTY', 'D6: and cannot reserve B''s listing');
SELECT tap.logout();
DELETE FROM public.user_blocks WHERE blocker_id = tap.buyer() AND blocked_id = tap.seller();

-- ── E. a reservation taken before the block completes ───────────────────────
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._reserve219(tap.ls2(), tap.buyer())), '{"ok": true}'::jsonb, 'E1: unblocked, B reserves LS2');
SELECT tap.logout();
SELECT tap.login(tap.seller());
SELECT lives_ok($$INSERT INTO public.user_blocks (blocker_id, blocked_id) VALUES (tap.seller(), tap.buyer())$$, 'E2: S then blocks B');
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._reserve219(tap.ls2(), tap.buyer())), '{"ok": true}'::jsonb, 'E3: B re-calling reserve on the live hold succeeds');
SELECT tap.logout();
SELECT is((SELECT (status, reserved_by) FROM public.listings WHERE id = tap.ls2()), ('reserved'::text, tap.buyer()),
  'E4: the pre-block hold is still B''s, so checkout can complete');
UPDATE public.listings SET reserved_until = now() - interval '1 second' WHERE id = tap.ls2();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._reserve219(tap.ls2(), tap.buyer())) ->> 'hint', 'BLOCKED_PARTY', 'E5: once the hold lapses, a new one is refused');
SELECT tap.logout();
DELETE FROM public.user_blocks WHERE blocker_id = tap.seller() AND blocked_id = tap.buyer();

-- ── F. suspension authority ─────────────────────────────────────────────────
SELECT tap.login(tap.buyer()); SELECT tap._aal2();
SELECT is(tap._try219($$SELECT ops.execute_action('k219-nonop-0000001','user_restrict','user', tap.other_user(), '{"kind":"suspended"}', 'x')$$) ->> 'code',
  '42501', 'F1: a non-operator cannot call ops.execute_action');
SELECT is(tap._try219($$INSERT INTO ops.user_restriction (user_id, kind, reason, actor) VALUES (tap.other_user(), 'suspended', 'x', tap.buyer())$$) ->> 'code',
  '42501', 'F2: a client cannot write ops.user_restriction directly');
SELECT tap.logout();
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.other_user(), 'platform_support', tap.admin_user());
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is((ops.execute_action('k219-support-00001','user_restrict','user', tap.buyer(), '{"kind":"suspended"}', 'support try')) ->> 'reject_reason',
  'forbidden', 'F3: platform_support may not suspend');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM ops.user_restriction WHERE user_id = tap.buyer() AND kind = 'suspended'), 0, 'F4: no suspension row from F1-F3');
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT is((ops.execute_action('k219-self-0000001','user_restrict','user', tap.admin_user(), '{"kind":"suspended"}', 'self')) ->> 'reject_reason',
  'precondition', 'F5: an operator cannot suspend their own account');
SELECT is(tap._try219($$SELECT ops.execute_action('k219-noreason-001','user_restrict','user', tap.buyer(), '{"kind":"suspended"}', '  ')$$) ->> 'ok',
  'false', 'F6: a suspension without a reason is refused');
SELECT is((ops.execute_action('k219-suspend-00001','user_restrict','user', tap.buyer(), '{"kind":"suspended"}', 'repeated harassment reports')) ->> 'status',
  'succeeded', 'F7: platform_admin suspends B with a reason');
SELECT is((ops.execute_action('k219-suspend-00002','user_restrict','user', tap.buyer(), '{"kind":"suspended"}', 'again')) ->> 'reject_reason',
  'stale_state', 'F8: suspending an already-suspended user is stale_state');
SELECT is((ops.execute_action('k219-badkind-00001','user_restrict','user', tap.buyer(), '{"kind":"banned"}', 'x')) ->> 'reject_reason',
  'not_supported', 'F9: an unknown kind is still not_supported');
SELECT tap.logout();
SELECT is((SELECT (actor, reason, lifted_at IS NULL, created_at = now()) FROM ops.user_restriction WHERE user_id = tap.buyer() AND kind = 'suspended'),
  (tap.admin_user(), 'repeated harassment reports'::text, true, true), 'F10: the row records actor, reason and time, not lifted');
SELECT ok(EXISTS (SELECT 1 FROM ops.audit WHERE action = 'action.user_restrict' AND subject_id = tap.buyer() AND actor = tap.admin_user()
                    AND reason = 'repeated harassment reports'), 'F11: ops.audit records the suspension with actor and reason');
SELECT is((SELECT is_listing_blocked FROM public.seller_risk_scores WHERE seller_id = tap.buyer()), NULL::boolean,
  'F12: suspension is its own record (no listing-block flag was written)');

-- ── G. suspension enforcement ───────────────────────────────────────────────
SELECT tap.reset_guards();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._bid219(tap.lo1(), tap.buyer(), 120)) - 'detail',
  '{"ok": false, "code": "P0001", "message": "Your account is suspended, so you can''t bid, buy or create listings. Orders you already have aren''t affected. Contact support@snatchitapp.com.", "hint": "ACCOUNT_SUSPENDED"}'::jsonb,
  'G1: the suspended B''s new bid is refused with the exact sentence and ACCOUNT_SUSPENDED');
SELECT is(tap._try219(tap._reserve219(tap.lo1(), tap.buyer())) ->> 'hint', 'ACCOUNT_SUSPENDED', 'G2: B''s new reservation is refused');
SELECT is(tap._try219(tap._create219(tap.buyer(), '219 suspended create')) ->> 'hint', 'ACCOUNT_SUSPENDED', 'G3: B''s new listing is refused');
SELECT is(tap._try219(tap._edit219(tap.lb1(), tap.buyer(), 'Fixture 219 LB1 renamed')) ->> 'hint', 'ACCOUNT_SUSPENDED', 'G4: B''s edit of listing text is refused');
SELECT is((SELECT (allowed, reason) FROM public.can_create_listing(tap.buyer())), (false, 'listing_blocked'::text),
  'G5: can_create_listing tells the suspended B listing_blocked (the copy every shipped client knows)');
SELECT is((tap._try219($$INSERT INTO public.reports (reporter_id, target_type, target_id, reason) VALUES (tap.buyer(), 'listing', tap.lo1(), 'other')$$)) ->> 'ok',
  'true', 'G6: the suspended B can still file a report');
SELECT tap.logout();
SELECT tap.login(tap.other_user());
SELECT is(tap._try219(tap._bid219(tap.lb1(), tap.other_user(), 130)) - 'detail',
  '{"ok": false, "code": "P0001", "message": "This listing isn''t available right now.", "hint": "LISTING_UNAVAILABLE"}'::jsonb,
  'G7: O''s new bid on the suspended seller''s listing is refused LISTING_UNAVAILABLE');
SELECT is(tap._try219(tap._reserve219(tap.lb2(), tap.other_user())) ->> 'hint', 'LISTING_UNAVAILABLE', 'G8: and so is a reservation');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.bids WHERE bidder_id = tap.buyer()), 2, 'G9: B''s two earlier bids stand');
SELECT is((SELECT array_agg(status ORDER BY id) FROM public.transfers WHERE buyer_id = tap.buyer()), ARRAY['pending','seller_sent'],
  'G10: B''s existing orders are untouched');
SELECT is((SELECT event_name FROM public.listings WHERE id = tap.lb1()), 'Fixture 219 LB1', 'G11: the refused edit wrote nothing');
SELECT tap.login(tap.seller());
SELECT is(tap._try219(tap._bid219(tap.lo1(), tap.seller(), 125)), '{"ok": true}'::jsonb, 'G12: an unsuspended user still bids normally');
SELECT tap.logout();
SELECT tap._backdate219();

-- ── H. restoration ──────────────────────────────────────────────────────────
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is(tap._try219($$SELECT ops.execute_action('k219-supp-lift-01','user_unrestrict','user', tap.buyer(), '{"kind":"suspended"}', 'support lift')$$) ->> 'code',
  '42501', 'H1: platform_support may not lift a suspension');
SELECT tap.logout();
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT is((ops.execute_action('k219-lift-0000001','user_unrestrict','user', tap.buyer(), '{"kind":"suspended"}', 'appeal accepted')) ->> 'status',
  'succeeded', 'H2: platform_admin lifts the suspension with a reason');
SELECT is((ops.execute_action('k219-lift-0000002','user_unrestrict','user', tap.buyer(), '{"kind":"suspended"}', 'again')) ->> 'reject_reason',
  'stale_state', 'H3: lifting a lifted suspension is stale_state');
SELECT tap.logout();
SELECT is((SELECT (lifted_by, lift_reason, lifted_at IS NOT NULL, reason) FROM ops.user_restriction WHERE user_id = tap.buyer() AND kind = 'suspended'),
  (tap.admin_user(), 'appeal accepted'::text, true, 'repeated harassment reports'::text), 'H4: the row keeps the suspension and records who lifted it, when and why');
SELECT tap.reset_guards();
SELECT tap.login(tap.buyer());
SELECT is(tap._try219(tap._bid219(tap.lo1(), tap.buyer(), 140)), '{"ok": true}'::jsonb, 'H5: after the lift, B bids again');
SELECT is((SELECT (allowed, reason) FROM public.can_create_listing(tap.buyer())), (true, 'ok'::text), 'H6: and can create listings again');
SELECT tap.logout();
SELECT tap._backdate219();
-- platform_risk may suspend too
INSERT INTO kernel.platform_role (identity_id, role, granted_by) VALUES (tap.other_user(), 'platform_risk', tap.admin_user());
SELECT tap.login(tap.other_user()); SELECT tap._aal2();
SELECT is((ops.execute_action('k219-risk-susp-001','user_restrict','user', tap.seller(), '{"kind":"suspended"}', 'risk review')) ->> 'status',
  'succeeded', 'H7: platform_risk may suspend');
SELECT is((ops.execute_action('k219-risk-lift-001','user_unrestrict','user', tap.seller(), '{"kind":"suspended"}', 'cleared')) ->> 'status',
  'succeeded', 'H8: and lift');
SELECT tap.logout();

-- ── I. prohibited content ───────────────────────────────────────────────────
CREATE TABLE tap.terms_219 (input text, want text);
INSERT INTO tap.terms_219 VALUES
  ('Alcohol tasting night', 'alcohol'), ('Free drugs', 'drugs'), ('drug party', 'drugs'), ('WEED fest', 'weed'),
  ('cocaine', 'cocaine'), ('Molly night', 'molly'), ('Open bar all night', 'open bar'), ('open-bar', 'open bar'),
  ('openbar', 'open bar'), ('Bottle Service table', 'bottle service'), ('bottle-service', 'bottle service'),
  ('fake tickets here', 'fake ticket'), ('fake-ticket', 'fake ticket'), ('Counterfeit', 'counterfeit'), ('underage ok', 'underage');
GRANT SELECT ON tap.terms_219 TO PUBLIC;
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT is((SELECT array_agg(d ORDER BY d) FROM (SELECT DISTINCT (tap._try219(tap._create219(tap.seller(), t.input))) ->> 'detail' AS d
                                                   FROM tap.terms_219 t) x),
  ARRAY['alcohol','bottle service','cocaine','counterfeit','drugs','fake ticket','molly','open bar','underage','weed'],
  'I1: every one of the ten terms (and its variants) is refused on create, each reporting its own label');
SELECT is((SELECT count(*)::int FROM tap.terms_219 t WHERE (tap._try219(tap._create219(tap.seller(), t.input))) ->> 'hint' = 'PROHIBITED_CONTENT'),
  15, 'I2: all 15 inputs are refused PROHIBITED_CONTENT');
SELECT is(tap._try219(tap._create219(tap.seller(), 'Clean Event', 'Club Y', 'No bottle service refunds')) ->> 'message',
  'Listings can''t mention "bottle service". Please revise your event name, venue, or restrictions and try again.',
  'I3: the restrictions field is checked too, with the app''s own sentence');
SELECT is(tap._try219(tap._create219(tap.seller(), 'Clean Event', 'The Weed Lounge')) ->> 'detail', 'weed', 'I4: the venue field is checked too');
SELECT is(tap._try219(tap._create219(tap.seller(), 'Weedon Arena Drugstore Cowboy Openbarn Mollyworld Underaged')), '{"ok": true}'::jsonb,
  'I5: near-misses (word boundaries) are allowed');
SELECT is(tap._try219(tap._edit219(tap.ls3(), tap.seller(), 'Now with an open bar')) ->> 'hint', 'PROHIBITED_CONTENT', 'I6: an edit into a term is refused');
SELECT is(tap._try219(tap._edit219(tap.ls3(), tap.seller(), 'Fixture 219 LS3 tidy')), '{"ok": true}'::jsonb, 'I7: a clean edit is saved');
SELECT tap.logout();
-- a legacy row (written before 152) keeps working for system writes that leave its text unchanged
ALTER TABLE public.listings DISABLE TRIGGER trg_guard_listing_content;
UPDATE public.listings SET event_name = 'Legacy open bar listing' WHERE id = tap.ls1();
ALTER TABLE public.listings ENABLE TRIGGER trg_guard_listing_content;
SELECT tap.login(tap.other_user());
SELECT is(tap._try219(tap._bid219(tap.ls1(), tap.other_user(), 200)), '{"ok": true}'::jsonb,
  'I8: a bid on a legacy listing passes (the bid trigger''s listing update leaves the text unchanged)');
SELECT tap.logout();
SELECT tap.login_service();
SELECT is(tap._try219(tap._create219(tap.seller(), 'Service path cocaine')) ->> 'hint', 'PROHIBITED_CONTENT', 'I9: the content rule applies to the service path too');
SELECT tap.logout();

-- ── J. scope: orders, payments, refunds and payouts are untouched ───────────
SELECT is((SELECT count(*)::int FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
            WHERE NOT t.tgisinternal
              AND t.tgrelid IN ('public.transfers'::regclass, 'public.payments'::regclass, 'public.payment_refunds'::regclass,
                                'public.payout_attempts'::regclass, 'public.payout_decisions'::regclass)
              AND (p.proname IN ('guard_bid_parties','guard_listing_reservation_parties','guard_listing_content')
                   OR p.prosrc LIKE '%assert_marketplace_parties%')), 0,
  'J1: no trigger on transfers, payments, refunds or payouts uses a 152 rule');
SELECT is((SELECT array_agg(p.proname::text ORDER BY p.proname) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE p.prosrc LIKE '%assert_marketplace_parties(%' AND p.proname <> 'assert_marketplace_parties'),
  ARRAY['guard_bid_parties','guard_listing_content','guard_listing_reservation_parties'],
  'J2: only the three guards call the refusal rule (no payment, settlement or order function does)');
SELECT ok((SELECT prosrc NOT LIKE '%user_blocks%' AND prosrc NOT LIKE '%user_restriction%'
             FROM pg_proc WHERE oid = 'public.complete_auction_payment(uuid,uuid)'::regprocedure),
  'J3: auction settlement (complete_auction_payment) has no block or suspension check: a pre-existing win settles');

SELECT * FROM finish();
ROLLBACK;
