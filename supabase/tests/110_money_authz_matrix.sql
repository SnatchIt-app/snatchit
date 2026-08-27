-- ============================================================================
-- 110_money_authz_matrix.sql — MONEY-1.
--
-- 005_service_path.sql pins the CLAIM shapes request_is_service_role() (0550)
-- accepts. This file pins the shapes 005 does not cover — the legacy SINGULAR
-- GUC, disagreeing claims, malformed claims, and the SQL role — and then pins
-- the reason the helper's weakness is not reachable from a client.
--
-- WHY THIS FILE EXISTS
-- Migration 071 replaced guard_proof_status() because it keyed on
-- `request.jwt.claim.role` — the LEGACY SINGULAR PostgREST GUC — and its header
-- records (point 4) that request_is_service_role() was deliberately NOT reused
-- because it "reads the legacy singular GUC first, grants on the claim alone
-- without checking the SQL role, and treats a NULL claims GUC as trusted".
-- That is an accurate description of the live 0550 definition. This file makes
-- all three properties EXECUTABLE, so they cannot silently get worse, and pins
-- the two facts that currently stop them becoming an exploit:
--
--   (a) auth.uid() is non-NULL for every PostgREST-authenticated caller, so the
--       `IF v_caller_id IS NULL AND request_is_service_role()` branch — the one
--       that substitutes p_user_id for the caller's identity — is never even
--       evaluated for a signed-in client. Assertions 13-17.
--   (b) `request.jwt.claims` is never NULL inside a PostgREST request, because
--       PostgREST issues set_config('request.jwt.claims', $3, true)
--       unconditionally on every request, and set_config(name, NULL, true)
--       CREATES the GUC as '' rather than leaving it NULL. Assertion 3.
--       This is what makes the fail-open branch unreachable over HTTP. If a
--       future PostgreSQL changes that set_config semantic, assertion 3 fails
--       and the whole safety argument for the fail-open branch must be redone.
--
-- ORDERING RULE (same as 005): assertions 1-2 can only be made in a session
-- where request.jwt.claims has never been assigned. set_config() creates the
-- placeholder permanently for the session (RESET restores '' — never NULL
-- again). pg_prove opens one psql per file, which is what makes them hold.
-- Nothing before assertion 3 may touch a request.jwt.* GUC.
--
-- NOT a money-movement test: it tests the authorization boundary only. No
-- assertion here completes a payout, transfer or refund.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ── 1-2: fresh session — neither GUC has ever been assigned ─────────────────
SELECT ok(current_setting('request.jwt.claims', true) IS NULL,
  'fresh session: request.jwt.claims never assigned (pg_prove = one psql per file)');
SELECT ok(current_setting('request.jwt.claim.role', true) IS NULL,
  'fresh session: the legacy SINGULAR request.jwt.claim.role is also unassigned');

