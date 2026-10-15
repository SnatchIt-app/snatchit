-- ============================================================================
-- 20261015000000_listing_public_visibility.sql — registry 154 (pgTAP 221).
-- Hidden listings leave public access on every surface and every build; their private parties keep it.
-- Owner authorisation 2026-10-15 (A's chat): all existing listings leave public access; private payment,
-- refund, transfer, dispute and order history is preserved; no money state changes.
--
-- WHY. public.listings and public.bids each had one public read path, listings_select_all and
-- bids_select_all (070:43 and 070:24), both FOR SELECT TO public USING (true). Every client, including
-- installed builds 27 and earlier that read PostgREST and Realtime directly, saw every row. RLS is the
-- only lever that reaches those builds, so the fix is server-side and policy-shaped.
--
-- WHAT.
--   1. public.listing_visibility(listing_id PK -> listings ON DELETE CASCADE, hidden_at, hidden_reason,
--      hidden_by): a row means "hidden". RLS on, NO policies, REVOKE ALL from PUBLIC/anon/authenticated/
--      service_role, then GRANT SELECT, INSERT, DELETE to service_role. Clients can neither read nor write
--      it; only service_role, the postgres runner and the definer helpers below touch it. A separate table
--      keeps visibility out of the seller-writable listings row (anon/authenticated hold table-level UPDATE
--      there), causes no updated_at churn and no Realtime fan-out.
--   2. public.listing_is_public(uuid) and public.listing_private_party(uuid): LANGUAGE sql, STABLE,
--      SECURITY DEFINER, search_path ''. anon-execute BY EXPLICIT GRANT (written justification, SEC-2 B5):
--      each is evaluated inside a policy that applies to anon, so anon must hold EXECUTE, and each returns
--      only a boolean. They also become PostgREST RPCs; listing_is_public(id) answers "is this id hidden"
--      for a caller who already holds the uuid, and listing_private_party is false for anon. Definer rights
--      also break the listings<->bids policy recursion (42P17) and read listing_visibility past its RLS.
--      listing_private_party: the caller (auth.uid(), never NULL) is the seller, highest bidder, winner or
--      reservation holder on the row, a bidder on it, a buyer or seller on one of its payments, or a buyer
--      or seller on its transfer. NOT saved_listings, reports or notifications (a user can create the first
--      two for any id; the server writes the third). NO admin clause: the console reads through ops.*
--      definers, and an admin clause would put every hidden row back into admins' consumer feeds.
--   3. listings_select_all -> listings_select_visible and bids_select_all -> bids_select_visible,
--      FOR SELECT TO anon, authenticated USING (listing_is_public(..) OR listing_private_party(..)).
--      bids_select_own stays. No kernel.*, ops.* or is_admin() in any policy anon reaches (anon has no
--      USAGE on kernel; is_admin() is not authenticated-executable).
--   4. Invariant "a hidden listing is never live": guard_hidden_listing_not_live() (SECURITY DEFINER,
--      search_path ''), two triggers.
--        trg_hidden_listing_not_live  BEFORE UPDATE ON listings: a visibility row exists AND NEW is
--          status 'active', auction_status 'active', ends_at > now() -> 'Hidden listing cannot be made
--          live.' Blocks admin_relist_listing, any extension and any reactivation, for every caller.
--        trg_listing_visibility_not_live  BEFORE INSERT ON listing_visibility: the listing is live now ->
--          'Cannot hide a live listing; end or cancel it first.' "Live" here also counts a listing under a
--          Buy Now hold (status 'reserved') whose auction is active and unexpired: when that hold lapses,
--          cleanup_expired_reservations() returns it to live in ONE set-based UPDATE, the first trigger
--          would raise, and the whole sweep (every listing's expired hold) would fail. Refusing to hide
--          such a row is the only way the invariant cannot wedge the sweep. The row is FOR SHARE-locked,
--          so a concurrent relist or extension serialises against the hide.
--      With this, the live-state checks already in reserve_buy_now, validate_and_apply_bid, finalize and
--      checkout refuse hidden rows. Those functions are NOT edited.
--   5. get_profile_trust_stats(uuid): same signature, return type, attributes and grants; every
--      transfers-based count and active_listings now require listing_is_public(listing), so a public
--      profile shows nothing derived from a hidden listing. The production body before this file is 031's
--      verbatim (prosrc md5 b048a327d1fa23fdf409d86f2b56e427, functiondef md5 23719c73db47a2815d5102b11f4771f3).
--
-- WHAT STAYS. No row of listings, bids, payments, transfers, refunds, payouts or disputes is written. Every
--   private party keeps their history (D-section of 221). Edge functions read listings as service_role
--   (BYPASSRLS) and are unaffected; the admin console reads through ops.* definers. market.listing_unified
--   is security_invoker and inherits the new policy. Realtime postgres_changes applies the same RLS.
--   This file hides nothing by itself: hiding is a separate data step (docs/release/packages/154_20261015/).
--
-- NOT COVERED (reported, not fixed here): public auction-media cover URLs stay fetchable and the bucket is
--   listable by anon; running old-app sessions keep already-loaded rows until refresh; /_next/image caches
--   covers 4 h; proof_of_ownership_path stays readable on public listings (pre-existing).
--
-- GATE-2 census (public): tables 34 -> 35 (+listing_visibility); functions 116 -> 119 (+listing_is_public,
--   listing_private_party, guard_hidden_listing_not_live); policies 37 -> 37 (two 1-for-1 replacements);
--   triggers 43 -> 45 (+trg_hidden_listing_not_live, trg_listing_visibility_not_live).
-- ROLLBACK: supabase/rollbacks/20261015000000_listing_public_visibility_rollback.sql — restores both
--   USING (true) policies and 031's get_profile_trust_stats body, drops the new policies, triggers and
--   functions, and KEEPS listing_visibility and its rows (archival; inert). It RE-EXPOSES every hidden
--   listing publicly.
-- VERIFY (read-only): select policyname, roles, qual from pg_policies where tablename in ('listings','bids')
--   and cmd = 'SELECT';  -- listings_select_visible, bids_select_own, bids_select_visible
-- FAILURE BEHAVIOUR: one transaction; lock_timeout 3s. DROP/CREATE POLICY and CREATE TRIGGER take brief
--   ACCESS EXCLUSIVE / SHARE ROW EXCLUSIVE locks on listings and bids; it fails cleanly rather than queue.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. the deny-all side table ──────────────────────────────────────────────
-- IF NOT EXISTS: this file's rollback KEEPS the table and its rows (archival), so a re-apply after a
-- rollback must reuse them. The DO block refuses that re-apply if a kept row now names a live listing
-- (it could have been relisted while the table was inert): hiding it again would break the invariant.
CREATE TABLE IF NOT EXISTS public.listing_visibility (
  listing_id    uuid        PRIMARY KEY REFERENCES public.listings(id) ON DELETE CASCADE,
  hidden_at     timestamptz NOT NULL DEFAULT now(),
  hidden_reason text        NOT NULL CHECK (char_length(hidden_reason) BETWEEN 1 AND 300),
  hidden_by     text        NOT NULL CHECK (char_length(hidden_by) BETWEEN 1 AND 120)
);
DO $live$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n
    FROM public.listing_visibility v JOIN public.listings l ON l.id = v.listing_id
   WHERE l.status IN ('active', 'reserved') AND l.auction_status = 'active' AND l.ends_at > now();
  IF n > 0 THEN
    RAISE EXCEPTION '154: % kept listing_visibility row(s) name a live listing; end those listings (or delete their rows) before re-applying.', n
      USING ERRCODE = 'P0001';
  END IF;
END
$live$;
ALTER TABLE public.listing_visibility ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.listing_visibility FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT, DELETE ON public.listing_visibility TO service_role;
COMMENT ON TABLE public.listing_visibility IS
  '154: a row hides its listing from public reads (anon and non-party users) on every surface. RLS on, no policies; '
  'service_role holds SELECT/INSERT/DELETE only (a row is added or removed, never rewritten). Read by '
  'listing_is_public(); a live listing cannot be hidden and a hidden listing cannot be made live.';

-- ── 2. the two policy predicates ────────────────────────────────────────────
CREATE FUNCTION public.listing_is_public(p_listing_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.listing_visibility v WHERE v.listing_id = p_listing_id)
$$;
REVOKE ALL ON FUNCTION public.listing_is_public(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.listing_is_public(uuid) TO anon, authenticated;
COMMENT ON FUNCTION public.listing_is_public(uuid) IS
  '154: true unless public.listing_visibility holds a row for the listing. anon-execute by explicit grant: it is '
  'evaluated inside the anon-reachable listings/bids SELECT policies and returns only a boolean.';

CREATE FUNCTION public.listing_private_party(p_listing_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (SELECT auth.uid()) IS NOT NULL AND (
       EXISTS (SELECT 1 FROM public.listings l
                WHERE l.id = p_listing_id
                  AND (SELECT auth.uid()) IN (l.seller_id, l.highest_bidder_id, l.winner_user_id, l.reserved_by))
    OR EXISTS (SELECT 1 FROM public.bids b
                WHERE b.listing_id = p_listing_id AND b.bidder_id = (SELECT auth.uid()))
    OR EXISTS (SELECT 1 FROM public.payments p
                WHERE p.listing_id = p_listing_id AND (SELECT auth.uid()) IN (p.buyer_id, p.seller_id))
    OR EXISTS (SELECT 1 FROM public.transfers t
                WHERE t.listing_id = p_listing_id AND (SELECT auth.uid()) IN (t.buyer_id, t.seller_id))
  )
$$;
REVOKE ALL ON FUNCTION public.listing_private_party(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.listing_private_party(uuid) TO anon, authenticated;
COMMENT ON FUNCTION public.listing_private_party(uuid) IS
  '154: true when the signed-in caller is the listing''s seller, highest bidder, winner or reservation holder, a '
  'bidder on it, a buyer/seller on one of its payments, or a buyer/seller on its transfer. NULL-safe; false for anon. '
  'Deliberately excludes saved_listings, reports, notifications and any admin clause. anon-execute by explicit grant: '
  'evaluated inside the anon-reachable SELECT policies; returns only a boolean.';

-- ── 3. the two public read policies ─────────────────────────────────────────
DROP POLICY listings_select_all ON public.listings;
CREATE POLICY listings_select_visible ON public.listings
  FOR SELECT TO anon, authenticated
  USING (public.listing_is_public(id) OR public.listing_private_party(id));

DROP POLICY bids_select_all ON public.bids;
CREATE POLICY bids_select_visible ON public.bids
  FOR SELECT TO anon, authenticated
  USING (public.listing_is_public(listing_id) OR public.listing_private_party(listing_id));
-- bids_select_own (TO authenticated USING bidder_id = auth.uid()) is kept unchanged.

-- ── 4. invariant: a hidden listing is never live ────────────────────────────
CREATE FUNCTION public.guard_hidden_listing_not_live()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_live boolean;
BEGIN
  IF TG_TABLE_NAME = 'listings' THEN
    -- BEFORE UPDATE ON public.listings, every caller (service_role and postgres included).
    IF NEW.status = 'active' AND NEW.auction_status = 'active' AND NEW.ends_at > now()
       AND EXISTS (SELECT 1 FROM public.listing_visibility v WHERE v.listing_id = NEW.id) THEN
      RAISE EXCEPTION 'Hidden listing cannot be made live.'
        USING ERRCODE = 'P0001', HINT = 'LISTING_HIDDEN';
    END IF;
    RETURN NEW;
  END IF;

  -- BEFORE INSERT ON public.listing_visibility. FOR SHARE serialises against a concurrent relist or
  -- extension of the same row. A Buy Now hold on an active, unexpired auction counts as live (see header).
  SELECT l.status IN ('active', 'reserved') AND l.auction_status = 'active' AND l.ends_at > now()
    INTO v_live
    FROM public.listings l
   WHERE l.id = NEW.listing_id
     FOR SHARE;
  IF coalesce(v_live, false) THEN
    RAISE EXCEPTION 'Cannot hide a live listing; end or cancel it first.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_LIVE';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_hidden_listing_not_live() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_hidden_listing_not_live() IS
  '154: invariant "a hidden listing is never live". On listings (BEFORE UPDATE) refuses making a hidden row live; on '
  'listing_visibility (BEFORE INSERT) refuses hiding a live row (or one under a hold that would return to live).';

CREATE TRIGGER trg_hidden_listing_not_live
  BEFORE UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_hidden_listing_not_live();
CREATE TRIGGER trg_listing_visibility_not_live
  BEFORE INSERT ON public.listing_visibility
  FOR EACH ROW EXECUTE FUNCTION public.guard_hidden_listing_not_live();

-- ── 5. public trust stats: nothing derived from a hidden listing ────────────
-- 031's body with listing_is_public() added to every transfers-based count and to active_listings.
-- Signature, return type, LANGUAGE, STABLE, SECURITY DEFINER and search_path unchanged.
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
  -- 154: every count below also requires the listing to be public, so a
  -- public profile shows nothing derived from a hidden (legacy) listing.
  WITH stripe_d AS (
    SELECT transfer_id,
           bool_or(status = 'lost') AS stripe_lost,  -- seller/platform lost
           bool_or(status = 'won')  AS stripe_won    -- buyer lost
      FROM public.disputes
     WHERE transfer_id IS NOT NULL
     GROUP BY transfer_id
  )
  SELECT
    -- 1) Completed Sales — seller-side terminal-successful
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released')
        AND public.listing_is_public(listing_id))
      AS completed_sales,

    -- 2) Completed Purchases — buyer-side terminal-successful
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE buyer_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released')
        AND public.listing_is_public(listing_id))
      AS completed_purchases,

    -- 3) Active Listings — currently live + accepting bids
    (SELECT COUNT(*)::int
       FROM public.listings
      WHERE seller_id      = p_user_id
        AND status         = 'active'
        AND auction_status = 'active'
        AND public.listing_is_public(id))
      AS active_listings,

    -- 4) Disputes Opened — unique dispute events involving the user.
    --    One transfer = max one event, regardless of how many markers
    --    (in-app freeze AND Stripe rows) it carries.  (B1 + B2b fix)
    (SELECT COUNT(*)::int
       FROM public.transfers t
      WHERE (t.buyer_id = p_user_id OR t.seller_id = p_user_id)
        AND (   t.disputed_at IS NOT NULL
             OR t.status = 'disputed'
             OR EXISTS (SELECT 1 FROM stripe_d sd WHERE sd.transfer_id = t.id))
        AND public.listing_is_public(t.listing_id))
      AS disputes_opened,

    -- 5) Disputes Lost — unique lost-dispute events, side-correct (B2),
    --    deduped per transfer (B2b). stripe_d is grouped by transfer_id so
    --    the LEFT JOIN is 1:1 — no row multiplication.
    (SELECT COUNT(*)::int
       FROM public.transfers t
       LEFT JOIN stripe_d sd ON sd.transfer_id = t.id
      WHERE ((t.seller_id = p_user_id
              AND (t.dispute_resolution IN ('resolved_buyer_refunded',
                                            'resolved_partial_refund')
                   OR COALESCE(sd.stripe_lost, false)))
          OR (t.buyer_id = p_user_id
              AND (t.dispute_resolution = 'resolved_seller_paid'
                   OR COALESCE(sd.stripe_won, false))))
        AND public.listing_is_public(t.listing_id))
      AS disputes_lost,

    -- 6) Seller terminal denominator (Stripe-disputed auto_released
    --    transfers are already counted once here).
    (SELECT COUNT(*)::int
       FROM public.transfers
      WHERE seller_id = p_user_id
        AND status IN ('buyer_confirmed','auto_released',
                       'disputed','expired','reversed')
        AND public.listing_is_public(listing_id))
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
                 OR COALESCE(sd.stripe_lost, false))
        AND public.listing_is_public(t.listing_id))
      AS seller_terminal_successful,

    -- 8) Member Since — canonical profiles.created_at, auth.users fallback
    --    (unchanged; no FROM clause preserves the 1-row guarantee).
    COALESCE(
      (SELECT created_at FROM public.profiles WHERE id = p_user_id),
      (SELECT created_at FROM auth.users      WHERE id = p_user_id)
    ) AS member_since
  ;
$$;
-- Grants unchanged (067): authenticated and service_role, never anon. Restated for idempotence.
REVOKE ALL ON FUNCTION public.get_profile_trust_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_profile_trust_stats(uuid) TO authenticated, service_role;
COMMENT ON FUNCTION public.get_profile_trust_stats(uuid) IS
  'Public seller-profile trust counts (031). 154: every transfers-based count and active_listings exclude hidden '
  'listings (listing_is_public), so a public profile shows nothing derived from a hidden listing.';

COMMIT;
