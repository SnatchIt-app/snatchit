-- ============================================================================
-- ROLLBACK for 20261015000100_listing_duration_72h.sql (registry 155).
-- Restores the APPLIED pre-155 check exactly: CHECK ((duration_hours = ANY (ARRAY[1, 3, 6, 12, 24, 48])))
-- (production pg_get_constraintdef, 2026-10-15), and drops 155's server-side end time
-- (trg_listing_ends_at_from_duration + set_listing_ends_at_from_duration()): ends_at is client-set again.
-- REFUSES while any listing has duration_hours = 72: narrowing would fail on those rows, and they are
-- real listings (never rewritten or deleted by a rollback). End or migrate them first, or keep 155.
-- CONSEQUENCE: clients that offer 72 h get a check violation on create until they drop the option; a
-- seller can again PATCH ends_at on their own listing (the pre-155 surface). 154's hidden-row guard still
-- refuses any end-time move on a hidden listing.
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
