-- ============================================================================
-- 010_rls_smoke.sql — RLS is on everywhere; deny-all tables have no policies;
-- the client policy surface is pinned so silent policy drift turns CI red.
-- Ground truth: migrations 000/033/044/060/065/069/070.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

-- 1. Every table in public has row level security enabled.
SELECT is_empty(
  $$ SELECT c.relname
       FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity $$,
  'every public table has RLS enabled');

-- 2. Deny-all tables carry ZERO policies (RLS-on + no policy = no client rows;
--    most additionally carry explicit REVOKEs, asserted in 030/080/090).
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'admin_users'),            0::bigint, 'admin_users: zero policies (033)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'rate_limits'),            0::bigint, 'rate_limits: zero policies (005)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'stripe_webhook_events'),  0::bigint, 'stripe_webhook_events: zero policies (025)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'webhook_retries'),        0::bigint, 'webhook_retries: zero policies (069)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'seller_flags'),           0::bigint, 'seller_flags: zero policies (012)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'seller_risk_scores'),     0::bigint, 'seller_risk_scores: zero policies (012)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payout_policy'),          0::bigint, 'payout_policy: zero policies (039)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payout_decisions'),       0::bigint, 'payout_decisions: zero policies (039)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'disputes'),               0::bigint, 'disputes: zero policies (024)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'dispute_resolutions'),    0::bigint, 'dispute_resolutions: zero policies (065)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'auth_audit_sweep_state'), 0::bigint, 'auth_audit_sweep_state: zero policies (060)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'stripe_connect_archive'), 0::bigint, 'stripe_connect_archive: zero policies (044)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transfer_notifications'), 0::bigint, 'transfer_notifications: zero policies (034)');

-- 3. Pin the post-070 client policy surface on the five core tables.
--    070 deliberately reconciled to production's exact (redundant-variant)
--    set; a count change means somebody added/dropped a policy without a
--    reviewed migration.
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'profiles'),  5::bigint, 'profiles: exactly 5 policies (070 reconciliation)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'listings'),  6::bigint, 'listings: exactly 6 policies (070 reconciliation)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'transfers'), 5::bigint, 'transfers: exactly 5 SELECT-only policies (055/070)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bids'),      3::bigint, 'bids: exactly 3 policies (070 reconciliation)');
SELECT is((SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = 'payments'),  2::bigint, 'payments: exactly 2 SELECT-only policies (000)');

-- 4. Transfers and payments have no INSERT/UPDATE/DELETE policy at all —
--    writes are RPC / service-path only.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'public' AND tablename IN ('transfers', 'payments')
        AND cmd <> 'SELECT' $$,
  'transfers/payments: zero non-SELECT policies — client writes impossible via RLS');

SELECT * FROM finish();
ROLLBACK;
