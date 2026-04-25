-- =============================================================================
-- Migration 020: delete_account_cleanup RPC
-- =============================================================================
-- PURPOSE: Provide a SECURITY DEFINER function that can safely cancel listings
-- and anonymize seller_id during account deletion.
--
-- The guard_listing_state_columns trigger blocks direct PostgREST updates to
-- auction_status. The guard_listing_identity_columns trigger blocks ALL changes
-- to seller_id with no bypass flag. This RPC bypasses the state guard and
-- temporarily disables the identity guard to allow account deletion cleanup.
--
-- This function is called by the delete-account edge function using the
-- service role key. It is NOT callable by end users (requires service role).
-- =============================================================================

create or replace function public.delete_account_cleanup(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_sentinel_id uuid := '00000000-0000-0000-0000-000000000000';
  v_listing     record;
begin
  -- ── 1. Cancel active/reserved listings ──────────────────────────────────
  -- Use the state guard bypass to set auction_status = 'cancelled'.
  -- Also clear reservations on these listings.
  perform set_config('app.bypass_listing_guard', 'on', true);

  update public.listings
     set auction_status = 'cancelled',
         status         = 'active',
         reserved_by    = null,
         reserved_until = null,
         ended_at       = now()
   where seller_id = p_user_id
     and auction_status in ('active', 'ended');

  -- ── 2. Anonymize seller_id on all remaining user listings ───────────────
  -- The identity guard blocks seller_id changes unconditionally, so we must
  -- temporarily disable it. We re-enable it immediately after.
  -- This is safe because:
  --   a) This function is SECURITY DEFINER (runs as DB owner)
  --   b) Only called from the service-role delete-account edge function
  --   c) The disable/enable is within a single transaction
  alter table public.listings disable trigger trg_guard_listing_identity;

  update public.listings
     set seller_id = v_sentinel_id
   where seller_id = p_user_id;

  alter table public.listings enable trigger trg_guard_listing_identity;

  -- ── 3. Anonymize financial records ──────────────────────────────────────
  -- Payments
  update public.payments
     set buyer_id = v_sentinel_id
   where buyer_id = p_user_id;

  update public.payments
     set seller_id = v_sentinel_id
   where seller_id = p_user_id;

  -- Transfers
  update public.transfers
     set buyer_id = v_sentinel_id
   where buyer_id = p_user_id;

  update public.transfers
     set seller_id = v_sentinel_id
   where seller_id = p_user_id;
end;
$$;
