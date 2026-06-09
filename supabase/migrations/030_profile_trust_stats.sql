-- =============================================================================
-- Migration 029: get_profile_trust_stats(p_user_id) RPC  (v2)
-- =============================================================================
-- Marketplace trust metrics for the profile screen. Counts + ratios only —
-- NEVER emails, phone, Stripe IDs, payout info, or transaction amounts.
--
-- v2 fixes over the initial cut:
--   B1: replaced cross-join over single-row CTEs with explicit subselects in
--       a single top-level SELECT. The previous form returned zero rows
--       whenever the `member` CTE was empty (anonymized / missing auth.users),
--       which made every metric NULL → rendered as 0 in the client.
--   B2: member_since now sourced from public.profiles.created_at (public-RLS-
--       readable, canonical) instead of auth.users.created_at.
--   B3: disputes_opened now counts disputed_at IS NOT NULL OR status='disputed'
--       so Stripe-driven chargebacks (webhook freezes status without always
--       writing disputed_at in older code paths) are not missed.
--   B5: disputes_lost now unions in-app dispute_resolution with Stripe-side
--       disputes.status = 'lost' joined via transfer_id.
--
-- Terminal seller states (denominator for success rate):
--   buyer_confirmed, auto_released, disputed, expired, reversed.
-- Successful seller states (numerator):
--   buyer_confirmed, auto_released.
--
-- SECURITY DEFINER + search_path = public so the function runs with the
-- function-owner's privileges and never accidentally resolves to a public
-- schema-search-path-injected table.
--
-- Idempotent — CREATE OR REPLACE.
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
  SELECT
    -- 1) Completed Sales — seller-side terminal-successful
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released'))
      AS completed_sales,

    -- 2) Completed Purchases — buyer-side terminal-successful
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE buyer_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released'))
      AS completed_purchases,

    -- 3) Active Listings — currently live + accepting bids
    (SELECT COUNT(*)::int
       FROM public.listings
      WHERE seller_id      = p_user_id
        AND status         = 'active'
        AND auction_status = 'active')
      AS active_listings,

    -- 4) Disputes Opened — buyer-initiated dispute (in-app + Stripe chargeback).
    --    The OR clause catches historical rows where stripe-webhook freezes
    --    status without writing disputed_at.
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE buyer_id = p_user_id
        AND (disputed_at IS NOT NULL OR status = 'disputed'))
      AS disputes_opened,

    -- 5) Disputes Lost — resolutions against this user (any side) OR
    --    Stripe-side dispute officially lost.
    (
      (SELECT COUNT(*)::int
         FROM public.transfers
        WHERE (
              seller_id = p_user_id
          AND dispute_resolution IN ('resolved_buyer_refunded','resolved_partial_refund')
        )
          OR (
              buyer_id  = p_user_id
          AND dispute_resolution = 'resolved_seller_paid'
        ))
      +
      (SELECT COUNT(*)::int
         FROM public.disputes d
         JOIN public.transfers t ON t.id = d.transfer_id
        WHERE (t.seller_id = p_user_id OR t.buyer_id = p_user_id)
          AND d.status = 'lost')
    )::int AS disputes_lost,

    -- 6) Seller terminal denominator
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released','disputed','expired','reversed'))
      AS seller_terminal_total,

    -- 7) Seller terminal numerator
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released'))
      AS seller_terminal_successful,

    -- 8) Member Since — canonical profiles.created_at (public-RLS readable).
    --    No FROM clause + COALESCE so a missing profile row still returns a
    --    row (with NULL member_since) instead of collapsing the whole result.
    COALESCE(
      (SELECT created_at FROM public.profiles WHERE id = p_user_id),
      (SELECT created_at FROM auth.users      WHERE id = p_user_id)
    ) AS member_since
  ;
$$;

REVOKE ALL ON FUNCTION public.get_profile_trust_stats(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_profile_trust_stats(uuid) TO authenticated, anon;

COMMIT;
