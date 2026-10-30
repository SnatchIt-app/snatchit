-- ROLLBACK for 20260916000000_processing_sweep_arm.sql (registry 134) — restores public.get_unsettled_payments
-- EXACTLY as the 20260906110000 chain tip defines it (pg_get_functiondef at that tip).
begin;

CREATE OR REPLACE FUNCTION public.get_unsettled_payments(p_limit integer DEFAULT 50)
 RETURNS TABLE(payment_id uuid, stripe_payment_intent_id text, listing_id uuid, mode text, status text, paid_at timestamp with time zone, kind text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH candidates AS (
    -- review_unfulfillable: an unresolved unfulfillable review row. Highest
    -- priority: money is held for an order that cannot be delivered. The
    -- sweep's own 'unfulfillable:manual_review' marker (a capture that already
    -- carries a transfer — MINOR-4) is an operator item, not sweep work.
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           'review_unfulfillable'::text AS kind, 1 AS priority
      FROM public.webhook_retries w
      JOIN public.payments p ON p.id = w.payment_id
     WHERE w.rpc_name = 'settle_verified_payment'
       AND w.resolved IS NOT TRUE
       AND w.error_message LIKE 'unfulfillable%'
       AND w.error_message <> 'unfulfillable:manual_review'
       AND p.status <> 'refunded'
    UNION ALL
    -- paid_unsettled: the money fact is recorded but the listing is not sold
    -- or the seller has no transfer obligation yet.
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           CASE WHEN p.stripe_livemode IS NULL THEN 'legacy_unknown_mode' ELSE 'paid_unsettled' END::text,
           CASE WHEN p.stripe_livemode IS NULL THEN 4 ELSE 2 END
      FROM public.payments p
      JOIN public.listings l ON l.id = p.listing_id
     WHERE p.status = 'succeeded'
       AND p.mode IN ('buy_now','auction')   -- external rail only (093 native rows excluded)
       AND coalesce(p.paid_at, p.created_at) < now() - interval '5 minutes'
       AND p.stripe_payment_intent_id IS NOT NULL
       AND (l.status <> 'sold' OR NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id = p.id))
    UNION ALL
    -- pending_stale: a late capture whose success event may have been missed.
    -- Window 15 min .. 2 h: the cron runs every 2 minutes (034), so a wider
    -- window turns every abandoned checkout into hundreds of Stripe GETs
    -- (MINOR-5); card captures land within seconds and the webhook and
    -- confirm-payment remain the primary paths.
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           CASE WHEN p.stripe_livemode IS NULL THEN 'legacy_unknown_mode' ELSE 'pending_stale' END::text,
           CASE WHEN p.stripe_livemode IS NULL THEN 4 ELSE 3 END
      FROM public.payments p
     WHERE p.status = 'pending'
       AND p.listing_id IS NOT NULL AND p.mode IN ('buy_now','auction')   -- external rail only
       AND p.stripe_payment_intent_id IS NOT NULL
       AND p.created_at < now() - interval '15 minutes'
       AND p.created_at > now() - interval '2 hours'
  ),
  -- legacy_unknown_mode (priority 4): stripe_livemode IS NULL — a pre-045 row
  -- the live key cannot address (404 on every run). Phase 0 only counts these;
  -- it never calls Stripe for them. Test-mode rows (= false) are dropped —
  -- EXCEPT under the sandbox-only switch app.allow_test_mode_money = 'on'
  -- (set with ALTER DATABASE on an isolated test project so a Stripe test key
  -- can exercise the money rails end to end; production never sets it, and
  -- even if it did, a live key cannot move a test-mode charge).
  deduped AS (
    SELECT DISTINCT ON (c.id) c.*
      FROM candidates c
     WHERE current_setting('app.allow_test_mode_money', true) = 'on'
        OR NOT EXISTS (SELECT 1 FROM public.payments x WHERE x.id = c.id AND x.stripe_livemode = false)
     ORDER BY c.id, c.priority
  )
  SELECT d.id, d.stripe_payment_intent_id, d.listing_id, d.mode, d.status, d.paid_at, d.kind
    FROM deduped d
   ORDER BY d.priority, coalesce(d.paid_at, d.created_at), d.id
   LIMIT greatest(coalesce(p_limit, 50), 1)
$function$;

comment on function public.get_unsettled_payments(integer) is
  'Package 2 reconciliation work list (service_role only): review_unfulfillable (unresolved unfulfillable review rows, minus the unfulfillable:manual_review operator marker), paid_unsettled (succeeded > 5 min, listing not sold or no transfer), pending_stale (pending 15 min .. 2 h with a PaymentIntent), legacy_unknown_mode (either of the last two with stripe_livemode NULL — count only, never fetched). Test-mode rows (stripe_livemode = false) are excluded — the live key cannot see them. One row per payment, highest priority kind wins, oldest first.';

commit;
