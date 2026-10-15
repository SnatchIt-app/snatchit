-- ============================================================================
-- 20261015000200_listing_proof_owner_waiver.sql — registry 156 (pgTAP 223).
-- An explicit, recorded owner proof waiver for an admin's own inventory, never marked verified.
-- Owner authorisation 2026-10-15 (A's chat). Addendum (F's request, A approved): current_user_is_admin().
--
-- WHAT.
--   1. public.listings gains three nullable columns: proof_waived_at timestamptz, proof_waived_by uuid,
--      proof_waiver_reason text (1..300 chars when set). listings_proof_waiver_all_or_none: all three are
--      NULL together or all three are set. ADD COLUMN without a default rewrites nothing.
--   2. guard_listing_proof_waiver() (SECURITY DEFINER: it reads public.admin_users, which is deny-all;
--      search_path ''), trigger trg_guard_listing_proof_waiver BEFORE INSERT OR UPDATE ON public.listings.
--        Trusted (allowed as-is): the service_role SQL role with claims absent or service_role, or a
--          claims-less postgres session — the trust tests of guard_listing_insert_columns (072), read the
--          119 way for a definer body (the PostgREST SET ROLE is the `role` GUC; 'none' on a direct
--          connection, where current_user is the owner).
--        INSERT, untrusted: three NULLs pass. Otherwise ALL of: proof_waived_by = auth.uid(); seller_id =
--          auth.uid(); the caller is in public.admin_users; proof_of_ownership_path IS NULL; a reason with
--          a non-blank character. Then proof_waived_at := now(), overriding whatever the client sent.
--          Anything else: 'Only an admin listing its own inventory can record an owner proof waiver.'
--        UPDATE, untrusted: the three fields must be NOT DISTINCT FROM OLD, else 'An owner proof waiver
--          is recorded only when the listing is created.' (No adding, rewriting or clearing later.)
--      proof_status is untouched: guard_proof_status (071) already keeps clients at 'pending_review', so a
--      waived listing is never 'approved'.
--   3. public.current_user_is_admin(): the caller's own boolean only (EXISTS admin_users for auth.uid()).
--      authenticated-execute; anon and PUBLIC revoked. The web /sell page uses it to show the waiver box.
-- DISPLAY CONTRACT (clients): "Ticket proof waived by Snatch It" when proof_waived_at IS NOT NULL; never
--   show proof_waived_by or the reason; a waived listing's seller badge reads "Verified seller", never a bare
--   "Verified". NOTE: anon/authenticated hold table-level SELECT on listings, so the reason and waived_by
--   (which always equals seller_id) are readable through PostgREST like every other listings column.
--
-- GATE-2 census (public): functions 119 -> 121 (+guard_listing_proof_waiver, current_user_is_admin);
--   triggers 45 -> 46 (+trg_guard_listing_proof_waiver). Tables and policies unchanged.
-- ROLLBACK: supabase/rollbacks/20261015000200_listing_proof_owner_waiver_rollback.sql — REFUSES while any
--   listing carries a waiver (archival record; and leaving the columns without the guard would let any
--   client write a waiver); otherwise drops the trigger, both functions, the check and the three columns.
-- VERIFY (read-only): select tgname from pg_trigger where tgname = 'trg_guard_listing_proof_waiver'; -- 1 row
-- FAILURE BEHAVIOUR: one transaction; ACCESS EXCLUSIVE on listings for the column adds and check validation
--   (113 rows, all NULL); lock_timeout 3s, so it fails cleanly rather than queue.
-- OWNER APPROVAL POINT: prepared and tested locally only; applying it is a separate owner approval.
-- ============================================================================
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ── 1. columns ──────────────────────────────────────────────────────────────
ALTER TABLE public.listings
  ADD COLUMN proof_waived_at     timestamptz NULL,
  ADD COLUMN proof_waived_by     uuid        NULL,
  ADD COLUMN proof_waiver_reason text        NULL
    CONSTRAINT listings_proof_waiver_reason_check
    CHECK (proof_waiver_reason IS NULL OR char_length(proof_waiver_reason) BETWEEN 1 AND 300);
