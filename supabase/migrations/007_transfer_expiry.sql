-- =============================================================================
-- Migration 007: Transfer expiry + auto-refund support
-- =============================================================================
-- PURPOSE: Add columns and RPC needed for the enforce_transfer_expiry system.
--
-- CONTEXT (Day 2 — transfer auto-expiry):
--   The enforce-transfer-expiry edge function will:
--     1. Call enforce_transfer_expiry() RPC (batch: pending → expired)
--     2. For each expired transfer, look up the payment's stripe_payment_intent_id
--     3. Skip if already refunded (idempotency via stripe_refund_id)
--     4. Call Stripe POST /v1/refunds
--     5. Write payments.status='refunded', refunded_at, stripe_refund_id
--     6. Send push notifications to buyer and seller
--
-- COLUMNS ADDED:
--   transfers.expired_at       — timestamp when expiry was enforced
--                                (distinct from expires_at which is the deadline)
--                                NULL = not yet expired by enforcement
--   payments.stripe_refund_id  — Stripe Refund object ID (re_xxx) for
--                                idempotency, reconciliation, and support
--
-- RPC ADDED:
--   enforce_transfer_expiry()  — batch function using FOR UPDATE SKIP LOCKED
--                                to atomically expire pending transfers
--
-- SAFETY:
--   - Purely additive (ADD COLUMN IF NOT EXISTS, CREATE OR REPLACE)
--   - Both columns nullable — no backfill needed
--   - No existing queries, RPCs, RLS policies, or constraints are affected
--   - Partial index is additive — does not affect existing queries
--   - Safe to run on live DB with zero downtime
-- =============================================================================


-- ===========================================================================
-- 1. NEW COLUMNS
-- ===========================================================================

-- Track when expiry was actually enforced (vs expires_at = the deadline)
alter table public.transfers
  add column if not exists expired_at timestamptz;

-- Track Stripe Refund ID for idempotency and reconciliation
alter table public.payments
  add column if not exists stripe_refund_id text;


-- ===========================================================================
-- 2. PARTIAL INDEX FOR EXPIRY SWEEP
-- ===========================================================================
-- The enforce_transfer_expiry() RPC queries:
--   WHERE status = 'pending' AND expires_at < now()
--
-- This partial index covers exactly that query. Only rows with status='pending'
-- are indexed, keeping the index small and writes fast.
-- ===========================================================================
create index if not exists idx_transfers_pending_expires
  on public.transfers (expires_at)
  where status = 'pending';


-- ===========================================================================
-- 3. enforce_transfer_expiry() RPC
-- ===========================================================================
-- Called by:   enforce-transfer-expiry edge function (service role, cron)
-- Pattern:     Identical to auto_finalize_expired_auctions — batch + SKIP LOCKED
-- Transition:  pending → expired (only for transfers past their expires_at)
--
-- Returns the affected rows so the edge function can:
--   - Issue Stripe refunds for each payment
--   - Send push notifications to buyer and seller
--
-- SKIP LOCKED ensures concurrent cron invocations never double-process the
-- same transfer row. Each row is claimed by exactly one transaction.
-- ===========================================================================
create or replace function public.enforce_transfer_expiry()
returns table (
  transfer_id         uuid,
  payment_id          uuid,
  listing_id          uuid,
  buyer_id            uuid,
  seller_id           uuid
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with expired as (
    select t.id, t.payment_id, t.listing_id, t.buyer_id, t.seller_id
      from public.transfers t
     where t.status = 'pending'
       and t.expires_at < now()
       for update skip locked
  )
  update public.transfers t
     set status     = 'expired',
         expired_at = now()
    from expired e
   where t.id = e.id
  returning t.id        as transfer_id,
            t.payment_id,
            t.listing_id,
            t.buyer_id,
            t.seller_id;
end;
$$;