-- ── 3: the set_config semantic the whole "unreachable over HTTP" claim rests
--       on. Measured on production 2026-08-27; pinned here so a PostgreSQL
--       upgrade that changes it breaks the build instead of the marketplace.
SELECT set_config('money1.probe', NULL, true);
SELECT is(current_setting('money1.probe', true), '',
  'set_config(name, NULL, true) CREATES the GUC as '''' — never leaves it NULL '
  '(so PostgREST''s unconditional claims setter makes the 0550 fail-open branch unreachable over HTTP)');

SELECT tap.seed_core();

-- ── 4-6: the LEGACY SINGULAR GUC decides, and a claim alone grants ──────────
-- 071 point 4, first and second properties, made executable.
SELECT tap.set_claims(tap.other_user(), 'authenticated');
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok(public.request_is_service_role(),
  'WEAKNESS PINNED: a forged legacy SINGULAR claim role=service_role grants the service path '
  'even though the plural claims say authenticated and current_user is not service_role');

SELECT set_config('request.jwt.claim.role', '', true);
SELECT ok(NOT public.request_is_service_role(),
  'clearing only the singular GUC flips the same session back to denied — proving #4 was the singular GUC');

SELECT set_config('request.jwt.claim.role', 'authenticated', true);
SELECT set_config('request.jwt.claims', '{"role":"service_role"}', true);
SELECT ok(NOT public.request_is_service_role(),
  'disagreeing claims: the SINGULAR GUC wins in BOTH directions — a singular authenticated '
  'claim masks a plural service_role claim');

-- ── 7-8: malformed and empty claims fail CLOSED ─────────────────────────────
SELECT set_config('request.jwt.claim.role', '', true);
SELECT set_config('request.jwt.claims', 'not-json{', true);
SELECT ok(NOT public.request_is_service_role(),
  'unparseable plural claims fail closed (the jsonb cast raises, and the raw GUC is non-NULL '
  'so the fail-open branch cannot fire)');

SELECT set_config('request.jwt.claims', '', true);
SELECT ok(NOT public.request_is_service_role(),
  'both GUCs empty-string: '''' reads back as '''' not NULL, so the fail-open branch is not reached');

-- ── 9-10: the helper never consults the SQL role ────────────────────────────
-- 071 point 4, third property. 071's ALLOW-1 requires current_user to actually
-- BE service_role and lets a claim only contradict; 0550 does the exact
-- inverse — which is also why `SET ROLE service_role` does not help an attacker
-- here, and why a genuine service_role SQL session with client claims is denied.
SELECT tap.set_claims(tap.other_user(), 'authenticated');
SELECT set_config('role', 'service_role', true);
SELECT is(current_user::text, 'service_role',
  'SET ROLE service_role succeeded (authenticator is a member of service_role — see report MONEY-1)');
SELECT ok(NOT public.request_is_service_role(),
  'current_user = service_role does NOT flip the helper: 0550 reads claims only, never the SQL role '
  '(the exact inverse of 071 ALLOW-1)');
SELECT set_config('role', 'none', true);

-- ── 11-12: the grant posture that keeps the weakness off the public surface ─
SELECT is(
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ILIKE '%request_is_service_role%'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')),
  0::bigint,
  'no function that depends on request_is_service_role() is executable by anon (0552/067)');
SELECT is(
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND pg_get_functiondef(p.oid) ILIKE '%request_is_service_role%'
      AND p.proacl IS NULL),
  0::bigint,
  'every request_is_service_role() dependant carries an explicit ACL — none is left on the default PUBLIC EXECUTE');

-- ── 13-14: THE VERDICT. The helper can be fooled; the RPC still holds. ──────
-- A signed-in attacker forges the singular GUC. The helper is fooled (13) — but
-- auth.uid() is non-NULL, so `IF v_caller_id IS NULL AND ...` short-circuits and
-- the helper is never consulted (14). This pair is the whole reason MONEY-1 is
-- NOT EXPLOITABLE. If 14 ever fails, p_user_id is an identity-forgery parameter
-- across every money RPC and this is a live impersonation hole.
SELECT tap.set_claims(tap.other_user(), 'authenticated');
SELECT set_config('request.jwt.claim.role', 'service_role', true);
SELECT ok(public.request_is_service_role() AND auth.uid() = tap.other_user(),
  'attacker session: helper fooled by the forged singular GUC, but auth.uid() still resolves to the attacker');
SELECT set_config('role', 'authenticated', true);
SELECT throws_ok(
  $$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.seller()) $$,
  'P0001', 'Only the seller can mark a transfer as sent.',
  'forged singular GUC + forged p_user_id: mark_transfer_sent STILL refuses — auth.uid() short-circuits the service path');

-- ── 15-17: forged p_user_id refused across the other money RPCs ────────────
SELECT throws_ok(
  $$ SELECT public.confirm_transfer_received(tap.transfer_b(), tap.buyer()) $$,
  'P0001', 'Only the buyer can confirm transfer receipt.',
  'forged p_user_id: confirm_transfer_received refuses (payout release cannot be triggered for another user)');
SELECT throws_ok(
  $$ SELECT public.cancel_listing(tap.listing_a(), tap.seller()) $$,
  'P0001', 'You can only cancel your own listings.',
  'forged p_user_id: cancel_listing refuses');
SELECT throws_ok(
  $$ SELECT public.mark_listing_sold(tap.listing_a(), tap.seller()) $$,
  'P0001', 'This listing is not reserved by you.',
  'forged p_user_id: mark_listing_sold refuses');

SELECT * FROM finish();
ROLLBACK;
