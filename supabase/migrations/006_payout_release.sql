-- =============================================================================
-- Migration 006: Payout release tracking
-- =============================================================================
-- PURPOSE: Add minimal columns to the transfers table to support idempotent
-- payout release after buyer confirms receipt.
--
-- CONTEXT (Day 2 — buyer-protection payout):
--   The confirm-and-release edge function will:
--     1. Call confirm_transfer_received RPC (seller_sent → buyer_confirmed)
--     2. Check payout_released_at IS NULL (idempotency guard)
--     3. Call stripe.transfers.create() to the seller's Connect account
--     4. Write payout_released_at + stripe_transfer_id atomically
--
-- COLUMNS ADDED:
--   payout_released_at  — timestamp when Stripe Transfer was created
--                         NULL = payout not yet released
--                         NOT NULL = payout released, do not pay again
--   stripe_transfer_id  — Stripe Transfer object ID (tr_xxx) for
--                         debugging, reconciliation, and support
--
-- SAFETY:
--   - Purely additive (ADD COLUMN IF NOT EXISTS)
--   - Both columns nullable — no backfill needed
--   - No existing queries, RPCs, RLS policies, or constraints are affected
--   - No indexes added (not needed at private beta scale)
--   - Safe to run on live DB with zero downtime
-- =============================================================================

alter table public.transfers
  add column if not exists payout_released_at  timestamptz,
  add column if not exists stripe_transfer_id  text;
