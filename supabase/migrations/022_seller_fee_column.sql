-- =============================================================================
-- Migration 022: 10/10 fee model — buyer fee + seller fee tracking
-- =============================================================================
-- Buyer pays listing × 1.10. Seller receives listing × 0.90.
-- Platform retains 0.20 × listing (10% from buyer side + 10% from seller side).
--
-- Schema change:
--   • Rename payments.service_fee → payments.buyer_fee (semantic clarity).
--   • Add payments.seller_fee (NEW): the 10% withheld from seller payout.
--
-- Backfill rule:
--   Historical rows (created under the OLD 5%-buyer-only model) get
--   seller_fee=0 — those payments transferred the full listing price to
--   the seller. This is correct: do not retroactively withhold from
--   already-paid sellers.
--
-- Idempotent: re-running this migration is a no-op once columns are in place.
-- =============================================================================

BEGIN;

-- ── 1. Rename service_fee → buyer_fee (no-op if already renamed) ────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'payments'
      AND column_name  = 'service_fee'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'payments'
      AND column_name  = 'buyer_fee'
  ) THEN
    EXECUTE 'ALTER TABLE public.payments RENAME COLUMN service_fee TO buyer_fee';
  END IF;
END
$$;

-- ── 2. Add seller_fee column (defaults to 0 for historical rows) ────────────
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS seller_fee int NOT NULL DEFAULT 0
    CHECK (seller_fee >= 0);

COMMIT;
