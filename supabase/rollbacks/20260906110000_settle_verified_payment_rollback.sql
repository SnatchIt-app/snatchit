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
--   select md5(prosrc) from pg_proc where oid = 'public.cleanup_expired_reservations()'::regprocedure;
--     -- must equal the md5 of the 000 body on a fresh replay stopped at 092
--   supabase/tests/121_settlement.sql must FAIL (functions missing); every
--   other file is unchanged.
-- ============================================================================

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
