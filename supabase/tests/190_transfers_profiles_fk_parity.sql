-- ============================================================================
-- 190_transfers_profiles_fk_parity.sql — migration 122 (transfers↔profiles FK).
--   (187 my_tickets_read = release candidate; 188 venue_api = venue slice 1;
--    189 manifest signing context = PR #58. 190 is the next free number.)
--
-- Asserts the SHAPE production carries, read read-only on 2026-09-10:
--   buyer_id / seller_id -> public.profiles(id), NO ACTION on update and
--   delete, MATCH SIMPLE, VALIDATED, NOT DEFERRABLE, original constraint names.
-- The FK is what PostgREST resolves an embed through, so asserting it is the
-- testable proxy for `profiles!seller_id` / `profiles!buyer_id` resolving. The
-- definitive end-to-end proof is the HTTP check in the application plan.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(15);

-- A. both constraints exist under their production names and target profiles
SELECT is((SELECT (SELECT relname FROM pg_class WHERE oid = c.confrelid)
             FROM pg_constraint c
            WHERE c.conrelid = 'public.transfers'::regclass AND c.conname = 'transfers_buyer_id_fkey'),
          'profiles', 'A1: transfers_buyer_id_fkey references profiles');
SELECT is((SELECT (SELECT relname FROM pg_class WHERE oid = c.confrelid)
             FROM pg_constraint c
            WHERE c.conrelid = 'public.transfers'::regclass AND c.conname = 'transfers_seller_id_fkey'),
          'profiles', 'A2: transfers_seller_id_fkey references profiles');
SELECT is((SELECT (SELECT nspname FROM pg_namespace n JOIN pg_class r ON r.relnamespace = n.oid WHERE r.oid = c.confrelid)
             FROM pg_constraint c
            WHERE c.conrelid = 'public.transfers'::regclass AND c.conname = 'transfers_buyer_id_fkey'),
          'public', 'A3: …in the public schema, not auth');

-- B. exact behaviour production carries
SELECT is((SELECT c.confupdtype::text FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass AND c.conname='transfers_buyer_id_fkey'), 'a',
          'B1: buyer FK is ON UPDATE NO ACTION');
SELECT is((SELECT c.confdeltype::text FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass AND c.conname='transfers_buyer_id_fkey'), 'a',
          'B2: buyer FK is ON DELETE NO ACTION');
SELECT is((SELECT c.confupdtype::text FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass AND c.conname='transfers_seller_id_fkey'), 'a',
          'B3: seller FK is ON UPDATE NO ACTION');
SELECT is((SELECT c.confdeltype::text FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass AND c.conname='transfers_seller_id_fkey'), 'a',
          'B4: seller FK is ON DELETE NO ACTION');
SELECT ok((SELECT bool_and(c.confmatchtype = 's' AND c.convalidated AND NOT c.condeferrable AND NOT c.condeferred)
             FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass
              AND c.conname IN ('transfers_buyer_id_fkey','transfers_seller_id_fkey')),
          'B5: both are MATCH SIMPLE, VALIDATED, NOT DEFERRABLE');

-- C. nothing else moved
SELECT is((SELECT (SELECT nspname FROM pg_namespace n JOIN pg_class r ON r.relnamespace=n.oid WHERE r.oid=c.confrelid)
             FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass AND c.conname='transfers_dispute_resolved_by_fkey'),
          'auth', 'C1: dispute_resolved_by still references auth.users, as production does');
SELECT is((SELECT count(*)::int FROM pg_constraint c
            WHERE c.conrelid='public.transfers'::regclass AND c.contype='f'), 5,
          'C2: transfers still has exactly five foreign keys');
SELECT is((SELECT count(*)::int FROM pg_policy pol WHERE pol.polrelid='public.transfers'::regclass), 5,
          'C3: all five transfers RLS policies survive the constraint change');
SELECT ok((SELECT bool_and(x.present) FROM (VALUES
            ('transfers: buyer select'), ('transfers: seller select'),
            ('Buyers can view own transfers'), ('Sellers can view own transfers'),
            ('Users can view their transfers')
          ) AS n(nm), LATERAL (SELECT EXISTS (
            SELECT 1 FROM pg_policy pol WHERE pol.polrelid='public.transfers'::regclass AND pol.polname = n.nm)) AS x(present)),
          'C3b: each named access-control policy is still present');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.transfers'::regclass),
          'C4: row level security is still enabled on transfers');

-- D. the data the FK now guarantees.
--    NOTE: a negative test ("insert a transfer whose seller has no profile and
--    expect 23503") is deliberately NOT here. transfers.listing_id is NOT NULL,
--    so such an insert fails on 23502 before the foreign key is ever consulted,
--    and seeding a valid listing runs into guard_listing_insert_columns in this
--    harness. A test that raises the wrong error while claiming to prove the FK
--    is worse than no test. The FK's existence and exact shape are asserted from
--    the catalog above; that it makes the PostgREST embed resolve is proven
--    end-to-end by the HTTP check in the sandbox application plan.
SELECT is((SELECT count(*)::int FROM public.transfers t
            WHERE t.buyer_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = t.buyer_id)), 0,
          'D1: no transfer references a buyer without a profile');
SELECT is((SELECT count(*)::int FROM public.transfers t
            WHERE t.seller_id IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = t.seller_id)), 0,
          'D2: no transfer references a seller without a profile');

SELECT finish();
ROLLBACK;
