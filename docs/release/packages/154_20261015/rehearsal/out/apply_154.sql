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
--   4. Invariant "a hidden listing is never live, held or extended": guard_hidden_listing_not_live()
--      (SECURITY DEFINER, search_path ''), two triggers, for EVERY caller (service_role and postgres too).
--      "Open" means what reserve_buy_now accepts, not only what the Home feed calls live. reserve_buy_now
--      refuses only a sold row, a cancelled auction, a succeeded payment, an expired clock (now() > ends_at)
--      and another buyer's live hold. It never requires auction_status = 'active'. So:
--        OPEN(l)      = l.status IN ('active','reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now()
--        LIVE_HOLD(l) = l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false)
--                       (a hold that is not provably lapsed; create-payment-intent mints for a live one)
--        trg_listing_visibility_not_live  BEFORE INSERT ON listing_visibility (hide time):
--          OPEN -> 'Cannot hide a live listing; end or cancel it first.'
--          LIVE_HOLD -> 'Cannot hide a listing under a live Buy Now hold; let the hold lapse or complete first.'
--          The row is FOR SHARE-locked, so a concurrent relist, extension or reserve serialises against it.
--          A LAPSED hold on a closed auction may be hidden: nobody can pay for it (create-payment-intent
--          needs a live hold), and the sweep returns it to a closed row.
--        trg_hidden_listing_not_live  BEFORE UPDATE ON listings, when a visibility row exists:
--          (a) a new or changed Buy Now hold (NEW.status 'reserved' and OLD not reserved, or reserved_by /
--              reserved_until changed) -> 'Hidden listing cannot be reserved.';
--          (b) ends_at changed to a time >= now() -> 'Hidden listing cannot be made live.' (no extension,
--              whatever the auction status: the seller's own PATCH, admin_relist_listing, a trusted write);
--          (c) NEW is OPEN -> 'Hidden listing cannot be made live.' (no reactivation, no cancelled ->
--              ended flip that would re-open Buy Now).
--      Consequences: a hidden row is never OPEN and never newly held, so reserve_buy_now (its own sold /
--      cancelled / expired checks), a bid (validate_and_apply_bid needs auction 'active' and an unexpired
--      clock) and create-payment-intent (buy_now needs a live hold by the caller; auction needs the
--      caller to be the recorded winner) are all refused for anyone who is not already the winner.
--      The reservation sweep cannot be wedged: a hidden held row has a lapsed hold on a closed auction
--      (hide time) and its ends_at can never move forward (b), so the sweep's NEW row is never OPEN.
--      reserve_buy_now, validate_and_apply_bid, finalize, the sweep and checkout are NOT edited.
--      Not refused (reported): the recorded winner of an ended, unpaid hidden auction can still complete
--      that payment (a pre-existing obligation of a private party; production preimage: 0 such rows).
--   5. get_profile_trust_stats(uuid): same signature, return type, attributes and grants; every
--      transfers-based count and active_listings now require listing_is_public(listing), and
--      active_listings also requires ends_at > now() (an expired auction the finalizer has not closed yet
--      is not "active"; closes RC8's accepted trust-row lag server-side), so a public profile shows
--      nothing derived from a hidden listing. The production body before this file is 031's verbatim
--      (prosrc md5 b048a327d1fa23fdf409d86f2b56e427, functiondef md5 23719c73db47a2815d5102b11f4771f3).
--   6. public.is_public(public.listings): the PostgREST computed field (LANGUAGE sql, STABLE, search_path
--      '', SECURITY INVOKER; body listing_is_public($1.id)). anon-execute by explicit grant, boolean only.
--      Lets a build filter `.eq('is_public', true)`, so a private party's own hidden rows stay out of
--      Home/Explore/profile feeds while their order history still embeds them. Without it, that filter
--      is a 400 (42703) from PostgREST on every such read.
--   7. Recursion (42P17) safety: listing_is_public, listing_private_party and is_public are owned by the
--      owner of listings/bids/payments/transfers/listing_visibility (postgres: BYPASSRLS in production,
--      superuser locally), and none of those tables has FORCE ROW LEVEL SECURITY, so the definer bodies
--      read them without re-entering the policies. pgTAP 221 A12/A13 and state.sql own_* pin this.
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
-- GATE-2 census (public): tables 34 -> 35 (+listing_visibility); functions 116 -> 120 (+listing_is_public,
--   listing_private_party, guard_hidden_listing_not_live, is_public); policies 37 -> 37 (two 1-for-1
--   replacements); triggers 43 -> 45 (+trg_hidden_listing_not_live, trg_listing_visibility_not_live).
-- ROLLBACK: supabase/rollbacks/20261015000000_listing_public_visibility_rollback.sql — restores both
--   USING (true) policies and 031's get_profile_trust_stats body, drops the new policies, triggers and
--   functions (is_public included), and KEEPS listing_visibility and its rows (archival; inert). It
--   RE-EXPOSES every hidden listing publicly.
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
-- rollback must reuse them. The DO block refuses that re-apply if a kept row now names an OPEN listing or
-- one under a LIVE_HOLD (header §4; it could have been relisted or reserved while the table was inert):
-- hiding it again would break the invariant. Same predicate as the BEFORE INSERT branch below.
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
   WHERE (l.status IN ('active', 'reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now())
      OR (l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false));
  IF n > 0 THEN
    RAISE EXCEPTION '154: % kept listing_visibility row(s) name a live or held listing; end those listings (or delete their rows) before re-applying.', n
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

-- The PostgREST computed field: GET /listings?is_public=eq.true (supabase-js .eq('is_public', true)).
-- SECURITY INVOKER: it reads nothing itself; listing_is_public is the definer that reads the side table.
CREATE FUNCTION public.is_public(public.listings)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT public.listing_is_public($1.id)
$$;
REVOKE ALL ON FUNCTION public.is_public(public.listings) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_public(public.listings) TO anon, authenticated;
COMMENT ON FUNCTION public.is_public(public.listings) IS
  '154: PostgREST computed field listings.is_public = listing_is_public(id). Lets a build filter .eq(''is_public'', true) '
  'so a private party''s own hidden listings stay out of public feeds. anon-execute by explicit grant; boolean only.';

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

-- ── 4. invariant: a hidden listing is never live, held or extended ──────────
-- OPEN and LIVE_HOLD are defined in the header (§4); the same text appears in the re-apply DO block above.
CREATE FUNCTION public.guard_hidden_listing_not_live()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_open boolean;
  v_hold boolean;
BEGIN
  IF TG_TABLE_NAME = 'listings' THEN
    -- BEFORE UPDATE ON public.listings, every caller (service_role and postgres included). The row checks
    -- come first, so an update that could not re-open anything costs no visibility lookup.
    IF NEW.status = 'reserved'
       AND (OLD.status IS DISTINCT FROM 'reserved'
            OR NEW.reserved_by    IS DISTINCT FROM OLD.reserved_by
            OR NEW.reserved_until IS DISTINCT FROM OLD.reserved_until)
       AND EXISTS (SELECT 1 FROM public.listing_visibility v WHERE v.listing_id = NEW.id) THEN
      -- (a) a new or changed Buy Now hold
      RAISE EXCEPTION 'Hidden listing cannot be reserved.'
        USING ERRCODE = 'P0001', HINT = 'LISTING_HIDDEN';
    END IF;
    IF ((NEW.ends_at IS DISTINCT FROM OLD.ends_at AND NEW.ends_at >= now())
        OR (NEW.status IN ('active', 'reserved') AND NEW.auction_status <> 'cancelled' AND NEW.ends_at >= now()))
       AND EXISTS (SELECT 1 FROM public.listing_visibility v WHERE v.listing_id = NEW.id) THEN
      -- (b) the end time moved to now or later; (c) the row would be OPEN
      RAISE EXCEPTION 'Hidden listing cannot be made live.'
        USING ERRCODE = 'P0001', HINT = 'LISTING_HIDDEN';
    END IF;
    RETURN NEW;
  END IF;

  -- BEFORE INSERT ON public.listing_visibility (hide time). FOR SHARE serialises against a concurrent
  -- relist, extension or reserve of the same row.
  SELECT (l.status IN ('active', 'reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now()),
         (l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false))
    INTO v_open, v_hold
    FROM public.listings l
   WHERE l.id = NEW.listing_id
     FOR SHARE;
  IF coalesce(v_open, false) THEN
    RAISE EXCEPTION 'Cannot hide a live listing; end or cancel it first.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_LIVE';
  END IF;
  IF coalesce(v_hold, false) THEN
    RAISE EXCEPTION 'Cannot hide a listing under a live Buy Now hold; let the hold lapse or complete first.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_HELD';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_hidden_listing_not_live() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_hidden_listing_not_live() IS
  '154: invariant "a hidden listing is never live, held or extended". On listings (BEFORE UPDATE, every caller) refuses '
  'a new Buy Now hold, an end time moved to now or later, and any row reserve_buy_now would accept (status active/reserved, '
  'auction not cancelled, ends_at >= now()); on listing_visibility (BEFORE INSERT) refuses hiding such a row or one under a '
  'live Buy Now hold.';

CREATE TRIGGER trg_hidden_listing_not_live
  BEFORE UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_hidden_listing_not_live();
CREATE TRIGGER trg_listing_visibility_not_live
  BEFORE INSERT ON public.listing_visibility
  FOR EACH ROW EXECUTE FUNCTION public.guard_hidden_listing_not_live();

-- ── 5. public trust stats: nothing derived from a hidden listing ────────────
-- 031's body with listing_is_public() added to every transfers-based count and to active_listings, and
-- ends_at > now() added to active_listings (ADDENDUM 2: an expired auction the finalizer has not closed
-- yet is not active). Signature, return type, LANGUAGE, STABLE, SECURITY DEFINER and search_path unchanged.
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

    -- 3) Active Listings — currently live + accepting bids (154: and the
    --    clock has not run out, even if the finalizer has not closed it yet)
    (SELECT COUNT(*)::int
       FROM public.listings
      WHERE seller_id      = p_user_id
        AND status         = 'active'
        AND auction_status = 'active'
        AND ends_at        > now()
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
  'listings (listing_is_public), so a public profile shows nothing derived from a hidden listing; active_listings '
  'also requires ends_at > now().';

COMMIT;
;
INSERT INTO supabase_migrations.schema_migrations (version, name, statements, created_by)
VALUES ('20261015000000', 'listing_public_visibility', ARRAY[$pkg154$-- ============================================================================
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
--   4. Invariant "a hidden listing is never live, held or extended": guard_hidden_listing_not_live()
--      (SECURITY DEFINER, search_path ''), two triggers, for EVERY caller (service_role and postgres too).
--      "Open" means what reserve_buy_now accepts, not only what the Home feed calls live. reserve_buy_now
--      refuses only a sold row, a cancelled auction, a succeeded payment, an expired clock (now() > ends_at)
--      and another buyer's live hold. It never requires auction_status = 'active'. So:
--        OPEN(l)      = l.status IN ('active','reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now()
--        LIVE_HOLD(l) = l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false)
--                       (a hold that is not provably lapsed; create-payment-intent mints for a live one)
--        trg_listing_visibility_not_live  BEFORE INSERT ON listing_visibility (hide time):
--          OPEN -> 'Cannot hide a live listing; end or cancel it first.'
--          LIVE_HOLD -> 'Cannot hide a listing under a live Buy Now hold; let the hold lapse or complete first.'
--          The row is FOR SHARE-locked, so a concurrent relist, extension or reserve serialises against it.
--          A LAPSED hold on a closed auction may be hidden: nobody can pay for it (create-payment-intent
--          needs a live hold), and the sweep returns it to a closed row.
--        trg_hidden_listing_not_live  BEFORE UPDATE ON listings, when a visibility row exists:
--          (a) a new or changed Buy Now hold (NEW.status 'reserved' and OLD not reserved, or reserved_by /
--              reserved_until changed) -> 'Hidden listing cannot be reserved.';
--          (b) ends_at changed to a time >= now() -> 'Hidden listing cannot be made live.' (no extension,
--              whatever the auction status: the seller's own PATCH, admin_relist_listing, a trusted write);
--          (c) NEW is OPEN -> 'Hidden listing cannot be made live.' (no reactivation, no cancelled ->
--              ended flip that would re-open Buy Now).
--      Consequences: a hidden row is never OPEN and never newly held, so reserve_buy_now (its own sold /
--      cancelled / expired checks), a bid (validate_and_apply_bid needs auction 'active' and an unexpired
--      clock) and create-payment-intent (buy_now needs a live hold by the caller; auction needs the
--      caller to be the recorded winner) are all refused for anyone who is not already the winner.
--      The reservation sweep cannot be wedged: a hidden held row has a lapsed hold on a closed auction
--      (hide time) and its ends_at can never move forward (b), so the sweep's NEW row is never OPEN.
--      reserve_buy_now, validate_and_apply_bid, finalize, the sweep and checkout are NOT edited.
--      Not refused (reported): the recorded winner of an ended, unpaid hidden auction can still complete
--      that payment (a pre-existing obligation of a private party; production preimage: 0 such rows).
--   5. get_profile_trust_stats(uuid): same signature, return type, attributes and grants; every
--      transfers-based count and active_listings now require listing_is_public(listing), and
--      active_listings also requires ends_at > now() (an expired auction the finalizer has not closed yet
--      is not "active"; closes RC8's accepted trust-row lag server-side), so a public profile shows
--      nothing derived from a hidden listing. The production body before this file is 031's verbatim
--      (prosrc md5 b048a327d1fa23fdf409d86f2b56e427, functiondef md5 23719c73db47a2815d5102b11f4771f3).
--   6. public.is_public(public.listings): the PostgREST computed field (LANGUAGE sql, STABLE, search_path
--      '', SECURITY INVOKER; body listing_is_public($1.id)). anon-execute by explicit grant, boolean only.
--      Lets a build filter `.eq('is_public', true)`, so a private party's own hidden rows stay out of
--      Home/Explore/profile feeds while their order history still embeds them. Without it, that filter
--      is a 400 (42703) from PostgREST on every such read.
--   7. Recursion (42P17) safety: listing_is_public, listing_private_party and is_public are owned by the
--      owner of listings/bids/payments/transfers/listing_visibility (postgres: BYPASSRLS in production,
--      superuser locally), and none of those tables has FORCE ROW LEVEL SECURITY, so the definer bodies
--      read them without re-entering the policies. pgTAP 221 A12/A13 and state.sql own_* pin this.
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
-- GATE-2 census (public): tables 34 -> 35 (+listing_visibility); functions 116 -> 120 (+listing_is_public,
--   listing_private_party, guard_hidden_listing_not_live, is_public); policies 37 -> 37 (two 1-for-1
--   replacements); triggers 43 -> 45 (+trg_hidden_listing_not_live, trg_listing_visibility_not_live).
-- ROLLBACK: supabase/rollbacks/20261015000000_listing_public_visibility_rollback.sql — restores both
--   USING (true) policies and 031's get_profile_trust_stats body, drops the new policies, triggers and
--   functions (is_public included), and KEEPS listing_visibility and its rows (archival; inert). It
--   RE-EXPOSES every hidden listing publicly.
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
-- rollback must reuse them. The DO block refuses that re-apply if a kept row now names an OPEN listing or
-- one under a LIVE_HOLD (header §4; it could have been relisted or reserved while the table was inert):
-- hiding it again would break the invariant. Same predicate as the BEFORE INSERT branch below.
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
   WHERE (l.status IN ('active', 'reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now())
      OR (l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false));
  IF n > 0 THEN
    RAISE EXCEPTION '154: % kept listing_visibility row(s) name a live or held listing; end those listings (or delete their rows) before re-applying.', n
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

-- The PostgREST computed field: GET /listings?is_public=eq.true (supabase-js .eq('is_public', true)).
-- SECURITY INVOKER: it reads nothing itself; listing_is_public is the definer that reads the side table.
CREATE FUNCTION public.is_public(public.listings)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT public.listing_is_public($1.id)
$$;
REVOKE ALL ON FUNCTION public.is_public(public.listings) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_public(public.listings) TO anon, authenticated;
COMMENT ON FUNCTION public.is_public(public.listings) IS
  '154: PostgREST computed field listings.is_public = listing_is_public(id). Lets a build filter .eq(''is_public'', true) '
  'so a private party''s own hidden listings stay out of public feeds. anon-execute by explicit grant; boolean only.';

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

-- ── 4. invariant: a hidden listing is never live, held or extended ──────────
-- OPEN and LIVE_HOLD are defined in the header (§4); the same text appears in the re-apply DO block above.
CREATE FUNCTION public.guard_hidden_listing_not_live()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_open boolean;
  v_hold boolean;
BEGIN
  IF TG_TABLE_NAME = 'listings' THEN
    -- BEFORE UPDATE ON public.listings, every caller (service_role and postgres included). The row checks
    -- come first, so an update that could not re-open anything costs no visibility lookup.
    IF NEW.status = 'reserved'
       AND (OLD.status IS DISTINCT FROM 'reserved'
            OR NEW.reserved_by    IS DISTINCT FROM OLD.reserved_by
            OR NEW.reserved_until IS DISTINCT FROM OLD.reserved_until)
       AND EXISTS (SELECT 1 FROM public.listing_visibility v WHERE v.listing_id = NEW.id) THEN
      -- (a) a new or changed Buy Now hold
      RAISE EXCEPTION 'Hidden listing cannot be reserved.'
        USING ERRCODE = 'P0001', HINT = 'LISTING_HIDDEN';
    END IF;
    IF ((NEW.ends_at IS DISTINCT FROM OLD.ends_at AND NEW.ends_at >= now())
        OR (NEW.status IN ('active', 'reserved') AND NEW.auction_status <> 'cancelled' AND NEW.ends_at >= now()))
       AND EXISTS (SELECT 1 FROM public.listing_visibility v WHERE v.listing_id = NEW.id) THEN
      -- (b) the end time moved to now or later; (c) the row would be OPEN
      RAISE EXCEPTION 'Hidden listing cannot be made live.'
        USING ERRCODE = 'P0001', HINT = 'LISTING_HIDDEN';
    END IF;
    RETURN NEW;
  END IF;

  -- BEFORE INSERT ON public.listing_visibility (hide time). FOR SHARE serialises against a concurrent
  -- relist, extension or reserve of the same row.
  SELECT (l.status IN ('active', 'reserved') AND l.auction_status <> 'cancelled' AND l.ends_at >= now()),
         (l.status = 'reserved' AND NOT coalesce(l.reserved_until <= now(), false))
    INTO v_open, v_hold
    FROM public.listings l
   WHERE l.id = NEW.listing_id
     FOR SHARE;
  IF coalesce(v_open, false) THEN
    RAISE EXCEPTION 'Cannot hide a live listing; end or cancel it first.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_LIVE';
  END IF;
  IF coalesce(v_hold, false) THEN
    RAISE EXCEPTION 'Cannot hide a listing under a live Buy Now hold; let the hold lapse or complete first.'
      USING ERRCODE = 'P0001', HINT = 'LISTING_HELD';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.guard_hidden_listing_not_live() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_hidden_listing_not_live() IS
  '154: invariant "a hidden listing is never live, held or extended". On listings (BEFORE UPDATE, every caller) refuses '
  'a new Buy Now hold, an end time moved to now or later, and any row reserve_buy_now would accept (status active/reserved, '
  'auction not cancelled, ends_at >= now()); on listing_visibility (BEFORE INSERT) refuses hiding such a row or one under a '
  'live Buy Now hold.';

CREATE TRIGGER trg_hidden_listing_not_live
  BEFORE UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_hidden_listing_not_live();
CREATE TRIGGER trg_listing_visibility_not_live
  BEFORE INSERT ON public.listing_visibility
  FOR EACH ROW EXECUTE FUNCTION public.guard_hidden_listing_not_live();

-- ── 5. public trust stats: nothing derived from a hidden listing ────────────
-- 031's body with listing_is_public() added to every transfers-based count and to active_listings, and
-- ends_at > now() added to active_listings (ADDENDUM 2: an expired auction the finalizer has not closed
-- yet is not active). Signature, return type, LANGUAGE, STABLE, SECURITY DEFINER and search_path unchanged.
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

    -- 3) Active Listings — currently live + accepting bids (154: and the
    --    clock has not run out, even if the finalizer has not closed it yet)
    (SELECT COUNT(*)::int
       FROM public.listings
      WHERE seller_id      = p_user_id
        AND status         = 'active'
        AND auction_status = 'active'
        AND ends_at        > now()
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
  'listings (listing_is_public), so a public profile shows nothing derived from a hidden listing; active_listings '
  'also requires ends_at > now().';

COMMIT;
$pkg154$], 'claude-a/owner-authorised-154');
