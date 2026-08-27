-- 071_fix_guard_proof_status.sql
-- =============================================================================
-- SECURITY HOTFIX (DB-1, HIGH). Pre-Phase-2.
--
-- THE DEFECT
-- public.guard_proof_status() (migration 033, never redefined) guarded
-- listings.proof_status with:
--
--     IF current_setting('request.jwt.claim.role', true) NOT IN ('service_role')
--        AND session_user NOT IN ('postgres') THEN RAISE EXCEPTION ...
--
-- `request.jwt.claim.role` is the LEGACY SINGULAR PostgREST GUC. PostgREST sets
-- `request.jwt.claims` (plural JSON) — confirmed from production
-- pg_stat_statements, where the PostgREST per-request setter (~296k calls) writes
-- only the plural form. (Precisely: the singular GUC IS still written in this
-- database, ~6k calls, by the Storage API and realtime.apply_rls(). Neither can
-- write public.listings, so the conclusion holds — but "PostgREST never sets it"
-- is the accurate claim, not "nothing sets it".)
-- The singular GUC therefore reads NULL on every REST request,
-- so:
--     NULL NOT IN ('service_role')  ->  NULL
--     NULL AND TRUE                 ->  NULL
--     IF NULL THEN                  ->  not taken
-- and the UPDATE proceeds. The guard was a no-op for every authenticated client.
--
-- IMPACT (confirmed, no evidence of exploitation)
--   * A seller could self-approve their own ownership proof — the buyer-facing
--     trust badge (ListingDetailScreen) became self-certifiable by the party the
--     review exists to check.
--   * proof_status also feeds the payout risk engine
--     (_shared/payout-policy.ts: 'rejected' -> PROOF_REJECTED -> HIGH ->
--     manual_review). A seller rejected for bad ownership proof could set their
--     own row back to 'approved' and clear that payout hold.
--   * A SECOND path, found by independent review after the first version of this
--     migration: the trigger was BEFORE UPDATE ONLY, so a seller could simply
--     CREATE a listing already stamped 'approved'. Closing UPDATE alone would
--     have left the headline claim false. This migration guards INSERT too.
--   * Reproduced on a fresh CI database before this fix: 5 UPDATE-path assertions
--     failed, then 2 more on the INSERT path once they were written. All pass
--     after it. supabase/tests/040_authenticated_boundaries.sql.
--
-- WHY THIS SHAPE
-- 1. FAIL-CLOSED. The old guard computed a DENY condition and fell through when
--    three-valued logic produced NULL. This computes an ALLOW condition into a
--    boolean initialised false; anything unmatched, NULL, or unparseable raises.
--
-- 2. SECURITY INVOKER, not DEFINER. The body touches no table, so it needs no
--    privileges and DEFINER was gratuitous. Under DEFINER, current_user is the
--    function OWNER (postgres) and cannot identify the caller at all. Under
--    INVOKER it is the caller's real SQL role, which PostgreSQL enforces through
--    role membership — `authenticator` may SET ROLE only to anon/authenticated/
--    service_role, never postgres, so it cannot be forged from a client.
--    Verified that EXECUTE is NOT consulted when a trigger fires (migration 067
--    revoked EXECUTE from anon/authenticated/public): the two sibling guards on
--    this same table, guard_listing_state_columns() and
--    guard_listing_identity_columns(), are already prosecdef=false with EXECUTE
--    revoked, and assertions exercising them as `authenticated` pass on the
--    fresh CI database. So this does not break listing edits.
--
-- 3. The SQL ROLE decides; a CLAIM may only contradict, never grant. A forged
--    `{"role":"service_role"}` claim under the authenticated SQL role is denied.
--
-- 4. request_is_service_role() (migration 0550) is deliberately NOT reused. It
--    reads the legacy singular GUC first, grants on the claim alone without
--    checking the SQL role, and treats a NULL claims GUC as trusted — three
--    behaviours that would each reopen this hole.
--
-- 5. nullif(..., '') normalises the empty string. set_config(name,'',true)
--    CREATES the GUC, so `current_setting(name,true)` returns '' rather than
--    NULL; an IS NULL test on the raw GUC is wrong.
--
-- 6. search_path = public, pg_temp matches the 0660 hardening pattern used by
--    the sibling guards on this table.
--
-- SCOPE: this function only. No table, RLS, money, transfer, or payout change.
-- No legitimate writer exists in code: exactly two functions in this database
-- mention proof_status — this guard, and get_auto_release_candidates(), which
-- only SELECTs it. No Edge Function, RPC or pg_cron job writes it. Review is
-- performed manually as `postgres` via the SQL editor, which lands on ALLOW
-- path 2 (verified live: current_user=postgres, request.jwt.claims IS NULL).
--
-- KNOWN FORWARD-COMPAT GAP, recorded deliberately: a future admin-review RPC
-- written as SECURITY DEFINER owned by postgres and called through PostgREST
-- would be DENIED — inside it current_user='postgres' (so ALLOW 1 fails) while
-- the caller's claims are still set (so ALLOW 2 fails). Write that RPC as
-- SECURITY INVOKER owned by a service role, or use the codebase's existing
-- transaction-local app.bypass_* idiom (0550/0563). Do not relax ALLOW 2.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_proof_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $function$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
  v_allow      boolean := false;
