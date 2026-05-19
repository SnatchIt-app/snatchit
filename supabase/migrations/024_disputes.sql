-- =============================================================================
-- Migration 024: Stripe disputes (P1-02 webhook coverage)
-- =============================================================================
-- Captures chargebacks ("charge.dispute.created") and their lifecycle.
-- When a dispute opens we freeze the related transfer so auto-release
-- and confirm-and-release cannot fire while the case is pending.
-- =============================================================================

BEGIN;

-- ─── 1. disputes table ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.disputes (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  stripe_dispute_id   text        UNIQUE NOT NULL,
  stripe_charge_id    text        NOT NULL,
  stripe_pi_id        text,
  payment_id          uuid        REFERENCES public.payments(id),
  transfer_id         uuid        REFERENCES public.transfers(id),
  amount              int         NOT NULL CHECK (amount >= 0),
  currency            text        NOT NULL DEFAULT 'usd',
  reason              text        NOT NULL,
  -- Stripe statuses: warning_needs_response, warning_under_review,
  -- warning_closed, needs_response, under_review, won, lost, charge_refunded
  status              text        NOT NULL,
  evidence_due_by     timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS disputes_pi_idx        ON public.disputes (stripe_pi_id);
CREATE INDEX IF NOT EXISTS disputes_charge_idx    ON public.disputes (stripe_charge_id);
CREATE INDEX IF NOT EXISTS disputes_payment_idx   ON public.disputes (payment_id);
CREATE INDEX IF NOT EXISTS disputes_transfer_idx  ON public.disputes (transfer_id);
CREATE INDEX IF NOT EXISTS disputes_open_idx      ON public.disputes (created_at DESC)
  WHERE status NOT IN ('won', 'lost', 'warning_closed', 'charge_refunded');

ALTER TABLE public.disputes ENABLE ROW LEVEL SECURITY;
-- No client policies — disputes are server-only (service role) state.

-- updated_at trigger
CREATE OR REPLACE FUNCTION public.disputes_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS disputes_updated_at ON public.disputes;
CREATE TRIGGER disputes_updated_at
  BEFORE UPDATE ON public.disputes
  FOR EACH ROW EXECUTE FUNCTION public.disputes_set_updated_at();


-- ─── 2. Extend transfers.status to allow 'reversed' ──────────────────────────
-- Stripe Connect can reverse a transfer (refund out of the seller's
-- Connect account) when a dispute is lost and `debit_negative_balances`
-- is enabled, or when ops manually reverses for an event cancellation.
ALTER TABLE public.transfers DROP CONSTRAINT IF EXISTS transfers_status_check;
ALTER TABLE public.transfers
  ADD CONSTRAINT transfers_status_check
  CHECK (status IN (
    'pending',
    'seller_sent',
    'buyer_confirmed',
    'disputed',
    'expired',
    'auto_released',
    'reversed'
  ));

COMMIT;
