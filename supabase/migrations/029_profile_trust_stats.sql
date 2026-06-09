-- =============================================================================
-- Migration 029: get_profile_trust_stats(p_user_id) RPC
-- =============================================================================
-- Public marketplace trust metrics for the profile screen.
--
-- NEVER returns: email, phone, Stripe IDs, payout info, transaction amounts,
-- wallet balances. Only counts + ratios + member_since.
--
-- Status taxonomy (transfers.status, current as of migration 024):
--   pending → seller_sent → buyer_confirmed
--                       ↘   auto_released   (post 24h auto-release)
--                       ↘   disputed         (buyer raises)
--                       ↘   expired          (seller didn't send)
--                       ↘   reversed         (Stripe chargeback lost)
--
-- Terminal-for-success-rate: buyer_confirmed, auto_released, disputed,
--                            expired, reversed.
--
-- Dispute resolution taxonomy (transfers.dispute_resolution, migration 011):
--   resolved_seller_paid       → buyer lost the dispute
--   resolved_buyer_refunded    → seller lost the dispute
--   resolved_partial_refund    → seller lost (treated as loss for seller)
--
-- SECURITY DEFINER so the function can read auth.users.created_at without
-- granting public SELECT on auth schema. Returns a single row.
--
-- Idempotent — CREATE OR REPLACE safe to re-run.
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
SET search_path = public, auth
AS $$
  WITH
  sales AS (
    SELECT COUNT(*)::int AS n
      FROM public.transfers
     WHERE seller_id = p_user_id
       AND status IN ('buyer_confirmed','auto_released')
  ),
  purchases AS (
    SELECT COUNT(*)::int AS n
      FROM public.transfers
     WHERE buyer_id = p_user_id
       AND status IN ('buyer_confirmed','auto_released')
  ),
  active AS (
    SELECT COUNT(*)::int AS n
      FROM public.listings
     WHERE seller_id      = p_user_id
       AND status         = 'active'
       AND auction_status = 'active'
  ),
  opened AS (
    -- Buyer-initiated disputes — `buyer_dispute_transfer` sets disputed_at.
    SELECT COUNT(*)::int AS n
      FROM public.transfers
     WHERE buyer_id    = p_user_id
       AND disputed_at IS NOT NULL
  ),
  lost AS (
    -- Disputes resolved AGAINST this user.
    SELECT COUNT(*)::int AS n
      FROM public.transfers
     WHERE (
            seller_id = p_user_id
        AND dispute_resolution IN ('resolved_buyer_refunded','resolved_partial_refund')
       )
        OR (
            buyer_id  = p_user_id
        AND dispute_resolution = 'resolved_seller_paid'
       )
  ),
  seller_term AS (
    -- Denominator: every seller-side transfer that reached a terminal state.
    SELECT COUNT(*)::int AS total,
           COUNT(*) FILTER (
             WHERE status IN ('buyer_confirmed','auto_released')
           )::int AS successful
      FROM public.transfers
     WHERE seller_id = p_user_id
       AND status IN ('buyer_confirmed','auto_released','disputed','expired','reversed')
  ),
  member AS (
    SELECT created_at FROM auth.users WHERE id = p_user_id
  )
  SELECT
    sales.n,
    purchases.n,
    active.n,
    opened.n,
    lost.n,
    seller_term.total,
    seller_term.successful,
    member.created_at
  FROM sales, purchases, active, opened, lost, seller_term, member;
$$;

REVOKE ALL ON FUNCTION public.get_profile_trust_stats(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_profile_trust_stats(uuid) TO authenticated, anon;

COMMIT;
