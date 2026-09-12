-- ============================================================================
-- 185_listing_block_insert_guard.sql — migration 119 (listing block enforced
-- at the database boundary).
--   1. wiring — trg_guard_listing_seller_not_blocked is BEFORE INSERT on
--      public.listings; the trigger function is not client-executable.
--   2. the guard is the ONLY blocker — the same seller INSERT (client column
--      set, 036/038 policy prerequisites satisfied by the fixture) succeeds
--      while is_listing_blocked = false and fails with listing_blocked once
--      the flag is flipped.
--   3. trusted paths keep working — service_role and a claims-less postgres
--      session insert for the blocked seller; a seller with no risk row is
--      never blocked.
--   4. can_create_listing() (advisory path) still reports listing_blocked.
--   5. end-to-end — ops.execute_action user_restrict blocks the seller's next
--      INSERT; user_unrestrict lets it through again.
-- ============================================================================
BEGIN;
SELECT plan(24);
SELECT tap.seed_core();

CREATE TABLE tap.memo_185 (k text PRIMARY KEY, v text);
CREATE FUNCTION tap._store185(k text, v text) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $m$ INSERT INTO tap.memo_185 VALUES (k,v) ON CONFLICT (k) DO UPDATE SET v=excluded.v $m$;
CREATE FUNCTION tap._j185(k text) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER AS $m$ SELECT v::jsonb FROM tap.memo_185 WHERE k=$1 $m$;
CREATE FUNCTION tap._aal2() RETURNS void LANGUAGE plpgsql AS $f$ begin perform set_config('request.jwt.claims',
  (coalesce(current_setting('request.jwt.claims',true),'{}')::jsonb || '{"aal":"aal2"}'::jsonb)::text, true); end $f$;
-- The exact client shape (src/screens/CreateListingScreen.tsx): current_bid =
-- starting_bid, every server-controlled column at its default (072).
CREATE FUNCTION tap._insert185(p_seller uuid, p_name text) RETURNS text LANGUAGE sql AS $f$
  SELECT format($i$ INSERT INTO public.listings
       (seller_id, event_name, venue, neighborhood, event_date, event_time,
        ticket_type, quantity, transfer_method, starting_bid, buy_now_enabled,
        duration_hours, ends_at, current_bid, cover_image_path)
     VALUES (%L, %L, 'Club X', 'wynwood', current_date + 7, '21:00',
             'GA', 2, 'mobile_transfer', 60, false, 24, now() + interval '24 hours', 60, 'covers/185.jpg') $i$,
     p_seller, p_name) $f$;

-- ── 1. wiring ───────────────────────────────────────────────────────────────
SELECT is((SELECT count(*)::int FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass
            AND tgname = 'trg_guard_listing_seller_not_blocked' AND NOT tgisinternal), 1,
  '1: trg_guard_listing_seller_not_blocked exists on public.listings');
SELECT ok((SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgrelid = 'public.listings'::regclass
            AND tgname = 'trg_guard_listing_seller_not_blocked')
          LIKE 'CREATE TRIGGER trg_guard_listing_seller_not_blocked BEFORE INSERT ON public.listings FOR EACH ROW EXECUTE FUNCTION %guard_listing_seller_not_blocked()',
  '2: ...BEFORE INSERT, FOR EACH ROW, on guard_listing_seller_not_blocked()');
SELECT ok(NOT has_function_privilege('anon', 'public.guard_listing_seller_not_blocked()', 'EXECUTE'),
  '3: anon may NOT EXECUTE the trigger function');
SELECT ok(NOT has_function_privilege('authenticated', 'public.guard_listing_seller_not_blocked()', 'EXECUTE'),
  '4: authenticated may NOT EXECUTE the trigger function');
SELECT ok((SELECT proacl IS NOT NULL AND NOT EXISTS (SELECT 1 FROM aclexplode(proacl) a WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE')
             FROM pg_proc WHERE oid = 'public.guard_listing_seller_not_blocked()'::regprocedure),
  '5: PUBLIC holds no EXECUTE on the trigger function (default grant revoked)');

-- ── 2. the guard is the only blocker ────────────────────────────────────────
SELECT ok((SELECT stripe_onboarding_complete FROM public.profiles WHERE id = tap.seller())
          AND (SELECT phone_confirmed_at IS NOT NULL FROM auth.users WHERE id = tap.seller()),
  '6: fixture seller satisfies the 036/038 INSERT policy (onboarded + verified phone)');
INSERT INTO public.seller_risk_scores (seller_id, is_listing_blocked) VALUES (tap.seller(), false);
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT lives_ok(tap._insert185(tap.seller(), '185 unblocked create'),
  '7: with is_listing_blocked = false the seller INSERT succeeds (same statement as #9)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.listings WHERE seller_id = tap.seller() AND event_name = '185 unblocked create'), 1,
  '8: ...the row exists');
DELETE FROM public.listings WHERE event_name = '185 unblocked create';

UPDATE public.seller_risk_scores
   SET is_listing_blocked = true, listing_blocked_at = now(), listing_blocked_reason = '185 fixture block'
 WHERE seller_id = tap.seller();
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT throws_like(tap._insert185(tap.seller(), '185 blocked create'), '%listing_blocked%',
  '9: with is_listing_blocked = true the SAME seller INSERT throws listing_blocked');
SELECT throws_ok(tap._insert185(tap.seller(), '185 blocked create'), 'P0001', NULL,
  '10: ...with errcode P0001');
SELECT is((SELECT (allowed, reason) FROM public.can_create_listing(tap.seller())), (false, 'listing_blocked'::text),
  '11: can_create_listing() (advisory path) still reports allowed=false / listing_blocked');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.listings WHERE event_name = '185 blocked create'), 0,
  '12: no listing row was created by the refused INSERTs');

