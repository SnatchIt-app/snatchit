-- Rollback for 051_storage_scope_public_read.sql
--
-- WARNING: this restores the unscoped legacy policies, which REOPENS public
-- read access to the private `proof-docs` bucket (proof-of-ownership documents
-- and transfer/dispute evidence) to any caller holding the anon key.
--
-- Only run this if dropping them broke a read path that could not be fixed
-- forward. Prefer adding a narrower policy for the broken path instead.
--
-- Definitions below are reproduced verbatim from pg_policies as captured on
-- 2026-08-05, immediately before 051 was applied.

BEGIN;

DROP POLICY IF EXISTS "public read public buckets" ON storage.objects;

CREATE POLICY "Allow public read avatars 1oj01fe_0"
ON storage.objects FOR SELECT TO public
USING (true);

CREATE POLICY "allow public read 51etwa_0"
ON storage.objects FOR SELECT TO public
USING (bucket_id = 'true'::text);

CREATE POLICY "allow public read v2 51etwa_0"
ON storage.objects FOR SELECT TO public
USING (true);

CREATE POLICY "Allow authenticated avatar update 1oj01fe_1"
ON storage.objects FOR SELECT TO authenticated
USING (auth.role() = 'authenticated'::text);

COMMIT;
