-- Rollback for 053_storage_scope_write_policies.sql
--
-- WARNING: this restores unscoped write access to storage.objects. Any
-- authenticated user regains the ability to INSERT into any bucket under any
-- other user's folder, and to RENAME or OVERWRITE any object in any bucket —
-- which re-opens the migration 049 bypass (evidence can be renamed away
-- instead of deleted).
--
-- Only run this if the scoped policies broke an upload path that cannot be
-- fixed forward. Prefer adding a narrower policy for the broken path.
--
-- Definitions reproduced verbatim from pg_policies as captured on 2026-08-05,
-- before 053. Note the two INSERT policies were duplicates of one another, and
-- "allow uploads 51etwa_0" was already dead (bucket_id = 'authenticated'
-- matches no bucket); both are restored for exactness.

BEGIN;

DROP POLICY IF EXISTS "avatars owner insert"       ON storage.objects;
DROP POLICY IF EXISTS "avatars owner update"       ON storage.objects;
DROP POLICY IF EXISTS "auction-media owner insert" ON storage.objects;
DROP POLICY IF EXISTS "auction-media owner update" ON storage.objects;
DROP POLICY IF EXISTS "proof-docs owner update"    ON storage.objects;

CREATE POLICY "allow uploads v2 51etwa_0"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (auth.role() = 'authenticated'::text);

CREATE POLICY "Allow authenticated avatar upload 1oj01fe_0"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (auth.role() = 'authenticated'::text);

CREATE POLICY "allow uploads 51etwa_0"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'authenticated'::text);

CREATE POLICY "Allow authenticated avatar update 1oj01fe_0"
ON storage.objects FOR UPDATE TO authenticated
USING (auth.role() = 'authenticated'::text);

COMMIT;
