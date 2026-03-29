-- =============================================================================
-- Migration 002: Transfers system
-- =============================================================================
-- PURPOSE: Capture live DB objects into version control.
-- This migration does NOT redesign anything. It is a faithful snapshot of
-- the transfers table, its RLS policies, and the two canonical RPCs that
-- already exist in the live database and are actively used by the app.
--
-- Safe to run on the live DB: every CREATE uses IF NOT EXISTS / OR REPLACE,
-- and every DROP uses IF EXISTS.
--
-- Live flow preserved:
--   stripe-webhook inserts transfer row (pending)
--     → seller taps "Mark as Sent" → mark_transfer_sent (pending → seller_sent)
--     → buyer taps "Confirm Received" → confirm_transfer_received (seller_sent → buyer_confirmed)
-- =============================================================================


-- ===========================================================================
-- 1. PROFILES: stripe_connect_id
-- Untracked column used by stripe-webhook to route Stripe payouts to sellers.
-- Added here because it is part of the same payment/transfer system.
-- ===========================================================================
alter table public.profiles
  add column if not exists stripe_connect_id text unique;


-- ===========================================================================
-- 2. TRANSFERS TABLE
-- ===========================================================================
-- Who writes it:  stripe-webhook edge function (service role) on payment success
-- Who reads it:   ListingDetailScreen — selects id, status, buyer_id
-- Who updates it: mark_transfer_sent and confirm_transfer_received RPCs only
-- ===========================================================================
create table if not exists public.transfers (
  id                  uuid        primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),

  -- References
  listing_id          uuid        not null references public.listings(id),
  payment_id          uuid        not null references public.payments(id),
  seller_id           uuid        not null references auth.users(id),
  buyer_id            uuid        not null references auth.users(id),

  -- Transfer details
  transfer_method     text        not null
                                  check (transfer_method in ('mobile_transfer', 'email')),

  -- State machine
  -- pending:          transfer created, seller has not yet sent
  -- seller_sent:      seller marked as sent (mark_transfer_sent RPC)
  -- buyer_confirmed:  buyer confirmed receipt (confirm_transfer_received RPC)
  -- disputed:         either party raised a dispute
  -- expired:          seller did not send before expires_at
  status              text        not null default 'pending'
                                  check (status in (
                                    'pending',
                                    'seller_sent',
                                    'buyer_confirmed',
                                    'disputed',
                                    'expired'
                                  )),

  -- Timestamps
  seller_sent_at      timestamptz,
  buyer_confirmed_at  timestamptz,
  expires_at          timestamptz not null
);


-- ===========================================================================
-- 3. INDEXES
-- ===========================================================================

-- Primary query path: ListingDetailScreen fetches by listing_id
create index if not exists idx_transfers_listing_id
  on public.transfers (listing_id);

-- RLS and buyer-side queries
create index if not exists idx_transfers_buyer_id
  on public.transfers (buyer_id);

-- RLS and seller-side queries
create index if not exists idx_transfers_seller_id
  on public.transfers (seller_id);

-- Status filtering (expiry sweeps, dispute queries)
create index if not exists idx_transfers_status
  on public.transfers (status);


-- ===========================================================================
-- 4. ROW LEVEL SECURITY
-- ===========================================================================
alter table public.transfers enable row level security;

-- Buyers can see their own transfers (to check if seller has sent)
drop policy if exists "transfers: buyer select" on public.transfers;
create policy "transfers: buyer select"
  on public.transfers for select
  using (buyer_id = auth.uid());

-- Sellers can see their own transfers (to confirm what to send)
drop policy if exists "transfers: seller select" on public.transfers;
create policy "transfers: seller select"
  on public.transfers for select
  using (seller_id = auth.uid());

-- NO client INSERT policy — inserts are performed exclusively by
-- the stripe-webhook edge function using the service role key.

-- NO client UPDATE policy — updates are performed exclusively by
-- the SECURITY DEFINER RPCs mark_transfer_sent and confirm_transfer_received.


