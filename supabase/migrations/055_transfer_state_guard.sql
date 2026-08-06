-- =============================================================================
-- 055_transfer_state_guard.sql   APPLIED 2026-08-05, verified.
--
-- Applied in four parts (each a separate entry in the migration history):
--   055   transfer_state_guard                        - guard trigger, strict RPC auth, privilege lockdown
--   055b  transfer_guard_bypass_for_remaining_writers - GUC for the remaining SECURITY DEFINER writers
--   055c  revoke_anon_public_on_listing_rpcs          - same auth-bypass class on 5 listing/checkout RPCs
--   055d  fix_mark_transfer_sent_overload_ambiguity   - regression fix (see below)
--
-- CLOSES THREE CONFIRMED-EXPLOITABLE HOLES
--
-- 1. Forged-status payout (money theft). transfers' two RLS UPDATE policies had
--    with_check = NULL, so Postgres reused USING and pinned only buyer_id /
--    seller_id -- every other column was writable by either party, and
--    `authenticated` AND `anon` held UPDATE on all 32 columns.
--    enforce-transfer-expiry Phase 2b (index.ts:772-788) pays out on
--    `status IN ('auto_released','buyer_confirmed')` alone, with no check of
--    HOW the row reached that status and NO time gate on the auto_released
--    branch, and resolves the Stripe destination from the mutable
--    transfers.seller_id (index.ts:518-519). A buyer could therefore PATCH
--    {"status":"auto_released","seller_id":"<self>"} on their own transfer,
--    take delivery of the tickets, and receive the seller's payout within two
--    minutes. Phase 2's risk engine was bypassed entirely -- it only ever sees
--    status='seller_sent'.
--
-- 2. Anon-key identity forgery. Five SECURITY DEFINER RPCs resolved the caller
--    as coalesce(auth.uid(), p_user_id) and were EXECUTE-able by anon AND
--    PUBLIC (the bare '=X/postgres' ACL entry -- revoking anon alone would not
--    have closed it). With no session at all, auth.uid() is NULL and p_user_id
--    was trusted verbatim. The required uuids are public: listings_select_all
--    is USING (true), exposing seller_id / winner_user_id / highest_bidder_id.
--
-- 3. Evidence tampering. transfer_evidence_path / dispute_evidence_path were
--    freely rewritable, which also defeated 049 (null the reference, then the
--    storage DELETE policy permits removing the object).
--
-- FIX
--   * guard_transfer_state_columns() BEFORE UPDATE trigger, modelled on the
--     existing guard_listing_state_columns() precedent, with a transaction-local
--     `app.bypass_transfer_guard` GUC. Rejects direct changes to status, the
--     party/payment/listing ids, every state timestamp, all payout and Stripe
--     columns, and the deadlines. Evidence paths are append-only.
--   * Strict identity on the transfer RPCs: auth.uid() is authoritative;
--     p_user_id is honoured only when request_is_service_role() is true (the
--     confirm-and-release edge function legitimately depends on it, index.ts:205).
--   * REVOKE EXECUTE FROM PUBLIC, anon on all six transfer RPCs and (055c) the
--     five listing/checkout RPCs carrying the same coalesce fallback:
--     cancel_listing, complete_auction_payment, mark_listing_sold,
--     release_reservation, reserve_buy_now.
--   * REVOKE ALL on public.transfers from authenticated/anon, re-GRANT SELECT
--     only, and drop both with_check=NULL UPDATE policies. Verified first that
--     every mobile and web `.from('transfers')` call site is a SELECT -- all
--     mutations already go through RPCs or service-role edge functions.
--
-- SERVICE-ROLE EXEMPTION IS TEMPORARY. Four edge-function writes still reach
-- the table directly through PostgREST as service_role and cannot set a
-- transaction-local GUC (enforce-transfer-expiry:670, confirm-and-release:541,
-- stripe-webhook:517 and :656). The guard therefore still lets current_user =
-- 'service_role' through. Migration 056 moves those four to RPCs and removes
-- the exemption -- it MUST NOT be applied before that edge-function deploy.
--
-- 055d REGRESSION FIX: 055 recreated the 3-arg mark_transfer_sent with
-- `p_transfer_evidence_path text DEFAULT NULL`. That default made the 3-arg
-- overload a viable candidate for a 2-key JSON body, so PostgREST returned
-- PGRST203 for {p_transfer_id, p_user_id} -- exactly the payload shipped build
-- 13 sends (ListingDetailScreen.tsx:798), breaking the seller mark-sent path
-- for the build in App Review. Caught by the adversarial suite. The default was
-- dropped; both overloads now resolve unambiguously.
--
-- VERIFIED AFTER APPLYING
--   client privileges on transfers ... SELECT only
--   anon/PUBLIC EXECUTE on transfer RPCs ... 0
--   guard trigger armed ... yes      UPDATE policies remaining ... 0
--   seller/payment ownership mismatches ... 0 / 0
--   anon attacks all rejected 42501: PATCH transfers, confirm_transfer_received,
--     buyer_dispute_transfer, ensure_transfer_exists, cancel_listing,
--     reserve_buy_now; mark_transfer_sent resolves per-overload then denies
--   cron jobs 7 and 9 succeeded continuously across the migration window
--
-- Rollback: supabase/rollbacks/055_transfer_state_guard_rollback.sql
-- Full applied SQL is in the Supabase migration history under the four names above.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- SQL below recovered verbatim from supabase_migrations.schema_migrations
-- version 20260805040743. This file previously contained documentation only.
-- ---------------------------------------------------------------------------
-- 055: transfers state guard + strict RPC auth + privilege lockdown.
-- Service-role exemption is TEMPORARY, removed in 056 after the edge-function deploy.

