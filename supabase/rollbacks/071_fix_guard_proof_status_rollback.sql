-- Rollback for 071.
--
-- WARNING: THIS RESTORES A KNOWN HIGH-SEVERITY VULNERABILITY (DB-1).
-- The definition below is the migration-033 version, transcribed verbatim from
-- production pg_get_functiondef before the fix. It keys on the LEGACY SINGULAR
-- GUC request.jwt.claim.role, which modern PostgREST never sets, so the guard
-- evaluates NULL and falls through: any authenticated seller can set
-- listings.proof_status on their own listing — self-approving their ownership
-- proof and clearing the PROOF_REJECTED payout hold — AND, because the trigger
-- is narrowed back to BEFORE UPDATE, can again CREATE a listing pre-stamped
-- 'approved' with no review at all.
--
-- Only run this if 071 itself is causing a production regression, and treat it
-- as an incident: the window it opens is the original vulnerability.
--
-- Preferred alternative to a full rollback: 071 is a single CREATE OR REPLACE
-- with no schema change, so a corrected forward migration is almost always the
-- better move.

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_proof_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.proof_status IS DISTINCT FROM OLD.proof_status THEN
    IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role')
       AND session_user NOT IN ('postgres') THEN
      RAISE EXCEPTION 'proof_status can only be changed by Snatch It review';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.guard_proof_status() IS NULL;

-- 071 also widened the trigger from BEFORE UPDATE to BEFORE INSERT OR UPDATE,
-- so the rollback must narrow it back. Restoring the 033 definition without this
-- would leave an INSERT-firing trigger calling the old UPDATE-only body, where
-- OLD is NULL on INSERT — a state that never existed and was never tested.
DROP TRIGGER IF EXISTS trg_guard_proof_status ON public.listings;
CREATE TRIGGER trg_guard_proof_status
  BEFORE UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_proof_status();

-- Owner and ACL are preserved by CREATE OR REPLACE and need no restatement.

COMMIT;
