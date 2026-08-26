-- 056a_transfer_writer_rpcs.sql   APPLIED 2026-08-05, verified.
--
-- The three trusted RPCs that replace the four direct Edge Function writes to
-- public.transfers. ADDITIVE ONLY: the `current_user = 'service_role'`
-- exemption stays in guard_transfer_state_columns, so the old direct-UPDATE
-- path and the new RPC path both work. That is what makes the Edge Function
-- deploy safe to perform in either order.
--
--   record_transfer_payout(uuid, text)    <- enforce-transfer-expiry:670, confirm-and-release:541
--   freeze_transfer_for_dispute(uuid)     <- stripe-webhook:517
--   mark_transfer_reversed(text)          <- stripe-webhook:656
--
-- All three: SECURITY DEFINER, search_path pinned, EXECUTE granted to
-- service_role ONLY (revoked from PUBLIC/anon/authenticated). Verified post-apply.
--
-- SEMANTICS. record_transfer_payout unifies the two callers' WHERE clauses and
-- is strictly stricter than either (expiry guarded on stripe_transfer_id IS
-- NULL, confirm-and-release on payout_released_at IS NULL). Safe: the two
-- columns are only ever written together by those same two sites, and a
-- production census found 22 both-set / 13 neither-set / 0 split rows. It also
-- closes a latent hole where the old confirm-and-release WHERE could overwrite
-- a non-NULL stripe_transfer_id.
--
-- freeze_transfer_for_dispute moves the webhook's read-then-write TOCTOU check
-- into the statement. mark_transfer_reversed keeps its predicate identical
-- (status is NOT NULL, so <> and .neq behave alike).
--
-- Two contract details that matter:
--   * mark_transfer_reversed returns `v > 0`, NOT `= 1` -- stripe_transfer_id
--     has no unique index (only listing_id and payment_id do), so `= 1` would
--     report false while still having updated rows.
--   * both text-arg RPCs reject NULL/'' early: otherwise a NULL arg would write
--     NULL into stripe_transfer_id and then satisfy its own IS NULL guard on retry.
--
-- DEPLOY ORDER (056b must not jump the queue):
--   1. 056a  (this migration)                     <- done
--   2. deploy enforce-transfer-expiry, confirm-and-release, stripe-webhook
--   3. soak >= 1 full cron cycle + 1 live payout, zero PGRST202 /
--      "record_transfer_payout FAILED" / "Cannot directly modify transfer
--      state columns" in edge logs
--   4. 056b  (drop the service_role exemption)
--
-- If 056b lands before step 2 converges: every payout write is rejected, the
-- seller is paid but the DB never records it, and Phase 2b re-sweeps the row
-- forever (the shared Stripe idempotency key prevents a double payout, but the
-- row never converges). Disputes also stop freezing. Recovery is a single
-- CREATE OR REPLACE restoring the exemption.
--
-- NOTE for the function patch: enforce-transfer-expiry currently DISCARDS the
-- update error (destructures `{ data: updated }` only), so a DB failure is
-- today indistinguishable from a race. The converted call must add an explicit
-- error branch, or an orphaned payout becomes invisible.
--
-- Rollback: supabase/rollbacks/056a_transfer_writer_rpcs_rollback.sql

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805045314. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 056a: the three trusted RPCs that replace the four direct Edge Function
-- writes to public.transfers. ADDITIVE ONLY -- the `current_user =
-- 'service_role'` exemption stays in guard_transfer_state_columns, so the old
-- direct-UPDATE path and the new RPC path both work. That is what makes the
-- Edge Function deploy safe to do in either order.
--
-- 056b (removing the exemption) must NOT be applied until the three functions
-- are deployed AND soaked for at least one full cron cycle plus one live
-- payout with zero PGRST202 / record_transfer_payout failures in edge logs.

CREATE OR REPLACE FUNCTION public.record_transfer_payout(p_transfer_id uuid, p_stripe_transfer_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  -- Without this guard a NULL arg would write NULL into stripe_transfer_id and
  -- then satisfy its own IS NULL predicate on the next retry.
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RETURN false;
  END IF;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);

  -- Unifies the two callers' WHERE clauses. Strictly stricter than either:
  -- enforce-transfer-expiry guarded on stripe_transfer_id IS NULL,
  -- confirm-and-release on payout_released_at IS NULL. Verified safe -- the two
  -- columns are only ever written together by these same two sites, and a
  -- production census found 22 both-set / 13 neither-set / 0 split rows.
  UPDATE public.transfers
     SET payout_released_at = now(),
         stripe_transfer_id = p_stripe_transfer_id
   WHERE id = p_transfer_id
     AND stripe_transfer_id IS NULL
     AND payout_released_at IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;   -- id is the PK
END; $function$;

CREATE OR REPLACE FUNCTION public.freeze_transfer_for_dispute(p_transfer_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  -- Moves the webhook's read-then-write TOCTOU check into the statement.
  UPDATE public.transfers
     SET status = 'disputed', disputed_at = now()
   WHERE id = p_transfer_id
     AND payout_released_at IS NULL
     AND status <> 'disputed';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated = 1;   -- id is the PK
END; $function$;

CREATE OR REPLACE FUNCTION public.mark_transfer_reversed(p_stripe_transfer_id text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_updated int;
BEGIN
  IF p_stripe_transfer_id IS NULL OR p_stripe_transfer_id = '' THEN
    RETURN false;
  END IF;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers
     SET status = 'reversed'
   WHERE stripe_transfer_id = p_stripe_transfer_id
     AND status <> 'reversed';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  -- `> 0`, NOT `= 1`: transfers.stripe_transfer_id has no unique index (only
  -- listing_id and payment_id do), so a duplicate would make `= 1` report
  -- false while still having updated rows.
  RETURN v_updated > 0;
END; $function$;

REVOKE ALL ON FUNCTION public.record_transfer_payout(uuid, text)   FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.freeze_transfer_for_dispute(uuid)    FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_transfer_reversed(text)         FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_transfer_payout(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.freeze_transfer_for_dispute(uuid)  TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_transfer_reversed(text)       TO service_role;