CREATE OR REPLACE FUNCTION public.request_is_service_role()
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_role text; v_claims text;
BEGIN
  v_role := nullif(current_setting('request.jwt.claim.role', true), '');
  IF v_role IS NULL THEN
    v_claims := nullif(current_setting('request.jwt.claims', true), '');
    IF v_claims IS NOT NULL THEN
      BEGIN v_role := v_claims::jsonb ->> 'role'; EXCEPTION WHEN others THEN v_role := NULL; END;
    END IF;
  END IF;
  IF v_role = 'service_role' THEN RETURN true; END IF;
  IF v_role IS NULL AND current_setting('request.jwt.claims', true) IS NULL THEN RETURN true; END IF;
  RETURN false;
END; $function$;

REVOKE EXECUTE ON FUNCTION public.request_is_service_role() FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.request_is_service_role() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.guard_transfer_state_columns()
RETURNS trigger LANGUAGE plpgsql
AS $function$
BEGIN
  IF current_setting('app.bypass_transfer_guard', true) = 'on' THEN RETURN NEW; END IF;
  -- TEMPORARY (removed in 056): four edge-function writes still reach this table
  -- directly through PostgREST as service_role and cannot set a local GUC.
  IF current_user = 'service_role' THEN RETURN NEW; END IF;

  IF NEW.status               IS DISTINCT FROM OLD.status
  OR NEW.seller_id            IS DISTINCT FROM OLD.seller_id
  OR NEW.buyer_id             IS DISTINCT FROM OLD.buyer_id
  OR NEW.payment_id           IS DISTINCT FROM OLD.payment_id
  OR NEW.listing_id           IS DISTINCT FROM OLD.listing_id
  OR NEW.seller_sent_at       IS DISTINCT FROM OLD.seller_sent_at
  OR NEW.buyer_confirmed_at   IS DISTINCT FROM OLD.buyer_confirmed_at
  OR NEW.disputed_at          IS DISTINCT FROM OLD.disputed_at
  OR NEW.payout_released_at   IS DISTINCT FROM OLD.payout_released_at
  OR NEW.stripe_transfer_id   IS DISTINCT FROM OLD.stripe_transfer_id
  OR NEW.payout_hold_until    IS DISTINCT FROM OLD.payout_hold_until
  OR NEW.payout_review_status IS DISTINCT FROM OLD.payout_review_status
  OR NEW.payout_risk_tier     IS DISTINCT FROM OLD.payout_risk_tier
  OR NEW.payout_reason_codes  IS DISTINCT FROM OLD.payout_reason_codes
  OR NEW.auto_release_at      IS DISTINCT FROM OLD.auto_release_at
  OR NEW.expires_at           IS DISTINCT FROM OLD.expires_at
  OR NEW.expired_at           IS DISTINCT FROM OLD.expired_at
  THEN
    RAISE EXCEPTION 'Cannot directly modify transfer state columns. Use the appropriate RPC.';
  END IF;

  IF OLD.transfer_evidence_path IS NOT NULL
     AND NEW.transfer_evidence_path IS DISTINCT FROM OLD.transfer_evidence_path THEN
    RAISE EXCEPTION 'transfer_evidence_path is append-only.';
  END IF;
  IF OLD.dispute_evidence_path IS NOT NULL
     AND NEW.dispute_evidence_path IS DISTINCT FROM OLD.dispute_evidence_path THEN
    RAISE EXCEPTION 'dispute_evidence_path is append-only.';
  END IF;
  RETURN NEW;
