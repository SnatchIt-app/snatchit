-- ============================================================================
-- ROLLBACK for 20261015000100_listing_duration_72h.sql (registry 155).
-- Restores the APPLIED pre-155 check exactly: CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))
-- (production pg_get_constraintdef, 2026-10-15), and drops 155's server-side end time
-- (trg_listing_ends_at_from_duration + set_listing_ends_at_from_duration()): ends_at is client-set again.
-- REFUSES while any listing has duration_hours = 72: narrowing would fail on those rows, and they are
-- real listings (never rewritten or deleted by a rollback). End or migrate them first, or keep 155.
-- CLIENT ORDER (required once web #107 or #108 is deployed; each step is an owner decision):
--   1. Deploy web WITHOUT the 72 h option. Web #107 (a2540576, also carried in #108) adds 72 to
--      LISTING_DURATION_HOURS (web/src/lib/listing-durations.ts:6). /sell offers it and create-listing.ts accepts
--      it. After this rollback a 72 h create is refused by the restored check (23514).
--   2. End or migrate every 72 h listing (through the trusted path; this rollback refuses while any exists).
--   3. Only then run this rollback. A 72 h listing created between steps 1 and 3 (by a client still offering
--      it) makes it refuse again (nothing changed); repeat step 2.
-- NATIVE: RC9 (4f7ad2b4; also the N1 build 7fc72a08) offers 72 h (src/lib/sell/durations.ts:10 DURATION_OPTIONS,
--   the "3d" chip). An installed RC9 keeps offering it, and that create gets the check violation until a build
--   without 72 h is installed. Once RC9 is in users' hands, step 1 also needs a successor native build without
--   72 h, adopted by users, or the owner's written acceptance that RC9's "3d" create fails.
-- ENDS_AT: web #107/#108 (create-listing.ts:160,179) and RC9 (CreateListingScreen.tsx:628) still send ends_at
--   on insert, so with 155's server-side end time gone their other creates keep working. A seller can again
--   PATCH ends_at on their own listing (the pre-155 surface). 154's hidden-row guard still refuses any end-time
--   move on a hidden listing.
-- Order: run 156's rollback first if it is applied; 154's after this one.
-- Run only under owner approval, with D's read-back.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $rb$
DECLARE
  n int;
BEGIN
  SELECT count(*) INTO n FROM public.listings WHERE duration_hours = 72;
  IF n > 0 THEN
    RAISE EXCEPTION '155 rollback refused: % listing(s) have duration_hours = 72; narrowing the check would fail on them. Nothing changed.', n
      USING ERRCODE = 'P0001';
  END IF;
END
$rb$;

DROP TRIGGER IF EXISTS trg_listing_ends_at_from_duration ON public.listings;
DROP FUNCTION IF EXISTS public.set_listing_ends_at_from_duration();

ALTER TABLE public.listings DROP CONSTRAINT listings_duration_hours_check;
ALTER TABLE public.listings ADD CONSTRAINT listings_duration_hours_check
  CHECK (duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48]));

COMMIT;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000100' AND (SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid = 'public.listings'::regclass AND conname = 'listings_duration_hours_check') = 'CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))' AND to_regprocedure('public.set_listing_ends_at_from_duration()') IS NULL;
