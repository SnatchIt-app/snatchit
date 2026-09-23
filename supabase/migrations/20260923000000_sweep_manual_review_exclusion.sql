-- =============================================================================
-- 20260923000000_sweep_manual_review_exclusion.sql  (registry number 147 — versioned by
-- TIMESTAMP because it redefines public.get_unsettled_payments, last defined by
-- 20260916000000; a numbered file would sort BEFORE it under LC_ALL=C and a fresh
-- replay would silently overwrite this body. The timestamp sorts last in every order.)
--
-- INCIDENT 2026-09-23 (production, deploy 4 of the refund/payout safety release):
-- enforce-transfer-expiry v40's Phase 0 selected the same live payment on every
-- 2-minute run. The paid_unsettled branch admits any succeeded external-rail
-- payment whose listing is not 'sold' — regardless of an existing transfer — and
-- settle_verified_payment, finding a transfer already in place, declined to settle
-- and INSERTED a fresh 'unfulfillable…' review row, which the edge then parked as
-- 'unfulfillable:manual_review' (and paged Sentry) — once per run, unbounded.
-- Only the review_unfulfillable branch excluded the marker; nothing consulted it
-- for the branch that kept re-selecting the payment. The marker's documented
-- disposition ("an operator item, not sweep work") was not implemented by the
-- selection.
--
-- FIX (selection only): a payment carrying an UNRESOLVED
-- 'unfulfillable:manual_review' marker is excluded from the work list by EVERY
-- branch — the exclusion lives in the deduped CTE, after the branch union, so no
-- branch can bypass it. ELIGIBLE AGAIN: when an operator resolves the marker
-- (webhook_retries.resolved = true) the payment is selected on the next run if it
-- still meets a branch; reviewed work is never stranded permanently, and it is
-- never re-selected while under review. A RESOLVED marker excludes nothing.
-- Every other predicate, the return signature, grants (service_role EXECUTE
-- only), census and expected_grants are unchanged. Rollback restores the
-- 20260916000000 body verbatim (md5-proven).
-- Verification: supabase/tests/214_sweep_manual_review_exclusion.sql
-- Rollback:     supabase/rollbacks/20260923000000_sweep_manual_review_exclusion_rollback.sql
-- =============================================================================
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
    UNION ALL
    -- processing_stale (134): a LIVE attempt Stripe has already moved on from —
    -- the buyer confirmed, the intent went to `processing`, then fell back to
    -- requires_payment_method (or was canceled) and the payment_failed event
    -- never landed. 132's edge refuses every further checkout by THAT buyer on
    -- the listing while such a row lives, and nothing swept it. Window 15 min
    -- .. 7 days (card processing is seconds; such rows are rare, so the extra
    -- Stripe GETs are negligible). Phase 0 retrieves the intent: succeeded ->
    -- the settle path; requires_payment_method / canceled -> the row is failed
    -- exactly the way stripe-webhook fails it (guarded on pending|processing)
    -- and the 127 hold release runs; anything else is left untouched.
    SELECT p.id, p.stripe_payment_intent_id, p.listing_id, p.mode, p.status, p.paid_at, p.created_at,
           CASE WHEN p.stripe_livemode IS NULL THEN 'legacy_unknown_mode' ELSE 'processing_stale' END::text,
           CASE WHEN p.stripe_livemode IS NULL THEN 4 ELSE 3 END
      FROM public.payments p
     WHERE p.status = 'processing'
       AND p.listing_id IS NOT NULL AND p.mode IN ('buy_now','auction')   -- external rail only
       AND p.stripe_payment_intent_id IS NOT NULL
       AND p.created_at < now() - interval '15 minutes'
       AND p.created_at > now() - interval '7 days'
  ),
  -- legacy_unknown_mode (priority 4): stripe_livemode IS NULL — a pre-045 row
  -- the live key cannot address (404 on every run). Phase 0 only counts these;
  -- it never calls Stripe for them. Test-mode rows (= false) are dropped —
  -- EXCEPT under the sandbox-only switch app.allow_test_mode_money = 'on'
  -- (set with ALTER DATABASE on an isolated test project so a Stripe test key
  -- can exercise the money rails end to end; production never sets it, and
  -- even if it did, a live key cannot move a test-mode charge).
  -- 147 (incident 2026-09-23): a payment under manual review — an UNRESOLVED
  -- 'unfulfillable:manual_review' marker — is excluded here, AFTER the branch
  -- union, so no branch can re-select it while an operator holds it. Resolving
  -- the marker (resolved = true) makes the payment eligible again on the next
  -- run; a resolved marker excludes nothing.
  deduped AS (
    SELECT DISTINCT ON (c.id) c.*
      FROM candidates c
     WHERE (current_setting('app.allow_test_mode_money', true) = 'on'
            OR NOT EXISTS (SELECT 1 FROM public.payments x WHERE x.id = c.id AND x.stripe_livemode = false))
       AND NOT EXISTS (SELECT 1 FROM public.webhook_retries m
                        WHERE m.payment_id = c.id
                          AND m.rpc_name = 'settle_verified_payment'
                          AND m.resolved IS NOT TRUE
                          AND m.error_message = 'unfulfillable:manual_review')
     ORDER BY c.id, c.priority
  )
  SELECT d.id, d.stripe_payment_intent_id, d.listing_id, d.mode, d.status, d.paid_at, d.kind
    FROM deduped d
   ORDER BY d.priority, coalesce(d.paid_at, d.created_at), d.id
   LIMIT greatest(coalesce(p_limit, 50), 1)
$function$;

comment on function public.get_unsettled_payments(integer) is
  'Phase 0 work list for enforce-transfer-expiry: review_unfulfillable (1), paid_unsettled (2), pending_stale and processing_stale (3), legacy_unknown_mode (4). 134 added processing_stale: a processing row 15 min .. 7 days old whose intent may have failed/canceled without the webhook landing. 147: a payment with an unresolved unfulfillable:manual_review marker is excluded from every branch until an operator resolves the marker. service_role only.';

commit;
