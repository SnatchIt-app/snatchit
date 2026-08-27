-- ============================================================================
-- 130_privilege_cleanup.sql — migration 074.
--
-- Part 1 (SEC-1): public.webhook_retries must carry NO client DML.
-- Part 2: the five functions migration 067 missed must carry no PUBLIC EXECUTE,
--         the three trigger functions among them must carry no anon /
--         authenticated EXECUTE either, and the two read-only helpers must KEEP
--         the anon / authenticated EXECUTE that 0230 granted and 063
--         deliberately retained.
--
-- WHAT EACH HALF OF THIS FILE ACTUALLY PROVES — stated up front, because the
-- two halves are NOT equally strong and pretending otherwise is how a suite
-- goes vacuously green:
--
--   PART 2 IS DISCRIMINATING. Nothing in the migration chain before 074 removes
--   the Postgres default `=X/postgres` from these five functions, so on a fresh
--   replay WITHOUT 074 the B-section assertions fail. Verified by running this
--   file in CI against a chain that did not yet contain 074 (the RED run
--   recorded in the PR): B1-B5, B7 and B8 failed, everything else passed.
--
--   PART 1 IS NOT DISCRIMINATING IN CI, AND CANNOT BE. Migration 069 line 22
--   already contains the identical revoke, and on a fresh replay 069 EXECUTES.
--   074 exists because production's 069 ledger row was written by a repair
--   without executing its statements, so the grants survived there. In CI the A
--   assertions therefore hold both with and without 074. They are an invariant
--   lock, not a proof of 074's effect. The proof for production is the
--   post-apply verification query in the migration header, run against the live
--   catalog. Do not read a green A section as evidence that 074 changed
--   anything here.
--
-- The A section is also careful about a second confusion the brief for this
-- work called out: on a deny-all-RLS table, "the grant is gone" and "access is
-- blocked" are DIFFERENT claims that a naive test conflates. A1-A5 are the
-- grant claim (privilege denial, error 42501, raised before RLS is ever
-- consulted). A8 is the RLS claim, and it is proved INDEPENDENTLY by handing
-- anon the SELECT privilege inside this transaction and showing it still reads
-- nothing. The GRANT dies with the ROLLBACK.
--
-- Not re-proved here, deliberately:
--   * dispute_resolutions_append_only() still firing — 070_payouts.sql already
--     asserts the P0001 append-only rejection, and it runs against this same
--     post-074 database. Duplicating its dispute fixture here would add
--     fragility, not proof. D4 asserts the trigger is still attached and
--     enabled; 070 asserts it still bites.
--   * public.set_ambassador_application_updated_at() — deliberately OUT of 074
--     (it is created by a timestamp-scheme migration that sorts AFTER '074', so
--     an unguarded revoke would abort a fresh replay). It still carries PUBLIC
--     EXECUTE by design until its own migration lands; asserting otherwise here
--     would fail the suite for a defect this migration does not claim to fix.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(24);
SELECT tap.seed_core();

-- ════════════════════════════════════════════════════════════════════════════
-- A. SEC-1 — public.webhook_retries carries no client privilege
-- ════════════════════════════════════════════════════════════════════════════

-- A1-A3: the GRANT claim, read straight from the catalog.
SELECT ok(NOT (has_table_privilege('anon', 'public.webhook_retries', 'SELECT')
             OR has_table_privilege('anon', 'public.webhook_retries', 'INSERT')
             OR has_table_privilege('anon', 'public.webhook_retries', 'UPDATE')
             OR has_table_privilege('anon', 'public.webhook_retries', 'DELETE')),
  'webhook_retries: anon holds no SELECT/INSERT/UPDATE/DELETE (069 line 22, enforced by 074)');

SELECT ok(NOT (has_table_privilege('authenticated', 'public.webhook_retries', 'SELECT')
             OR has_table_privilege('authenticated', 'public.webhook_retries', 'INSERT')
             OR has_table_privilege('authenticated', 'public.webhook_retries', 'UPDATE')
             OR has_table_privilege('authenticated', 'public.webhook_retries', 'DELETE')),
  'webhook_retries: authenticated holds no SELECT/INSERT/UPDATE/DELETE');

SELECT ok(has_table_privilege('service_role', 'public.webhook_retries', 'SELECT')
      AND has_table_privilege('service_role', 'public.webhook_retries', 'INSERT')
      AND has_table_privilege('service_role', 'public.webhook_retries', 'UPDATE')
      AND has_table_privilege('service_role', 'public.webhook_retries', 'DELETE'),
  'webhook_retries: service_role KEEPS full DML — 074 must not touch the stripe-webhook writer');

