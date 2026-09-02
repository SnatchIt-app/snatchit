-- Rollback 20260902003623_admin_relist_listing_rpc — remove the relist RPC.
--
-- Dropping the function does NOT re-cancel anything it already relisted; a
-- listing restored with it stays active. Re-cancel individually with
-- cancel_listing if that is actually wanted.

DROP FUNCTION IF EXISTS public.admin_relist_listing(uuid, timestamptz, uuid);
