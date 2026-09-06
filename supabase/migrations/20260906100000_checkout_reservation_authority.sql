-- ============================================================================
-- 20260906100000_checkout_reservation_authority.sql
-- Package 1 of docs/security/PAYMENTS_RELIABILITY_2026-09/01_INTEGRATED_PLAN.md
-- (ratified decisions 1-4). Closes investigation findings F01 / F03 / F04 on
-- the database side.
--
-- PURPOSE
--   1. ONE listing-settlement core: public.settle_listing_for_payment(uuid).
--      Given a SUCCEEDED payments row it marks the listing sold and creates
--      the transfer row atomically, or reports 'already_settled' /
--      'unfulfillable' with NO side effects. Zero client EXECUTE — reached
--      only through owner (SECURITY DEFINER) functions: the two shipped
--      wrappers below now, Package 2's settle_verified_payment next.
--   2. mark_listing_sold / complete_auction_payment (shipped-client RPCs,
--      signatures unchanged) require a bound succeeded payment for auth.uid()
--      before they can flip inventory, then delegate to the core. Before this
--      an unpaid reservation holder / auction winner could mark a listing
--      sold from POST /rest/v1/rpc with a user JWT (F03).
--   3. reserve_buy_now (signature unchanged): the reservation is server-owned.
--      TTL is a fixed 10 minutes (p_minutes accepted for wire compatibility,
--      ignored); a holder re-reserving keeps its existing window; one live
--      reservation per buyer (reserving another listing releases the previous
--      one); check_rate_limit(caller,'reserve_buy_now',20,600) fail-closed.
--      Before this p_minutes was unbounded and re-callable (F04).
--
-- FORWARD BEHAVIOUR (decisions 1-3)
--   * Money wins. A succeeded payment settles the listing even if the buyer's
--     reservation lapsed or another buyer currently holds a live Buy-Now
--     reservation (that holder cannot have paid: create-payment-intent binds
--     the PaymentIntent to the live holder and idx_payments_one_success_per_
--     listing admits one success). The old "reservation expired => release +
--     raise" side effect of mark_listing_sold is removed.
--   * A capture that can no longer be fulfilled (listing sold to a different
--     payment, cancelled, auction not won by the payer) is 'unfulfillable';
--     the core touches nothing and never expires/releases a reservation.
--   * Buy-Now hold has priority over an auction win WHILE LIVE:
--     complete_auction_payment refuses with 'This listing is already reserved
--     by another buyer.' until that hold lapses (the webhook path settles it
--     later via Package 2).
--
-- COMPATIBILITY
--   No signature, argument name, or return type changes. Mobile builds <= 13
--   and web call confirm-payment (Stripe-verified `succeeded` write) before
--   these wrappers, so the wrappers succeed on the happy path and no-op when
--   the server settled first. Refusal strings match the regexes in
--   src/lib/payments.ts (/already reserved/, /already sold/, /reservation
--   expired/) so field builds render a real message. Error text for the
--   NEW refusals: 'No verified payment found for this listing. Payment must
--   be confirmed before the sale can complete.' (mirrors 061) and 'Too many
--   reservation attempts. Please try again later.'
--
-- LOCKS & RUNTIME
--   CREATE OR REPLACE FUNCTION only — no table rewrite, no long lock. Runtime
--   behaviour: every state transition takes FOR UPDATE row locks in the fixed
--   order payments -> listings (the core and both wrappers), so a concurrent
--   wrapper call and a concurrent webhook settlement cannot deadlock on the
--   pair. reserve_buy_now additionally updates the caller's OTHER live holds
--   (ordinary row locks; Postgres deadlock detection resolves the pathological
--   cross-order case by failing one caller, who retries).
--
-- ROLLBACK
--   supabase/rollbacks/20260906100000_checkout_reservation_authority_rollback.sql
--   restores the 0590 bodies verbatim, re-issues the 0552/0590 grants and
--   drops the core. NOTE: rolling back re-opens F03/F04 and the wrappers again
--   settle without a payment check.
--
-- VERIFICATION
--   select p.proname, pg_get_userbyid(p.proowner), p.prosecdef, p.proconfig,
--          has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_x,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_x,
--          has_function_privilege('service_role', p.oid, 'EXECUTE')  as svc_x,
--          md5(p.prosrc)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('settle_listing_for_payment','mark_listing_sold',
--                        'complete_auction_payment','reserve_buy_now');
--   expected: settle_listing_for_payment anon_x=f auth_x=f svc_x=f; the three
--   wrappers anon_x=f auth_x=t svc_x=t; all prosecdef=t, owner postgres,
--   proconfig {search_path=public}. pgTAP: supabase/tests/120_reservation_lifecycle.sql.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. The settlement core.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.settle_listing_for_payment(p_payment_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_p  public.payments%ROWTYPE;
  v_l  public.listings%ROWTYPE;
  v_transfer_payment uuid;
BEGIN
  -- Lock order: payments -> listings (same everywhere).
  SELECT * INTO v_p FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Payment not found.'; END IF;
  IF v_p.status <> 'succeeded' THEN
    RAISE EXCEPTION 'Payment has not succeeded; cannot settle the listing.';
  END IF;

  SELECT * INTO v_l FROM public.listings WHERE id = v_p.listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;

  -- A transfer already bound to a DIFFERENT payment means the listing was
  -- settled to someone else (e.g. an earlier sale later refunded): this
  -- capture cannot be fulfilled. Checked before any write.
  SELECT payment_id INTO v_transfer_payment
    FROM public.transfers WHERE listing_id = v_l.id;
  IF FOUND AND v_transfer_payment IS DISTINCT FROM p_payment_id THEN
    RETURN 'unfulfillable';
  END IF;

  IF v_l.status = 'sold' THEN
    -- Sold, and no transfer bound to another payment: this row is the
    -- listing's one succeeded payment (idx_payments_one_success_per_listing),
    -- so the sale is this buyer's. Make sure the transfer exists (heals a
    -- legacy sold-without-transfer state) and report idempotently.
    IF v_transfer_payment IS NULL THEN
      PERFORM set_config('app.bypass_transfer_guard', 'on', true);
      INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
      VALUES (v_l.id, v_p.id, v_p.seller_id, v_p.buyer_id,
              coalesce(v_l.transfer_method, 'mobile_transfer'), 'pending', now() + interval '24 hours')
      ON CONFLICT (payment_id) DO NOTHING;
    END IF;
    RETURN 'already_settled';
  END IF;

  IF v_l.auction_status = 'cancelled' THEN RETURN 'unfulfillable'; END IF;

  IF v_p.mode = 'auction' THEN
    -- Only the auction winner's payment settles an auction. No reservation
    -- check here (money wins); the client wrapper applies decision 3.
    IF v_l.auction_status <> 'ended' OR v_l.winner_user_id IS DISTINCT FROM v_p.buyer_id THEN
      RETURN 'unfulfillable';
    END IF;
  END IF;
  -- mode = 'buy_now': settle regardless of reserved_by / reserved_until.

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET status = 'sold', auction_status = 'sold', sold_at = now(),
         reserved_by = NULL, reserved_until = NULL
   WHERE id = v_l.id;

  PERFORM set_config('app.bypass_transfer_guard', 'on', true);
  INSERT INTO public.transfers (listing_id, payment_id, seller_id, buyer_id, transfer_method, status, expires_at)
  VALUES (v_l.id, v_p.id, v_p.seller_id, v_p.buyer_id,
          coalesce(v_l.transfer_method, 'mobile_transfer'), 'pending', now() + interval '24 hours')
  ON CONFLICT (payment_id) DO NOTHING;

  RETURN 'settled';
