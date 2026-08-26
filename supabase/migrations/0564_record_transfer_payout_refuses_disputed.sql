-- 056d — record_transfer_payout must refuse a disputed transfer.
--
-- Found by the 056b regression suite. The trusted final money-recording writer
-- guarded only on "not already paid":
--
--     WHERE id = p_transfer_id
--       AND stripe_transfer_id IS NULL
--       AND payout_released_at IS NULL
--
-- Proven live against a freshly disputed transfer (rolled back):
--
--     L08 buyer_dispute_transfer                 => OK status=disputed
--     A09 record_transfer_payout on DISPUTED row => *** PAID ***
--
-- Every dispute check in the system lives in a caller, never in the writer:
--   confirm-and-release/index.ts:279      status/disputed_at pre-check
--   confirm-and-release/index.ts:440-445  recheck before the Stripe call
--   enforce-transfer-expiry/index.ts:553  cron payout pre-flight
--   enforce-transfer-expiry/index.ts:797  Phase 2b sweep filter
--
-- and payoutEligibility() in _shared/payout-logic.ts:80 — the one function that
-- reads like the canonical gate — is imported by nothing except its own test.
-- So the protection is four hand-rolled copies with no backstop: any fifth
-- payout path, or a reordering that lets a chargeback land inside the
-- read-then-write window, pays out a disputed order. That is money leaving the
-- platform for an order the buyer has already contested.
--
-- The predicate is written so a dispute resolved in the seller's favour still
-- pays. 'resolved_seller_paid' is one of the three values already allowed by
-- transfers_dispute_resolution_check, so this composes with the resolution RPC
-- rather than blocking it.
--
-- Both live callers are unaffected: each already refuses to call this function
-- unless disputed_at IS NULL, so no currently-succeeding payout changes
-- behaviour. This only closes the gap beneath them.

CREATE OR REPLACE FUNCTION public.record_transfer_payout(p_transfer_id uuid, p_stripe_transfer_id text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  -- Without this guard a NULL arg would write NULL into stripe_transfer_id and
  -- then satisfy its own IS NULL predicate on the next retry.
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RETURN false;
  END IF;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);

  -- Unifies the two callers' WHERE clauses. Strictly stricter than either:
  -- enforce-transfer-expiry guarded on stripe_transfer_id IS NULL,
  -- confirm-and-release on payout_released_at IS NULL. Verified safe -- the two
  -- columns are only ever written together by these same two sites, and a
  -- production census found 22 both-set / 13 neither-set / 0 split rows.
  UPDATE public.transfers
     SET payout_released_at = now(),
         stripe_transfer_id = p_stripe_transfer_id
   WHERE id = p_transfer_id
     AND stripe_transfer_id IS NULL
     AND payout_released_at IS NULL
     -- 056d: an open dispute blocks payout here, not just in the callers.
     -- A dispute decided for the seller is explicitly still payable.
     AND (disputed_at IS NULL OR dispute_resolution = 'resolved_seller_paid');
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;   -- id is the PK
END; $function$;

COMMENT ON FUNCTION public.record_transfer_payout(uuid, text) IS
  'Records a completed Stripe transfer. Idempotent, and refuses any transfer '
  'with an open dispute -- only a dispute resolved resolved_seller_paid is '
  'payable (056d).';
