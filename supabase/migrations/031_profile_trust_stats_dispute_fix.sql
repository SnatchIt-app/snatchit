-- =============================================================================
-- Migration 031: get_profile_trust_stats(p_user_id) RPC  (v3 — dispute fix)
-- =============================================================================
-- Fixes the latent dispute bugs found in the final trust-system audit:
--
--   B1:  Post-payout Stripe chargebacks (transfer stays 'auto_released',
--        chargeback exists only in public.disputes) were invisible to
--        disputes_opened and inflated the seller success-rate numerator.
--        → disputes_opened now unions Stripe disputes (via transfer_id), and
--          the numerator subtracts transfers with a known seller-lost event.
--   B1b: disputes rows with NULL transfer_id have no reliable user link.
--        → excluded from all user-level metrics (no crash, no misattribution).
--   B2:  Stripe outcomes were attributed to both sides. Corrected semantics:
--          disputes.status = 'lost' → seller/platform lost (counts vs SELLER)
--          disputes.status = 'won'  → buyer lost           (counts vs BUYER)
--   B2b: disputes_lost summed the in-app leg and the Stripe leg without
--        dedup, double-counting a dispute carrying both markers.
--        → dispute-event model: events are keyed by transfer_id; each
--          transfer contributes at most ONE lost-dispute event per user.
--
-- Dispute-event model:
--   stripe_d           — public.disputes aggregated per transfer_id
--                        (bool_or so multiple Stripe rows on one transfer
--                        dedupe to a single event; NULL transfer_id excluded).
--   seller-lost(t)     — t.dispute_resolution IN
--                        ('resolved_buyer_refunded','resolved_partial_refund')
--                        OR stripe lost on t.
--   buyer-lost(t)      — t.dispute_resolution = 'resolved_seller_paid'
--                        OR stripe won on t.
--   dispute-opened(t)  — t.disputed_at IS NOT NULL OR t.status = 'disputed'
--                        OR any Stripe dispute linked to t.
--
-- Success rate (seller-side only):
--   numerator   = transfers (seller, status IN buyer_confirmed/auto_released)
--                 MINUS transfers with a known seller-lost event  (B1 fix)
--   denominator = transfers (seller) in terminal states
--                 buyer_confirmed/auto_released/disputed/expired/reversed.
--                 Seller-side Stripe-disputed-but-still-auto_released
--                 transfers are already included exactly once via
--                 'auto_released' — no addition needed, no double count.
--
-- Unchanged: completed_sales, completed_purchases, active_listings,
-- member_since, return signature (8 columns — no TypeScript change needed),
-- 1-row guarantee (top-level SELECT with no FROM), SECURITY DEFINER,
-- pinned search_path, grants.
--
-- Idempotent — CREATE OR REPLACE, identical signature.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_profile_trust_stats(p_user_id uuid)
RETURNS TABLE (
  completed_sales              int,
  completed_purchases          int,
  active_listings              int,
  disputes_opened              int,
  disputes_lost                int,
  seller_terminal_total        int,
  seller_terminal_successful   int,
  member_since                 timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Stripe disputes deduped to one row per transfer. NULL transfer_id rows
  -- have no reliable user mapping → excluded from user-level metrics (B1b).
  WITH stripe_d AS (
    SELECT transfer_id,
           bool_or(status = 'lost') AS stripe_lost,  -- seller/platform lost
           bool_or(status = 'won')  AS stripe_won    -- buyer lost
      FROM public.disputes
     WHERE transfer_id IS NOT NULL
     GROUP BY transfer_id
  )
  SELECT
    -- 1) Completed Sales — seller-side terminal-successful (unchanged)
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released'))
      AS completed_sales,

    -- 2) Completed Purchases — buyer-side terminal-successful (unchanged)
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE buyer_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released'))
      AS completed_purchases,

    -- 3) Active Listings — currently live + accepting bids (unchanged)
    (SELECT COUNT(*)::int
       FROM public.listings
      WHERE seller_id      = p_user_id
        AND status         = 'active'
        AND auction_status = 'active')
      AS active_listings,

    -- 4) Disputes Opened — unique dispute events involving the user.
    --    One transfer = max one event, regardless of how many markers
    --    (in-app freeze AND Stripe rows) it carries.  (B1 + B2b fix)
    (SELECT COUNT(*)::int
       FROM public.transfers t
      WHERE (t.buyer_id = p_user_id OR t.seller_id = p_user_id)
        AND (   t.disputed_at IS NOT NULL
             OR t.status = 'disputed'
             OR EXISTS (SELECT 1 FROM stripe_d sd WHERE sd.transfer_id = t.id)))
      AS disputes_opened,

    -- 5) Disputes Lost — unique lost-dispute events, side-correct (B2),
    --    deduped per transfer (B2b). stripe_d is grouped by transfer_id so
    --    the LEFT JOIN is 1:1 — no row multiplication.
    (SELECT COUNT(*)::int
       FROM public.transfers t
       LEFT JOIN stripe_d sd ON sd.transfer_id = t.id
      WHERE (t.seller_id = p_user_id
             AND (t.dispute_resolution IN ('resolved_buyer_refunded',
                                           'resolved_partial_refund')
                  OR COALESCE(sd.stripe_lost, false)))
         OR (t.buyer_id = p_user_id
             AND (t.dispute_resolution = 'resolved_seller_paid'
                  OR COALESCE(sd.stripe_won, false))))
      AS disputes_lost,

    -- 6) Seller terminal denominator (unchanged set — Stripe-disputed
    --    auto_released transfers are already counted once here).
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released',
                       'disputed','expired','reversed'))
      AS seller_terminal_total,

    -- 7) Seller terminal numerator — successes MINUS known seller-lost
    --    events (B1 fix: a post-payout chargeback lost while the transfer
    --    sits in 'auto_released' no longer counts as a success).
    --    COALESCE guards the NULL dispute_resolution three-valued-logic trap.
    (SELECT COUNT(*)::int
       FROM public.transfers t
       LEFT JOIN stripe_d sd ON sd.transfer_id = t.id
      WHERE t.seller_id = p_user_id
        AND t.status IN ('buyer_confirmed','auto_released')
        AND NOT (COALESCE(t.dispute_resolution IN ('resolved_buyer_refunded',
                                                   'resolved_partial_refund'),
                          false)
                 OR COALESCE(sd.stripe_lost, false)))
      AS seller_terminal_successful,

    -- 8) Member Since — canonical profiles.created_at, auth.users fallback
    --    (unchanged; no FROM clause preserves the 1-row guarantee).
    COALESCE(
      (SELECT created_at FROM public.profiles WHERE id = p_user_id),
      (SELECT created_at FROM auth.users      WHERE id = p_user_id)
    ) AS member_since
  ;
$$;

REVOKE ALL ON FUNCTION public.get_profile_trust_stats(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_profile_trust_stats(uuid) TO authenticated, anon;

COMMIT;