-- A4-A5: the same claim behaviourally. 42501 is insufficient_privilege — the
-- GRANT layer refusing, decided before any RLS policy is consulted.
SELECT tap.login_anon();
SELECT throws_ok($$ SELECT * FROM public.webhook_retries $$,
  '42501', NULL, 'anon read of webhook_retries is refused at the privilege layer (42501)');
SELECT tap.logout();

SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ INSERT INTO public.webhook_retries (rpc_name) VALUES ('forged') $$,
  '42501', NULL, 'authenticated cannot forge a retry row — write path refused at the privilege layer');
SELECT tap.logout();

-- A6-A7: the positive path. The stripe-webhook Edge Function records failed
-- handler RPCs as service_role; that must still work after the revoke.
SELECT tap.login_service();
SELECT lives_ok(
  $$ INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message)
     VALUES (tap.payment_a(), tap.listing_a(), 'complete_auction_payment', '074 fixture') $$,
  'positive: service_role can still record a webhook retry (the only real writer)');
SELECT is((SELECT count(*) FROM public.webhook_retries), 1::bigint,
  'positive: service_role reads its own retry row back (BYPASSRLS service path intact)');
SELECT tap.logout();

-- A8: the OTHER layer, proved on its own. Hand anon the SELECT privilege that
-- 074 removed and show the deny-all RLS still returns nothing — so the two
-- controls are genuinely independent, not one control counted twice. The GRANT
-- is transaction-local and dies with the ROLLBACK at the end of this file.
GRANT SELECT ON TABLE public.webhook_retries TO anon;
SELECT tap.login_anon();
SELECT is((SELECT count(*) FROM public.webhook_retries), 0::bigint,
  'second layer, independently: even WITH SELECT granted, anon reads 0 of 1 rows — RLS is deny-all');
SELECT tap.logout();
REVOKE SELECT ON TABLE public.webhook_retries FROM anon;

-- ════════════════════════════════════════════════════════════════════════════
-- B. EXECUTE cleanup — the PUBLIC grant 067 left behind on five functions
-- ════════════════════════════════════════════════════════════════════════════
-- grantee = 0 in aclexplode() is PUBLIC. coalesce(proacl, acldefault(...))
-- matters: a NULL proacl means "Postgres defaults", which INCLUDE PUBLIC
-- EXECUTE, so testing the raw column would report a clean sheet for the exact
-- state this migration exists to remove.