END; $function$;

ALTER FUNCTION public.settle_listing_for_payment(uuid) OWNER TO postgres;

COMMENT ON FUNCTION public.settle_listing_for_payment(uuid) IS
  'Package 1 settlement core. Given a SUCCEEDED payment: marks the listing sold and creates the transfer row (ON CONFLICT DO NOTHING); returns settled | already_settled | unfulfillable. Never writes payments, never releases a reservation. No client EXECUTE — reached only through owner functions (mark_listing_sold, complete_auction_payment, settle_verified_payment).';

-- ---------------------------------------------------------------------------
-- 2. mark_listing_sold — body only. Requires a bound succeeded buy_now payment.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_listing_sold(p_listing_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_payment_id uuid; v_result text;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  -- Only a payment a Stripe-verified writer already marked succeeded, for
  -- THIS caller and THIS listing in Buy-Now mode, can complete the sale.
  SELECT id INTO v_payment_id
    FROM public.payments
   WHERE listing_id = p_listing_id
     AND buyer_id   = v_caller_id
     AND mode       = 'buy_now'
     AND status     = 'succeeded'
   ORDER BY created_at DESC LIMIT 1
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No verified payment found for this listing. Payment must be confirmed before the sale can complete.';
  END IF;

  v_result := public.settle_listing_for_payment(v_payment_id);
  IF v_result = 'unfulfillable' THEN
    RAISE EXCEPTION 'This listing has already been sold.';
  END IF;
  -- 'settled' / 'already_settled': done (idempotent for client retries and
  -- for the webhook-settled-first case).
END; $function$;

-- ---------------------------------------------------------------------------
-- 3. complete_auction_payment — body only. Requires a bound succeeded auction
--    payment; refuses while another buyer's Buy-Now hold is live (decision 3).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_auction_payment(p_listing_id uuid, p_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_payment_id uuid; v_result text;
        v_status text; v_reserved_by uuid; v_reserved_until timestamptz;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  -- Lock order payments -> listings, matching the core.
  SELECT id INTO v_payment_id
    FROM public.payments
   WHERE listing_id = p_listing_id
     AND buyer_id   = v_caller_id
     AND mode       = 'auction'
     AND status     = 'succeeded'
   ORDER BY created_at DESC LIMIT 1
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'No verified payment found for this listing. Payment must be confirmed before the sale can complete.';
  END IF;

  SELECT status, reserved_by, reserved_until INTO v_status, v_reserved_by, v_reserved_until
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;

  -- Buy-Now hold has priority over the auction win while it is live.
  IF v_status = 'reserved'
     AND v_reserved_by IS NOT NULL
     AND v_reserved_by IS DISTINCT FROM v_caller_id
     AND v_reserved_until > now() THEN
    RAISE EXCEPTION 'This listing is already reserved by another buyer.';
  END IF;

  v_result := public.settle_listing_for_payment(v_payment_id);
  IF v_result = 'unfulfillable' THEN
    RAISE EXCEPTION 'This listing has already been sold.';
  END IF;
END; $function$;

-- ---------------------------------------------------------------------------
-- 4. reserve_buy_now — body only. Server-owned TTL, no extension, one live
--    hold per buyer, fail-closed rate limit (decision 2).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.reserve_buy_now(p_listing_id uuid, p_user_id uuid, p_minutes integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_caller_id uuid; v_status text; v_ends_at timestamptz;
        v_reserved_by uuid; v_reserved_until timestamptz; v_auction_status text;
        v_minutes integer;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL AND public.request_is_service_role() THEN v_caller_id := p_user_id; END IF;
  IF v_caller_id IS NULL THEN RAISE EXCEPTION 'Unable to identify caller. Ensure the request is authenticated.'; END IF;

  -- The reservation window is SERVER-OWNED. p_minutes stays in the signature
  -- for wire compatibility with shipped clients (they send 10) and is ignored.
  v_minutes := 10;

  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings SET status='active', reserved_by=null, reserved_until=null
   WHERE id = p_listing_id AND status='reserved' AND reserved_until <= now();

  SELECT status, ends_at, reserved_by, reserved_until, auction_status
    INTO v_status, v_ends_at, v_reserved_by, v_reserved_until, v_auction_status
    FROM public.listings WHERE id = p_listing_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Listing not found.'; END IF;

  IF EXISTS (SELECT 1 FROM public.listings WHERE id = p_listing_id AND seller_id = v_caller_id) THEN
    RAISE EXCEPTION 'You cannot purchase your own listing.';
  END IF;
  IF v_status = 'sold' THEN RAISE EXCEPTION 'This listing has already been sold.'; END IF;
  IF v_auction_status = 'cancelled' THEN RAISE EXCEPTION 'This listing has been cancelled.'; END IF;
  IF now() > v_ends_at THEN RAISE EXCEPTION 'This auction has ended.'; END IF;
  IF v_status = 'reserved' THEN
    IF v_reserved_by IS DISTINCT FROM v_caller_id AND v_reserved_until > now() THEN
      RAISE EXCEPTION 'This listing is already reserved by another buyer.';
    END IF;
    -- The holder re-reserving its own live hold keeps the EXISTING window.
    IF v_reserved_by = v_caller_id AND v_reserved_until > now() THEN
      RETURN;
    END IF;
  END IF;

  -- Fail-closed: check_rate_limit returns false on its own internal error.
  IF NOT public.check_rate_limit(v_caller_id, 'reserve_buy_now', 20, 600) THEN
    RAISE EXCEPTION 'Too many reservation attempts. Please try again later.';
  END IF;

  -- One live reservation per buyer: release the caller's OTHER holds first.
  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings SET status='active', reserved_by=null, reserved_until=null
   WHERE reserved_by = v_caller_id AND status='reserved' AND id <> p_listing_id;

  UPDATE public.listings
     SET status='reserved', reserved_by=v_caller_id,
         reserved_until = now() + (v_minutes || ' minutes')::interval
   WHERE id = p_listing_id;
END; $function$;

-- ---------------------------------------------------------------------------
-- 5. Grants (SEC-2 default-ACL rule): explicit REVOKE from every client role,
--    then only the intended GRANTs. A bare REVOKE FROM PUBLIC is insufficient.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.settle_listing_for_payment(uuid)   FROM PUBLIC, anon, authenticated, service_role;
-- (no GRANT: reached only through owner functions)

REVOKE EXECUTE ON FUNCTION public.mark_listing_sold(uuid, uuid)          FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.complete_auction_payment(uuid, uuid)   FROM PUBLIC, anon, authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.reserve_buy_now(uuid, uuid, integer)   FROM PUBLIC, anon, authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.mark_listing_sold(uuid, uuid)          TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.complete_auction_payment(uuid, uuid)   TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.reserve_buy_now(uuid, uuid, integer)   TO authenticated, service_role;
