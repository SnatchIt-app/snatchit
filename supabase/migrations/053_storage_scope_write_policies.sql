-- =============================================================================
-- 053_storage_scope_write_policies.sql
--
-- STATUS: PREPARED, NOT YET APPLIED (2026-08-05).
-- The automated apply was refused by the tooling guardrail that gates policy
-- changes against production. Reviewed and verified against live state and both
-- shipped clients; awaiting an operator. Nothing here has taken effect.
--
-- Companion to 051 (which fixed the READ half of the same bug class).
--
-- storage.objects carries legacy dashboard write policies with no bucket scope
-- and no owner scope:
--
--   "allow uploads v2 51etwa_0"                   INSERT  WITH CHECK (auth.role() = 'authenticated')
--   "Allow authenticated avatar upload 1oj01fe_0" INSERT  WITH CHECK (auth.role() = 'authenticated')
--   "Allow authenticated avatar update 1oj01fe_0" UPDATE  USING      (auth.role() = 'authenticated')
--   "allow uploads 51etwa_0"                      INSERT  WITH CHECK (bucket_id = 'authenticated')  -- dead
--
-- Because policies OR together, these defeat the scoped "proof-docs owner
-- insert" policy entirely. Any authenticated user can write into any other
-- user's folder in any bucket.
--
-- The UPDATE policy is the worst of them, and it is worse than it looks: its
-- WITH CHECK is NULL, so Postgres reuses the USING expression as the check.
-- USING is unconditionally true for any authenticated caller, so the NEW row is
-- unconstrained too — including `name`, `bucket_id` and `owner`. Reached through
-- the Storage API's move/copy endpoints, that means any authenticated user can
-- RENAME or OVERWRITE any object in any bucket.
--
-- That defeats migration 049 outright, with no DELETE involved: 049 blocks
-- deleting an object while a transfer still references it as
-- transfer_evidence_path, but a rename leaves the reference dangling and the
-- evidence gone. It also allows destroying ANOTHER user's dispute evidence or
-- overwriting a rival seller's cover image.
--
-- FIX: drop the four legacy write policies; replace with per-bucket,
-- owner-folder-scoped INSERT and UPDATE policies carrying EXPLICIT WITH CHECK
-- clauses so the new row is constrained too. The proof-docs UPDATE additionally
-- mirrors 049's NOT EXISTS guard, so a referenced evidence object cannot be
-- renamed away either.
--
-- COMPATIBILITY — every upload path in both shipped clients is already
-- uid-prefixed, so nothing breaks:
--   mobile src/lib/avatarImage.ts:115     `${userId}/avatar_${Date.now()}.${ext}`   (upsert: true -> needs UPDATE)
--   mobile src/hooks/useImageUpload.ts:161 `${userId}/${folder}/${Date.now()}.${ext}` (upsert: false)
--   web    src/lib/create-listing.ts       `${uid}/covers/...`, `${uid}/proofs/...`
--   web    src/lib/transfers.ts:197        `${userId}/transfer-evidence/...`
-- The only upsert:true path is the avatar, and it is uid-prefixed, so the
-- scoped UPDATE policy covers it. Build 13 (in App Review) is unaffected.
--
-- Grant/policy definitions only. No data is read, moved, or deleted.
--
-- Rollback: supabase/rollbacks/053_storage_scope_write_policies_rollback.sql
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "allow uploads v2 51etwa_0"                   ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated avatar upload 1oj01fe_0" ON storage.objects;
DROP POLICY IF EXISTS "allow uploads 51etwa_0"                      ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated avatar update 1oj01fe_0" ON storage.objects;

DROP POLICY IF EXISTS "avatars owner insert"       ON storage.objects;
DROP POLICY IF EXISTS "avatars owner update"       ON storage.objects;
DROP POLICY IF EXISTS "auction-media owner insert" ON storage.objects;
DROP POLICY IF EXISTS "auction-media owner update" ON storage.objects;
DROP POLICY IF EXISTS "proof-docs owner update"    ON storage.objects;

CREATE POLICY "avatars owner insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (auth.uid())::text);

CREATE POLICY "avatars owner update"
ON storage.objects FOR UPDATE TO authenticated
USING      (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (auth.uid())::text)
WITH CHECK (bucket_id = 'avatars' AND (storage.foldername(name))[1] = (auth.uid())::text);

CREATE POLICY "auction-media owner insert"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id = 'auction-media' AND (storage.foldername(name))[1] = (auth.uid())::text);

CREATE POLICY "auction-media owner update"
ON storage.objects FOR UPDATE TO authenticated
USING      (bucket_id = 'auction-media' AND (storage.foldername(name))[1] = (auth.uid())::text)
WITH CHECK (bucket_id = 'auction-media' AND (storage.foldername(name))[1] = (auth.uid())::text);

-- proof-docs keeps its existing scoped INSERT policy ("proof-docs owner
-- insert"). This adds the missing UPDATE, refusing to rename or overwrite an
-- object still referenced as transfer evidence.
CREATE POLICY "proof-docs owner update"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'proof-docs'
  AND (storage.foldername(name))[1] = (auth.uid())::text
  AND NOT EXISTS (
    SELECT 1 FROM public.transfers t WHERE t.transfer_evidence_path = storage.objects.name
  )
)
WITH CHECK (
  bucket_id = 'proof-docs'
  AND (storage.foldername(name))[1] = (auth.uid())::text
);

COMMIT;
