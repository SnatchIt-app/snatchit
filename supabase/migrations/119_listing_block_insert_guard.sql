-- ============================================================================
-- 119_listing_block_insert_guard.sql — enforce the listing-creation block at
-- the database boundary (PR #55 review finding 3).
--
-- WHAT THIS MIGRATION IS. Before this file, `seller_risk_scores.is_listing_blocked`
-- was consulted only by public.can_create_listing(), which the mobile and web
-- clients call BEFORE inserting a listing. A seller holding a valid session
-- could insert directly through PostgREST and skip that advisory check, so the
-- console's "block listing creation" action was not an authoritative
-- restriction. This adds ONE BEFORE INSERT trigger on public.listings that
-- refuses a row whose seller is blocked.
--
-- Scope — deliberately narrow:
--   * INSERT only. Listing creation is the restricted act; the seller's
--     existing listings, account, sign-in and purchases are untouched (this is
--     a listing restriction, not an account suspension).
--   * Reactivation paths were traced: the only path that sets
--     auction_status back to 'active' is public.admin_relist_listing, which
--     refuses any listing whose seller is not in public.admin_users, so a
--     blocked seller cannot revive a cancelled listing. guard_listing_state_columns
--     (046/0590) already forbids clients from writing status/auction_status.
--   * Trusted server paths keep working exactly as in 072: a genuine
--     service_role SQL role, or a direct admin connection with no request
--     context (migrations, fixtures, cron), is never blocked.
--   * Concurrency: the seller's seller_risk_scores row is locked FOR SHARE for
--     the duration of the insert, so a block being committed concurrently
--     (ops.execute_action user_restrict takes the row lock) is observed: the
--     insert waits for the block transaction and then sees the flag. An insert
--     that committed before the block stands — the block applies to
--     subsequent creations, never retroactively.
--   * The existing 036/038 INSERT policies (payout onboarding, verified phone)
--     and the 072 column guard are untouched; this trigger runs beside them.
--
-- Gate-2 (public census): +1 function, +1 trigger. ci.yml EXPECT_FUNCS 70→71,
-- EXPECT_TRIGGERS 26→27; SEC-2 decision recorded in
-- supabase/ci/assert_public_table_grant_decisions.sql ('no-client-execute').
--
-- Rollback: supabase/rollbacks/119_listing_block_insert_guard_rollback.sql
-- Verification: select tgname from pg_trigger where tgrelid='public.listings'::regclass
--                 and tgname='trg_guard_listing_seller_not_blocked';   -- 1 row
-- Locks/runtime: CREATE TRIGGER takes a brief SHARE ROW EXCLUSIVE lock on
-- public.listings; no rewrite.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.guard_listing_seller_not_blocked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role       text;
  v_claims     text;
  v_claim_role text;
  v_blocked    boolean;
  v_reason     text;
BEGIN
  -- Same trust predicate as 072's guard_listing_insert_columns, adapted for a
  -- SECURITY DEFINER body (seller_risk_scores is deny-all under RLS, so the
  -- read needs definer rights): inside a definer function current_user is the
  -- owner, but the PostgREST SET ROLE is still visible as the `role` GUC
  -- ('none' on a direct admin connection). A trusted server path is never a
  -- blocked seller acting for themselves.
  v_role   := coalesce(nullif(current_setting('role', true), 'none'), current_user::text);
  v_claims := nullif(current_setting('request.jwt.claims', true), '');
  IF v_claims IS NOT NULL THEN
    BEGIN
      v_claim_role := v_claims::jsonb ->> 'role';
    EXCEPTION WHEN others THEN
      v_claim_role := NULL;
    END;
  END IF;
  IF v_role = 'service_role' AND coalesce(v_claim_role, 'service_role') = 'service_role' THEN
    RETURN NEW;
  END IF;
  IF v_claims IS NULL AND v_role NOT IN ('anon', 'authenticated') THEN
    RETURN NEW;   -- direct admin connection (role GUC 'none'): migrations, fixtures, cron
  END IF;

  -- FOR SHARE serialises against a concurrent block (user_restrict locks the
  -- same row); a seller with no risk row is not blocked.
  SELECT srs.is_listing_blocked, srs.listing_blocked_reason
    INTO v_blocked, v_reason
    FROM public.seller_risk_scores srs
   WHERE srs.seller_id = NEW.seller_id
   FOR SHARE;

  IF coalesce(v_blocked, false) THEN
    RAISE EXCEPTION 'listing_blocked: this account cannot create listings at the moment'
      USING ERRCODE = 'P0001',
            HINT = 'seller_risk_scores.is_listing_blocked is true for this seller; contact support',
            DETAIL = coalesce(v_reason, 'no reason recorded');
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_listing_seller_not_blocked() IS
  '119: BEFORE INSERT guard on public.listings — refuses a new listing when seller_risk_scores.is_listing_blocked is true for NEW.seller_id (FOR SHARE against a concurrent block). Trusted server paths (service_role, no request context) pass. INSERT only: a listing restriction, never an account suspension.';

DROP TRIGGER IF EXISTS trg_guard_listing_seller_not_blocked ON public.listings;
CREATE TRIGGER trg_guard_listing_seller_not_blocked
  BEFORE INSERT ON public.listings
  FOR EACH ROW EXECUTE FUNCTION public.guard_listing_seller_not_blocked();

-- SEC-2 / F2: a trigger function is never client-executable.
REVOKE EXECUTE ON FUNCTION public.guard_listing_seller_not_blocked() FROM anon, authenticated, PUBLIC;

COMMIT;
