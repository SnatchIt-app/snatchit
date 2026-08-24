-- Migration 066a: vendor two production functions created out-of-band (Gate-2 reproducibility)
--
-- sync_listing_current_bid() (a SECURITY DEFINER trigger fn) and is_winner(uuid,uuid) exist in
-- PRODUCTION but were never captured in any migration. On a fresh bootstrap this breaks migration
-- 067, which REVOKEs EXECUTE on sync_listing_current_bid() — 067 runs as one implicit transaction,
-- so the missing function made ALL of 067's hardening roll back. Definitions captured verbatim from
-- production pg_get_functiondef on 2026-08-24. Placed before 067 (066 < 066a < 067) so 067 applies.
-- CREATE OR REPLACE => no-op on production; creates them on a fresh/staging DB.

CREATE OR REPLACE FUNCTION public.sync_listing_current_bid()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE public.listings
     SET current_bid = GREATEST(COALESCE(current_bid, 0), NEW.amount),
         updated_at = now()
   WHERE id = NEW.listing_id;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_winner(p_listing_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.listings
     WHERE id             = p_listing_id
       AND auction_status = 'ended'
       AND winner_user_id = p_user_id
  );
$function$;

-- Production also carries this trigger (AFTER INSERT on bids) using the function above,
-- created out-of-band with no migration. Vendored here for reproduction. Idempotent.
DROP TRIGGER IF EXISTS trg_sync_listing_current_bid ON public.bids;
CREATE TRIGGER trg_sync_listing_current_bid
  AFTER INSERT ON public.bids
  FOR EACH ROW EXECUTE FUNCTION public.sync_listing_current_bid();
