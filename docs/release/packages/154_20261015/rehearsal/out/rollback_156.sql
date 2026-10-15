-- ============================================================================
-- ROLLBACK for 20261015000200_listing_proof_owner_waiver.sql (registry 156).
-- Pre-156 state (production 2026-10-15): no proof_waived_* columns, no waiver check, no
-- guard_listing_proof_waiver() or current_user_is_admin(). Nothing that existed before 156 is redefined.
-- REFUSES while any listing carries a waiver value: those rows are the archival record of an owner decision,
-- and dropping only the guard would leave the columns client-writable (anon/authenticated hold table-level
-- UPDATE/INSERT on listings), so any seller could then forge a waiver. Clear recorded waivers through the
-- trusted path first (an owner decision), or keep 156.
-- With no waiver recorded: drops the trigger, both functions, the two checks and the three columns.
-- CONSEQUENCE: web /sell's admin waiver box loses current_user_is_admin() (F must ship the matching revert).
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

DROP TRIGGER IF EXISTS trg_guard_listing_proof_waiver ON public.listings;
DROP FUNCTION IF EXISTS public.guard_listing_proof_waiver();
DROP FUNCTION IF EXISTS public.current_user_is_admin();
ALTER TABLE public.listings
  DROP CONSTRAINT IF EXISTS listings_proof_waiver_all_or_none,
  DROP COLUMN IF EXISTS proof_waiver_reason,
  DROP COLUMN IF EXISTS proof_waived_by,
  DROP COLUMN IF EXISTS proof_waived_at;

COMMIT;
DELETE FROM supabase_migrations.schema_migrations WHERE version = '20261015000200' AND to_regprocedure('public.guard_listing_proof_waiver()') IS NULL AND to_regprocedure('public.current_user_is_admin()') IS NULL AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'listings' AND column_name IN ('proof_waived_at','proof_waived_by','proof_waiver_reason'));
