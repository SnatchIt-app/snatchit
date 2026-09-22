-- ============================================================================
-- ROLLBACK for 20260906110000_settle_verified_payment.sql
--
-- Drops the two Package 2 functions and restores cleanup_expired_reservations
-- exactly as migration 000_baseline_schema.sql defined it (text copied
-- verbatim from that file — not retyped). Grants on cleanup_expired_
-- reservations are unchanged by the forward migration and by this rollback
-- (063/067 posture: service_role only).
--
-- WARNING: run this ONLY after rolling the Package 2 edge functions back
-- (stripe-webhook, confirm-payment, enforce-transfer-expiry). With the edges
-- deployed, every payment_intent.succeeded delivery would 500 on the missing
-- RPC and confirm-payment would 500 for every buyer. It also re-opens
-- investigation F02/F05/F06 and the "cleanup re-lists a paid listing" path.
-- Prefer fixing forward.
--
-- Verification after rollback:
--   select proname from pg_proc where pronamespace='public'::regnamespace
--     and proname in ('settle_verified_payment','get_unsettled_payments');
--     -- expect 0 rows
--   select md5(prosrc), md5(pg_get_functiondef(oid)) from pg_proc where oid = 'public.cleanup_expired_reservations()'::regprocedure;
--     -- must equal the 000 body's values (a fresh replay of the repo chain gives them; pg_get_functiondef md5
--     -- 95c21a0eb07946e6663a13885cb959b6). This rollback restores the REPO body everywhere, by design.
--     -- NOTE (production, 2026-09-22 — manifest §3a): before this migration production carried the SAME statements
--     -- with uppercase keywords (pg_get_functiondef md5 ecc0afc0cfc3b4521ed8cbe87cad93e8, prosrc md5
--     -- 113cebf6671591c540cf2e54fa45ca0b; capture: docs/release/captures/cleanup_expired_reservations_production_20260922.sql).
--     -- After this rollback on production the function is therefore semantically identical to its pre-apply body
--     -- but hashes as the repo body, not the capture. That is pre-existing casing drift, not something this
--     -- rollback creates; a byte-exact restoration on production is an OPTIONAL manifest-only step, never this file.
--   supabase/tests/121_settlement.sql must FAIL (functions missing); every
--   other file is unchanged.
-- ============================================================================

BEGIN;

-- ── Pre-rollback gates (R5 D-detectors). Rollback is data-safe only while every
-- detector is zero; otherwise old code re-interprets new-code facts (full-net
-- payout on a partially refunded order, re-POST of an in-flight payout, ...).
-- An operator may override ONLY with a ticketed decision:
--   SELECT set_config('app.rollback_force', 'on', true);
DO $gate$
DECLARE v_bad text := '';
BEGIN
  IF current_setting('app.rollback_force', true) = 'on' THEN
    RAISE WARNING 'rollback 20260906110000: gates OVERRIDDEN by app.rollback_force (ticketed operator decision expected)';
    RETURN;
  END IF;
  IF (SELECT count(*) FROM public.webhook_retries WHERE resolved IS NOT TRUE AND rpc_name = 'settle_verified_payment' AND error_message LIKE 'unfulfillable:%') > 0 THEN v_bad := v_bad || ' D3=' || (SELECT count(*) FROM public.webhook_retries WHERE resolved IS NOT TRUE AND rpc_name = 'settle_verified_payment' AND error_message LIKE 'unfulfillable:%')::text || ' [unfulfillable captures not yet refunded - no old-code refunder]'; END IF;
  IF (SELECT count(*) FROM public.payments p JOIN public.listings l ON l.id = p.listing_id WHERE p.status = 'succeeded' AND p.mode IN ('buy_now','auction') AND l.status <> 'sold' AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id = p.id)) > 0 THEN v_bad := v_bad || ' D4=' || (SELECT count(*) FROM public.payments p JOIN public.listings l ON l.id = p.listing_id WHERE p.status = 'succeeded' AND p.mode IN ('buy_now','auction') AND l.status <> 'sold' AND NOT EXISTS (SELECT 1 FROM public.transfers t WHERE t.payment_id = p.id))::text || ' [paid-but-unsettled captures - drain the sweep first, the 000 cleanup would re-list them]'; END IF;

  IF v_bad <> '' THEN
    RAISE EXCEPTION 'rollback 20260906110000 REFUSED - unsafe state present:% (settle each, or set app.rollback_force=on with a ticket)', v_bad;
  END IF;
END $gate$;

DROP FUNCTION IF EXISTS public.settle_verified_payment(text, text, integer, text, boolean, integer, text, text, jsonb, text);
DROP FUNCTION IF EXISTS public.get_unsettled_payments(integer);

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
     and reserved_until <= now();
end;
$$;

REVOKE EXECUTE ON FUNCTION public.cleanup_expired_reservations() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.cleanup_expired_reservations() TO service_role;

COMMIT;
