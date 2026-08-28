-- =============================================================================
-- ROLLBACK for 20260828041500_account_deletion_residue.sql
--
-- Restores public.delete_account_cleanup to its 0563 body verbatim.
--
-- WHAT THIS ROLLBACK CANNOT UNDO, AND YOU SHOULD KNOW BEFORE RUNNING IT:
--
--   Rolling back the FUNCTION is clean — it is a CREATE OR REPLACE and the
--   0563 text is reproduced below exactly.
--
--   Rolling back its EFFECTS is not possible. Any account deleted while the
--   new function was live has had its bids removed, its auction heads
--   reconciled, and its cover_image_path rewritten to 'deleted/cover-removed'.
--   None of that is recoverable, because nothing records the prior values —
--   which is the same property the old function already had, and part of why
--   this migration exists.
--
--   Restoring the old body does NOT re-break anything already fixed. It
--   re-opens the defects for FUTURE deletions only: the auth.users DELETE will
--   again raise 23503 for auction winners and top bidders, and cover_image_path
--   will again carry the deleted user's uuid on a world-readable row.
--
-- Forward-fix is strongly preferred over this rollback.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.delete_account_cleanup(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare v_sentinel_id uuid := '00000000-0000-0000-0000-000000000000';
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  perform set_config('app.bypass_transfer_guard', 'on', true);

  update public.listings
     set auction_status='cancelled', status='active', reserved_by=null,
         reserved_until=null, ended_at=now()
   where seller_id = p_user_id and auction_status in ('active','ended');

  alter table public.listings disable trigger trg_guard_listing_identity;
  update public.listings set seller_id = v_sentinel_id where seller_id = p_user_id;
  alter table public.listings enable trigger trg_guard_listing_identity;

  update public.payments set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  update public.payments set seller_id = v_sentinel_id where seller_id = p_user_id;

  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set buyer_id  = v_sentinel_id where buyer_id  = p_user_id;
  perform set_config('app.bypass_transfer_guard', 'on', true);
  update public.transfers set seller_id = v_sentinel_id where seller_id = p_user_id;
end; $function$;

COMMENT ON FUNCTION public.delete_account_cleanup(uuid) IS NULL;

COMMIT;
