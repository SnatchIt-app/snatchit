-- Rollback for 049_proof_docs_owner_delete_unreferenced.sql
--
-- Drops the owner-scoped, unreferenced-only DELETE policy on proof-docs.
-- After this, proof-of-ownership files orphaned by a deleted listing can
-- never be removed again. Transfer evidence was already protected by the
-- policy's transfer check, so dropping it does not change dispute behaviour.

BEGIN;

DROP POLICY IF EXISTS "proof-docs owner delete unreferenced" ON storage.objects;

COMMIT;
