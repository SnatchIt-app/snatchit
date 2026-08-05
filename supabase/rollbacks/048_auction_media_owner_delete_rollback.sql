-- Rollback for 048_auction_media_owner_delete.sql
--
-- Drops the owner-scoped DELETE policy on storage.objects. After this,
-- storage.objects again has NO delete policy, so remove() silently fails for
-- every user and deleted listings orphan their cover images again.

BEGIN;

DROP POLICY IF EXISTS "auction-media owner delete unreferenced" ON storage.objects;

COMMIT;
