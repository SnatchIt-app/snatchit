-- =============================================================================
-- 048_auction_media_owner_delete.sql
--
-- storage.objects has INSERT, SELECT and UPDATE policies but NO DELETE policy
-- of any kind, so `supabase.storage.from(...).remove([...])` has always failed
-- silently for every user. Found during live seller-flow verification: a
-- listing deleted through /account/listings removed the row but left its cover
-- image in auction-media forever. Mobile's my-listings delete has the same
-- best-effort remove() call and the same silent failure, so orphaned covers
-- have been accumulating from both clients.
--
-- Fix: a single owner-scoped DELETE policy, deliberately narrow.
--
--   * auction-media ONLY. proof-docs is intentionally excluded: it holds
--     proof-of-ownership and transfer evidence, which is dispute evidence.
--     A seller must not be able to delete their own evidence after a buyer
--     opens a dispute.
--   * Owner-scoped via the existing folder convention — the first path
--     segment is the uploader's uid, same as "proof-docs owner insert".
--   * Only UNREFERENCED objects. A cover still pointed at by a listing can
--     never be deleted, so this cannot be used to blank out a live listing's
--     image. deleteSellerListing() removes the listing row first, so by the
--     time it calls remove() the object is already unreferenced.
--
-- Grant only — no data is deleted by this migration, and nothing that was
-- previously permitted becomes forbidden.
--
-- Rollback: supabase/rollbacks/048_auction_media_owner_delete_rollback.sql
-- =============================================================================

BEGIN;

DROP POLICY IF EXISTS "auction-media owner delete unreferenced" ON storage.objects;

CREATE POLICY "auction-media owner delete unreferenced"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'auction-media'
  AND (storage.foldername(name))[1] = (auth.uid())::text
  AND NOT EXISTS (
    SELECT 1 FROM public.listings l
     WHERE l.cover_image_path = storage.objects.name
  )
);

COMMIT;
