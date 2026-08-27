-- ============================================================================
-- 100_storage.sql — proof-of-ownership documents and ticket-transfer evidence
-- are the most sensitive files the platform holds (screenshots of real tickets,
-- ID-adjacent material). They live in the `proof-docs` bucket, which must stay
-- private and reachable only by the uploader or the counterparty on that
-- transfer. Ground truth: 000 (auction-media), 033 (proof-docs bucket + owner
-- policies), 034 (transfer-party read), 049 (owner delete, unreferenced only),
-- 051 (public read scoped to the two public buckets), 053 (owner writes).
--
-- CATALOG-LEVEL ONLY, deliberately. Asserting behaviour would mean INSERTing
-- into storage.objects, whose column set and INSERT triggers (path_tokens,
-- level, storage.prefixes) differ across storage-api versions — a fixture that
-- errors on a runner upgrade would take the whole gate down. The bucket flag
-- plus the exact policy surface is what actually decides exposure here.
-- ============================================================================
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

-- 1. The bucket exists and is PRIVATE. `public = true` would make every object
--    fetchable by URL with no policy evaluation at all — the single flag that
--    matters most. A missing bucket yields NULL, which is not false, so this
--    also fails if 033 stopped creating it.
SELECT is((SELECT public FROM storage.buckets WHERE id = 'proof-docs'), false,
  'proof-docs bucket exists and is private (033)');

-- 2. No OTHER bucket has quietly become public.
SELECT is_empty(
  $$ SELECT id FROM storage.buckets
      WHERE public AND id NOT IN ('auction-media','avatars') $$,
  'only auction-media and avatars are public buckets');

-- 3. The five proof-docs policies are all present. If one is dropped, the
--    matching operation silently stops working (or, for the read policies,
--    stops being the constraint anyone reasons about).
SELECT is(
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname IN ('proof-docs owner insert',
                         'proof-docs owner read',
                         'proof-docs owner update',
                         'proof-docs transfer party read',
                         'proof-docs owner delete unreferenced')),
  5::bigint, 'all five proof-docs policies present (033/034/049/053)');

-- 4. Exactly two SELECT policies may mention proof-docs, and they are the
--    owner and transfer-party ones. A third — however well-intentioned — is a
--    new read path onto other people's ticket evidence.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd = 'SELECT' AND qual ILIKE '%proof-docs%'
        AND policyname NOT IN ('proof-docs owner read','proof-docs transfer party read') $$,
  'no third SELECT path onto proof-docs');

-- 5. And no anon/public-facing SELECT policy touches it at all.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd = 'SELECT'
        AND roles::text[] && ARRAY['public','anon']
        AND qual ILIKE '%proof-docs%' $$,
  'no anon/public SELECT policy reaches proof-docs (051 scoped its read to the public buckets)');

-- 6. Every SELECT policy on storage.objects is bucket-scoped. An unqualified
--    USING (true) would expose every bucket including proof-docs regardless of
--    the checks above.
SELECT is_empty(
  $$ SELECT policyname FROM pg_policies
      WHERE schemaname = 'storage' AND tablename = 'objects'
        AND cmd = 'SELECT'
        AND (qual IS NULL OR qual NOT ILIKE '%bucket_id%') $$,
  'every storage.objects SELECT policy is bucket-scoped (no blanket USING(true))');

SELECT * FROM finish();
ROLLBACK;
