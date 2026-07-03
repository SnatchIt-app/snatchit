-- =============================================================================
-- 035_bid_notifications.sql
-- Seller push notification on every new bid (fire-and-forget, same pg_net +
-- Vault pattern as 033/034). One trigger fire per bid insert = one push per
-- valid bid; validate_and_apply_bid already rejects invalid/self bids, and the
-- edge function additionally skips bidder == seller. No payment logic touched.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.notify_bid_placed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_key text;
BEGIN
  BEGIN
    SELECT decrypted_secret INTO v_key
      FROM vault.decrypted_secrets
     WHERE name = 'service_role_key'
     ORDER BY created_at DESC
     LIMIT 1;

    IF v_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://hqycwntpfoztoinemqns.supabase.co/functions/v1/notify-transfer',
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || v_key,
          'Content-Type',  'application/json'
        ),
        body    := jsonb_build_object(
          'event',      'bid_placed',
          'bid_id',     NEW.id,
          'listing_id', NEW.listing_id,
          'bidder_id',  NEW.bidder_id,
          'amount',     NEW.amount
        )
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never block a bid because a notification failed.
    RAISE WARNING 'notify_bid_placed: notification failed: %', SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_bid_placed ON public.bids;
CREATE TRIGGER trg_notify_bid_placed
  AFTER INSERT ON public.bids
  FOR EACH ROW EXECUTE FUNCTION public.notify_bid_placed();

COMMIT;