-- ── 3. trusted paths ────────────────────────────────────────────────────────
SELECT tap.login_service();
SELECT lives_ok(tap._insert185(tap.seller(), '185 service create'),
  '13: service_role inserts for the blocked seller (trusted path)');
SELECT tap.logout();
SELECT is((SELECT count(*)::int FROM public.listings WHERE seller_id = tap.seller() AND event_name = '185 service create'), 1,
  '14: ...the row exists');
DELETE FROM public.listings WHERE event_name = '185 service create';
SELECT lives_ok(tap._insert185(tap.seller(), '185 postgres create'),
  '15: a claims-less postgres session inserts for the blocked seller (migrations / fixtures / cron)');
SELECT is((SELECT count(*)::int FROM public.listings WHERE seller_id = tap.seller() AND event_name = '185 postgres create'), 1,
  '16: ...the row exists');
DELETE FROM public.listings WHERE event_name = '185 postgres create';

-- a seller with NO seller_risk_scores row: other_user, given the 036/038 prerequisites
UPDATE public.profiles SET stripe_onboarding_complete = true WHERE id = tap.other_user();
UPDATE auth.users SET phone = '+13055550003', phone_confirmed_at = now() WHERE id = tap.other_user();
SELECT is((SELECT count(*)::int FROM public.seller_risk_scores WHERE seller_id = tap.other_user()), 0,
  '17: other_user has no seller_risk_scores row');
SELECT tap.reset_guards();
SELECT tap.login(tap.other_user());
SELECT lives_ok(tap._insert185(tap.other_user(), '185 no-risk-row create'),
  '18: a seller without a risk row inserts fine (absent row = not blocked)');
SELECT tap.logout();
DELETE FROM public.listings WHERE event_name = '185 no-risk-row create';

-- ── 4. end-to-end: console user_restrict -> guard -> user_unrestrict ────────
UPDATE public.seller_risk_scores SET is_listing_blocked = false WHERE seller_id = tap.seller();
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store185('r_restrict', ops.execute_action('k185-restrict-00001','user_restrict','user',tap.seller(),
  '{}'::jsonb, 'duplicate evidence pattern')::text);
SELECT is((tap._j185('r_restrict') ->> 'status'), 'succeeded', '19: ops.execute_action user_restrict succeeds');
SELECT tap.logout();
SELECT is((SELECT (is_listing_blocked, listing_blocked_reason) FROM public.seller_risk_scores WHERE seller_id = tap.seller()),
  (true, 'duplicate evidence pattern'::text), '20: seller_risk_scores.is_listing_blocked = true with the console reason');
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT throws_like(tap._insert185(tap.seller(), '185 restricted create'), '%listing_blocked%',
  '21: the restricted seller''s INSERT throws listing_blocked (console -> guard)');
SELECT tap.logout();
SELECT tap.login(tap.admin_user()); SELECT tap._aal2();
SELECT tap._store185('r_lift', ops.execute_action('k185-unrestrict-0001','user_unrestrict','user',tap.seller(),
  '{}'::jsonb, 'cleared')::text);
SELECT is((tap._j185('r_lift') ->> 'status'), 'succeeded', '22: ops.execute_action user_unrestrict succeeds');
SELECT tap.logout();
SELECT tap.reset_guards();
SELECT tap.login(tap.seller());
SELECT lives_ok(tap._insert185(tap.seller(), '185 unrestricted create'),
  '23: after user_unrestrict the seller INSERT is allowed again');
SELECT tap.logout();
SELECT is(((SELECT is_listing_blocked FROM public.seller_risk_scores WHERE seller_id = tap.seller()),
           (SELECT count(*)::int FROM public.listings WHERE seller_id = tap.seller() AND event_name = '185 unrestricted create')),
  (false, 1), '24: flag back to false and the listing exists');

SELECT * FROM finish();
ROLLBACK;