END; $function$;

DROP TRIGGER IF EXISTS trg_guard_transfer_state_columns ON public.transfers;
CREATE TRIGGER trg_guard_transfer_state_columns
  BEFORE UPDATE ON public.transfers
  FOR EACH ROW EXECUTE FUNCTION public.guard_transfer_state_columns();

CREATE OR REPLACE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_seller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, seller_id INTO v_status, v_seller_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the seller can mark a transfer as sent.'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+interval '72 hours' WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.mark_transfer_sent(p_transfer_id uuid, p_user_id uuid, p_transfer_evidence_path text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_seller_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, seller_id INTO v_status, v_seller_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_seller_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the seller can mark a transfer as sent.'; END IF;
  IF v_status <> 'pending' THEN RAISE EXCEPTION 'Transfer cannot be marked as sent from current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='seller_sent', seller_sent_at=now(), auto_release_at=now()+INTERVAL '72 hours',
    transfer_evidence_path=COALESCE(p_transfer_evidence_path, transfer_evidence_path) WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.confirm_transfer_received(p_transfer_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_buyer_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, buyer_id INTO v_status, v_buyer_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the buyer can confirm transfer receipt.'; END IF;
  IF v_status <> 'seller_sent' THEN RAISE EXCEPTION 'Transfer cannot be confirmed from current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='buyer_confirmed', buyer_confirmed_at=now() WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.buyer_dispute_transfer(p_transfer_id uuid, p_user_id uuid DEFAULT NULL::uuid, p_dispute_reason text DEFAULT NULL::text, p_dispute_evidence_path text DEFAULT NULL::text, p_dispute_notes text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_buyer_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, buyer_id INTO v_status, v_buyer_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the buyer can dispute a transfer.'; END IF;
  IF v_status = 'disputed' THEN RETURN; END IF;
  IF v_status <> 'seller_sent' THEN RAISE EXCEPTION 'Cannot dispute transfer in current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET status='disputed', disputed_at=now(),
    dispute_reason=COALESCE(p_dispute_reason, dispute_reason),
    dispute_evidence_path=COALESCE(p_dispute_evidence_path, dispute_evidence_path),
    dispute_notes=COALESCE(p_dispute_notes, dispute_notes) WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.set_transfer_delivery_info(p_transfer_id uuid, p_delivery_email text DEFAULT NULL::text, p_delivery_phone text DEFAULT NULL::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_buyer_id uuid;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;
  SELECT status, buyer_id INTO v_status, v_buyer_id FROM public.transfers WHERE id = p_transfer_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transfer not found.'; END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller_id THEN RAISE EXCEPTION 'Only the buyer can set delivery info.'; END IF;
  IF v_status NOT IN ('pending', 'seller_sent') THEN RAISE EXCEPTION 'Cannot update delivery info in current status: %.', v_status; END IF;
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET delivery_email=COALESCE(p_delivery_email, delivery_email),
    delivery_phone=COALESCE(p_delivery_phone, delivery_phone) WHERE id=p_transfer_id;
END; $function$;

CREATE OR REPLACE FUNCTION public.mark_transfer_viewed(p_transfer_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  UPDATE public.transfers SET buyer_viewed_at = COALESCE(buyer_viewed_at, now())
   WHERE id = p_transfer_id AND buyer_id = auth.uid();
END; $function$;

REVOKE EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid)                       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid, text)                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.confirm_transfer_received(uuid, uuid)                FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.buyer_dispute_transfer(uuid, uuid, text, text, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid, uuid)                   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.set_transfer_delivery_info(uuid, text, text)         FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid)                       TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.mark_transfer_sent(uuid, uuid, text)                 TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.confirm_transfer_received(uuid, uuid)                TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.buyer_dispute_transfer(uuid, uuid, text, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ensure_transfer_exists(uuid, uuid)                   TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_transfer_delivery_info(uuid, text, text)         TO authenticated, service_role;

REVOKE ALL ON TABLE public.transfers FROM authenticated, anon;
GRANT  SELECT ON TABLE public.transfers TO authenticated, anon;

DROP POLICY IF EXISTS "Buyers can update own transfers"  ON public.transfers;
DROP POLICY IF EXISTS "Sellers can update own transfers" ON public.transfers;
