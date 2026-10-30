-- 209_payments_amount_refunded_cents.sql — pgTAP for migration 142.
--
-- What 142 promises, as assertions:
--   S1-S4  the column exists with exactly 20260906120000's shape: integer,
--          nullable, no default (so either migration may apply first);
--   S5     payments carries no column-level ACL, the premise behind "grants do
--          not move" — the table-level SELECT covers the new column;
--   S6     authenticated can SELECT the column;
--   B1     checkout's exact select list (CheckoutNative.tsx:228/:595) resolves
--          for the buyer under RLS — the 42703 that D's column break returned;
--   B2     an existing payment reads NULL (never backfilled);
--   B3     another user sees none of the buyer's rows;
--   B4     the buyer cannot write the column on their own row;
--   B5     anon sees nothing.
--
-- VERSION-AGNOSTIC: the full chain also carries 20260906120000, which declares
-- the same column; every assertion holds with or without it. That also means
-- this suite CANNOT tell 142 from 20260906120000 on the full chain — its
-- negative control runs on the production shape without either (see the
-- rehearsal record in docs/release/GO_NO_GO_PRODUCTION_8f45e9b_20260918.md §12).
--
-- MEASURED 2026-09-18 on the production shape (ledger 135, synthetic rows):
--   without 142 ... S1 S2 S3 S4 fail; S6 errors (42703) and aborts the file
--   with 142 ...... 11/11
--   full chain .... 11/11 (with 20260906120000 also declaring the column)
BEGIN;
SELECT plan(11);
SELECT tap.seed_core();

CREATE FUNCTION tap._try209(stmt text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE stmt; RETURN 'ran'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ' ' || SQLERRM; END $$;

-- ── Shape ────────────────────────────────────────────────────────────────────
SELECT has_column('public', 'payments', 'amount_refunded_cents', 'S1: payments.amount_refunded_cents exists');
SELECT col_type_is('public', 'payments', 'amount_refunded_cents', 'integer', 'S2: it is integer (20260906120000:306 shape)');
SELECT col_is_null('public', 'payments', 'amount_refunded_cents', 'S3: it is nullable — NULL means the amount is unknown');
SELECT col_hasnt_default('public', 'payments', 'amount_refunded_cents', 'S4: it has no default — nothing is invented for existing rows');
SELECT is((SELECT count(*)::int FROM pg_attribute
            WHERE attrelid = 'public.payments'::regclass AND attnum > 0
              AND NOT attisdropped AND attacl IS NOT NULL),
          0, 'S5: payments has no column-level ACL, so the table-level grants cover the new column');
SELECT ok(has_column_privilege('authenticated', 'public.payments', 'amount_refunded_cents', 'SELECT'),
          'S6: authenticated may SELECT the column');

-- ── Buyer, through RLS ───────────────────────────────────────────────────────
SELECT tap.login(tap.buyer());
SELECT lives_ok(
  $$ SELECT status, refunded_at, amount_refunded_cents, total FROM public.payments
      WHERE listing_id = tap.listing_a() AND buyer_id = tap.buyer()
        AND status IN ('succeeded', 'refunded') LIMIT 5 $$,
  'B1: checkout''s settled-payment select list resolves for the buyer');
SELECT is((SELECT count(*)::int FROM public.payments
            WHERE id = tap.payment_a() AND amount_refunded_cents IS NULL),
          1, 'B2: the buyer''s existing payment reads amount NULL (not backfilled)');
SELECT tap._try209($$ UPDATE public.payments SET amount_refunded_cents = 11000 WHERE id = tap.payment_a() $$) AS b4_update_attempt;
SELECT tap.logout();
SELECT is((SELECT amount_refunded_cents FROM public.payments WHERE id = tap.payment_a()),
          NULL::int, 'B4: the buyer''s attempted write left the amount NULL');

SELECT tap.login(tap.other_user());
SELECT is((SELECT count(*)::int FROM public.payments WHERE buyer_id = tap.buyer()),
          0, 'B3: another user sees none of the buyer''s payments');
SELECT tap.logout();

SELECT tap.login_anon();
SELECT is((SELECT count(*)::int FROM public.payments), 0, 'B5: anon sees no payments');
SELECT tap.logout();

SELECT * FROM finish();
ROLLBACK;