SELECT ok(NOT EXISTS (
    SELECT 1 FROM pg_proc p,
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = 'public.dispute_resolutions_append_only()'::regprocedure
       AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'dispute_resolutions_append_only(): PUBLIC EXECUTE removed (074)');

SELECT ok(NOT EXISTS (
    SELECT 1 FROM pg_proc p,
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = 'public.guard_transfer_state_columns()'::regprocedure
       AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'guard_transfer_state_columns(): PUBLIC EXECUTE removed (074)');

SELECT ok(NOT EXISTS (
    SELECT 1 FROM pg_proc p,
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = 'public.reset_transfer_guard_bypass()'::regprocedure
       AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'reset_transfer_guard_bypass(): PUBLIC EXECUTE removed (074)');

SELECT ok(NOT EXISTS (
    SELECT 1 FROM pg_proc p,
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = 'public.is_blocked_by_me(uuid)'::regprocedure
       AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'is_blocked_by_me(uuid): PUBLIC EXECUTE removed (074) — anon/authenticated checked separately below');

SELECT ok(NOT EXISTS (
    SELECT 1 FROM pg_proc p,
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = 'public.is_winner(uuid,uuid)'::regprocedure
       AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'is_winner(uuid,uuid): PUBLIC EXECUTE removed (074) — anon/authenticated checked separately below');

-- B6-B7: the same claim through a role instead of the catalog. `authenticator`
-- is the PostgREST connection role: NOINHERIT, and holding no explicit grant on
-- these functions, so the ONLY EXECUTE it can have is the ambient PUBLIC one.
-- B6 is the control that keeps B7 from being vacuous — it proves the probe
-- returns TRUE when a PUBLIC EXECUTE really is present.
SELECT ok(has_function_privilege('authenticator', 'pg_catalog.upper(text)', 'EXECUTE'),
  'probe control: authenticator CAN execute a genuinely PUBLIC function — a false B7 means something');

SELECT ok(NOT (has_function_privilege('authenticator', 'public.dispute_resolutions_append_only()', 'EXECUTE')
             OR has_function_privilege('authenticator', 'public.guard_transfer_state_columns()',    'EXECUTE')
             OR has_function_privilege('authenticator', 'public.reset_transfer_guard_bypass()',     'EXECUTE')),
  'authenticator has lost its ambient PUBLIC EXECUTE on all three trigger functions');

-- B8: the explicit anon / authenticated grants are gone too. Revoking only
-- PUBLIC would have left these standing — that is the exact trap 067 recorded
-- ("a bare REVOKE FROM PUBLIC left notify_bid_placed and phone_verified still
-- anon-executable").
SELECT ok(NOT (has_function_privilege('anon',          'public.dispute_resolutions_append_only()', 'EXECUTE')
             OR has_function_privilege('authenticated','public.dispute_resolutions_append_only()', 'EXECUTE')
             OR has_function_privilege('anon',          'public.guard_transfer_state_columns()',   'EXECUTE')
             OR has_function_privilege('authenticated','public.guard_transfer_state_columns()',    'EXECUTE')
             OR has_function_privilege('anon',          'public.reset_transfer_guard_bypass()',    'EXECUTE')
             OR has_function_privilege('authenticated','public.reset_transfer_guard_bypass()',     'EXECUTE')),
  'neither client role can execute any of the three trigger functions (067 Group A treatment)');

-- ════════════════════════════════════════════════════════════════════════════
-- C. What 074 must NOT have taken away
-- ════════════════════════════════════════════════════════════════════════════
-- 0230 granted both helpers to authenticated + anon, and 063 lines 44-46 record
-- keeping them as a deliberate decision ("read-only helpers anon legitimately
-- needs while browsing signed-out"). 074 removes PUBLIC and nothing else here.
-- If a later change wires is_blocked_by_me into the listings feed policy as 0230
-- intended, authenticated MUST still hold EXECUTE — these two assertions are
-- what stops a future cleanup from quietly breaking that.

SELECT ok(has_function_privilege('anon',          'public.is_blocked_by_me(uuid)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'public.is_blocked_by_me(uuid)', 'EXECUTE'),
  'is_blocked_by_me: anon + authenticated KEEP EXECUTE (0230 grant / 063 retention survive 074)');

SELECT ok(has_function_privilege('anon',          'public.is_winner(uuid,uuid)', 'EXECUTE')
      AND has_function_privilege('authenticated', 'public.is_winner(uuid,uuid)', 'EXECUTE'),
  'is_winner: anon + authenticated KEEP EXECUTE (063 retention survives 074)');

SELECT tap.login_anon();
SELECT is(public.is_winner(tap.listing_a(), tap.buyer()), false,
  'positive: a signed-out browser can still EVALUATE is_winner() after the PUBLIC revoke');
SELECT tap.logout();

SELECT tap.login(tap.buyer());
SELECT is(public.is_blocked_by_me(tap.seller()), false,
  'positive: a signed-in client can still EVALUATE is_blocked_by_me() after the PUBLIC revoke');
SELECT tap.logout();

-- ════════════════════════════════════════════════════════════════════════════
-- D. The trigger functions still fire with EXECUTE revoked
-- ════════════════════════════════════════════════════════════════════════════
-- This is the whole regression argument for Group A, exercised rather than
-- asserted: PostgreSQL checks EXECUTE on a trigger function at CREATE TRIGGER
-- time, never when the trigger fires. If that were wrong, the revoke above
-- would have silently disarmed transfer custody — the most expensive failure
-- mode in this database — and D1 would pass trivially instead of raising.

SELECT tap.reset_guards();
SELECT throws_ok(
  $$ UPDATE public.transfers SET payout_released_at = now() WHERE id = tap.transfer_a() $$,
  'P0001', 'Cannot directly modify transfer state columns. Use the appropriate RPC.',
  'guard_transfer_state_columns() still fires after its EXECUTE was revoked (custody intact)');

SELECT tap.login(tap.seller());
SELECT lives_ok(
  $$ SELECT public.mark_transfer_sent(tap.transfer_a(), tap.seller()) $$,
  'positive: the sanctioned RPC path still advances the transfer through the same guard');

SELECT is(current_setting('app.bypass_transfer_guard', true), 'off',
  'reset_transfer_guard_bypass() still fires — the RPC bypass window was closed by the statement trigger');
SELECT tap.logout();

SELECT is((SELECT count(*) FROM pg_trigger t
             JOIN pg_proc p      ON p.oid = t.tgfoid
             JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE NOT t.tgisinternal
              AND n.nspname = 'public'
              AND t.tgenabled = 'O'
              AND p.proname IN ('dispute_resolutions_append_only',
                                'guard_transfer_state_columns',
                                'reset_transfer_guard_bypass')),
  3::bigint,
  'all three triggers remain attached and enabled — 074 revoked privileges, it detached nothing');

SELECT * FROM finish();
ROLLBACK;
