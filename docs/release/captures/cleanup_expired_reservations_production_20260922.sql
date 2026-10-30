-- Captured from production hqycwntpfoztoinemqns on 2026-09-22 (A, owner-authorised read): pg_get_functiondef output.
-- md5(pg_get_functiondef) = ecc0afc0cfc3b4521ed8cbe87cad93e8 ; md5(prosrc) = 113cebf6671591c540cf2e54fa45ca0b ; owner postgres ; SECURITY DEFINER ; search_path=public ; volatile.
CREATE OR REPLACE FUNCTION public.cleanup_expired_reservations()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM set_config('app.bypass_listing_guard', 'on', true);
  UPDATE public.listings
     SET status         = 'active',
         reserved_by    = NULL,
         reserved_until = NULL
   WHERE status = 'reserved'
     AND reserved_until <= now();
END;
$function$;
