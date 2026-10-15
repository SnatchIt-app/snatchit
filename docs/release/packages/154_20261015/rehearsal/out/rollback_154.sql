-- ============================================================================
-- ROLLBACK for 20261015000000_listing_public_visibility.sql (registry 154).
--
-- !! THIS ROLLBACK RE-EXPOSES EVERY HIDDEN LISTING PUBLICLY. !!
-- It restores listings_select_all and bids_select_all exactly as applied before 154 (070:43 and 070:24,
-- read from production pg_policies 2026-10-15: FOR SELECT TO public USING (true)), so anon and every
-- signed-in user read every listing and every bid again, hidden or not, on every build.
--
-- Restores the APPLIED body of public.get_profile_trust_stats(uuid): 031's, verbatim (production prosrc md5
-- b048a327d1fa23fdf409d86f2b56e427, pg_get_functiondef md5 23719c73db47a2815d5102b11f4771f3, no comment;
-- ACL {postgres,authenticated,service_role}=X is preserved by CREATE OR REPLACE). Drops the two new policies,
-- the two invariant triggers and the four new functions (the three predicates/guard and the is_public(listings)
-- computed field: a build that filters .eq('is_public', true) gets a 400 again once this runs).
-- KEEPS public.listing_visibility and every row in it: archival record of what was hidden, by whom and why.
-- With its readers gone the table is inert (RLS on, no policies, service_role only). Re-applying 154 later
-- reuses it (CREATE TABLE IF NOT EXISTS) and refuses while a kept row names a live listing.
-- Order: run 156's and 155's rollbacks first if they are applied.
-- CONSEQUENCE: legacy test/beta listings, their bids and their trust-stat counts become public again
-- immediately, including to installed old builds. The owner must accept this explicitly.
-- Run only under owner approval, with D's read-back.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DROP TRIGGER IF EXISTS trg_hidden_listing_not_live ON public.listings;
DROP TRIGGER IF EXISTS trg_listing_visibility_not_live ON public.listing_visibility;

DROP POLICY IF EXISTS listings_select_visible ON public.listings;
DROP POLICY IF EXISTS bids_select_visible ON public.bids;
-- 070 verbatim
create policy "listings_select_all" on public.listings for select using (true);
create policy "bids_select_all" on public.bids for select using (true);

-- 031's body, verbatim (restored BEFORE listing_is_public is dropped: the 154 body calls it)
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

COMMENT ON FUNCTION public.get_profile_trust_stats(uuid) IS NULL;

DROP FUNCTION IF EXISTS public.guard_hidden_listing_not_live();
DROP FUNCTION IF EXISTS public.is_public(public.listings);   -- the computed field calls listing_is_public
DROP FUNCTION IF EXISTS public.listing_private_party(uuid);
DROP FUNCTION IF EXISTS public.listing_is_public(uuid);

-- public.listing_visibility is deliberately NOT dropped (archival; see header).

COMMIT;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000000' AND to_regprocedure('public.listing_is_public(uuid)') IS NULL AND to_regprocedure('public.listing_private_party(uuid)') IS NULL AND to_regprocedure('public.is_public(public.listings)') IS NULL AND to_regprocedure('public.guard_hidden_listing_not_live()') IS NULL AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'listings' AND policyname = 'listings_select_all' AND qual = 'true') AND EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'bids' AND policyname = 'bids_select_all' AND qual = 'true') AND md5(pg_get_functiondef('public.get_profile_trust_stats(uuid)'::regprocedure)) = '23719c73db47a2815d5102b11f4771f3';
