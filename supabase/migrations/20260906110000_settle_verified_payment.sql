-- ============================================================================
-- 20260906110000_settle_verified_payment.sql
-- Package 2 of docs/security/PAYMENTS_RELIABILITY_2026-09/01_INTEGRATED_PLAN.md
-- (ratified decision 5). Closes investigation findings F02 / F05 / F06 on the
-- database side; depends on Package 1's public.settle_listing_for_payment.
--
-- PURPOSE
--   1. ONE verified-settlement contract: public.settle_verified_payment(...).
--      Given what Stripe says about a PaymentIntent (status, amount_received,
--      currency, livemode, refund facts, metadata) it verifies the binding
--      against the stored payments row, enforces refund monotonicity,
--      promotes the row only on Stripe `succeeded`, delegates listing/transfer
--      settlement to the Package 1 core, and records every non-settling
--      outcome ONCE in public.webhook_retries (the previously orphaned table
--      becomes the compensation / review queue). service_role only; used by
--      stripe-webhook, confirm-payment and the reconciliation sweep in
--      enforce-transfer-expiry. Never calls the network.
--   2. public.get_unsettled_payments(p_limit): the sweep's work list —
--      paid-but-unsettled rows, stale pending rows (late captures), and
--      unresolved `unfulfillable` review rows joined to their payment.
--   3. cleanup_expired_reservations(): body only. Identical to 000 plus
--      "never re-list a listing that holds a succeeded payment" (N1). Before
--      this, a paid listing whose reservation lapsed while the webhook was
--      down was flipped back to active by the 2-minute cron, resold, and the
--      second buyer's promotion 500-looped forever on
--      idx_payments_one_success_per_listing (investigation B §2 row 2).
--
-- FORWARD BEHAVIOUR (settle_verified_payment, single transaction; every step
-- is guarded by CURRENT state, never by "did I run before")
--   outcome           meaning / writes
--   unknown_payment   no payments row for the PI. Review row (payment_id NULL,
--                     error_message 'unknown_payment:<pi> source=<src>'). No
--                     other writes.
--   binding_mismatch  (only checked once the row is found) currency not usd;
--                     stripe_livemode set and different; metadata carries a
--                     mode / listing_id / buyer_id / seller_id that is not the
--                     row's; or, when p_stripe_status = 'succeeded',
--                     amount_received <> total. Review row; NO writes to
--                     payments / listings / transfers. (amount_received is 0
--                     for a canceled or processing PI, so the amount check is
--                     scoped to the succeeded case — otherwise a canceled PI
--                     could never mark its row failed.)
--   refunded          row already refunded (no promotion, refund id filled in
--                     if we did not have it), OR p_amount_refunded > 0:
--                     refunded_at/stripe_refund_id are set once (coalesce);
--                     when the refund covers total the row becomes refunded —
--                     promoting pending -> succeeded first when Stripe says
--                     succeeded so the transition is succeeded -> refunded.
--                     Listing/transfer untouched.
--   canceled          p_stripe_status = 'canceled': a pending row becomes
--                     failed (failed_at = now()). Nothing else.
--   not_succeeded     any other non-succeeded Stripe status. No writes.
--   unfulfillable     the promotion collided with idx_payments_one_success_
--                     per_listing (another payment holds the listing's one
--                     success; row left as is; review row
--                     'unfulfillable:one_success_per_listing'), OR the core
--                     reported the listing cannot be fulfilled (sold to another
--                     payment / cancelled / not the auction winner; the row
--                     STAYS succeeded — the money fact is real — review row
--                     'unfulfillable:listing'). The sweep refunds these.
--   settled           row promoted (paid_at / payment_method coalesced),
--                     listing sold, transfer created.
--   already_settled   listing already sold to this payment; transfer ensured.
--   Promotion predicate is status NOT IN ('succeeded','refunded'), so Package
--   3's transition guard (refunded terminal) never fires on a legitimate path.
--   Review rows are idempotent per (payment / PI, outcome prefix): a redelivery
--   never adds a second unresolved row.
--
-- COMPATIBILITY
--   New functions only; no signature changes anywhere. Shipped clients keep
--   calling confirm-payment -> mark_listing_sold / complete_auction_payment
--   -> ensure_transfer_exists: confirm-payment now settles through this
--   contract, so the wrappers see an already-settled listing and no-op.
--   cleanup_expired_reservations keeps its signature and grants.
--
-- LOCKS & RUNTIME
--   CREATE OR REPLACE FUNCTION only — no table rewrite, no long lock. Runtime:
--   settle_verified_payment takes FOR UPDATE on the payments row, then the
--   core takes the listing row — the fixed payments -> listings order shared
--   with Package 1, so a concurrent client wrapper and a concurrent webhook
--   cannot deadlock. get_unsettled_payments is read-only. No network calls
--   inside any lock (the edges fetch Stripe BEFORE calling the RPC).
--
-- ROLLBACK
--   supabase/rollbacks/20260906110000_settle_verified_payment_rollback.sql
--   drops the two new functions and restores the 000 cleanup body verbatim.
--   NOTE: rolling back while the Package 2 edge functions are deployed makes
--   every payment_intent.succeeded delivery return 500 (RPC missing) — roll
--   the edges back first, or prefer fixing forward.
--
-- VERIFICATION
--   select p.proname, pg_get_userbyid(p.proowner), p.prosecdef, p.proconfig,
--          has_function_privilege('anon', p.oid, 'EXECUTE')          as anon_x,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_x,
--          has_function_privilege('service_role', p.oid, 'EXECUTE')  as svc_x,
--          md5(p.prosrc)
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and p.proname in ('settle_verified_payment','get_unsettled_payments',
--                        'cleanup_expired_reservations');
--   expected: all three anon_x=f auth_x=f svc_x=t, prosecdef=t, owner postgres,
--   proconfig {search_path=public}. pgTAP: supabase/tests/121_settlement.sql.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. The verified-settlement contract.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.settle_verified_payment(
  p_payment_intent_id text,
  p_stripe_status     text,
  p_amount_received   integer,
  p_currency          text,
  p_livemode          boolean,
  p_amount_refunded   integer,
  p_stripe_refund_id  text,
  p_payment_method    text,
  p_metadata          jsonb,
  p_source            text
) RETURNS TABLE(payment_id uuid, payment_status text, listing_status text, transfer_id uuid, outcome text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_p         public.payments%ROWTYPE;
  v_core      text;
  v_collision boolean := false;
BEGIN
  -- ── 1. Lock the payment. Lock order payments -> listings (same everywhere).
  SELECT * INTO v_p FROM public.payments p
   WHERE p.stripe_payment_intent_id = p_payment_intent_id
   FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
    SELECT NULL, NULL, 'settle_verified_payment',
           'unknown_payment:' || coalesce(p_payment_intent_id, '<null>') || ' source=' || coalesce(p_source, '<null>'),
           false
     WHERE NOT EXISTS (
       SELECT 1 FROM public.webhook_retries w
        WHERE w.rpc_name = 'settle_verified_payment' AND w.resolved IS NOT TRUE AND w.payment_id IS NULL
          AND w.error_message LIKE 'unknown_payment:' || coalesce(p_payment_intent_id, '<null>') || '%');
    payment_id := NULL; payment_status := NULL; listing_status := NULL; transfer_id := NULL;
    outcome := 'unknown_payment';
    RETURN NEXT; RETURN;
  END IF;

  payment_id     := v_p.id;
  payment_status := v_p.status;
  SELECT l.status INTO listing_status FROM public.listings l WHERE l.id = v_p.listing_id;
  SELECT t.id INTO transfer_id FROM public.transfers t WHERE t.payment_id = v_p.id;

  -- ── 2. Binding: Stripe's facts must describe THIS row. Never trusted, only
  --       cross-checked. No writes on mismatch.
  IF lower(coalesce(p_currency, '')) <> 'usd'
     OR (v_p.stripe_livemode IS NOT NULL AND v_p.stripe_livemode IS DISTINCT FROM p_livemode)
     OR (p_stripe_status = 'succeeded' AND (p_amount_received IS NULL OR p_amount_received <> v_p.total))
     OR (p_metadata ? 'mode'       AND nullif(p_metadata->>'mode', '')       IS NOT NULL AND p_metadata->>'mode'       <> v_p.mode)
     OR (p_metadata ? 'listing_id' AND nullif(p_metadata->>'listing_id', '') IS NOT NULL AND p_metadata->>'listing_id' <> v_p.listing_id::text)
     OR (p_metadata ? 'buyer_id'   AND nullif(p_metadata->>'buyer_id', '')   IS NOT NULL AND p_metadata->>'buyer_id'   <> v_p.buyer_id::text)
     OR (p_metadata ? 'seller_id'  AND nullif(p_metadata->>'seller_id', '')  IS NOT NULL AND p_metadata->>'seller_id'  <> v_p.seller_id::text)
  THEN
    INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
    SELECT v_p.id, v_p.listing_id, 'settle_verified_payment',
           'binding_mismatch:' || p_payment_intent_id
             || ' stripe=' || coalesce(p_stripe_status, '<null>') || '/' || coalesce(p_amount_received::text, '<null>')
             || '/' || coalesce(p_currency, '<null>') || '/live=' || coalesce(p_livemode::text, '<null>')
             || ' row=' || v_p.status || '/' || v_p.total || '/live=' || coalesce(v_p.stripe_livemode::text, '<null>')
             || ' source=' || coalesce(p_source, '<null>'),
           false
     WHERE NOT EXISTS (
       SELECT 1 FROM public.webhook_retries w
        WHERE w.rpc_name = 'settle_verified_payment' AND w.resolved IS NOT TRUE
          AND w.payment_id = v_p.id AND w.error_message LIKE 'binding_mismatch:%');
    outcome := 'binding_mismatch';
    RETURN NEXT; RETURN;
  END IF;

  -- ── 3. Refund monotonicity: a refund fact is never overwritten by a success.
  IF v_p.status = 'refunded' THEN
    IF v_p.stripe_refund_id IS NULL AND nullif(p_stripe_refund_id, '') IS NOT NULL THEN
      UPDATE public.payments SET stripe_refund_id = p_stripe_refund_id WHERE id = v_p.id;
    END IF;
    outcome := 'refunded';
    RETURN NEXT; RETURN;
  END IF;

  IF coalesce(p_amount_refunded, 0) > 0 THEN
    IF coalesce(p_amount_refunded, 0) >= v_p.total THEN
      -- Full refund of a captured charge: record the success first when Stripe
      -- says so, so the transition is pending -> succeeded -> refunded. A
      -- collision on the one-success index just means we skip the promotion.
      IF p_stripe_status = 'succeeded' AND v_p.status NOT IN ('succeeded', 'refunded') THEN
        BEGIN
          UPDATE public.payments
             SET status = 'succeeded',
                 paid_at = coalesce(paid_at, now()),
                 payment_method = coalesce(payment_method, p_payment_method)
           WHERE id = v_p.id AND status NOT IN ('succeeded', 'refunded');
        EXCEPTION WHEN unique_violation THEN
          NULL;
        END;
      END IF;
      UPDATE public.payments
         SET status = 'refunded',
             refunded_at = coalesce(refunded_at, now()),
             stripe_refund_id = coalesce(stripe_refund_id, nullif(p_stripe_refund_id, ''))
       WHERE id = v_p.id AND status <> 'refunded'
       RETURNING status INTO payment_status;
    ELSE
      -- Partial refund: keep the refund facts, do not promote or settle.
      UPDATE public.payments
         SET refunded_at = coalesce(refunded_at, now()),
             stripe_refund_id = coalesce(stripe_refund_id, nullif(p_stripe_refund_id, ''))
       WHERE id = v_p.id
       RETURNING status INTO payment_status;
    END IF;
    outcome := 'refunded';
    RETURN NEXT; RETURN;
  END IF;

  -- ── 4. Only a succeeded PaymentIntent moves anything forward.
  IF p_stripe_status = 'canceled' THEN
    IF v_p.status = 'pending' THEN
      UPDATE public.payments SET status = 'failed', failed_at = coalesce(failed_at, now())
       WHERE id = v_p.id AND status = 'pending'
       RETURNING status INTO payment_status;
    END IF;
    outcome := 'canceled';
    RETURN NEXT; RETURN;
  END IF;
  IF p_stripe_status IS DISTINCT FROM 'succeeded' THEN
    outcome := 'not_succeeded';
    RETURN NEXT; RETURN;
  END IF;

  -- ── 5. Promote pending | processing | failed -> succeeded.
  IF v_p.status NOT IN ('succeeded', 'refunded') THEN
    BEGIN
      UPDATE public.payments
         SET status = 'succeeded',
             paid_at = coalesce(paid_at, now()),
             payment_method = coalesce(payment_method, p_payment_method)
       WHERE id = v_p.id AND status NOT IN ('succeeded', 'refunded')
       RETURNING status INTO payment_status;
    EXCEPTION WHEN unique_violation THEN
      v_collision := true;
    END;
  END IF;

  IF v_collision THEN
    -- Another payment already holds this listing's one success. This capture
    -- cannot be fulfilled; the row is left exactly as it was and the sweep
    -- refunds it from the review queue.
    INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
    SELECT v_p.id, v_p.listing_id, 'settle_verified_payment', 'unfulfillable:one_success_per_listing', false
     WHERE NOT EXISTS (
       SELECT 1 FROM public.webhook_retries w
        WHERE w.rpc_name = 'settle_verified_payment' AND w.resolved IS NOT TRUE
          AND w.payment_id = v_p.id AND w.error_message = 'unfulfillable:one_success_per_listing');
    outcome := 'unfulfillable';
    RETURN NEXT; RETURN;
  END IF;

  -- ── 6. Listing + transfer through the ONE core (Package 1).
  v_core := public.settle_listing_for_payment(v_p.id);
  SELECT l.status INTO listing_status FROM public.listings l WHERE l.id = v_p.listing_id;
  SELECT t.id INTO transfer_id FROM public.transfers t WHERE t.payment_id = v_p.id;

  IF v_core = 'unfulfillable' THEN
    INSERT INTO public.webhook_retries (payment_id, listing_id, rpc_name, error_message, resolved)
    SELECT v_p.id, v_p.listing_id, 'settle_verified_payment', 'unfulfillable:listing', false
     WHERE NOT EXISTS (
       SELECT 1 FROM public.webhook_retries w
        WHERE w.rpc_name = 'settle_verified_payment' AND w.resolved IS NOT TRUE
          AND w.payment_id = v_p.id AND w.error_message = 'unfulfillable:listing');
    outcome := 'unfulfillable';
    RETURN NEXT; RETURN;
  END IF;

  outcome := v_core;   -- 'settled' | 'already_settled'
  RETURN NEXT; RETURN;
END; $function$;

ALTER FUNCTION public.settle_verified_payment(text, text, integer, text, boolean, integer, text, text, jsonb, text) OWNER TO postgres;

COMMENT ON FUNCTION public.settle_verified_payment(text, text, integer, text, boolean, integer, text, text, jsonb, text) IS
  'Package 2 verified-settlement contract (service_role only). Cross-checks Stripe''s PaymentIntent facts against the payments row, enforces refund monotonicity, promotes only on succeeded, settles through settle_listing_for_payment, and records unknown_payment / binding_mismatch / unfulfillable once in webhook_retries. Outcomes: settled | already_settled | refunded | not_succeeded | canceled | unfulfillable | unknown_payment | binding_mismatch.';

-- ---------------------------------------------------------------------------
-- 2. The reconciliation sweep's work list.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_unsettled_payments(p_limit integer DEFAULT 50)
RETURNS TABLE(payment_id uuid, stripe_payment_intent_id text, listing_id uuid, mode text, status text, paid_at timestamptz, kind text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  WITH candidates AS (
    -- review_unfulfillable: an unresolved unfulfillable review row. Highest
    -- priority: money is held for an order that cannot be delivered.
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           'review_unfulfillable'::text AS kind, 1 AS priority
      FROM public.webhook_retries w
      JOIN public.payments p ON p.id = w.payment_id
     WHERE w.rpc_name = 'settle_verified_payment'
       AND w.resolved IS NOT TRUE
       AND w.error_message LIKE 'unfulfillable%'
       AND p.status <> 'refunded'
    UNION ALL
    -- paid_unsettled: the money fact is recorded but the listing is not sold
    -- or the seller has no transfer obligation yet.
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           'paid_unsettled'::text, 2
      FROM public.payments p
      JOIN public.listings l ON l.id = p.listing_id
     WHERE p.status = 'succeeded'
       AND coalesce(p.paid_at, p.created_at) < now() - interval '5 minutes'
       AND p.stripe_payment_intent_id IS NOT NULL
       AND (l.status <> 'sold' OR NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id = p.id))
    UNION ALL
    -- pending_stale: a late capture whose success event may have been missed.
    -- Bounded to the last 24 hours so abandoned checkouts do not become a
    -- permanent Stripe look-up every run (card captures land within seconds;
    -- the webhook and confirm-payment remain the primary paths).
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           'pending_stale'::text, 3
      FROM public.payments p
     WHERE p.status = 'pending'
       AND p.stripe_payment_intent_id IS NOT NULL
       AND p.created_at < now() - interval '15 minutes'
       AND p.created_at > now() - interval '24 hours'
  ),
  deduped AS (
    SELECT DISTINCT ON (c.id) c.*
      FROM candidates c
     WHERE NOT EXISTS (SELECT 1 FROM public.payments x WHERE x.id = c.id AND x.stripe_livemode = false)
     ORDER BY c.id, c.priority
  )
  SELECT d.id, d.stripe_payment_intent_id, d.listing_id, d.mode, d.status, d.paid_at, d.kind
    FROM deduped d
   ORDER BY d.priority, coalesce(d.paid_at, d.created_at), d.id
   LIMIT greatest(coalesce(p_limit, 50), 1)
$function$;

ALTER FUNCTION public.get_unsettled_payments(integer) OWNER TO postgres;

COMMENT ON FUNCTION public.get_unsettled_payments(integer) IS
  'Package 2 reconciliation work list (service_role only): review_unfulfillable (unresolved unfulfillable review rows), paid_unsettled (succeeded > 5 min, listing not sold or no transfer), pending_stale (pending 15 min .. 24 h with a PaymentIntent). Test-mode rows (stripe_livemode = false) are excluded — the live key cannot see them. One row per payment, highest priority kind wins, oldest first.';

-- ---------------------------------------------------------------------------
-- 3. cleanup_expired_reservations — body only. 000 text plus the N1 guard.
-- ---------------------------------------------------------------------------
create or replace function public.cleanup_expired_reservations()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform set_config('app.bypass_listing_guard', 'on', true);
  update public.listings
     set status         = 'active',
         reserved_by    = null,
         reserved_until = null
   where status = 'reserved'
     and reserved_until <= now()
     -- N1 (Package 2): a listing that holds a succeeded payment is settled by
     -- settle_verified_payment / the reconciliation sweep, never re-listed.
     and not exists (
       select 1 from public.payments p
        where p.listing_id = listings.id
          and p.status = 'succeeded');
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Grants (SEC-2 default-ACL rule): explicit REVOKE from every client role,
--    then only the intended GRANTs. A bare REVOKE FROM PUBLIC is insufficient.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.settle_verified_payment(text, text, integer, text, boolean, integer, text, text, jsonb, text) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.settle_verified_payment(text, text, integer, text, boolean, integer, text, text, jsonb, text) TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_unsettled_payments(integer) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.get_unsettled_payments(integer) TO service_role;

-- Unchanged posture (063/067): re-issued so the body replacement can never be
-- read as having relaxed it.
REVOKE EXECUTE ON FUNCTION public.cleanup_expired_reservations() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cleanup_expired_reservations() TO service_role;
