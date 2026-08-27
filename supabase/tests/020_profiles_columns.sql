-- ============================================================================
-- 020_profiles_columns.sql — the profiles read boundary is COLUMN GRANTS, not
-- policies (three permissive USING(true) SELECT policies remain by design).
-- Pins 052 (anon) + 068 (authenticated) SELECT sets, the 041 UPDATE set, and
-- proves the live behavior: private fields deny, get_my_profile() is the only
-- self-read path.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);
SELECT tap.seed_core();

-- ── Grant surface (catalog level, exact sets) ───────────────────────────────
-- (aggregated to a single string: name-type columns carry collation "C",
--  which conflicts with text[] literals inside results_eq's record compare)
-- 1. anon SELECT = exactly the 8 public-safe columns (052).
SELECT is(
  (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
     FROM pg_attribute a
    WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
      AND has_column_privilege('anon', 'public.profiles', a.attname, 'SELECT')),
  'avatar_path,avatar_url,bio,created_at,display_name,id,is_verified_seller,stripe_onboarding_complete',
  'anon SELECT on profiles = exactly the 8 public-safe columns (052)');

-- 2. authenticated SELECT = the same 8 (068 — H-1 residual closed).
SELECT is(
  (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
     FROM pg_attribute a
    WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
      AND has_column_privilege('authenticated', 'public.profiles', a.attname, 'SELECT')),
  'avatar_path,avatar_url,bio,created_at,display_name,id,is_verified_seller,stripe_onboarding_complete',
  'authenticated SELECT on profiles = exactly the 8 public-safe columns (068)');

-- 3. authenticated UPDATE = exactly the 6 self-editable columns (041).
SELECT is(
  (SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
     FROM pg_attribute a
    WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
      AND has_column_privilege('authenticated', 'public.profiles', a.attname, 'UPDATE')),
  'avatar_path,bio,display_name,full_name,phone_number,preferred_neighborhoods',
  'authenticated UPDATE on profiles = exactly the 6 profile-edit columns (041)');

-- 4-6. No INSERT for either client role; no UPDATE at all for anon (041).
SELECT is((SELECT count(*) FROM pg_attribute a
            WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
              AND has_column_privilege('anon', 'public.profiles', a.attname, 'UPDATE')),
  0::bigint, 'anon holds UPDATE on zero profiles columns');
SELECT is((SELECT count(*) FROM pg_attribute a
            WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
              AND has_column_privilege('anon', 'public.profiles', a.attname, 'INSERT')),
  0::bigint, 'anon holds INSERT on zero profiles columns');
SELECT is((SELECT count(*) FROM pg_attribute a
            WHERE a.attrelid = 'public.profiles'::regclass AND a.attnum > 0 AND NOT a.attisdropped
              AND has_column_privilege('authenticated', 'public.profiles', a.attname, 'INSERT')),
  0::bigint, 'authenticated holds INSERT on zero profiles columns (row creation is handle_new_user only)');

-- 7-8. Production-only columns (is_admin, trust_status_override,
-- stripe_connect_status/payouts/charges) are NOT created by the vendored
-- chain — they exist only in the live DB (out-of-band drift; flagged for
-- reconciliation). If a future migration vendors them, they must arrive
-- WITHOUT client grants; the exact-set assertions above already fail on any
-- new granted column, and these two stay meaningful either way.
SELECT ok(
  (SELECT bool_and(
     CASE WHEN a.attname IS NULL THEN true
          ELSE NOT has_column_privilege('anon', 'public.profiles', a.attname, 'SELECT')
     END)
     FROM unnest(ARRAY['is_admin','trust_status_override','stripe_connect_status',
                       'stripe_payouts_enabled','stripe_charges_enabled']) c(col)
     LEFT JOIN pg_attribute a
       ON a.attrelid = 'public.profiles'::regclass AND a.attname = c.col AND NOT a.attisdropped),
  'anon: no SELECT on any admin/trust/stripe-status column (if vendored)');
SELECT ok(
  (SELECT bool_and(
     CASE WHEN a.attname IS NULL THEN true
          ELSE NOT has_column_privilege('authenticated', 'public.profiles', a.attname, 'SELECT')
     END)
     FROM unnest(ARRAY['is_admin','trust_status_override','stripe_connect_status',
                       'stripe_payouts_enabled','stripe_charges_enabled']) c(col)
     LEFT JOIN pg_attribute a
       ON a.attrelid = 'public.profiles'::regclass AND a.attname = c.col AND NOT a.attisdropped),
  'authenticated: no SELECT on any admin/trust/stripe-status column (if vendored)');

-- ── Live behavior: anon ─────────────────────────────────────────────────────
SELECT tap.login_anon();

SELECT lives_ok(
  $$ SELECT display_name, avatar_path, is_verified_seller FROM public.profiles $$,
  'anon can read the public-safe columns');
SELECT throws_ok(
  $$ SELECT full_name FROM public.profiles $$,
  '42501', NULL, 'anon reading full_name denied (42501)');
SELECT throws_ok(
  $$ SELECT phone_number FROM public.profiles $$,
  '42501', NULL, 'anon reading phone_number denied (42501)');
SELECT throws_ok(
  $$ SELECT wallet_balance FROM public.profiles $$,
  '42501', NULL, 'anon reading wallet_balance denied (42501)');

-- ── Live behavior: authenticated cross-user reads ───────────────────────────
SELECT tap.logout();
SELECT tap.login(tap.buyer());

SELECT throws_ok(
  $$ SELECT full_name FROM public.profiles WHERE id = tap.seller() $$,
  '42501', NULL, 'signed-in user cannot read another user''s full_name');
SELECT throws_ok(
  $$ SELECT phone_number FROM public.profiles WHERE id = tap.seller() $$,
  '42501', NULL, 'signed-in user cannot read another user''s phone_number');
SELECT throws_ok(
  $$ SELECT stripe_connect_id FROM public.profiles WHERE id = tap.buyer() $$,
  '42501', NULL, 'column grants also block direct self-reads of private fields (by design — RPC is the path)');
SELECT results_eq(
  $$ SELECT display_name FROM public.profiles WHERE id = tap.seller() $$,
  ARRAY['Seller S'::text],
  'signed-in user CAN read another user''s public-safe columns');

-- ── get_my_profile(): the sanctioned self-read (042) ────────────────────────
SELECT results_eq(
  $$ SELECT id FROM public.get_my_profile() $$,
  ARRAY['22222222-2222-2222-2222-222222222222'::uuid],
  'get_my_profile() returns exactly the caller''s row');
SELECT results_eq(
  $$ SELECT full_name FROM public.get_my_profile() $$,
  ARRAY['BUYER PRIVATE'::text],
  'get_my_profile() exposes the caller''s own private fields');

SELECT tap.logout();
SELECT ok(NOT has_function_privilege('anon', 'public.get_my_profile()', 'EXECUTE'),
  'anon holds no EXECUTE on get_my_profile()');

-- Claims say authenticated but carry no sub -> explicit raise, not empty set.
SELECT set_config('request.jwt.claims', '{"role":"authenticated"}', true);
SELECT throws_ok(
  $$ SELECT * FROM public.get_my_profile() $$,
  'P0001', 'get_my_profile() requires an authenticated caller',
  'get_my_profile() raises for a caller with no sub claim');

SELECT * FROM finish();
ROLLBACK;