ALTER TABLE public.listings ADD CONSTRAINT listings_proof_waiver_all_or_none CHECK (
     (proof_waived_at IS NULL     AND proof_waived_by IS NULL     AND proof_waiver_reason IS NULL)
  OR (proof_waived_at IS NOT NULL AND proof_waived_by IS NOT NULL AND proof_waiver_reason IS NOT NULL));
COMMENT ON COLUMN public.listings.proof_waived_at IS
  '156: when an admin recorded an owner proof waiver for their own listing (server time; set only at creation).';
COMMENT ON COLUMN public.listings.proof_waived_by IS
  '156: the admin who recorded the waiver; always the listing''s seller. Never displayed.';
COMMENT ON COLUMN public.listings.proof_waiver_reason IS
  '156: the admin''s recorded reason for the waiver (1..300 chars). Never displayed.';

-- ── 2. the guard ────────────────────────────────────────────────────────────
CREATE FUNCTION public.guard_listing_proof_waiver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
  v_uid        uuid;
BEGIN
  -- Trust test of 072 (guard_listing_insert_columns), read the 119 way inside a definer body.
  v_role   := coalesce(nullif(current_setting('role', true), 'none'), current_user::text);
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      v_claim_role := NULL;   -- unparseable claims assert nothing
    END;
  END IF;
  IF v_role = 'service_role' AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF v_role = 'postgres' AND v_claims IS NULL THEN
    RETURN NEW;               -- migrations, cron, the SQL editor: no request context
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.proof_waived_at     IS NOT DISTINCT FROM OLD.proof_waived_at
       AND NEW.proof_waived_by     IS NOT DISTINCT FROM OLD.proof_waived_by
       AND NEW.proof_waiver_reason IS NOT DISTINCT FROM OLD.proof_waiver_reason THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'An owner proof waiver is recorded only when the listing is created.'
      USING ERRCODE = 'P0001', HINT = 'PROOF_WAIVER_FROZEN';
  END IF;

  -- INSERT
  IF NEW.proof_waived_at IS NULL AND NEW.proof_waived_by IS NULL AND NEW.proof_waiver_reason IS NULL THEN
    RETURN NEW;
  END IF;
  v_uid := auth.uid();
  IF v_uid IS NOT NULL
     AND NEW.proof_waived_by IS NOT DISTINCT FROM v_uid
     AND NEW.seller_id       IS NOT DISTINCT FROM v_uid
     AND EXISTS (SELECT 1 FROM public.admin_users a WHERE a.user_id = v_uid)
     AND NEW.proof_of_ownership_path IS NULL
     AND coalesce(NEW.proof_waiver_reason ~ '\S', false) THEN
    NEW.proof_waived_at := now();   -- the server's time, never the client's
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Only an admin listing its own inventory can record an owner proof waiver.'
    USING ERRCODE = 'P0001', HINT = 'PROOF_WAIVER_NOT_ALLOWED';
END;
$$;
REVOKE ALL ON FUNCTION public.guard_listing_proof_waiver() FROM PUBLIC, anon, authenticated;
COMMENT ON FUNCTION public.guard_listing_proof_waiver() IS
  '156: BEFORE INSERT OR UPDATE on public.listings. Untrusted callers may record an owner proof waiver only at '
  'creation, only as an admin listing their own inventory with no proof path and a reason (waived_at stamped '
  'now()); the three waiver fields are frozen for clients afterwards. service_role / claims-less postgres pass.';

DROP TRIGGER IF EXISTS trg_guard_listing_proof_waiver ON public.listings;
CREATE TRIGGER trg_guard_listing_proof_waiver
  BEFORE INSERT OR UPDATE ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_listing_proof_waiver();

-- ── 3. the caller's own admin bit (web /sell) ───────────────────────────────
CREATE FUNCTION public.current_user_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.admin_users WHERE user_id = (SELECT auth.uid()))
$$;
REVOKE ALL ON FUNCTION public.current_user_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_is_admin() TO authenticated;
COMMENT ON FUNCTION public.current_user_is_admin() IS
  '156: true when the signed-in caller is in public.admin_users. The caller''s own boolean only; authenticated-execute.';

COMMIT;