-- ===========================================================================
-- 5. mark_transfer_sent
-- ===========================================================================
-- Called by:   ListingDetailScreen.handleMarkSent()
-- Client call: supabase.rpc('mark_transfer_sent', { p_transfer_id, p_user_id })
-- Transition:  pending → seller_sent
-- Auth:        COALESCE(auth.uid(), p_user_id) must equal seller_id
-- ===========================================================================
create or replace function public.mark_transfer_sent(
  p_transfer_id uuid,
  p_user_id     uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid;
  v_status    text;
  v_seller_id uuid;
begin
  -- SECURITY: auth.uid() wins for client calls; p_user_id used for
  -- service-role callers (webhook, SQL Editor) where auth.uid() is NULL.
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  -- Lock the transfer row for the duration of this transaction to prevent
  -- concurrent state transitions racing each other.
  select status, seller_id
    into v_status, v_seller_id
    from public.transfers
   where id = p_transfer_id
     for update;

  if not found then
    raise exception 'Transfer not found.';
  end if;

  -- Only the seller may mark a transfer as sent.
  if v_seller_id is distinct from v_caller_id then
    raise exception 'Only the seller can mark a transfer as sent.';
  end if;

  -- Guard the state machine — must be in pending to advance.
  if v_status <> 'pending' then
    raise exception 'Transfer cannot be marked as sent from current status: %.', v_status;
  end if;

  update public.transfers
     set status         = 'seller_sent',
         seller_sent_at = now()
   where id = p_transfer_id;
end;
$$;


-- ===========================================================================
-- 6. confirm_transfer_received
-- ===========================================================================
-- Called by:   ListingDetailScreen.handleConfirmReceived()
-- Client call: supabase.rpc('confirm_transfer_received', { p_transfer_id, p_user_id })
-- Transition:  seller_sent → buyer_confirmed
-- Auth:        COALESCE(auth.uid(), p_user_id) must equal buyer_id
-- ===========================================================================
create or replace function public.confirm_transfer_received(
  p_transfer_id uuid,
  p_user_id     uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
begin
  -- SECURITY: auth.uid() wins for client calls; p_user_id used for
  -- service-role callers (webhook, SQL Editor) where auth.uid() is NULL.
  v_caller_id := coalesce(auth.uid(), p_user_id);

  if v_caller_id is null then
    raise exception 'Unable to identify caller. Ensure the request is authenticated.';
  end if;

  -- Lock the transfer row for the duration of this transaction.
  select status, buyer_id
    into v_status, v_buyer_id
    from public.transfers
   where id = p_transfer_id
     for update;

  if not found then
    raise exception 'Transfer not found.';
  end if;

  -- Only the buyer may confirm receipt.
  if v_buyer_id is distinct from v_caller_id then
    raise exception 'Only the buyer can confirm transfer receipt.';
  end if;

  -- Guard the state machine — must be seller_sent to advance.
  if v_status <> 'seller_sent' then
    raise exception 'Transfer cannot be confirmed from current status: %.', v_status;
  end if;

  update public.transfers
     set status             = 'buyer_confirmed',
         buyer_confirmed_at = now()
   where id = p_transfer_id;
end;
$$;


-- ===========================================================================
-- 7. DROP DEAD LEGACY RPCs
-- ===========================================================================
-- seller_send_transfer and buyer_confirm_transfer are only referenced by:
--   app/transfer/send/[id].tsx   — unreachable (no navigation path)
--   app/transfer/receive/[id].tsx — unreachable (no navigation path)
--
-- Neither screen is registered in _layout.tsx as a Stack.Screen.
-- No router.push(), Link, or href in any live source file points to them.
-- These RPCs serve no live client path and should not exist in production.
--
-- VERIFY BEFORE RUNNING: Confirm the exact signatures in your live DB with:
--   SELECT proname, pg_get_function_identity_arguments(oid)
--     FROM pg_proc
--    WHERE proname IN ('seller_send_transfer', 'buyer_confirm_transfer')
--      AND pronamespace = 'public'::regnamespace;
--
-- The DROP statements below use the signatures inferred from the dead screens.
-- If the live DB has different signatures, adjust accordingly.
-- A DROP with a wrong signature is a no-op (IF EXISTS protects against errors).
-- ===========================================================================

-- Dead screen app/transfer/send/[id].tsx called: (p_transfer_id uuid, p_transfer_code text)
drop function if exists public.seller_send_transfer(uuid, text);

-- Dead screen app/transfer/receive/[id].tsx called: (p_transfer_id uuid)
drop function if exists public.buyer_confirm_transfer(uuid);
