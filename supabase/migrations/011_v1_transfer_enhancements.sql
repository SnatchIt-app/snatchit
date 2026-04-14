-- =============================================================================
-- Migration 011: V1 Transfer Enhancements (Phase A)
-- =============================================================================
-- PURPOSE: Add minimum trust-building fields to listings and transfers,
-- plus the RPCs needed to populate them from the app.
--
-- LISTINGS additions:
--   ticket_platform                — which ticketing platform the seller uses
--   proof_of_ownership_path        — storage path to proof screenshot
--   seller_commitment_accepted_at  — timestamp seller checked the commitment box
--
-- TRANSFERS additions:
--   delivery_email                 — buyer-provided email for ticket delivery
--   delivery_phone                 — buyer-provided phone for ticket delivery
--   transfer_evidence_path         — storage path to seller's transfer proof
--   dispute_reason                 — structured reason from buyer dispute
--   dispute_evidence_path          — storage path to buyer's dispute proof
--   dispute_notes                  — free-text notes from buyer dispute
--   dispute_resolution             — admin resolution outcome
--   dispute_resolved_at            — when admin resolved
--   dispute_resolved_by            — which admin resolved
--
-- RPCs added / updated:
--   set_transfer_delivery_info     — NEW: buyer sets delivery email/phone
--   mark_transfer_sent             — EXTENDED: optional evidence path param
--   buyer_dispute_transfer         — EXTENDED: optional reason/evidence/notes
--   admin_resolve_dispute          — NEW: admin resolves disputed transfer
--
-- PRESERVES: All existing payout, refund, auto-release, expiry, and
-- confirm-and-release architecture. No edge functions are modified.
--
-- BACKWARD COMPAT: All new RPC params use DEFAULT NULL. Existing callsites
-- that pass only (p_transfer_id, p_user_id) continue to work unchanged.
--
-- SAFETY: All DDL uses IF NOT EXISTS / OR REPLACE. Safe to re-run.
-- =============================================================================


-- ===========================================================================
-- 1. LISTINGS: platform selection + proof of ownership + seller commitment
-- ===========================================================================

ALTER TABLE public.listings
  ADD COLUMN IF NOT EXISTS ticket_platform TEXT NOT NULL DEFAULT 'other',
  ADD COLUMN IF NOT EXISTS proof_of_ownership_path TEXT,
  ADD COLUMN IF NOT EXISTS seller_commitment_accepted_at TIMESTAMPTZ;

-- CHECK constraint for ticket_platform enum values.
-- Wrapped in DO block so re-running is safe (constraint may already exist).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'listings_ticket_platform_check'
      AND conrelid = 'public.listings'::regclass
  ) THEN
    ALTER TABLE public.listings
      ADD CONSTRAINT listings_ticket_platform_check
      CHECK (ticket_platform IN (
        'dice', 'eventbrite', 'posh', 'axs', 'ticketmaster', 'other'
      ));
  END IF;
END $$;


-- ===========================================================================
-- 2. TRANSFERS: delivery info + transfer evidence + dispute details
-- ===========================================================================

ALTER TABLE public.transfers
  ADD COLUMN IF NOT EXISTS delivery_email TEXT,
  ADD COLUMN IF NOT EXISTS delivery_phone TEXT,
  ADD COLUMN IF NOT EXISTS transfer_evidence_path TEXT,
  ADD COLUMN IF NOT EXISTS dispute_reason TEXT,
  ADD COLUMN IF NOT EXISTS dispute_evidence_path TEXT,
  ADD COLUMN IF NOT EXISTS dispute_notes TEXT,
  ADD COLUMN IF NOT EXISTS dispute_resolution TEXT,
  ADD COLUMN IF NOT EXISTS dispute_resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS dispute_resolved_by UUID REFERENCES auth.users(id);

-- CHECK constraint for dispute_reason enum values.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transfers_dispute_reason_check'
      AND conrelid = 'public.transfers'::regclass
  ) THEN
    ALTER TABLE public.transfers
      ADD CONSTRAINT transfers_dispute_reason_check
      CHECK (dispute_reason IN (
        'never_received', 'wrong_tickets', 'invalid_tickets', 'partial_delivery'
      ));
  END IF;
END $$;

-- CHECK constraint for dispute_resolution enum values.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'transfers_dispute_resolution_check'
      AND conrelid = 'public.transfers'::regclass
  ) THEN
    ALTER TABLE public.transfers
      ADD CONSTRAINT transfers_dispute_resolution_check
      CHECK (dispute_resolution IN (
        'resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund'
      ));
  END IF;
END $$;


