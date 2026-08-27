-- ============================================================================
-- 080_admin.sql — the admin allowlist is unreachable from any client role:
-- no self-promotion, no enumeration, is_admin() is service-surface only
-- (033/067), and the risk/laundering tables stay closed. TRUNCATE (which RLS
-- never governs) is revoked from client roles (063).
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);
SELECT tap.seed_core();

-- ── admin_users: fully invisible to clients ─────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT throws_ok(
  $$ INSERT INTO public.admin_users (user_id, label) VALUES (tap.buyer(), 'me') $$,
  '42501', NULL, 'no admin self-grant (REVOKE ALL, 033)');
SELECT throws_ok($$ SELECT * FROM public.admin_users $$,
  '42501', NULL, 'clients cannot enumerate admins');
SELECT throws_ok($$ UPDATE public.admin_users SET label = 'x' $$,
  '42501', NULL, 'clients cannot update admin rows');
SELECT throws_ok($$ DELETE FROM public.admin_users $$,
  '42501', NULL, 'clients cannot delete admin rows');

-- ── is_admin(): EXECUTE stripped from clients (067); semantics intact ───────
SELECT tap.logout();
SELECT ok(NOT has_function_privilege('anon',          'public.is_admin()', 'EXECUTE'), 'anon: no EXECUTE is_admin()');
SELECT ok(NOT has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE'), 'authenticated: no EXECUTE is_admin() (067)');
SELECT ok(NOT has_function_privilege('anon',          'public.request_is_service_role()', 'EXECUTE')
      AND NOT has_function_privilege('authenticated', 'public.request_is_service_role()', 'EXECUTE'),
  'clients cannot probe request_is_service_role() (067)');

-- Called on the service surface, is_admin() answers for the claims subject.
SELECT tap.set_claims(tap.buyer());
SELECT is(public.is_admin(), false, 'is_admin() = false for a normal user');
SELECT tap.set_claims(tap.admin_user());
SELECT is(public.is_admin(), true,  'is_admin() = true for the allowlisted admin');
SELECT tap.logout();

-- ── Risk / laundering surfaces stay closed to clients ───────────────────────
SELECT tap.login(tap.buyer());
SELECT is_empty($$ SELECT * FROM public.seller_risk_scores $$,
  'seller_risk_scores unreadable (RLS deny-all)');
SELECT throws_ok(
  $$ INSERT INTO public.seller_risk_scores (seller_id) VALUES (tap.buyer()) $$,
  '42501', NULL, 'cannot launder own risk score (no policy)');
SELECT is_empty($$ SELECT * FROM public.payout_decisions $$,
  'payout_decisions unreadable (RLS deny-all)');
SELECT is_empty($$ SELECT * FROM public.payout_policy $$,
  'payout_policy thresholds unreadable (RLS deny-all)');
SELECT throws_ok(
  $$ SELECT * FROM public.auth_audit_sweep_state $$,
  '42501', NULL, 'auth sweep state unreadable (explicit REVOKE, 060)');

-- ── 063: TRUNCATE/REFERENCES/TRIGGER stripped (RLS does not govern them) ────
SELECT tap.logout();
SELECT ok(NOT (SELECT bool_or(
                 has_table_privilege(r, 'public.' || t, 'TRUNCATE')
              OR has_table_privilege(r, 'public.' || t, 'REFERENCES')
              OR has_table_privilege(r, 'public.' || t, 'TRIGGER'))
             FROM unnest(ARRAY['anon','authenticated']) roles(r)
             CROSS JOIN unnest(ARRAY['payments','transfers','listings','bids',
                                     'profiles','disputes']) tabs(t)),
  'no client role holds TRUNCATE/REFERENCES/TRIGGER on any core table (063)');

-- Direct probe: the RLS bypass everyone forgets.
SELECT tap.login(tap.buyer());
SELECT throws_ok($$ TRUNCATE public.payments $$,
  '42501', NULL, 'client TRUNCATE of payments denied outright');

SELECT tap.logout();
SELECT * FROM finish();
ROLLBACK;