BEGIN
  -- UPDATE that leaves proof_status alone: nothing to guard. NULL-safe both
  -- ways, and keeps every ordinary listing edit and every definer RPC that
  -- UPDATEs listings unaffected.
  IF TG_OP = 'UPDATE' AND NEW.proof_status IS NOT DISTINCT FROM OLD.proof_status THEN
    RETURN NEW;
  END IF;

  -- INSERT that does not assert a review state. The column DEFAULT is applied
  -- BEFORE a BEFORE-INSERT trigger fires, so an ordinary client INSERT arrives
  -- here already carrying 'pending_review' and is allowed. Anything else on
  -- INSERT is a client claiming a review outcome and must pass an ALLOW path.
  IF TG_OP = 'INSERT' AND NEW.proof_status IS NOT DISTINCT FROM 'pending_review' THEN
    RETURN NEW;
  END IF;

  v_role   := current_user::text;
  v_claims := nullif(current_setting('request.jwt.claims', true), '');

  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      -- Unparseable claims assert nothing; both ALLOW paths below then fail.
      v_claim_role := NULL;
    END;
  END IF;

  -- ALLOW 1 — trusted server role. The SQL role must actually BE service_role;
  -- a claim can only contradict it.
  IF v_role = 'service_role'
     AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    v_allow := true;

  -- ALLOW 2 — direct admin connection with no request context: migrations,
  -- pg_cron, the Supabase SQL editor. A PostgREST request always carries claims,
  -- so this cannot be reached from a client.
  ELSIF v_role = 'postgres' AND v_claims IS NULL THEN
    v_allow := true;
  END IF;

  IF NOT v_allow THEN
    RAISE EXCEPTION 'proof_status can only be changed by Snatch It review';
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.guard_proof_status() IS
  'Fail-closed guard for listings.proof_status. Allows only the service_role SQL '
  'role (claims may contradict, never grant) or a claims-less postgres session '
  '(migration/cron/SQL editor). Replaces the migration-033 version, which keyed '
  'on the legacy singular request.jwt.claim.role GUC that modern PostgREST never '
  'sets, making it a no-op for every authenticated client (DB-1).';

-- The trigger was BEFORE UPDATE ONLY, which left the whole INSERT path open: a
-- seller could simply CREATE a listing already stamped 'approved' and never be
-- reviewed. authenticated holds table-wide INSERT, pg_attribute.attacl is NULL
-- for every column, the INSERT policy's WITH CHECK constrains only seller_id /
-- stripe_onboarding_complete / phone_verified(), and listings_proof_status_check
-- permits 'approved' — so nothing else stopped it. Found by independent review;
-- the original UPDATE-only assertions passed while the hole stood open.
DROP TRIGGER IF EXISTS trg_guard_proof_status ON public.listings;
CREATE TRIGGER trg_guard_proof_status
  BEFORE INSERT OR UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_proof_status();

-- Idempotent restatement of the 067 posture. EXECUTE is irrelevant when a
-- trigger fires; this only keeps the function self-contained if it is ever
-- replayed onto a database that predates 067. CREATE OR REPLACE preserves owner
-- and ACL, so this is a no-op on production.
REVOKE EXECUTE ON FUNCTION public.guard_proof_status() FROM anon, authenticated, PUBLIC;

COMMIT;
