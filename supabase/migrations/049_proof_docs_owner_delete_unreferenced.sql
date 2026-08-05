-- =============================================================================
-- 049_proof_docs_owner_delete_unreferenced.sql
--
-- Companion to 048. Deleting a listing orphans its proof-of-ownership file
-- forever: neither client ever removes it (mobile's my-listings delete only
-- calls remove() on auction-media), and until 048 there was no DELETE policy
-- on storage.objects at all. So proof-docs accumulates one dead file per
-- deleted listing, permanently.
--
-- 048 deliberately excluded proof-docs because that bucket also holds
-- TRANSFER EVIDENCE, which is dispute evidence — a seller must never be able
-- to delete their own evidence after a buyer opens a dispute.
--
-- This policy keeps that guarantee while still allowing genuine garbage to be
-- collected. An object is deletable only when ALL of the following hold:
--
--   * bucket is proof-docs,
--   * the caller owns the folder (first path segment = auth.uid()),
--   * NO listing references it as proof_of_ownership_path, AND
--   * NO transfer references it as transfer_evidence_path.
--
-- The transfer check is the load-bearing one: any file that is or ever was
-- attached to a transfer stays undeletable for the life of that transfer row,
-- so dispute evidence remains immutable. Only files whose listing has already
-- been deleted — which can only happen while the listing was active with zero
-- bids, so it never reached a transfer — become eligible.
--
-- Grant only. No data is deleted by this migration.
--
-- Rollback: supabase/rollbacks/049_proof_docs_owner_delete_unreferenced_rollback.sql
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "proof-docs owner delete unreferenced" ON storage.objects;

CREATE POLICY "proof-docs owner delete unreferenced"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'proof-docs'
  AND (storage.foldername(name))[1] = (auth.uid())::text
  AND NOT EXISTS (
    SELECT 1 FROM public.listings l
     WHERE l.proof_of_ownership_path = storage.objects.name
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.transfers t
     WHERE t.transfer_evidence_path = storage.objects.name
  )
);

COMMIT;
