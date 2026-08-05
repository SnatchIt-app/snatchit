-- Rollback for 057. Drops the producers first (058 depends on the helper).
BEGIN;
DROP TRIGGER IF EXISTS trg_notify_bid_inbox ON public.bids;
DROP TRIGGER IF EXISTS trg_notify_auction_won_inbox ON public.listings;
DROP TRIGGER IF EXISTS trg_notify_transfer_created_inbox ON public.transfers;
DROP TRIGGER IF EXISTS trg_notify_transfer_state_inbox ON public.transfers;
DROP FUNCTION IF EXISTS public.notify_bid_inbox();
DROP FUNCTION IF EXISTS public.notify_auction_won_inbox();
DROP FUNCTION IF EXISTS public.notify_transfer_created_inbox();
DROP FUNCTION IF EXISTS public.notify_transfer_state_inbox();
DROP FUNCTION IF EXISTS public.enqueue_notification(uuid,text,text,text,text,text,jsonb);
DROP INDEX IF EXISTS public.notifications_dedupe_key_uidx;
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_dedupe_key_check;
ALTER TABLE public.notifications DROP COLUMN IF EXISTS dedupe_key;
COMMIT;
