-- ============================================================================
-- ROLLBACK for 20261015000200_listing_proof_owner_waiver.sql (registry 156).
-- Pre-156 state (production 2026-10-15): no proof_waived_* columns, no waiver checks, no
-- guard_listing_proof_waiver(), current_user_is_admin(), client_shows_proof_disclosure(),
-- guard_bid_requires_disclosure() or guard_reservation_requires_disclosure(), and none of their three
-- triggers. Nothing that existed before 156 is redefined, so nothing is restored: dropping is the rollback.
-- REFUSES while any listing carries a waiver value: those rows are the archival record of an owner decision,
-- and dropping only the guard would leave the columns client-writable (anon/authenticated hold table-level
-- UPDATE/INSERT on listings), so any seller could then forge a waiver. Clear recorded waivers through the
-- trusted path first (an owner decision), or keep 156.
-- With no waiver recorded: drops the three triggers (listings: trg_guard_listing_proof_waiver,
-- trg_reservation_requires_disclosure; bids: trg_bid_requires_disclosure), the five functions, the three
-- checks and the three columns.
-- CLIENT ORDER (required once web #108 is deployed; each step is an owner decision):
--   1. Clear every recorded waiver through the trusted path (cancel or end the waived listings first). This
--      rollback refuses while any waiver is recorded. Rule (F): never roll web back past #108 while a waived
--      listing is live.
--   2. Deploy web WITHOUT #108's proof_waived_at selects. Web #108 (068f054e) adds proof_waived_at to
--      LISTING_COLUMNS (web/src/lib/listings.ts:54-55). Once the column is dropped, every read of that list is a
--      PostgREST 400 (42703). getActiveListings and getListing throw on it, so /, /browse, /listing/[id] and
--      /checkout/[id] render the error page; saved listings (the favorites embed, favorites.ts:44) shows its
--      error state; /api/public/events answers 500; the sitemap catches the error and drops its listing
--      entries. SELLER_LISTING_COLUMNS does not select the column, and the non-waived create path never sends
--      a waiver key, so seller listings and normal creates are unaffected.
--   3. Only then run this rollback. A waiver recorded between steps 1 and 3 makes it refuse again (nothing
--      changed); repeat step 1.
-- NATIVE: RC9 (4f7ad2b4; also the N1 build 7fc72a08) selects proof_waived_at for checkout's pay face
--   (src/lib/checkout/listingSummary.ts:37) and on PlaceBidScreen (src/screens/PlaceBidScreen.tsx:165). After
--   this rollback both reads fail on EVERY listing, so an RC9 install cannot bid or pay. A web deploy cannot
--   undo an installed build. Once RC9 is in users' hands, step 2 also needs a successor native build without
--   those selects, adopted by users, or the owner's written acceptance of that outage.
-- OTHER CONSEQUENCES: web /sell's admin waiver box disappears (#108's admin check fails closed when
--   current_user_is_admin() is missing: create-listing.ts:58); an untrusted create without a proof path is
--   accepted again (pre-156 behaviour); the x-snatchit-caps header is ignored again.
-- Order: run before 155's and 154's rollbacks.
-- Run only under owner approval, with D's read-back.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $rb$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.listings
   WHERE proof_waived_at IS NOT NULL OR proof_waived_by IS NOT NULL OR proof_waiver_reason IS NOT NULL;
  IF n > 0 THEN
    RAISE EXCEPTION '156 rollback refused: % listing(s) carry a recorded owner proof waiver (archival record). Nothing changed.', n
      USING ERRCODE = 'P0001';
  END IF;
END
$rb$;

DROP TRIGGER IF EXISTS trg_bid_requires_disclosure ON public.bids;
DROP TRIGGER IF EXISTS trg_reservation_requires_disclosure ON public.listings;
DROP TRIGGER IF EXISTS trg_guard_listing_proof_waiver ON public.listings;
DROP FUNCTION IF EXISTS public.guard_bid_requires_disclosure();
DROP FUNCTION IF EXISTS public.guard_reservation_requires_disclosure();
DROP FUNCTION IF EXISTS public.client_shows_proof_disclosure();
DROP FUNCTION IF EXISTS public.guard_listing_proof_waiver();
DROP FUNCTION IF EXISTS public.current_user_is_admin();
ALTER TABLE public.listings
  DROP CONSTRAINT IF EXISTS listings_proof_waiver_never_approved,
  DROP CONSTRAINT IF EXISTS listings_proof_waiver_all_or_none,
  DROP COLUMN IF EXISTS proof_waiver_reason,
  DROP COLUMN IF EXISTS proof_waived_by,
  DROP COLUMN IF EXISTS proof_waived_at;

COMMIT;