-- ===========================================================================
-- 3. NEW RPC: set_transfer_delivery_info
-- ===========================================================================
-- Called by:  Buyer receive screen (post-purchase delivery info form)
-- Client:    supabase.rpc('set_transfer_delivery_info', {
--              p_transfer_id, p_delivery_email, p_delivery_phone })
-- Auth:      auth.uid() must equal buyer_id
-- Guard:     transfer must be in 'pending' or 'seller_sent' status
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.set_transfer_delivery_info(
  p_transfer_id    UUID,
  p_delivery_email TEXT DEFAULT NULL,
  p_delivery_phone TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
BEGIN
  v_caller_id := auth.uid();

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  -- Lock the row to prevent concurrent updates.
  SELECT status, buyer_id
    INTO v_status, v_buyer_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer can set delivery info.';
  END IF;

  -- Allow updates while pending (normal flow) or seller_sent (late update).
  IF v_status NOT IN ('pending', 'seller_sent') THEN
    RAISE EXCEPTION 'Cannot update delivery info in current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET delivery_email = COALESCE(p_delivery_email, delivery_email),
         delivery_phone = COALESCE(p_delivery_phone, delivery_phone)
   WHERE id = p_transfer_id;
END;
$$;


-- ===========================================================================
-- 4. EXTENDED RPC: mark_transfer_sent
-- ===========================================================================
-- CHANGE: Adds optional p_transfer_evidence_path parameter.
-- BACKWARD COMPAT: Existing callsites passing (p_transfer_id, p_user_id)
-- continue to work — p_transfer_evidence_path defaults to NULL.
--
-- Preserves 008_auto_release.sql behavior: sets auto_release_at = now() + 72h
--
-- Called by:  Seller send screen (after uploading evidence)
-- Client:    supabase.rpc('mark_transfer_sent', {
--              p_transfer_id, p_user_id, p_transfer_evidence_path })
-- Transition: pending → seller_sent
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.mark_transfer_sent(
  p_transfer_id            UUID,
  p_user_id                UUID,
  p_transfer_evidence_path TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_seller_id uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  -- Lock the transfer row to prevent concurrent state transitions.
  SELECT status, seller_id
    INTO v_status, v_seller_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_seller_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the seller can mark a transfer as sent.';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status                 = 'seller_sent',
         seller_sent_at         = now(),
         auto_release_at        = now() + INTERVAL '72 hours',
         transfer_evidence_path = COALESCE(p_transfer_evidence_path, transfer_evidence_path)
   WHERE id = p_transfer_id;
END;
$$;


-- ===========================================================================
-- 5. EXTENDED RPC: buyer_dispute_transfer
-- ===========================================================================
-- CHANGE: Adds optional p_dispute_reason, p_dispute_evidence_path,
-- p_dispute_notes parameters.
-- BACKWARD COMPAT: Existing callsites passing (p_transfer_id) or
-- (p_transfer_id, p_user_id) continue to work — new params default to NULL.
--
-- Preserves 009_dispute.sql behavior: sets status='disputed', disputed_at=now()
-- Preserves idempotency: if already disputed, returns silently.
--
-- Called by:  Buyer receive screen (dispute form)
-- Client:    supabase.rpc('buyer_dispute_transfer', {
--              p_transfer_id, p_user_id,
--              p_dispute_reason, p_dispute_evidence_path, p_dispute_notes })
-- Transition: seller_sent → disputed
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(
  p_transfer_id           UUID,
  p_user_id               UUID DEFAULT NULL,
  p_dispute_reason        TEXT DEFAULT NULL,
  p_dispute_evidence_path TEXT DEFAULT NULL,
  p_dispute_notes         TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_status    text;
  v_buyer_id  uuid;
BEGIN
  v_caller_id := coalesce(auth.uid(), p_user_id);

  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.';
  END IF;

  -- Lock the transfer row to prevent concurrent state transitions.
  SELECT status, buyer_id
    INTO v_status, v_buyer_id
    FROM public.transfers
   WHERE id = p_transfer_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found.';
  END IF;

  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN
    RAISE EXCEPTION 'Only the buyer can dispute a transfer.';
  END IF;

  -- Idempotent: if already disputed, return silently.
  IF v_status = 'disputed' THEN
    RETURN;
  END IF;

  IF v_status <> 'seller_sent' THEN
    RAISE EXCEPTION 'Cannot dispute transfer in current status: %.', v_status;
  END IF;

  UPDATE public.transfers
     SET status                = 'disputed',
         disputed_at           = now(),
         dispute_reason        = COALESCE(p_dispute_reason, dispute_reason),
         dispute_evidence_path = COALESCE(p_dispute_evidence_path, dispute_evidence_path),
         dispute_notes         = COALESCE(p_dispute_notes, dispute_notes)
   WHERE id = p_transfer_id;
END;
$$;


-- ===========================================================================
-- 6. NEW RPC: admin_resolve_dispute
-- ===========================================================================
-- Called by:  Admin (SQL Editor or future admin panel) to resolve disputes.
-- Client:    supabase.rpc('admin_resolve_dispute', {
--              p_transfer_id, p_resolution, p_admin_id })
-- Guard:     transfer must be in 'disputed' status
-- Note:      This does NOT trigger Stripe refunds or payouts. The admin must
--            trigger those separately using existing edge functions / Stripe
--            dashboard. This RPC only records the resolution decision.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.admin_resolve_dispute(
  p_transfer_id UUID,
  p_resolution  TEXT,
  p_admin_id    UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Validate resolution value.
  IF p_resolution NOT IN (
    'resolved_seller_paid', 'resolved_buyer_refunded', 'resolved_partial_refund'
  ) THEN
    RAISE EXCEPTION 'Invalid resolution type: %', p_resolution;
  END IF;

  -- Lock and update the disputed transfer.
  UPDATE public.transfers
     SET dispute_resolution  = p_resolution,
         dispute_resolved_at = now(),
         dispute_resolved_by = p_admin_id
   WHERE id = p_transfer_id
     AND status = 'disputed'
     AND dispute_resolved_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Transfer not found, not in disputed state, or already resolved.';
  END IF;
END;
$$;
