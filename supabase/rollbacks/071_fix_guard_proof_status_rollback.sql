-- Rollback for 071.
--
-- WARNING: THIS RESTORES A KNOWN HIGH-SEVERITY VULNERABILITY (DB-1).
-- The definition below is the migration-033 version, transcribed verbatim from
-- production pg_get_functiondef before the fix. It keys on the LEGACY SINGULAR
-- GUC request.jwt.claim.role, which modern PostgREST never sets, so the guard
-- evaluates NULL and falls through: any authenticated seller can set
-- listings.proof_status on their own listing — self-approving their ownership
-- proof and clearing the PROOF_REJECTED payout hold.
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

-- No trigger statement is needed: 071 used CREATE OR REPLACE, so
-- trg_guard_proof_status on public.listings was never dropped and still points
-- at the same function OID. Owner and ACL are likewise preserved by REPLACE.

COMMIT;
