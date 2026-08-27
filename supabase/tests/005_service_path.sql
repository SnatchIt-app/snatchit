-- ============================================================================
-- 005_service_path.sql — pins request_is_service_role() (055) and the identity
-- resolution every strict-auth RPC is built on (059/059b/061):
--
--     v_caller_id := auth.uid();
--     IF v_caller_id IS NULL AND public.request_is_service_role()
--        THEN v_caller_id := p_user_id; END IF;
--
-- If request_is_service_role() ever returned TRUE under a client persona, that
-- second line would make p_user_id an identity-forgery parameter across
-- reserve_buy_now / mark_listing_sold / complete_auction_payment /
-- cancel_listing / release_reservation / ensure_transfer_exists /
-- mark_transfer_sent / confirm_transfer_received / buyer_dispute_transfer —
-- and EVERY other file in this suite would silently stop proving anything.
-- So it is pinned here, once, for every claim shape the four personas produce.
--
-- MUST RUN BEFORE ANY OTHER PERSONA-USING FILE: assertions 1-2 can only be made
-- in a session where request.jwt.claims has never been assigned, and
-- set_config() creates that placeholder GUC permanently for the session (RESET
-- restores '' — never NULL again). pg_prove opens one psql per file, which is
-- what makes assertion 1 hold; if it ever fails, the runner is sharing a
-- session and assertion 2 is no longer a valid observation.
--
-- NOTE ON HOW THE PROBES RUN: 067 revoked EXECUTE on request_is_service_role()
-- from anon and authenticated, so the function cannot be called *as* those SQL
-- roles. It reads claims only — it never looks at current_user — so the probes
-- set the claim shape with set_config/tap.set_claims and stay on the owner
-- connection. The persona helpers are then used for the behavioural half.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ── 1-2: the documented fail-open, observed before anything touches claims ──
SELECT ok(current_setting('request.jwt.claims', true) IS NULL,
  'fresh session: request.jwt.claims has never been set (pg_prove = one psql per file)');
SELECT ok(public.request_is_service_role(),
  'claims-less direct connection IS the service path (055 fail-open) — this is why every persona must set claims');

SELECT tap.seed_core();

-- ── 3-5: no client claim shape can reach the service path ───────────────────
SELECT tap.set_claims(tap.seller(), 'authenticated');
SELECT ok(NOT public.request_is_service_role(),
  'claims {sub,role:authenticated} => NOT the service path (p_user_id cannot win)');

SELECT set_config('request.jwt.claims', '{"role":"anon"}', true);
SELECT ok(NOT public.request_is_service_role(),
  'claims {role:anon} => NOT the service path');

-- The shape PostgREST presents for a request carrying no JWT at all.
SELECT set_config('request.jwt.claims', '{}', true);
SELECT ok(NOT public.request_is_service_role(),
  'claims {} (no-JWT PostgREST request) => NOT the service path');

-- ── 6: service_role claims — the ONLY trusted server shape ──────────────────
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT ok(public.request_is_service_role(),
  'claims {role:service_role} => IS the service path');

-- ── 7: tap.logout() is the OWNER connection, not the service path ───────────
-- set_config(...,'') CREATES the GUC with value '', and current_setting(...,true)
-- returns '' — not NULL — so the fail-open branch does not fire. The original
-- harness comment claimed the opposite; this assertion guards against anyone
-- writing a test that relies on the false version.
SELECT tap.logout();
SELECT ok(NOT public.request_is_service_role(),
  'tap.logout(): claims = '''' reads back as '''' not NULL => NOT the service path (use login_service)');

-- ── 8-9: the persona helpers really do drive auth.uid() ─────────────────────
SELECT tap.login(tap.seller());
SELECT is(auth.uid(), tap.seller(), 'tap.login() drives auth.uid() from the sub claim');
SELECT tap.logout();
SELECT tap.login_anon();
SELECT ok(auth.uid() IS NULL, 'tap.login_anon() leaves auth.uid() NULL');

-- ── 10: auth.uid() beats p_user_id for a signed-in caller ───────────────────
-- buyer asks for listing A while passing the SELLER as p_user_id. If p_user_id
-- won, the payment lookup (buyer_id = v_caller_id) would find nothing and the
-- call would raise; getting transfer A back proves auth.uid() decided.
SELECT tap.logout();
SELECT tap.login(tap.buyer());
SELECT results_eq(
  $$ SELECT public.ensure_transfer_exists(tap.listing_a(), tap.seller()) $$,
  ARRAY['cccccccc-0000-0000-0000-000000000001'::uuid],
  'signed-in caller: auth.uid() wins, forged p_user_id is ignored (059/059b)');

-- ── 11: on the service path p_user_id IS the subject, and is mandatory ──────
SELECT tap.logout();
SELECT tap.login_service();
SELECT results_eq(
  $$ SELECT public.ensure_transfer_exists(tap.listing_a(), tap.buyer()) $$,
  ARRAY['cccccccc-0000-0000-0000-000000000001'::uuid],
  'service path: p_user_id names the subject (the sanctioned Edge Function call)');

-- ── 12: and the owner connection gets no p_user_id fallback ─────────────────
SELECT tap.logout();
SELECT throws_ok(
  $$ SELECT public.ensure_transfer_exists(tap.listing_a(), tap.buyer()) $$,
  'P0001', 'Unable to identify caller. Ensure the request is authenticated.',
  'tap.logout(): no auth.uid() and not service => p_user_id refused, confirming #7');

SELECT * FROM finish();
ROLLBACK;
