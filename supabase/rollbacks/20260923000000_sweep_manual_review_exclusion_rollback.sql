-- ROLLBACK for 20260923000000_sweep_manual_review_exclusion.sql (registry 147) — restores
-- public.get_unsettled_payments EXACTLY as 20260916000000 (registry 134) defines it: the function text below is
-- extracted verbatim from that migration file (not retyped), and the comment is its comment.
-- CHECK BOTH HASHES after running: md5(pg_get_functiondef) must equal 8052e26987f522886af400137f32b876 (production's
-- value after the 24-file apply, read 2026-09-23 03:06:38Z) and md5(prosrc) must equal
-- 37b86cc4a62bdf5d80bbc9a7d7538042 — prosrc alone is blind to SECURITY DEFINER / search_path.
-- Restoring this body re-opens the re-selection loop for any payment under manual review (incident 2026-09-23);
-- only run it with the production listing/marker state understood.
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
  'Phase 0 work list for enforce-transfer-expiry: review_unfulfillable (1), paid_unsettled (2), pending_stale and processing_stale (3), legacy_unknown_mode (4). 134 added processing_stale: a processing row 15 min .. 7 days old whose intent may have failed/canceled without the webhook landing. service_role only.';

do $chk$
declare v_def text; v_src text;
begin
  select md5(pg_get_functiondef(p.oid)), md5(p.prosrc) into v_def, v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'get_unsettled_payments';
  if v_def <> '8052e26987f522886af400137f32b876' or v_src <> '37b86cc4a62bdf5d80bbc9a7d7538042' then
    raise exception 'rollback 20260923000000: restored get_unsettled_payments hashes % / % do not match the 20260916000000 tip (8052e269… / 37b86cc4…)', v_def, v_src;
  end if;
end $chk$;

commit;
